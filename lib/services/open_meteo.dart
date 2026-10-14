import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:http/http.dart' as http;

import '../models/weather.dart';
import 'weather.dart';

/// Forecasts from Open-Meteo (open-meteo.com), free for non-commercial
/// use and needing no key: its forecast, which picks the best models for
/// the place (in the US, NOAA's), for the sky, temperatures and the next
/// hours' rain; and NOAA's GFS ensemble, for the chance of rain in each
/// part of a day and each day -- the share of its runs with any.
class OpenMeteoForecastSource implements ForecastSource {
  OpenMeteoForecastSource({http.Client? client})
    : _client = client ?? http.Client();

  final http.Client _client;

  static const forecastOrigin = 'https://api.open-meteo.com';
  static const ensembleOrigin = 'https://ensemble-api.open-meteo.com';

  /// How long the hours are told hour by hour: past that, by parts of
  /// days.
  static const hourly = Duration(hours: 36);

  /// How many days are told part by part (today among them): past that,
  /// by whole days.
  static const dayPartDays = 3;

  /// How many days are told at all, today among them.
  static const days = 7;

  /// How many quarter hours are told, from the one going on.
  static const quarterHours = 12;

  /// How much has to fall, in millimeters, for an ensemble's run to count
  /// as rain: a hundredth of an inch, as the chance of rain is reckoned.
  static const measurable = 0.25;

  static const _timeout = Duration(seconds: 20);

  @override
  Future<Forecast> fetch(Coordinates at, {required DateTime now}) async {
    final place = {
      'latitude': at.latitude.toStringAsFixed(2),
      'longitude': at.longitude.toStringAsFixed(2),
      'timeformat': 'unixtime',
      'forecast_days': '$days',
    };
    final forecast = _get(
      Uri.parse('$forecastOrigin/v1/forecast').replace(
        queryParameters: {
          ...place,
          'timezone': 'auto',
          'forecast_minutely_15': '$quarterHours',
          'minutely_15': 'precipitation,precipitation_probability',
          'hourly':
              'temperature_2m,precipitation_probability,precipitation,'
              'weather_code,cloud_cover,is_day',
          'daily':
              'temperature_2m_max,temperature_2m_min,precipitation_sum,'
              'precipitation_probability_max',
        },
      ),
    );
    // Without it, the chance of rain is the likeliest hour's.
    final ensemble = _get(
      Uri.parse('$ensembleOrigin/v1/ensemble').replace(
        queryParameters: {
          ...place,
          'models': 'gfs_seamless',
          'hourly': 'precipitation',
        },
      ),
    ).then<Map<String, dynamic>?>((json) => json, onError: (_) => null);
    return parseOpenMeteo(await forecast, await ensemble, now: now);
  }

