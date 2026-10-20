import 'package:flutter/material.dart';

import 'durations.dart';
import '../models/goal.dart';
import '../services/plan_memory.dart';
import 'goal_editor.dart';
import 'goal_icon.dart';
import 'priority_chip.dart';

/// The time spent toward each goal in the events kept on the device
/// ([timeSpent]), by id: with [through], only those ended by then.
Map<String, Duration> keptGoalTime(
  PlanMemory memory,
  GoalTree tree, {
  DateTime? through,
}) {
  final store = memory.eventStore;
  final span = store?.span;
  if (store == null || span == null) return const {};
  final (first, last) = span;
  final events = store.between(first, last.add(const Duration(days: 1)));
  return timeSpent(
    through == null ? events : events.where((e) => !e.end.isAfter(through)),
    tree,
  );
}

/// What's left of [goal]'s expected time after [spent]: "3h 40m left",
/// or, past it, "1h over"; null if it has none.
String? leftLabel(Goal goal, Duration? spent) {
  final expected = goal.expectedMinutes;
  if (expected == null) return null;
  final left = expected - (spent?.inMinutes ?? 0);
  return left < 0
      ? '${formatMinutes(-left)} over'
      : '${formatMinutes(left)} left';
}

/// [spent] against [goal]'s expected time: "6h 20m of 10h", or just the
/// time spent, if it has none; null with neither.
String? spentLabel(Goal goal, Duration? spent) {
  final minutes = spent?.inMinutes ?? 0;
  return switch ((minutes, goal.expectedMinutes)) {
    (_, final expected?) =>
      '${formatMinutes(minutes)} of ${formatMinutes(expected)}',
    (> 0, null) => '${formatMinutes(minutes)} spent',
    _ => null,
  };
}

/// [n] times: "once", "twice", "3 times".
String timesLabel(int n) => switch (n) {
  1 => 'once',
  2 => 'twice',
  _ => '$n times',
};

/// A goal's color by its status: active in the theme's primary, the rest
/// quieter.
Color goalColor(BuildContext context, Goal goal) {
  final scheme = Theme.of(context).colorScheme;
  return switch (goal.status) {
    'active' => scheme.primary,
    'done' => scheme.tertiary,
    _ => scheme.onSurfaceVariant,
  };
}

/// One goal in a list: its icon, title -- with [priority], the one that
/// applies, after it as a chip, filled when it's the goal's own and
/// outlined when it's inherited or the default -- when it's due and the
/// time spent toward it -- and, if it's not active, its status. Tapped, it
/// opens ([onTap]); its button at the right edits it ([onEdit]).
class GoalTile extends StatelessWidget {
  const GoalTile({
    super.key,
    required this.goal,
    this.spent,
    this.subGoals = 0,
    this.priority,
    this.onTap,
    this.onEdit,
  });

  final Goal goal;
  final Duration? spent;

  /// How many goals are directly under it.
  final int subGoals;

  /// The priority that applies to it ([GoalTree.priorityOf]); none shown,
  /// if null.
  final int? priority;
  final VoidCallback? onTap;
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final overdue =
        goal.open && goal.due != null && goal.due!.isBefore(DateTime.now());
    final details = [
      if (!goal.active) goalStatuses[goal.status] ?? goal.status,
      if (goal.deadline != null) 'Due ${deadlineLabel(context, goal.deadline)}',
      if (goal.open && goal.misses.isNotEmpty)
        'Missed ${timesLabel(goal.misses.length)}',
      ?spentLabel(goal, spent),
      if (subGoals > 0) '$subGoals sub-goal${subGoals == 1 ? '' : 's'}',
      if (goal.required) 'Required',
    ];
    return Opacity(
      opacity: goal.closed ? 0.6 : 1,
      child: ListTile(
        leading: GoalIcon(color: goalColor(context, goal)),
        title: Row(
          children: [
            Flexible(
              child: Text(
                goalTitle(goal),
                style: goal.closed
                    ? const TextStyle(decoration: TextDecoration.lineThrough)
                    : null,
              ),
            ),
            if (priority case final p?) ...[
              const SizedBox(width: 6),
              PriorityChip(priority: p, own: goal.priority != null),
            ],
          ],
        ),
        subtitle: details.isEmpty
            ? null
            : Text(
                details.join(' · '),
                style: overdue
                    ? TextStyle(color: theme.colorScheme.error)
                    : null,
              ),
        trailing: onEdit == null
            ? null
            : IconButton(
                tooltip: 'Edit ${goalTitle(goal)}',
                icon: const Icon(Icons.edit_outlined),
                onPressed: onEdit,
              ),
        onTap: onTap,
      ),
    );
  }
}

/// [depth] lines side by side, standing for how deep a goal is: none at
/// the top level.
class DepthBars extends StatelessWidget {
  const DepthBars({super.key, required this.depth, this.height = 32});

  final int depth;
  final double height;

  @override
  Widget build(BuildContext context) {
    if (depth <= 0) return const SizedBox.shrink();
    final color = Theme.of(context).colorScheme.primary;
    return Padding(
      padding: const EdgeInsetsDirectional.only(end: 10),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < depth; i++)
            Container(
              width: 3,
              height: height,
              margin: const EdgeInsetsDirectional.only(end: 3),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.35 + 0.65 * (i + 1) / depth),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
        ],
      ),
    );
  }
}

/// A filter of goals by status, as a button that drops down every
/// status, each with a check: [statuses] those shown.
class GoalStatusFilter extends StatelessWidget {
  const GoalStatusFilter({
    super.key,
    required this.statuses,
    required this.onChanged,
  });

  final Set<String> statuses;
  final ValueChanged<Set<String>> onChanged;

  @override
  Widget build(BuildContext context) => PopupMenuButton<String>(
    tooltip: 'Show goals by status',
    icon: Icon(
      statuses.length == goalStatuses.length ||
              (statuses.length == 2 &&
                  statuses.containsAll(const {'inactive', 'active'}))
          ? Icons.filter_list
          : Icons.filter_list_alt,
    ),
    itemBuilder: (context) => [
      for (final MapEntry(key: status, value: label) in goalStatuses.entries)
        CheckedPopupMenuItem(
          value: status,
          checked: statuses.contains(status),
          child: Text(label),
        ),
    ],
    onSelected: (status) {
      final next = {...statuses};
      if (!next.remove(status)) next.add(status);
      if (next.isNotEmpty) onChanged(next);
    },
  );
}
