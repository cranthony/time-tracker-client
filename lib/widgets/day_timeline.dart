import 'dart:math' as math;

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

/// The column of times, then the band of priorities, then the gutter the
/// leaders of moved events are drawn in, then the events.
const _timeWidth = 60.0;
const _bandWidth = 24.0;
const _gutterWidth = 16.0;
const _cardsLeft = _timeWidth + _bandWidth + _gutterWidth;

/// The space each event leaves above and below it, inside where it's
/// placed, so ones end to end stay apart.
const _cardInset = 1.5;

/// The colored strip down an event's left edge.
const _stripWidth = 4.0;

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
/// stops. Then each event: its summary, then a line for each of its
/// goals, the primary goal first, each after a diamond in the goal's
/// color ([goals] gives them; one not among them gets an outline).
///
/// An event too short for that is drawn as tall as its text needs: the
/// strip down its edge is solid only as far as it lasts, dashed below,
/// and it says how long it is. One pushed down by the event above it is
/// joined to where it truly is by a line from a bracket in the gutter.
/// [now], if it's in the day, is marked with a line across, under the
/// events.
class DayTimeline extends StatelessWidget {
  const DayTimeline({
    super.key,
    required this.events,
    required this.day,
    this.goals = const {},
    this.scale = defaultTimelineScale,
    this.now,
    this.onTap,
  });

  final List<Event> events;

  /// Midnight, local time, at the start of the day shown.
  final DateTime day;

