import 'dart:math';

import 'package:flutter/material.dart';

/// A goal's icon, drawn as an icon is, in the [IconTheme]'s color and
/// size: a bullseye, straight on, with an arrow stuck in the middle, come
/// in from the upper right, solid vanes at its back.
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

/// Draws [GoalIcon] on a 24-unit square, as Material's icons are -- or
/// [copies] of it, each overlapping the one before from the left, for
/// [GoalStack].
class GoalPainter extends CustomPainter {
  GoalPainter(this.color, {this.copies = 1});

  final Color color;

  /// How many, from the front one, at the right, back to the left.
  final int copies;

  /// How far, in units, each copy is from the one in front of it.
  static const _step = 7.0;

  /// The gap, in units, round each copy where it covers the one behind,
  /// as the action diamonds' edges keep them apart -- cut out, so it's the
  /// background's color, whatever's behind.
  static const _edge = 1.4;

  /// How wide [copies] are, in 24ths of their height.
  static double widthOf(int copies) => 24 + _step * (copies - 1);

  /// Where the arrow's in: the bullseye's middle.
  static const _center = Offset(10, 14);

  /// The outer ring's diameter, the inner's, and the middle's.
  static const _outer = 18.0;
  static const _inner = 10.2;
  static const _bull = 4.4;
  static const _ring = 2.2;

  /// The arrow's back end, its shaft's width, and its vanes' length along
  /// it and reach either side.
  static const _tail = Offset(21.6, 2.4);
  static const _shaft = 1.5;
  static const _vaneLength = 4.8;
  static const _vaneReach = 1.9;

  /// The gap cut round the arrow where it crosses the rings, from this
  /// far out from the middle -- clear of the bull.
  static const _halo = 0.9;
  static const _haloFrom = 2.6;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.height / 24);
    // One layer, so the gaps cut through only what's drawn here.
    canvas.saveLayer(Rect.fromLTWH(-2, -2, widthOf(copies) + 4, 28), Paint());
    for (var i = copies - 1; i >= 0; i--) {
      canvas
        ..save()
        ..translate(_step * (copies - 1 - i), 0);
      if (i < copies - 1) _clearUnder(canvas);
      // Behind the front one, only the rings show, so only they're drawn:
      // an arrow's vanes would poke out above the one in front.
      _paintOne(canvas, arrow: i == 0);
      canvas.restore();
    }
    canvas.restore();
  }

  static Paint _stroke(Paint paint, double width) => paint
    ..style = PaintingStyle.stroke
    ..strokeWidth = width
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round;

  static Paint get _clear => Paint()..blendMode = BlendMode.clear;

  /// The arrow's two vanes, swept back, set in from its end.
  static List<Path> _vanes() {
    final along = (_tail - _center) / (_tail - _center).distance;
    final across = Offset(-along.dy, along.dx);
    final back = _tail - along * 0.9;
    final front = back - along * _vaneLength;
    return [
      for (final side in [1.0, -1.0])
        () {
          final outerFront =
              back - along * (_vaneLength - 1.8) + across * side * _vaneReach;
          final outerBack = back + along * 0.5 + across * side * _vaneReach;
          return Path()
            ..moveTo(front.dx, front.dy)
            ..lineTo(outerFront.dx, outerFront.dy)
            ..lineTo(outerBack.dx, outerBack.dy)
            ..lineTo(back.dx, back.dy)
            ..close();
        }(),
    ];
  }

  void _paintOne(Canvas canvas, {required bool arrow}) {
    final ink = Paint()..color = color;
    canvas
      ..drawCircle(_center, _outer / 2, _stroke(Paint()..color = color, _ring))
      ..drawCircle(_center, _inner / 2, _stroke(Paint()..color = color, _ring))
      ..drawCircle(_center, _bull / 2, ink);
    if (!arrow) return;
    final along = (_tail - _center) / (_tail - _center).distance;
    final vanes = _vanes();
    // A gap round the arrow where it crosses the rings, then the arrow.
    canvas.drawLine(
      _center + along * _haloFrom,
      _tail,
      _stroke(_clear, _shaft + _halo * 2),
    );
    for (final vane in vanes) {
      canvas
        ..drawPath(vane, _stroke(_clear, _halo * 2))
        ..drawPath(vane, _clear);
    }
    canvas.drawLine(_center, _tail, _stroke(Paint()..color = color, _shaft));
    for (final vane in vanes) {
      canvas.drawPath(vane, ink);
    }
  }

  /// Clears where one goes, and [_edge] round it, from those behind it.
  void _clearUnder(Canvas canvas) {
    canvas
      ..drawCircle(_center, _outer / 2 + _ring / 2 + _edge, _clear)
      ..drawLine(_center, _tail, _stroke(_clear, _shaft + _edge * 2));
    for (final vane in _vanes()) {
      canvas
        ..drawPath(vane, _stroke(_clear, _edge * 2))
        ..drawPath(vane, _clear);
    }
  }

  @override
  bool shouldRepaint(GoalPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.copies != copies;
}

/// Whether an event is tagged with goals, on its tile: one [GoalIcon] for
/// one goal, two overlapping from the left for more. Nothing for none.
class GoalStack extends StatelessWidget {
  const GoalStack({super.key, required this.count, this.size = 16, this.color});

  final int count;
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    if (count <= 0) return const SizedBox.shrink();
    final color =
        this.color ??
        IconTheme.of(context).color ??
        Theme.of(context).colorScheme.onSurface;
    final copies = min(count, 2);
    return Semantics(
      label: count == 1 ? '1 goal' : '$count goals',
      child: CustomPaint(
        size: Size(size * GoalPainter.widthOf(copies) / 24, size),
        painter: GoalPainter(color, copies: copies),
      ),
    );
  }
}
