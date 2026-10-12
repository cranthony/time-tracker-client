import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:time_tracker_client/models/google_calendar.dart';
import 'package:time_tracker_client/platform/google_calendar_source.dart';
import 'package:time_tracker_client/services/google_calendars.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('time_tracker/google_calendar');
  final calls = <MethodCall>[];
  Object? Function(MethodCall call) answer = (_) => null;
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  setUp(() {
    calls.clear();
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return answer(call);
    });
  });
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  const mine = GoogleCalendar(
    id: '7',
    account: 'me@gmail.com',
    name: 'Me',
    color: Color(0xFF039BE5),
    isPrimary: true,
  );

  test('says what Android says of the permission', () async {
    final source = AndroidGoogleCalendarSource();
    for (final (said, permission) in [
      ('granted', CalendarPermission.granted),
      ('denied', CalendarPermission.denied),
      ('blocked', CalendarPermission.blocked),
    ]) {
      answer = (_) => said;
      expect(await source.permission(), permission);
      expect(await source.requestPermission(), permission);
    }
  });

  test('reads the calendars, opaque', () async {
    answer = (_) => [
      {
        'id': '7',
        'account': 'me@gmail.com',
        'name': 'Me',
        'color': 0x00039BE5,
        'isPrimary': true,
      },
    ];
    final [calendar] = await AndroidGoogleCalendarSource().calendars();
    expect(calendar.id, '7');
    expect(calendar.name, 'Me');
    expect(calendar.color, const Color(0xFF039BE5));
    expect(calendar.isPrimary, isTrue);
  });

  test('reads events: a whole day on its own date here, its own color or '
      "its calendar's, and none outside the time asked for", () async {
    final day = DateTime(2026, 10, 2);
    answer = (call) => [
      {
        'id': '1@x',
        'eventId': '1',
        'calendarId': '7',
        'title': 'Standup',
        'begin': day.add(const Duration(hours: 9)).millisecondsSinceEpoch,
        'end': day.add(const Duration(hours: 10)).millisecondsSinceEpoch,
        'allDay': false,
        'location': '  Room 4B ',
        'description': '',
        'color': 0,
      },
      {
        'id': '2@x',
        'eventId': '2',
        'calendarId': '7',
        'title': "Sam's birthday",
        'begin': DateTime.utc(2026, 10, 2).millisecondsSinceEpoch,
        'end': DateTime.utc(2026, 10, 3).millisecondsSinceEpoch,
        'allDay': true,
        'color': 0xFF8E24AA,
      },
      {
        'id': '3@x',
        'eventId': '3',
        'calendarId': '7',
        'title': 'Tomorrow',
        'begin': DateTime.utc(2026, 10, 3).millisecondsSinceEpoch,
        'end': DateTime.utc(2026, 10, 4).millisecondsSinceEpoch,
        'allDay': true,
      },
      {
        'id': '4@x',
        'calendarId': '99',
        'title': 'Not asked for',
        'begin': day.millisecondsSinceEpoch,
        'end': day.add(const Duration(hours: 1)).millisecondsSinceEpoch,
      },
    ];
    final events = await AndroidGoogleCalendarSource().events(
      day,
      day.add(const Duration(days: 1)),
      const [mine],
    );
    expect(calls.single.arguments['calendarIds'], ['7']);
    expect([for (final e in events) e.title], ['Standup', "Sam's birthday"]);
    final [standup, birthday] = events;
    expect(standup.location, 'Room 4B');
    expect(standup.description, isNull);
    expect(standup.color, mine.color);
    expect(standup.sourceId, '1');
    expect(birthday.allDay, isTrue);
    expect(birthday.start, day);
    expect(birthday.end, DateTime(2026, 10, 3));
    expect(birthday.color, const Color(0xFF8E24AA));
  });

  test(
    "opens an event in the calendar app at its occurrence's times",
    () async {
      answer = (_) => true;
      final start = DateTime(2026, 10, 2, 9);
      final opened = await AndroidGoogleCalendarSource().open(
        GoogleEvent(
          id: '1@x',
          calendar: mine,
          title: 'Standup',
          start: start,
          end: start.add(const Duration(hours: 1)),
          sourceId: '1',
        ),
      );
      expect(opened, isTrue);
      expect(calls.single.method, 'openEvent');
      expect(calls.single.arguments, {
        'id': '1',
        'begin': start.millisecondsSinceEpoch,
        'end': start.add(const Duration(hours: 1)).millisecondsSinceEpoch,
      });
    },
  );
}
