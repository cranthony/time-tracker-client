import 'package:flutter/material.dart';

/// A walking plow, drawn as an icon is, in the [IconTheme]'s color and
/// size: its long beam down to the hitch and its hook at the front; two
/// handles rising at the back, a rung between them; and the share and
/// moldboard under the beam, pointing forward. What's done: an event's
/// actions.
class PlowIcon extends StatelessWidget {
  const PlowIcon({super.key, this.size, this.color});

  /// As an [Icon]'s: the [IconTheme]'s, if null.
  final double? size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final theme = IconTheme.of(context);
    final size = this.size ?? theme.size ?? 24;
    return CustomPaint(
      size: Size.square(size),
      painter: _PlowPainter(
        color ?? theme.color ?? Theme.of(context).colorScheme.onSurface,
      ),
    );
  }
}

/// Draws on a 24-unit square, as Material's icons are.
class _PlowPainter extends CustomPainter {
  _PlowPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 24);
    final ink = Paint()
      ..color = color
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;
    final thin = Paint()
      ..color = color
      ..strokeWidth = 1.4
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    // The beam.
    canvas.drawLine(const Offset(1.6, 17.2), const Offset(18.4, 10.6), ink);
    // The handles, apart, and the rung between them.
    canvas.drawLine(const Offset(13.8, 12.6), const Offset(15.4, 2.2), ink);
    canvas.drawLine(const Offset(16.4, 16.4), const Offset(22.6, 3.2), ink);
    canvas.drawLine(const Offset(15, 7), const Offset(19.9, 8.2), thin);
    // The share and moldboard, its point forward.
    canvas.drawPath(
      Path()
        ..moveTo(12.4, 13.4)
        ..lineTo(11.2, 17.4)
        ..lineTo(7.4, 21.4)
        ..lineTo(17.2, 19)
        ..lineTo(16.4, 14.4)
        ..close(),
      Paint()..color = color,
    );
    // The hitch, and its hook.
    canvas.drawPath(
      Path()
        ..moveTo(1.8, 17.2)
        ..lineTo(1.8, 20.6)
        ..arcToPoint(
          const Offset(3.8, 21.4),
          radius: const Radius.circular(1.2),
          clockwise: false,
        ),
      thin,
    );
  }

  @override
  bool shouldRepaint(_PlowPainter old) => old.color != color;
}
