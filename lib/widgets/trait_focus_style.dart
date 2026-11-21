import 'package:flutter/material.dart';

/// The color of a trait's [lean] (see [TraitReading]): red below
/// neutral, deeper the lower; a faint grey at neutral; green above it,
/// deeper the higher. The same for any trait, whatever its scale.
Color traitLeanColor(double lean) {
  final t = lean.clamp(-1.0, 1.0).abs();
  return Color.lerp(
    _neutral,
    lean < 0 ? _low : _high,
    // Any lean at all shows plainly.
    t == 0 ? 0 : 0.35 + 0.65 * t,
  )!;
}

const _neutral = Color(0x559E9E9E);
const _low = Color(0xFFE53935);
const _high = Color(0xFF2E7D32);
