import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:time_tracker_client/demo/weather_sample.dart';
import 'package:time_tracker_client/models/event.dart';
import 'package:time_tracker_client/models/goal.dart';
import 'package:time_tracker_client/models/note.dart';
import 'package:time_tracker_client/models/plan_action.dart';
import 'package:time_tracker_client/models/weather.dart';
import 'package:time_tracker_client/platform/calendar_widget.dart';
import 'package:time_tracker_client/services/app_settings.dart';
import 'package:time_tracker_client/services/event_store.dart';
import 'package:time_tracker_client/services/events_repository.dart';
import 'package:time_tracker_client/services/weather.dart';

/// Today, at noon.
final _now = DateTime(2026, 10, 8, 12);

DateTime _day(int offset) => DateTime(2026, 10, 8 + offset);

Event _event(
  String id,
  int dayOffset, {
  int hour = 12,
  int hours = 1,
  bool cancelled = false,
  List<String> actions = const [],
}) {
  final start = DateTime(2026, 10, 8 + dayOffset, hour);
  return Event.fromJson({
    'id': id,
    'summary': id,
    'start': localIsoTimestamp(start),
    'end': localIsoTimestamp(start.add(Duration(hours: hours))),
    'is_cancelled': cancelled,
    'action_ids': actions,
  });
}

/// A store with [days] from today kept, holding [events].
EventStore _store(List<Event> events, {int days = 7}) {
  final store = EventStore(repository: InMemoryEventsRepository());
  for (var i = 0; i < days; i++) {
    final from = _day(i), to = _day(i + 1);
    store.putDay(from, [
      for (final e in events)
        if (e.start.isBefore(to) && e.end.isAfter(from)) e,
    ]);
  }
  return store;
}

/// Each day's events' ids, by day.
List<List<String?>> _ids(Map<String, Object?>? snapshot) => [
  for (final day in snapshot!['days'] as List)
    [
      for (final e in (day as Map)['events'] as List)
        (e as Map)['id'] as String?,
    ],
];

class _FakeHost implements CalendarWidgetHost {
  final saved = <String?>[];
  final scheduled = <List<DateTime>>[];
  var redraws = 0;

  @override
  Future<void> save(String? snapshot) async => saved.add(snapshot);

  /// What was saved last -- by the widget under test, or added to [saved]
  /// by a test, as the background task would save it from its isolate.
  @override
  Future<String?> kept() async => saved.lastOrNull;

  final weathers = <String?>[];

  @override
  Future<void> saveWeather(String? weather) async => weathers.add(weather);

  @override
  Future<void> schedule(List<DateTime> times) async => scheduled.add(times);

  @override
  Future<void> redraw() async => redraws++;

  var pins = 0;

