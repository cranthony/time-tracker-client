import '../models/weather.dart';
import '../services/weather.dart';

/// Somewhere fixed, always allowed: for the offline demo and tests.
class FixedLocationSource implements LocationSource {
  FixedLocationSource([
    this.at = const Coordinates(47.61, -122.33),
    this.granted = LocationAccess.granted,
  ]);

  final Coordinates at;

  /// What asking says.
  LocationAccess granted;

  @override
  Future<LocationAccess> access() async => granted;

  @override
  Future<LocationAccess> requestAccess() async => granted;

  @override
  Future<Coordinates> current() async => at;

  @override
  Future<void> openSettings() async {}
}

/// A made-up week's weather, the same every time: a clear morning
/// clouding over, showers likely late this afternoon, a wet day after
/// tomorrow, then clearing for the weekend.
class SampleForecastSource implements ForecastSource {
  @override
  Future<Forecast> fetch(Coordinates at, {required DateTime now}) async =>
      sampleForecast(now);
}

/// The [SampleForecastSource]'s forecast, from [now].
Forecast sampleForecast(DateTime now) {
  final today = DateTime(now.year, now.month, now.day);
  DateTime at(int day, [int hour = 0, int minute = 0]) =>
      DateTime(today.year, today.month, today.day + day, hour, minute);

  // The rain's chance, by hours from midnight today.
  int chanceAt(int hour) => switch (hour) {
    15 => 30,
    16 => 60,
    17 => 70,
    18 => 40,
    19 => 20,
    >= 24 && < 30 => 10,
    _ => 0,
  };
  Sky skyAt(int hour) => switch (hour % 24) {
    _ when chanceAt(hour) >= 50 => Sky.rain,
    < 11 => Sky.clear,
    < 14 => Sky.partlyCloudy,
    _ => Sky.cloudy,
  };
  final start = DateTime(now.year, now.month, now.day, now.hour);
  final hours = [
    for (var i = 0; i < 36; i++)
      if (start.add(Duration(hours: i)) case final s)
        WeatherSpan(
          start: s,
          end: s.add(const Duration(hours: 1)),
          sky: skyAt(s.difference(today).inHours),
          daytime: s.hour >= 7 && s.hour < 19,
          rainChance: chanceAt(s.difference(today).inHours),
          precipitation: chanceAt(s.difference(today).inHours) >= 50 ? 1.2 : 0,
          temperature: 14 + 6 * (1 - ((s.hour - 15).abs() / 12)),
        ),
  ];
  final quarterStart = DateTime(
    now.year,
    now.month,
    now.day,
    now.hour,
    now.minute - now.minute % 15,
  );
  final quarters = [
    for (var i = 0; i < 12; i++)
      if (quarterStart.add(Duration(minutes: 15 * i)) case final s)
        WeatherSpan(
          start: s,
          end: s.add(const Duration(minutes: 15)),
          sky: skyAt(s.difference(today).inHours),
          daytime: true,
          // Showers from a quarter to three.
          rainChance: s.isBefore(at(0, 14, 45)) ? 5 : 55,
          precipitation: s.isBefore(at(0, 14, 45)) ? 0 : 0.3,
        ),
  ];
  final hoursEnd = hours.last.end;
  final parts = [
    for (var day = 0; day < 3; day++)
      for (final (i, hour) in dayPartStarts.indexed)
        if (at(day, hour + 6).isAfter(hoursEnd))
          WeatherSpan(
            start: at(day, hour).isBefore(hoursEnd) ? hoursEnd : at(day, hour),
            end: at(day, hour + 6),
            sky: day == 2 && i > 0 ? Sky.rain : Sky.cloudy,
            daytime: i == 1 || i == 2,
            rainChance: day == 2 ? const [40, 80, 90, 60][i] : 20,
            high: 13,
            low: 9,
          ),
  ];
  const days = [
    (Sky.cloudy, 70, 16, 10),
    (Sky.partlyCloudy, 10, 17, 9),
    (Sky.rain, 90, 12, 8),
    (Sky.cloudy, 40, 13, 7),
    (Sky.partlyCloudy, 20, 15, 6),
    (Sky.clear, 0, 18, 6),
    (Sky.clear, 0, 19, 7),
  ];
  return Forecast(
    fetchedAt: now,
    quarterHours: quarters,
    hours: hours,
    dayParts: parts,
    days: [
      for (final (i, (sky, chance, high, low)) in days.indexed)
        WeatherSpan(
          start: i == 0 ? now : at(i),
          end: at(i + 1),
          sky: sky,
          rainChance: chance,
          precipitation: chance >= 50 ? chance / 10 : 0,
          high: high.toDouble(),
          low: low.toDouble(),
        ),
    ],
    source: 'Open-Meteo',
  );
}
