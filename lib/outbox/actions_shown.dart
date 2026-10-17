import '../models/plan_action.dart';
import 'action_writes.dart';
import 'pending_write.dart';

/// [actions] as they're to be shown: with the writes [writes] has made
/// since they were fetched, then those it's still to make, or that failed,
/// made to them -- on every page alike, as soon as each is made.
ActionList actionsShown(ActionList actions, ActionWrites writes) {
  final all = [...writes.justSaved, ...writes.saves];
  if (all.isEmpty) return actions;
  var list = [...actions.actions];
  for (final save in all) {
    final at = list.indexWhere((a) => a.id == save.actionId);
    switch (save.write.op) {
      case WriteOp.create when at < 0:
        list.add(
          PlanAction.fromJson({
            'status': 'active',
            ...save.changes,
            'id': save.actionId,
          }),
        );
      case WriteOp.create || WriteOp.update when at >= 0:
        list[at] = PlanAction.fromJson({...list[at].toJson(), ...save.changes});
      case WriteOp.delete when at >= 0:
        list.removeAt(at);
      case _:
    }
  }
  return _inTree(actions, list);
}

/// [actions] in place of [list]'s, parents first, each action's sub-actions
/// after it in the order given, and each path made again from its
/// ancestors' names, and the priority each inherits from them.
ActionList _inTree(ActionList list, List<PlanAction> actions) {
  final ids = {for (final action in actions) action.id};
  final children = <String?, List<PlanAction>>{};
  for (final action in actions) {
    final parent = ids.contains(action.parentId) ? action.parentId : null;
    children.putIfAbsent(parent, () => []).add(action);
  }
  final ordered = <PlanAction>[];
  void visit(PlanAction action, PlanAction? parent, String? parentPath) {
    final path = switch ((parentPath, action.parentId)) {
      (final parent?, _) => '$parent › ${actionName(action)}',
      (null, null) => actionName(action),
      // Under an action that isn't listed: only its own name can be redone.
      _ => switch (action.path?.lastIndexOf(' › ')) {
        final end? when end >= 0 =>
          '${action.path!.substring(0, end)} › ${actionName(action)}',
        _ => actionName(action),
      },
    };
    // Under an action that isn't listed, what it inherits is as it was.
    final priority =
        action.priority ??
        (parent != null
            ? parent.effectivePriority
            : action.parentId == null
            ? null
            : action.effectivePriority);
    final shown = path == action.path && priority == action.effectivePriority
        ? action
        : PlanAction.fromJson({
            ...action.toJson(),
            'path': path,
            'effective_priority': priority,
          });
    ordered.add(shown);
    for (final child in children[action.id] ?? const <PlanAction>[]) {
      visit(child, shown, path);
    }
  }

  children[null]?.forEach((action) => visit(action, null, null));
  return ActionList(
    actions: ordered,
    labelSlotsUsed: list.labelSlotsUsed,
    labelSlotsTotal: list.labelSlotsTotal,
  );
}
