import 'goal.dart';

/// The gap left between goals' [Goal.sortOrder]s when they're numbered
/// afresh, so a goal dragged between two can mostly take one between
/// theirs, with no other goal changed.
const sortOrderStep = 1000;

/// Where a goal dragged in a list ends up: [index], where it's dropped,
/// among the goals listed without it -- kept among those it lists alike
/// with ([GoalTree.listAlike]) -- [warning] if that isn't where it was
/// dragged to, and the [Goal.sortOrder]s to save, by goal id: none if it
/// doesn't move.
class GoalMove {
  const GoalMove(this.index, this.warning, this.sortOrders);

  final int index;
  final String? warning;
  final Map<String, int> sortOrders;
}

/// [id], in [listed] -- goals as [GoalTree.compare] has them in [tree] --
/// dragged to [to], the place among the others it's dropped at (0, before
/// them all). It can't go past a goal it doesn't list alike with: there,
/// it's kept at the nearest place it can be, saying why.
GoalMove moveGoal(List<Goal> listed, GoalTree tree, String id, int to) {
  final goal = listed.firstWhere((g) => g.id == id);
  final from = listed.indexOf(goal);
  final others = [...listed]..removeAt(from);
  // Those it lists alike with are together, in the list without it.
  final first = others.indexWhere((g) => tree.listAlike(g, goal));
  final alike = others.where((g) => tree.listAlike(g, goal)).length;
  final lo = first < 0 ? from : first;
  final hi = lo + alike;
  final index = to.clamp(lo, hi);
  String? warning;
  if (to < lo) {
    final above = others[lo - 1];
    warning = tree.priorityOf(above.id) < tree.priorityOf(goal.id)
        ? "It can't go above a higher-priority goal."
        : "It can't go above a goal due sooner.";
  } else if (to > hi) {
    final below = others[hi];
    warning = tree.priorityOf(below.id) > tree.priorityOf(goal.id)
        ? "It can't go below a lower-priority goal."
        : below.due == null
        ? "It can't go below a goal with no deadline."
        : "It can't go below a goal due later.";
  }
  if (index == from) return GoalMove(index, warning, const {});
  final group = others.sublist(lo, hi)..insert(index - lo, goal);
  return GoalMove(index, warning, _sortOrders(group, index - lo));
}

/// The [Goal.sortOrder]s that list [group] -- goals listed alike -- in its
/// order, [at] the one moved: just its own, if one fits between its
/// neighbours'; or else theirs numbered afresh, as far as needed.
Map<String, int> _sortOrders(List<Goal> group, int at) {
  final moved = group[at];
  final before = at > 0 ? group[at - 1].sortOrder : null;
  final after = at + 1 < group.length ? group[at + 1].sortOrder : null;
  // Those with no order list after those with one, so it fits on its own
  // only after goals that all have one.
  if (at == 0 || before != null) {
    final own = switch ((before, after)) {
      (null, null) => sortOrderStep,
      (final b?, null) => b + sortOrderStep,
      (null, final a?) => a - sortOrderStep,
      (final b?, final a?) when a - b > 1 => b + (a - b) ~/ 2,
      _ => null,
    };
    if (own != null) return {moved.id: own};
  }
  // Numbered afresh up to it, and past it as far as goals have an order.
  final last = [
    at,
    for (final (i, g) in group.indexed)
      if (g.sortOrder != null) i,
  ].reduce((a, b) => a > b ? a : b);
  return {
    for (final (i, g) in group.take(last + 1).indexed)
      if (g.sortOrder != (i + 1) * sortOrderStep) g.id: (i + 1) * sortOrderStep,
  };
}
