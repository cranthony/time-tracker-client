import '../models/goal.dart';
import 'goal_icon.dart';

import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../models/event.dart';
import '../models/google_calendar.dart';
import '../models/person.dart' show selfPersonId;
import '../models/plan_action.dart';
import '../models/weather.dart';
import 'color_picker.dart';
import 'durations.dart';
import 'other_events.dart';
import 'weather_style.dart';

/// The zoom levels a [DayTimeline] can be shown at, in logical pixels
/// per minute: from a day in about 720 pixels to one hour in 360.
const timelineScales = [0.5, 0.75, 1.0, 1.5, 2.0, 3.0, 4.0, 6.0];

/// The zoom level a [DayTimeline] starts at: an hour in 90 pixels.
const defaultTimelineScale = 1.5;

/// Space above midnight and below the next, so their labels fit.
const _pad = 12.0;

/// The column of times, then the band of priorities, [_bandPadding] in
/// from either side of its column, then the band of events, then the
/// gutter each event's color fills from its piece of the band to it,
/// then the events. Where an event is drawn at its times, its band, that
/// fill and the strip down its edge make a bar as wide as the priority
/// band, as far from it as its padding.
const _timeWidth = 64.0;
const _bandWidth = 24.0;
const _bandPadding = 2.0;
const _gutterWidth = 8.0;
const _eventBandLeft = _timeWidth + _bandWidth + _bandPadding;
const _eventBandWidth =
    _bandWidth - 2 * _bandPadding - _gutterWidth - _stripWidth;
const _cardsLeft = _eventBandLeft + _eventBandWidth + _gutterWidth;

/// How far from a [DayTimeline]'s left its events' cards start: right of
/// the times and the bands.
const timelineCardsLeft = _cardsLeft;

/// How wide a [DayTimeline]'s column of times is.
const timelineTimesWidth = _timeWidth;

/// How wide the line round each event is, in its color.
const _outlineWidth = 1.25;

/// How faint a cancelled event's band and outline are.
const _cancelledAlpha = 0.4;

/// The colored strip down an event's left edge.
const _stripWidth = 4.0;

/// How thick the hairline is between events that meet in one color.
const _seamWidth = 1.0;

/// How round an event's corners on the right are, where it meets no
/// other.
const _cardRadius = 8.0;

/// The padding inside an event, around its text.
const _cardPadding = EdgeInsets.fromLTRB(8, 4, 8, 4);

/// How wide an event's card, inside its padding, must be to list its
/// locations and people down its right.
const _detailsMinCardWidth = 220.0;

/// The most of a card's width its locations and people take.
const _detailsWidthFraction = 0.5;

/// The size of each location's and person's icon, the space after it,
/// and the space between them side by side.
const _detailIconSize = 12.0;
const _detailIconGap = 2.0;
const _detailGap = 8.0;

/// The space before each of the things after an event's summary, and
/// inside a chip either side of its text.
const _chipGap = 6.0;
const _chipPadding = 4.0;

/// How big an event's goal icons are, by its chips.
const _goalIconSize = 14.0;

/// The size of a commute's icon before its summary, and the space after.
const _commuteIconSize = 14.0;
const _commuteIconGap = 4.0;

/// A proposal's mark on an event, before its summary: its dot, marking
/// it changed since the user last looked, and its icon.
const _dotSize = 7.0;
const _dotGap = 4.0;
const _markIconSize = 14.0;
const _markIconGap = 4.0;

/// The time labels' and priority labels' text, and how tall they are.
const _labelFontSize = 11.0;
const _bandFontSize = 10.0;

/// How tall a sunrise's or sunset's badge on the band is.
const _sunBadgeHeight = 18.0;

/// Where [event] sits on a [DayTimeline]: where its times put it
/// ([trueTop] to [trueBottom]) and where it's drawn ([top] to [bottom]).
/// An event too short for its text is drawn taller than its time
/// ([compressed]); one that starts while the one above it is still
/// drawn is pushed down below it ([displaced]).
@immutable
class TimelinePlacement {
  const TimelinePlacement({
    required this.event,
    required this.trueTop,
    required this.trueBottom,
    required this.top,
    required this.bottom,
  });

  final Event event;
  final double trueTop;
  final double trueBottom;
  final double top;
  final double bottom;

  /// Whether it's drawn lower than it starts.
  bool get displaced => top > trueTop + 0.5;

  /// Whether it's drawn taller than it lasts.
  bool get compressed => bottom - top > trueBottom - trueTop + 0.5;

  /// Whether it's drawn shorter than it lasts: pushed down by the event
  /// above, but still ending where it ends.
  bool get shortened => bottom - top < trueBottom - trueTop - 0.5;
}

/// The run of time from [start] to [end] in which the most important
/// event going on has [priority].
@immutable
class PriorityRun {
  const PriorityRun(this.start, this.end, this.priority);

  final DateTime start;
  final DateTime end;
  final int priority;

  @override
  bool operator ==(Object other) =>
      other is PriorityRun &&
      other.start == start &&
      other.end == end &&
      other.priority == priority;

  @override
  int get hashCode => Object.hash(start, end, priority);

  @override
  String toString() => 'PriorityRun($start, $end, P$priority)';
}

/// How far down a [DayTimeline] [time] is, at [scale], for a day that
/// starts at [day] and ends at [dayEnd]: times outside it are put at its
/// top or bottom.
double timelineOffset(
  DateTime time, {
  required DateTime day,
  required DateTime dayEnd,
  required double scale,
}) {
  final minutes = time.difference(day).inSeconds / 60;
  final length = dayEnd.difference(day).inSeconds / 60;
  return _pad + minutes.clamp(0, length) * scale;
}

/// How tall a timeline from [start] to [end] -- days stacked on each
/// other -- is at [scale], with room for their labels.
double timelineSpanHeight(DateTime start, DateTime end, double scale) =>
    timelineOffset(end, day: start, dayEnd: end, scale: scale) + _pad;

/// How tall a [DayTimeline] for [day] is at [scale]: midnight to
/// midnight, with room for their labels; taller only if an event near
/// midnight is drawn past it.
double timelineHeight(DateTime day, double scale) {
  final dayEnd = DateTime(day.year, day.month, day.day + 1);
  return timelineOffset(dayEnd, day: day, dayEnd: dayEnd, scale: scale) + _pad;
}

/// How tall a [DayTimeline] of [events] on [day] at [scale] is drawn in
/// [context]: as [timelineHeight], or taller, to the foot of an event
/// drawn on past midnight, pushed down by those above.
double timelineDrawnHeight(
  BuildContext context, {
  required List<Event> events,
  required DateTime day,
  required double scale,
}) => _layOut(context, events: events, day: day, scale: scale).height;

/// How a [DayTimeline] lays out [events] on [day] in [context]: its cards'
/// text, where each is drawn, and how tall it all is.
({_CardStyles styles, List<TimelinePlacement> placements, double height})
_layOut(
  BuildContext context, {
  required List<Event> events,
  required DateTime day,
  required double scale,
}) {
  final text = Theme.of(context).textTheme;
  final scaler = MediaQuery.textScalerOf(context);
  double lineHeight(TextStyle? style) {
    final painter = TextPainter(
      text: TextSpan(text: 'Ag', style: style),
      textDirection: TextDirection.ltr,
      textScaler: scaler,
      maxLines: 1,
    )..layout();
    final height = painter.height;
    painter.dispose();
    return height;
  }

  final styles = _CardStyles(
    summary: text.titleSmall,
    action: text.bodySmall,
    chip: text.labelSmall,
  );
  final summaryLine = lineHeight(styles.summary);
  // Its actions' names aren't made room for: they're listed as far as
  // its time leaves room, its diamonds by its chips standing for them.
  // Nor is a proposal's mark: it's on its summary's line.
  double minHeight(Event event) =>
      _cardPadding.vertical +
      summaryLine +
      // Slack for rounding, so the text never overflows.
      2;

  final dayEnd = DateTime(day.year, day.month, day.day + 1);
  final placements = placeEvents(
    events,
    day: day,
    dayEnd: dayEnd,
    scale: scale,
    minHeight: minHeight,
  );
  final height = math.max(
    timelineHeight(day, scale),
    placements.map((p) => p.bottom).fold(0.0, math.max) + _pad,
  );
  return (styles: styles, placements: placements, height: height);
}

/// The time [offset] down a [DayTimeline] is: the inverse of
/// [timelineOffset], clamped to the day.
DateTime timelineTime(
  double offset, {
  required DateTime day,
  required DateTime dayEnd,
  required double scale,
}) {
  final length = dayEnd.difference(day).inSeconds / 60;
  final minutes = ((offset - _pad) / scale).clamp(0, length);
  return day.add(Duration(seconds: (minutes * 60).round()));
}

/// Where each of [events] is drawn, by start: at its times, at [scale],
/// unless it needs more room for its text ([minHeight]) than it lasts,
/// or the event above it does. Then it's drawn taller, or lower, but
/// never higher or shorter than its times.
List<TimelinePlacement> placeEvents(
  List<Event> events, {
  required DateTime day,
  required DateTime dayEnd,
  required double scale,
  required double Function(Event) minHeight,
}) {
  double y(DateTime t) =>
      timelineOffset(t, day: day, dayEnd: dayEnd, scale: scale);
  final sorted = [...events]
    ..sort((a, b) {
      final byStart = a.start.compareTo(b.start);
      return byStart != 0 ? byStart : a.end.compareTo(b.end);
    });
  final placed = <TimelinePlacement>[];
  var below = double.negativeInfinity;
  for (final event in sorted) {
    final trueTop = y(event.start);
    final trueBottom = math.max(y(event.end), trueTop);
    final top = math.max(trueTop, below);
    final bottom = math.max(trueBottom, top + minHeight(event));
    placed.add(
      TimelinePlacement(
        event: event,
        trueTop: trueTop,
        trueBottom: trueBottom,
        top: top,
        bottom: bottom,
      ),
    );
    below = bottom;
  }
  return placed;
}

/// The priority of the most important event going on (the lowest
/// number) through the day from [day] to [dayEnd], in runs: none where
/// nothing is. An event with no priority, of its own or from its actions,
/// counts as [defaultPriority]. Cancelled events don't count.
List<PriorityRun> priorityRuns(
  List<Event> events, {
  required DateTime day,
  required DateTime dayEnd,
}) {
  DateTime clip(DateTime t) =>
      t.isBefore(day) ? day : (t.isAfter(dayEnd) ? dayEnd : t);
  final live = [
    for (final event in events)
      if (!event.isCancelled && clip(event.end).isAfter(clip(event.start)))
        (
          start: clip(event.start),
          end: clip(event.end),
          priority: event.effectivePriority ?? defaultPriority,
        ),
  ];
  final edges = {
    for (final e in live) ...[e.start, e.end],
  }.toList()..sort();
  final runs = <PriorityRun>[];
  for (var i = 0; i + 1 < edges.length; i++) {
    final (from, to) = (edges[i], edges[i + 1]);
    final going = [
      for (final e in live)
        if (!e.start.isAfter(from) && !e.end.isBefore(to)) e.priority,
    ];
    if (going.isEmpty) continue;
    final priority = going.reduce(math.min);
    if (runs.lastOrNull case final last?
        when last.end == from && last.priority == priority) {
      runs[runs.length - 1] = PriorityRun(last.start, to, priority);
    } else {
      runs.add(PriorityRun(from, to, priority));
    }
  }
  return runs;
}

/// The times through the day from [day] to [dayEnd] when two or more of
/// [events] are going on at once, in order, those that meet run
/// together. Cancelled events don't count.
List<({DateTime start, DateTime end})> eventOverlaps(
  List<Event> events, {
  required DateTime day,
  required DateTime dayEnd,
}) {
  DateTime clip(DateTime t) =>
      t.isBefore(day) ? day : (t.isAfter(dayEnd) ? dayEnd : t);
  final live = [
    for (final event in events)
      if (!event.isCancelled && clip(event.end).isAfter(clip(event.start)))
        (start: clip(event.start), end: clip(event.end)),
  ]..sort((a, b) => a.start.compareTo(b.start));
  final overlaps = <({DateTime start, DateTime end})>[];
  // The latest end of those before, to find what each starts inside.
  DateTime? reach;
  for (final e in live) {
    if (reach != null && e.start.isBefore(reach)) {
      final end = e.end.isBefore(reach) ? e.end : reach;
      if (overlaps.lastOrNull case final last?
          when !e.start.isAfter(last.end)) {
        overlaps[overlaps.length - 1] = (
          start: last.start,
          end: end.isAfter(last.end) ? end : last.end,
        );
      } else {
        overlaps.add((start: e.start, end: end));
      }
    }
    if (reach == null || e.end.isAfter(reach)) reach = e.end;
  }
  return overlaps;
}

/// The color [event] is shown in: its primary action's, if [actions] has it
/// and it has one, or else its priority's.
Color eventColor(Event event, Map<String, PlanAction> actions) {
  final action = switch (event.actionIds) {
    [final id, ...] => actions[id],
    _ => null,
  };
  return (action == null
          ? null
          : parseColor(action.effectiveColor ?? action.backgroundColor)) ??
      priorityColor(event.effectivePriority);
}

