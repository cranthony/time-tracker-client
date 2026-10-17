import 'dart:math';

import 'package:flutter/material.dart';

/// A goal's icon, drawn as an icon is, in the [IconTheme]'s color and
/// size: a bullseye seen from a little to one side -- its rings ovals,
/// leaning -- with an arrow stuck in the middle, come in from the upper
/// right, its fletching at the back.
class GoalIcon extends StatelessWidget {
  const GoalIcon({super.key, this.size, this.color});

  /// As an [Icon]'s: the [IconTheme]'s, if null.
  final double? size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final theme = IconTheme.of(context);
    final size = this.size ?? theme.size ?? 24;
    return CustomPaint(
      size: Size.square(size),
      painter: GoalPainter(
        color ?? theme.color ?? Theme.of(context).colorScheme.onSurface,
      ),
    );
  }
}

/// Draws [GoalIcon] on a 24-unit square, as Material's icons are.
class GoalPainter extends CustomPainter {
  GoalPainter(this.color);

  final Color color;

  /// Where the arrow's in: the bullseye's middle.
  static const _center = Offset(10, 14);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 24);
    final ink = Paint()
      ..color = color
      ..strokeWidth = 1.6
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final solid = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    // The target, turned a little away: ovals, leaning.
    canvas
      ..save()
      ..translate(_center.dx, _center.dy)
      ..rotate(-0.35);
    canvas.drawOval(
      Rect.fromCenter(center: Offset.zero, width: 17, height: 13),
      ink,
    );
    canvas.drawOval(
      Rect.fromCenter(center: Offset.zero, width: 10.4, height: 7.8),
      ink,
    );
    canvas.drawOval(
      Rect.fromCenter(center: Offset.zero, width: 3.8, height: 2.9),
      solid,
    );
    canvas.restore();
    // The arrow's shaft, from the upper right into the middle.
    const tail = Offset(21.4, 3.2);
    canvas.drawLine(_center, tail, ink..strokeWidth = 1.5);
    // Its fletching: two vanes either side of the shaft's end, swept back.
    final along = (tail - _center) / (tail - _center).distance;
    final across = Offset(-along.dy, along.dx);
    for (final at in [0.0, 2.2]) {
      final base = tail - along * at;
      for (final side in [1.0, -1.0]) {
        canvas.drawLine(
          base - along * 1.6,
          base - along * 3.4 + across * side * 2.1,
          ink..strokeWidth = 1.2,
        );
      }
    }
  }

  @override
  bool shouldRepaint(GoalPainter oldDelegate) => oldDelegate.color != color;
}

/// How many goals an event is tagged with, as a stack of [GoalIcon]s:
/// one for one goal; two, offset, for more -- with the count beside them.
/// Nothing for none.
class GoalStack extends StatelessWidget {
  const GoalStack({super.key, required this.count, this.size = 16, this.color});

  final int count;
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    if (count <= 0) return const SizedBox.shrink();
    final color = this.color ?? IconTheme.of(context).color;
    final icon = GoalIcon(size: size, color: color);
    final offset = size * 0.28;
    final stacked = count == 1
        ? icon
        : SizedBox(
            width: size + offset,
            height: size + offset,
            child: Stack(
              children: [
                Positioned(
                  left: offset,
                  top: 0,
                  child: Opacity(opacity: 0.55, child: icon),
                ),
                Positioned(left: 0, top: offset, child: icon),
              ],
            ),
          );
    return Semantics(
      label: count == 1 ? '1 goal' : '$count goals',
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          stacked,
          if (count > 1)
            Padding(
              padding: const EdgeInsets.only(left: 1),
              child: Text(
                '$count',
                style: TextStyle(
                  fontSize: max(9, size * 0.62),
                  fontWeight: FontWeight.w600,
                  color: color,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
