import 'dart:ui' show Color;

/// One of the user's Google calendars, as the phone has it synced: read
/// from Android's calendar provider, never from the server.
class GoogleCalendar {
  const GoogleCalendar({
    required this.id,
    required this.account,
    required this.name,
    required this.color,
    this.isPrimary = false,
  });

  final String id;

  /// The Google account it's synced from.
  final String account;
  final String name;
  final Color color;

  /// Whether it's [account]'s own calendar, rather than one it subscribes
  /// to or is shared.
  final bool isPrimary;
}

/// An event in a [GoogleCalendar]: shown for reference, never edited, and
/// never sent to the server. Each occurrence of a repeating one is its own.
class GoogleEvent {
  const GoogleEvent({
    required this.id,
    required this.calendar,
    required this.title,
    required this.start,
    required this.end,
    this.allDay = false,
    this.location,
    this.description,
  });

  final String id;
  final GoogleCalendar calendar;
  final String title;
  final DateTime start;
  final DateTime end;

  /// Whether it's for whole days, from [start]'s to [end]'s midnight.
  final bool allDay;
  final String? location;

  /// What it says about itself: HTML, if it was written on Google
  /// Calendar's website; plain text otherwise.
  final String? description;
}
