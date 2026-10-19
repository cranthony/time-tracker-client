import 'package:flutter/material.dart';

import '../models/goal.dart';
import 'goal_icon.dart';
import 'goal_tile.dart';

/// The goals due on [day], from [goals]: by status -- active, inactive,
/// done, missed, then obsolete -- then each status's as [byPriority] has
/// them in [tree] (by default, [goals] themselves): the highest priority
/// first, then those due at a time, by time, then those due by its end,
/// by title.
List<Goal> goalsDueOn(Iterable<Goal> goals, DateTime day, [GoalTree? tree]) {
  final date = deadlineOf(day);
  final order = tree ?? GoalTree(goals);
  return [
    for (final g in goals)
      if (g.deadline?.trim().split('T').first == date && g.due != null) g,
  ]..sort((a, b) {
    final byStatus = _rank(a).compareTo(_rank(b));
    return byStatus != 0 ? byStatus : order.compare(a, b);
  });
}

const _statusOrder = ['active', 'inactive', 'done', 'missed', 'obsolete'];

/// Where [goal]'s status falls in [_statusOrder]; one it doesn't know,
/// after them.
int _rank(Goal goal) => switch (_statusOrder.indexOf(goal.status)) {
  -1 => _statusOrder.length,
  final i => i,
};

/// The goals due on the day shown, above its timeline, so they're in
/// sight wherever it's scrolled to: a pill each, or, [collapsed], one
/// line naming them. An open one with an expected time says what's left
/// of it ([leftLabel]); one that's closed says so: done, missed or
/// obsolete. Tapping a pill calls [onTap].
class GoalsDueStrip extends StatelessWidget {
  const GoalsDueStrip({
    super.key,
    required this.goals,
    required this.collapsed,
    required this.onCollapsed,
    this.tree,
    this.spent,
    this.onTap,
  });

  /// The day's, as [goalsDueOn] gives them.
  final List<Goal> goals;
  final bool collapsed;
  final ValueChanged<bool> onCollapsed;

  /// Every goal, for each one's parents; none, if null.
  final GoalTree? tree;

  /// The time spent toward each goal, by id, for what's left of each
  /// one's expected time; none is said, if null.
  final Map<String, Duration>? spent;
  final ValueChanged<Goal>? onTap;

  @override
  Widget build(BuildContext context) {
    if (goals.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final muted = theme.textTheme.labelMedium?.copyWith(
      color: colors.onSurfaceVariant,
    );
    final open = goals.where((g) => g.open).length;
    final toggle = IconButton(
      visualDensity: VisualDensity.compact,
      tooltip: collapsed ? 'Show goals due' : 'Hide goals due',
      icon: Icon(collapsed ? Icons.expand_more : Icons.expand_less),
      onPressed: () => onCollapsed(!collapsed),
    );
    return Material(
      color: colors.surfaceContainerLow,
      shape: Border(bottom: BorderSide(color: colors.outlineVariant)),
      child: InkWell(
        onTap: collapsed ? () => onCollapsed(false) : null,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 2, 4, 2),
          child: collapsed
              ? Row(
                  children: [
                    GoalIcon(size: 16, color: colors.primary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '${_count(goals.length)} due'
                        '${open < goals.length ? ' ($open open)' : ''} · '
                        '${goals.map(goalTitle).join(', ')}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: muted,
                      ),
                    ),
                    toggle,
                  ],
                )
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 12, right: 8),
                      child: GoalIcon(size: 16, color: colors.primary),
                    ),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            for (final g in goals)
                              _Pill(
                                goal: g,
                                path: tree?.pathOf(g.id) ?? g.path,
                                left: g.closed || spent == null
                                    ? null
                                    : leftLabel(g, spent![g.id]),
                                onTap: onTap == null ? null : () => onTap!(g),
                              ),
                          ],
                        ),
                      ),
                    ),
                    toggle,
                  ],
                ),
        ),
      ),
    );
  }

  static String _count(int n) => '$n goal${n == 1 ? '' : 's'}';
}

/// [goal] as a pill: its title, its time if it's due at one, and what's
/// [left] of its expected time, or, closed, struck through with what it
/// came to. Its parents are in its tooltip.
class _Pill extends StatelessWidget {
  const _Pill({required this.goal, required this.path, this.left, this.onTap});

  final Goal goal;
  final List<String> path;
  final String? left;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final closed = goal.closed;
    final done = goal.status == 'done';
    final ink = closed ? colors.onSurfaceVariant : colors.onSecondaryContainer;
    final time = deadlineHasTime(goal.deadline)
        ? MaterialLocalizations.of(context)
              .formatTimeOfDay(TimeOfDay.fromDateTime(goal.due!))
        : null;
    final title = goalTitle(goal);
    final status = closed ? goalStatuses[goal.status]!.toLowerCase() : null;
    final label = [
      title,
      if (time != null) 'due at $time' else 'due by the end of the day',
      ?left,
      ?status,
    ].join(', ');
    final pill = Semantics(
      label: label,
      button: onTap != null,
      excludeSemantics: true,
      child: Material(
        color: closed ? Colors.transparent : colors.secondaryContainer,
        shape: StadiumBorder(
          side: BorderSide(
            color: closed ? colors.outlineVariant : colors.secondary,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (closed) ...[
                  Icon(done ? Icons.check : Icons.close, size: 14, color: ink),
                  const SizedBox(width: 4),
                ],
                Flexible(
                  child: Text.rich(
                    TextSpan(
                      children: [
                        if (time != null) TextSpan(text: '$time  '),
                        TextSpan(
                          text: title,
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            decoration: closed
                                ? TextDecoration.lineThrough
                                : null,
                          ),
                        ),
                        if (left != null) TextSpan(text: '  ·  $left'),
                      ],
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelMedium?.copyWith(color: ink),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    return path.isEmpty
        ? pill
        : Tooltip(message: [...path, title].join(' › '), child: pill);
  }
}