/// [event]'s [eventColor] as it's drawn: fainter if it's cancelled.
Color _shownColor(Event event, Map<String, PlanAction> actions) {
  final color = eventColor(event, actions);
  return event.isCancelled ? color.withValues(alpha: _cancelledAlpha) : color;
}

/// How far apart two events' colors can be, in any channel, and still
/// run together where they meet.
const _seamTolerance = 0.1;

/// Whether the [i]th of [placements] meets the one before it in a color
/// so close to its own that they'd run together, so a seam is drawn
/// between them: across their band, their fill from it and their strips.
bool _seamAbove(
  List<TimelinePlacement> placements,
  int i,
  Map<String, PlanAction> actions,
) {
  if (i == 0 || placements[i - 1].bottom < placements[i].top) return false;
  final a = _shownColor(placements[i - 1].event, actions);
  final b = _shownColor(placements[i].event, actions);
  return (a.r - b.r).abs() <= _seamTolerance &&
      (a.g - b.g).abs() <= _seamTolerance &&
      (a.b - b.b).abs() <= _seamTolerance &&
      (a.a - b.a).abs() <= _seamTolerance;
}

/// Picks which of [candidates] to show, [height] tall at [top]: each in
/// turn, unless it'd overlap one already picked. So the ones first win.
List<T> placeLabels<T>(
  Iterable<T> candidates, {
  required double Function(T) top,
  required double height,
}) {
  final placed = <T>[];
  for (final candidate in candidates) {
    final y = top(candidate);
    if (placed.every((p) => (top(p) - y).abs() >= height)) {
      placed.add(candidate);
    }
  }
  return placed;
}

/// One day's events on a timeline, from midnight to midnight at a
/// constant [scale] (logical pixels per minute).
///
/// Down its left edge are the times: those where events start or end
/// first, then the hours, as many as fit. Beside them, a band in the
/// color of the priority of the most important event going on, clear
/// where nothing is, labeled "P0" to "P3" where each run of it starts and
/// stops -- or, given the [weather], a band of it: the sky's color, with
/// the chance of rain a blue bar across it, as wide as it's likely,
/// labeled with the chance where it changes, and each of the [sun]'s
/// rising and setting an orange badge across it, the sun on the horizon,
/// its time beside it in orange after an arrow up or down. Given a
/// [temperatureLabel], the temperature is on it too: every third hour
/// where the forecast is by the hour -- counted from [temperaturesFrom]
/// -- once in each part of a day where it's coarser, just below the chance of rain where that's labeled at
/// the same time. Beside that, a band as wide of the events, each where its
/// times put it, in its [eventColor]. Then each event: its summary, then
/// a line for each of its actions, the primary action first, each after a
/// diamond in the action's color ([actions] gives them; one not among them
/// gets an outline). Its color fills the gutter from its piece of the
/// band to it, and a thin line of it runs round it. A commute has a
/// small icon before its summary. Where there's room, down its right,
/// are the locations and the people its facts name, from
/// [locationNames] and [personNames].
///
/// An event too short for that is drawn as tall as its text needs, and
/// says how long it is. One pushed down by the event above it is joined
/// to where it truly is by that fill from the band. Where an event meets
/// the one before it in the same color, or one too close to tell apart,
/// a hairline of the background divides them. Where events overlap
/// ([eventOverlaps]), that time is tinted red over them, labeled
/// "overlap" -- but not the [faded] one's, being moved from there.
/// [now], the [lastCompaction] and each of the [pendingNotes], if
/// they're in the day, are marked with lines across, under the events;
/// zoomed in past the [defaultTimelineScale], they're labeled "now",
/// "last compacted" and "pending note" in place of the times beside
/// them. A note's label gives way to any it would overlap.
///
/// Under it all is its [TimelineAxis], unless not to draw its [axis]:
/// then it's drawn over one drawn apart, and covers the axis' times its
/// own labels would overlap.
///
/// A compaction proposal's [review], what happened to confirm, is a
/// tinted band, outlined, headed "What happened -- to confirm" where it
/// starts and ending at a line labeled with its `through`. Each event in
/// [marks] -- the proposal's -- is tinted too, and says under its summary
/// what the proposal does to it; one changed since the user last looked
/// stands out. Its notes ([reviewNotes]) are drawn over the events, each
/// with a badge saying what became of it, and the one [ReviewNote.selected]
/// highlighted.
///
/// Tapping an event calls [onTap] with it, and pressing and holding it,
/// [onLongPress]; tapping anywhere else calls [onTapTime] with the time
/// there. The [highlighted] event is ringed, pulsing, and the [keyed]
/// one, steadily. While a cursor stops at notes ([pulseNotes]) or
/// events' edges ([pulseEdges]), they're marked, pulsing.
class DayTimeline extends StatelessWidget {
  const DayTimeline({
    super.key,
    required this.events,
    required this.day,
    this.actions = const {},
    this.personNames = const {},
    this.locationNames = const {},
    this.goalNames = const {},
    this.scale = defaultTimelineScale,
    this.now,
    this.lastCompaction,
    this.pendingNotes = const [],
    this.onTap,
    this.onLongPress,
    this.onTapTime,
    this.faded,
    this.highlighted,
    this.keyed,
    this.listed = const {},
    this.pulseNotes = false,
    this.pulseEdges = false,
    this.axis = true,
    this.review,
    this.onTapThrough,
    this.marks = const {},
    this.reviewNotes = const [],
    this.googleEvents = const [],
    this.googleOnTop = false,
    this.onTapGoogle,
    this.weather,
    this.sun = const [],
    this.temperatureLabel,
    this.temperaturesFrom,
    this.temperatures,
  });

  final List<Event> events;

  /// When the temperature's labels count every third hour from, in the
  /// day it's in -- a quarter hour after the forecast was fetched, so
  /// they hold still till it's fetched again. Other days, and without
  /// it, they count from midnight.
  final DateTime? temperaturesFrom;

  /// The forecast to label the temperature from: from when it was
  /// fetched, so the labels before now stay, as [weather] -- from now --
  /// doesn't. Without it, [weather]'s.
  final List<WeatherSpan>? temperatures;

  /// A temperature, in degrees Celsius, in the units shown: for the
  /// temperature on the [weather] band. Without it, none is.
  final String Function(double celsius)? temperatureLabel;

  /// The sunrises and sunsets in the day, marked on the band: only with
  /// the [weather].
  final List<SunTime> sun;

  /// The forecast, span by span, from now: drawn down the band in place
  /// of the priorities. Empty, the band's empty; null, it's the
  /// priorities'.
  final List<WeatherSpan>? weather;

  /// Events from the user's Google calendars, for reference: the timed
  /// ones drawn faintly behind [events], each also marked down the right
  /// edge, so one under an event still shows. Tapping one calls
  /// [onTapGoogle].
  final List<GoogleEvent> googleEvents;

  /// Whether [googleEvents] are drawn over [events], nearly solid, rather
  /// than faintly behind them.
  final bool googleOnTop;
  final ValueChanged<GoogleEvent>? onTapGoogle;

  /// Midnight, local time, at the start of the day shown.
  final DateTime day;

  /// The actions by id, for their colors and names.
  final Map<String, PlanAction> actions;

  /// Names by id, for the people and locations events' facts name; one
  /// not among them is shown by its id.
  final Map<String, String> personNames;
  final Map<String, String> locationNames;

  /// Goals' titles by id, for the goals events are for: listed under an
  /// event's actions where there's room. One not among them isn't listed
  /// (deleted since), though it's counted.
  final Map<String, String> goalNames;
  final double scale;
  final DateTime? now;

  /// When notes were last compacted into the calendar: what's before it
  /// is as the notes had it.
  final DateTime? lastCompaction;

  /// When each note not yet compacted into the calendar was taken.
  final List<DateTime> pendingNotes;
  final ValueChanged<Event>? onTap;
  final ValueChanged<Event>? onLongPress;

  /// The id of an event to draw faintly: one being moved from there.
  final String? faded;

  /// The id of an event to pick out: ringed, pulsing.
  final String? highlighted;

  /// The id of the event the keyboard's on: ringed, steadily.
  final String? keyed;

  /// The events in a list, by id, with its icon: each ringed, slightly
  /// pulsing, the icon on it.
  final Map<String, IconData> listed;

  /// Whether to mark the notes, and the edges of the events, as what a
  /// cursor stops at: bolder, pulsing.
  final bool pulseNotes;
  final bool pulseEdges;

  /// Called with the time at a tap that isn't on an event.
  final ValueChanged<DateTime>? onTapTime;

  /// Whether to draw its [TimelineAxis] under it.
  final bool axis;

  /// What a compaction proposal says happened, to confirm: from its
  /// window's start to its `through`.
  final ({DateTime from, DateTime through, DateTime? claudeThrough})? review;

  /// The [review] band's `through` tapped: to extend it. Null, it can't
  /// be.
  final VoidCallback? onTapThrough;

  /// What the proposal says of each of its events, by id.
  final Map<String, EventMark> marks;

  /// The proposal's notes.
  final List<ReviewNote> reviewNotes;

  /// Midnight at the end of the day.
  DateTime get dayEnd => DateTime(day.year, day.month, day.day + 1);

  /// The names of the locations [event]'s facts name, then of the people
  /// and circles with the user, then of those it was for, each kind
  /// apart -- a circle with those its except leaves out, "Family (except
  /// Ulyssie)": never Self, who's at every event.
  List<(_Detail, List<String>)> _details(Event event) => switch (event.facts) {
    null => const [],
    final facts => [
      for (final (kind, named, names) in [
        (_Detail.location, namedFrom(facts.locationIds), locationNames),
        (_Detail.withPerson, facts.withWhom, personNames),
        (_Detail.forPerson, facts.forWhom, personNames),
      ])
        if ([
              for (final n in named)
                if (n.id != selfPersonId)
                  namedLabel(n, (id) => names[id] ?? id),
            ]
            case final shown when shown.isNotEmpty)
          (kind, shown),
    ],
  };

