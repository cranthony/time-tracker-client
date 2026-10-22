import 'package:flutter/material.dart';

import '../models/event.dart';
import '../models/goal.dart';
import '../models/plan_action.dart';
import '../models/time_split.dart';
import 'color_picker.dart';
import 'plan_summaries.dart';
import 'time_summary.dart';

/// [day]'s time, from its midnight to the next, by [keysOf]: see
/// [timeBy].
Map<K?, Duration> _timeBy<K>(
  List<Event> events,
  DateTime day,
  Iterable<K> Function(Event) keysOf,
  K none,
) => timeBy(
  events,
  day,
  DateTime(day.year, day.month, day.day + 1),
  keysOf,
  none,
);

/// [day]'s time, from its midnight to the next, by [partsOf]: see
/// [timeByParts].
Map<K?, Duration> _timeByParts<K>(
  List<Event> events,
  DateTime day,
  Map<K, double> Function(Event) partsOf,
  K none,
) => timeByParts(
  events,
  day,
  DateTime(day.year, day.month, day.day + 1),
  partsOf,
  none,
);

/// [day]'s time by priority, highest first, then the time with nothing
/// scheduled. Events with none count as [defaultPriority], as the
/// timeline shows them.
List<SummarySlice> priorityShares(List<Event> events, DateTime day) {
  final time = _timeBy(
    events,
    day,
    (event) => [event.effectivePriority ?? defaultPriority],
    defaultPriority,
  );
  final unscheduled = time.remove(null);
  return [
    for (final p in time.keys.whereType<int>().toList()..sort())
      SummarySlice('P$p', priorityColor(p), time[p]!),
    if (unscheduled != null) SummarySlice('Unscheduled', null, unscheduled),
  ];
}

/// [day]'s time by action: the [top] actions with the most, then the rest
/// together, then events with no actions (and what an event's actions'
/// shares leave), then the time with nothing scheduled. Each event's time
/// goes to its actions as their shares say ([Event.actionFractions]).
List<SummarySlice> actionShares(
  List<Event> events,
  DateTime day,
  Map<String, PlanAction> actions, {
  int top = 3,
}) {
  final names = <String, String?>{
    for (final event in events)
      for (final (i, id) in event.actionIds.indexed)
        id: i < event.actionNames.length ? event.actionNames[i] : null,
  };
  const none = '';
  final time = _timeByParts(
    events,
    day,
    (event) => event.actionFractions(),
    none,
  );
  final unscheduled = time.remove(null);
  final noAction = time.remove(none);
  return [
    ...topShares(
      {for (final MapEntry(:key, :value) in time.entries) ?key: value},
      (id, time) => SummarySlice(
        actions[id]?.name ?? names[id] ?? id,
        parseColor(actions[id]?.effectiveColor) ??
            priorityColor(actions[id]?.effectivePriority),
        time,
      ),
      top: top,
    ),
    if (noAction != null) SummarySlice('No action', noActionColor, noAction),
    if (unscheduled != null) SummarySlice('Unscheduled', null, unscheduled),
  ];
}

/// [day]'s time by top-level goal: the [top] goals with the most, then
/// the rest together, then events toward no goal (and what an event's
/// goals' shares leave), then the time with nothing scheduled. Each
/// event's time goes to the top-level goals it's for, each its share with
/// its sub-goals' ([topLevelFractions]), as the Goals pane splits it.
List<SummarySlice> goalShares(
  List<Event> events,
  DateTime day,
  List<Goal> goals, {
  int top = 3,
}) {
  final tree = GoalTree(goals);
  const none = '';
  final time = _timeByParts(
    events,
    day,
    (event) =>
        topLevelFractions(event.goals, event.end.difference(event.start), tree),
    none,
  );
  final unscheduled = time.remove(null);
  final noGoal = time.remove(none);
  return [
    ...topShares(
      {for (final MapEntry(:key, :value) in time.entries) ?key: value},
      (id, time) => SummarySlice(
        switch (tree[id]) {
          final goal? => goalTitle(goal),
          null => id,
        },
        colorFor(id),
        time,
      ),
      top: top,
      others: 'goals',
    ),
    if (noGoal != null && noGoal > Duration.zero)
      SummarySlice('No goal', noActionColor, noGoal),
    if (unscheduled != null) SummarySlice('Unscheduled', null, unscheduled),
  ];
}

/// A day's time at a glance, above its timeline: its share for the top
/// actions, for the top-level goals, and for each priority, in that
/// order, and the time with nothing scheduled. Swiping it, or tapping a
/// title, turns between them, its chevron folds it away, and the button
/// by that turns its percentages into durations and back.
class DaySummary extends StatelessWidget {
  const DaySummary({
    super.key,
    required this.events,
    required this.day,
    required this.actions,
    this.goals = const [],
    this.initialPage = 0,
    this.collapsed = false,
    this.onCollapsed,
    this.durations = false,
    this.onDurations,
  });

  final List<Event> events;
  final DateTime day;
  final Map<String, PlanAction> actions;

  /// The goals, for its time by top-level goal.
  final List<Goal> goals;
  final int initialPage;

  /// Whether it's folded away, by its chevron; with no [onCollapsed],
  /// there's no chevron.
  final bool collapsed;
  final ValueChanged<bool>? onCollapsed;

  /// Whether it shows durations, rather than percentages; with no
  /// [onDurations], there's no button to change it.
  final bool durations;
  final ValueChanged<bool>? onDurations;

  @override
  Widget build(BuildContext context) => TimeSummary(
    titles: const ['Actions', 'Goals', 'Priorities'],
    initialPage: initialPage,
    collapsed: collapsed,
    onCollapsed: onCollapsed,
    durations: durations,
    onDurations: onDurations,
    pages: [
      for (final slices in [
        actionShares(events, day, actions),
        goalShares(events, day, goals),
        priorityShares(events, day),
      ])
        SummaryBar.single(slices: slices),
    ],
  );
}
