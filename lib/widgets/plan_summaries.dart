import 'package:flutter/material.dart';

import '../models/event.dart';
import '../models/facts.dart';
import '../models/plan_action.dart';
import '../models/person.dart';
import '../models/time_split.dart';
import 'color_picker.dart';
import 'time_summary.dart';

/// The time on nothing in particular: no event then.
const _unscheduled = 'Unscheduled';

/// [time]'s shares, as the Plan page's summaries show them: the [top]
/// keys with the most, each as [slice] makes it, then the rest together
/// as "N other [others]", then the time with an event but no key
/// ([none], as [noneLabel]), then the time with no event.
List<SummarySlice> planShares<K>(
  Map<K?, Duration> time, {
  required K none,
  required String noneLabel,
  required SummarySlice Function(K key, Duration time) slice,
  required String others,
  int top = 3,
}) {
  final rest = {...time};
  final unscheduled = rest.remove(null);
  final noKey = rest.remove(none);
  return [
    ...topShares(
      {for (final MapEntry(:key, :value) in rest.entries) key as K: value},
      slice,
      top: top,
      others: others,
    ),
    if (noKey != null && noKey > Duration.zero)
      SummarySlice(noneLabel, noActionColor, noKey),
    if (unscheduled != null && unscheduled > Duration.zero)
      SummarySlice(_unscheduled, null, unscheduled),
  ];
}

/// A color for [id] among [calendarColors], the same each time.
Color colorFor(String id) =>
    calendarColors[id.codeUnits.fold(7, (h, c) => (h * 31 + c) & 0x7fffffff) %
        calendarColors.length];

/// Each action's time, by its id: an event's time split evenly among its
/// actions with any of [statuses], as the summaries split it. Those
/// with none of them count toward "".
(Map<String?, Duration>, Map<String?, Duration>) actionTime(
  List<Event> events,
  SummaryWindow window,
  Map<String?, PlanAction> byId,
  Set<String> statuses,
) => window.split<String>(
  events,
  (event) => [
    for (final id in event.actionIds)
      if (statuses.contains(byId[id]?.status ?? 'active')) id,
  ],
  '',
);

/// Each of [actions]' time, with what's in it, from each action's [time]:
/// an action's own, and a group's, its actions'.
Map<String?, Duration> rolledUp(
  Map<String?, Duration> time,
  Map<String?, PlanAction> byId,
) {
  final total = <String?, Duration>{};
  for (final MapEntry(key: id, value: length) in time.entries) {
    if (id == null || id.isEmpty) continue;
    final seen = <String?>{};
    for (String? at = id; at != null && seen.add(at); at = byId[at]?.parentId) {
      total[at] = (total[at] ?? Duration.zero) + length;
    }
  }
  return total;
}

/// [time] by the actions and groups [visible]: each action's time goes to
/// the nearest of it and the groups it's in that's shown, so a collapsed
/// group has what's in it.
Map<String?, Duration> byVisible(
  Map<String?, Duration> time,
  Map<String?, PlanAction> byId,
  Set<String?> visible,
) {
  final shown = <String?, Duration>{};
  for (final MapEntry(key: id, value: length) in time.entries) {
    String? at = id;
    if (id != null && id.isNotEmpty) {
      final seen = <String?>{};
      while (at != null && !visible.contains(at) && seen.add(at)) {
        at = byId[at]?.parentId;
      }
      // Under nothing shown: with no action, as far as this goes.
      at ??= '';
    }
    shown[at] = (shown[at] ?? Duration.zero) + length;
  }
  return shown;
}

/// An action's or group's share, in its color.
SummarySlice actionSlice(PlanAction? action, String id, Duration time) =>
    SummarySlice(
      action == null ? id : actionName(action),
      parseColor(action?.effectiveColor) ??
          priorityColor(action?.effectivePriority),
      time,
    );

