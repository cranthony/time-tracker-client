import 'package:flutter/material.dart';

import '../models/assessment.dart';

/// The status color for a 0-100 rating: green from 70, yellow from 40, red
/// below. Never shown alone -- always beside the number or a label.
Color healthColor(int rating) => rating >= 70
    ? const Color(0xFF0CA30C)
    : rating >= 40
    ? const Color(0xFFFAB219)
    : const Color(0xFFD03B3B);

/// What a rating's band is called.
String healthBand(int rating) => rating >= 70
    ? 'on track'
    : rating >= 40
    ? 'needs attention'
    : 'off track';

/// The color for a 0-100 relationship health rating: from gray, for a
/// relationship gone disconnected, to green, for a healthy one -- there's
/// no red, since drifting apart isn't a failure. Never shown alone.
Color relationshipColor(int rating) => Color.lerp(
  _disconnected,
  _connected,
  // Gray up to 15, green from 85, so the bands between read apart.
  ((rating - 15) / 70).clamp(0.0, 1.0),
)!;

const _disconnected = Color(0xFF9E9E9E);
const _connected = Color(0xFF0CA30C);

/// What a relationship health rating's band is called.
String relationshipBand(int rating) => rating >= 70
    ? 'healthy'
    : rating >= 40
    ? 'drifting'
    : 'disconnected';

/// Which scale a rating is shown on: a goal's (red, yellow, green) or a
/// relationship's (gray to green).
enum HealthScale {
  goal(healthColor, healthBand),
  relationship(relationshipColor, relationshipBand);

  const HealthScale(this.color, this.band);

  final Color Function(int rating) color;
  final String Function(int rating) band;
}

/// A latest confirmed rating: a dot in its band's color beside the
/// number, or a muted dash when it has none.
class HealthDot extends StatelessWidget {
  const HealthDot({
    super.key,
    required this.rating,
    this.scale = HealthScale.goal,
  });

  final int? rating;
  final HealthScale scale;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final rating = this.rating;
    if (rating == null) {
      return Tooltip(
        message: 'Not rated yet',
        child: Text('–', style: TextStyle(color: theme.hintColor)),
      );
    }
    return Tooltip(
      message: 'Health $rating: ${scale.band(rating)}',
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: scale.color(rating),
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 4),
          Text('$rating', style: theme.textTheme.labelMedium),
        ],
      ),
    );
  }
}

/// A goal's last few ratings, oldest first, as tiny bars: each as tall as
/// its rating and in its band's color; a day with none is a short muted
/// tick.
class TrendSparkline extends StatelessWidget {
  const TrendSparkline({
    super.key,
    required this.trend,
    this.scale = HealthScale.goal,
  });

  final List<int?> trend;
  final HealthScale scale;

  @override
  Widget build(BuildContext context) {
    final rated = trend.nonNulls.toList();
    return Tooltip(
      message: rated.isEmpty
          ? 'No ratings in the last ${trend.length} days'
          : 'Last ${trend.length} days: '
                '${trend.map((r) => r?.toString() ?? '–').join(', ')}',
      child: CustomPaint(
        size: Size(trend.length * 6.0, 18),
        painter: _SparklinePainter(
          trend,
          Theme.of(context).hintColor,
          scale.color,
        ),
      ),
    );
  }
}

class _SparklinePainter extends CustomPainter {
  _SparklinePainter(this.trend, this.muted, this.color);

  final List<int?> trend;
  final Color muted;
  final Color Function(int rating) color;

  @override
  void paint(Canvas canvas, Size size) {
    const width = 4.0; // 2px of surface between bars
    for (final (i, rating) in trend.indexed) {
      final left = i * 6.0 + 1;
      if (rating == null) {
        canvas.drawRect(
          Rect.fromLTWH(left, size.height - 2, width, 2),
          Paint()..color = muted.withValues(alpha: 0.5),
        );
        continue;
      }
      final height = (size.height * rating / 100).clamp(2.0, size.height);
      canvas.drawRRect(
        RRect.fromRectAndCorners(
          Rect.fromLTWH(left, size.height - height, width, height),
          topLeft: const Radius.circular(2),
          topRight: const Radius.circular(2),
        ),
        Paint()..color = color(rating),
      );
    }
  }

  @override
  bool shouldRepaint(_SparklinePainter old) =>
      old.muted != muted ||
      old.color != color ||
      old.trend.join(',') != trend.join(',');
}

