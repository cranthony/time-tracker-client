import 'dart:async';
import 'dart:ui' show Color;

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:time_tracker_client/models/google_calendar.dart';
import 'package:time_tracker_client/services/google_calendars.dart';

const _mine = GoogleCalendar(
  id: '1',
  account: 'me@gmail.com',
  name: 'Me',
  color: Color(0xFF039BE5),
  isPrimary: true,
);
const _family = GoogleCalendar(
  id: '2',
  account: 'me@gmail.com',
  name: 'Family',
  color: Color(0xFF33B679),
);

/// A phone's calendars, as a test has them: [answer] to the permission,
/// and each day's events, by calendar, as [events] has them.
class _Source implements GoogleCalendarSource {
  CalendarPermission granted = CalendarPermission.granted;
  CalendarPermission answer = CalendarPermission.granted;
  var asked = 0;
  var reads = 0;
  bool fail = false;
  List<GoogleEvent> kept = [];
  Completer<void>? gate;

  @override
  Future<CalendarPermission> permission() async => granted;

  @override
  Future<CalendarPermission> requestPermission() async {
    asked++;
    return granted = answer;
  }

  @override
  Future<List<GoogleCalendar>> calendars() async {
    if (fail) throw StateError('not allowed');
    return const [_mine, _family];
  }

  @override
  Future<List<GoogleEvent>> events(
    DateTime from,
    DateTime to,
    List<GoogleCalendar> calendars,
  ) async {
    reads++;
    await gate?.future;
    if (fail) throw StateError('not allowed');
    final ids = {for (final c in calendars) c.id};
    return [
      for (final e in kept)
        if (ids.contains(e.calendar.id)) e,
    ];
  }

  @override
  Future<bool> open(GoogleEvent event) async => true;

  @override
  Future<void> openSettings() async {}
}

final _day = DateTime(2026, 10, 2);

GoogleEvent _event(String id, GoogleCalendar calendar, int hour) => GoogleEvent(
  id: id,
  calendar: calendar,
  title: id,
  start: _day.add(Duration(hours: hour)),
  end: _day.add(Duration(hours: hour + 1)),
);

void main() {
  setUp(
    () => SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty(),
  );

  test('turned on, it asks for the permission, then shows each '
      "account's own calendar to start with", () async {
    final source = _Source()
      ..granted = CalendarPermission.denied
      ..kept = [_event('standup', _mine, 9), _event('pickup', _family, 17)];
    final calendars = GoogleCalendars(source: source, persist: false);
    expect(await calendars.enable(), isTrue);
    expect(source.asked, 1);
    expect(calendars.enabled, isTrue);
    expect(calendars.selected, {'1'});

    expect(calendars.on(_day), isEmpty);
    await pumpEventQueue();
    expect([for (final e in calendars.on(_day)) e.id], ['standup']);

    calendars.select('2', true);
    calendars.on(_day);
    await pumpEventQueue();
    expect([for (final e in calendars.on(_day)) e.id], ['standup', 'pickup']);
  });

  test('refused, it stays off and says how', () async {
    final source = _Source()
      ..granted = CalendarPermission.denied
      ..answer = CalendarPermission.blocked;
    final calendars = GoogleCalendars(source: source, persist: false);
    expect(await calendars.enable(), isFalse);
    expect(calendars.enabled, isFalse);
    expect(calendars.permission, CalendarPermission.blocked);
    expect(calendars.on(_day), isEmpty);
  });

  test('what it shows is kept, and it comes back off if the permission '
      'was taken away', () async {
    final source = _Source();
    final first = GoogleCalendars(source: source);
    await first.enable();
    first.select('2', true);
    await pumpEventQueue();

    final again = GoogleCalendars(source: source);
    await again.load();
    expect(again.enabled, isTrue);
    expect(again.selected, {'1', '2'});

    source.granted = CalendarPermission.denied;
    final revoked = GoogleCalendars(source: source);
    await revoked.load();
    expect(revoked.enabled, isFalse);
  });

  test('a refresh loads a day again, showing what it had meanwhile', () async {
    final source = _Source()..kept = [_event('standup', _mine, 9)];
    final calendars = GoogleCalendars(
      source: source,
      persist: false,
      enabled: true,
    );
    calendars.on(_day);
    await pumpEventQueue();
    expect(source.reads, 1);

    source.kept = [_event('standup', _mine, 9), _event('review', _mine, 10)];
    source.gate = Completer();
    calendars.refresh();
    expect([for (final e in calendars.on(_day)) e.id], ['standup']);
    source.gate!.complete();
    await pumpEventQueue();
    expect(source.reads, 2);
    expect([for (final e in calendars.on(_day)) e.id], ['standup', 'review']);
  });

  test("a read that fails because it's no longer allowed turns it off, "
      'without asking again at every rebuild', () async {
    final source = _Source();
    final calendars = GoogleCalendars(
      source: source,
      persist: false,
      enabled: true,
    );
    calendars.on(_day);
    await pumpEventQueue();
    source
      ..fail = true
      ..granted = CalendarPermission.denied;
    calendars.refresh();
    calendars.on(_day);
    await pumpEventQueue();
    expect(calendars.enabled, isFalse);
    expect(calendars.on(_day), isEmpty);
  });

  test(
    'a failed read for another reason is not retried until a refresh',
    () async {
      final source = _Source()..fail = true;
      final calendars = GoogleCalendars(
        source: source,
        persist: false,
        enabled: true,
      );
      calendars.on(_day);
      await pumpEventQueue();
      // Still allowed: still on, but with nothing to show.
      expect(calendars.enabled, isTrue);
      final reads = source.reads;
      calendars.on(_day);
      calendars.on(_day);
      await pumpEventQueue();
      expect(source.reads, reads);
    },
  );
}
