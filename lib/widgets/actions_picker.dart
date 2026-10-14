import 'package:flutter/material.dart';

import '../models/plan_action.dart';
import 'picker_search.dart';

/// Picks several actions from a long list: the picked ones as chips on top,
/// the first marked as the primary action; a search over every action's whole
/// path; and, while the search is empty, the actions as a tree that opens
/// only the branches holding a picked action.
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
/// closes it.
///
/// Its [search] can be given, to start it with words typed, or keep
/// them past it. Long-pressing an action or group calls [onEdit] with it;
/// with [onAdd], a row over the list adds one, given what's typed.
class ActionsPicker extends StatefulWidget {
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

  /// Whether the search takes the keyboard at once, what's typed in it
  /// selected.
  final bool autofocus;

  final PickerSearch? search;
  final ValueChanged<PlanAction>? onEdit;
  final ValueChanged<String>? onAdd;

  /// Drawn before each action's name, e.g. a dot in its color.
  final Widget Function(PlanAction action) marker;

  /// How tall the list of actions grows before it scrolls.
  final double maxListHeight;

  @override
  State<ActionsPicker> createState() => _ActionsPickerState();
}

class _ActionsPickerState extends State<ActionsPicker> {
  /// Its own search, unless it was given one.
  PickerSearch? _own;
  PickerSearch get _search => widget.search ?? (_own ??= PickerSearch());

  /// The actions whose sub-actions are shown, while the search is empty.
  late final Set<String> _open = _ancestorsOf(widget.picked);

