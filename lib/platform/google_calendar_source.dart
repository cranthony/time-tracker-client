import 'package:flutter/services.dart';

import '../models/google_calendar.dart';
import '../services/google_calendars.dart';

/// The phone's Google calendars, from Android's calendar provider by way
/// of MainActivity's GoogleCalendarReader: what the Google Calendar app
/// syncs, read on the phone and never sent to the server.
class AndroidGoogleCalendarSource implements GoogleCalendarSource {
  AndroidGoogleCalendarSource({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel('time_tracker/google_calendar');

  final MethodChannel _channel;

  static CalendarPermission _permission(Object? answer) => switch (answer) {
    'granted' => CalendarPermission.granted,
    'blocked' => CalendarPermission.blocked,
    _ => CalendarPermission.denied,
  };

  @override
  Future<CalendarPermission> permission() async =>
      _permission(await _channel.invokeMethod<String>('permission'));

  @override
  Future<CalendarPermission> requestPermission() async =>
      _permission(await _channel.invokeMethod<String>('requestPermission'));

  @override
  Future<List<GoogleCalendar>> calendars() async => [
    for (final c in await _channel.invokeListMethod<Map>('calendars') ?? [])
      GoogleCalendar(
        id: '${c['id']}',
        account: '${c['account'] ?? ''}',
        name: '${c['name'] ?? c['account'] ?? ''}',
        color: Color((c['color'] as int? ?? 0xFF039BE5) | 0xFF000000),
        isPrimary: c['isPrimary'] == true,
      ),
  ];

  @override
  Future<List<GoogleEvent>> events(
    DateTime from,
    DateTime to,
    List<GoogleCalendar> calendars,
  ) async {
    if (calendars.isEmpty) return const [];
    final byId = {for (final c in calendars) c.id: c};
    // A day either side: whole-day events are kept as midnights in UTC,
    // which may be a day off from the local ones asked for.
    final rows = await _channel.invokeListMethod<Map>('events', {
      'from': from.subtract(const Duration(days: 1)).millisecondsSinceEpoch,
      'to': to.add(const Duration(days: 1)).millisecondsSinceEpoch,
      'calendarIds': [...byId.keys],
    });
    return [
      for (final row in rows ?? const <Map>[])
        if (eventOf(row, byId) case final event?
            when event.start.isBefore(to) && event.end.isAfter(from))
          event,
    ];
  }

  /// [row], as GoogleCalendarReader sends it, as an event in one of
  /// [calendars]; null if it's not in one of them.
  static GoogleEvent? eventOf(Map row, Map<String, GoogleCalendar> calendars) {
    final calendar = calendars['${row['calendarId']}'];
    if (calendar == null) return null;
    final allDay = row['allDay'] == true;
    DateTime at(Object? ms) {
      final t = DateTime.fromMillisecondsSinceEpoch(
        (ms as num?)?.toInt() ?? 0,
        isUtc: allDay,
      );
      // A whole day's begin and end are midnights in UTC: the same dates'
      // midnights here.
      return allDay ? DateTime(t.year, t.month, t.day) : t;
    }

    final start = at(row['begin']);
    var end = at(row['end']);
    if (!end.isAfter(start)) {
      end = allDay
          ? DateTime(start.year, start.month, start.day + 1)
          : start.add(const Duration(minutes: 1));
    }
    String? text(Object? value) => switch (value) {
      final String s when s.trim().isNotEmpty => s,
      _ => null,
    };
    final color = row['color'] as int?;
    return GoogleEvent(
      id: '${row['id']}',
      calendar: calendar,
      title: text(row['title']) ?? '(No title)',
      start: start,
      end: end,
      allDay: allDay,
      location: text(row['location'])?.trim(),
      description: text(row['description']),
      color: color == null || color == 0 ? null : Color(color | 0xFF000000),
      sourceId: row['eventId'] == null ? null : '${row['eventId']}',
    );
  }

  @override
  Future<bool> open(GoogleEvent event) async {
    if (event.sourceId == null) return false;
    return await _channel.invokeMethod<bool>('openEvent', {
          'id': event.sourceId,
          // A whole day's, as the calendar app keeps it: midnight in UTC.
          'begin': event.allDay
              ? DateTime.utc(
                  event.start.year,
                  event.start.month,
                  event.start.day,
                ).millisecondsSinceEpoch
              : event.start.millisecondsSinceEpoch,
          'end': event.allDay
              ? DateTime.utc(
                  event.end.year,
                  event.end.month,
                  event.end.day,
                ).millisecondsSinceEpoch
              : event.end.millisecondsSinceEpoch,
        }) ??
        false;
  }

  @override
  Future<void> openSettings() => _channel.invokeMethod('openSettings');
}