  /// [child] under the temperature on the band, if it's shown: fading
  /// out and back in as the forecast is fetched again.
  Widget _withTemperatures(BuildContext context, {required Widget child}) {
    final weather = this.weather;
    final label = temperatureLabel;
    if (weather == null || label == null) return child;
    final scaler = MediaQuery.textScalerOf(context);
    final baseStyle =
        Theme.of(context).textTheme.labelSmall ?? const TextStyle();
    return _FadingTemperatures(
      from: temperaturesFrom,
      painter: (from, opacity) => TemperatureLabelsPainter(
        day: day,
        dayEnd: dayEnd,
        scale: scale,
        weather: weather,
        temperatures: temperatures ?? weather,
        sun: sun,
        label: label,
        from: from,
        opacity: opacity,
        scaler: scaler,
        baseStyle: baseStyle,
      ),
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text = theme.textTheme;
    final scaler = MediaQuery.textScalerOf(context);
    final (:styles, :placements, :height) = _layOut(
      context,
      events: events,
      day: day,
      scale: scale,
    );
    final runs = weather == null
        ? priorityRuns(events, day: day, dayEnd: dayEnd)
        : const <PriorityRun>[];
    double y(DateTime t) =>
        timelineOffset(t, day: day, dayEnd: dayEnd, scale: scale);
    double? yIfToday(DateTime? t) => switch (t) {
      final t? when !t.isBefore(day) && t.isBefore(dayEnd) => y(t),
      _ => null,
    };
    final nowY = yIfToday(now);
    final compactionY = yIfToday(lastCompaction);
    final noteYs = [for (final t in pendingNotes) ?yIfToday(t)]..sort();
    final colors = theme.colorScheme;
    // The lines' labels, in place of the times beside them, only when
    // zoomed in: each centered on its line, unless that's too close to the
    // one above.
    final markerStyle = (text.labelSmall ?? const TextStyle()).copyWith(
      fontSize: _bandFontSize,
      fontWeight: FontWeight.w400,
      height: 1.2,
    );
    final markers = <_Marker>[];
    if (scale > defaultTimelineScale) {
      for (final (y, label, color) in [
        if (compactionY != null)
          (compactionY, 'last\ncompacted', colors.tertiary),
        if (nowY != null) (nowY, 'now', colors.error),
      ]..sort((a, b) => a.$1.compareTo(b.$1))) {
        final painter = _markerText(label, markerStyle, scaler);
        final height = painter.height;
        painter.dispose();
        final clear = switch (markers.lastOrNull) {
          final above? => above.y + (above.height + height) / 2 + 1,
          null => double.negativeInfinity,
        };
        markers.add((
          y: math.max(y, clear),
          height: height,
          label: label,
          color: color,
        ));
      }
      // Each note's, where it's clear of every other label, so many
      // together don't push each other down the timeline.
      const noteLabel = 'pending\nnote';
      final painter = _markerText(noteLabel, markerStyle, scaler);
      final noteHeight = painter.height;
      painter.dispose();
      for (final y in noteYs) {
        if (markers.every(
          (m) => (m.y - y).abs() >= (m.height + noteHeight) / 2 + 1,
        )) {
          markers.add((
            y: y,
            height: noteHeight,
            label: noteLabel,
            color: _noteColor(colors),
          ));
        }
      }
    }
    final rail = _RailPainter(
      day: day,
      dayEnd: dayEnd,
      scale: scale,
      events: events,
      actions: actions,
      runs: runs,
      weather: weather,
      sun: weather == null ? const [] : sun,
      sunColor: sunColor(theme.brightness),
      placements: placements,
      timeLabel: (t) =>
          MaterialLocalizations.of(context)
              .formatTimeOfDay(TimeOfDay.fromDateTime(t.toLocal())),
      scaler: scaler,
      baseStyle: text.labelSmall ?? const TextStyle(),
      nowY: nowY,
      nowColor: colors.error,
      compactionY: compactionY,
      compactionColor: colors.tertiary,
      noteYs: noteYs,
      noteColor: _noteColor(colors),
      markers: markers,
      edgeColor: colors.onSurface,
      coverColor: theme.scaffoldBackgroundColor,
    );
    final band = switch (review) {
      final review? => _reviewBand(
        context,
        day: day,
        dayEnd: dayEnd,
        from: review.from,
        through: review.through,
        claudeThrough: review.claudeThrough,
        onTapThrough: onTapThrough,
        y: y,
      ),
      null => null,
    };
    return LayoutBuilder(
      builder: (context, constraints) {
        final cardWidth = math.max(0.0, constraints.maxWidth - _cardsLeft - 8);
        return CustomPaint(
          painter: axis ? _axisPainter(context, day, scale) : null,
          child: CustomPaint(
            painter: rail,
            foregroundPainter: markers.isEmpty
                ? null
                : _MarkerLabelsPainter(
                    markers: markers,
                    style: markerStyle,
                    scaler: scaler,
                  ),
            child: _withTemperatures(
              context,
              child: GestureDetector(
                // The events' own taps win where they are.
                behavior: HitTestBehavior.opaque,
                onTapUp: onTapTime == null
                    ? null
                    : (details) => onTapTime!(
                        timelineTime(
                          details.localPosition.dy,
                          day: day,
                          dayEnd: dayEnd,
                          scale: scale,
                        ),
                      ),
                child: SizedBox(
                  width: constraints.maxWidth,
                  height: height,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      ...?band?.under,
                      if (!googleOnTop)
                        ..._googleEvents(
                          context,
                          googleEvents,
                          day: day,
                          dayEnd: dayEnd,
                          y: y,
                          width: cardWidth,
                          onTap: onTapGoogle,
                        ),
                      for (final (i, placement) in placements.indexed)
                        Positioned(
                          left: _cardsLeft,
                          top: placement.top,
                          width: cardWidth,
                          height: placement.bottom - placement.top,
                          child: _EventCard(
                            placement: placement,
                            joinedAbove:
                                i > 0 &&
                                placements[i - 1].bottom >= placement.top,
                            joinedBelow:
                                i + 1 < placements.length &&
                                placements[i + 1].top <= placement.bottom,
                            seamColor: _seamAbove(placements, i, actions)
                                ? theme.scaffoldBackgroundColor
                                : null,
                            actions: actions,
                            goalNames: goalNames,
                            details: _details(placement.event),
                            styles: styles,
                            onTap: onTap == null
                                ? null
                                : () => onTap!(placement.event),
                            onLongPress: onLongPress == null
                                ? null
                                : () => onLongPress!(placement.event),
                            faded: faded != null && placement.event.id == faded,
                            mark: marks[placement.event.id],
                            timeLabel: (t) => MaterialLocalizations.of(context)
                                .formatTimeOfDay(
                                  TimeOfDay.fromDateTime(t.toLocal()),
                                ),
                          ),
                        ),
                      if (googleOnTop)
                        ..._googleEvents(
                          context,
                          googleEvents,
                          day: day,
                          dayEnd: dayEnd,
                          y: y,
                          width: cardWidth,
                          onTap: onTapGoogle,
                          onTop: true,
                        ),
                      for (final placement in placements)
                        if (listed[placement.event.id] case final icon?)
                          Positioned(
                            left: _cardsLeft - 2,
                            top: placement.top - 2,
                            width: cardWidth + 4,
                            height: placement.bottom - placement.top + 4,
                            child: IgnorePointer(child: _Listed(icon: icon)),
                          ),
                      for (final placement in placements)
                        if (highlighted != null &&
                            placement.event.id == highlighted)
                          Positioned(
                            left: _cardsLeft - 3,
                            top: placement.top - 3,
                            width: cardWidth + 6,
                            height: placement.bottom - placement.top + 6,
                            child: const IgnorePointer(child: _Highlight()),
                          )
                        else if (keyed != null && placement.event.id == keyed)
                          Positioned(
                            left: _cardsLeft - 3,
                            top: placement.top - 3,
                            width: cardWidth + 6,
                            height: placement.bottom - placement.top + 6,
                            child: const IgnorePointer(child: _Keyed()),
                          ),
                      if (pulseNotes || pulseEdges)
                        Positioned.fill(
                          child: IgnorePointer(
                            child: _SnapMarks(
                              notes: pulseNotes
                                  ? [
                                      ...noteYs,
                                      for (final note in reviewNotes)
                                        ?yIfToday(note.time),
                                    ]
                                  : const [],
                              edges: pulseEdges
                                  ? {
                                      for (final p in placements)
                                        if (!p.event.isCancelled) ...[
                                          p.trueTop,
                                          p.trueBottom,
                                        ],
                                    }.toList()
                                  : const [],
                              noteColor: colors.tertiary,
                              edgeColor: colors.primary,
                            ),
                          ),
                        ),
                      // Not the one being moved: its overlaps go with it.
                      for (final overlap in eventOverlaps(
                        OtherEvents(events, except: faded).events,
                        day: day,
                        dayEnd: dayEnd,
                      ))
                        ..._overlap(context, y(overlap.start), y(overlap.end)),
                      ...?band?.over,
                      ..._googleMarks(
                        googleEvents,
                        day: day,
                        dayEnd: dayEnd,
                        y: y,
                        left: _cardsLeft + cardWidth + 2,
                        onTap: onTapGoogle,
                      ),
                      for (final note in reviewNotes)
                        if (yIfToday(note.time) case final y?)
                          ..._reviewNote(context, note, y),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// [events]' timed ones on [day], each with its lane and how many lanes
/// its run of overlapping ones needs, so they sit side by side.
List<({GoogleEvent event, int lane, int lanes})> _googleLanes(
  List<GoogleEvent> events, {
  required DateTime day,
  required DateTime dayEnd,
}) {
  final timed = [
    for (final e in events)
      if (!e.allDay && e.start.isBefore(dayEnd) && e.end.isAfter(day)) e,
  ]..sort((a, b) => a.start.compareTo(b.start));
  final placed = <({GoogleEvent event, int lane, int lanes})>[];
  var run = <({GoogleEvent event, int lane})>[];
  var runEnd = day;
  void close() {
    final lanes = run.map((r) => r.lane + 1).fold(1, math.max);
    placed.addAll([
      for (final r in run) (event: r.event, lane: r.lane, lanes: lanes),
    ]);
    run = [];
  }

  for (final e in timed) {
    if (run.isNotEmpty && !e.start.isBefore(runEnd)) close();
    final ends = <int, DateTime>{};
    for (final r in run) {
      final end = ends[r.lane];
      if (end == null || r.event.end.isAfter(end)) ends[r.lane] = r.event.end;
    }
    var lane = 0;
    while (ends[lane]?.isAfter(e.start) ?? false) {
      lane++;
    }
    run.add((event: e, lane: lane));
    if (e.end.isAfter(runEnd)) runEnd = e.end;
  }
  if (run.isNotEmpty) close();
  return placed;
}

/// [events] drawn faintly at their times, [width] wide from the cards'
/// left, side by side where they overlap: behind the user's own events.
/// The whole day's aren't drawn: the Events page lists them above.
/// [onTop], they're over the user's events instead, nearly solid, so
/// they read over them.
List<Widget> _googleEvents(
  BuildContext context,
  List<GoogleEvent> events, {
  required DateTime day,
  required DateTime dayEnd,
  required double Function(DateTime) y,
  required double width,
  ValueChanged<GoogleEvent>? onTap,
  bool onTop = false,
}) {
  if (events.isEmpty) return const [];
  final theme = Theme.of(context);
  final dark = theme.brightness == Brightness.dark;
  final local = MaterialLocalizations.of(context);
  String time(DateTime t) =>
      local.formatTimeOfDay(TimeOfDay.fromDateTime(t.toLocal()));
  Widget ghost(GoogleEvent e) {
    final color = e.color;
    final ink = dark
        ? Color.lerp(color, Colors.white, 0.55)!
        : Color.lerp(color, Colors.black, 0.45)!;
    return Semantics(
      label: '${e.title}, ${e.calendar.name}, Google Calendar',
      button: onTap != null,
      excludeSemantics: true,
      child: Material(
        color: onTop
            ? Color.alphaBlend(
                color.withValues(alpha: dark ? 0.3 : 0.18),
                theme.colorScheme.surface,
              ).withValues(alpha: 0.94)
            : color.withValues(alpha: dark ? 0.22 : 0.14),
        elevation: onTop ? 2 : 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(6),
          side: BorderSide(color: color.withValues(alpha: 0.75)),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap == null ? null : () => onTap(e),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(6, 2, 6, 2),
            child: Text.rich(
              TextSpan(
                children: [
                  WidgetSpan(
                    alignment: PlaceholderAlignment.middle,
                    child: Padding(
                      padding: const EdgeInsets.only(right: 3),
                      child: Icon(Icons.event_outlined, size: 12, color: ink),
                    ),
                  ),
                  TextSpan(
                    text: e.title,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  TextSpan(text: '  ${time(e.start)}–${time(e.end)}'),
                ],
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelSmall?.copyWith(color: ink),
            ),
          ),
        ),
      ),
    );
  }

  return [
    for (final (:event, :lane, :lanes) in _googleLanes(
      events,
      day: day,
      dayEnd: dayEnd,
    ))
      Positioned(
        left: _cardsLeft + width * lane / lanes,
        top: y(event.start.isBefore(day) ? day : event.start),
        width: width / lanes - (lanes > 1 ? 2 : 0),
        height: math.max(
          16,
          y(event.end.isAfter(dayEnd) ? dayEnd : event.end) -
              y(event.start.isBefore(day) ? day : event.start),
        ),
        child: ghost(event),
      ),
  ];
}

/// A strip down the right edge, from [left], at each of [events]' times,
/// in its calendar's color: over everything, so one under the user's own
/// events still shows.
List<Widget> _googleMarks(
  List<GoogleEvent> events, {
  required DateTime day,
  required DateTime dayEnd,
  required double Function(DateTime) y,
  required double left,
  ValueChanged<GoogleEvent>? onTap,
}) => [
  for (final (:event, :lane, :lanes) in _googleLanes(
    events,
    day: day,
    dayEnd: dayEnd,
  ))
    Positioned(
      // Its lane's share of the strip, where they overlap.
      left: left + 4 * lane / lanes,
      top: y(event.start.isBefore(day) ? day : event.start),
      width: math.max(1.5, 4 / lanes),
      height: math.max(
        4,
        y(event.end.isAfter(dayEnd) ? dayEnd : event.end) -
            y(event.start.isBefore(day) ? day : event.start),
      ),
      child: GestureDetector(
        onTap: onTap == null ? null : () => onTap(event),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: event.color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      ),
    ),
];

/// The part of a proposal's review band, [from] to [through], on [day]:
/// [under] the events, its tint and outline; [over] them, its heading
/// where it starts and its `through` where it ends. Null if it's not on
/// the day.
({List<Widget> under, List<Widget> over})? _reviewBand(
  BuildContext context, {
  required DateTime day,
  required DateTime dayEnd,
  required DateTime from,
  required DateTime through,
  DateTime? claudeThrough,
  VoidCallback? onTapThrough,
  required double Function(DateTime) y,
}) {
  if (!from.isBefore(dayEnd) || !through.isAfter(day)) return null;
  final scheme = Theme.of(context).colorScheme;
  final colors = reviewColors(scheme);
  final starts = !from.isBefore(day);
  final ends = through.isBefore(dayEnd);
  final top = y(starts ? from : day);
  final bottom = y(ends ? through : dayEnd);
  final time = MaterialLocalizations.of(context)
      .formatTimeOfDay(TimeOfDay.fromDateTime(through.toLocal()));
  // A tab on the band's edge: above it at the top, below it at the foot.
  Widget tab(String text, String label, {required bool below}) => IgnorePointer(
    child: Semantics(
      label: label,
      child: ExcludeSemantics(
        child: Container(
          height: _tabHeight,
          padding: const EdgeInsets.symmetric(horizontal: 6),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: colors.line,
            borderRadius: BorderRadius.vertical(
              top: below ? Radius.zero : const Radius.circular(6),
              bottom: below ? const Radius.circular(6) : Radius.zero,
            ),
          ),
          child: Text(
            text,
            style: TextStyle(
              fontSize: _bandFontSize,
              fontWeight: FontWeight.w600,
              color: colors.onLine,
            ),
          ),
        ),
      ),
    ),
  );
  final line = BorderSide(color: colors.line, width: 2);
  // The stretch the user extended it by, past Claude's end.
  final extension = switch (claudeThrough) {
    final c? when c.isBefore(through) && c.isBefore(dayEnd) => (
      top: y(c.isBefore(day) ? day : c),
      shows: !c.isBefore(day),
    ),
    _ => null,
  };
  return (
    under: [
      Positioned(
        left: _timeWidth - 4,
        right: 2,
        top: top,
        height: math.max(0, bottom - top),
        child: IgnorePointer(
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: colors.tint,
              border: Border(
                left: line,
                right: line,
                top: starts ? line : BorderSide.none,
                bottom: ends ? line : BorderSide.none,
              ),
            ),
          ),
        ),
      ),
      if (extension case (:final top, shows: _))
        Positioned(
          left: _timeWidth - 4,
          right: 2,
          top: top,
          height: math.max(0, bottom - top),
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: scheme.secondaryContainer.withValues(alpha: 0.45),
                border: Border(
                  left: BorderSide(color: scheme.secondary, width: 2),
                  right: BorderSide(color: scheme.secondary, width: 2),
                ),
              ),
            ),
          ),
        ),
    ],
    over: [
      if (extension case (:final top, shows: true))
        Positioned(
          left: _timeWidth + _bandWidth + 4,
          top: top,
          child: IgnorePointer(
            child: Semantics(
              label: 'Extended by you, from here',
              child: ExcludeSemantics(
                child: Container(
                  height: _tabHeight,
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: scheme.secondary,
                    borderRadius: const BorderRadius.vertical(
                      bottom: Radius.circular(6),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.anchor, size: 10, color: scheme.onSecondary),
                      const SizedBox(width: 3),
                      Text(
                        'extended by you',
                        style: TextStyle(
                          fontSize: _bandFontSize,
                          fontWeight: FontWeight.w600,
                          color: scheme.onSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      if (starts)
        Positioned(
          right: 2,
          top: top - _tabHeight,
          child: tab(
            'What happened — to confirm',
            'What happened, to confirm, from here',
            below: false,
          ),
        ),
      if (ends)
        Positioned(
          right: 2,
          top: bottom,
          child: switch (onTapThrough) {
            // Tapped, to extend it: a pencil says so.
            final onTap? => Tooltip(
              message: 'Extend what happened',
              child: GestureDetector(
                // The tab itself takes no touches: this does, over it.
                behavior: HitTestBehavior.opaque,
                onTap: onTap,
                child: Semantics(
                  button: true,
                  label:
                      'What happened, to confirm, through $time. Tap to '
                      'extend it',
                  child: ExcludeSemantics(
                    child: Container(
                      height: _tabHeight,
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      decoration: BoxDecoration(
                        color: colors.line,
                        borderRadius: const BorderRadius.vertical(
                          bottom: Radius.circular(6),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'through $time',
                            style: TextStyle(
                              fontSize: _bandFontSize,
                              fontWeight: FontWeight.w600,
                              color: colors.onLine,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Icon(Icons.edit, size: 10, color: colors.onLine),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
            null => tab(
              'through $time',
              'What happened, to confirm, through $time',
              below: true,
            ),
          },
        ),
    ],
  );
}

/// What a cursor stops at, marked, pulsing -- steady with animations
/// turned off: a line across at each of the
/// [notes], in [noteColor], and on the bands a bar at each of the
/// [edges] of the events, in [edgeColor] -- each a height down the
/// timeline.
class _SnapMarks extends StatefulWidget {
  const _SnapMarks({
    required this.notes,
    required this.edges,
    required this.noteColor,
    required this.edgeColor,
  });

  final List<double> notes;
  final List<double> edges;
  final Color noteColor;
  final Color edgeColor;

  @override
  State<_SnapMarks> createState() => _SnapMarksState();
}

class _SnapMarksState extends State<_SnapMarks>
    with SingleTickerProviderStateMixin {
  late final _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
    value: 1,
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Steady, at their boldest, with animations turned off.
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) {
      _pulse
        ..stop()
        ..value = 1;
    } else if (!_pulse.isAnimating) {
      _pulse.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Semantics(
    label: [
      if (widget.notes.isNotEmpty) 'Notes marked as stops',
      if (widget.edges.isNotEmpty) "Events' edges marked as stops",
    ].join('. '),
    child: CustomPaint(
      painter: _SnapMarksPainter(
        notes: widget.notes,
        edges: widget.edges,
        noteColor: widget.noteColor,
        edgeColor: widget.edgeColor,
        pulse: _pulse,
      ),
    ),
  );
}

class _SnapMarksPainter extends CustomPainter {
  _SnapMarksPainter({
    required this.notes,
    required this.edges,
    required this.noteColor,
    required this.edgeColor,
    required this.pulse,
  }) : super(repaint: pulse);

  final List<double> notes;
  final List<double> edges;
  final Color noteColor;
  final Color edgeColor;
  final Animation<double> pulse;

  @override
  void paint(Canvas canvas, Size size) {
    final alpha = 0.4 + 0.6 * pulse.value;
    final note = Paint()
      ..color = noteColor.withValues(alpha: alpha)
      ..strokeWidth = 2.5;
    for (final y in notes) {
      canvas.drawLine(Offset(_timeWidth, y), Offset(size.width, y), note);
    }
    final edge = Paint()
      ..color = edgeColor.withValues(alpha: alpha)
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    for (final y in edges) {
      canvas.drawLine(
        Offset(_timeWidth + 2, y),
        Offset(_cardsLeft + 10, y),
        edge,
      );
    }
  }

  @override
  bool shouldRepaint(_SnapMarksPainter old) =>
      old.notes != notes ||
      old.edges != edges ||
      old.noteColor != noteColor ||
      old.edgeColor != edgeColor;
}

/// An event in a list: ringed in the secondary color, slightly pulsing --
/// steady with animations turned off -- with the list's [icon] in its
/// corner.
class _Listed extends StatefulWidget {
  const _Listed({required this.icon});

  final IconData icon;

  @override
  State<_Listed> createState() => _ListedState();
}

class _ListedState extends State<_Listed> with SingleTickerProviderStateMixin {
  late final _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
    value: 1,
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) {
      _pulse
        ..stop()
        ..value = 1;
    } else if (!_pulse.isAnimating) {
      _pulse.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return AnimatedBuilder(
      animation: _pulse,
      builder: (context, _) => Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: colors.secondary.withValues(
                  alpha: 0.06 + 0.08 * _pulse.value,
                ),
                borderRadius: BorderRadius.circular(_cardRadius + 2),
                border: Border.all(
                  color: colors.secondary.withValues(
                    alpha: 0.55 + 0.45 * _pulse.value,
                  ),
                  width: 2.5,
                ),
              ),
            ),
          ),
          Positioned(
            right: 6,
            bottom: 4,
            child: Container(
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                color: colors.secondary,
                shape: BoxShape.circle,
              ),
              child: Icon(widget.icon, size: 14, color: colors.onSecondary),
            ),
          ),
        ],
      ),
    );
  }
}

/// A ring round an event, in the primary color, pulsing: to pick it out.
class _Highlight extends StatefulWidget {
  const _Highlight();

  @override
  State<_Highlight> createState() => _HighlightState();
}

class _HighlightState extends State<_Highlight>
    with SingleTickerProviderStateMixin {
  late final _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 600),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary;
    return Semantics(
      label: 'Shown',
      child: AnimatedBuilder(
        animation: _pulse,
        builder: (context, _) => DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(_cardRadius + 3),
            border: Border.all(
              color: color.withValues(alpha: 0.5 + 0.5 * _pulse.value),
              width: 3,
            ),
          ),
        ),
      ),
    );
  }
}

/// A ring round the event the keyboard's on, in the primary color.
class _Keyed extends StatelessWidget {
  const _Keyed();

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Highlighted',
    child: DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(_cardRadius + 3),
        border: Border.all(
          color: Theme.of(context).colorScheme.primary,
          width: 3,
        ),
      ),
    ),
  );
}

/// Where events overlap, from [top] to [bottom]: a red tint over them,
/// edged in red, labeled "overlap" at its top right. Only to see; it
/// takes no taps.
List<Widget> _overlap(BuildContext context, double top, double bottom) {
  final red = Theme.of(context).colorScheme.error;
  final onRed = Theme.of(context).colorScheme.onError;
  return [
    Positioned(
      left: _timeWidth,
      right: 8,
      top: top,
      height: math.max(1, bottom - top),
      child: IgnorePointer(
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: red.withValues(alpha: 0.18),
            border: Border.all(color: red, width: 1.5),
          ),
        ),
      ),
    ),
    Positioned(
      right: 8,
      top: top,
      child: IgnorePointer(
        child: Container(
          height: _tabHeight,
          padding: const EdgeInsets.symmetric(horizontal: 6),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: red,
            borderRadius: const BorderRadius.only(
              bottomLeft: Radius.circular(6),
            ),
          ),
          child: Text(
            'overlap',
            style: TextStyle(
              fontSize: _bandFontSize,
              fontWeight: FontWeight.w600,
              color: onRed,
            ),
          ),
        ),
      ),
    ),
  ];
}

/// A proposal's [note], at [y]: a line across, over the events, in the
/// highlight if it's selected, and on the priority band a badge saying
/// what became of it.
List<Widget> _reviewNote(BuildContext context, ReviewNote note, double y) {
  final colors = Theme.of(context).colorScheme;
  final color = note.selected
      ? colors.primary
      : note.kind == ReviewNoteKind.ignored ||
            note.kind == ReviewNoteKind.compacted
      ? colors.outline
      : colors.tertiary;
  final halo = note.selected ? 14.0 : 0.0;
  const badge = 18.0;
  return [
    Positioned(
      left: _timeWidth,
      right: 0,
      top: y - halo / 2 - 1,
      height: halo + 2 + (note.selected ? 1 : 0),
      child: IgnorePointer(
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: note.selected
                ? colors.primary.withValues(alpha: 0.18)
                : null,
          ),
          child: Center(
            child: Container(
              height: note.selected ? 3 : 2,
              color: color.withValues(alpha: note.selected ? 1 : 0.85),
            ),
          ),
        ),
      ),
    ),
    Positioned(
      left: _timeWidth + (_bandWidth - badge) / 2,
      top: y - badge / 2,
      child: IgnorePointer(
        child: Semantics(
          label: 'Note: ${note.kind.description}',
          child: Container(
            width: badge,
            height: badge,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              border: Border.all(color: colors.surface, width: 1.5),
            ),
            child: Icon(note.kind.icon, size: 11, color: colors.surface),
          ),
        ),
      ),
    ),
  ];
}