  @override
  Future<void> pin() async => pins++;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('calendarSnapshot', () {
    test('starts at now: what has ended is left out, what is on is in', () {
      final store = _store([
        _event('over', 0, hour: 9),
        _event('on', 0, hour: 11, hours: 2),
        _event('later', 0, hour: 15),
        _event('tomorrow', 1, hour: 9),
      ]);
      final snapshot = calendarSnapshot(store, now: _now);
      expect(_ids(snapshot), [
        ['on', 'later'],
        ['tomorrow'],
        <String>[],
        <String>[],
      ]);
      final today = (snapshot!['days'] as List).first as Map;
      expect(today['start'], _day(0).millisecondsSinceEpoch);
      expect(today['end'], _day(1).millisecondsSinceEpoch);
    });

    test('an event across midnight is in each day it is in', () {
      final store = _store([_event('night', 0, hour: 22, hours: 4)]);
      expect(_ids(calendarSnapshot(store, now: _now)).take(2), [
        ['night'],
        ['night'],
      ]);
    });

    test('leaves out cancelled events', () {
      final store = _store([_event('off', 0, hour: 15, cancelled: true)]);
      expect(_ids(calendarSnapshot(store, now: _now)).first, isEmpty);
    });

    test('gives each day the two active goals due soonest in it', () {
      final goals = [
        const Goal(id: 'late', title: 'Late', deadline: '2026-10-08'),
        const Goal(id: 'b', title: 'B', deadline: '2026-10-08T09:00'),
        const Goal(id: 'a', title: 'A', deadline: '2026-10-08T09:00'),
        const Goal(id: 'third', title: 'Third', deadline: '2026-10-08T17:00'),
        const Goal(
          id: 'done',
          title: 'Done',
          deadline: '2026-10-08T08:00',
          status: 'done',
        ),
        const Goal(id: 'tomorrow', title: 'Tomorrow', deadline: '2026-10-09'),
        const Goal(id: 'overdue', title: 'Overdue', deadline: '2026-10-07'),
        const Goal(id: 'none', title: 'None', status: 'inactive'),
      ];
      final days =
          calendarSnapshot(_store([]), goals: goals, now: _now)!['days']
              as List;
      expect((days[0] as Map)['goals'], [
        {'id': 'a', 'title': 'A'},
        {'id': 'b', 'title': 'B'},
      ]);
      expect((days[0] as Map)['more_goals'], 2);
      expect((days[1] as Map)['goals'], [
        {'id': 'tomorrow', 'title': 'Tomorrow'},
      ]);
      expect((days[1] as Map).containsKey('more_goals'), isFalse);
      expect((days[2] as Map).containsKey('goals'), isFalse);
    });

    test('shows only the days kept, from today, in a row', () {
      expect(
        (calendarSnapshot(_store([], days: 2), now: _now)!['days'] as List)
            .length,
        2,
      );
      expect(calendarSnapshot(_store([], days: 0), now: _now), isNull);
    });

    test('colors each event as the timeline does: its action\'s color', () {
      final store = _store([
        _event('tagged', 0, hour: 15, actions: ['a']),
      ]);
      final snapshot = calendarSnapshot(
        store,
        now: _now,
        actions: [
          const PlanAction(
            id: 'a',
            name: 'A',
            status: 'active',
            backgroundColor: '#123456',
          ),
        ],
      );
      final event =
          (((snapshot!['days'] as List).first as Map)['events'] as List).first
              as Map;
      expect(event['color'], 0xFF123456);
    });
  });

  test('redrawTimes: each event\'s start and end, and each day\'s end', () {
    final store = _store([
      _event('on', 0, hour: 11, hours: 2),
      _event('later', 0, hour: 15),
    ], days: 1);
    expect(redrawTimes(calendarSnapshot(store, now: _now)), [
      DateTime(2026, 10, 8, 11),
      DateTime(2026, 10, 8, 13),
      DateTime(2026, 10, 8, 15),
      DateTime(2026, 10, 8, 16),
      _day(1),
    ]);
    expect(redrawTimes(null), isEmpty);
  });

  group('publish', () {
    test('keeps the snapshot, schedules its redraws, and draws it', () async {
      final host = _FakeHost();
      final widget = CalendarWidget(host: host, enabled: true);
      final store = _store([_event('later', 0, hour: 15)], days: 1);
      await widget.publish(store, now: _now);

      final snapshot = calendarSnapshot(store, now: _now);
      expect(host.saved, [jsonEncode(snapshot)]);
      expect(host.scheduled, [redrawTimes(snapshot)]);
      expect(host.redraws, 1);
    });

    test('publishes again only when what it shows changes', () async {
      final host = _FakeHost();
      final widget = CalendarWidget(host: host, enabled: true);
      final store = _store([_event('later', 0, hour: 15)], days: 1);
      await widget.publish(store, now: _now);
      await widget.publish(store, now: _now);
      expect(host.redraws, 1);

      store.putDay(_day(0), [_event('later', 0, hour: 16)]);
      await widget.publish(store, now: _now);
      expect(host.redraws, 2);
    });

    test('publishes again when what is kept was saved elsewhere: by the '
        'background task, from its own isolate', () async {
      final host = _FakeHost();
      final widget = CalendarWidget(host: host, enabled: true);
      final store = _store([_event('later', 0, hour: 15)], days: 1);
      await widget.publish(store, now: _now);
      final own = host.saved.single;

      // The task, having fetched the goals before a change to them was
      // sent, kept a snapshot of its own.
      host.saved.add('{"days":[]}');
      await widget.publish(store, now: _now);
      expect(host.saved, [own, '{"days":[]}', own]);
      expect(host.redraws, 2);
    });

    test('with no events kept, says so: signed out, say', () async {
      final host = _FakeHost();
      final widget = CalendarWidget(host: host, enabled: true);
      final store = _store([_event('later', 0, hour: 15)], days: 1);
      await widget.publish(store, now: _now);
      await store.clear();
      await widget.publish(store, now: _now);
      expect(host.saved.last, isNull);
      expect(host.scheduled.last, isEmpty);
    });

    test('does nothing off Android', () async {
      final host = _FakeHost();
      final widget = CalendarWidget(host: host, enabled: false);
      await widget.publish(_store([]), now: _now);
      expect(host.saved, isEmpty);
    });
  });

