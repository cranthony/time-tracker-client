import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/plan_action.dart';
import '../services/actions_repository.dart';
import '../services/server_errors.dart';
import 'outbox.dart';
import 'pending_action_save.dart';

/// PlanAction saves waiting to be sent to the server, or that failed: an
/// [Outbox] of them, sent oldest first, retrying with backoff. One the
/// server refuses (a name already used, say) waits until it's retried,
/// edited or discarded.
///
/// A save to an action that already has one waiting, or that failed, joins
/// it, so they're sent as one. Call [start] to have it send while the app
/// is in use, and [stop] when the app goes to the background, where the
/// Android background task sends them, as it does notes.
class ActionOutbox extends Outbox<PendingActionSave, String?> {
  ActionOutbox({
    required super.store,
    required this._repository,
    super.clock,
    super.sender,
  });

  final ActionsRepository _repository;
  int _nextId = 0;

  /// Every save waiting, being sent, or that failed, oldest first.
  List<PendingActionSave> get saves => items;

  /// Whether anything is being sent, or waiting to be for the first time.
  /// Saves that failed wait a while, or to be retried, so they don't count.
  bool get busy => saves.any((s) => !s.failed || isSending(s));

  /// Saves an action made from [fields], keyed as `create_action` takes them.
  /// Returns the id it's shown with until the server makes it.
  String create(Map<String, Object?> fields) {
    final save = PendingActionSave(
      id: _newId(),
      actionId: 'unsaved-${_newId()}',
      isNew: true,
      changes: fields,
    );
    _changeAndSend((saves) => [...saves, save]);
    return save.actionId;
  }

  /// Saves [changes], keyed as `update_action` takes them, to the action with
  /// [actionId], which, if [group], is a group. If it has a save waiting, or that failed, these join it,
  /// and it's sent (again) with all of them; with [replace], these stand
  /// in for its changes instead, as when what failed is edited. That's
  /// also how a new action that failed is changed before trying again.
  void update(
    String actionId,
    Map<String, Object?> changes, {
    required bool group,
    bool replace = false,
  }) {
    final added = PendingActionSave(
      id: _newId(),
      actionId: actionId,
      isNew: false,
      changes: changes,
      group: group,
    );
    _changeAndSend((saves) {
      final i = saves.lastIndexWhere(
        (s) => s.actionId == actionId && !isSending(s),
      );
      if (i < 0) return [...saves, added];
      final save = saves[i];
      final joined = save.withChanges(
        replace ? changes : {...save.changes, ...changes},
      );
      return [
        for (final (j, s) in saves.indexed)
          if (j != i)
            s
          // Tried, it may have been made, unheard: sent again as it was,
          // it would be answered as it was then. So it's a new write.
          else if (save.attempts > 0)
            joined.withId(_newId())
          else
            joined,
      ];
    });
  }

  /// Sends the saves that failed for the action with [actionId] again, now.
  void retry(String actionId) => _changeAndSend(
    (saves) => [
      for (final s in saves)
        s.actionId == actionId && s.failed && !isSending(s)
            ? s.copyWith(
                refused: false,
                lastError: () => null,
                nextAttemptAt: () => null,
              )
            : s,
    ],
  );

  /// Drops the saves waiting, or that failed, for the action with [actionId],
  /// without sending them. One being sent can't be dropped.
  void discard(String actionId) => _changeAndSend(
    (saves) => [
      for (final s in saves)
        if (s.actionId != actionId || isSending(s)) s,
    ],
  );

  /// Drops new actions whose requests failed unanswered, if [actions] (from
  /// the server) shows they were made after all. Returns the saves
  /// dropped.
  List<PendingActionSave> reconcile(ActionList actions) {
    bool made(PendingActionSave s) =>
        s.isNew &&
        s.failed &&
        !s.refused &&
        s.attempts > 0 &&
        !isSending(s) &&
        s.madeIn(actions) != null;
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
  Future<String?> send(
    PendingActionSave item, {
    required bool maybeSaved,
  }) async {
    if (!item.isNew) {
      final group = item.group ?? await _isGroup(item.actionId);
      await _repository
          .updateAction(
            PlanAction(
              id: item.actionId,
              properties: {if (group) 'kind': 'group'},
            ),
            item.changes,
          )
          .timeout(Outbox.requestTimeout);
      return null;
    }
    if (maybeSaved) {
      final actions = await _repository.actions().timeout(
        Outbox.requestTimeout,
      );
      if (item.madeIn(actions) case final made?) return made.id;
    }
    return _repository
        .createAction(item.changes)
        .timeout(Outbox.requestTimeout);
  }

  /// Whether the action with [id] is a group, as the server has it: for a
  /// save kept without saying.
  Future<bool> _isGroup(String id) async {
    final actions =
        await _repository.cachedActions() ??
        await _repository.actions().timeout(Outbox.requestTimeout);
    return actions.actions.any((a) => a.id == id && a.isGroup);
  }

  /// The server's refusals wait to be retried; the rest are tried again.
  @override
  bool retries(Object error) =>
      describeServerError(error).kind != FailureKind.refused;

  String _newId() =>
      '${now().microsecondsSinceEpoch.toRadixString(36)}-${_nextId++}';

  /// Applies [change] to the saves, at once, then keeps them and sends
  /// what's due. A store that fails only loses them if the app closes.
  void _changeAndSend(
    List<PendingActionSave> Function(List<PendingActionSave> saves) change,
  ) {
    unawaited(
      this.change(change).then((_) => schedule(immediately: true)).catchError((
        Object e,
        StackTrace stack,
      ) {
        debugPrint("Couldn't keep the action saves: $e\n$stack");
      }),
    );
  }
}
