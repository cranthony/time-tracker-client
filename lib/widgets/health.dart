import 'package:flutter/material.dart';

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

/// Which scale a rating is shown on: an action's (red, yellow, green) or a
/// relationship's (gray to green).
enum HealthScale {
  action(healthColor, healthBand),
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
    this.scale = HealthScale.action,
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

/// An action's last few ratings, oldest first, as tiny bars: each as tall as
/// its rating and in its band's color; a day with none is a short muted
/// tick.
class TrendSparkline extends StatelessWidget {
  const TrendSparkline({
    super.key,
    required this.trend,
    this.scale = HealthScale.action,
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
