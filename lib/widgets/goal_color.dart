import 'package:flutter/material.dart';

import '../models/goal.dart';
import 'color_picker.dart';

/// The color [goal] shows -- its page's dot, the due strip's pills and
/// the home screen widget's bars: its own ([Goal.backgroundColor]), or
/// else its nearest parent's that has one, found among [tree]'s goals
/// ([GoalTree.colorSourceOf]) -- or, with no tree, or one it isn't in, as
/// the server last said ([Goal.effectiveColor]) -- or else the color of
/// the priority that applies to it ([priorityColor]).
Color colorOfGoal(Goal goal, {GoalTree? tree}) {
  if (tree != null && tree[goal.id] != null) {
    return parseColor(tree.colorSourceOf(goal.id)?.backgroundColor) ??
        priorityColor(tree.priorityOf(goal.id));
  }
  return parseColor(goal.backgroundColor) ??
      parseColor(goal.effectiveColor) ??
      priorityColor(goal.priority ?? defaultGoalPriority);
}

/// The color each of [goals] was given, by id: its own, or else its
/// nearest parent's that has one. Those whose color is only their
/// priority's aren't in it.
Map<String, Color> chosenGoalColors(Iterable<Goal> goals) {
  final tree = GoalTree(goals);
  return {
    for (final g in goals)
      g.id: ?parseColor(tree.colorSourceOf(g.id)?.backgroundColor),
  };
}

/// Where [goal]'s color comes from, for its page: "Its own", "From
/// `the parent it takes it from`" or "Its priority's (P2)".
String goalColorSource(GoalTree tree, Goal goal) =>
    switch (tree.colorSourceOf(goal.id)) {
      final from? when from.id == goal.id => 'Its own',
      final from? => 'From ${goalTitle(from)}',
      null => "Its priority's (P${tree.priorityOf(goal.id)})",
    };

/// What a goal under [parentId] (the top level, if null) with no color of
/// its own shows, for its editor: its nearest parent's that has one, or
/// else [priority]'s -- the one that applies to it.
String inheritedColorLabel(GoalTree tree, String? parentId, int priority) {
  final from = parentId == null ? null : tree.colorSourceOf(parentId);
  return from == null
      ? "With none, it takes its priority's (P$priority)."
      : "With none, it takes ${goalTitle(from)}'s.";
}