/// What became of a note in a compaction proposal.
enum ReviewNoteKind {
  /// Its text was added to an event.
  annotated(Icons.subdirectory_arrow_right, 'added to an event'),

  /// It sets an event's start or end, and isn't added to one.
  setsEdge(Icons.vertical_align_center, "sets an event's start or end"),

  /// Claude left it out: it's added to no event.
  ignored(Icons.do_not_disturb_alt, 'not added to any event'),

  /// None of those.
  other(Icons.sticky_note_2_outlined, 'not used'),

  /// An earlier compaction used it: there as context.
  compacted(Icons.check, 'compacted earlier'),

  /// Added to an event because the user extended the proposal to take
  /// it in -- not Claude.
  extended(Icons.person_add_alt_1, 'added when you extended it');

  const ReviewNoteKind(this.icon, this.description);

  final IconData icon;
  final String description;
}

/// A note in a compaction proposal, at [time], as [DayTimeline] draws it:
/// what became of it, and whether it's the one [selected].
class ReviewNote {
  const ReviewNote({
    required this.time,
    required this.kind,
    this.selected = false,
  });

  final DateTime time;
  final ReviewNoteKind kind;
  final bool selected;
}

/// How tall the tabs on a review band's edges are.
const _tabHeight = 15.0;

/// The colors of a proposal's review band: its [tint], and the [line]
/// round it, with text [onLine]; an event in it is [card], and one
/// changed since the user last looked, [changed]: stronger.
({Color tint, Color line, Color onLine, Color card, Color changed})
reviewColors(ColorScheme colors) => (
  tint: colors.tertiaryContainer.withValues(alpha: 0.35),
  line: colors.tertiary,
  onLine: colors.onTertiary,
  card: Color.alphaBlend(
    colors.tertiaryContainer.withValues(alpha: 0.45),
    colors.surfaceContainerHigh,
  ),
  changed: colors.tertiaryContainer,
);

/// What a compaction proposal says of an event in it: a [label] of what
/// it does to it, if it does anything -- "Moved, was 7:45–8:15" -- said
/// for accessibility, not drawn, so the event takes no more room than
/// its time gives it; an [icon], if it has one, before its summary; and
/// whether that's [changed] since the user last looked, marked with a
/// dot there.
class EventMark {
  const EventMark({
    this.label,
    this.icon,
    this.changed = false,
    this.selected = false,
  });

  final String? label;
  final IconData? icon;
  final bool changed;

  /// Whether it's the one being looked at, outlined: the cancel, or an
  /// event an addition is used at, under the proposal's bar.
  final bool selected;
}

/// A dot, marking an event changed since the user last looked.
class _Dot extends StatelessWidget {
  const _Dot({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    width: _dotSize,
    height: _dotSize,
    decoration: BoxDecoration(color: color, shape: BoxShape.circle),
  );
}

/// The color of a note not yet compacted, and its label: the last
/// compaction's, fainter, as it's only a hint.
Color _noteColor(ColorScheme colors) => colors.tertiary.withValues(alpha: 0.6);

/// What's the same on every [DayTimeline] for [day] at [scale], so it
/// can be drawn apart, kept still while the days slide over it: a line
/// across at each hour, and down its left edge the times, midnight at
/// both ends, then the hours, as many as fit. A day's timeline covers
/// those its own labels would overlap.
class TimelineAxis extends StatelessWidget {
  const TimelineAxis({
    super.key,
    required this.day,
    this.dayEnd,
    required this.scale,
  });

