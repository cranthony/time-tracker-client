import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../models/event.dart';
import '../models/goal.dart';
import 'color_picker.dart';

/// One share of a day: some of its time, by priority or goal.
class SummarySlice {
  const SummarySlice(this.label, this.color, this.time);

  final String label;

  /// Its color; null for the time with nothing scheduled, drawn empty.
  final Color? color;
  final Duration time;
}

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
  final ranked = time.keys.whereType<String>().toList()
    ..sort((a, b) => time[b]!.compareTo(time[a]!));
  final rest = ranked
      .skip(top)
      .fold(Duration.zero, (sum, id) => sum + time[id]!);
  return [
    for (final id in ranked.take(top))
      SummarySlice(
        goals[id]?.name ?? names[id] ?? id,
        parseColor(goals[id]?.effectiveColor) ??
            priorityColor(goals[id]?.effectivePriority),
        time[id]!,
      ),
    if (rest > Duration.zero)
      SummarySlice('${ranked.length - top} other goals', _other, rest),
    if (noGoal != null) SummarySlice('No goal', _none, noGoal),
    if (unscheduled != null) SummarySlice('Unscheduled', null, unscheduled),
  ];
}

const _none = Color(0xFFD0D0D0);
const _other = Color(0xFF8A8A8A);

/// A day's time at a glance, above its timeline: its share for each
/// priority, for the top goals, and for the top-level goals they're
/// under, and the time with nothing scheduled. Swiping it, or tapping a
/// title, turns between them.
class DaySummary extends StatefulWidget {
  const DaySummary({
    super.key,
    required this.events,
    required this.day,
    required this.goals,
    this.initialPage = 0,
  });

  final List<Event> events;
  final DateTime day;
  final Map<String, Goal> goals;
  final int initialPage;

  @override
  State<DaySummary> createState() => _DaySummaryState();
}

class _DaySummaryState extends State<DaySummary> {
  late final _pages = PageController(initialPage: widget.initialPage);
  late int _page = widget.initialPage;

  /// Each page's height, once it's laid out: the summary grows or shrinks
  /// between them as it's swiped.
  final _heights = <int, double>{};

  static const _titles = ['Priorities', 'Goals', 'Top-level goals'];

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final shares = [
      priorityShares(widget.events, widget.day),
      goalShares(widget.events, widget.day, widget.goals),
      goalShares(widget.events, widget.day, widget.goals, topLevel: true),
    ];
    return Material(
      color: theme.colorScheme.surfaceContainerLow,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: _header(context),
          ),
          ListenableBuilder(
            listenable: _pages,
            builder: (context, pages) {
              final at = _pages.hasClients && _pages.position.haveDimensions
                  ? _pages.page!
                  : _page.toDouble();
              final from = _heights[at.floor()] ?? _heights[at.ceil()];
              final to = _heights[at.ceil()] ?? from;
              return SizedBox(
                height: lerpDouble(from, to, at - at.floor()) ?? 0,
                child: pages,
              );
            },
            child: PageView(
              controller: _pages,
              onPageChanged: (page) => setState(() => _page = page),
              children: [
                for (final (i, slices) in shares.indexed)
                  // As tall as it needs, whatever the summary's height
                  // this frame.
                  OverflowBox(
                    alignment: Alignment.topCenter,
                    minHeight: 0,
                    maxHeight: double.infinity,
                    child: _Measured(
                      onHeight: (height) {
                        if (mounted) setState(() => _heights[i] = height);
                      },
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                        child: _Bar(slices: slices),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Divider(height: 1, color: theme.colorScheme.outlineVariant),
        ],
      ),
    );
  }

  /// The titles, the current one bold and underlined.
  Widget _header(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        for (final (i, title) in _titles.indexed) ...[
          if (i > 0) const SizedBox(width: 14),
          GestureDetector(
            onTap: () => _pages.animateToPage(
              i,
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeOut,
            ),
            child: Text(
              title,
              style: theme.textTheme.labelLarge?.copyWith(
                color: i == _page
                    ? theme.colorScheme.onSurface
                    : theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
                fontWeight: i == _page ? FontWeight.w700 : FontWeight.w500,
                decoration: i == _page ? TextDecoration.underline : null,
                decorationThickness: 2,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// [slices] as one bar split by share, with a legend under it. The time
/// with nothing scheduled is left empty.
class _Bar extends StatelessWidget {
  const _Bar({required this.slices});

  final List<SummarySlice> slices;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final total = slices.fold(Duration.zero, (sum, s) => sum + s.time);
    final outline = theme.colorScheme.outlineVariant;
    String percent(Duration part) =>
        '${(100 * part.inSeconds / total.inSeconds).round()}%';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 8),
        Container(
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
        const SizedBox(height: 8),
        Wrap(
          spacing: 14,
          runSpacing: 4,
          children: [
            for (final slice in slices)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: slice.color,
                      border: slice.color == null
                          ? Border.all(color: outline, width: 1.5)
                          : null,
                      borderRadius: BorderRadius.circular(2.5),
                    ),
                  ),
                  const SizedBox(width: 5),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 130),
                    child: Text(
                      slice.label,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    percent(slice.time),
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
          ],
        ),
      ],
    );
  }
}

/// [child], telling [onHeight] its height after each layout that changes
/// it.
class _Measured extends SingleChildRenderObjectWidget {
  const _Measured({required this.onHeight, super.child});

  final ValueChanged<double> onHeight;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderMeasured(onHeight);

  @override
  void updateRenderObject(BuildContext context, _RenderMeasured renderObject) =>
      renderObject.onHeight = onHeight;
}

class _RenderMeasured extends RenderProxyBox {
  _RenderMeasured(this.onHeight);

  ValueChanged<double> onHeight;
  double? _height;

  @override
  void performLayout() {
    super.performLayout();
    final height = size.height;
    if (height == _height) return;
    _height = height;
    WidgetsBinding.instance.addPostFrameCallback((_) => onHeight(height));
  }
}