  Future<Map<String, dynamic>> _get(Uri url) async {
    final response = await _client.get(url).timeout(_timeout);
    if (response.statusCode != 200) {
      final reason = switch (_tryJson(response.body)) {
        {'reason': final String reason} => ': $reason',
        _ => '',
      };
      throw WeatherException(
        'Open-Meteo answered ${response.statusCode}$reason',
      );
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  static Object? _tryJson(String body) {
    try {
      return jsonDecode(body);
    } catch (_) {
      return null;
    }
  }
}

/// The forecast Open-Meteo's [forecast] and, if it came, its GFS
/// [ensemble] say, from [now] on.
Forecast parseOpenMeteo(
  Map<String, dynamic> forecast,
  Map<String, dynamic>? ensemble, {
  required DateTime now,
}) {
  final hours = _hours(forecast['hourly'] as Map<String, dynamic>? ?? {});
  final chance = ensemble == null ? null : _EnsembleRain.parse(ensemble);
  int? chanceIn(DateTime start, DateTime end, List<_Hour> hours) =>
      chance?.chance(start, end) ??
      hours.map((h) => h.rainChance).nonNulls.fold<int?>(null, _max);

  // The hours: each hour's precipitation is of the hour before its time.
  final hourEnd = now.add(OpenMeteoForecastSource.hourly);
  final hourSpans = [
    for (final h in hours)
      if (h.end.isAfter(now) && h.start.isBefore(hourEnd))
        WeatherSpan(
          start: h.start,
          end: h.end,
          sky: h.sky,
          daytime: h.daytime,
          rainChance: h.rainChance,
          precipitation: h.precipitation,
          temperature: h.temperature,
        ),
  ];
  final hoursUntil = hourSpans.lastOrNull?.end ?? now;

  // The quarter hours, each of the quarter before its time, in the sky of
  // its hour.
  final quarters = <WeatherSpan>[];
  if (forecast['minutely_15'] case final Map<String, dynamic> m) {
    final times = _times(m['time']);
    for (final (i, end) in times.indexed) {
      final start = end.subtract(const Duration(minutes: 15));
      if (!end.isAfter(now)) continue;
      final hour = hours
          .where((h) => !start.isBefore(h.start) && start.isBefore(h.end))
          .firstOrNull;
      quarters.add(
        WeatherSpan(
          start: start,
          end: end,
          sky: hour?.sky ?? Sky.cloudy,
          daytime: hour?.daytime ?? true,
          rainChance: _intAt(m['precipitation_probability'], i),
          precipitation: _doubleAt(m['precipitation'], i),
          temperature: hour?.temperature,
        ),
      );
    }
  }

  final today = DateTime(now.year, now.month, now.day);
  DateTime midnight(int days) =>
      DateTime(today.year, today.month, today.day + days);

  // The parts of days, from where the hours stop to the end of the days
  // told so; the first maybe cut short.
  final partsUntil = midnight(OpenMeteoForecastSource.dayPartDays);
  final parts = <WeatherSpan>[];
  for (var day = 0; day < OpenMeteoForecastSource.dayPartDays; day++) {
    for (final (i, hour) in dayPartStarts.indexed) {
      final d = midnight(day);
      var start = DateTime(d.year, d.month, d.day, hour);
      final end = i + 1 < dayPartStarts.length
          ? DateTime(d.year, d.month, d.day, dayPartStarts[i + 1])
          : midnight(day + 1);
      if (!end.isAfter(hoursUntil) || !start.isBefore(partsUntil)) continue;
      if (start.isBefore(hoursUntil)) start = hoursUntil;
      if (_summary(hours, start, end, chanceIn) case final span?) {
        parts.add(span);
      }
    }
  }

  // The days, today's from now.
  final daily = forecast['daily'] as Map<String, dynamic>? ?? {};
  final dayTimes = _times(daily['time']);
  final daySpans = <WeatherSpan>[];
  for (var day = 0; day < OpenMeteoForecastSource.days; day++) {
    final start = day == 0 ? now : midnight(day);
    final end = midnight(day + 1);
    final i = dayTimes.indexWhere(
      (t) => DateTime(t.year, t.month, t.day) == midnight(day),
    );
    final span = _summary(hours, start, end, chanceIn, wholeDay: true);
    if (span == null && i < 0) continue;
    // Today's high and low are what's left of it; the others', the day's.
    daySpans.add(
      WeatherSpan(
        start: start,
        end: end,
        sky: span?.sky ?? Sky.cloudy,
        rainChance:
            span?.rainChance ??
            _intAt(daily['precipitation_probability_max'], i),
        precipitation: day == 0 && span != null
            ? span.precipitation
            : _doubleAt(daily['precipitation_sum'], i) ?? span?.precipitation,
        high: day == 0 && span != null
            ? span.high
            : _doubleAt(daily['temperature_2m_max'], i) ?? span?.high,
        low: day == 0 && span != null
            ? span.low
            : _doubleAt(daily['temperature_2m_min'], i) ?? span?.low,
      ),
    );
  }

  return Forecast(
    fetchedAt: now,
    quarterHours: quarters,
    hours: hourSpans,
    dayParts: parts,
    days: daySpans,
    source: 'Open-Meteo',
  );
}

int? _max(int? a, int b) => a == null ? b : math.max(a, b);

/// The hours from [start] to [end] summed up: if rain's likely, the worst
/// that falls; otherwise, fog if it's foggy half the time, or else how
/// cloudy it is -- for a [wholeDay], in the daylight. Null with no hours.
WeatherSpan? _summary(
  List<_Hour> hours,
  DateTime start,
  DateTime end,
  int? Function(DateTime, DateTime, List<_Hour>) chanceIn, {
  bool wholeDay = false,
}) {
  final within = [
    for (final h in hours)
      if (h.end.isAfter(start) && h.start.isBefore(end)) h,
  ];
  if (within.isEmpty) return null;
  final chance = chanceIn(start, end, within);
  final falling = within
      .map((h) => h.sky)
      .where((s) => s.precipitates)
      .fold<Sky?>(
        null,
        (worst, s) => worst == null || s.index > worst.index ? s : worst,
      );
  final lit = within.where((h) => h.daytime).toList();
  final looked = wholeDay && lit.isNotEmpty ? lit : within;
  final Sky sky;
  if (falling != null && (chance ?? 0) >= 50) {
    sky = falling;
  } else if (looked.where((h) => h.sky == Sky.fog).length * 2 >=
      looked.length) {
    sky = Sky.fog;
  } else {
    final covers = looked.map((h) => h.cloudCover).nonNulls.toList();
    sky = covers.isEmpty
        ? Sky.cloudy
        : Sky.ofCloudCover(covers.reduce((a, b) => a + b) / covers.length);
  }
  final temperatures = within.map((h) => h.temperature).nonNulls;
  final amounts = within.map((h) => h.precipitation).nonNulls;
  return WeatherSpan(
    start: start,
    end: end,
    sky: sky,
    daytime: wholeDay || lit.length * 2 >= within.length,
    rainChance: chance,
    precipitation: amounts.isEmpty ? null : amounts.reduce((a, b) => a + b),
    high: temperatures.isEmpty ? null : temperatures.reduce(math.max),
    low: temperatures.isEmpty ? null : temperatures.reduce(math.min),
  );
}

/// An hour of Open-Meteo's forecast: the hour before its time.
class _Hour {
  _Hour({
    required this.end,
    required this.sky,
    required this.daytime,
    this.rainChance,
    this.precipitation,
    this.temperature,
    this.cloudCover,
  });

  final DateTime end;
  DateTime get start => end.subtract(const Duration(hours: 1));
  final Sky sky;
  final bool daytime;
  final int? rainChance;
  final double? precipitation;
  final double? temperature;
  final double? cloudCover;
}

List<_Hour> _hours(Map<String, dynamic> hourly) => [
  for (final (i, end) in _times(hourly['time']).indexed)
    _Hour(
      end: end,
      sky: switch (_intAt(hourly['weather_code'], i)) {
        final code? => Sky.ofWmo(code),
        null => Sky.cloudy,
      },
      daytime: _intAt(hourly['is_day'], i) != 0,
      rainChance: _intAt(hourly['precipitation_probability'], i),
      precipitation: _doubleAt(hourly['precipitation'], i),
      temperature: _doubleAt(hourly['temperature_2m'], i),
      cloudCover: _doubleAt(hourly['cloud_cover'], i),
    ),
];

List<DateTime> _times(Object? times) => [
  for (final t in times as List? ?? const [])
    DateTime.fromMillisecondsSinceEpoch((t as num).toInt() * 1000),
];

double? _doubleAt(Object? list, int i) => switch (list) {
  final List l when i >= 0 && i < l.length => (l[i] as num?)?.toDouble(),
  _ => null,
};

int? _intAt(Object? list, int i) => _doubleAt(list, i)?.round();

/// An ensemble's runs' rain, hour by hour: each value the hour (or step)
/// before its time.
class _EnsembleRain {
  _EnsembleRain(this.ends, this.step, this.members);

  final List<DateTime> ends;
  final Duration step;
  final List<List<double?>> members;

  static _EnsembleRain? parse(Map<String, dynamic> json) {
    final hourly = json['hourly'] as Map<String, dynamic>?;
    if (hourly == null) return null;
    final ends = _times(hourly['time']);
    if (ends.length < 2) return null;
    final members = [
      for (final MapEntry(:key, :value) in hourly.entries)
        if (key == 'precipitation' || key.startsWith('precipitation_member'))
          [for (final v in value as List) (v as num?)?.toDouble()],
    ];
    if (members.isEmpty) return null;
    return _EnsembleRain(ends, ends[1].difference(ends[0]), members);
  }

  /// The share of runs, in percent, with measurable rain from [start] to
  /// [end]: counting each step whose middle is in it. Null if no step's
  /// is, or no run says.
  int? chance(DateTime start, DateTime end) {
    final steps = [
      for (final (i, t) in ends.indexed)
        if (t.subtract(step ~/ 2) case final middle
            when !middle.isBefore(start) && middle.isBefore(end))
          i,
    ];
    if (steps.isEmpty) return null;
    var told = 0;
    var wet = 0;
    for (final member in members) {
      final values = [
        for (final i in steps)
          if (i < member.length) member[i],
      ].nonNulls;
      if (values.isEmpty) continue;
      told++;
      if (values.reduce((a, b) => a + b) >=
          OpenMeteoForecastSource.measurable) {
        wet++;
      }
    }
    if (told == 0) return null;
    return (wet * 100 / told).round();
  }
}