  /// Midnight, local time, at the start of the day.
  final DateTime day;

  /// Midnight at its end: the day after [day]'s, unless it runs on over
  /// days stacked on it.
  final DateTime? dayEnd;
  final double scale;

  @override
  Widget build(BuildContext context) =>
      CustomPaint(painter: _axisPainter(context, day, scale, dayEnd: dayEnd));
}

_AxisPainter _axisPainter(
  BuildContext context,
  DateTime day,
  double scale, {
  DateTime? dayEnd,
}) {
  final theme = Theme.of(context);
  return _AxisPainter(
    day: day,
    dayEnd: dayEnd ?? DateTime(day.year, day.month, day.day + 1),
    scale: scale,
    timeLabel: (t) =>
        MaterialLocalizations.of(context)
            .formatTimeOfDay(TimeOfDay.fromDateTime(t.toLocal())),
    scaler: MediaQuery.textScalerOf(context),
    baseStyle: theme.textTheme.labelSmall ?? const TextStyle(),
    hourColor: theme.colorScheme.onSurfaceVariant,
    gridColor: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
  );
}

class _CardStyles {
  const _CardStyles({
    required this.summary,
    required this.action,
    required this.chip,
  });

  final TextStyle? summary;
  final TextStyle? action;
  final TextStyle? chip;
}

/// An event: its summary, its actions' diamonds stacked by its chips --
/// and, if it's for any goals, a stack of goal icons saying how many --
/// then as many of its actions, each after a diamond, and then its goals,
/// each after a goal icon, as fit whole.
class _EventCard extends StatelessWidget {
  const _EventCard({
    required this.placement,
    required this.joinedAbove,
    required this.joinedBelow,
    required this.seamColor,
    required this.actions,
    this.goalNames = const {},
    required this.details,
    required this.styles,
    required this.onTap,
    required this.onLongPress,
    required this.faded,
    required this.timeLabel,
    this.mark,
  });

  final TimelinePlacement placement;

  /// Whether the event before it ends where it starts, and the one after
  /// starts where it ends. Where two meet, the corners are square and
  /// only the lower one's outline is drawn, so the line between them is
  /// no thicker than the rest.
  final bool joinedAbove;
  final bool joinedBelow;

  /// The color of the hairline across the top of its strip, dividing it
  /// from the one above's, if they're too alike to tell apart.
  final Color? seamColor;
  final Map<String, PlanAction> actions;

  /// Goals' titles by id.
  final Map<String, String> goalNames;

  /// The names of its locations, of the people with the user, and of
  /// those it was for, listed down its right where there's room.
  final List<(_Detail, List<String>)> details;
  final _CardStyles styles;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  /// Whether it's drawn faintly: being moved from here.
  final bool faded;
  final String Function(DateTime) timeLabel;

  /// What a compaction proposal says of it, if it's in one.
  final EventMark? mark;

  Color? _colorOf(String id) => switch (actions[id]) {
    final action? => parseColor(
      action.effectiveColor ?? action.backgroundColor,
    ),
    null => null,
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final event = placement.event;
    final cancelled = event.isCancelled;
    final summary = switch (event.summary) {
      final s? when s.isNotEmpty => s,
      _ => '(no summary)',
    };
    final ids = event.actionIds;
    final names = event.actionNames;
    final outline = _shownColor(event, actions);
    final muted = colors.onSurfaceVariant;
    final strike = cancelled ? TextDecoration.lineThrough : null;
    final duration = formatDuration(event.end.difference(event.start));
    final goals = event.goals;
    // Those still there, by title, to list under its actions.
    final goalTitles = [for (final g in goals) ?goalNames[g.goalId]];
    final fill = switch (mark) {
      null => colors.surfaceContainerHigh,
      EventMark(changed: true) => reviewColors(colors).changed,
      _ => reviewColors(colors).card,
    };
    final card = Semantics(
      label:
          '$summary, ${timeLabel(event.start)} to ${timeLabel(event.end)}'
          '${event.isCommute ? ', commute' : ''}'
          '${cancelled ? ', cancelled' : ''}'
          '${switch (mark) {
            null => '',
            EventMark(:final label?, :final changed) => '. To confirm: $label'
                '${changed ? ', changed since you looked' : ''}',
            _ => '. To confirm',
          }}',
      button: onTap != null,
      onLongPress: onLongPress,
      onLongPressHint: onLongPress == null ? null : 'Move',
      excludeSemantics: true,
      child: Material(
        color: fill,
        // Square on the left, where its fill from the band meets it, and
        // where it meets another event.
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.only(
            topRight: Radius.circular(joinedAbove ? 0 : _cardRadius),
            bottomRight: Radius.circular(joinedBelow ? 0 : _cardRadius),
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: CustomPaint(
          foregroundPainter: _OutlinePainter(
            color: outline,
            topRadius: joinedAbove ? 0 : _cardRadius,
            bottomRadius: joinedBelow ? 0 : _cardRadius,
            bottom: !joinedBelow,
            seamColor: seamColor,
          ),
          child: InkWell(
            onTap: onTap,
            onLongPress: onLongPress,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  width: _stripWidth,
                  child: ColoredBox(color: outline),
                ),
                Expanded(
                  child: Padding(
                    padding: _cardPadding,
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final listed = _actionsThatFit(
                          context,
                          constraints.maxHeight,
                          count: ids.length,
                        );
                        // Its goals, under its actions, as many as fit.
                        final goalsListed =
                            _actionsThatFit(
                              context,
                              constraints.maxHeight,
                              count: ids.length + goalTitles.length,
                            ) -
                            listed;
                        // Its locations and people, only where there's
                        // room beside its actions.
                        final detailStyle = styles.action?.copyWith(
                          color: muted,
                          decoration: strike,
                        );
                        final detailWidth =
                            constraints.maxWidth * _detailsWidthFraction;
                        final packed =
                            constraints.maxWidth < _detailsMinCardWidth
                            ? const <List<(_Detail, String)>>[]
                            : _packDetails(context, detailWidth, detailStyle);
                        // Its locations are listed only if all their lines
                        // fit; if not, they're on its summary's line.
                        final locationLines = packed
                            .where((line) => line.first.$1 == _Detail.location)
                            .length;
                        final locationsListed =
                            locationLines > 0 &&
                            _actionsThatFit(
                                  context,
                                  constraints.maxHeight,
                                  count: packed.length,
                                ) >=
                                locationLines;
                        final detailLines = locationsListed
                            ? packed
                            : [
                                for (final line in packed)
                                  if (line.first.$1 != _Detail.location) line,
                              ];
                        final detailed = _actionsThatFit(
                          context,
                          constraints.maxHeight,
                          count: detailLines.length,
                        );
                        final summaryStyle = styles.summary?.copyWith(
                          color: cancelled ? muted : null,
                          decoration: strike,
                        );
                        final located = locationsListed
                            ? null
                            : switch ([
                                for (final (kind, names) in details)
                                  if (kind == _Detail.location) ...names,
                              ]) {
                                final names when names.isNotEmpty => names.join(
                                  ', ',
                                ),
                                _ => null,
                              };
                        final (:locationWidth, :goalStack) = _summaryLine(
                          context,
                          constraints.maxWidth,
                          summary: summary,
                          summaryStyle: summaryStyle,
                          location: located,
                          locationStyle: detailStyle,
                          goals: goals.length,
                          duration: duration,
                        );
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                if (mark case EventMark(
                                  :final icon,
                                  :final changed,
                                )) ...[
                                  if (changed) ...[
                                    _Dot(color: colors.tertiary),
                                    const SizedBox(width: _dotGap),
                                  ],
                                  if (icon != null) ...[
                                    Icon(
                                      icon,
                                      size: _markIconSize,
                                      color: colors.tertiary,
                                    ),
                                    const SizedBox(width: _markIconGap),
                                  ],
                                ],
                                if (event.isCommute) ...[
                                  Icon(
                                    Icons.directions_walk,
                                    size: _commuteIconSize,
                                    color: muted,
                                  ),
                                  const SizedBox(width: _commuteIconGap),
                                ],
                                Expanded(
                                  child: Text(
                                    summary,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: summaryStyle,
                                  ),
                                ),
                                if (located != null)
                                  SizedBox(
                                    width: locationWidth,
                                    child: ClipRect(
                                      child: Padding(
                                        padding: const EdgeInsets.only(
                                          left: _chipGap,
                                        ),
                                        child: Align(
                                          alignment: Alignment.centerRight,
                                          child: _DetailLine(
                                            items: [
                                              (_Detail.location, located),
                                            ],
                                            style: detailStyle,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                if (ids.isNotEmpty)
                                  _DiamondStack(
                                    colors: [
                                      for (final id in ids) _colorOf(id),
                                    ],
                                    outline: muted,
                                    edge: fill,
                                  ),
                                if (duration != null)
                                  // Square-cornered when it's drawn taller than
                                  // it lasts; open at the top when it's drawn
                                  // shorter, having started above.
                                  _Chip(
                                    text: duration,
                                    style: styles.chip?.copyWith(color: muted),
                                    border: colors.outline,
                                    shape: placement.compressed
                                        ? _ChipShape.square
                                        : placement.shortened
                                        ? _ChipShape.openTop
                                        : _ChipShape.rounded,
                                  ),
                                if (goalStack && goals.isNotEmpty)
                                  Padding(
                                    padding: const EdgeInsets.only(
                                      left: _chipGap,
                                    ),
                                    child: GoalStack(
                                      count: goals.length,
                                      size: _goalIconSize,
                                      color: muted,
                                    ),
                                  ),
                              ],
                            ),
                            if (listed > 0 || goalsListed > 0 || detailed > 0)
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        for (final (i, id)
                                            in ids.take(listed).indexed)
                                          Row(
                                            children: [
                                              _Diamond(
                                                color: _colorOf(id),
                                                outline: muted,
                                              ),
                                              const SizedBox(width: 6),
                                              Expanded(
                                                child: Text(
                                                  switch (actions[id]) {
                                                    final action? => actionName(
                                                      action,
                                                    ),
                                                    null =>
                                                      (i < names.length
                                                              ? names[i]
                                                              : null) ??
                                                          id,
                                                  },
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: styles.action
                                                      ?.copyWith(
                                                        color: muted,
                                                        decoration: strike,
                                                      ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        for (final title in goalTitles.take(
                                          goalsListed,
                                        ))
                                          Row(
                                            children: [
                                              GoalIcon(size: 10, color: muted),
                                              const SizedBox(width: 6),
                                              Expanded(
                                                child: Text(
                                                  title,
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: styles.action
                                                      ?.copyWith(
                                                        color: muted,
                                                        decoration: strike,
                                                      ),
                                                ),
                                              ),
                                            ],
                                          ),
                                      ],
                                    ),
                                  ),
                                  if (detailed > 0) ...[
                                    const SizedBox(width: 8),
                                    ConstrainedBox(
                                      constraints: BoxConstraints(
                                        maxWidth: detailWidth,
                                      ),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.end,
                                        children: [
                                          for (final line in detailLines.take(
                                            detailed,
                                          ))
                                            _DetailLine(
                                              items: line,
                                              style: detailStyle,
                                            ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                          ],
                        );
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    final shown = mark?.selected ?? false
        ? DecoratedBox(
            position: DecorationPosition.foreground,
            decoration: BoxDecoration(
              border: Border.all(color: colors.primary, width: 2.5),
              borderRadius: BorderRadius.only(
                topRight: Radius.circular(joinedAbove ? 0 : _cardRadius),
                bottomRight: Radius.circular(joinedBelow ? 0 : _cardRadius),
              ),
            ),
            child: card,
          )
        : card;
    // Faint, but over the page's background, not what's behind it: a
    // Google Calendar event under it stays hidden, as under any other.
    return faded
        ? ColoredBox(
            color: theme.scaffoldBackgroundColor,
            child: Opacity(opacity: 0.35, child: shown),
          )
        : shown;
  }
}

extension on _EventCard {
  /// Its [details] in lines no wider than [width], in [style]: each kind
  /// on lines of its own, side by side while they fit. One too wide even
  /// alone is on a line by itself, cut short.
  List<List<(_Detail, String)>> _packDetails(
    BuildContext context,
    double width,
    TextStyle? style,
  ) {
    double widthOf(String text) => _widthOf(context, text, style);

    final lines = <List<(_Detail, String)>>[];
    for (final (kind, names) in details) {
      var line = <(_Detail, String)>[];
      var used = 0.0;
      for (final name in names) {
        final each = _detailIconSize + _detailIconGap + widthOf(name);
        if (line.isNotEmpty && used + _detailGap + each > width) {
          lines.add(line);
          line = [];
          used = 0;
        }
        used += (line.isEmpty ? 0 : _detailGap) + each;
        line.add((kind, name));
      }
      lines.add(line);
    }
    return lines;
  }

  /// How wide [text] is on one line, in [style].
  double _widthOf(BuildContext context, String text, TextStyle? style) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: DefaultTextStyle.of(context).style.merge(style),
      ),
      textDirection: TextDirection.ltr,
      textScaler: MediaQuery.textScalerOf(context),
      maxLines: 1,
    )..layout();
    final width = painter.width.ceilToDouble();
    painter.dispose();
    return width;
  }

  /// What its mark takes at the start of its summary's line: its dot and
  /// its icon, those it has.
  double get _markWidth => switch (mark) {
    null => 0,
    EventMark(:final changed, :final icon) =>
      (changed ? _dotSize + _dotGap : 0) +
          (icon == null ? 0 : _markIconSize + _markIconGap),
  };

  /// How its summary's line, [width] wide, fits its [location] (if
  /// it's there) between its summary and its diamonds: as much of it as
  /// fits once its summary has whatever it needs of half the line. If
  /// that's not all of it, the line goes without its stack of [goals]'
  /// icons, to make more room.
  ({double locationWidth, bool goalStack}) _summaryLine(
    BuildContext context,
    double width, {
    required String summary,
    required TextStyle? summaryStyle,
    required String? location,
    required TextStyle? locationStyle,
    required int goals,
    required String? duration,
  }) {
    if (location == null) return (locationWidth: 0, goalStack: true);
    double chip(String text, TextStyle? style) =>
        _chipGap + 2 * _chipPadding + _widthOf(context, text, style);
    final ids = placement.event.actionIds;
    final room =
        width -
        _markWidth -
        (placement.event.isCommute ? _commuteIconSize + _commuteIconGap : 0) -
        (ids.isEmpty ? 0 : _DiamondStack.widthOf(ids.length)) -
        (duration == null ? 0 : chip(duration, styles.chip));
    final wanted =
        _chipGap +
        _detailIconSize +
        _detailIconGap +
        _widthOf(context, location, locationStyle);
    final summaryWidth = _widthOf(context, summary, summaryStyle);
    double fit(double room) =>
        math.max(0, math.min(wanted, room - math.min(summaryWidth, room / 2)));
    final stack = goals == 0
        ? 0.0
        : _chipGap +
              _goalIconSize * GoalPainter.widthOf(math.min(goals, 2)) / 24;
    final withGoals = fit(room - stack);
    return withGoals >= wanted
        ? (locationWidth: withGoals, goalStack: true)
        : (locationWidth: fit(room), goalStack: false);
  }

  /// How many of its [count] actions' lines fit whole in [height], under
  /// its summary and chips.
  int _actionsThatFit(
    BuildContext context,
    double height, {
    required int count,
  }) {
    if (count == 0 || !height.isFinite) return count;
    final base = DefaultTextStyle.of(context).style;
    final scaler = MediaQuery.textScalerOf(context);
    double line(TextStyle? style) => (TextPainter(
      text: TextSpan(text: 'Hg', style: base.merge(style)),
      textDirection: TextDirection.ltr,
      textScaler: scaler,
      maxLines: 1,
    )..layout()).height;
    // A chip's text, and its border above and below.
    final above = math.max(line(styles.summary), line(styles.chip) + 2);
    // As tall as its diamond, at least.
    final each = math.max(line(styles.action), 10.0);
    return ((height - above) / each).floor().clamp(0, count);
  }
}

/// The outline round an event, in [color], inside its edge so it's no
/// taller than its piece of the band: square on the left, where the fill
/// from the band meets it, its top right corner [topRadius] round and
/// its bottom right [bottomRadius]; and with no [bottom] edge where the
/// event after it starts, whose top edge is drawn there instead. Over
/// the top of the strip down its edge, a hairline in [seamColor], if
/// it has one.
class _OutlinePainter extends CustomPainter {
  _OutlinePainter({
    required this.color,
    required this.topRadius,
    required this.bottomRadius,
    required this.bottom,
    this.seamColor,
  });

  final Color color;
  final double topRadius;
  final double bottomRadius;
  final bool bottom;
  final Color? seamColor;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = (Offset.zero & size).deflate(_outlineWidth / 2);
    final top = Radius.circular(math.max(0, topRadius - _outlineWidth / 2));
    final low = Radius.circular(math.max(0, bottomRadius - _outlineWidth / 2));
    final path = Path()
      ..moveTo(rect.left, bottom ? rect.bottom : size.height)
      ..lineTo(rect.left, rect.top)
      ..lineTo(rect.right - top.x, rect.top)
      ..arcToPoint(Offset(rect.right, rect.top + top.y), radius: top)
      ..lineTo(rect.right, bottom ? rect.bottom - low.y : size.height);
    if (bottom) {
      path
        ..arcToPoint(Offset(rect.right - low.x, rect.bottom), radius: low)
        ..lineTo(rect.left, rect.bottom);
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = _outlineWidth,
    );
    if (seamColor case final seam?) {
      canvas.drawRect(
        const Rect.fromLTWH(0, 0, _stripWidth, _seamWidth),
        Paint()..color = seam,
      );
    }
  }

  @override
  bool shouldRepaint(_OutlinePainter old) =>
      old.seamColor != seamColor ||
      old.color != color ||
      old.topRadius != topRadius ||
      old.bottomRadius != bottomRadius ||
      old.bottom != bottom;
}

/// How a [_Chip]'s outline is drawn.
enum _ChipShape {
  rounded,

  /// With square corners.
  square,

  /// Rounded, with no top edge.
  openTop,
}

/// What one of an event's details is: a location it was at, someone
/// with the user, or someone it was for.
enum _Detail { location, withPerson, forPerson }

/// A line of an event's details, side by side, each after its kind's
/// icon, as much of each as fits.
class _DetailLine extends StatelessWidget {
  const _DetailLine({required this.items, this.style});

  final List<(_Detail, String)> items;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      for (final (i, (kind, text)) in items.indexed) ...[
        if (i > 0) const SizedBox(width: _detailGap),
        switch (kind) {
          _Detail.location => Icon(
            Icons.place_outlined,
            size: _detailIconSize,
            color: style?.color,
          ),
          _Detail.withPerson => Icon(
            Icons.person_outline,
            size: _detailIconSize,
            color: style?.color,
          ),
          _Detail.forPerson => DottedPersonIcon(
            size: _detailIconSize,
            color: style?.color,
          ),
        },
        const SizedBox(width: _detailIconGap),
        Flexible(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: style,
          ),
        ),
      ],
    ],
  );
}

/// A person's outline, as [Icons.person_outline] draws it, but dotted:
/// someone an event was for, who wasn't there.
class DottedPersonIcon extends StatelessWidget {
  const DottedPersonIcon({super.key, this.size = 24, this.color});

  final double size;

  /// Its color; by default, the [IconTheme]'s.
  final Color? color;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: size,
    child: CustomPaint(
      painter: _DottedPersonPainter(
        color ?? IconTheme.of(context).color ?? const Color(0xFF000000),
      ),
    ),
  );
}

class _DottedPersonPainter extends CustomPainter {
  _DottedPersonPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final unit = size.width / 24;
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2 * unit
      ..strokeCap = StrokeCap.round;
    // On the 24-unit grid Material's icons are drawn on: a head, and
    // shoulders below it.
    final outline = Path()
      ..addOval(
        Rect.fromCircle(center: Offset(12 * unit, 8 * unit), radius: 4 * unit),
      )
      ..moveTo(4 * unit, 20 * unit)
      ..lineTo(4 * unit, 18 * unit)
      ..cubicTo(4 * unit, 15 * unit, 9 * unit, 14 * unit, 12 * unit, 14 * unit)
      ..cubicTo(
        15 * unit,
        14 * unit,
        20 * unit,
        15 * unit,
        20 * unit,
        18 * unit,
      )
      ..lineTo(20 * unit, 20 * unit)
      ..close();
    final dash = 2.5 * unit;
    final gap = 2.5 * unit;
    for (final metric in outline.computeMetrics()) {
      for (var d = 0.0; d < metric.length; d += dash + gap) {
        canvas.drawPath(metric.extractPath(d, d + dash), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_DottedPersonPainter old) => old.color != color;
}

/// A small box of [text] at the end of an event's summary: its duration,
/// or its priority.
class _Chip extends StatelessWidget {
  const _Chip({
    required this.text,
    required this.style,
    required this.border,
    this.shape = _ChipShape.rounded,
  });

  final String text;
  final TextStyle? style;
  final Color border;
  final _ChipShape shape;

  @override
  Widget build(BuildContext context) {
    final radius = shape == _ChipShape.square ? 0.0 : 4.0;
    final open = shape == _ChipShape.openTop;
    return Padding(
      padding: const EdgeInsets.only(left: _chipGap),
      child: CustomPaint(
        foregroundPainter: open ? _OpenTopPainter(border, radius) : null,
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: open ? null : Border.all(color: border),
            borderRadius: BorderRadius.circular(radius),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: _chipPadding),
            child: Text(text, style: style),
          ),
        ),
      ),
    );
  }
}

/// A chip's outline with no top edge: down its sides and round the
/// bottom, in [color], as wide as the others' borders.
class _OpenTopPainter extends CustomPainter {
  _OpenTopPainter(this.color, this.radius);

  final Color color;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = (Offset.zero & size).deflate(0.5);
    final corner = Radius.circular(radius - 0.5);
    canvas.drawPath(
      Path()
        ..moveTo(rect.left, rect.top)
        ..lineTo(rect.left, rect.bottom - corner.y)
        ..arcToPoint(
          Offset(rect.left + corner.x, rect.bottom),
          radius: corner,
          clockwise: false,
        )
        ..lineTo(rect.right - corner.x, rect.bottom)
        ..arcToPoint(
          Offset(rect.right, rect.bottom - corner.y),
          radius: corner,
          clockwise: false,
        )
        ..lineTo(rect.right, rect.top),
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        // A border's width; a stroke's default is a hairline.
        ..strokeWidth = 1,
    );
  }

  @override
  bool shouldRepaint(_OpenTopPainter old) =>
      old.color != color || old.radius != radius;
}

/// An event's actions' diamonds, overlapping, the first on top: one in
/// each action's color, or outlined in [outline] if it has none.
class _DiamondStack extends StatelessWidget {
  const _DiamondStack({
    required this.colors,
    required this.outline,
    required this.edge,
  });

