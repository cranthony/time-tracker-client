import 'package:flutter/material.dart';

import '../models/event.dart';
import '../models/goal.dart';
import '../models/time_split.dart';
import 'color_picker.dart';
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

/// [day]'s time by goal: the [top] goals with the most, then the rest
/// together, then events with no goals, then the time with nothing
/// scheduled. With [topLevel], a goal's time counts toward the top-level
/// goal it's under, once per event however many of its goals are.
List<SummarySlice> goalShares(
  List<Event> events,
  DateTime day,
  Map<String, Goal> goals, {
  bool topLevel = false,
  int top = 3,
}) {
  final names = <String, String?>{
    for (final event in events)
      for (final (i, id) in event.goalIds.indexed)
        id: i < event.goalNames.length ? event.goalNames[i] : null,
  };
  String topLevelOf(String id) {
    final seen = {id};
    var at = id;
    for (
      var parent = goals[at]?.parentId;
      parent != null && goals.containsKey(parent) && seen.add(parent);
      parent = goals[at]?.parentId
    ) {
      at = parent;
    }
    return at;
  }

  const none = '';
  final time = _timeBy(
    events,
    day,
    (event) => event.goalIds.map(topLevel ? topLevelOf : (id) => id),
    none,
  );
  final unscheduled = time.remove(null);
  final noGoal = time.remove(none);
  return [
    ...topShares(
      {for (final MapEntry(:key, :value) in time.entries) ?key: value},
      (id, time) => SummarySlice(
        goals[id]?.name ?? names[id] ?? id,
        parseColor(goals[id]?.effectiveColor) ??
            priorityColor(goals[id]?.effectivePriority),
        time,
      ),
      top: top,
    ),
    if (noGoal != null) SummarySlice('No goal', noGoalColor, noGoal),
    if (unscheduled != null) SummarySlice('Unscheduled', null, unscheduled),
  ];
}

/// A day's time at a glance, above its timeline: its share for each
/// priority, for the top goals, and for the top-level goals they're
/// under, and the time with nothing scheduled. Swiping it, or tapping a
/// title, turns between them, its chevron folds it away, and the button
/// by that turns its percentages into durations and back.
class DaySummary extends StatelessWidget {
  const DaySummary({
    super.key,
    required this.events,
    required this.day,
    required this.goals,
    this.initialPage = 0,
    this.collapsed = false,
    this.onCollapsed,
    this.durations = false,
    this.onDurations,
  });

  final List<Event> events;
  final DateTime day;
  final Map<String, Goal> goals;
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
    titles: const ['Priorities', 'Goals', 'Top-level goals'],
    initialPage: initialPage,
    collapsed: collapsed,
    onCollapsed: onCollapsed,
    durations: durations,
    onDurations: onDurations,
    pages: [
      for (final slices in [
        priorityShares(events, day),
        goalShares(events, day, goals),
        goalShares(events, day, goals, topLevel: true),
      ])
        SummaryBar.single(slices: slices),
    ],
  );
}
