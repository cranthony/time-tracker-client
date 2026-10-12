import 'dart:ui' show Color;

import '../models/google_calendar.dart';
import '../services/google_calendars.dart';

/// A phone with two Google accounts synced, for trying the app without
/// one: a personal account with a shared family calendar, birthdays and
/// holidays, and a work account. Each weekday has the same meetings, and
/// today a few things more, dated relative to [now].
class SampleGoogleCalendarSource implements GoogleCalendarSource {
  SampleGoogleCalendarSource(this.now);

  final DateTime now;

  static const _me = 'alex@gmail.com';
  static const _work = 'alex@acme.example';

  static const personal = GoogleCalendar(
    id: 'personal',
    account: _me,
    name: 'Alex',
    color: Color(0xFF039BE5),
    isPrimary: true,
  );
  static const family = GoogleCalendar(
    id: 'family',
    account: _me,
    name: 'Family',
    color: Color(0xFF33B679),
  );
  static const birthdays = GoogleCalendar(
    id: 'birthdays',
    account: _me,
    name: 'Birthdays',
    color: Color(0xFF8E24AA),
  );
  static const holidays = GoogleCalendar(
    id: 'holidays',
    account: _me,
    name: 'Holidays in United States',
    color: Color(0xFF0B8043),
  );
  static const work = GoogleCalendar(
    id: 'work',
    account: _work,
    name: 'Alex Rivera',
    color: Color(0xFFF4511E),
    isPrimary: true,
  );

  /// Allowed to start with: it's only a sample.
  var _permission = CalendarPermission.granted;

  @override
  Future<CalendarPermission> permission() async => _permission;

  @override
  Future<CalendarPermission> requestPermission() async =>
      _permission = CalendarPermission.granted;

  @override
  Future<bool> open(GoogleEvent event) async => false;

  @override
  Future<void> openSettings() async {}

  @override
  Future<List<GoogleCalendar>> calendars() async => const [
    personal,
    family,
    birthdays,
    holidays,
    work,
  ];

  @override
  Future<List<GoogleEvent>> events(
    DateTime from,
    DateTime to,
    List<GoogleCalendar> calendars,
  ) async {
    final calendarIds = {for (final c in calendars) c.id};
    final today = DateTime(now.year, now.month, now.day);
    final all = <GoogleEvent>[];
    for (
      var day = from;
      day.isBefore(to);
      day = day.add(const Duration(days: 1))
    ) {
      final d = DateTime(day.year, day.month, day.day);
      DateTime at(int h, [int m = 0]) => DateTime(d.year, d.month, d.day, h, m);
      final key = '${d.year}-${d.month}-${d.day}';
      if (d.weekday <= DateTime.friday) {
        all.addAll([
          GoogleEvent(
            id: 'standup-$key',
            calendar: work,
            title: 'Team standup',
            start: at(9, 30),
            end: at(9, 45),
            location: 'Google Meet',
            description:
                'Join with Google Meet: https://meet.google.com/abc-defg-hij\n'
                'Or dial: +1 555-0142 PIN: 314 159#',
          ),
          GoogleEvent(
            id: 'review-$key',
            calendar: work,
            title: 'Design review',
            start: at(10, 30),
            end: at(11, 30),
            location: 'Room 4B',
            description:
                '<b>Agenda</b><br><ol><li>Calendar view: <i>week</i> '
                'layout</li><li>Settings page polish</li><li>Open '
                'questions</li></ol>Mocks are in the '
                '<a href="https://example.com/design/mocks">design doc</a>. '
                '<u>Please read them first.</u>',
          ),
          GoogleEvent(
            id: 'focus-$key',
            calendar: work,
            title: 'Focus time',
            start: at(14),
            end: at(16),
          ),
        ]);
      }
      if (d == today) {
        all.addAll([
          GoogleEvent(
            id: 'trip',
            calendar: family,
            title: 'Jamie: school trip',
            start: d,
            end: d.add(const Duration(days: 1)),
            allDay: true,
          ),
          GoogleEvent(
            id: 'sam-bday',
            calendar: birthdays,
            title: "Sam's birthday",
            start: d,
            end: d.add(const Duration(days: 1)),
            allDay: true,
          ),
          GoogleEvent(
            id: 'lunch',
            calendar: personal,
            title: 'Lunch with Sam',
            start: at(12),
            end: at(13),
            location: 'The noodle bar',
          ),
          GoogleEvent(
            id: 'dentist',
            calendar: personal,
            title: 'Dentist',
            start: at(16, 30),
            end: at(17, 15),
            location: 'Bright Smile Dental',
            description:
                'Six-month cleaning.\n'
                'Bring the new insurance card.\n'
                'Reschedule: https://brightsmile.example/appointments',
          ),
          GoogleEvent(
            id: 'pickup',
            calendar: family,
            title: 'Pick up Jamie',
            start: at(17, 0),
            end: at(17, 30),
          ),
          GoogleEvent(
            id: 'call',
            calendar: family,
            title: 'Call Mom',
            start: at(17, 45),
            end: at(18, 15),
          ),
          GoogleEvent(
            id: 'book',
            calendar: personal,
            title: 'Book club',
            start: at(19),
            end: at(20),
            location: "Priya's place",
            description:
                '<p>This month: <b><i>The Left Hand of Darkness</i></b>, '
                'by Ursula K. Le Guin.</p>'
                '<p>Questions to think about:</p>'
                '<ul><li>How does Genly change over the book?</li>'
                '<li>What does the Gethenian calendar say about time?</li>'
                '<li>Is Estraven a tragic figure?</li>'
                '<li>Would the story work told by an insider?</li></ul>'
                '<p>Priya is making soup; bring bread or dessert. '
                'Sign-up sheet is '
                '<a href="https://example.com/bookclub/signup">here</a>.</p>'
                '<p><s>Starts at 7:30</s> Starts at 7 sharp.</p>',
          ),
        ]);
      }
    }
    // Days off at work, from yesterday to the day after tomorrow.
    final away = today.subtract(const Duration(days: 1));
    final back = today.add(const Duration(days: 3));
    if (away.isBefore(to) && back.isAfter(from)) {
      all.add(
        GoogleEvent(
          id: 'ooo',
          calendar: work,
          title: 'Out of office',
          description:
              'Away until Monday. For anything urgent, ask '
              '<a href="mailto:jordan@acme.example">Jordan</a>.',
          start: away,
          end: back,
          allDay: true,
        ),
      );
    }
    if (today.isBefore(to) && !today.isBefore(from)) {
      all.add(
        GoogleEvent(
          id: 'holiday',
          calendar: holidays,
          title: 'Sample Holiday',
          start: today,
          end: today.add(const Duration(days: 1)),
          allDay: true,
        ),
      );
    }
    return [
      for (final e in all)
        if (calendarIds.contains(e.calendar.id)) e,
    ];
  }
}