  final List<Color?> colors;
  final Color outline;

  /// The card's color, edging each to stand apart from those it overlaps.
  final Color edge;

  /// How far along each is from the one before.
  static const _step = 5.0;

  /// A diamond's width, corner to corner.
  static const _size = 10.0;

  /// How wide [count] diamonds are, with the space before them.
  static double widthOf(int count) => _chipGap + _size + _step * (count - 1);

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(left: _chipGap),
    child: SizedBox(
      width: _size + _step * (colors.length - 1),
      height: _size,
      child: Stack(
        children: [
          for (final (i, color) in colors.indexed.toList().reversed)
            Positioned(
              left: _step * i,
              top: 0,
              width: _size,
              height: _size,
              child: Center(
                child: _Diamond(color: color, outline: outline, edge: edge),
              ),
            ),
        ],
      ),
    ),
  );
}

/// A small diamond in an action's [color], or outlined if it has none.
class _Diamond extends StatelessWidget {
  const _Diamond({required this.color, required this.outline, this.edge});

  final Color? color;
  final Color outline;

  /// The color it's edged in, outside it so it's as big as the rest: the
  /// card's, to stand apart from those it overlaps.
  final Color? edge;

  @override
  Widget build(BuildContext context) => Transform.rotate(
    angle: math.pi / 4,
    child: Container(
      width: 7,
      height: 7,
      decoration: BoxDecoration(
        color: color,
        border: color == null
            ? Border.all(color: outline)
            : edge != null
            ? Border.all(
                color: edge!,
                width: 0.75,
                strokeAlign: BorderSide.strokeAlignOutside,
              )
            : null,
      ),
    ),
  );
}

/// A line across the timeline to label: [label], [height] tall, centered
/// at [y] (on the line, unless that's too close to another), in place of
/// the times beside it.
typedef _Marker = ({double y, double height, String label, Color color});

/// [label] as a line's label is drawn: right-aligned in the time column,
/// its lines broken where it says, never by width, so no word is cut.
TextPainter _markerText(String label, TextStyle style, TextScaler scaler) =>
    TextPainter(
      text: TextSpan(text: label, style: style),
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.right,
      textScaler: scaler,
    )..layout();

/// The labels of the lines across the timeline, in the time column in
/// place of the times there: small text in its line's color.
class _MarkerLabelsPainter extends CustomPainter {
  _MarkerLabelsPainter({
    required this.markers,
    required this.style,
    required this.scaler,
  });

  final List<_Marker> markers;
  final TextStyle style;
  final TextScaler scaler;

  @override
  void paint(Canvas canvas, Size size) {
    for (final marker in markers) {
      final painter = _markerText(
        marker.label,
        style.copyWith(color: marker.color.withValues(alpha: 0.8)),
        scaler,
      );
      painter.paint(
        canvas,
        Offset(_timeWidth - 6 - painter.width, marker.y - painter.height / 2),
      );
      painter.dispose();
    }
  }