  /// The goals by id, for their colors and names.
  final Map<String, Goal> goals;
  final double scale;
  final DateTime? now;
  final ValueChanged<Event>? onTap;

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
        2 * _cardInset +
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
    final nowY = switch (now) {
      final now? when !now.isBefore(day) && now.isBefore(dayEnd) => y(now),
      _ => null,
    };
    final colors = theme.colorScheme;
    final rail = _RailPainter(
      day: day,
      dayEnd: dayEnd,
      scale: scale,
      events: events,
      runs: runs,
      placements: placements,
      timeLabel: (t) =>
          MaterialLocalizations.of(context)
              .formatTimeOfDay(TimeOfDay.fromDateTime(t.toLocal())),
      scaler: scaler,
      baseStyle: text.labelSmall ?? const TextStyle(),
      nowY: nowY,
      nowColor: colors.error,
      edgeColor: colors.onSurface,
      hourColor: colors.onSurfaceVariant,
      gridColor: colors.outlineVariant.withValues(alpha: 0.5),
      leaderColor: colors.outline,
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final cardWidth = math.max(0.0, constraints.maxWidth - _cardsLeft - 8);
        return CustomPaint(
          painter: rail,
          child: SizedBox(
            width: constraints.maxWidth,
            height: height,
            child: Stack(
              children: [
                for (final placement in placements)
                  Positioned(
                    left: _cardsLeft,
                    top: placement.top,
                    width: cardWidth,
                    height: placement.bottom - placement.top,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: _cardInset),
                      child: _EventCard(
                        placement: placement,
                        goals: goals,
                        styles: styles,
                        onTap: onTap == null
                            ? null
                            : () => onTap!(placement.event),
                        timeLabel: (t) => MaterialLocalizations.of(
                          context,
                        ).formatTimeOfDay(TimeOfDay.fromDateTime(t.toLocal())),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
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
    required this.goals,
    required this.styles,
    required this.onTap,
    required this.timeLabel,
  });

  final TimelinePlacement placement;
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
    final primary = ids.isEmpty ? null : _colorOf(ids.first);
    final muted = colors.onSurfaceVariant;
    final strike = cancelled ? TextDecoration.lineThrough : null;
    final duration = formatDuration(event.end.difference(event.start));
    return Semantics(
      label:
          '$summary, ${timeLabel(event.start)} to ${timeLabel(event.end)}'
          '${cancelled ? ', cancelled' : ''}',
      button: onTap != null,
      excludeSemantics: true,
      child: Material(
        color: colors.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(8),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              CustomPaint(
                size: const Size(_stripWidth, double.infinity),
                painter: _StripPainter(
                  solidFrom: placement.trueTop - placement.top - _cardInset,
                  solidTo: placement.trueBottom - placement.top - _cardInset,
                  color: primary ?? colors.outline,
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
                          if (placement.compressed && duration != null)
                            Padding(
                              padding: const EdgeInsets.only(left: 6),
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  border: Border.all(color: colors.outline),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 4,
                                  ),
                                  child: Text(
                                    duration,
                                    style: styles.chip?.copyWith(color: muted),
                                  ),
                                ),
                              ),
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
                                    (i < names.length ? names[i] : null) ?? id,
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
    );
  }
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

/// A time label to draw: [time] at [y], and whether an event starts or
/// ends there.
typedef _TimeLabel = ({DateTime time, double y, bool edge});

/// The rail down the left edge, under the events: the hours' lines, the
/// time labels, the priority band and its labels, and the leaders from
/// moved events to where they truly are.
class _RailPainter extends CustomPainter {
  _RailPainter({
    required this.day,
    required this.dayEnd,
    required this.scale,
    required this.events,
    required this.runs,
    required this.placements,
    required this.timeLabel,
    required this.scaler,
    required this.baseStyle,
    required this.nowY,
    required this.nowColor,
    required this.edgeColor,
    required this.hourColor,
    required this.gridColor,
    required this.leaderColor,
  });

  final DateTime day;
  final DateTime dayEnd;
  final double scale;
  final List<Event> events;
  final List<PriorityRun> runs;
  final List<TimelinePlacement> placements;
  final String Function(DateTime) timeLabel;
  final TextScaler scaler;

  /// The theme's text style the labels are drawn in, for its font.
  final TextStyle baseStyle;

  /// Where now is, if it's in the day: a line across, under the events.
  final double? nowY;
  final Color nowColor;
  final Color edgeColor;
  final Color hourColor;
  final Color gridColor;
  final Color leaderColor;

  double _y(DateTime t) =>
      timelineOffset(t, day: day, dayEnd: dayEnd, scale: scale);

  TextPainter _text(String text, TextStyle style) => TextPainter(
    text: TextSpan(text: text, style: style),
    textDirection: TextDirection.ltr,
    textScaler: scaler,
    maxLines: 1,
  )..layout();

  /// The hours of the day, by how much each deserves a label: every six
  /// hours, then every three, then the rest.
  List<DateTime> get _hours {
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

  @override
  void paint(Canvas canvas, Size size) {
    final grid = Paint()
      ..color = gridColor
      ..strokeWidth = 1;
    for (final hour in [day, ..._hours, dayEnd]) {
      final y = _y(hour);
      canvas.drawLine(Offset(_timeWidth, y), Offset(size.width, y), grid);
    }

    // The band, under its labels.
    for (final run in runs) {
      canvas.drawRect(
        Rect.fromLTRB(
          _timeWidth + 2,
          _y(run.start),
          _timeWidth + _bandWidth - 2,
          _y(run.end),
        ),
        Paint()..color = priorityColor(run.priority),
      );
    }
    _paintBandLabels(canvas);
    _paintTimeLabels(canvas);
    _paintLeaders(canvas);
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
        _timeWidth + 2,
        label.top,
        _bandWidth - 4,
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

  /// The times: midnight at both ends, then where events start or end,
  /// then the hours, as many as fit.
  void _paintTimeLabels(Canvas canvas) {
    final labelHeight = scaler.scale(_labelFontSize) * 1.3 + 2;
    final edges = <DateTime>{
      for (final event in events)
        if (!event.isCancelled) ...[event.start, event.end],
    }.where((t) => t.isAfter(day) && t.isBefore(dayEnd)).toList()..sort();
    final candidates = <_TimeLabel>[
      (time: day, y: _y(day), edge: false),
      (time: dayEnd, y: _y(dayEnd), edge: false),
      for (final t in edges) (time: t, y: _y(t), edge: true),
      for (final t in _hours) (time: t, y: _y(t), edge: false),
    ];
    final placed = placeLabels(
      candidates,
      top: (l) => l.y - labelHeight / 2,
      height: labelHeight,
    );
    final tick = Paint()
      ..color = edgeColor
      ..strokeWidth = 1;
    for (final label in placed) {
      final painter = _text(
        timeLabel(label.time),
        baseStyle.copyWith(
          fontSize: _labelFontSize,
          height: 1.3,
          color: label.edge ? edgeColor : hourColor,
          fontWeight: label.edge ? FontWeight.w500 : FontWeight.w400,
        ),
      );
      painter.paint(
        canvas,
        Offset(_timeWidth - 6 - painter.width, label.y - painter.height / 2),
      );
      painter.dispose();
      if (label.edge) {
        canvas.drawLine(
          Offset(_timeWidth - 4, label.y),
          Offset(_timeWidth, label.y),
          tick,
        );
      }
    }
  }

  /// For each event drawn taller than its times, a bracket in the gutter
  /// over the time it truly takes; for each pushed down, a line from
  /// where it truly starts to it.
  void _paintLeaders(Canvas canvas) {
    final paint = Paint()
      ..color = leaderColor
      ..strokeWidth = 1.2
      ..style = PaintingStyle.stroke;
    const x = _timeWidth + _bandWidth + 3;
    for (final p in placements) {
      if (!p.compressed) {
        // Only pushed down.
      } else if (p.trueBottom - p.trueTop < 2) {
        canvas.drawCircle(
          Offset(x + 2, p.trueTop),
          2,
          paint..style = PaintingStyle.fill,
        );
        paint.style = PaintingStyle.stroke;
      } else {
        canvas.drawPath(
          Path()
            ..moveTo(x + 4, p.trueTop)
            ..lineTo(x, p.trueTop)
            ..lineTo(x, p.trueBottom)
            ..lineTo(x + 4, p.trueBottom),
          paint,
        );
      }
      if (p.displaced) {
        canvas.drawLine(
          Offset(x + 4, p.trueTop),
          Offset(_cardsLeft, p.top + 10),
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_RailPainter old) =>
      old.scale != scale ||
      old.day != day ||
      old.events != events ||
      old.edgeColor != edgeColor ||
      old.nowY != nowY ||
      old.scaler != scaler;
}
