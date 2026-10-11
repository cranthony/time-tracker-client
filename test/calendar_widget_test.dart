import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:time_tracker_client/models/event.dart';
import 'package:time_tracker_client/models/note.dart';
import 'package:time_tracker_client/models/plan_action.dart';
import 'package:time_tracker_client/platform/calendar_widget.dart';
import 'package:time_tracker_client/services/event_store.dart';
import 'package:time_tracker_client/services/events_repository.dart';

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

  @override
  Future<void> schedule(List<DateTime> times) async => scheduled.add(times);

  @override
  Future<void> redraw() async => redraws++;
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
}
