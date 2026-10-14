import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:time_tracker_client/demo/sample_data.dart';
import 'package:time_tracker_client/demo/weather_sample.dart';
import 'package:time_tracker_client/screens/events_screen.dart';
import 'package:time_tracker_client/screens/settings_screen.dart';
import 'package:time_tracker_client/services/app_settings.dart';
import 'package:time_tracker_client/services/people_repository.dart';
import 'package:time_tracker_client/services/weather.dart';
import 'package:time_tracker_client/theme.dart';
import 'package:time_tracker_client/widgets/day_timeline.dart';

/// A fixed moment, so every run renders the same thing: a Friday.
final _now = DateTime(2026, 10, 2, 13, 30);

/// A typical phone's screen, in logical pixels.
const _phone = Size(390, 844);

void main() {
  final sample = SampleData(_now);

  for (final brightness in Brightness.values) {
    final mode = brightness.name;

    Future<void> render(
      WidgetTester tester,
      String name,
      Widget screen, {
      Future<void> Function()? then,
      Weather? weather,
    }) async {
      tester.view.physicalSize = _phone * 2;
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      debugDisableShadows = false;
      final settings = AppSettings(persist: false);
      weather ??= Weather(
        forecasts: SampleForecastSource(),
        location: FixedLocationSource(),
        persist: false,
        enabled: true,
        clock: () => _now,
      );
      // Fetched, as it would be by the time the page is looked at.
      await weather.load();
      try {
        await tester.pumpWidget(
          PeopleScope(
            repository: sample.peopleRepository(),
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: appTheme(brightness),
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context).copyWith(disableAnimations: true),
                child: AppSettingsScope(
                  settings: settings,
                  child: WeatherScope(weather: weather!, child: child!),
                ),
              ),
              home: screen is SettingsScreen
                  ? SettingsScreen(settings: settings)
                  : screen,
            ),
          ),
        );
        await tester.pumpAndSettle();
        await then?.call();
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile('${name}_$mode.png'),
        );
      } finally {
        debugDisableShadows = true;
      }
    }

    Widget events() => EventsScreen(
      repository: sample.eventsRepository(),
      notesRepository: sample.notesRepository(),
      actionsRepository: sample.actionsRepository(),
      serverLabel: 'sample',
      clock: () => _now,
    );

    /// Scrolls the timeline so [hour] is near the top.
    Future<void> scrollTo(WidgetTester tester, double hour) async {
      final scrollable = find
          .ancestor(
            of: find.byType(DayTimeline).first,
            matching: find.byWidgetPredicate(
              (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
            ),
          )
          .first;
      final state = tester.state<ScrollableState>(scrollable);
      state.position.jumpTo(hour * 60 * defaultTimelineScale);
      await tester.pumpAndSettle();
    }

    // Today, from now: the quarter hours' showers coming, then the hours.
    testWidgets('weather_today ($mode)', (tester) async {
      await render(
        tester,
        'weather_today',
        events(),
        then: () => scrollTo(tester, 11.5),
      );
    });

    // Two days on: by parts of the day.
    testWidgets('weather_day_parts ($mode)', (tester) async {
      await render(
        tester,
        'weather_day_parts',
        events(),
        then: () async {
          await tester.tap(find.bySemanticsLabel(RegExp(r'^Sun, ')));
          await tester.pumpAndSettle();
          await scrollTo(tester, 6);
        },
      );
    });

    /// Settings, scrolled to its Weather section.
    Future<void> toWeather(WidgetTester tester) async {
      await tester.scrollUntilVisible(
        find.text('Weather'),
        100,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.drag(find.byType(Scrollable).first, const Offset(0, -260));
      await tester.pumpAndSettle();
    }

    // For where the device is, allowed.
    testWidgets('weather_settings ($mode)', (tester) async {
      await render(
        tester,
        'weather_settings',
        SettingsScreen(settings: AppSettings(persist: false)),
        then: () => toWeather(tester),
      );
    });

    // The location refused.
    testWidgets('weather_settings_refused ($mode)', (tester) async {
      await render(
        tester,
        'weather_settings_refused',
        SettingsScreen(settings: AppSettings(persist: false)),
        weather: Weather(
          forecasts: SampleForecastSource(),
          location: FixedLocationSource(
            const Coordinates(0, 0),
            LocationAccess.denied,
          ),
          persist: false,
          enabled: true,
          clock: () => _now,
        ),
        then: () => toWeather(tester),
      );
    });

    // For a place given.
    testWidgets('weather_settings_place ($mode)', (tester) async {
      await render(
        tester,
        'weather_settings_place',
        SettingsScreen(settings: AppSettings(persist: false)),
        weather: Weather(
          forecasts: SampleForecastSource(),
          location: FixedLocationSource(
            const Coordinates(0, 0),
            LocationAccess.denied,
          ),
          persist: false,
          enabled: true,
          usesDevice: false,
          place: const Coordinates(47.6062, -122.3321),
          clock: () => _now,
        ),
        then: () => toWeather(tester),
      );
    });
  }
}