/// [window]'s time by priority: each moment's events' highest, those
/// with none counting as [defaultPriority], as the Events page counts
/// them.
(List<SummarySlice>, List<SummarySlice>) priorityTime(
  List<Event> events,
  SummaryWindow window,
) {
  final (day, week) = window.split<int>(
    events,
    (event) => [event.effectivePriority ?? defaultPriority],
    defaultPriority,
  );
  List<SummarySlice> shares(Map<int?, Duration> time) => [
    for (final p in time.keys.whereType<int>().toList()..sort())
      SummarySlice('P$p', priorityColor(p), time[p]!),
    if (time[null] case final none? when none > Duration.zero)
      SummarySlice(_unscheduled, null, none),
  ];
  return (shares(day), shares(week));
}

/// [window]'s time by who was there: each event's time split evenly
/// among the people with you; those with no one, "With no one".
(List<SummarySlice>, List<SummarySlice>) personTime(
  List<Event> events,
  SummaryWindow window,
  PeopleList people,
) {
  final byId = {for (final p in people.withSelf) p.id: p};
  final (day, week) = window.split<String>(
    events,
    (event) => Facts.fromJson(event.properties['facts'])?.withIds ?? const [],
    '',
  );
  List<SummarySlice> shares(Map<String?, Duration> time) => planShares(
    time,
    none: '',
    noneLabel: 'With no one',
    others: 'people',
    slice: (id, time) => SummarySlice(
      switch (byId[id]) {
        final person? => personName(person),
        null => id,
      },
      colorFor(id),
      time,
    ),
  );
  return (shares(day), shares(week));
}

/// The key for the people in no circle, in [circleTime].
const individuals = '\u0000individuals';

/// [window]'s time by the circles of who was there: each event's time
/// split evenly among their circles, those in none together as
/// "Individuals"; events with no one, "With no one".
(List<SummarySlice>, List<SummarySlice>) circleTime(
  List<Event> events,
  SummaryWindow window,
  PeopleList people,
) {
  final byId = {for (final p in people.withSelf) p.id: p};
  final circles = {for (final c in people.circles) c.id: c};
  final (day, week) = window.split<String>(events, (event) {
    final there =
        Facts.fromJson(event.properties['facts'])?.withIds ?? const [];
    return {
      for (final id in there)
        ...switch (byId[id]?.circleIds) {
          final ids? when ids.any(circles.containsKey) => ids.where(
            circles.containsKey,
          ),
          _ => const [individuals],
        },
    };
  }, '');
  List<SummarySlice> shares(Map<String?, Duration> time) => planShares(
    time,
    none: '',
    noneLabel: 'With no one',
    others: 'circles',
    slice: (id, time) => id == individuals
        ? SummarySlice('Individuals', otherActionsColor, time)
        : SummarySlice(circles[id]?.name ?? id, colorFor(id), time),
  );
  return (shares(day), shares(week));
}

/// [window]'s time by where it was; events with no location, "No
/// location".
(List<SummarySlice>, List<SummarySlice>) locationTime(
  List<Event> events,
  SummaryWindow window,
  Map<String?, String> locationNames,
) {
  final (day, week) = window.split<String>(
    events,
    (event) => [?Facts.fromJson(event.properties['facts'])?.locationId],
    '',
  );
  List<SummarySlice> shares(Map<String?, Duration> time) => planShares(
    time,
    none: '',
    noneLabel: 'No location',
    others: 'locations',
    slice: (id, time) =>
        SummarySlice(locationNames[id] ?? id, colorFor(id), time),
  );
  return (shares(day), shares(week));
}

/// What all the Plan page's summaries measure, and how they're shown:
/// the window, and whether they're folded away or in durations. One
/// for every pane, so moving it on one moves them all.
class SummaryView {
  const SummaryView({
    required this.window,
    required this.lastCompaction,
    required this.dayOffset,
    required this.collapsed,
    required this.durations,
    required this.onDays,
    required this.onForward,
    required this.onCollapsed,
    required this.onDurations,
    this.events,
    this.error,
  });

  final SummaryWindow window;

  /// When notes were last compacted: the window's default end, or start,
  /// [dayOffset] days away. Null if they never were; then it's now.
  final DateTime? lastCompaction;
  final int dayOffset;
  final bool collapsed;
  final bool durations;

  /// Called with how many days from [lastCompaction] to measure from.
  final ValueChanged<int> onDays;
  final ValueChanged<bool> onForward;
  final ValueChanged<bool> onCollapsed;
  final ValueChanged<bool> onDurations;

