import 'package:flutter/material.dart';

import '../models/goal.dart';
import 'color_picker.dart';
import 'day_summary.dart';

/// How [GoalsTimeSummary] lays itself out. A mockup's choice, for now.
enum GoalsSummaryStyle {
  /// Both windows' bars, one over the other, with one legend.
  stacked,

  /// One page for each window, swiped between.
  windows,

  /// One page for each breakdown, swiped between, with a switch for the
  /// window.
  toggle,
}

/// Mockup only: which [GoalsSummaryStyle] the Goals page shows.
var goalsSummaryStyle = GoalsSummaryStyle.stacked;

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

/// The same by priority: each goal's own time, apart from its
/// sub-goals', counted toward its priority. Only roughly right: an
/// event's own priority isn't known here.
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
          'P$p',
          priorityColor(p),
          Duration(minutes: byPriority[p]!),
        ),
    ],
    onGoals,
    week,
  );
}

/// The time on goals in the last 24 hours and 7 days, as the Goals page
/// counts it, at a glance: by top-level goal, or by priority, and the
/// rest of the time.
class GoalsTimeSummary extends StatefulWidget {
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
  State<GoalsTimeSummary> createState() => _GoalsTimeSummaryState();
}

class _GoalsTimeSummaryState extends State<GoalsTimeSummary> {
  /// For [GoalsSummaryStyle.toggle]: whether it shows the last 7 days.
  var _week = false;

  List<SummarySlice> _topLevel(bool week) => topLevelShares(
    widget.goals,
    widget.statuses,
    week: week,
    onGoals: week ? widget.onGoals.$2 : widget.onGoals.$1,
  );

  List<SummarySlice> _priorities(bool week) => goalPriorityShares(
    widget.goals,
    widget.statuses,
    week: week,
    onGoals: week ? widget.onGoals.$2 : widget.onGoals.$1,
  );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      color: theme.colorScheme.surfaceContainerLow,
      clipBehavior: Clip.antiAlias,
      child: switch (goalsSummaryStyle) {
        GoalsSummaryStyle.stacked => _Stacked(
          day: _topLevel(false),
          week: _topLevel(true),
        ),
        GoalsSummaryStyle.windows => SummaryPages(
          titles: const ['Last 24 hours', 'Last 7 days'],
          initialPage: widget.initialPage,
          pages: [_topLevel(false), _topLevel(true)],
        ),
        GoalsSummaryStyle.toggle => SummaryPages(
          titles: const ['Top-level goals', 'Priorities'],
          initialPage: widget.initialPage,
          pages: [_topLevel(_week), _priorities(_week)],
          trailing: SegmentedButton<bool>(
            showSelectedIcon: false,
            style: SegmentedButton.styleFrom(
              visualDensity: const VisualDensity(horizontal: -4, vertical: -4),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              textStyle: theme.textTheme.labelSmall,
              padding: const EdgeInsets.symmetric(horizontal: 6),
            ),
            segments: const [
              ButtonSegment(value: false, label: Text('24h')),
              ButtonSegment(value: true, label: Text('7d')),
            ],
            selected: {_week},
            onSelectionChanged: (picked) =>
                setState(() => _week = picked.single),
          ),
        ),
      },
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
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Top-level goals',
                style: theme.textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              Text('24h · 7d', style: faint),
            ],
          ),
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
