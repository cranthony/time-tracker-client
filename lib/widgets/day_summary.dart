import 'package:flutter/material.dart';

import '../models/event.dart';
import '../models/goal.dart';
import 'color_picker.dart';
import 'time_summary.dart';

/// How [day], from its midnight to the next, is spent among [events]: for
/// each stretch of it, the events then, each with an even part of it. The
/// stretches with no events are null's.
Map<Event?, Duration> _timeByEvent(List<Event> events, DateTime day) {
  final next = DateTime(day.year, day.month, day.day + 1);
  DateTime clip(DateTime t) =>
      t.isBefore(day) ? day : (t.isAfter(next) ? next : t);
  final shown = [
    for (final event in events)
      if (!event.isCancelled && clip(event.end).isAfter(clip(event.start)))
        event,
  ];
  final edges = {
    day,
    next,
    for (final event in shown) ...[clip(event.start), clip(event.end)],
  }.toList()..sort();
  final time = <Event?, Duration>{};
  for (var i = 0; i + 1 < edges.length; i++) {
    final (from, to) = (edges[i], edges[i + 1]);
    final during = [
      for (final event in shown)
        if (!event.start.isAfter(from) && !event.end.isBefore(to)) event,
    ];
    final length = to.difference(from);
    if (during.isEmpty) time[null] = (time[null] ?? Duration.zero) + length;
    for (final event in during) {
      time[event] = (time[event] ?? Duration.zero) + length ~/ during.length;
    }
  }
  return time;
}

/// [day]'s time by what each event counts toward, as [keysOf] says, an
/// event's time split evenly between its keys: an event with none counts
/// toward [none]. The time with no events is null's.
Map<K?, Duration> _timeBy<K>(
  List<Event> events,
  DateTime day,
  Iterable<K> Function(Event) keysOf,
  K none,
) {
  final time = <K?, Duration>{};
  for (final MapEntry(key: event, value: length) in _timeByEvent(
    events,
    day,
  ).entries) {
    final keys = event == null ? {null} : keysOf(event).toSet();
    if (keys.isEmpty) keys.add(none);
    for (final key in keys) {
      time[key] = (time[key] ?? Duration.zero) + length ~/ keys.length;
    }
  }
  return time;
}

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
      parent != null &&
          parent != overallGoalId &&
          goals.containsKey(parent) &&
          seen.add(parent);
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
/// title, turns between them, and its chevron folds it away.
class DaySummary extends StatelessWidget {
  const DaySummary({
    super.key,
    required this.events,
    required this.day,
    required this.goals,
    this.initialPage = 0,
    this.collapsed = false,
    this.onCollapsed,
  });

  final List<Event> events;
  final DateTime day;
  final Map<String, Goal> goals;
  final int initialPage;

  /// Whether it's folded away, by its chevron; with no [onCollapsed],
  /// there's no chevron.
  final bool collapsed;
  final ValueChanged<bool>? onCollapsed;

  @override
  Widget build(BuildContext context) => TimeSummary(
    titles: const ['Priorities', 'Goals', 'Top-level goals'],
    initialPage: initialPage,
    collapsed: collapsed,
    onCollapsed: onCollapsed,
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
