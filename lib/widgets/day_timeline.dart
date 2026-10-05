import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../models/event.dart';
import '../models/goal.dart';
import 'color_picker.dart';
import 'durations.dart';

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

/// How wide the line round each event is, in its color.
const _outlineWidth = 1.25;

/// How faint a cancelled event's band and outline are.
const _cancelledAlpha = 0.4;

/// The colored strip down an event's left edge.
const _stripWidth = 4.0;

/// How round an event's corners on the right are, where it meets no
/// other.
const _cardRadius = 8.0;

/// The padding inside an event, around its text.
const _cardPadding = EdgeInsets.fromLTRB(8, 4, 8, 4);

/// The time labels' and priority labels' text, and how tall they are.
const _labelFontSize = 11.0;
const _bandFontSize = 10.0;

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

/// How tall a [DayTimeline] for [day] is at [scale]: midnight to
/// midnight, with room for their labels; taller only if an event near
/// midnight is drawn past it.
double timelineHeight(DateTime day, double scale) {
  final dayEnd = DateTime(day.year, day.month, day.day + 1);
  return timelineOffset(dayEnd, day: day, dayEnd: dayEnd, scale: scale) + _pad;
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
/// nothing is. An event with no priority, of its own or from its goals,
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

/// The color [event] is shown in: its primary goal's, if [goals] has it
/// and it has one, or else its priority's.
Color eventColor(Event event, Map<String, Goal> goals) {
  final goal = switch (event.goalIds) {
    [final id, ...] => goals[id],
    _ => null,
  };
  return (goal == null
          ? null
          : parseColor(goal.effectiveColor ?? goal.backgroundColor)) ??
      priorityColor(event.effectivePriority);
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
/// stops. Beside that, a band as wide of the events, each where its
/// times put it, in its [eventColor]. Then each event: its summary, then
/// a line for each of its goals, the primary goal first, each after a
/// diamond in the goal's color ([goals] gives them; one not among them
/// gets an outline). Its color fills the gutter from its piece of the
/// band to it, and a thin line of it runs round it.
///
/// An event too short for that is drawn as tall as its text needs: the
/// strip down its edge is solid only as far as it lasts, dashed below,
/// and it says how long it is. One pushed down by the event above it is
/// joined to where it truly is by that fill from the band.
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
/// Tapping an event calls [onTap] with it; tapping anywhere else calls
/// [onTapTime] with the time there.
class DayTimeline extends StatelessWidget {
  const DayTimeline({
    super.key,
    required this.events,
    required this.day,
    this.goals = const {},
    this.scale = defaultTimelineScale,
    this.now,
    this.lastCompaction,
    this.pendingNotes = const [],
    this.onTap,
    this.onTapTime,
    this.axis = true,
  });

  final List<Event> events;

  /// Midnight, local time, at the start of the day shown.
  final DateTime day;

  /// The goals by id, for their colors and names.
  final Map<String, Goal> goals;
  final double scale;
  final DateTime? now;

  /// When notes were last compacted into the calendar: what's before it
  /// is as the notes had it.
  final DateTime? lastCompaction;

  /// When each note not yet compacted into the calendar was taken.
  final List<DateTime> pendingNotes;
  final ValueChanged<Event>? onTap;

  /// Called with the time at a tap that isn't on an event.
  final ValueChanged<DateTime>? onTapTime;

  /// Whether to draw its [TimelineAxis] under it.
  final bool axis;

  /// Midnight at the end of the day.
  DateTime get dayEnd => DateTime(day.year, day.month, day.day + 1);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text = theme.textTheme;
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
      goal: text.bodySmall,
      chip: text.labelSmall,
    );
    final summaryLine = lineHeight(styles.summary);
    final goalLine = math.max(lineHeight(styles.goal), 10.0);
    double minHeight(Event event) =>
        _cardPadding.vertical +
        summaryLine +
        event.goalIds.length * goalLine +
        // Slack for rounding, so the text never overflows.
        2;

    final placements = placeEvents(
      events,
      day: day,
      dayEnd: dayEnd,
      scale: scale,
      minHeight: minHeight,
    );
    final runs = priorityRuns(events, day: day, dayEnd: dayEnd);
    double y(DateTime t) =>
        timelineOffset(t, day: day, dayEnd: dayEnd, scale: scale);
    final height = math.max(
      y(dayEnd) + _pad,
      (placements.map((p) => p.bottom).fold(0.0, math.max)) + _pad,
    );
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
      goals: goals,
      runs: runs,
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
                  children: [
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
                          goals: goals,
                          styles: styles,
                          onTap: onTap == null
                              ? null
                              : () => onTap!(placement.event),
                          timeLabel: (t) => MaterialLocalizations.of(context)
                              .formatTimeOfDay(
                                TimeOfDay.fromDateTime(t.toLocal()),
                              ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
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
  const TimelineAxis({super.key, required this.day, required this.scale});

  /// Midnight, local time, at the start of the day.
  final DateTime day;
  final double scale;

  @override
  Widget build(BuildContext context) =>
      CustomPaint(painter: _axisPainter(context, day, scale));
}

_AxisPainter _axisPainter(BuildContext context, DateTime day, double scale) {
  final theme = Theme.of(context);
  return _AxisPainter(
    day: day,
    dayEnd: DateTime(day.year, day.month, day.day + 1),
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
    required this.goal,
    required this.chip,
  });

  final TextStyle? summary;
  final TextStyle? goal;
  final TextStyle? chip;
}

/// An event: its summary, then its goals, each after a diamond.
class _EventCard extends StatelessWidget {
  const _EventCard({
    required this.placement,
    required this.joinedAbove,
    required this.joinedBelow,
    required this.goals,
    required this.styles,
    required this.onTap,
    required this.timeLabel,
  });

  final TimelinePlacement placement;

  /// Whether the event before it ends where it starts, and the one after
  /// starts where it ends. Where two meet, the corners are square and
  /// only the lower one's outline is drawn, so the line between them is
  /// no thicker than the rest.
  final bool joinedAbove;
  final bool joinedBelow;
  final Map<String, Goal> goals;
  final _CardStyles styles;
  final VoidCallback? onTap;
  final String Function(DateTime) timeLabel;

  Color? _colorOf(String id) => switch (goals[id]) {
    final goal? => parseColor(goal.effectiveColor ?? goal.backgroundColor),
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
    final ids = event.goalIds;
    final names = event.goalNames;
    final color = eventColor(event, goals);
    final outline = cancelled
        ? color.withValues(alpha: _cancelledAlpha)
        : color;
    final muted = colors.onSurfaceVariant;
    final strike = cancelled ? TextDecoration.lineThrough : null;
    final duration = formatDuration(event.end.difference(event.start));
    final priority = event.effectivePriority ?? defaultPriority;
    return Semantics(
      label:
          '$summary, ${timeLabel(event.start)} to ${timeLabel(event.end)}'
          '${cancelled ? ', cancelled' : ''}',
      button: onTap != null,
      excludeSemantics: true,
      child: Material(
        color: colors.surfaceContainerHigh,
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
          ),
          child: InkWell(
            onTap: onTap,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                CustomPaint(
                  size: const Size(_stripWidth, double.infinity),
                  painter: _StripPainter(
                    solidFrom: placement.trueTop - placement.top,
                    solidTo: placement.trueBottom - placement.top,
                    color: outline,
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: _cardPadding,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                summary,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: styles.summary?.copyWith(
                                  color: cancelled ? muted : null,
                                  decoration: strike,
                                ),
                              ),
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
                            _Chip(
                              text: 'P$priority',
                              style: styles.chip?.copyWith(
                                color: Colors.black87,
                                fontWeight: FontWeight.w600,
                              ),
                              fill: priorityColor(priority),
                              border: priorityColor(priority),
                            ),
                          ],
                        ),
                        for (final (i, id) in ids.indexed)
                          Row(
                            children: [
                              _Diamond(color: _colorOf(id), outline: muted),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  switch (goals[id]) {
                                    final goal? => goalName(goal),
                                    null =>
                                      (i < names.length ? names[i] : null) ??
                                          id,
                                  },
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: styles.goal?.copyWith(
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
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The outline round an event, in [color], inside its edge so it's no
/// taller than its piece of the band: square on the left, where the fill
/// from the band meets it, its top right corner [topRadius] round and
/// its bottom right [bottomRadius]; and with no [bottom] edge where the
/// event after it starts, whose top edge is drawn there instead.
class _OutlinePainter extends CustomPainter {
  _OutlinePainter({
    required this.color,
    required this.topRadius,
    required this.bottomRadius,
    required this.bottom,
  });

  final Color color;
  final double topRadius;
  final double bottomRadius;
  final bool bottom;

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
  }

  @override
  bool shouldRepaint(_OutlinePainter old) =>
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

/// A small box of [text] at the end of an event's summary: its duration,
/// or its priority.
class _Chip extends StatelessWidget {
  const _Chip({
    required this.text,
    required this.style,
    required this.border,
    this.fill,
    this.shape = _ChipShape.rounded,
  });

  final String text;
  final TextStyle? style;
  final Color border;
  final Color? fill;
  final _ChipShape shape;

  @override
  Widget build(BuildContext context) {
    final radius = shape == _ChipShape.square ? 0.0 : 4.0;
    final open = shape == _ChipShape.openTop;
    return Padding(
      padding: const EdgeInsets.only(left: 6),
      child: CustomPaint(
        foregroundPainter: open ? _OpenTopPainter(border, radius) : null,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: fill,
            border: open ? null : Border.all(color: border),
            borderRadius: BorderRadius.circular(radius),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
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

/// A small diamond in a goal's [color], or outlined if it has none.
class _Diamond extends StatelessWidget {
  const _Diamond({required this.color, required this.outline});

  final Color? color;
  final Color outline;

  @override
  Widget build(BuildContext context) => Transform.rotate(
    angle: math.pi / 4,
    child: Container(
      width: 7,
      height: 7,
      decoration: BoxDecoration(
        color: color,
        border: color == null ? Border.all(color: outline) : null,
      ),
    ),
  );
}

/// The strip down an event's edge: solid from [solidFrom] to [solidTo],
/// the part of it its times cover, and dashed elsewhere.
class _StripPainter extends CustomPainter {
  _StripPainter({
    required this.solidFrom,
    required this.solidTo,
    required this.color,
  });

  final double solidFrom;
  final double solidTo;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    final from = solidFrom.clamp(0.0, size.height);
    final to = solidTo.clamp(0.0, size.height);
    if (to > from) {
      canvas.drawRect(Rect.fromLTRB(0, from, size.width, to), paint);
    }
    void dashed(double a, double b) {
      for (var y = a; y < b; y += 6) {
        canvas.drawRect(
          Rect.fromLTRB(0, y, size.width, math.min(y + 3, b)),
          paint,
        );
      }
    }

    dashed(0, from);
    dashed(math.max(to, from), size.height);
  }

  @override
  bool shouldRepaint(_StripPainter old) =>
      old.solidFrom != solidFrom ||
      old.solidTo != solidTo ||
      old.color != color;
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
    required this.goals,
    required this.runs,
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
  final Map<String, Goal> goals;
  final List<PriorityRun> runs;
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
    _paintTimeLabels(canvas);
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
    // The lines' labels come first; any time they'd cover isn't shown.
    bool clearOfMarkers(_TimeLabel label) => markers.every(
      (m) => (m.y - label.y).abs() >= (m.height + labelHeight) / 2,
    );
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
      var color = eventColor(p.event, goals);
      if (p.event.isCancelled) {
        color = color.withValues(alpha: _cancelledAlpha);
      }
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
  }

  @override
  bool shouldRepaint(_RailPainter old) =>
      old.scale != scale ||
      old.day != day ||
      old.events != events ||
      old.goals != goals ||
      old.edgeColor != edgeColor ||
      old.coverColor != coverColor ||
      old.nowY != nowY ||
      old.compactionY != compactionY ||
      !listEquals(old.noteYs, noteYs) ||
      old.scaler != scaler;
}