  @override
  bool shouldRepaint(_MarkerLabelsPainter old) =>
      old.markers.length != markers.length ||
      [for (final (i, m) in markers.indexed) m != old.markers[i]]
          .any((changed) => changed);
}

/// A time label to draw: [time] at [y], and whether an event starts or
/// ends there.
typedef _TimeLabel = ({DateTime time, double y, bool edge});

/// How tall a time label is, with room around it.
double _timeLabelHeight(TextScaler scaler) =>
    scaler.scale(_labelFontSize) * 1.3 + 2;

/// The hours of the day from [day] to [dayEnd], by how much each
/// deserves a label: every six hours, then every three, then the rest.
List<DateTime> _hoursOf(DateTime day, DateTime dayEnd) {
  final hours = [
    for (
      var t = DateTime(day.year, day.month, day.day, 1);
      t.isBefore(dayEnd);
      t = DateTime(t.year, t.month, t.day, t.hour + 1)
    )
      t,
  ];
  int rank(DateTime t) => t.hour % 6 == 0 ? 0 : (t.hour % 3 == 0 ? 1 : 2);
  return hours..sort((a, b) => rank(a).compareTo(rank(b)));
}

/// The times a [TimelineAxis] shows: midnight at both ends, then the
/// hours, as many as fit.
List<_TimeLabel> _axisLabels({
  required DateTime day,
  required DateTime dayEnd,
  required double scale,
  required double labelHeight,
}) {
  double y(DateTime t) =>
      timelineOffset(t, day: day, dayEnd: dayEnd, scale: scale);
  return placeLabels(
    [
      for (final t in [day, dayEnd, ..._hoursOf(day, dayEnd)])
        (time: t, y: y(t), edge: false),
    ],
    top: (l) => l.y - labelHeight / 2,
    height: labelHeight,
  );
}

/// The [TimelineAxis]: the hours' lines, and the times, midnight at both
/// ends, then the hours, as many as fit.
class _AxisPainter extends CustomPainter {
  _AxisPainter({
    required this.day,
    required this.dayEnd,
    required this.scale,
    required this.timeLabel,
    required this.scaler,
    required this.baseStyle,
    required this.hourColor,
    required this.gridColor,
  });

  final DateTime day;
  final DateTime dayEnd;
  final double scale;
  final String Function(DateTime) timeLabel;
  final TextScaler scaler;

  /// The theme's text style the labels are drawn in, for its font.
  final TextStyle baseStyle;
  final Color hourColor;
  final Color gridColor;

  @override
  void paint(Canvas canvas, Size size) {
    double y(DateTime t) =>
        timelineOffset(t, day: day, dayEnd: dayEnd, scale: scale);
    final grid = Paint()
      ..color = gridColor
      ..strokeWidth = 1;
    for (final hour in [day, ..._hoursOf(day, dayEnd), dayEnd]) {
      canvas.drawLine(
        Offset(_timeWidth, y(hour)),
        Offset(size.width, y(hour)),
        grid,
      );
    }
    final style = baseStyle.copyWith(
      fontSize: _labelFontSize,
      height: 1.3,
      color: hourColor,
      fontWeight: FontWeight.w400,
    );
    for (final label in _axisLabels(
      day: day,
      dayEnd: dayEnd,
      scale: scale,
      labelHeight: _timeLabelHeight(scaler),
    )) {
      final painter = TextPainter(
        text: TextSpan(text: timeLabel(label.time), style: style),
        textDirection: TextDirection.ltr,
        textScaler: scaler,
        maxLines: 1,
      )..layout();
      painter.paint(
        canvas,
        Offset(_timeWidth - 6 - painter.width, label.y - painter.height / 2),
      );
      painter.dispose();
    }
  }

  @override
  bool shouldRepaint(_AxisPainter old) =>
      old.scale != scale ||
      old.day != day ||
      old.hourColor != hourColor ||
      old.gridColor != gridColor ||
      old.scaler != scaler;
}

/// How tall a label on the band of weather is: a chance of rain's, or a
/// temperature's.
double _bandLabelHeight(TextScaler scaler) =>
    scaler.scale(_bandFontSize - 1) * 1.2 + 2;

/// Where the chance of rain is labeled down the band, [y] placing a time:
/// where it starts being much, and where it changes much -- by the
/// nearest ten -- as many as fit, none above the [day]'s start.
List<({double top, int chance})> _rainLabels(
  List<WeatherSpan> shown, {
  required double Function(DateTime) y,
  required DateTime day,
  required TextScaler scaler,
}) {
  int tens(WeatherSpan? span) => (((span?.rainChance ?? 0) + 5) ~/ 10) * 10;
  final starts = [
    for (final (i, span) in shown.indexed)
      if (tens(span) >= 20 && tens(span) != tens(i > 0 ? shown[i - 1] : null))
        (top: math.max(y(span.start), y(day)), chance: span.rainChance!),
  ];
  return placeLabels(
    starts,
    top: (l) => l.top,
    height: _bandLabelHeight(scaler),
  );
}

/// The temperature down a [DayTimeline]'s band of [weather], as [label]
/// says it, at [opacity], of the [temperatures] -- before now too: every
/// third hour, in the spans an hour long or shorter, from [from] if
/// that's in the day or else from midnight; and
/// once in the middle of each longer span. One that would cover a chance
/// of rain's label goes just below it, and one that would cover a
/// sunrise or sunset ([sun]) is left out.
@visibleForTesting
class TemperatureLabelsPainter extends CustomPainter {
  TemperatureLabelsPainter({
    required this.day,
    required this.dayEnd,
    required this.scale,
    required this.weather,
    required this.temperatures,
    required this.sun,
    required this.label,
    required this.from,
    required this.opacity,
    required this.scaler,
    required this.baseStyle,
  });

  final DateTime day;
  final DateTime dayEnd;
  final double scale;
  final List<WeatherSpan> weather;

  /// The spans the temperatures are of: from when the forecast was
  /// fetched, before now too.
  final List<WeatherSpan> temperatures;
  final List<SunTime> sun;
  final String Function(double celsius) label;
  final DateTime? from;
  final double opacity;
  final TextScaler scaler;
  final TextStyle baseStyle;

  double _y(DateTime t) =>
      timelineOffset(t, day: day, dayEnd: dayEnd, scale: scale);

  @override
  void paint(Canvas canvas, Size size) {
    if (opacity <= 0) return;
    const left = _timeWidth + _bandPadding;
    const width = _bandWidth - 2 * _bandPadding;
    final labelHeight = _bandLabelHeight(scaler);
    final inDay = [
      for (final span in weather)
        if (span.end.isAfter(day) && span.start.isBefore(dayEnd)) span,
    ];
    final rainLabels = [
      for (final l in _rainLabels(inDay, y: _y, day: day, scaler: scaler))
        l.top,
    ];
    final sunYs = [
      for (final s in sun)
        if (!s.at.isBefore(day) && s.at.isBefore(dayEnd)) _y(s.at),
    ];
    final shown = [
      for (final span in temperatures)
        if (span.celsius != null &&
            span.end.isAfter(day) &&
            span.start.isBefore(dayEnd))
          span,
    ];
    if (shown.isEmpty) return;
    // Every third hour from [from], if it's in the day, or else from
    // midnight, where the forecast says.
    final anchor = switch (from) {
      final from? when !from.isBefore(day) && from.isBefore(dayEnd) => from,
      _ => day,
    };
    final times = <(DateTime, double)>[
      for (
        var t = anchor;
        t.isBefore(dayEnd);
        t = t.add(const Duration(hours: 3))
      )
        if (shown
                .where((s) => !t.isBefore(s.start) && t.isBefore(s.end))
                .firstOrNull
            case final span? when span.length <= const Duration(hours: 1))
          (t, span.celsius!),
      // Once in the middle of each longer span.
      for (final span in shown)
        if (span.length > const Duration(hours: 1))
          if ((
                span.start.isBefore(day) ? day : span.start,
                span.end.isAfter(dayEnd) ? dayEnd : span.end,
              )
              case (final from, final to))
            (from.add(to.difference(from) ~/ 2), span.celsius!),
    ]..sort((a, b) => a.$1.compareTo(b.$1));
    final candidates = <({double top, double celsius})>[];
    for (final (t, celsius) in times) {
      var top = _y(t) - labelHeight / 2;
      // Just below a chance of rain labeled there.
      for (final rain in rainLabels) {
        if ((rain - top).abs() < labelHeight) top = rain + labelHeight + 1;
      }
      if (rainLabels.any((r) => (r - top).abs() < labelHeight)) continue;
      if (sunYs.any(
        (y) =>
            (y - (top + labelHeight / 2)).abs() <
            (_sunBadgeHeight + labelHeight) / 2,
      )) {
        continue;
      }
      candidates.add((top: top, celsius: celsius));
    }
    final style = baseStyle.copyWith(
      fontSize: _bandFontSize - 1,
      fontWeight: FontWeight.w700,
      color: Colors.black87.withValues(alpha: 0.87 * opacity),
      height: 1.2,
    );
    final fill = Paint()
      ..color = Colors.white.withValues(alpha: 0.95 * opacity);
    for (final l in placeLabels(
      candidates,
      top: (l) => l.top,
      height: labelHeight,
    )) {
      final rect = Rect.fromLTWH(left, l.top, width, labelHeight);
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(2)),
        fill,
      );
      final painter = TextPainter(
        text: TextSpan(text: label(l.celsius), style: style),
        textDirection: TextDirection.ltr,
        textScaler: scaler,
        maxLines: 1,
      )..layout();
      // Narrowed to fit, if it must be.
      final squeeze = math.min(1.0, (width - 1) / painter.width);
      canvas.save();
      canvas.translate(rect.center.dx, rect.center.dy);
      canvas.scale(squeeze, 1);
      painter.paint(canvas, Offset(-painter.width / 2, -painter.height / 2));
      canvas.restore();
      painter.dispose();
    }
  }

  @override
  bool shouldRepaint(TemperatureLabelsPainter old) =>
      old.opacity != opacity ||
      old.from != from ||
      old.scale != scale ||
      old.day != day ||
      old.label != label ||
      old.scaler != scaler ||
      !listEquals(old.weather, weather) ||
      !listEquals(old.temperatures, temperatures) ||
      !listEquals(old.sun, sun);
}

/// [child] under the temperatures [painter] draws, counted [from] a
/// time: when that changes -- the forecast fetched again -- the old ones
/// fade out, then the new ones in. At once, with animations off.
class _FadingTemperatures extends StatefulWidget {
  const _FadingTemperatures({
    required this.from,
    required this.painter,
    required this.child,
  });

  final DateTime? from;
  final CustomPainter Function(DateTime? from, double opacity) painter;
  final Widget child;

  @override
  State<_FadingTemperatures> createState() => _FadingTemperaturesState();
}

class _FadingTemperaturesState extends State<_FadingTemperatures>
    with SingleTickerProviderStateMixin {
  /// Out over the first half, in over the second.
  late final _fade = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 800),
  )..addListener(_faded);

  /// What the labels shown count from.
  late DateTime? _shown = widget.from;

  @override
  void didUpdateWidget(_FadingTemperatures old) {
    super.didUpdateWidget(old);
    if (widget.from == old.from) return;
    if (_shown == null || MediaQuery.disableAnimationsOf(context)) {
      _fade.stop();
      _fade.value = 0;
      _shown = widget.from;
      return;
    }
    // Fading in already: out again from as faded as it is.
    if (_fade.value >= 0.5) _fade.value = 1 - _fade.value;
    if (!_fade.isAnimating) _fade.forward(from: _fade.value);
  }

  /// Halfway, the new labels in place of the old.
  void _faded() {
    if (_fade.value >= 0.5 && _shown != widget.from) {
      setState(() => _shown = widget.from);
    }
    if (_fade.isCompleted) _fade.value = 0;
  }

  @override
  void dispose() {
    _fade.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _fade,
    child: widget.child,
    builder: (context, child) {
      final t = Curves.easeInOut.transform(
        _fade.value < 0.5 ? 1 - 2 * _fade.value : 2 * _fade.value - 1,
      );
      return CustomPaint(painter: widget.painter(_shown, t), child: child);
    },
  );
}

/// The rail down the left edge, under the events and over the
/// [TimelineAxis]: the times events start and end, the priority band and
/// its labels, and the band of events, with the fill from each piece of
/// it to its event. It covers the axis' times its labels would overlap.
class _RailPainter extends CustomPainter {
  _RailPainter({
    required this.day,
    required this.dayEnd,
    required this.scale,
    required this.events,
    required this.actions,
    required this.runs,
    required this.weather,
    required this.sun,
    required this.sunColor,
    required this.placements,
    required this.timeLabel,
    required this.scaler,
    required this.baseStyle,
    required this.nowY,
    required this.nowColor,
    required this.compactionY,
    required this.compactionColor,
    required this.noteYs,
    required this.noteColor,
    required this.markers,
    required this.edgeColor,
    required this.coverColor,
  });

  final DateTime day;
  final DateTime dayEnd;
  final double scale;
  final List<Event> events;
  final Map<String, PlanAction> actions;
  final List<PriorityRun> runs;

  /// The forecast, drawn on the band in place of the [runs].
  final List<WeatherSpan>? weather;

  /// Sunrises and sunsets, badged on the band, their times beside it.
  final List<SunTime> sun;
  final Color sunColor;
  final List<TimelinePlacement> placements;
  final String Function(DateTime) timeLabel;
  final TextScaler scaler;

  /// The theme's text style the labels are drawn in, for its font.
  final TextStyle baseStyle;

