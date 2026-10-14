import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:time_tracker_client/demo/weather_sample.dart';
import 'package:time_tracker_client/models/weather.dart';
import 'package:time_tracker_client/screens/settings_screen.dart';
import 'package:time_tracker_client/services/app_settings.dart';
import 'package:time_tracker_client/services/open_meteo.dart';
import 'package:time_tracker_client/services/weather.dart';
import 'package:time_tracker_client/widgets/weather_strip.dart';

/// Where the device is, counting how often it's asked: to be sure it's
/// asked nothing while the weather's off.
class _CountingLocation extends FixedLocationSource {
  _CountingLocation([LocationAccess granted = LocationAccess.granted])
    : super(const Coordinates(47.6062, -122.3321), granted);

  var asked = 0;
  var requested = 0;
  var read = 0;

  @override
  Future<LocationAccess> access() {
    asked++;
    return super.access();
  }

  @override
  Future<LocationAccess> requestAccess() {
    requested++;
    return super.requestAccess();
  }

  @override
  Future<Coordinates> current() {
    read++;
    return super.current();
  }
}

/// Forecasts made to order, counting them, and where they were for.
class _FakeForecasts implements ForecastSource {
  final fetched = <Coordinates>[];
  Object? failWith;
  Forecast Function(DateTime now) make = sampleForecast;

  @override
  Future<Forecast> fetch(Coordinates at, {required DateTime now}) async {
    fetched.add(at);
    if (failWith case final error?) throw error;
    return make(now);
  }
}

WeatherSpan _span(
  DateTime start,
  Duration length, {
  Sky sky = Sky.cloudy,
  int? chance,
}) => WeatherSpan(
  start: start,
  end: start.add(length),
  sky: sky,
  rainChance: chance,
);

