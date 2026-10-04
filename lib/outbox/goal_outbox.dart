import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/goal.dart';
import '../services/goals_repository.dart';
import '../services/mcp_client.dart';
import 'outbox_store.dart';
import 'pending_goal_save.dart';
import 'save_error.dart';

/// What happened to a goal save: see [GoalOutbox.events].
sealed class GoalSaveEvent {
  const GoalSaveEvent();
}

/// [save] reached the server. For a new goal, [createdId] is the id the
/// server gave it, if it said.
class GoalSaved extends GoalSaveEvent {
  const GoalSaved(this.save, this.createdId);
  final PendingGoalSave save;
  final String? createdId;
}

/// [save] failed, as its [PendingGoalSave.error] says. It's kept, and
/// isn't sent again until it's retried.
class GoalSaveFailed extends GoalSaveEvent {
  const GoalSaveFailed(this.save);
  final PendingGoalSave save;
}

/// Everything waiting has been sent, and answered: the goals can be
/// fetched again, once, to show them as the server has them.
class GoalSavesDone extends GoalSaveEvent {
  const GoalSavesDone();
}

/// Goal saves waiting to be sent to the server, or that failed. Saves land
/// here first (and in [OutboxStore], so they survive the app closing),
/// then are sent one at a time, oldest first. One that fails is kept, with
/// why, until it's retried, edited or discarded.
///
/// A save to a goal that already has one waiting, or that failed, joins
/// it, so they're sent as one. Call [start] to have it send while the app
/// is in use, and [stop] when the app goes to the background.
class GoalOutbox extends ChangeNotifier {
  GoalOutbox({
    required this._store,
    required this._repository,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final OutboxStore<PendingGoalSave> _store;
  final GoalsRepository _repository;
  final DateTime Function() _clock;

  /// Gives up on a single request after this long. It may still reach the
  /// server, which the next attempt checks for.
  static const requestTimeout = Duration(seconds: 30);

  /// Gives up on reading or writing the [OutboxStore] after this long.
  static const storeTimeout = Duration(seconds: 10);

  List<PendingGoalSave> _saves = [];
  String? _sendingId;
  bool _running = false;
  bool _flushing = false;
  bool _loaded = false;
  int _nextId = 0;
  Future<void> _lock = Future.value();
  final _events = StreamController<GoalSaveEvent>.broadcast();

  /// Every save waiting, being sent, or that failed, oldest first.
  List<PendingGoalSave> get saves => List.unmodifiable(_saves);

  /// What happens to each save, as it happens.
  Stream<GoalSaveEvent> get events => _events.stream;

  /// Whether anything is waiting to be sent, or being sent. Saves that
  /// failed wait to be retried, so they don't count.
  bool get busy => _saves.any((s) => s.error == null);

  /// Whether [save] is being sent right now: it can't be changed then.
  bool isSending(PendingGoalSave save) => save.id == _sendingId;

  /// Reads what was kept from last time, if it hasn't yet, and starts
  /// sending. Saves that failed without an answer (no connection, say) are
  /// tried again; ones the server refused wait to be retried.
  Future<void> start() async {
    _running = true;
    if (!_loaded) {
      _loaded = true;
      try {
        final kept = await _store.load().timeout(storeTimeout);
        _saves = [...kept, ..._saves];
      } catch (e, stack) {
        debugPrint("Couldn't read the goal saves kept: $e\n$stack");
      }
    }
    _saves = [
      for (final save in _saves)
        save.error != null && save.uncertain
            ? save.copyWith(error: () => null)
            : save,
    ];
    notifyListeners();
    unawaited(_flush());
  }

  /// Stops sending more. A request already in flight still finishes.
  void stop() => _running = false;

  /// Saves a goal made from [fields], keyed as `create_goal` takes them.
  /// Returns the id it's shown with until the server makes it.
  String create(Map<String, Object?> fields) {
    final goalId = 'unsaved-${_newId()}';
    _saves = [
      ..._saves,
      PendingGoalSave(
        id: _newId(),
        goalId: goalId,
        isNew: true,
        changes: fields,
      ),
    ];
    _changed();
    return goalId;
  }

  /// Saves [changes], keyed as `update_goal` takes them, to the goal with
  /// [goalId]. If it has a save waiting, or that failed, these join it,
  /// and it's sent (again) with all of them; with [replace], these stand
  /// in for its changes instead, as when what failed is edited. That's
  /// also how a new goal that failed is changed before trying again.
  void update(
    String goalId,
    Map<String, Object?> changes, {
    bool replace = false,
  }) {
    final i = _saves.lastIndexWhere(
      (s) => s.goalId == goalId && s.id != _sendingId,
    );
    if (i < 0) {
      _saves = [
        ..._saves,
        PendingGoalSave(
          id: _newId(),
          goalId: goalId,
          isNew: false,
          changes: changes,
        ),
      ];
    } else {
      final save = _saves[i];
      _saves = [
        for (final (j, s) in _saves.indexed)
          j == i
              ? save.copyWith(
                  changes: replace ? changes : {...save.changes, ...changes},
                  error: () => null,
                )
              : s,
      ];
    }
    _changed();
  }

  /// Sends the saves that failed for the goal with [goalId] again.
  void retry(String goalId) => _retryWhere((s) => s.goalId == goalId);

  /// Sends every save that failed again: after signing in, say.
  void retryAll() => _retryWhere((_) => true);

  void _retryWhere(bool Function(PendingGoalSave save) test) {
    _saves = [
      for (final save in _saves)
        save.error != null && test(save)
            ? save.copyWith(error: () => null)
            : save,
    ];
    _changed();
  }

  /// Drops the saves waiting, or that failed, for the goal with [goalId],
  /// without sending them. One being sent can't be dropped.
  void discard(String goalId) {
    _saves = [
      for (final save in _saves)
        if (save.goalId != goalId || isSending(save)) save,
    ];
    _changed();
  }

  /// Drops new goals that failed without an answer, if [goals] (from the
  /// server) shows they were made after all.
  void reconcile(GoalList goals) {
    final before = _saves.length;
    _saves = [
      for (final save in _saves)
        if (!(save.isNew &&
            save.uncertain &&
            save.error != null &&
            save.madeIn(goals)))
          save,
    ];
    if (_saves.length != before) _changed();
  }

  @override
  void dispose() {
    stop();
    _events.close();
    super.dispose();
  }

  String _newId() =>
      '${_clock().microsecondsSinceEpoch.toRadixString(36)}-${_nextId++}';

  /// Keeps the saves, tells listeners, and sends what's waiting.
  void _changed() {
    unawaited(_persist());
    notifyListeners();
    unawaited(_flush());
  }

  /// Sends what's waiting, one at a time, oldest first, while running.
  Future<void> _flush() async {
    if (_flushing || !_running) return;
    _flushing = true;
    var sent = false;
    try {
      while (_running) {
        final next = _saves.where((s) => s.error == null).firstOrNull;
        if (next == null) break;
        sent = true;
        await _send(next);
      }
    } finally {
      _flushing = false;
    }
    if (sent && !busy && !_events.isClosed) {
      _events.add(const GoalSavesDone());
    }
  }

  Future<void> _send(PendingGoalSave save) async {
    _sendingId = save.id;
    // Marked first, so if the app closes mid-request, the next attempt
    // checks whether it was made.
    final attempt = save.copyWith(uncertain: true);
    _replace(save, attempt);
    await _persist();
    notifyListeners();
    try {
      String? created;
      if (save.isNew) {
        if (save.uncertain) {
          final goals = await _repository.goals().timeout(requestTimeout);
          if (save.madeIn(goals)) {
            created = goals.goals
                .firstWhere(
                  (g) =>
                      g.parentId == save.changes['parent_id'] &&
                      g.name == save.changes['name'],
                )
                .id;
          }
        }
        created ??= await _repository
            .createGoal(save.changes)
            .timeout(requestTimeout);
      } else {
        await _repository
            .updateGoal(Goal(id: save.goalId), save.changes)
            .timeout(requestTimeout);
      }
      _sendingId = null;
      // Anything added to it meanwhile went into a save of its own.
      _saves = [
        for (final s in _saves)
          if (s.id != save.id) s,
      ];
      unawaited(_persist());
      notifyListeners();
      if (!_events.isClosed) _events.add(GoalSaved(attempt, created));
    } catch (e) {
      _sendingId = null;
      final failed = attempt.copyWith(
        error: () => describeSaveError(e),
        // The server answered, saying no: it wasn't saved.
        uncertain: !(e is McpException || e is SignInRequiredException),
      );
      _replace(attempt, failed);
      unawaited(_persist());
      notifyListeners();
      if (!_events.isClosed) _events.add(GoalSaveFailed(failed));
    }
  }

  /// Puts [to] in [from]'s place, if it's still there.
  void _replace(PendingGoalSave from, PendingGoalSave to) {
    _saves = [for (final s in _saves) s.id == from.id ? to : s];
  }

  /// Writes the saves to the store, after any write before. A store that
  /// fails only loses them if the app closes.
  Future<void> _persist() {
    final saves = List.of(_saves);
    return _lock = _lock.then(
      (_) => _store.save(saves).timeout(storeTimeout).catchError((
        Object e,
        StackTrace stack,
      ) {
        debugPrint("Couldn't keep the goal saves: $e\n$stack");
      }),
    );
  }
}
