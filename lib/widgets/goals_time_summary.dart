import 'package:flutter/material.dart';

import '../models/goal.dart';
import 'color_picker.dart';
import 'day_summary.dart';

/// A goal's minutes in the last 24 hours, or 7 days with [week], through
/// goals with [statuses].
int _minutes(Goal goal, Set<String> statuses, bool week) {
  final (day, days) =
      goal.timeFor(statuses) ?? (goal.minutes24h ?? 0, goal.minutes7d ?? 0);
  return week ? days : day;
}

/// A window's minutes: the last 24 hours, or 7 days with [week].
int _window(bool week) => week ? 7 * 24 * 60 : 24 * 60;

/// [shares] of the time on goals, [onGoals] minutes, scaled down to it if
/// they come to more (an event with goals in more than one tree counts in
/// each), then the rest of the window, not on goals.
List<SummarySlice> _fill(List<SummarySlice> shares, int onGoals, bool week) {
  final sum = shares.fold(0, (sum, s) => sum + s.time.inMinutes);
  final scale = sum > onGoals && sum > 0 ? onGoals / sum : 1.0;
  final rest = _window(week) - onGoals;
  return [
    for (final share in shares)
      SummarySlice(
        share.label,
        share.color,
        Duration(minutes: (share.time.inMinutes * scale).round()),
      ),
    if (rest > 0) SummarySlice('Not on goals', null, Duration(minutes: rest)),
  ];
}

/// The last 24 hours', or 7 days' with [week], time by top-level goal:
/// the [top] with the most, the rest together, then the time not on
/// goals. [onGoals] is the time on any goal, each event once.
List<SummarySlice> topLevelShares(
  List<Goal> goals,
  Set<String> statuses, {
  required bool week,
  required int onGoals,
  int top = 3,
}) {
  final ranked = [
    for (final goal in goals)
      if (!goal.isOverall &&
          (goal.parentId == null || goal.parentId == overallGoalId) &&
          _minutes(goal, statuses, week) > 0)
        goal,
  ]..sort((a, b) => _minutes(b, statuses, week) - _minutes(a, statuses, week));
  final rest = ranked
      .skip(top)
      .fold(0, (sum, goal) => sum + _minutes(goal, statuses, week));
  return _fill(
    [
      for (final goal in ranked.take(top))
        SummarySlice(
          goalName(goal),
          parseColor(goal.effectiveColor) ??
              priorityColor(goal.effectivePriority),
          Duration(minutes: _minutes(goal, statuses, week)),
        ),
      if (rest > 0)
        SummarySlice(
          '${ranked.length - top} other goals',
          otherGoalsColor,
          Duration(minutes: rest),
        ),
    ],
    onGoals,
    week,
  );
}

/// The same by goal priority: each goal's own time, apart from its
/// sub-goals', counted toward the goal's priority, whatever its events'
/// own priorities.
List<SummarySlice> goalPriorityShares(
  List<Goal> goals,
  Set<String> statuses, {
  required bool week,
  required int onGoals,
}) {
  final byPriority = <int, int>{};
  for (final goal in goals) {
    if (goal.isOverall) continue;
    final own =
        _minutes(goal, statuses, week) -
        goals
            .where((sub) => sub.parentId == goal.id)
            .fold<int>(0, (sum, sub) => sum + _minutes(sub, statuses, week));
    if (own <= 0) continue;
    final p = goal.effectivePriority ?? defaultPriority;
    byPriority[p] = (byPriority[p] ?? 0) + own;
  }
  return _fill(
    [
      for (final p in byPriority.keys.toList()..sort())
        SummarySlice(
          'P$p goals',
          priorityColor(p),
          Duration(minutes: byPriority[p]!),
        ),
    ],
    onGoals,
    week,
  );
}

/// The time on goals in the last 24 hours and 7 days, as the Goals page
/// counts it, at a glance: each window's bar, one over the other, split
/// by top-level goal, or by goal priority, and the rest of the window,
/// not on goals. Swiping it, or tapping a title, turns between the two.
class GoalsTimeSummary extends StatelessWidget {
  const GoalsTimeSummary({
    super.key,
    required this.goals,
    required this.statuses,
    required this.onGoals,
    this.initialPage = 0,
  });

  final List<Goal> goals;

  /// The statuses the Goals page shows: time through other goals isn't
  /// counted, as the page doesn't count it.
  final Set<String> statuses;

  /// The minutes on goals shown, each event once, in the last 24 hours
  /// and 7 days.
  final (int, int) onGoals;
  final int initialPage;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (day, week) = onGoals;
    return Card(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      color: theme.colorScheme.surfaceContainerLow,
      clipBehavior: Clip.antiAlias,
      child: SummaryPages(
        titles: const ['Top-level goals', 'Goal priorities'],
        initialPage: initialPage,
        trailing: Text(
          '24h · 7d',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        pages: [
          _Stacked(
            day: topLevelShares(goals, statuses, week: false, onGoals: day),
            week: topLevelShares(goals, statuses, week: true, onGoals: week),
          ),
          _Stacked(
            day: goalPriorityShares(goals, statuses, week: false, onGoals: day),
            week: goalPriorityShares(
              goals,
              statuses,
              week: true,
              onGoals: week,
            ),
          ),
        ],
      ),
    );
  }
}

/// The last 24 hours' bar over the last 7 days', and one legend for both:
/// each share's percentage of each.
class _Stacked extends StatelessWidget {
  const _Stacked({required this.day, required this.week});

  final List<SummarySlice> day;
  final List<SummarySlice> week;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final outline = theme.colorScheme.outlineVariant;
    final small = theme.textTheme.bodySmall;
    final faint = small?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    int total(List<SummarySlice> slices) =>
        slices.fold(0, (sum, s) => sum + s.time.inSeconds);
    String percent(List<SummarySlice> slices, String label) {
      final slice = slices.where((s) => s.label == label).firstOrNull;
      if (slice == null) return '–';
      return '${(100 * slice.time.inSeconds / total(slices)).round()}%';
    }

    Widget bar(String label, List<SummarySlice> slices) => Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        children: [
          SizedBox(width: 30, child: Text(label, style: faint)),
          Expanded(
            child: Container(
              height: 14,
              decoration: BoxDecoration(
                border: Border.all(color: outline),
                borderRadius: BorderRadius.circular(7),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: Row(
                  children: [
                    for (final (i, slice) in slices.indexed)
                      Expanded(
                        flex: slice.time.inMinutes,
                        child: Container(
                          margin: EdgeInsets.only(left: i == 0 ? 0 : 1),
                          color: slice.color,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );

    // The week's shares, then any only the day has.
    final labels = [
      for (final slice in week) slice.label,
      for (final slice in day)
        if (!week.any((s) => s.label == slice.label)) slice.label,
    ];
    final colors = {
      for (final slice in [...day, ...week]) slice.label: slice.color,
    };
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          bar('24h', day),
          bar('7d', week),
          const SizedBox(height: 8),
          Wrap(
            spacing: 14,
            runSpacing: 4,
            children: [
              for (final label in labels)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: colors[label],
                        border: colors[label] == null
                            ? Border.all(color: outline, width: 1.5)
                            : null,
                        borderRadius: BorderRadius.circular(2.5),
                      ),
                    ),
                    const SizedBox(width: 5),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 110),
                      child: Text(
                        label,
                        overflow: TextOverflow.ellipsis,
                        style: small,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '${percent(day, label)} · ${percent(week, label)}',
                      style: small?.copyWith(fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
            ],
          ),
        ],
      ),
    );
  }
}
