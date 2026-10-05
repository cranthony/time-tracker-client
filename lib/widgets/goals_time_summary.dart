import 'package:flutter/material.dart';

import '../models/goal.dart';
import 'color_picker.dart';
import 'time_summary.dart';

/// A goal's minutes in the last 24 hours, or 7 days with [week], through
/// goals with [statuses]: its own and its sub-goals'.
int _minutes(Goal goal, Set<String> statuses, bool week) {
  final (day, days) =
      goal.timeFor(statuses) ?? (goal.minutes24h ?? 0, goal.minutes7d ?? 0);
  return week ? days : day;
}

/// A window's minutes: the last 24 hours, or 7 days with [week].
int _window(bool week) => week ? 7 * 24 * 60 : 24 * 60;

/// The last 24 hours', or 7 days' with [week], time by the goals shown,
/// [visible]: the [top] with the most, the rest together, then the rest
/// of the window, not on goals. A goal's time goes to the deepest of it
/// and its ancestors that's shown, so a collapsed goal has its sub-goals'
/// and an expanded one only its own. [onGoals] is the time on any goal
/// shown, each event once: the shares are scaled down to it if they come
/// to more, as an event with goals in more than one place counts in each.
List<SummarySlice> visibleGoalShares(
  List<Goal> visible,
  Map<String?, Goal> byId,
  Set<String> statuses, {
  required bool week,
  required int onGoals,
  int top = 3,
}) {
  final shown = {for (final goal in visible) goal.id};
  final time = <Goal, int>{
    for (final goal in visible) goal: _minutes(goal, statuses, week),
  };
  // Each goal's time, taken from the nearest ancestor shown, which keeps
  // only the rest.
  for (final goal in visible) {
    final seen = {goal.id};
    var parent = byId[goal.parentId];
    while (parent != null &&
        !shown.contains(parent.id) &&
        seen.add(parent.id)) {
      parent = byId[parent.parentId];
    }
    if (parent != null && time.containsKey(parent)) {
      time[parent] = time[parent]! - _minutes(goal, statuses, week);
    }
  }
  final shares = topShares(
    {
      for (final MapEntry(:key, :value) in time.entries)
        if (value > 0) key: Duration(minutes: value),
    },
    (goal, time) => SummarySlice(
      goalName(goal),
      parseColor(goal.effectiveColor) ?? priorityColor(goal.effectivePriority),
      time,
    ),
    top: top,
  );
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
    if (rest > 0) SummarySlice('Not on actions', null, Duration(minutes: rest)),
  ];
}

/// The last 24 hours', or 7 days' with [week], time by priority, as the
/// server splits it ([split]): highest first, then the rest, with no
/// priority.
List<SummarySlice> windowPriorityShares(
  List<PriorityMinutes> split, {
  required bool week,
}) {
  int minutes(PriorityMinutes part) => week ? part.minutes7d : part.minutes24h;
  final prioritized = [
    for (final part in split)
      if (part.priority != null && minutes(part) > 0) part,
  ]..sort((a, b) => a.priority!.compareTo(b.priority!));
  final none = split
      .where((part) => part.priority == null)
      .fold(0, (sum, part) => sum + minutes(part));
  return [
    for (final part in prioritized)
      SummarySlice(
        'P${part.priority}',
        priorityColor(part.priority),
        Duration(minutes: minutes(part)),
      ),
    if (none > 0) SummarySlice('No priority', null, Duration(minutes: none)),
  ];
}

/// The last 24 hours and 7 days at a glance, under the Goals heading:
/// each window's bar, one over the other, split by the goals shown, or by
/// priority. Swiping it, or tapping a title, turns between the two, its
/// chevron folds it away, and the button by that turns its percentages
/// into durations and back.
class GoalsTimeSummary extends StatelessWidget {
  const GoalsTimeSummary({
    super.key,
    required this.visible,
    required this.byId,
    required this.statuses,
    required this.onGoals,
    this.byPriority,
    this.initialPage = 0,
    this.collapsed = false,
    this.onCollapsed,
    this.durations = false,
    this.onDurations,
  });

  /// The goals shown, as the page shows them: by status, and not under
  /// a collapsed goal.
  final List<Goal> visible;

  /// Every goal, by id, for the ancestors of [visible].
  final Map<String?, Goal> byId;

  /// The statuses the Goals page shows: time through other goals isn't
  /// counted, as the page doesn't count it.
  final Set<String> statuses;

  /// The minutes on goals shown, each event once, in the last 24 hours
  /// and 7 days.
  final (int, int) onGoals;

  /// The windows by priority, as [GoalList.minutesByPriority] gives
  /// them; null leaves that page out.
  final List<PriorityMinutes>? byPriority;
  final int initialPage;
  final bool collapsed;
  final ValueChanged<bool>? onCollapsed;

  /// Whether it shows durations, rather than percentages; with no
  /// [onDurations], there's no button to change it.
  final bool durations;
  final ValueChanged<bool>? onDurations;

  @override
  Widget build(BuildContext context) {
    final (day, week) = onGoals;
    final byPriority = this.byPriority;
    List<SummarySlice> goals(bool week, int onGoals) => visibleGoalShares(
      visible,
      byId,
      statuses,
      week: week,
      onGoals: onGoals,
    );
    return TimeSummary(
      titles: ['Visible actions', if (byPriority != null) 'By priority'],
      initialPage: initialPage,
      collapsed: collapsed,
      onCollapsed: onCollapsed,
      durations: durations,
      onDurations: onDurations,
      pages: [
        SummaryBar(
          rows: [('24h', goals(false, day)), ('7d', goals(true, week))],
        ),
        if (byPriority != null)
          SummaryBar(
            rows: [
              ('24h', windowPriorityShares(byPriority, week: false)),
              ('7d', windowPriorityShares(byPriority, week: true)),
            ],
          ),
      ],
    );
  }
}