  @override
  void initState() {
    super.initState();
    _search.addListener(_searched);
    if (widget.autofocus) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _search.focusAll();
      });
    }
  }

  @override
  void didUpdateWidget(ActionsPicker oldWidget) {
    super.didUpdateWidget(oldWidget);
    final was = oldWidget.search ?? _own;
    if (was != _search) {
      was?.removeListener(_searched);
      _search.addListener(_searched);
    }
  }

  void _searched() => setState(() {});

  @override
  void dispose() {
    _search.removeListener(_searched);
    _own?.dispose();
    super.dispose();
  }

  List<PlanAction> get _shown => [
    for (final action in widget.actions)
      if (action.id != null &&
          !widget.exclude.contains(action.id) &&
          (widget.inactive ||
              action.active ||
              widget.picked.contains(action.id)))
        action,
  ];

  Map<String, PlanAction> get _byId => {
    for (final action in widget.actions) ?action.id: action,
  };

  /// Every action above any of [ids], so the tree opens down to them.
  Set<String> _ancestorsOf(List<String> ids) {
    final byId = _byId;
    final above = <String>{};
    for (final id in ids) {
      var parent = byId[id]?.parentId;
      while (parent != null && above.add(parent)) {
        parent = byId[parent]?.parentId;
      }
    }
    return above;
  }

  /// Picks or unpicks [action]; an action picked opens the tree down to it.
  void _toggle(PlanAction action, bool on) {
    if (on) _open.addAll(_ancestorsOf([action.id!]));
    if (widget.single) {
      widget.onChanged([action.id!]);
      return;
    }
    widget.onChanged([
      for (final id in widget.picked)
        if (id != action.id) id,
      if (on) action.id!,
    ]);
  }

  /// [action]'s path above it, e.g. "Cooking" for "Cooking › Tofu"; null
  /// for a top-level action.
  static String? _above(PlanAction action) {
    final path = action.path;
    if (path == null) return null;
    final cut = path.lastIndexOf(' › ');
    return cut < 0 ? null : path.substring(0, cut);
  }

  /// What an action is searched by: its whole path (or name).
  static String _text(PlanAction action) => action.path ?? actionName(action);

  @override
  Widget build(BuildContext context) {
    final shown = _shown;
    if (shown.isEmpty && widget.onAdd == null) {
      return const Text('No active actions.');
    }
    final query = _search.query;
    final rows = query.isEmpty
        ? _tree(shown)
        : [
            for (final action in query.filter(shown, _text))
              _row(action, subtitle: _above(action)),
          ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.picked.isNotEmpty && !widget.single) _chips(context),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: PickerSearchField(
            search: _search,
            hint: 'Search actions',
            // The top match, picked (or unpicked) from the keyboard.
            // What's typed now, which may not have been built yet.
            onSubmitted: (text) {
              final query = PickerQuery(text, any: _search.matchAny);
              if (query.isEmpty) return;
              final pickable = [
                for (final action in shown)
                  if (!widget.leavesOnly || !action.isGroup) action,
              ];
              final top = query.filter(pickable, _text).firstOrNull;
              if (top == null) return;
              _toggle(top, !widget.picked.contains(top.id));
              _search.controller.clear();
            },
          ),
        ),
        if (widget.onAdd case final add?)
          PickerAddTile(
            noun: 'action',
            search: _search,
            icon: Icons.add,
            onAdd: add,
          ),
        ConstrainedBox(
          constraints: BoxConstraints(maxHeight: widget.maxListHeight),
          child: rows.isEmpty
              ? const Padding(
                  padding: EdgeInsets.all(8),
                  child: Text('No actions match.'),
                )
              // Not a ListView: a dialog measures its content's
              // intrinsic width, which a lazy list can't give.
              : SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: rows,
                  ),
                ),
        ),
      ],
    );
  }

  /// The picked actions, the first starred as the primary action; ✕ unpicks.
  Widget _chips(BuildContext context) {
    final byId = _byId;
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final (i, id) in widget.picked.indexed)
          InputChip(
            avatar: i == 0
                ? const Tooltip(
                    message: 'Primary action',
                    child: Icon(Icons.star, size: 18),
                  )
                : switch (byId[id]) {
                    final action? => widget.marker(action),
                    null => null,
                  },
            label: Text(switch (byId[id]) {
              final action? => actionName(action),
              null => id,
            }),
            deleteButtonTooltipMessage: 'Remove',
            onDeleted: () => widget.onChanged([
              for (final other in widget.picked)
                if (other != id) other,
            ]),
          ),
      ],
    );
  }

  /// The actions in tree order, indented, each branch shown only while
  /// it's open. An action whose parent isn't shown sits at the top, with its
  /// path under its name.
  List<Widget> _tree(List<PlanAction> shown) {
    final ids = {for (final action in shown) action.id!};
    final children = <String?, List<PlanAction>>{};
    for (final action in shown) {
      final parent = ids.contains(action.parentId) ? action.parentId : null;
      children.putIfAbsent(parent, () => []).add(action);
    }
    final rows = <Widget>[];
    void visit(PlanAction action, int depth) {
      final id = action.id!;
      final subActions = children[id] ?? const <PlanAction>[];
      final open = _open.contains(id);
      void toggle() => setState(() => open ? _open.remove(id) : _open.add(id));
      rows.add(
        _row(
          action,
          depth: depth,
          subtitle: depth == 0 ? _above(action) : null,
          onOpen: subActions.isEmpty ? null : toggle,
          trailing: subActions.isEmpty
              ? null
              : IconButton(
                  tooltip: open
                      ? "Hide what's inside"
                      : 'Show ${subActions.length} inside',
                  icon: Icon(open ? Icons.expand_less : Icons.expand_more),
                  onPressed: toggle,
                ),
        ),
      );
      if (open) {
        for (final child in subActions) {
          visit(child, depth + 1);
        }
      }
    }

    for (final root in children[null] ?? const <PlanAction>[]) {
      visit(root, 0);
    }
    return rows;
  }

  /// [action]'s row, long-pressed to edit it; [onOpen] opens or closes
  /// what's in it, where it can't be picked.
  Widget _row(
    PlanAction action, {
    int depth = 0,
    String? subtitle,
    Widget? trailing,
    VoidCallback? onOpen,
  }) {
    final row = _tile(
      action,
      depth: depth,
      subtitle: subtitle,
      trailing: trailing,
      onOpen: onOpen,
    );
    final edit = widget.onEdit;
    if (edit == null) return row;
    return GestureDetector(
      key: ValueKey(action.id!),
      onLongPress: () => edit(action),
      child: row,
    );
  }

  Widget _tile(
    PlanAction action, {
    required int depth,
    required String? subtitle,
    required Widget? trailing,
    required VoidCallback? onOpen,
  }) {
    final hint = Theme.of(context).hintColor;
    final picked = widget.picked.contains(action.id);
    final title = Row(
      children: [
        widget.marker(action),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            actionName(action),
            style: action.active ? null : TextStyle(color: hint),
          ),
        ),
      ],
    );
    final under = subtitle == null
        ? null
        : Text(
            subtitle,
            style: TextStyle(color: hint),
            overflow: TextOverflow.ellipsis,
          );
    if (widget.leavesOnly && action.isGroup) {
      return ListTile(
        key: ValueKey(action.id!),
        dense: true,
        contentPadding: EdgeInsetsDirectional.only(start: 16.0 * depth + 12),
        leading: Icon(Icons.folder_outlined, color: hint),
        trailing: trailing,
        title: title,
        subtitle: under,
        onTap: onOpen,
      );
    }
    if (widget.single) {
      return ListTile(
        key: ValueKey(action.id!),
        dense: true,
        contentPadding: EdgeInsetsDirectional.only(start: 16.0 * depth + 12),
        selected: picked,
        leading: Icon(
          picked ? Icons.radio_button_checked : Icons.radio_button_unchecked,
        ),
        trailing: trailing,
        title: title,
        subtitle: under,
        onTap: () => _toggle(action, true),
      );
    }
    return CheckboxListTile(
      key: ValueKey(action.id!),
      dense: true,
      contentPadding: EdgeInsetsDirectional.only(start: 16.0 * depth),
      controlAffinity: ListTileControlAffinity.leading,
      value: picked,
      // With the box leading, this sits at the end.
      secondary: trailing,
      title: title,
      subtitle: under,
      onChanged: (on) => _toggle(action, on == true),
    );
  }
}

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

/// One action, shown by its whole path, picked by tapping it: a dialog
/// searches [actions] or browses their tree (see [ActionsPicker]). With
/// [noneLabel], the dialog can pick no action too, which [value] null shows
/// as; without, null shows [hint].
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

/// Asks for one of [actions], [value] picked to start with; see
/// [ActionField]. Null if called off; otherwise the action picked, its id
/// null for none.
Future<({String? id})?> showActionPicker(
  BuildContext context, {
  required List<PlanAction> actions,
  required String? value,
  required Widget Function(PlanAction action) marker,
  String title = 'Pick an action',
  String? noneLabel,
  Set<String> exclude = const {},
}) => showDialog<({String? id})>(
  context: context,
  builder: (context) => AlertDialog(
    title: Text(title),
    content: SizedBox(
      width: 420,
      child: ActionsPicker(
        actions: actions,
        picked: [?value],
        single: true,
        inactive: true,
        exclude: exclude,
        autofocus: true,
        // Room left on the screen for the list, past the dialog's title,
        // search and buttons.
        maxListHeight: (MediaQuery.sizeOf(context).height - 320).clamp(
          160,
          400,
        ),
        marker: marker,
        onChanged: (ids) => Navigator.pop(context, (id: ids.single)),
      ),
    ),
    actions: [
      if (noneLabel != null)
        TextButton(
          onPressed: () => Navigator.pop(context, (id: null)),
          child: Text(noneLabel),
        ),
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
    ],
  ),
);
