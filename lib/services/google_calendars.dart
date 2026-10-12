import 'package:flutter/widgets.dart';

import '../models/google_calendar.dart';

/// Where the phone's Google calendars come from: on Android, its calendar
/// provider, which needs the calendar permission.
abstract class GoogleCalendarSource {
  /// Whether the app may read the calendars.
  Future<bool> hasPermission();

  /// Asks the user to let the app read them; whether they did.
  Future<bool> requestPermission();

  /// Every Google calendar synced to the phone.
  Future<List<GoogleCalendar>> calendars();

  /// The events in [calendarIds] that overlap [from] to [to].
  Future<List<GoogleEvent>> events(
    DateTime from,
    DateTime to,
    Set<String> calendarIds,
  );
}

/// Whether Google Calendar events are shown, from which calendars, and
/// each day's, once loaded. Kept on this device only.
class GoogleCalendars extends ChangeNotifier {
  GoogleCalendars({
    required this.source,
    bool enabled = false,
    Set<String>? selected,
  }) : _enabled = enabled,
       // ignore: prefer_initializing_formals
       _selected = selected;

  final GoogleCalendarSource source;

  bool _enabled;

  /// Whether they're shown: on only once the user's let the app read
  /// them.
  bool get enabled => _enabled;

  List<GoogleCalendar> _calendars = const [];

  /// The calendars to pick from, once loaded.
  List<GoogleCalendar> get calendars => _calendars;

  Set<String>? _selected;

  /// The ids of the calendars shown: at first, each account's own.
  Set<String> get selected =>
      _selected ??
      {
        for (final c in _calendars)
          if (c.isPrimary) c.id,
      };

  final _days = <DateTime, List<GoogleEvent>>{};
  final _loading = <DateTime>{};

  /// Turns them on, asking for the permission if need be; whether they're
  /// on.
  Future<bool> enable() async {
    if (!await source.hasPermission() && !await source.requestPermission()) {
      return false;
    }
    _enabled = true;
    await _loadCalendars();
    return true;
  }

  void disable() {
    _enabled = false;
    _days.clear();
    notifyListeners();
  }

  void select(String id, bool shown) {
    _selected = {...selected}
      ..remove(id)
      ..addAll([if (shown) id]);
    _days.clear();
    notifyListeners();
  }

  Future<void> _loadCalendars() async {
    _calendars = await source.calendars();
    notifyListeners();
  }

  /// The events on [day] (midnight), or none till they're loaded: they're
  /// loaded then, and listeners told.
  List<GoogleEvent> on(DateTime day) {
    if (!_enabled) return const [];
    if (_days[day] case final events?) return events;
    if (_loading.add(day)) {
      if (_calendars.isEmpty) _loadCalendars();
      final end = DateTime(day.year, day.month, day.day + 1);
      source
          .events(day, end, selected)
          .then(
            (events) {
              _loading.remove(day);
              _days[day] = events;
              notifyListeners();
            },
            onError: (_) {
              _loading.remove(day);
            },
          );
    }
    return const [];
  }

  /// The nearest [GoogleCalendarsScope]'s, or null where there's none:
  /// not on this platform.
  static GoogleCalendars? of(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<GoogleCalendarsScope>()
      ?.notifier;
}

/// Gives the [GoogleCalendars] to everything below it.
class GoogleCalendarsScope extends InheritedNotifier<GoogleCalendars> {
  const GoogleCalendarsScope({
    super.key,
    required GoogleCalendars calendars,
    required super.child,
  }) : super(notifier: calendars);
}
