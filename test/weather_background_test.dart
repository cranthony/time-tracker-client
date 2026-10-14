import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:time_tracker_client/demo/weather_sample.dart';
import 'package:time_tracker_client/models/weather.dart';
import 'package:time_tracker_client/screens/background_updates_screen.dart';
import 'package:time_tracker_client/services/app_settings.dart';
import 'package:time_tracker_client/services/background_refresh.dart';
import 'package:time_tracker_client/services/schedule_hints_repository.dart';
import 'package:time_tracker_client/services/weather.dart';

/// Forecasts made to order, counting where they were for.
class _FakeForecasts implements ForecastSource {
  final fetched = <Coordinates>[];
  Object? failWith;

  @override
  Future<Forecast> fetch(Coordinates at, {required DateTime now}) async {
    fetched.add(at);
    if (failWith case final error?) throw error;
    return sampleForecast(now);
  }
}

/// Where the device is, failing the test if it's ever read or asked.
class _UntouchableLocation implements LocationSource {
  @override
  Future<LocationAccess> access() async => fail('asked for access');

  @override
  Future<LocationAccess> requestAccess() async => fail('requested access');

  @override
  Future<Coordinates> current() async => fail('read the location');

  @override
  Future<void> openSettings() async {}
}

void main() {
  final now = DateTime(2026, 10, 14, 7, 0);

  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });

  Future<void> keepPicked({
    bool enabled = true,
    bool device = true,
    Coordinates? place,
  }) async {
    final prefs = SharedPreferencesAsync();
    await prefs.setBool(KeptWeather.enabledKey, enabled);
    await prefs.setBool(KeptWeather.usesDeviceKey, device);
    if (place != null) {
      await prefs.setDouble(KeptWeather.latitudeKey, place.latitude);
      await prefs.setDouble(KeptWeather.longitudeKey, place.longitude);
    }
  }

  test('a forecast is kept as it was', () {
    final forecast = sampleForecast(now);
    final back = Forecast.fromJson(forecast.toJson())!;
    expect(back.fetchedAt, forecast.fetchedAt);
    expect(back.source, forecast.source);
    expect(back.quarterHours, forecast.quarterHours);
    expect(back.hours, forecast.hours);
    expect(back.dayParts, forecast.dayParts);
    expect(back.days, forecast.days);
    expect(back.sun, forecast.sun);
    expect(back.sun, isNotEmpty);
  });

  group('the background fetch', () {
    test('off, fetches nothing', () async {
      await keepPicked(enabled: false);
      final forecasts = _FakeForecasts();
      expect(await refreshWeatherInBackground(forecasts: forecasts), isNull);
      expect(forecasts.fetched, isEmpty);
    });

    test('for where the device is, uses where it was last found -- never '
        'asking where it is now -- and keeps the forecast', () async {
      await keepPicked();
      await KeptWeather.keepDevicePlace(const Coordinates(47.61, -122.33));
      final forecasts = _FakeForecasts();

      final record = await refreshWeatherInBackground(
        forecasts: forecasts,
        clock: () => now,
      );

      expect(record!.ok, isTrue);
      expect(forecasts.fetched, [const Coordinates(47.61, -122.33)]);
      final kept = await KeptWeather.forecast();
      expect(kept!.forecast.fetchedAt, now);
      expect(kept.device, isTrue);
      expect((await KeptWeather.lastBackground())!.at, now);
    });

    test('for where the device is, never yet found, says so', () async {
      await keepPicked();
      final forecasts = _FakeForecasts();

      final record = await refreshWeatherInBackground(forecasts: forecasts);

      expect(record!.problem, contains('open the app'));
      expect(forecasts.fetched, isEmpty);
    });

    test('for a place given, uses it', () async {
      await keepPicked(
        device: false,
        place: const Coordinates(40.7128, -74.006),
      );
      final forecasts = _FakeForecasts();

      await refreshWeatherInBackground(forecasts: forecasts, clock: () => now);

      expect(forecasts.fetched, [const Coordinates(40.71, -74.01)]);
      expect((await KeptWeather.forecast())!.device, isFalse);
    });

    test("one that fails keeps the forecast before, and says why", () async {
      await keepPicked(device: false, place: const Coordinates(1, 2));
      final forecasts = _FakeForecasts();
      await refreshWeatherInBackground(forecasts: forecasts, clock: () => now);
      forecasts.failWith = WeatherException('Open-Meteo answered 503');

      final record = await refreshWeatherInBackground(
        forecasts: forecasts,
        clock: () => now.add(const Duration(hours: 1)),
      );

      expect(record!.problem, 'Open-Meteo answered 503');
      expect((await KeptWeather.forecast())!.forecast.fetchedAt, now);
    });
  });

  group('the app, opening', () {
    test('shows the forecast fetched in the background at once, and fetches '
        'no other while it is fresh', () async {
      await keepPicked();
      await KeptWeather.keepDevicePlace(const Coordinates(47.61, -122.33));
      await refreshWeatherInBackground(
        forecasts: _FakeForecasts(),
        clock: () => now,
      );
      final forecasts = _FakeForecasts();
      final weather = Weather(
        forecasts: forecasts,
        location: FixedLocationSource(),
        clock: () => now.add(const Duration(minutes: 10)),
      );

      await weather.load();

      expect(weather.forecast!.fetchedAt, now);
      expect(forecasts.fetched, isEmpty);
    });

    test('an old one is shown till a new one replaces it', () async {
      await keepPicked();
      await KeptWeather.keepDevicePlace(const Coordinates(47.61, -122.33));
      await refreshWeatherInBackground(
        forecasts: _FakeForecasts(),
        clock: () => now,
      );
      final later = now.add(const Duration(hours: 2));
      final forecasts = _FakeForecasts();
      final weather = Weather(
        forecasts: forecasts,
        location: FixedLocationSource(),
        clock: () => later,
      );

      await weather.load();

      expect(forecasts.fetched, hasLength(1));
      expect(weather.forecast!.fetchedAt, later);
      expect((await KeptWeather.forecast())!.forecast.fetchedAt, later);
    });

    test("one kept for another place isn't shown", () async {
      await keepPicked(device: false, place: const Coordinates(1, 2));
      await refreshWeatherInBackground(
        forecasts: _FakeForecasts(),
        clock: () => now,
      );
      final weather = Weather(
        forecasts: _FakeForecasts()..failWith = WeatherException('offline'),
        location: _UntouchableLocation(),
        usesDevice: false,
        place: const Coordinates(1, 2),
        clock: () => now,
      );
      // Moved, since.
      await keepPicked(device: false, place: const Coordinates(3, 4));

      await weather.load();

      expect(weather.place, const Coordinates(3, 4));
      expect(weather.forecast, isNull);
    });

    test(
      'where the device is, found in the app, is kept for the background',
      () async {
        await keepPicked();
        final weather = Weather(
          forecasts: _FakeForecasts(),
          location: FixedLocationSource(const Coordinates(47.6062, -122.3321)),
          clock: () => now,
        );
        await weather.load();

        expect(
          await KeptWeather.devicePlace(),
          const Coordinates(47.61, -122.33),
        );
      },
    );
  });

  group('scheduling', () {
    test(
      "every 15 minutes while it's on, as set; not till it's known; none when "
      "it's off",
      () async {
        final scheduled = <Duration?>[];
        final settings = AppSettings(persist: false);
        final weather = Weather(
          forecasts: _FakeForecasts(),
          location: FixedLocationSource(),
          persist: false,
          enabled: true,
          clock: () => now,
        );
        final refresh = BackgroundRefresh(
          settings: settings,
          weather: weather,
          supported: true,
          schedule: (_) async {},
          scheduleWeather: (every) async => scheduled.add(every),
          lastRecord: () async => null,
          lastWeather: () async => null,
        );
        addTearDown(refresh.dispose);
        expect(scheduled, isEmpty);

        await weather.load();
        expect(scheduled, [const Duration(minutes: 15)]);

        await settings.setWeatherRefresh(const Duration(hours: 3));
        expect(scheduled.last, const Duration(hours: 3));

        weather.disable();
        expect(scheduled.last, isNull);

        await settings.setWeatherRefresh(const Duration(minutes: 30));
        expect(scheduled, hasLength(3));
      },
    );
  });

  group('the Background updates page', () {
    Future<(AppSettings, BackgroundRefresh)> pump(
      WidgetTester tester, {
      WeatherRefreshRecord? last,
    }) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final settings = AppSettings(persist: false);
      final weather = Weather(
        forecasts: _FakeForecasts(),
        location: FixedLocationSource(),
        persist: false,
        enabled: true,
        usesDevice: true,
      );
      await weather.load();
      final refresh = BackgroundRefresh(
        repository: InMemoryScheduleHintsRepository(),
        settings: settings,
        weather: weather,
        supported: true,
        clock: () => now,
        schedule: (_) async {},
        scheduleWeather: (_) async {},
        lastRecord: () async => null,
        lastWeather: () async => last,
      );
      await tester.pumpWidget(
        MaterialApp(home: BackgroundUpdatesScreen(refresh: refresh)),
      );
      await tester.pumpAndSettle();
      return (settings, refresh);
    }

    testWidgets('sets how often the weather is fetched', (tester) async {
      final (settings, _) = await pump(tester);
      expect(find.text('Weather'), findsOneWidget);
      // The weather's, not the proposal's, which is every 15 minutes too.
      final forecast = find.widgetWithText(ListTile, 'Forecast');
      final shown = find.descendant(
        of: forecast,
        matching: find.text('Every 15 min'),
      );
      expect(shown, findsOneWidget);

      await tester.tap(shown);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Every 3 hours').last);
      await tester.pumpAndSettle();
      expect(settings.weatherRefresh, const Duration(hours: 3));

      await tester.tap(find.text('Every 3 hours'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Off').last);
      await tester.pumpAndSettle();
      expect(settings.weatherRefresh, isNull);
    });

    testWidgets('says what the last weather fetch did', (tester) async {
      await pump(
        tester,
        last: WeatherRefreshRecord(
          at: now.subtract(const Duration(minutes: 20)),
          problem: 'Open-Meteo answered 503',
        ),
      );
      expect(find.text('Open-Meteo answered 503'), findsOneWidget);
      expect(find.textContaining('never asked where it is'), findsOneWidget);
    });
  });
}