  /// The events [window] covers, once they're loaded.
  final List<Event>? events;

  /// Why they couldn't be loaded, if they couldn't.
  final Object? error;
}

/// A summary of [view]'s window on one of the Plan page's panes: its
/// [titles] over the [pages] its events make, each a pair of shares, for
/// the 24 hours and the 7 days, with the window's controls. Until the
/// events are in, each page says they're loading.
class PlanSummary extends StatelessWidget {
  const PlanSummary({
    super.key,
    required this.view,
    required this.titles,
    required this.pages,
  });

  final SummaryView view;
  final List<String> titles;
  final List<(List<SummarySlice>, List<SummarySlice>)> Function(
    List<Event> events,
  )
  pages;

  @override
  Widget build(BuildContext context) {
    final (day, week) = view.window.labels;
    final events = view.events;
    return TimeSummary(
      titles: titles,
      collapsed: view.collapsed,
      onCollapsed: view.onCollapsed,
      durations: view.durations,
      onDurations: view.onDurations,
      controls: SummaryWindowBar(view: view),
      pages: [
        if (events != null)
          for (final (dayShares, weekShares) in pages(events))
            SummaryBar(rows: [(day, dayShares), (week, weekShares)])
        else
          for (final _ in titles)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: view.error == null
                  ? const LinearProgressIndicator()
                  : Text(
                      "Couldn't load the events. ${view.error}",
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
            ),
      ],
    );
  }
}

/// Where a summary's window is: back or on from the last compaction, or
/// a day at a time from it, with buttons to move it a day earlier or
/// later, and to measure back or on from it. Tapping its time, moved,
/// brings it back to the last compaction.
class SummaryWindowBar extends StatelessWidget {
  const SummaryWindowBar({super.key, required this.view});

  final SummaryView view;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final small = theme.textTheme.bodySmall;
    final strings = MaterialLocalizations.of(context);
    final at = view.window.asOf.toLocal();
    final when =
        '${strings.formatShortDate(at)}, '
        '${strings.formatTimeOfDay(TimeOfDay.fromDateTime(at))}';
    final moved = view.dayOffset != 0;
    final what = view.lastCompaction == null
        ? 'Now'
        : moved
        ? '${view.dayOffset > 0 ? '+' : ''}${view.dayOffset} '
              'day${view.dayOffset.abs() == 1 ? '' : 's'} from last compaction'
        : 'Last compaction';
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 8, 0),
      child: Row(
        children: [
          IconButton(
            visualDensity: VisualDensity.compact,
            tooltip: 'A day earlier',
            icon: const Icon(Icons.chevron_left),
            onPressed: () => view.onDays(view.dayOffset - 1),
          ),
          Expanded(
            child: Tooltip(
              message: moved
                  ? 'Back to the last compaction'
                  : 'What the summary measures from',
              child: InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: moved ? () => view.onDays(0) : null,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Column(
                    children: [
                      Text(
                        '${view.window.forward ? 'From' : 'As of'} $when',
                        style: small?.copyWith(fontWeight: FontWeight.w600),
                        textAlign: TextAlign.center,
                      ),
                      Text(
                        what,
                        style: small?.copyWith(
                          color: moved
                              ? theme.colorScheme.primary
                              : theme.colorScheme.onSurfaceVariant,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            tooltip: 'A day later',
            icon: const Icon(Icons.chevron_right),
            onPressed: () => view.onDays(view.dayOffset + 1),
          ),
          SegmentedButton<bool>(
            showSelectedIcon: false,
            style: const ButtonStyle(
              visualDensity: VisualDensity(horizontal: -3, vertical: -3),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            segments: const [
              ButtonSegment(
                value: false,
                label: Text('Past'),
                tooltip: 'The 24 hours and 7 days before',
              ),
              ButtonSegment(
                value: true,
                label: Text('Next'),
                tooltip: 'The 24 hours and 7 days after',
              ),
            ],
            selected: {view.window.forward},
            onSelectionChanged: (picked) => view.onForward(picked.single),
          ),
        ],
      ),
    );
  }
}