  /// Where now is, if it's in the day: a line across, under the events.
  final double? nowY;
  final Color nowColor;

  /// Where the last compaction is, if it's in the day: a dashed line
  /// across, under the events.
  final double? compactionY;
  final Color compactionColor;

  /// Where each note not yet compacted is, if it's in the day: a dashed
  /// line across, under the events, like the last compaction's but
  /// thinner and fainter.
  final List<double> noteYs;
  final Color noteColor;

  /// The lines' labels, which the times give way to, and how tall each
  /// is.
  final List<_Marker> markers;
  final Color edgeColor;

  /// The background, to cover the axis' times with.
  final Color coverColor;

  double _y(DateTime t) =>
      timelineOffset(t, day: day, dayEnd: dayEnd, scale: scale);

  TextPainter _text(String text, TextStyle style) => TextPainter(
    text: TextSpan(text: text, style: style),
    textDirection: TextDirection.ltr,
    textScaler: scaler,
    maxLines: 1,
  )..layout();

  @override
  void paint(Canvas canvas, Size size) {
    // The band, under its labels.
    for (final run in runs) {
      canvas.drawRect(
        Rect.fromLTRB(
          _timeWidth + _bandPadding,
          _y(run.start),
          _timeWidth + _bandWidth - _bandPadding,
          _y(run.end),
        ),
        Paint()..color = priorityColor(run.priority),
      );
    }
    _paintBandLabels(canvas);
    if (weather case final weather?) _paintWeather(canvas, weather);
    _paintTimeLabels(canvas);
    _paintSun(canvas);
    _paintEventBand(canvas);
    if (compactionY case final y?) {
      final paint = Paint()
        ..color = compactionColor
        ..strokeWidth = 1.5;
      for (var x = _timeWidth; x < size.width; x += 8) {
        canvas.drawLine(
          Offset(x, y),
          Offset(math.min(x + 4, size.width), y),
          paint,
        );
      }
    }
    if (noteYs.isNotEmpty) {
      final paint = Paint()
        ..color = noteColor
        ..strokeWidth = 1;
      for (final y in noteYs) {
        for (var x = _timeWidth; x < size.width; x += 8) {
          canvas.drawLine(
            Offset(x, y),
            Offset(math.min(x + 4, size.width), y),
            paint,
          );
        }
      }
    }
    if (nowY case final y?) {
      final now = Paint()
        ..color = nowColor
        ..strokeWidth = 1.5;
      canvas.drawLine(Offset(_timeWidth, y), Offset(size.width, y), now);
      canvas.drawCircle(Offset(_timeWidth, y), 4, now);
    }
  }

  /// "P1" where each run of the band starts, and where it stops if
  /// nothing follows straight on and it's long enough for both to help,
  /// as many as fit without overlapping: starts first.
  void _paintBandLabels(Canvas canvas) {
    final style = baseStyle.copyWith(
      fontSize: _bandFontSize,
      fontWeight: FontWeight.w600,
      color: Colors.black87,
      height: 1.2,
    );
    final labelHeight = scaler.scale(_bandFontSize) * 1.2 + 2;
    final starts = [
      for (final run in runs) (run: run, top: _y(run.start), start: true),
    ];
    final ends = [
      for (final (i, run) in runs.indexed)
        if ((i + 1 == runs.length || runs[i + 1].start != run.end) &&
            // A short run's start says it all.
            _y(run.end) - _y(run.start) >= 4 * labelHeight)
          (run: run, top: _y(run.end) - labelHeight, start: false),
    ];
    final placed = placeLabels(
      [...starts, ...ends],
      top: (l) => l.top,
      height: labelHeight,
    );
    for (final label in placed) {
      final painter = _text('P${label.run.priority}', style);
      final rect = Rect.fromLTWH(
        _timeWidth + _bandPadding,
        label.top,
        _bandWidth - 2 * _bandPadding,
        labelHeight,
      );
      // On a run too short for it, it carries its own color.
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(2)),
        Paint()..color = priorityColor(label.run.priority),
      );
      painter.paint(
        canvas,
        Offset(
          rect.center.dx - painter.width / 2,
          rect.center.dy - painter.height / 2,
        ),
      );
      painter.dispose();
    }
  }

  /// The weather, each span the sky's color, with a bar of rain's color
  /// across it from its left as wide as rain's likely; labeled with the
  /// chance where it starts being much, and where it changes much, as
  /// many as fit.
  void _paintWeather(Canvas canvas, List<WeatherSpan> weather) {
    const left = _timeWidth + _bandPadding;
    const width = _bandWidth - 2 * _bandPadding;
    final shown = [
      for (final span in weather)
        if (span.end.isAfter(day) && span.start.isBefore(dayEnd)) span,
    ];
    for (final span in shown) {
      final top = _y(span.start);
      final bottom = _y(span.end);
      canvas.drawRect(
        Rect.fromLTRB(left, top, left + width, bottom),
        Paint()..color = skyBandColor(span.sky, daytime: span.daytime),
      );
      final chance = span.rainChance ?? 0;
      if (chance > 0) {
        canvas.drawRect(
          Rect.fromLTRB(left, top, left + width * chance / 100, bottom),
          Paint()..color = rainColor.withValues(alpha: 0.85),
        );
      }
    }
    final style = baseStyle.copyWith(
      fontSize: _bandFontSize - 1,
      fontWeight: FontWeight.w600,
      color: Colors.white,
      height: 1.2,
    );
    final labelHeight = _bandLabelHeight(scaler);
    for (final label in _rainLabels(shown, y: _y, day: day, scaler: scaler)) {
      final rect = Rect.fromLTWH(left, label.top, width, labelHeight);
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(2)),
        Paint()..color = rainColor,
      );
      final painter = _text('${label.chance}%', style);
      // Narrowed to fit, if it must be.
      final squeeze = math.min(1.0, (width - 1) / painter.width);
      canvas.save();
      canvas.translate(rect.center.dx, rect.center.dy);
      canvas.scale(squeeze, 1);
      painter.paint(canvas, Offset(-painter.width / 2, -painter.height / 2));
      canvas.restore();
      painter.dispose();
    }
  }

  /// Where each of the [sun]'s times in the day is.
  List<double> get _sunYs => [
    for (final s in sun)
      if (!s.at.isBefore(day) && s.at.isBefore(dayEnd)) _y(s.at),
  ];

  /// Each sunrise and sunset: a badge across the band, the sun on the
  /// horizon, and its time beside it after an arrow up or down, in
  /// [sunColor], where an axis time would be.
  void _paintSun(Canvas canvas) {
    const left = _timeWidth + _bandPadding;
    const width = _bandWidth - 2 * _bandPadding;
    final color = Paint()..color = sunColor;
    // The axis' times under them are covered with the others'.
    for (final (:at, :rise) in sun) {
      if (at.isBefore(day) || !at.isBefore(dayEnd)) continue;
      final y = _y(at);
      canvas.drawLine(
        Offset(left - 2, y),
        Offset(left + width + 2, y),
        Paint()
          ..color = sunColor
          ..strokeWidth = 1.5,
      );
      final badge = Rect.fromCenter(
        center: Offset(left + width / 2, y),
        width: width + 2,
        height: _sunBadgeHeight,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(badge, const Radius.circular(4)),
        color,
      );
      _paintIcon(canvas, Icons.wb_twilight, 15, Colors.white, badge.center);
      final time = _text(
        timeLabel(at),
        baseStyle.copyWith(
          fontSize: _labelFontSize,
          height: 1.3,
          color: sunColor,
          fontWeight: FontWeight.w700,
        ),
      );
      final timeLeft = _timeWidth - 6 - time.width;
      time.paint(canvas, Offset(timeLeft, y - time.height / 2));
      time.dispose();
      final arrow = rise ? Icons.north : Icons.south;
      final arrowSize = scaler.scale(_labelFontSize);
      _paintIcon(
        canvas,
        arrow,
        arrowSize,
        sunColor,
        Offset(timeLeft - 1 - arrowSize / 2, y),
      );
      canvas.drawLine(
        Offset(_timeWidth - 4, y),
        Offset(_timeWidth, y),
        Paint()
          ..color = sunColor
          ..strokeWidth = 1,
      );
    }
  }

  /// [icon], [size] across, centered on [center].
  void _paintIcon(
    Canvas canvas,
    IconData icon,
    double size,
    Color color,
    Offset center,
  ) {
    final painter = TextPainter(
      text: TextSpan(
        text: String.fromCharCode(icon.codePoint),
        style: TextStyle(
          fontFamily: icon.fontFamily,
          package: icon.fontPackage,
          fontSize: size,
          color: color,
          height: 1,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(
      canvas,
      center - Offset(painter.width / 2, painter.height / 2),
    );
    painter.dispose();
  }

  /// The times events start or end, as many as fit after the midnights
  /// at both ends, over the axis' times they'd overlap.
  void _paintTimeLabels(Canvas canvas) {
    final labelHeight = _timeLabelHeight(scaler);
    final edges = <DateTime>{
      for (final event in events)
        if (!event.isCancelled) ...[event.start, event.end],
    }.where((t) => t.isAfter(day) && t.isBefore(dayEnd)).toList()..sort();
    final candidates = <_TimeLabel>[
      (time: day, y: _y(day), edge: false),
      (time: dayEnd, y: _y(dayEnd), edge: false),
      for (final t in edges) (time: t, y: _y(t), edge: true),
    ];
    // The lines' labels and the sun's come first; any time they'd cover
    // isn't shown.
    final sunYs = _sunYs;
    bool clearOfMarkers(_TimeLabel label) =>
        markers.every(
          (m) => (m.y - label.y).abs() >= (m.height + labelHeight) / 2,
        ) &&
        sunYs.every((y) => (y - label.y).abs() >= labelHeight);
    final placed = placeLabels(
      candidates.where(clearOfMarkers),
      top: (l) => l.y - labelHeight / 2,
      height: labelHeight,
    ).where((l) => l.edge).toList();
    // The axis' times under these, or under the lines' labels.
    final cover = Paint()..color = coverColor;
    for (final label in _axisLabels(
      day: day,
      dayEnd: dayEnd,
      scale: scale,
      labelHeight: labelHeight,
    )) {
      if (clearOfMarkers(label) &&
          placed.every((l) => (l.y - label.y).abs() >= labelHeight)) {
        continue;
      }
      canvas.drawRect(
        Rect.fromLTRB(
          0,
          label.y - labelHeight / 2,
          _timeWidth - 1,
          label.y + labelHeight / 2,
        ),
        cover,
      );
    }
    final tick = Paint()
      ..color = edgeColor
      ..strokeWidth = 1;
    for (final label in placed) {
      final painter = _text(
        timeLabel(label.time),
        baseStyle.copyWith(
          fontSize: _labelFontSize,
          height: 1.3,
          color: edgeColor,
          fontWeight: FontWeight.w500,
        ),
      );
      painter.paint(
        canvas,
        Offset(_timeWidth - 6 - painter.width, label.y - painter.height / 2),
      );
      painter.dispose();
      canvas.drawLine(
        Offset(_timeWidth - 4, label.y),
        Offset(_timeWidth, label.y),
        tick,
      );
    }
  }

  /// Each event's piece of the band, where its times put it, in its
  /// color, and the same color across the gutter from it to its event,
  /// widening or narrowing to meet the event's edge. Later events are
  /// drawn over earlier ones they overlap.
  void _paintEventBand(Canvas canvas) {
    const left = _eventBandLeft;
    const right = _eventBandLeft + _eventBandWidth;
    for (final p in placements) {
      final color = _shownColor(p.event, actions);
      // Exactly where its card is, if it's drawn at its times; and no
      // thinner than a line, if it has none.
      final top = p.trueTop;
      final bottom = math.max(p.trueBottom, top + 1);
      // Into the card's border, so no seam shows.
      const edge = _cardsLeft + _outlineWidth / 2;
      canvas.drawPath(
        Path()
          ..moveTo(left, top)
          ..lineTo(right, top)
          ..lineTo(edge, p.top)
          ..lineTo(edge, p.bottom)
          ..lineTo(right, bottom)
          ..lineTo(left, bottom)
          ..close(),
        Paint()..color = color,
      );
    }
    // Then a hairline of the background along the top of each that meets
    // the one before it in a color too like its own to tell them apart:
    // across the band, then along the fill to the event, whose strip
    // carries it on.
    final seam = Paint()
      ..color = coverColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = _seamWidth;
    for (final (i, p) in placements.indexed) {
      if (!_seamAbove(placements, i, actions)) continue;
      // Just below its top, as the strip's is.
      const down = _seamWidth / 2;
      canvas.drawPath(
        Path()
          ..moveTo(left, p.trueTop + down)
          ..lineTo(right, p.trueTop + down)
          ..lineTo(_cardsLeft, p.top + down),
        seam,
      );
    }
  }

  @override
  bool shouldRepaint(_RailPainter old) =>
      old.scale != scale ||
      old.day != day ||
      old.events != events ||
      old.actions != actions ||
      !listEquals(old.weather, weather) ||
      !listEquals(old.sun, sun) ||
      old.sunColor != sunColor ||
      old.edgeColor != edgeColor ||
      old.coverColor != coverColor ||
      old.nowY != nowY ||
      old.compactionY != compactionY ||
      !listEquals(old.noteYs, noteYs) ||
      old.scaler != scaler;
}
