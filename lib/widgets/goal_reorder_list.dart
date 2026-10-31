import 'package:flutter/material.dart';

import '../models/goal.dart';
import '../models/goal_order.dart';

/// [goals] -- as [GoalTree.compare] has them in [tree], or as an outline
/// of it ([GoalTree.outline]) -- each as [tile] builds it, held and
/// dragged to put it in the user's own order among those beside it (under
/// the same goal) that it lists alike with ([GoalTree.listAlike]); those
/// under it go with it. Dragged past one it
/// can't go past, the goal says why as it's dragged, and is dropped at the
/// nearest place it can be ([moveGoal]); [onMove] is given the
/// [Goal.sortOrder]s to save. With [scrolls] false, it's laid out in
/// whatever scrolls around it.
class GoalReorderList extends StatefulWidget {
  const GoalReorderList({
    super.key,
    required this.goals,
    required this.tree,
    required this.tile,
    required this.onMove,
    this.scrolls = true,
    this.footer,
    this.padding,
  });

  final List<Goal> goals;
  final GoalTree tree;
  final Widget Function(Goal goal) tile;
  final ValueChanged<Map<String, int>> onMove;
  final bool scrolls;

  /// After the goals, in the same list.
  final Widget? footer;

  /// Around the list: room under it for a button over it, say.
  final EdgeInsets? padding;

  @override
  State<GoalReorderList> createState() => _GoalReorderListState();
}

class _GoalReorderListState extends State<GoalReorderList> {
  /// Each goal's tile, by id, to find where it is as one's dragged.
  final _keys = <String, GlobalKey>{};

  /// The goal being dragged, if one is.
  String? _dragged;

  /// Why it can't go where it's been dragged to, if it can't.
  final _warning = ValueNotifier<String?>(null);

  @override
  void dispose() {
    _warning.dispose();
    super.dispose();
  }

  GlobalKey _keyOf(String id) => _keys.putIfAbsent(id, GlobalKey.new);

  /// Where the goal dragged would be dropped with the pointer at [y]: among
  /// the others, after those whose middles are above it.
  void _dragTo(double y) {
    final id = _dragged;
    if (id == null) return;
    var to = 0;
    for (final g in widget.goals) {
      if (g.id == id) continue;
      final box = _keys[g.id]?.currentContext?.findRenderObject();
      if (box is! RenderBox || !box.attached) continue;
      final middle = box.localToGlobal(box.size.center(Offset.zero)).dy;
      if (middle < y) to++;
    }
    _warning.value = _move(id, to).warning;
  }

  /// [to] is among the others, the goal dragged taken out.
  void _reorder(int from, int to) {
    final move = _move(widget.goals[from].id, to);
    if (move.sortOrders.isNotEmpty) widget.onMove(move.sortOrders);
  }

  /// [id] dropped at [to], among the goals listed but it: among those
  /// beside it, at the place after those of them above [to].
  GoalMove _move(String id, int to) {
    final tree = widget.tree;
    String? parentOf(Goal g) => tree[g.parentId]?.id;
    final parent = parentOf(tree[id]!);
    final others = [
      for (final g in widget.goals)
        if (g.id != id) g,
    ];
    final siblings = [
      for (final g in widget.goals)
        if (parentOf(g) == parent) g,
    ];
    final at = others.take(to).where((g) => parentOf(g) == parent).length;
    return moveGoal(siblings, tree, id, at);
  }

  Widget _proxy(Widget child, int index, Animation<double> animation) {
    final theme = Theme.of(context);
    return Material(
      elevation: 6,
      color: theme.colorScheme.surface,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          child,
          ValueListenableBuilder(
            valueListenable: _warning,
            builder: (context, warning, _) => warning == null
                ? const SizedBox.shrink()
                : Container(
                    color: theme.colorScheme.errorContainer,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 6,
                    ),
                    child: Text(
                      warning,
                      style: TextStyle(
                        color: theme.colorScheme.onErrorContainer,
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final goals = widget.goals;
    return Listener(
      onPointerMove: (event) => _dragTo(event.position.dy),
      child: ReorderableListView.builder(
        shrinkWrap: !widget.scrolls,
        physics: widget.scrolls
            ? const AlwaysScrollableScrollPhysics()
            : const NeverScrollableScrollPhysics(),
        buildDefaultDragHandles: false,
        itemCount: goals.length,
        footer: widget.footer,
        padding: widget.padding,
        proxyDecorator: _proxy,
        onReorderStart: (index) => setState(() {
          _dragged = goals[index].id;
          _warning.value = null;
        }),
        onReorderEnd: (_) => setState(() {
          _dragged = null;
          _warning.value = null;
        }),
        onReorderItem: _reorder,
        itemBuilder: (context, index) {
          final goal = goals[index];
          return ReorderableDelayedDragStartListener(
            key: ValueKey(goal.id),
            index: index,
            child: KeyedSubtree(key: _keyOf(goal.id), child: widget.tile(goal)),
          );
        },
      ),
    );
  }
}