  test(
    'pin asks to add it to the home screen; offered only when built so',
    () async {
      final host = _FakeHost();
      await CalendarWidget.pin(host: host);
      expect(host.pins, 1);
      // Not in this build: no --dart-define=CALENDAR_PIN=true.
      expect(CalendarWidget.pinOffered, isFalse);
    },
  );

  group('taps', () {
    const channel = MethodChannel(CalendarWidget.channelName);
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    tearDown(() => messenger.setMockMethodCallHandler(channel, null));

    Future<void> fromAndroid(String method, Object? arguments) =>
        messenger.handlePlatformMessage(
          channel.name,
          const StandardMethodCodec().encodeMethodCall(
            MethodCall(method, arguments),
          ),
          (_) {},
        );

    test('reports the tap that launched the app, then later taps', () async {
      final launchedAt = DateTime(2026, 10, 8, 15);
      messenger.setMockMethodCallHandler(channel, (call) async {
        expect(call.method, 'takeLaunchRequest');
        return {'at': launchedAt.millisecondsSinceEpoch, 'event': 'later'};
      });
      final widget = CalendarWidget(
        host: _FakeHost(),
        channel: channel,
        enabled: true,
      );
      final taps = <CalendarTap>[];
      await widget.start();
      // Buffered until something listens, as on a cold start.
      widget.taps.listen(taps.add);

      await fromAndroid('show', {'at': null, 'event': null});
      await pumpEventQueue();

      expect(taps, [
        (at: launchedAt, eventId: 'later'),
        (at: null, eventId: null),
      ]);
      widget.dispose();
    });

    test('reports nothing when launched normally', () async {
      messenger.setMockMethodCallHandler(channel, (call) async => null);
      final widget = CalendarWidget(
        host: _FakeHost(),
        channel: channel,
        enabled: true,
      );
      final taps = <CalendarTap>[];
      widget.taps.listen(taps.add);
      await widget.start();
      await pumpEventQueue();

      expect(taps, isEmpty);
      widget.dispose();
    });
  });

