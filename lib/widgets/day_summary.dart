import 'package:flutter/material.dart';

import '../models/event.dart';
import '../models/plan_action.dart';
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

/// [day]'s time by action: the [top] actions with the most, then the rest
/// together, then events with no actions, then the time with nothing
/// scheduled. With [topLevel], an action's time counts toward the top-level
/// action it's under, once per event however many of its actions are.
List<SummarySlice> actionShares(
  List<Event> events,
  DateTime day,
  Map<String, PlanAction> actions, {
  bool topLevel = false,
  int top = 3,
}) {
  final names = <String, String?>{
    for (final event in events)
      for (final (i, id) in event.actionIds.indexed)
        id: i < event.actionNames.length ? event.actionNames[i] : null,
  };
  String topLevelOf(String id) {
    final seen = {id};
    var at = id;
    for (
      var parent = actions[at]?.parentId;
      parent != null && actions.containsKey(parent) && seen.add(parent);
      parent = actions[at]?.parentId
    ) {
      at = parent;
    }
    return at;
  }

  const none = '';
  final time = _timeBy(
    events,
    day,
    (event) => event.actionIds.map(topLevel ? topLevelOf : (id) => id),
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

/// A day's time at a glance, above its timeline: its share for each
/// priority, for the top actions, and for the top-level actions they're
/// under, and the time with nothing scheduled. Swiping it, or tapping a
/// title, turns between them, its chevron folds it away, and the button
/// by that turns its percentages into durations and back.
class DaySummary extends StatelessWidget {
  const DaySummary({
    super.key,
    required this.events,
    required this.day,
    required this.actions,
    this.initialPage = 0,
    this.collapsed = false,
    this.onCollapsed,
    this.durations = false,
    this.onDurations,
  });

  final List<Event> events;
  final DateTime day;
  final Map<String, PlanAction> actions;
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
    titles: const ['Priorities', 'Actions', 'Top-level groups'],
    initialPage: initialPage,
    collapsed: collapsed,
    onCollapsed: onCollapsed,
    durations: durations,
    onDurations: onDurations,
    pages: [
      for (final slices in [
        priorityShares(events, day),
        actionShares(events, day, actions),
        actionShares(events, day, actions, topLevel: true),
      ])
        SummaryBar.single(slices: slices),
    ],
  );
}
