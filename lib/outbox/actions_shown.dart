import '../models/plan_action.dart';
import 'action_outbox.dart';
import 'pending_action_save.dart';

/// [actions] as they're to be shown: with the saves [outbox] has made since
/// they were fetched, then those it's still to make, or that failed, made
/// to them -- on every page alike, as soon as each is made.
ActionList actionsShown(ActionList actions, ActionOutbox outbox) =>
    _withSaves(_withSaved(actions, outbox.justSaved), outbox.saves);

/// [actions] with [saved], saves the server has answered, made to them, as
/// far as they don't have them yet: each new action added, with the id the
/// server gave it if that's known, and each action's changes made.
ActionList _withSaved(
  ActionList actions,
  List<({PendingActionSave item, String? result})> saved,
) {
  var shown = actions;
  for (final (:item, :result) in saved) {
    if (!item.isNew) {
      shown = _withChanged(shown, item.actionId, item.changes);
    } else if (item.madeIn(shown) == null &&
        !shown.actions.any((g) => result != null && g.id == result)) {
      shown = _inTree(shown, [
        ...shown.actions,
        PlanAction.fromJson({
          ...item.action.toJson(),
          'id': result ?? item.actionId,
        }),
      ]);
    }
  }
  return shown;
}

/// [actions] with [saves] made to them, oldest first: each new action added,
/// and each action's changes made.
ActionList _withSaves(ActionList actions, List<PendingActionSave> saves) {
  if (saves.isEmpty) return actions;
  var shown = actions;
  for (final save in saves) {
    shown = save.isNew
        ? _inTree(shown, [...shown.actions, save.action])
        : _withChanged(shown, save.actionId, save.changes);
  }
  return shown;
}

/// [actions] with [changes], keyed as `update_action` takes them, made to the
/// action with [id]: moved, if it's given another parent, and renamed in
/// its sub-actions' paths.
ActionList _withChanged(
  ActionList actions,
  String? id,
  Map<String, Object?> changes,
) => _inTree(actions, [
  for (final action in actions.actions)
    action.id == id
        ? PlanAction.fromJson({...action.toJson(), ...changes})
        : action,
]);

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
