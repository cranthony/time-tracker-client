import 'package:flutter/foundation.dart';

import '../models/plan_action.dart';
import '../services/actions_repository.dart';
import '../services/mcp_client.dart';
import 'legacy_writes.dart';
import 'outbox.dart';
import 'outbox_store.dart';
import 'write_queue.dart';

/// A write to an action or an action group waiting in the [WriteQueue],
/// or that failed, as the Plan page shows it.
class ActionSave {
  const ActionSave(this.write);

  final PendingWrite write;

  /// The action it's for: for a new one, the id the app gave it.
  String get actionId => write.itemId;

  /// Whether it makes a new action, rather than changing one.
  bool get isNew => write.op == WriteOp.create;

  /// Whether what it's for is a group.
  bool get group => write.kind == WriteKind.actionGroup.name;

  /// For a new action, everything it's made with; else its changes, a
  /// null clearing that property -- keyed as the Plan page edits them.
  Map<String, Object?> get changes => {
    for (final MapEntry(:key, :value) in write.changes.entries)
      (key == 'group_id' ? 'parent_id' : key): value,
    if (isNew && group) 'kind': 'group',
  };

  /// Whether its last attempt failed: it's tried again after a while, or,
  /// if [refused], when it's retried.
  bool get failed => write.lastError != null;
  bool get refused => write.refused;
  String? get lastError => write.lastError;
}

/// The Plan page's writes to actions and their groups, kept and sent by
/// a [WriteQueue] -- the app's, which sends everything else too, so each
/// is made once, in order, and one changed elsewhere since is resolved
/// field by field. Its listeners hear whenever the queue changes.
class ActionWrites implements Listenable {
  ActionWrites(this.queue);

  /// Writes kept in [store] (in memory, unless given) and made to
  /// [repository] itself: with no server, and in tests.
  factory ActionWrites.local(
    ActionsRepository repository, {
    OutboxStore<PendingWrite>? store,
    String sender = Outbox.appSender,
  }) => ActionWrites(
    WriteQueue(
      store: store ?? InMemoryOutboxStore(),
      call: localActionCalls(repository),
      sender: sender,
    ),
  );

  final WriteQueue queue;

  static WriteKind _kind(bool group) =>
      group ? WriteKind.actionGroup : WriteKind.action;

  static bool _its(PendingWrite w) =>
      w.kind == WriteKind.action.name || w.kind == WriteKind.actionGroup.name;

  /// Every write to an action waiting, being sent, or that failed, oldest
  /// first.
  List<ActionSave> get saves => [
    for (final w in queue.items)
      if (_its(w)) ActionSave(w),
  ];

  /// Those saved, till a fetch started after them is in.
  List<ActionSave> get justSaved => [
    for (final s in queue.justSaved)
      if (_its(s.item)) ActionSave(s.item),
  ];

  /// Whether anything is being sent, or waiting to be for the first time.
  /// Saves that failed wait a while, or to be retried, so they don't count.
  bool get busy => queue.items.any(
    (w) => _its(w) && (w.lastError == null || queue.isSending(w)),
  );

  bool isSending(ActionSave save) => queue.isSending(save.write);

  /// What a fetch of the actions brings: them, their groups and the
  /// priorities' colors.
  static const fetchedKinds = [
    WriteKind.action,
    WriteKind.actionGroup,
    WriteKind.priorityColors,
  ];

  /// Whether an action, group or color was saved that no fetch of the
  /// actions has started for since.
  bool get wantsFetch => queue.wantsFetchOfKinds(fetchedKinds);

  /// Call as a fetch of the actions starts; call what it gives once
  /// they're in, and shown ([WriteQueue.fetchingKinds]).
  void Function() fetching() => queue.fetchingKinds(fetchedKinds);
  Future<FlushResult> retryNow() => queue.retryNow();

