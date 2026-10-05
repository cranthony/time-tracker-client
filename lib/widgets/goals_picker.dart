import 'package:flutter/material.dart';

import '../models/goal.dart';

/// Picks several goals from a long list: the picked ones as chips on top,
/// the first marked as the primary goal; a search over every goal's whole
/// path; and, while the search is empty, the goals as a tree that opens
/// only the branches holding a picked goal.
///
/// Lists every active goal in [goals] (in tree order, as the server gives
/// them) and any inactive one already [picked], or with [inactive], every
/// goal; never those in [exclude]. Calls [onChanged] with the new ids, in
/// the order they were picked, so the first stays the primary goal.
///
/// With [single], it picks one goal, with no chips: tapping a goal (or
/// Enter, for the top match) calls [onChanged] with just that one. With
/// [leavesOnly], groups are shown, to find what's in them, but can't be
/// picked: only actions can be given to an event.
class GoalsPicker extends StatefulWidget {
  const GoalsPicker({
    super.key,
    required this.goals,
    required this.picked,
    required this.onChanged,
    required this.marker,
    this.single = false,
    this.inactive = false,
    this.exclude = const {},
    this.leavesOnly = false,
    this.autofocus = false,
    this.maxListHeight = 320,
  });

  final List<Goal> goals;
  final List<String> picked;
  final ValueChanged<List<String>> onChanged;
  final bool single;
  final bool inactive;
  final Set<String> exclude;
  final bool leavesOnly;

  /// Whether the search takes the keyboard at once.
  final bool autofocus;

  /// Drawn before each goal's name, e.g. a dot in its color.
  final Widget Function(Goal goal) marker;

  /// How tall the list of goals grows before it scrolls.
  final double maxListHeight;

  @override
  State<GoalsPicker> createState() => _GoalsPickerState();
}

class _GoalsPickerState extends State<GoalsPicker> {
  final _search = TextEditingController();

  /// The goals whose sub-goals are shown, while the search is empty.
  late final Set<String> _open = _ancestorsOf(widget.picked);

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  List<Goal> get _shown => [
    for (final goal in widget.goals)
      if (goal.id != null &&
          !widget.exclude.contains(goal.id) &&
          (widget.inactive || goal.active || widget.picked.contains(goal.id)))
        goal,
  ];

  Map<String, Goal> get _byId => {
    for (final goal in widget.goals) ?goal.id: goal,
  };

  /// Every goal above any of [ids], so the tree opens down to them.
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

  /// Picks or unpicks [goal]; a goal picked opens the tree down to it.
  void _toggle(Goal goal, bool on) {
    if (on) _open.addAll(_ancestorsOf([goal.id!]));
    if (widget.single) {
      widget.onChanged([goal.id!]);
      return;
    }
    widget.onChanged([
      for (final id in widget.picked)
        if (id != goal.id) id,
      if (on) goal.id!,
    ]);
  }

  /// [goal]'s path above it, e.g. "Cooking" for "Cooking › Tofu"; null
  /// for a top-level goal.
  static String? _above(Goal goal) {
    final path = goal.path;
    if (path == null) return null;
    final cut = path.lastIndexOf(' › ');
    return cut < 0 ? null : path.substring(0, cut);
  }

  /// The words of [query], to match in any order.
  static List<String> _words(String query) => [
    for (final word in query.toLowerCase().split(RegExp(r'\s+')))
      if (word.isNotEmpty) word,
  ];

  /// Whether every word of [query] is in [goal]'s path (or name).
  static bool _matches(Goal goal, List<String> words) {
    final text = (goal.path ?? goalName(goal)).toLowerCase();
    return words.every(text.contains);
  }