void main() {
  group('Sky', () {
    test('reads WMO weather codes', () {
      expect(Sky.ofWmo(0), Sky.clear);
      expect(Sky.ofWmo(2), Sky.partlyCloudy);
      expect(Sky.ofWmo(3), Sky.cloudy);
      expect(Sky.ofWmo(45), Sky.fog);
      expect(Sky.ofWmo(53), Sky.drizzle);
      expect(Sky.ofWmo(63), Sky.rain);
      expect(Sky.ofWmo(81), Sky.rain);
      expect(Sky.ofWmo(73), Sky.snow);
      expect(Sky.ofWmo(95), Sky.thunderstorm);
    });

    test('units', () {
      expect(TemperatureUnit.fahrenheit.format(20), '68°');
      expect(TemperatureUnit.celsius.format(20.4), '20°');
      expect(PrecipitationUnit.inches.format(25.4), '1.00 in');
      expect(PrecipitationUnit.millimeters.format(2.34), '2.3 mm');
      expect(PrecipitationUnit.millimeters.format(12.6), '13 mm');
    });
  });

  group('weatherTimeline', () {
    final now = DateTime(2026, 10, 14, 10, 20);

    test('is as precise as the forecast is, span after span, from now', () {
      final forecast = Forecast(
        fetchedAt: now,
        quarterHours: [
          for (var i = 0; i < 4; i++)
            _span(
              DateTime(2026, 10, 14, 10, 15 * i),
              const Duration(minutes: 15),
              chance: 10 * i,
            ),
        ],
        hours: [
          for (var h = 10; h < 14; h++)
            _span(DateTime(2026, 10, 14, h), const Duration(hours: 1)),
        ],
        dayParts: [
          _span(DateTime(2026, 10, 14, 14), const Duration(hours: 4)),
          _span(DateTime(2026, 10, 14, 18), const Duration(hours: 6)),
        ],
        days: [
          _span(now, DateTime(2026, 10, 15).difference(now)),
          _span(DateTime(2026, 10, 15), const Duration(days: 1), chance: 80),
        ],
      );

      final timeline = weatherTimeline(forecast, from: now);

      expect(timeline.first.start, now);
      expect(timeline.first.rainChance, 10);
      for (var i = 1; i < timeline.length; i++) {
        expect(timeline[i].start, timeline[i - 1].end);
      }
      expect(timeline.map((s) => s.length.inMinutes), [
        // What's left of the quarter going on, then the quarters.
        10, 15, 15,
        // The hours the quarters don't cover.
        60, 60, 60,
        // The parts of the day, then tomorrow.
        240, 360, 1440,
      ]);
      expect(timeline.last.rainChance, 80);
    });

    test('nothing past', () {
      final forecast = Forecast(
        fetchedAt: now,
        hours: [_span(DateTime(2026, 10, 14, 9), const Duration(hours: 1))],
      );
      expect(weatherTimeline(forecast, from: now), isEmpty);
    });
  });

  group('Open-Meteo', () {
    final forecastJson = jsonDecode(
      File('test/fixtures/open_meteo_forecast.json').readAsStringSync(),
    ) as Map<String, dynamic>;
    final ensembleJson = jsonDecode(
      File('test/fixtures/open_meteo_ensemble.json').readAsStringSync(),
    ) as Map<String, dynamic>;
    // Just into the first quarter hour it tells.
    final firstQuarter =
        ((forecastJson['minutely_15'] as Map)['time'] as List).first as int;
    final now = DateTime.fromMillisecondsSinceEpoch(
      (firstQuarter - 10 * 60) * 1000,
    );

    test('a real answer, told from now, quarter hours to days', () {
      final forecast = parseOpenMeteo(forecastJson, ensembleJson, now: now);

      expect(forecast.quarterHours, hasLength(12));
      expect(forecast.quarterHours.first.start.isAfter(now), isFalse);
      expect(forecast.hours, isNotEmpty);
      expect(
        forecast.hours.last.end.difference(now),
        lessThanOrEqualTo(const Duration(hours: 37)),
      );
      expect(forecast.dayParts.first.start, forecast.hours.last.end);
      expect(forecast.days, hasLength(OpenMeteoForecastSource.days));
      expect(forecast.days.first.start, now);
      for (final d in forecast.days) {
        expect(d.rainChance, inInclusiveRange(0, 100));
        expect(d.high, isNotNull);
        expect(d.low, lessThanOrEqualTo(d.high!));
      }

      final timeline = weatherTimeline(forecast, from: now);
      expect(timeline.first.start, now);
      for (var i = 1; i < timeline.length; i++) {
        expect(timeline[i].start, timeline[i - 1].end, reason: '$i');
      }
      expect(timeline.last.end, forecast.days.last.end);
    });

    test("a part of a day's chance is its share of the ensemble's runs with "
        'rain in it', () {
      final at = DateTime(2026, 10, 15);
      int t(int hour) =>
          at.add(Duration(hours: hour)).millisecondsSinceEpoch ~/ 1000;
      // Four runs, each hour's the hour before it: two wet in the
      // afternoon, one only a trace.
      final ensemble = {
        'hourly': {
          'time': [for (var h = 1; h <= 48; h++) t(h)],
          'precipitation': [for (var h = 1; h <= 48; h++) h == 15 ? 2.0 : 0.0],
          'precipitation_member01': [
            for (var h = 1; h <= 48; h++) h == 16 ? 0.5 : 0.0,
          ],
          'precipitation_member02': [
            for (var h = 1; h <= 48; h++) h == 14 ? 0.1 : 0.0,
          ],
          'precipitation_member03': [for (var h = 1; h <= 48; h++) 0.0],
        },
      };
      final forecast = {
        'hourly': {
          'time': [for (var h = 1; h <= 48; h++) t(h)],
          'weather_code': [for (var h = 1; h <= 48; h++) 3],
          'cloud_cover': [for (var h = 1; h <= 48; h++) 90],
          'is_day': [for (var h = 1; h <= 48; h++) 1],
          'temperature_2m': [for (var h = 1; h <= 48; h++) 10 + h % 24 / 4],
          'precipitation_probability': [for (var h = 1; h <= 48; h++) 5],
        },
      };

      final parsed = parseOpenMeteo(forecast, ensemble, now: at);
      final afternoon = parsed.dayParts.firstWhere(
        (p) => p.start == DateTime(2026, 10, 16, 12),
        orElse: () => parsed.dayParts.firstWhere(
          (p) =>
              p.start.isBefore(DateTime(2026, 10, 16, 12)) &&
              p.end.isAfter(DateTime(2026, 10, 16, 12)),
        ),
      );
      // Tomorrow's afternoon has no rain in any run.
      expect(afternoon.rainChance, 0);
      final today = parsed.days.first;
      expect(today.rainChance, 50);
      // Without the ensemble, the likeliest hour's.
      expect(parseOpenMeteo(forecast, null, now: at).days.first.rainChance, 5);
    });

    test('fetches the forecast for the rounded place, and the ensemble; '
        'without the ensemble, still a forecast', () async {
      final asked = <Uri>[];
      final client = MockClient((request) async {
        asked.add(request.url);
        if (request.url.host == 'ensemble-api.open-meteo.com') {
          return http.Response('{"error":true,"reason":"down"}', 500);
        }
        return http.Response(jsonEncode(forecastJson), 200);
      });

      final forecast = await OpenMeteoForecastSource(client: client)
          .fetch(const Coordinates(47.6062, -122.3321), now: now);

      expect(forecast.days, isNotEmpty);
      expect(asked, hasLength(2));
      for (final url in asked) {
        expect(url.queryParameters['latitude'], '47.61');
        expect(url.queryParameters['longitude'], '-122.33');
      }
    });

    test("a refused forecast says why", () async {
      final client = MockClient(
        (_) async => http.Response('{"error":true,"reason":"Bad place"}', 400),
      );
      expect(
        OpenMeteoForecastSource(client: client)
            .fetch(const Coordinates(0, 0), now: now),
        throwsA(
          isA<WeatherException>().having(
            (e) => e.message,
            'message',
            contains('Bad place'),
          ),
        ),
      );
    });
  });

  group('Weather', () {
    final now = DateTime(2026, 10, 14, 13, 30);

    test("off, it never asks or reads where the device is", () async {
      final location = _CountingLocation();
      final forecasts = _FakeForecasts();
      final weather = Weather(
        forecasts: forecasts,
        location: location,
        persist: false,
        clock: () => now,
      );

      await weather.load();
      await weather.refresh(force: true);

      expect(weather.enabled, isFalse);
      expect(location.asked + location.requested + location.read, 0);
      expect(forecasts.fetched, isEmpty);
    });

    test('turned on, it asks, then fetches for the rounded place', () async {
      final location = _CountingLocation(LocationAccess.denied);
      final forecasts = _FakeForecasts();
      final weather = Weather(
        forecasts: forecasts,
        location: location,
        persist: false,
        clock: () => now,
      );

      expect(await weather.enable(), isFalse);
      expect(location.requested, 1);
      expect(weather.access, LocationAccess.denied);
      expect(forecasts.fetched, isEmpty);

      location.granted = LocationAccess.granted;
      expect(await weather.enable(), isTrue);
      await weather.refresh();
      expect(forecasts.fetched, [const Coordinates(47.61, -122.33)]);
      expect(weather.forecast, isNotNull);
    });

    test('blocked, it asks no more: the settings must allow it', () async {
      final location = _CountingLocation(LocationAccess.blocked);
      final weather = Weather(
        forecasts: _FakeForecasts(),
        location: location,
        persist: false,
      );
      expect(await weather.enable(), isFalse);
      expect(location.requested, 0);
      expect(weather.access, LocationAccess.blocked);
    });

    test('each forecast replaces the last whole; a failure keeps it till '
        'the next', () async {
      var time = now;
      final forecasts = _FakeForecasts();
      final weather = Weather(
        forecasts: forecasts,
        location: _CountingLocation(),
        persist: false,
        enabled: true,
        clock: () => time,
      );
      await weather.refresh();
      final first = weather.forecast!;

      // Fresh: not fetched again.
      await weather.refresh();
      expect(forecasts.fetched, hasLength(1));

      time = now.add(const Duration(hours: 1));
      forecasts.failWith = WeatherException('offline');
      await weather.refresh();
      expect(weather.forecast, same(first));
      expect(weather.error, isA<WeatherException>());

      forecasts
        ..failWith = null
        ..make = (now) => Forecast(fetchedAt: now);
      await weather.refresh();
      expect(weather.forecast!.fetchedAt, time);
      expect(weather.forecast!.days, isEmpty);
      expect(weather.error, isNull);
    });

    test('turned off, the forecast goes, and one coming is dropped', () async {
      final weather = Weather(
        forecasts: _FakeForecasts(),
        location: _CountingLocation(),
        persist: false,
        enabled: true,
        clock: () => now,
      );
      final fetching = weather.refresh();
      weather.disable();
      await fetching;
      expect(weather.forecast, isNull);
      expect(weather.enabled, isFalse);
    });
  });

  group('nowcast', () {
    final now = DateTime(2026, 10, 14, 13, 50);
    String label(DateTime t) =>
        '${t.hour}:${t.minute.toString().padLeft(2, '0')}';
    List<WeatherSpan> quarters(List<int> chances) => [
      for (final (i, c) in chances.indexed)
        _span(
          DateTime(2026, 10, 14, 13, 45).add(Duration(minutes: 15 * i)),
          const Duration(minutes: 15),
          chance: c,
        ),
    ];

    test('when rain is likely to start', () {
      expect(
        nowcast(
          quarters([0, 10, 30, 60, 70, 40, 0, 0]),
          now: now,
          timeLabel: label,
        ),
        'Rain likely from about 14:30 (60%).',
      );
    });

    test('when rain going on eases', () {
      expect(
        nowcast(quarters([80, 70, 20, 0]), now: now, timeLabel: label),
        'Rain likely now, easing about 14:15.',
      );
    });

    test('no rain', () {
      expect(
        nowcast(
          quarters([0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]),
          now: now,
          timeLabel: label,
        ),
        'No rain expected in the next 3 hours.',
      );
    });
  });

  group('WeatherStrip', () {
    final now = DateTime(2026, 10, 14, 13, 30);
    final today = DateTime(2026, 10, 14);

    Future<(Weather, AppSettings)> pump(
      WidgetTester tester, {
      required DateTime day,
      ValueChanged<DateTime>? onDay,
      LocationAccess access = LocationAccess.granted,
    }) async {
      final settings = AppSettings(persist: false);
      final weather = Weather(
        forecasts: _FakeForecasts(),
        location: _CountingLocation(access),
        persist: false,
        enabled: access == LocationAccess.granted,
        clock: () => now,
      );
      if (access == LocationAccess.granted) {
        await weather.refresh();
      } else {
        await weather.enable();
      }
      await tester.pumpWidget(
        MaterialApp(
          home: AppSettingsScope(
            settings: settings,
            child: Scaffold(
              body: ListenableBuilder(
                listenable: weather,
                builder: (context, _) => WeatherStrip(
                  weather: weather,
                  day: day,
                  now: now,
                  collapsed: false,
                  onCollapsed: (_) {},
                  onDay: onDay,
                ),
              ),
            ),
          ),
        ),
      );
      return (weather, settings);
    }

    testWidgets("today's, from now, in the units set", (tester) async {
      final (_, settings) = await pump(tester, day: today);

      expect(
        find.text(
          'Cloudy · 61° / 50° · 70% rain · '
          '0.28 in',
        ),
        findsOneWidget,
      );
      expect(
        find.text('Rain likely from about 2:45 PM (55%).'),
        findsOneWidget,
      );
      expect(find.text('Open-Meteo'), findsOneWidget);

      await settings.setTemperatureUnit(TemperatureUnit.celsius);
      await settings.setPrecipitationUnit(PrecipitationUnit.millimeters);
      await tester.pump();
      expect(
        find.text(
          'Cloudy · 16° / 10° · 70% rain · '
          '7.0 mm',
        ),
        findsOneWidget,
      );
    });

    testWidgets('a day of the week goes to it', (tester) async {
      DateTime? went;
      await pump(tester, day: today, onDay: (d) => went = d);

      await tester.tap(find.bySemanticsLabel(RegExp(r'^Fri, Rain')));
      expect(went, DateTime(2026, 10, 16));
    });

    testWidgets('nothing for a day past', (tester) async {
      await pump(tester, day: DateTime(2026, 10, 13));
      expect(
        find.descendant(
          of: find.byType(WeatherStrip),
          matching: find.byType(Text),
        ),
        findsNothing,
      );
    });

    testWidgets('refused the location, it says so', (tester) async {
      await pump(tester, day: today, access: LocationAccess.blocked);
      expect(
        find.text('The weather needs to know roughly where the device is.'),
        findsOneWidget,
      );
      expect(find.text('Settings'), findsOneWidget);
    });
  });

  testWidgets('Settings turns the weather on, and picks its units', (
    tester,
  ) async {
    final settings = AppSettings(persist: false);
    final location = _CountingLocation();
    final weather = Weather(
      forecasts: _FakeForecasts(),
      location: location,
      persist: false,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: WeatherScope(
          weather: weather,
          child: SettingsScreen(settings: settings),
        ),
      ),
    );
    await tester.scrollUntilVisible(
      find.text('Show the weather'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(location.asked + location.requested, 0);

    await tester.tap(find.text('Show the weather'));
    await tester.pumpAndSettle();
    expect(weather.enabled, isTrue);
    expect(location.asked, 1);

    expect(settings.temperatureUnit, TemperatureUnit.fahrenheit);
    await tester.scrollUntilVisible(
      find.text('Fahrenheit (°F)'),
      100,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Fahrenheit (°F)'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Celsius (°C)').last);
    await tester.pumpAndSettle();
    expect(settings.temperatureUnit, TemperatureUnit.celsius);
  });
}