  /// Makes an action -- or, its kind "group", a group -- from [fields],
  /// keyed as the Plan page edits them. Gives its id, from now on.
  String create(Map<String, Object?> fields) {
    final group = fields['kind'] == 'group';
    final made = actionWriteFields(fields, group: group);
    return queue.create(_kind(group), {
      ...made,
      // Made by the user, so not waiting for their review.
      if (!group) 'status': made['status'] ?? 'active',
    });
  }

  /// Saves [changes], keyed as the Plan page edits them, to the action
  /// [actionId] -- a group, if [group]. With [replace], they stand in for
  /// the changes of its write that failed (a new one's fields, for a new
  /// one), to send again.
  void update(
    String actionId,
    Map<String, Object?> changes, {
    required bool group,
    bool replace = false,
  }) {
    final fields = actionWriteFields(changes, group: group);
    final failed = saves
        .where((s) => s.actionId == actionId && s.failed && !isSending(s))
        .lastOrNull;
    if (replace && failed != null) {
      final write = failed.write;
      _resend(
        write,
        changes: {
          if (write.op == WriteOp.create) ...{
            for (final MapEntry(:key, :value) in fields.entries) key: ?value,
            if (!group) 'status': fields['status'] ?? 'active',
          } else
            ...fields,
        },
      );
      return;
    }
    queue.update(_kind(group), actionId, fields);
  }

  /// Sends the writes that failed for [actionId] again, now.
  void retry(String actionId) {
    for (final s in saves) {
      if (s.actionId == actionId && s.failed) _resend(s.write);
    }
  }

  void _resend(PendingWrite write, {Map<String, Object?>? changes}) =>
      queue.resend(write, changes: changes).catchError((Object e) {
        debugPrint("Couldn't keep the action's write: $e");
        return false;
      });

  /// Drops the writes waiting, or that failed, for [actionId], without
  /// sending them. One being sent can't be dropped.
  void discard(String actionId) {
    for (final s in saves) {
      if (s.actionId == actionId) queue.drop(s.write);
    }
  }

  // As the queue's.
  void start() => queue.start();
  void stop() => queue.stop();
  Future<void> refresh() => queue.refresh();
  Future<FlushResult> flush({bool ignoreBackoff = false}) =>
      queue.flush(ignoreBackoff: ignoreBackoff);
  void dispose() => queue.dispose();

  @override
  void addListener(VoidCallback listener) => queue.addListener(listener);

  @override
  void removeListener(VoidCallback listener) => queue.removeListener(listener);
}

/// Makes the action writes' tool calls to [repository] itself, as the
/// server would: with no server, and in tests.
WriteCall localActionCalls(ActionsRepository repository) =>
    (tool, arguments) async {
      Map<String, Object?> item(String name) =>
          (arguments[name] as Map).cast<String, Object?>();
      Map<String, Object?> planned(Map<String, Object?> fields) => {
        for (final MapEntry(:key, :value) in fields.entries)
          if (key == 'group_id') 'parent_id': value else key: value,
      };
      // Not what it is now, which would need the actions fetched: the
      // Plan page fetches them once every write's made.
      Map<String, Object?> listed(String id) => {
        'changed': const [],
        'created_id': id,
      };

      switch (tool) {
        case 'create_action' || 'create_action_group':
          final group = tool == 'create_action_group';
          final fields = planned(item(group ? 'group' : 'action'));
          final id = await repository.createAction({
            ...fields,
            if (group) 'kind': 'group',
          });
          return listed(id ?? fields['id'] as String);
        case 'update_action' || 'update_action_group':
          final group = tool == 'update_action_group';
          final fields = planned(item(group ? 'group' : 'action'));
          final id = fields.remove('id') as String;
          fields.remove('version');
          await repository.updateAction(
            PlanAction(id: id, properties: {if (group) 'kind': 'group'}),
            {
              ...fields,
              for (final c in arguments['clear_fields'] as List? ?? const [])
                (c == 'group_id' ? 'parent_id' : c as String): null,
            },
          );
          return listed(id);
        case 'update_priority_color':
          await repository.updatePriorityColor(
            arguments['priority'] as int,
            arguments['color'] as String,
          );
          return null;
      }
      throw McpException('No tool $tool here');
    };
