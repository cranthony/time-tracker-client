import 'package:flutter/material.dart';

import '../models/goal.dart';

/// Picks several goals from a long list: the picked ones as chips on top,
/// the first marked as the primary goal; a search over every goal's whole
/// path; and, while the search is empty, the goals as a tree that opens
/// only the branches holding a picked goal.
///
/// Lists every active goal in [goals] (in tree order, as the server gives
/// them) and any inactive one already [picked]. Calls [onChanged] with the
/// new ids, in the order they were picked, so the first stays the primary
/// goal.
class GoalsPicker extends StatefulWidget {
  const GoalsPicker({
    super.key,
    required this.goals,
    required this.picked,
    required this.onChanged,
    required this.marker,
    this.maxListHeight = 320,
  });

  final List<Goal> goals;
  final List<String> picked;
  final ValueChanged<List<String>> onChanged;

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
          !goal.isOverall &&
          (goal.active || widget.picked.contains(goal.id)))
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

  void _toggle(Goal goal, bool on) => widget.onChanged([
    for (final id in widget.picked)
      if (id != goal.id) id,
    if (on) goal.id!,
  ]);

  /// [goal]'s path above it, e.g. "Cooking" for "Cooking › Tofu"; null
  /// for a top-level goal.
  static String? _above(Goal goal) {
    final path = goal.path;
    if (path == null) return null;
    final cut = path.lastIndexOf(' › ');
    return cut < 0 ? null : path.substring(0, cut);
  }

  /// Whether every word of [query] is in [goal]'s path (or name).
  static bool _matches(Goal goal, List<String> words) {
    final text = (goal.path ?? goalName(goal)).toLowerCase();
    return words.every(text.contains);
  }

  @override
  Widget build(BuildContext context) {
    final shown = _shown;
    if (shown.isEmpty) return const Text('No active goals.');
    final words = [
      for (final word in _search.text.toLowerCase().split(RegExp(r'\s+')))
        if (word.isNotEmpty) word,
    ];
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
        if (widget.picked.isNotEmpty) _chips(context),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: TextField(
            controller: _search,
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
            // The top match, picked (or unpicked) from the keyboard.
            onSubmitted: (_) {
              if (words.isEmpty) return;
              for (final goal in shown) {
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
    return CheckboxListTile(
      key: ValueKey(goal.id),
      dense: true,
      contentPadding: EdgeInsetsDirectional.only(start: 16.0 * depth),
      controlAffinity: ListTileControlAffinity.leading,
      value: picked,
      // With the box leading, this sits at the end.
      secondary: trailing,
      title: Row(
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
      ),
      subtitle: subtitle == null
          ? null
          : Text(
              subtitle,
              style: TextStyle(color: hint),
              overflow: TextOverflow.ellipsis,
            ),
      onChanged: (on) => _toggle(goal, on == true),
    );
  }
}
