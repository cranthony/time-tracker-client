import 'package:flutter/material.dart';

import '../models/plan_action.dart';
import 'picker_search.dart';
import 'picker_sheet.dart';
import 'tree_picker.dart';

/// Picks several actions from a long list, as a [TreePicker] does: the
/// picked ones as chips on top, the first marked as the primary action; a
/// search over every action's whole path; and, while the search is empty,
/// the actions as a tree that opens only the branches holding a picked
/// action.
///
/// Lists every active action in [actions] (in tree order, as the server gives
/// them) and any inactive one already [picked], or with [inactive], every
/// action; never those in [exclude]. Calls [onChanged] with the new ids, in
/// the order they were picked, so the first stays the primary action.
///
/// With [single], it picks one action, with no chips: tapping an action (or
/// Enter, for the top match) calls [onChanged] with just that one. With
/// [leavesOnly], groups are shown, to find what's in them, but can't be
/// picked: only actions can be given to an event -- tapping one opens or
/// closes it. With [none], a row by that name, over the list, picks no
/// action, calling [onChanged] with none.
///
/// Its [search] can be given, to start it with words typed, or keep
/// them past it. Long-pressing an action or group calls [onEdit] with it;
/// with [onAdd], a row over the list adds one, given what's typed.
class ActionsPicker extends StatelessWidget {
  const ActionsPicker({
    super.key,
    required this.actions,
    required this.picked,
    required this.onChanged,
    required this.marker,
    this.single = false,
    this.inactive = false,
    this.exclude = const {},
    this.leavesOnly = false,
    this.autofocus = false,
    this.maxListHeight = 320,
    this.none,
    this.search,
    this.onEdit,
    this.onAdd,
  });

  final List<PlanAction> actions;
  final List<String> picked;
  final ValueChanged<List<String>> onChanged;
  final bool single;
  final bool inactive;
  final Set<String> exclude;
  final bool leavesOnly;
  final String? none;

  /// Whether the search takes the keyboard at once, what's typed in it
  /// selected.
  final bool autofocus;

  final PickerSearch? search;
  final ValueChanged<PlanAction>? onEdit;
  final ValueChanged<String>? onAdd;

  /// Drawn before each action's name, e.g. a dot in its color.
  final Widget Function(PlanAction action) marker;

  /// How tall the list of actions grows before it scrolls; null, to fill
  /// what room there is.
  final double? maxListHeight;

  List<PlanAction> get _shown => [
    for (final action in actions)
      if (action.id != null &&
          !exclude.contains(action.id) &&
          (inactive || action.active || picked.contains(action.id)))
        action,
  ];

  @override
  Widget build(BuildContext context) {
    final shown = _shown;
    if (shown.isEmpty && onAdd == null) return const Text('No active actions.');
    final byId = {for (final action in shown) action.id!: action};
    return TreePicker(
      nodes: [for (final action in shown) actionNode(action)],
      picked: picked,
      onChanged: onChanged,
      single: single,
      groupsPickable: !leavesOnly,
      none: none,
      search: search,
      autofocus: autofocus,
      searchHint: 'Search actions',
      empty: 'No active actions.',
      noMatches: 'No actions match.',
      maxListHeight: maxListHeight,
      marker: (node) => switch (byId[node.id]) {
        final action? => marker(action),
        null => const SizedBox.shrink(),
      },
      chipAvatar: (i, node) => i == 0
          ? const Tooltip(
              message: 'Primary action',
              child: Icon(Icons.star, size: 18),
            )
          : switch (byId[node?.id]) {
              final action? => marker(action),
              null => null,
            },
      onEdit: switch (onEdit) {
        final edit? => (node) => edit(byId[node.id]!),
        null => null,
      },
      add: switch (onAdd) {
        final add? => (noun: 'action', icon: Icons.add, onAdd: add),
        null => null,
      },
    );
  }
}

/// [action] as a [TreePicker] shows it: by its name, in its group.
PickerNode actionNode(PlanAction action) => PickerNode(
  id: action.id!,
  label: actionName(action),
  parentId: action.parentId,
  path: action.path,
  group: action.isGroup,
  faded: !action.active,
);

/// [id] and every action under it in [actions]: what can't be its parent.
Set<String> actionAndSubActions(List<PlanAction> actions, String id) {
  final under = {id};
  // In tree order, an action's parent comes before it.
  for (final action in actions) {
    if (action.id case final child? when under.contains(action.parentId)) {
      under.add(child);
    }
  }
  return under;
}

/// One action, shown by its whole path, picked by tapping it: a sheet up
/// from the foot searches [actions] or browses their tree (see
/// [showActionPicker]). With [noneLabel], the sheet can pick no action
/// too, which [value] null shows as; without, null shows [hint].
class ActionField extends StatelessWidget {
  const ActionField({
    super.key,
    required this.actions,
    required this.value,
    required this.onChanged,
    required this.marker,
    this.title = 'Pick an action',
    this.hint = 'Pick an action',
    this.noneLabel,
    this.exclude = const {},
  });

  final List<PlanAction> actions;
  final String? value;
  final ValueChanged<String?> onChanged;
  final Widget Function(PlanAction action) marker;
  final String title;
  final String hint;
  final String? noneLabel;
  final Set<String> exclude;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final action = actions.where((g) => g.id == value).firstOrNull;
    return InkWell(
      borderRadius: BorderRadius.circular(4),
      onTap: () async {
        final picked = await showActionPicker(
          context,
          actions: actions,
          value: value,
          marker: marker,
          title: title,
          noneLabel: noneLabel,
          exclude: exclude,
        );
        if (picked != null) onChanged(picked.id);
      },
      child: InputDecorator(
        decoration: const InputDecoration(
          isDense: true,
          border: OutlineInputBorder(),
          suffixIcon: Icon(Icons.arrow_drop_down),
        ),
        child: action == null
            ? Text(
                value == null ? noneLabel ?? hint : value!,
                style: value == null && noneLabel == null
                    ? TextStyle(color: theme.hintColor)
                    : null,
              )
            : Row(
                children: [
                  marker(action),
                  const SizedBox(width: 8),
                  // The whole path, wrapping as it needs to.
                  Flexible(child: Text(action.path ?? actionName(action))),
                ],
              ),
      ),
    );
  }
}

/// Asks for one of [actions], [value] picked to start with, in a
/// [showPickerSheet] under [title]: an [ActionsPicker] of them, every
/// group open and the keyboard up to search. Tapping an action picks it
/// and closes the sheet; with [noneLabel], a row over the list picks
/// none. Null if called off; otherwise the action picked, its id null
/// for none.
Future<({String? id})?> showActionPicker(
  BuildContext context, {
  required List<PlanAction> actions,
  required String? value,
  required Widget Function(PlanAction action) marker,
  String title = 'Pick an action',
  String? noneLabel,
  Set<String> exclude = const {},
}) => showPickerSheet<({String? id})>(
  context,
  title: title,
  result: () => (id: value),
  body: (context, _) => ActionsPicker(
    actions: actions,
    picked: [?value],
    single: true,
    inactive: true,
    exclude: exclude,
    none: noneLabel,
    autofocus: true,
    maxListHeight: null,
    marker: marker,
    onChanged: (ids) => Navigator.of(context).pop((id: ids.firstOrNull)),
  ),
);
