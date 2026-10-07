import 'dart:ui' show PathMetric;

import 'package:flutter/material.dart';

import 'new_event_box.dart';

/// [mode]'s icon, in the [IconTheme]'s color and size: its
/// [CreateMode.icon], or, where Material has none for it, drawn here --
/// scissors over a push for [CreateMode.trimPush], and a zipper coming
/// open over a push for [CreateMode.splitPush].
class CreateModeIcon extends StatelessWidget {
  const CreateModeIcon(this.mode, {super.key, this.size});

  final CreateMode mode;

  /// As an [Icon]'s: the [IconTheme]'s, if null.
  final double? size;

  @override
  Widget build(BuildContext context) {
    final theme = IconTheme.of(context);
    final size = this.size ?? theme.size ?? 24;
    final color = theme.color ?? Theme.of(context).colorScheme.onSurface;
    final drawn = switch (mode) {
      CreateMode.trimPush => _Drawn.scissors,
      CreateMode.splitPush => _Drawn.zipper,
      _ => null,
    };
    if (drawn == null) return Icon(mode.icon, size: size);
    return Semantics(
      label: mode.label,
      child: CustomPaint(
        size: Size.square(size),
        painter: _CreateModePainter(drawn, color),
      ),
    );
  }
}

enum _Drawn { scissors, zipper }

/// Draws on a 24-unit square, as Material's icons are.
class _CreateModePainter extends CustomPainter {
  _CreateModePainter(this.drawn, this.color);

  final _Drawn drawn;
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
    final fill = Paint()..color = color;
    switch (drawn) {
      case _Drawn.scissors:
        _scissors(canvas, ink, fill);
        _push(canvas, ink, 19.6, 14.8);
      case _Drawn.zipper:
        _zipper(canvas, fill);
        _push(canvas, ink, 19.8, 12.4);
    }
  }

  /// The push: two chevrons down, their tops [top] down, centered on
  /// [x].
  static void _push(Canvas canvas, Paint ink, double x, double top) {
    const w = 3.2;
    for (final y in [top, top + w + 0.6]) {
      canvas.drawPath(
        Path()
          ..moveTo(x - w, y)
          ..lineTo(x, y + w)
          ..lineTo(x + w, y),
        ink,
      );
    }
  }

  /// Open scissors, pointing right: each handle's arm crossing at the
  /// pivot into the other side's blade -- the upper one's a stub, the
  /// rest behind the push.
  static void _scissors(Canvas canvas, Paint ink, Paint fill) {
    const pivot = Offset(10.6, 11.4);
    const upper = Offset(4.2, 6.8);
    const lower = Offset(4.2, 16.0);
    const ring = 2.5;
    Offset unit(Offset o) => o / o.distance;
    final down = unit(pivot - upper);
    final up = unit(pivot - lower);
    // A blade from the pivot along [toward], [length] long, tapering to
    // its point.
    Path blade(Offset toward, double length) {
      final across = Offset(-toward.dy, toward.dx);
      return Path()..addPolygon([
        pivot - across * 1.3,
        pivot + across * 1.3,
        pivot + toward * length + across * 0.15,
        pivot + toward * length - across * 0.15,
      ], true);
    }

    // On a layer of its own, for the pivot to be a hole through it.
    canvas.saveLayer(const Rect.fromLTWH(0, 0, 24, 24), Paint());
    canvas.drawCircle(upper, ring, ink);
    canvas.drawCircle(lower, ring, ink);
    canvas.drawLine(upper + down * ring, pivot, ink);
    canvas.drawLine(lower + up * ring, pivot, ink);
    canvas.save();
    canvas.clipRect(Rect.fromCircle(center: pivot, radius: 3.2));
    canvas.drawPath(blade(down, 13.4), fill);
    canvas.restore();
    canvas.drawPath(blade(up, 14.6), fill);
    canvas.drawCircle(pivot, 0.9, Paint()..blendMode = BlendMode.clear);
    canvas.restore();
  }

  /// A zipper lying across the top, its teeth in one straight, even row
  /// along the top; the bottom row's teeth between them where it's
  /// closed, at the left, then curving gently away below.
  static void _zipper(Canvas canvas, Paint fill) {
    const spacing = 2.8;
    const top = 8.0;
    // Close enough below for the rows to overlap where it's closed.
    const bottom = top + 1.8;
    const closedTo = 5.0;
    void row(Path path, double from) {
      final line = path.computeMetrics().first;
      for (var d = from; d < line.length; d += spacing) {
        _tooth(canvas, fill, line, d);
      }
    }

    row(
      Path()
        ..moveTo(0, top)
        ..lineTo(23.4, top),
      1.4,
    );
    row(
      Path()
        ..moveTo(0, bottom)
        ..lineTo(closedTo, bottom)
        ..quadraticBezierTo(10, bottom, 13.2, 17.6),
      1.4 + spacing / 2,
    );
  }

  /// A zipper's tooth: a block across [line], [d] along it.
  static void _tooth(Canvas canvas, Paint fill, PathMetric line, double d) {
    const along = 1.5;
    const across = 2.4;
    final tangent = line.getTangentForOffset(d)!;
    final a = tangent.vector;
    final n = Offset(-a.dy, a.dx);
    final at = tangent.position;
    canvas.drawPath(
      Path()..addPolygon([
        at - a * (along / 2) - n * (across / 2),
        at + a * (along / 2) - n * (across / 2),
        at + a * (along / 2) + n * (across / 2),
        at - a * (along / 2) + n * (across / 2),
      ], true),
      fill,
    );
  }

  @override
  bool shouldRepaint(_CreateModePainter old) =>
      old.drawn != drawn || old.color != color;
}
