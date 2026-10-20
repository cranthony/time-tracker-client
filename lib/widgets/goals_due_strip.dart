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
  return [
    for (final g in goals)
      if (g.deadline?.trim().split('T').first == date && g.due != null) g,
  ]..sort(_byStatus(tree ?? GoalTree(goals)));
}

/// The goals overdue on [day], from [goals]: the open ones -- active or
/// inactive -- due before it, in the order [goalsDueOn] gives: active
/// ones first, then each status's as [byPriority] has them in [tree] (by
/// default, [goals] themselves), so, at a priority, the longest overdue
/// first.
List<Goal> overdueGoalsOn(
  Iterable<Goal> goals,
  DateTime day, [
  GoalTree? tree,
]) {
  final date = deadlineOf(day);
  return [
    for (final g in goals)
      if (g.open)
        if (dueDay(g) case final due? when due.compareTo(date) < 0) g,
  ]..sort(_byStatus(tree ?? GoalTree(goals)));
}

/// Orders goals by status, then as [order] compares them.
Comparator<Goal> _byStatus(GoalTree order) => (a, b) {
  final byStatus = _rank(a).compareTo(_rank(b));
  return byStatus != 0 ? byStatus : order.compare(a, b);
};

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
/// obsolete. After them, the [overdue] ones -- still open past their
/// day -- each saying the day it was due, so they stay in sight until
/// they're done or retargeted; only on today or later, though, not on a
/// past day. Tapping a pill calls [onTap].
class GoalsDueStrip extends StatelessWidget {
  const GoalsDueStrip({
    super.key,
    required this.goals,
    required this.collapsed,
    required this.onCollapsed,
    this.overdue = const [],
    this.day,
    this.today,
    this.tree,
    this.spent,
    this.onTap,
  });

  /// The day's, as [goalsDueOn] gives them.
  final List<Goal> goals;

  /// The open ones due before the day, as [overdueGoalsOn] gives them.
  final List<Goal> overdue;

  /// The day shown and today, for whether [overdue] is shown: it isn't on
  /// a day before today. Shown whenever either is unknown.
  final DateTime? day;
  final DateTime? today;
  final bool collapsed;
  final ValueChanged<bool> onCollapsed;

  /// Every goal, for each one's parents; none, if null.
  final GoalTree? tree;

  /// The time spent toward each goal, by id, for what's left of each
  /// one's expected time; none is said, if null.
  final Map<String, Duration>? spent;
  final ValueChanged<Goal>? onTap;

  /// [overdue], on today or later; nothing on a past day.
  List<Goal> get _late => switch ((day, today)) {
    (final d?, final t?) when deadlineOf(d).compareTo(deadlineOf(t)) < 0 =>
      const [],
    _ => overdue,
  };

  @override
  Widget build(BuildContext context) {
    final late = _late;
    if (goals.isEmpty && late.isEmpty) return const SizedBox.shrink();
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
    final counts = [
      if (goals.isNotEmpty)
        '${_count(goals.length)} due'
            '${open < goals.length ? ' ($open open)' : ''}',
      if (late.isNotEmpty)
        goals.isEmpty
            ? '${_count(late.length)} overdue'
            : '${late.length} overdue',
    ];
    _Pill pill(Goal g, {bool late = false}) => _Pill(
      goal: g,
      path: tree?.pathOf(g.id) ?? g.path,
      dueDay: late ? _dueDayLabel(context, g) : null,
      left: g.closed || spent == null ? null : leftLabel(g, spent![g.id]),
      onTap: onTap == null ? null : () => onTap!(g),
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
                        '${counts.join(', ')} · '
                        '${[...goals, ...late].map(goalTitle).join(', ')}',
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
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (goals.isNotEmpty)
                              Wrap(
                                spacing: 6,
                                runSpacing: 6,
                                children: [for (final g in goals) pill(g)],
                              ),
                            if (late.isNotEmpty)
                              Padding(
                                padding: EdgeInsets.only(
                                  top: goals.isEmpty ? 0 : 6,
                                ),
                                child: Wrap(
                                  spacing: 6,
                                  runSpacing: 6,
                                  crossAxisAlignment: WrapCrossAlignment.center,
                                  children: [
                                    Text(
                                      'Overdue',
                                      style: theme.textTheme.labelSmall
                                          ?.copyWith(color: colors.error),
                                    ),
                                    for (final g in late) pill(g, late: true),
                                  ],
                                ),
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

  /// The day [goal] was due, short: "Oct 17".
  static String _dueDayLabel(BuildContext context, Goal goal) {
    final due = goal.due!;
    final day = deadlineHasTime(goal.deadline)
        ? due
        : due.subtract(const Duration(days: 1));
    return MaterialLocalizations.of(context).formatShortMonthDay(day);
  }
}

/// [goal] as a pill: its title, its time if it's due at one, and what's
/// [left] of its expected time, or, closed, struck through with what it
/// came to. Overdue -- [dueDay] given -- it's in the error color and says
/// the day it was due instead of a time. Its parents are in its tooltip.
class _Pill extends StatelessWidget {
  const _Pill({
    required this.goal,
    required this.path,
    this.dueDay,
    this.left,
    this.onTap,
  });

  final Goal goal;
  final List<String> path;

  /// The day it was due, when it's overdue; null when it's the day's own.
  final String? dueDay;
  final String? left;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final closed = goal.closed;
    final done = goal.status == 'done';
    final overdue = dueDay != null;
    final ink = overdue
        ? colors.onErrorContainer
        : closed
        ? colors.onSurfaceVariant
        : colors.onSecondaryContainer;
    final time = !overdue && deadlineHasTime(goal.deadline)
        ? MaterialLocalizations.of(context)
              .formatTimeOfDay(TimeOfDay.fromDateTime(goal.due!))
        : null;
    final title = goalTitle(goal);
    final status = closed ? goalStatuses[goal.status]!.toLowerCase() : null;
    final label = [
      title,
      if (overdue)
        'due $dueDay, overdue'
      else if (time != null)
        'due at $time'
      else
        'due by the end of the day',
      ?left,
      ?status,
    ].join(', ');
    final pill = Semantics(
      label: label,
      button: onTap != null,
      excludeSemantics: true,
      child: Material(
        color: overdue
            ? colors.errorContainer
            : closed
            ? Colors.transparent
            : colors.secondaryContainer,
        shape: StadiumBorder(
          side: BorderSide(
            color: overdue
                ? colors.error
                : closed
                ? colors.outlineVariant
                : colors.secondary,
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
                        if (overdue) TextSpan(text: '  ·  due $dueDay'),
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