  @override
  Widget build(BuildContext context) {
    final shown = _shown;
    if (shown.isEmpty) return const Text('No active goals.');
    final words = _words(_search.text);
    final rows = words.isEmpty
        ? _tree(shown)
        : [
            for (final goal in shown)
              if (_matches(goal, words)) _row(goal, subtitle: _above(goal)),
          ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.picked.isNotEmpty && !widget.single) _chips(context),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: TextField(
            controller: _search,
            autofocus: widget.autofocus,
            decoration: InputDecoration(
              isDense: true,
              border: const OutlineInputBorder(),
              prefixIcon: const Icon(Icons.search),
              hintText: 'Search goals',
              suffixIcon: _search.text.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'Clear search',
                      icon: const Icon(Icons.close),
                      onPressed: () => setState(_search.clear),
                    ),
            ),
            onChanged: (_) => setState(() {}),
            // Kept focused after Enter, ready for the next goal.
            onEditingComplete: () {},
            // The top match, picked (or unpicked) from the keyboard.
            // What's typed now, which may not have been built yet.
            onSubmitted: (text) {
              final words = _words(text);
              if (words.isEmpty) return;
              for (final goal in shown) {
                if (widget.leavesOnly && goal.isGroup) continue;
                if (_matches(goal, words)) {
                  _toggle(goal, !widget.picked.contains(goal.id));
                  setState(_search.clear);
                  return;
                }
              }
            },
          ),
        ),
        ConstrainedBox(
          constraints: BoxConstraints(maxHeight: widget.maxListHeight),
          child: rows.isEmpty
              ? const Padding(
                  padding: EdgeInsets.all(8),
                  child: Text('No goals match.'),
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

  /// The picked goals, the first starred as the primary goal; ✕ unpicks.
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
                    message: 'Primary goal',
                    child: Icon(Icons.star, size: 18),
                  )
                : switch (byId[id]) {
                    final goal? => widget.marker(goal),
                    null => null,
                  },
            label: Text(switch (byId[id]) {
              final goal? => goalName(goal),
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

  /// The goals in tree order, indented, each branch shown only while
  /// it's open. A goal whose parent isn't shown sits at the top, with its
  /// path under its name.
  List<Widget> _tree(List<Goal> shown) {
    final ids = {for (final goal in shown) goal.id!};
    final children = <String?, List<Goal>>{};
    for (final goal in shown) {
      final parent = ids.contains(goal.parentId) ? goal.parentId : null;
      children.putIfAbsent(parent, () => []).add(goal);
    }
    final rows = <Widget>[];
    void visit(Goal goal, int depth) {
      final id = goal.id!;
      final subGoals = children[id] ?? const <Goal>[];
      final open = _open.contains(id);
      rows.add(
        _row(
          goal,
          depth: depth,
          subtitle: depth == 0 ? _above(goal) : null,
          trailing: subGoals.isEmpty
              ? null
              : IconButton(
                  tooltip: open
                      ? 'Hide sub-goals'
                      : 'Show ${subGoals.length} sub-goal'
                            '${subGoals.length == 1 ? '' : 's'}',
                  icon: Icon(open ? Icons.expand_less : Icons.expand_more),
                  onPressed: () =>
                      setState(() => open ? _open.remove(id) : _open.add(id)),
                ),
        ),
      );
      if (open) {
        for (final child in subGoals) {
          visit(child, depth + 1);
        }
      }
    }

    for (final root in children[null] ?? const <Goal>[]) {
      visit(root, 0);
    }
    return rows;
  }

  Widget _row(Goal goal, {int depth = 0, String? subtitle, Widget? trailing}) {
    final hint = Theme.of(context).hintColor;
    final picked = widget.picked.contains(goal.id);
    final title = Row(
      children: [
        widget.marker(goal),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            goalName(goal),
            style: goal.active ? null : TextStyle(color: hint),
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
    if (widget.leavesOnly && goal.isGroup) {
      return ListTile(
        key: ValueKey(goal.id!),
        dense: true,
        contentPadding: EdgeInsetsDirectional.only(start: 16.0 * depth + 12),
        leading: Icon(Icons.folder_outlined, color: hint),
        trailing: trailing,
        title: title,
        subtitle: under,
      );
    }
    if (widget.single) {
      return ListTile(
        key: ValueKey(goal.id!),
        dense: true,
        contentPadding: EdgeInsetsDirectional.only(start: 16.0 * depth + 12),
        selected: picked,
        leading: Icon(
          picked ? Icons.radio_button_checked : Icons.radio_button_unchecked,
        ),
        trailing: trailing,
        title: title,
        subtitle: under,
        onTap: () => _toggle(goal, true),
      );
    }
    return CheckboxListTile(
      key: ValueKey(goal.id!),
      dense: true,
      contentPadding: EdgeInsetsDirectional.only(start: 16.0 * depth),
      controlAffinity: ListTileControlAffinity.leading,
      value: picked,
      // With the box leading, this sits at the end.
      secondary: trailing,
      title: title,
      subtitle: under,
      onChanged: (on) => _toggle(goal, on == true),
    );
  }
}

/// [id] and every goal under it in [goals]: what can't be its parent.
Set<String> goalAndSubGoals(List<Goal> goals, String id) {
  final under = {id};
  // In tree order, a goal's parent comes before it.
  for (final goal in goals) {
    if (goal.id case final child? when under.contains(goal.parentId)) {
      under.add(child);
    }
  }
  return under;
}

/// One goal, shown by its whole path, picked by tapping it: a dialog
/// searches [goals] or browses their tree (see [GoalsPicker]). With
/// [noneLabel], the dialog can pick no goal too, which [value] null shows
/// as; without, null shows [hint].
class GoalField extends StatelessWidget {
  const GoalField({
    super.key,
    required this.goals,
    required this.value,
    required this.onChanged,
    required this.marker,
    this.title = 'Pick a goal',
    this.hint = 'Pick a goal',
    this.noneLabel,
    this.exclude = const {},
  });

  final List<Goal> goals;
  final String? value;
  final ValueChanged<String?> onChanged;
  final Widget Function(Goal goal) marker;
  final String title;
  final String hint;
  final String? noneLabel;
  final Set<String> exclude;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final goal = goals.where((g) => g.id == value).firstOrNull;
    return InkWell(
      borderRadius: BorderRadius.circular(4),
      onTap: () async {
        final picked = await showGoalPicker(
          context,
          goals: goals,
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
        child: goal == null
            ? Text(
                value == null ? noneLabel ?? hint : value!,
                style: value == null && noneLabel == null
                    ? TextStyle(color: theme.hintColor)
                    : null,
              )
            : Row(
                children: [
                  marker(goal),
                  const SizedBox(width: 8),
                  // The whole path, wrapping as it needs to.
                  Flexible(child: Text(goal.path ?? goalName(goal))),
                ],
              ),
      ),
    );
  }
}

/// Asks for one of [goals], [value] picked to start with; see
/// [GoalField]. Null if called off; otherwise the goal picked, its id
/// null for none.
Future<({String? id})?> showGoalPicker(
  BuildContext context, {
  required List<Goal> goals,
  required String? value,
  required Widget Function(Goal goal) marker,
  String title = 'Pick a goal',
  String? noneLabel,
  Set<String> exclude = const {},
}) => showDialog<({String? id})>(
  context: context,
  builder: (context) => AlertDialog(
    title: Text(title),
    content: SizedBox(
      width: 420,
      child: GoalsPicker(
        goals: goals,
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
