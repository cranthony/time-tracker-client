import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/google_calendar.dart';

/// Whether the app may read the phone's calendars: [blocked] is denied
/// for good, so only the app's settings can allow it now.
enum CalendarPermission { granted, denied, blocked }

/// Where the phone's Google calendars come from: on Android, its calendar
/// provider, which needs the calendar permission.
abstract class GoogleCalendarSource {
  Future<CalendarPermission> permission();

  /// Asks the user to let the app read them; what they said.
  Future<CalendarPermission> requestPermission();

  /// Every Google calendar synced to the phone.
  Future<List<GoogleCalendar>> calendars();

  /// The events in [calendars] that overlap [from] to [to].
  Future<List<GoogleEvent>> events(
    DateTime from,
    DateTime to,
    List<GoogleCalendar> calendars,
  );

  /// Opens [event] in the calendar app; whether it did.
  Future<bool> open(GoogleEvent event);

  /// Opens the app's settings, to allow it there.
  Future<void> openSettings();
}

/// Whether Google Calendar events are shown, from which calendars, and
/// each day's, once loaded. Kept on this device only ([persist]): the
/// server never sees them.
class GoogleCalendars extends ChangeNotifier {
  GoogleCalendars({
    required this.source,
    this.persist = true,
    this._enabled = false,
    this._selected,
  });

  final GoogleCalendarSource source;
  final bool persist;

  static const _enabledKey = 'google_calendar_enabled';
  static const _selectedKey = 'google_calendar_selected';

  bool _enabled;

  /// Whether they're shown: only while the app may read them.
  bool get enabled => _enabled;

  CalendarPermission? _permission;

  /// What the user last said to letting the app read them, once asked.
  CalendarPermission? get permission => _permission;

  List<GoogleCalendar> _calendars = const [];

  /// The calendars to pick from, once loaded.
  List<GoogleCalendar> get calendars => _calendars;

  Set<String>? _selected;

  /// The ids of the calendars shown: until some are picked, each
  /// account's own.
  Set<String> get selected =>
      _selected ??
      {
        for (final c in _calendars)
          if (c.isPrimary) c.id,
      };

  final _days = <DateTime, List<GoogleEvent>>{};
  final _loading = <DateTime>{};

  /// The days loaded before a [refresh], to load again.
  final _stale = <DateTime>{};
  Future<void>? _calendarsLoading;

  /// Bumped whenever what's loaded is thrown away, so a load begun
  /// before is dropped as it comes.
  var _generation = 0;

  /// Reads what's kept on the device, and whether the app may still read
  /// the calendars: if not, they're off. Best effort.
  Future<void> load() async {
    if (persist) {
      try {
        final prefs = SharedPreferencesAsync();
        _enabled = await prefs.getBool(_enabledKey) ?? _enabled;
        if (await prefs.getStringList(_selectedKey) case final ids?) {
          _selected = {...ids};
        }
      } catch (_) {
        // Nothing kept: as it was.
      }
    }
    if (_enabled) {
      try {
        _permission = await source.permission();
      } catch (_) {
        _permission = CalendarPermission.denied;
      }
      if (_permission != CalendarPermission.granted) _enabled = false;
    }
    notifyListeners();
  }

  /// Turns them on, asking for the permission if need be; whether they're
  /// on. Refused, [permission] says how.
  Future<bool> enable() async {
    var permission = await source.permission();
    if (permission != CalendarPermission.granted) {
      permission = await source.requestPermission();
    }
    _permission = permission;
    if (permission != CalendarPermission.granted) {
      notifyListeners();
      return false;
    }
    _enabled = true;
    _forget();
    _keep();
    await _loadCalendars();
    return true;
  }

  void disable() {
    _enabled = false;
    _forget();
    _keep();
    notifyListeners();
  }

  void select(String id, bool shown) {
    _selected = {...selected}
      ..remove(id)
      ..addAll([if (shown) id]);
    _forget();
    _keep();
    notifyListeners();
  }

  /// Loads each day again as it's next asked for -- the calendars may
  /// have changed -- showing what it had till then.
  void refresh() {
    if (!_enabled) return;
    _generation++;
    _loading.clear();
    _stale.addAll(_days.keys);
    _calendarsLoading = null;
    notifyListeners();
  }

  void _forget() {
    _generation++;
    _days.clear();
    _loading.clear();
    _stale.clear();
  }

  void _keep() {
    if (!persist) return;
    try {
      final prefs = SharedPreferencesAsync();
      prefs.setBool(_enabledKey, _enabled).catchError((_) {});
      if (_selected case final ids?) {
        prefs.setStringList(_selectedKey, [...ids]).catchError((_) {});
      }
    } catch (_) {
      // Nowhere to keep it: it lasts until the app closes.
    }
  }

  var _loaded = false;

  /// Whether [calendars] have been read from the phone yet.
  bool get loaded => _loaded;

  /// Reads the calendars to pick from, if they haven't been yet.
  Future<void> loadCalendars() => _enabled ? _loadCalendars() : Future.value();

  Future<void> _loadCalendars() => _calendarsLoading ??= () async {
    try {
      _calendars = await source.calendars();
      _loaded = true;
    } catch (_) {
      // No longer allowed, most likely: off, until turned on again.
      await _lost();
      return;
    }
    notifyListeners();
  }();

  /// Checks the app may still read them, after a read failed: if not,
  /// they're off.
  Future<void> _lost() async {
    try {
      _permission = await source.permission();
    } catch (_) {
      _permission = CalendarPermission.denied;
    }
    if (_permission != CalendarPermission.granted && _enabled) {
      _enabled = false;
      _forget();
      _keep();
    }
    notifyListeners();
  }

  /// The events on [day] (midnight), or none till they're loaded: they're
  /// loaded then, and listeners told.
  List<GoogleEvent> on(DateTime day) {
    if (!_enabled) return const [];
    final had = _days[day];
    if ((had == null || _stale.remove(day)) && _loading.add(day)) {
      _loadDay(day);
    }
    return had ?? const [];
  }

  Future<void> _loadDay(DateTime day) async {
    final generation = _generation;
    // Which are shown can't be told till the calendars are in.
    await _loadCalendars();
    if (generation != _generation) return;
    final shown = selected;
    final end = DateTime(day.year, day.month, day.day + 1);
    try {
      final events = await source.events(day, end, [
        for (final c in _calendars)
          if (shown.contains(c.id)) c,
      ]);
      if (generation != _generation) return;
      _loading.remove(day);
      _stale.remove(day);
      _days[day] = [
        for (final e in events)
          if (e.start.isBefore(end) && e.end.isAfter(day)) e,
      ];
      notifyListeners();
    } catch (_) {
      if (generation != _generation) return;
      _loading.remove(day);
      // None, till they're refreshed: not asked for again at every
      // rebuild.
      _days[day] = const [];
      await _lost();
    }
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
