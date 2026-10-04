import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/goal.dart';
import '../services/goals_repository.dart';
import '../services/mcp_client.dart';
import 'outbox.dart';
import 'pending_goal_save.dart';

/// What happened to a goal save: see [GoalOutbox.events]. Saves that
/// went through are in [Outbox.justSaved].
sealed class GoalSaveEvent {
  const GoalSaveEvent();
}

/// [save] failed, as its [PendingGoalSave.lastError] says. It's kept, and
/// tried again after a while, or, if the server refused it, when it's
/// retried.
class GoalSaveFailed extends GoalSaveEvent {
  const GoalSaveFailed(this.save);
  final PendingGoalSave save;
}

/// Goal saves waiting to be sent to the server, or that failed: an
/// [Outbox] of them, sent oldest first, retrying with backoff. One the
/// server refuses (a name already used, say) waits until it's retried,
/// edited or discarded.
///
/// A save to a goal that already has one waiting, or that failed, joins
/// it, so they're sent as one. Call [start] to have it send while the app
/// is in use, and [stop] when the app goes to the background, where the
/// Android background task sends them, as it does notes.
class GoalOutbox extends Outbox<PendingGoalSave, String?> {
  GoalOutbox({required super.store, required this._repository, super.clock});

  final GoalsRepository _repository;
  int _nextId = 0;
  // Synchronous, so a failure is heard of as it's kept.
  final _events = StreamController<GoalSaveEvent>.broadcast(sync: true);

  /// Every save waiting, being sent, or that failed, oldest first.
  List<PendingGoalSave> get saves => items;

  /// What happens to each save, as it happens.
  Stream<GoalSaveEvent> get events => _events.stream;

  /// Whether anything is being sent, or waiting to be for the first time.
  /// Saves that failed wait a while, or to be retried, so they don't count.
  bool get busy => saves.any((s) => !s.failed || isSending(s));

  /// Saves a goal made from [fields], keyed as `create_goal` takes them.
  /// Returns the id it's shown with until the server makes it.
  String create(Map<String, Object?> fields) {
    final save = PendingGoalSave(
      id: _newId(),
      goalId: 'unsaved-${_newId()}',
      isNew: true,
      changes: fields,
    );
    _changeAndSend((saves) => [...saves, save]);
    return save.goalId;
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
    final added = PendingGoalSave(
      id: _newId(),
      goalId: goalId,
      isNew: false,
      changes: changes,
    );
    _changeAndSend((saves) {
      final i = saves.lastIndexWhere(
        (s) => s.goalId == goalId && !isSending(s),
      );
      if (i < 0) return [...saves, added];
      final save = saves[i];
      return [
        for (final (j, s) in saves.indexed)
          j == i
              ? save.withChanges(
                  replace ? changes : {...save.changes, ...changes},
                )
              : s,
      ];
    });
  }

  /// Sends the saves that failed for the goal with [goalId] again, now.
  void retry(String goalId) => _changeAndSend(
    (saves) => [
      for (final s in saves)
        s.goalId == goalId && s.failed && !isSending(s)
            ? s.copyWith(
                refused: false,
                lastError: () => null,
                nextAttemptAt: () => null,
              )
            : s,
    ],
  );

  /// Drops the saves waiting, or that failed, for the goal with [goalId],
  /// without sending them. One being sent can't be dropped.
  void discard(String goalId) => _changeAndSend(
    (saves) => [
      for (final s in saves)
        if (s.goalId != goalId || isSending(s)) s,
    ],
  );

  /// Drops new goals whose requests failed unanswered, if [goals] (from
  /// the server) shows they were made after all. Returns the saves
  /// dropped.
  List<PendingGoalSave> reconcile(GoalList goals) {
    bool made(PendingGoalSave s) =>
        s.isNew &&
        s.failed &&
        !s.refused &&
        s.attempts > 0 &&
        !isSending(s) &&
        s.madeIn(goals) != null;
    final dropped = saves.where(made).toList();
    if (dropped.isEmpty) return dropped;
    _changeAndSend(
      (saves) => [
        for (final s in saves)
          if (!made(s)) s,
      ],
    );
    return dropped;
  }

  @override
  Future<String?> send(PendingGoalSave item, {required bool maybeSaved}) async {
    if (!item.isNew) {
      await _repository
          .updateGoal(Goal(id: item.goalId), item.changes)
          .timeout(Outbox.requestTimeout);
      return null;
    }
    if (maybeSaved) {
      final goals = await _repository.goals().timeout(Outbox.requestTimeout);
      if (item.madeIn(goals) case final made?) return made.id;
    }
    return _repository.createGoal(item.changes).timeout(Outbox.requestTimeout);
  }

  /// The server's refusals wait to be retried; the rest are tried again.
  @override
  bool retries(Object error) => error is! McpException;

  @override
  void failed(PendingGoalSave item) => _emit(GoalSaveFailed(item));

  @override
  void dispose() {
    _events.close();
    super.dispose();
  }

  void _emit(GoalSaveEvent event) {
    if (!_events.isClosed) _events.add(event);
  }

  String _newId() =>
      '${now().microsecondsSinceEpoch.toRadixString(36)}-${_nextId++}';

  /// Applies [change] to the saves, at once, then keeps them and sends
  /// what's due. A store that fails only loses them if the app closes.
  void _changeAndSend(
    List<PendingGoalSave> Function(List<PendingGoalSave> saves) change,
  ) {
    unawaited(
      this.change(change).then((_) => schedule(immediately: true)).catchError((
        Object e,
        StackTrace stack,
      ) {
        debugPrint("Couldn't keep the goal saves: $e\n$stack");
      }),
    );
  }
}