  group('the weather in its headers', () {
    Map<String, Object?> day(Map<String, Object?> weather, DateTime midnight) =>
        (weather['days'] as List).cast<Map<String, Object?>>().firstWhere(
          (d) => d['start'] == midnight.millisecondsSinceEpoch,
        );

    test(
      "each day's sky, chance of rain and high and low; today's from now",
      () {
        final weather = calendarWeather(sampleForecast(_now));

        expect(weather['days'], hasLength(7));
        expect(day(weather, _day(0)), {
          'start': _day(0).millisecondsSinceEpoch,
          'icon': '☁️',
          'rain': '70%',
          'temps': '61° / 50°',
          'temps_compact': '61/50°',
        });
        expect(day(weather, _day(2))['icon'], '🌧️');
        expect(day(weather, _day(2))['rain'], '90%');
      },
    );

    test('a chance of rain shows whenever it is more than none', () {
      final weather = calendarWeather(sampleForecast(_now));
      // Clear, with none.
      expect(day(weather, _day(5)).containsKey('rain'), isFalse);
      expect(day(weather, _day(5))['icon'], '☀️');
      final forecast = Forecast(
        fetchedAt: _now,
        days: [
          WeatherSpan(
            start: _now,
            end: _day(1),
            sky: Sky.partlyCloudy,
            rainChance: 1,
            high: 20,
            low: 19.9,
          ),
        ],
      );
      final today = day(calendarWeather(forecast), _day(0));
      expect(today['rain'], '1%');
      // Late in the day, they round the same: one temperature.
      expect(today['temps'], '68°');
      expect(today['temps_compact'], '68°');
    });

    test('in the units set', () {
      final weather = calendarWeather(
        sampleForecast(_now),
        unit: TemperatureUnit.celsius,
      );
      expect(day(weather, _day(0))['temps'], '16° / 10°');
    });

    test('publishes it apart from the events, again only as it changes, and '
        'none when the weather is off', () async {
      final host = _FakeHost();
      final widget = CalendarWidget(host: host, enabled: true);
      final forecast = sampleForecast(_now);

      await widget.publishWeather(forecast);
      await widget.publishWeather(forecast);
      expect(host.weathers, [jsonEncode(calendarWeather(forecast))]);
      expect(host.saved, isEmpty);
      expect(host.redraws, 1);

      await widget.publishWeather(forecast, unit: TemperatureUnit.celsius);
      expect(host.redraws, 2);

      await widget.publishWeather(null);
      expect(host.weathers.last, isNull);
      expect(host.redraws, 3);
    });
  });

  group('the weather, linked to the app', () {
    Weather weather({required bool enabled}) => Weather(
      forecasts: SampleForecastSource(),
      location: FixedLocationSource(),
      persist: false,
      enabled: enabled,
      place: const Coordinates(47.61, -122.33),
      clock: () => _now,
    );

    test('on: each forecast, in the units set', () async {
      final host = _FakeHost();
      final settings = AppSettings(persist: false);
      final on = weather(enabled: true);
      final link = CalendarWeatherLink(
        widget: CalendarWidget(host: host, enabled: true),
        weather: on,
        settings: settings,
      );
      addTearDown(link.dispose);
      // Not till it's known whether it's on.
      expect(host.weathers, isEmpty);

      await on.load();
      await pumpEventQueue();
      expect(host.weathers.last, jsonEncode(calendarWeather(on.forecast!)));
      expect(jsonDecode(host.weathers.last!)['days'], isNotEmpty);

      await settings.setTemperatureUnit(TemperatureUnit.celsius);
      await pumpEventQueue();
      expect(
        host.weathers.last,
        jsonEncode(
          calendarWeather(on.forecast!, unit: TemperatureUnit.celsius),
        ),
      );
    });

    test('turned off, it goes', () async {
      final host = _FakeHost();
      final on = weather(enabled: true);
      final link = CalendarWeatherLink(
        widget: CalendarWidget(host: host, enabled: true),
        weather: on,
        settings: AppSettings(persist: false),
      );
      addTearDown(link.dispose);
      await on.load();
      await pumpEventQueue();
      expect(host.weathers.last, isNotNull);

      on.disable();
      await pumpEventQueue();
      expect(host.weathers.last, isNull);
    });

    test('off: none -- any kept from before is cleared -- and nothing '
        'fetched for it', () async {
      final host = _FakeHost();
      final off = weather(enabled: false);
      final link = CalendarWeatherLink(
        widget: CalendarWidget(host: host, enabled: true),
        weather: off,
        settings: AppSettings(persist: false),
      );
      addTearDown(link.dispose);

      await off.load();
      await pumpEventQueue();

      expect(off.forecast, isNull);
      expect(host.weathers, [null]);
      expect(host.redraws, 1);
      // The events are left as they are.
      expect(host.saved, isEmpty);
    });

    test('turned on, it comes', () async {
      final host = _FakeHost();
      final off = weather(enabled: false);
      final link = CalendarWeatherLink(
        widget: CalendarWidget(host: host, enabled: true),
        weather: off,
        settings: AppSettings(persist: false),
      );
      addTearDown(link.dispose);
      await off.load();
      await off.enable();
      await off.refresh();
      await pumpEventQueue();

      expect(host.weathers.first, isNull);
      expect(host.weathers.last, jsonEncode(calendarWeather(off.forecast!)));
    });
  });
}
