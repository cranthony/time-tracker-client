import 'package:flutter/foundation.dart';

/// What the sky's doing, or what's falling from it: for an icon, and the
/// weather bar's color. The kinds of precipitation are last, the worst
/// last.
enum Sky {
  clear('Clear'),
  partlyCloudy('Partly cloudy'),
  cloudy('Cloudy'),
  fog('Fog'),
  drizzle('Drizzle'),
  rain('Rain'),
  snow('Snow'),
  thunderstorm('Thunderstorms');

  const Sky(this.label);

  final String label;

  /// Whether something's falling.
  bool get precipitates => index >= drizzle.index;

  /// The sky a WMO weather code says: the codes forecasts give, 0 (clear)
  /// to 99 (thunderstorm with heavy hail).
  static Sky ofWmo(int code) => switch (code) {
    0 || 1 => clear,
    2 => partlyCloudy,
    3 => cloudy,
    45 || 48 => fog,
    >= 51 && <= 57 => drizzle,
    >= 61 && <= 67 || >= 80 && <= 82 => rain,
    >= 71 && <= 77 || 85 || 86 => snow,
    >= 95 && <= 99 => thunderstorm,
    _ => cloudy,
  };

  /// The sky for a sky [cloudCover] percent covered.
  static Sky ofCloudCover(double cloudCover) => cloudCover < 25
      ? clear
      : cloudCover < 70
      ? partlyCloudy
      : cloudy;
}

/// The forecast for the time from [start] to [end]: a quarter hour, an
/// hour, part of a day or a whole one. Temperatures are in degrees
/// Celsius and precipitation in millimeters, whatever the app shows
/// them in.
@immutable
class WeatherSpan {
  const WeatherSpan({
    required this.start,
    required this.end,
    required this.sky,
    this.daytime = true,
    this.rainChance,
    this.precipitation,
    this.temperature,
    this.high,
    this.low,
  });

  final DateTime start;
  final DateTime end;
  final Sky sky;

  /// Whether it's mostly in daylight: a clear night is drawn as one.
  final bool daytime;

  /// The chance, in percent, of measurable precipitation (rain, or snow,
  /// melted) some time in it; null if the forecast doesn't say.
  final int? rainChance;

  /// How much is expected to fall in it, in millimeters.
  final double? precipitation;

  /// The temperature, for a quarter hour or an hour.
  final double? temperature;

  /// The highest and lowest temperatures, for part of a day or a whole
  /// one.
  final double? high;
  final double? low;

  Duration get length => end.difference(start);

  /// It from [from], if it starts before; null if it's over by then.
  WeatherSpan? from(DateTime from) {
    if (!end.isAfter(from)) return null;
    if (!start.isBefore(from)) return this;
    return WeatherSpan(
      start: from,
      end: end,
      sky: sky,
      daytime: daytime,
      rainChance: rainChance,
      precipitation: precipitation,
      temperature: temperature,
      high: high,
      low: low,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is WeatherSpan &&
      other.start == start &&
      other.end == end &&
      other.sky == sky &&
      other.daytime == daytime &&
      other.rainChance == rainChance &&
      other.precipitation == precipitation &&
      other.temperature == temperature &&
      other.high == high &&
      other.low == low;

  @override
  int get hashCode => Object.hash(
    start,
    end,
    sky,
    daytime,
    rainChance,
    precipitation,
    temperature,
    high,
    low,
  );

  @override
  String toString() =>
      'WeatherSpan($start, $end, ${sky.name}'
      '${rainChance == null ? '' : ', $rainChance%'})';
}

/// The parts of a day the forecast is told in, past the next hours: their
/// starts, in hours from midnight, each running to the next's.
const dayPartStarts = [0, 6, 12, 18];

/// [hour]'s part of the day, by name.
String dayPartName(int hour) => switch (hour) {
  < 6 => 'Overnight',
  < 12 => 'Morning',
  < 18 => 'Afternoon',
  _ => 'Evening',
};

/// A forecast, as precise as the weather allows: the [quarterHours] of
/// the next few hours, the [hours] of the next day and a half, then the
/// [dayParts] (night, morning, afternoon and evening) of the next couple
/// of days, and the [days] of the week -- today's from now. Each list is
/// in order and covers its own stretch; each may start before the one
/// before it ends, but the finer one says it better there
/// ([weatherTimeline]).
@immutable
class Forecast {
  const Forecast({
    required this.fetchedAt,
    this.quarterHours = const [],
    this.hours = const [],
    this.dayParts = const [],
    this.days = const [],
    this.source = '',
  });

  final DateTime fetchedAt;
  final List<WeatherSpan> quarterHours;
  final List<WeatherSpan> hours;
  final List<WeatherSpan> dayParts;
  final List<WeatherSpan> days;

  /// Where it came from, to credit it.
  final String source;

  /// The forecast for the day starting at midnight [day]: from now, if
  /// it's today; null if it's past or beyond the forecast.
  WeatherSpan? dayOf(DateTime day) {
    for (final span in days) {
      if (span.end.isAfter(day) &&
          span.start.isBefore(DateTime(day.year, day.month, day.day + 1))) {
        return span;
      }
    }
    return null;
  }
}

/// [forecast] from [from] on, one span after another, as precisely as
/// it says: its quarter hours, then its hours, then its parts of days,
/// then its days, each taking up where the finer ones stop. A coarser
/// span cut short by a finer one keeps what it said of itself.
List<WeatherSpan> weatherTimeline(Forecast forecast, {required DateTime from}) {
  final timeline = <WeatherSpan>[];
  var covered = from;
  for (final tier in [
    forecast.quarterHours,
    forecast.hours,
    forecast.dayParts,
    forecast.days,
  ]) {
    for (final span in tier) {
      if (span.from(covered) case final rest?) {
        timeline.add(rest);
        covered = rest.end;
      }
    }
  }
  return timeline;
}

/// The units the weather is shown in.
enum TemperatureUnit {
  fahrenheit('Fahrenheit (°F)'),
  celsius('Celsius (°C)');

  const TemperatureUnit(this.label);

  final String label;

  /// [celsius] in this unit, rounded, with a degree sign.
  String format(double celsius) => switch (this) {
    TemperatureUnit.fahrenheit => '${(celsius * 9 / 5 + 32).round()}°',
    TemperatureUnit.celsius => '${celsius.round()}°',
  };
}

enum PrecipitationUnit {
  inches('Inches (in)'),
  millimeters('Millimeters (mm)');

  const PrecipitationUnit(this.label);

  final String label;

  /// [millimeters] in this unit, with its abbreviation: to the hundredth
  /// of an inch, or the millimeter (the tenth, under ten).
  String format(double millimeters) => switch (this) {
    PrecipitationUnit.inches => '${(millimeters / 25.4).toStringAsFixed(2)} in',
    PrecipitationUnit.millimeters =>
      '${millimeters < 10 ? millimeters.toStringAsFixed(1) : millimeters.round()} mm',
  };
}