/// A goal's assessments, oldest first, as bars on a 0-100 scale with the
/// band edges (40, 70) as dashed reference lines. A proposed rating -- not
/// yet confirmed in a reflection -- is a hollow bar; a skipped day, a
/// short muted tick. Tapping a bar calls [onSelected] with its index.
class HealthHistoryChart extends StatelessWidget {
  const HealthHistoryChart({
    super.key,
    required this.assessments,
    this.selected,
    this.onSelected,
  });

  final List<Assessment> assessments;
  final int? selected;
  final ValueChanged<int>? onSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, 178);
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (details) {
            final i = _HistoryPainter.indexAt(
              details.localPosition.dx,
              size.width,
              assessments.length,
            );
            if (i != null) onSelected?.call(i);
          },
          child: CustomPaint(
            size: size,
            painter: _HistoryPainter(
              assessments: assessments,
              selected: selected,
              muted: theme.hintColor,
              grid: theme.dividerColor,
              text: theme.textTheme.labelSmall!.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              surface: theme.colorScheme.surface,
            ),
          ),
        );
      },
    );
  }
}

class _HistoryPainter extends CustomPainter {
  _HistoryPainter({
    required this.assessments,
    required this.selected,
    required this.muted,
    required this.grid,
    required this.text,
    required this.surface,
  });

  final List<Assessment> assessments;
  final int? selected;
  final Color muted;
  final Color grid;
  final TextStyle text;
  final Color surface;

  static const _axis = 24.0;

  /// Room under the plot for the first and last days.
  static const _labels = 18.0;

  /// Which bar an x position falls on, if any.
  static int? indexAt(double x, double width, int count) {
    if (count == 0 || x < _axis) return null;
    final i = ((x - _axis) / ((width - _axis) / count)).floor();
    return i >= 0 && i < count ? i : null;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final plotHeight = size.height - _labels;
    double y(int rating) => plotHeight * (1 - rating / 100);

    // Recessive reference lines at the band edges, labelled on the left.
    for (final edge in [40, 70, 100]) {
      final paint = Paint()
        ..color = grid
        ..strokeWidth = 1;
      final dy = y(edge);
      for (var x = _axis; x < size.width; x += 6) {
        canvas.drawLine(Offset(x, dy), Offset(x + 3, dy), paint);
      }
      final label = TextPainter(
        text: TextSpan(text: '$edge', style: text),
        textDirection: TextDirection.ltr,
      )..layout();
      label.paint(canvas, Offset(0, dy - label.height / 2));
    }
    canvas.drawLine(
      Offset(_axis, plotHeight),
      Offset(size.width, plotHeight),
      Paint()
        ..color = muted
        ..strokeWidth = 1,
    );

    if (assessments.isEmpty) return;
    // Which days the chart spans: the first, under its start, and the
    // last, ending at the right edge.
    final first = TextPainter(
      text: TextSpan(text: assessments.first.day, style: text),
      textDirection: TextDirection.ltr,
    )..layout();
    first.paint(canvas, Offset(_axis, plotHeight + 4));
    if (assessments.length > 1) {
      final last = TextPainter(
        text: TextSpan(text: assessments.last.day, style: text),
        textDirection: TextDirection.ltr,
      )..layout();
      if (_axis + first.width + 8 < size.width - last.width) {
        last.paint(canvas, Offset(size.width - last.width, plotHeight + 4));
      }
    }
    final slot = (size.width - _axis) / assessments.length;
    final barWidth = (slot - 2).clamp(2.0, 24.0); // a 2px surface gap
    for (final (i, a) in assessments.indexed) {
      final left = _axis + i * slot + (slot - barWidth) / 2;
      if (i == selected) {
        canvas.drawRect(
          Rect.fromLTWH(_axis + i * slot, 0, slot, plotHeight),
          Paint()..color = muted.withValues(alpha: 0.12),
        );
      }
      final rating = a.rating;
      if (rating == null) {
        canvas.drawRect(
          Rect.fromLTWH(left, plotHeight - 3, barWidth, 3),
          Paint()..color = muted,
        );
        continue;
      }
      final top = y(rating).clamp(0.0, plotHeight - 2);
      final bar = RRect.fromRectAndCorners(
        Rect.fromLTWH(left, top, barWidth, plotHeight - top),
        topLeft: const Radius.circular(4),
        topRight: const Radius.circular(4),
      );
      final color = healthColor(rating);
      if (a.confirmed) {
        canvas.drawRRect(bar, Paint()..color = color);
      } else {
        // Proposed: hollow, until a reflection confirms it.
        canvas.drawRRect(
          bar.deflate(1),
          Paint()
            ..color = color
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_HistoryPainter old) =>
      old.assessments != assessments ||
      old.selected != selected ||
      old.muted != muted ||
      old.surface != surface;
}
