import 'package:flutter/material.dart';

import '../models/weather.dart';

/// [sky]'s icon, by day or night.
IconData skyIcon(Sky sky, {bool daytime = true}) => switch (sky) {
  Sky.clear => daytime ? Icons.wb_sunny : Icons.nightlight_round,
  Sky.partlyCloudy => daytime ? Icons.wb_cloudy : Icons.nights_stay,
  Sky.cloudy => Icons.cloud,
  Sky.fog => Icons.foggy,
  Sky.drizzle => Icons.grain,
  Sky.rain => Icons.water_drop,
  Sky.snow => Icons.ac_unit,
  Sky.thunderstorm => Icons.thunderstorm,
};

/// [sky]'s icon's color.
Color skyIconColor(Sky sky, {bool daytime = true}) => switch (sky) {
  Sky.clear || Sky.partlyCloudy when daytime => const Color(0xFFF9A825),
  Sky.clear || Sky.partlyCloudy => const Color(0xFF7986CB),
  Sky.cloudy || Sky.fog => const Color(0xFF90A4AE),
  Sky.drizzle || Sky.rain => rainColor,
  Sky.snow => const Color(0xFF4DD0E1),
  Sky.thunderstorm => const Color(0xFF7E57C2),
};

/// The weather bar's color for [sky]: sunny yellow, clouds grey, a clear
/// night indigo; what falls, as the clouds it falls from.
Color skyBandColor(Sky sky, {bool daytime = true}) => switch (sky) {
  Sky.clear when daytime => const Color(0xFFFFE082),
  Sky.clear => const Color(0xFF9FA8DA),
  Sky.partlyCloudy when daytime => const Color(0xFFE6DDB0),
  Sky.partlyCloudy => const Color(0xFFB0B6D0),
  Sky.fog => const Color(0xFFCFD8DC),
  Sky.thunderstorm => const Color(0xFF9E9AB8),
  _ => const Color(0xFFB0BEC5),
};

/// The color rain's chance is drawn in.
const rainColor = Color(0xFF1E88E5);
