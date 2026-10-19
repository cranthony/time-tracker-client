import 'package:flutter/material.dart';

import '../models/goal.dart';
import 'goal_icon.dart';
import 'picker_sheet.dart';
import 'share_dialog.dart';
import 'tree_picker.dart';

/// Picks the goals an event is for in a [showPickerSheet]: a [TreePicker]
/// over the open goals (and any [picked] already that aren't), each under
/// its parent, the picked as chips. Tapping a chip sets how much of the
/// event that goal takes ([showGoalShareDialog]); each chip says it. What
/// the shares come to is checked against the event, [eventMinutes] long.
/// Gives the shares picked, in order; null if it's dismissed.
Future<List<GoalShare>?> showGoalsSheet(
  BuildContext context, {
  required List<Goal> goals,
  required List<GoalShare> picked,
  required int eventMinutes,
}) {
  var shares = [...picked];
  final tree = GoalTree(goals);
  final pickedIds = {for (final s in picked) s.goalId};
  final shown = [
    for (final g in goals)
      if (g.open || pickedIds.contains(g.id)) g,
  ];
  final nodes = [
    for (final g in byPriority(shown, tree))
      PickerNode(
        id: g.id,
        label: goalTitle(g),
        parentId: g.parentId,
        path: [...tree.pathOf(g.id), goalTitle(g)].join(' › '),
        detail: g.inactive
            ? 'Inactive'
            : (g.closed ? goalStatuses[g.status] : null),
        group: tree.childrenOf(g.id).isNotEmpty,
        faded: !g.active,
      ),
  ];
  return showPickerSheet(
    context,
    title: 'Goals',
    result: () => shares,
    body: (context, setState) {
      final problems = shareProblems(shares, eventMinutes);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (problems.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                problems.join(' '),
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          Expanded(
            child: TreePicker(
              nodes: nodes,
              picked: [for (final s in shares) s.goalId],
              groupsPickable: true,
              searchHint: 'Search goals',
              empty: 'No goals yet: add them on the Plan page.',
              marker: (node) => GoalIcon(
                size: 18,
                color: tree[node.id]?.active ?? false
                    ? null
                    : Theme.of(context).hintColor,
              ),
              chipDetail: (id) =>
                  shares.where((s) => s.goalId == id).firstOrNull?.label,
              onChipTap: (id) async {
                final share = shares.firstWhere((s) => s.goalId == id);
                final set = await showGoalShareDialog(
                  context,
                  goal: tree[id],
                  share: share,
                  eventMinutes: eventMinutes,
                );
                if (set == null) return;
                setState(() {
                  shares = [for (final s in shares) s.goalId == id ? set : s];
                });
              },
              onChanged: (ids) => setState(() {
                final by = {for (final s in shares) s.goalId: s};
                shares = [for (final id in ids) by[id] ?? GoalShare(id)];
              }),
            ),
          ),
        ],
      );
    },
  );
}

/// How much of an event, [eventMinutes] long, [goal] takes
/// ([showShareDialog]). Gives the share as set, or null if it's called
/// off.
Future<GoalShare?> showGoalShareDialog(
  BuildContext context, {
  required Goal? goal,
  required GoalShare share,
  required int eventMinutes,
}) => showShareDialog(
  context,
  title: goal == null ? share.goalId : goalTitle(goal),
  share: share,
  eventMinutes: eventMinutes,
  kind: 'goal',
  rest:
      "It counts the time the other goals' durations and percents leave, "
      'as every goal given neither does.',
  make: (minutes, percent, remaining) => GoalShare(
    share.goalId,
    minutes: minutes,
    percent: percent,
    remaining: remaining,
  ),
);
