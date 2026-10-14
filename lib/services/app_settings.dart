import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'keep_rules.dart';

import '../models/schedule_hints.dart';
import '../models/weather.dart';
import '../widgets/cursor_modes.dart';
import '../widgets/cursor_snap.dart';

/// The app's settings, kept on this device only: the [grid] a cursor on
/// the timeline snaps to, what else cursors stop at ([snap]), what a new
/// event does with the events in its way ([endMode]), and when background
/// fetches run ([refreshDelay], [retryInterval], [expectsProposal]), and
/// the units the weather's shown in ([temperatureUnit],
/// [precipitationUnit]). Listeners hear every change.
class AppSettings extends ChangeNotifier {
  /// Kept on the device with [persist]; otherwise only while the app
  /// runs. Starts with [grid], until what's kept is [load]ed.
  AppSettings({this.persist = true, this._grid = defaultGrid});

  /// The grids to pick from; null is none.
  static const grids = <Duration?>[
    null,
    Duration(minutes: 5),
    Duration(minutes: 10),
    Duration(minutes: 15),
    Duration(minutes: 30),
    Duration(minutes: 60),
  ];

  static const defaultGrid = Duration(minutes: 15);
  static const _gridKey = 'settings_grid_minutes';
  static const _snapKey = 'settings_snap';
  static const _keepRulesKey = 'settings_keep_rules';

  List<KeepRule> _keepRules = KeepRule.defaults;

  /// What goes in a new or moved event's Keep list as its box starts.
  List<KeepRule> get keepRules => List.unmodifiable(_keepRules);

  /// Sets the rules, and keeps them.
  Future<void> setKeepRules(List<KeepRule> rules) async {
    _keepRules = [...rules];
    notifyListeners();
    if (!persist) return;
    try {
      await SharedPreferencesAsync().setString(
        _keepRulesKey,
        jsonEncode([for (final r in rules) r.toJson()]),
      );
    } catch (_) {
      // Kept while the app runs, then.
    }
  }

  /// What a cursor stops at, besides the grid, until it's changed.
  static const defaultSnap = {SnapTo.events, SnapTo.notes};

  Set<SnapTo> _snap = defaultSnap;

  static const _endModeKey = 'settings_end_mode';
  EndMode _endMode = EndMode.trim;

  /// What a new event's end does with the events the box reaches, as last
  /// picked.
  EndMode get endMode => _endMode;

  static const _temperatureUnitKey = 'settings_temperature_unit';
  static const _precipitationUnitKey = 'settings_precipitation_unit';
  TemperatureUnit _temperatureUnit = TemperatureUnit.fahrenheit;
  PrecipitationUnit _precipitationUnit = PrecipitationUnit.inches;

  /// What the weather's temperatures are shown in.
  TemperatureUnit get temperatureUnit => _temperatureUnit;

  /// What the weather's rain and snow are measured in.
  PrecipitationUnit get precipitationUnit => _precipitationUnit;

  /// Sets the [temperatureUnit], and keeps it.
  Future<void> setTemperatureUnit(TemperatureUnit unit) =>
      _setString(_temperatureUnitKey, unit.name, () => _temperatureUnit = unit);

  /// Sets the [precipitationUnit], and keeps it.
  Future<void> setPrecipitationUnit(PrecipitationUnit unit) => _setString(
    _precipitationUnitKey,
    unit.name,
    () => _precipitationUnit = unit,
  );

  /// The delays to pick from, after a routine's time, for the background
  /// fetch.
  static const refreshDelays = <Duration>[
    Duration(minutes: 5),
    Duration(minutes: 10),
    Duration(minutes: 15),
    Duration(minutes: 20),
    Duration(minutes: 30),
    Duration(minutes: 45),
    Duration(minutes: 60),
  ];

  /// How often to fetch again, to pick from, while a compaction's
  /// proposal hasn't come; null is not to.
  static const retryIntervals = <Duration?>[
    null,
    Duration(minutes: 15),
    Duration(minutes: 20),
    Duration(minutes: 30),
    Duration(minutes: 60),
  ];

  /// How often to fetch the weather in the background, to pick from;
  /// null is not to.
  static const weatherRefreshIntervals = <Duration?>[
    null,
    Duration(minutes: 30),
    Duration(hours: 1),
    Duration(hours: 2),
    Duration(hours: 3),
    Duration(hours: 6),
  ];

  static const defaultWeatherRefresh = Duration(hours: 1);
  static const _weatherRefreshKey = 'settings_weather_refresh_minutes';
  Duration? _weatherRefresh = defaultWeatherRefresh;

  /// How often the weather's fetched in the background, while it's on;
  /// null for only while the app's open.
  Duration? get weatherRefresh => _weatherRefresh;

  /// Sets the [weatherRefresh], and keeps it.
  Future<void> setWeatherRefresh(Duration? every) => _setInt(
    _weatherRefreshKey,
    every?.inMinutes ?? 0,
    () => _weatherRefresh = every,
  );

  static const defaultRefreshDelay = Duration(minutes: 10);
  static const defaultRetryInterval = Duration(minutes: 15);
  static const _refreshDelayKey = 'settings_refresh_delay_minutes';
  static const _retryIntervalKey = 'settings_retry_interval_minutes';
  Duration _refreshDelay = defaultRefreshDelay;
  Duration? _retryInterval = defaultRetryInterval;

  static const _expectingKey = 'settings_hints_expecting_proposal';
  var _expecting = <String>{};

  /// Whether a proposal's to be expected after [hint]'s routine runs --
  /// the user says so, of each -- for the background fetch to check again
  /// until it comes. A routine's known by its [ScheduleHint.key].
  bool expectsProposal(ScheduleHint hint) => _expecting.contains(hint.key);

  /// Sets whether a proposal's to be expected after [hint], and keeps it.
  Future<void> setExpectsProposal(ScheduleHint hint, bool expects) async {
    _expecting = {..._expecting}
      ..remove(hint.key)
      ..addAll([if (expects) hint.key]);
    notifyListeners();
    if (!persist) return;
    try {
      await SharedPreferencesAsync().setStringList(_expectingKey, [
        ..._expecting,
      ]);
    } catch (_) {
      // Kept while the app runs, then.
    }
  }

  /// How long after a routine's time the background fetch runs: the
  /// routine takes a while.
  Duration get refreshDelay => _refreshDelay;

  /// How often the background fetch runs again while a compaction's
  /// proposal is expected and hasn't come; null for not until the next
  /// it would anyway.
  Duration? get retryInterval => _retryInterval;

  final bool persist;
  Duration? _grid;
  Future<void>? _loading;

  /// The times a cursor snaps to, every so many minutes from midnight;
  /// null for none -- a cursor stops at any minute.
  Duration? get grid => _grid;

  /// Reads what's kept on the device, once. Best effort.
  Future<void> load() => _loading ??= () async {
    if (!persist) return;
    try {
      final prefs = SharedPreferencesAsync();
      final minutes = await prefs.getInt(_gridKey);
      if (minutes != null) {
        _grid = minutes <= 0 ? null : Duration(minutes: minutes);
      }
      if (await prefs.getInt(_refreshDelayKey) case final m? when m > 0) {
        _refreshDelay = Duration(minutes: m);
      }
      if (await prefs.getInt(_retryIntervalKey) case final m?) {
        _retryInterval = m <= 0 ? null : Duration(minutes: m);
      }
      if (await prefs.getInt(_weatherRefreshKey) case final m?) {
        _weatherRefresh = m <= 0 ? null : Duration(minutes: m);
      }
      if (await prefs.getStringList(_expectingKey) case final keys?) {
        _expecting = {...keys};
      }
      _endMode =
          EndMode.values.asNameMap()[await prefs.getString(_endModeKey)] ??
          _endMode;
      _temperatureUnit =
          TemperatureUnit.values.asNameMap()[await prefs.getString(
            _temperatureUnitKey,
          )] ??
          _temperatureUnit;
      _precipitationUnit =
          PrecipitationUnit.values.asNameMap()[await prefs.getString(
            _precipitationUnitKey,
          )] ??
          _precipitationUnit;
      if (await prefs.getString(_keepRulesKey) case final json?) {
        _keepRules = [
          for (final r in jsonDecode(json) as List) ?KeepRule.fromJson(r),
        ];
      }
      if (await prefs.getStringList(_snapKey) case final names?) {
        _snap = {
          for (final snap in SnapTo.values)
            if (names.contains(snap.name)) snap,
        };
      }
      notifyListeners();
    } catch (_) {
      // Nowhere to keep it: the default, then.
    }
  }();

  /// Sets the [grid], and keeps it.
  Future<void> setGrid(Duration? grid) async {
    if (grid == _grid) return;
    _grid = grid;
    notifyListeners();
    if (!persist) return;
    try {
      await SharedPreferencesAsync().setInt(_gridKey, grid?.inMinutes ?? 0);
    } catch (_) {
      // Kept while the app runs, then.
    }
  }

  /// Sets the [refreshDelay], and keeps it.
  Future<void> setRefreshDelay(Duration delay) =>
      _setInt(_refreshDelayKey, delay.inMinutes, () => _refreshDelay = delay);

  /// Sets the [retryInterval], and keeps it.
  Future<void> setRetryInterval(Duration? interval) => _setInt(
    _retryIntervalKey,
    interval?.inMinutes ?? 0,
    () => _retryInterval = interval,
  );

  Future<void> _setInt(String key, int value, VoidCallback set) async {
    set();
    notifyListeners();
    if (!persist) return;
    try {
      await SharedPreferencesAsync().setInt(key, value);
    } catch (_) {
      // Kept while the app runs, then.
    }
  }

  /// Sets what a new event's end does, and keeps it.
  Future<void> setEndMode(EndMode mode) =>
      _setString(_endModeKey, mode.name, () => _endMode = mode);

  Future<void> _setString(String key, String value, VoidCallback set) async {
    set();
    notifyListeners();
    if (!persist) return;
    try {
      await SharedPreferencesAsync().setString(key, value);
    } catch (_) {
      // Kept while the app runs, then.
    }
  }

  /// What every cursor stops at, besides the grid's lines.
  Set<SnapTo> get snap => _snap;

  /// What [role]'s cursor stops at: as every cursor does ([snap]).
  Set<SnapTo> snapFor(CursorRole role) => _snap;

  /// Sets what every cursor stops at, and keeps it.
  Future<void> setSnap(Set<SnapTo> snap) async {
    _snap = {...snap};
    notifyListeners();
    if (!persist) return;
    try {
      await SharedPreferencesAsync().setStringList(_snapKey, [
        for (final s in snap) s.name,
      ]);
    } catch (_) {
      // Kept while the app runs, then.
    }
  }

  /// The nearest [AppSettingsScope]'s settings, or the defaults if there's
  /// none.
  static AppSettings of(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<AppSettingsScope>()
          ?.notifier ??
      _defaults;

  static final _defaults = AppSettings(persist: false);
}

/// Gives the [AppSettings] to everything below it, rebuilding what reads
/// them ([AppSettings.of]) as they change.
class AppSettingsScope extends InheritedNotifier<AppSettings> {
  const AppSettingsScope({
    super.key,
    required AppSettings settings,
    required super.child,
  }) : super(notifier: settings);
}

/// [time] on the nearest line of [grid], counted from its midnight; to
/// the minute with none.
DateTime snapToGrid(DateTime time, Duration? grid) {
  final step = grid == null || grid.inMinutes <= 0 ? 1 : grid.inMinutes;
  final minutes = time.hour * 60 + time.minute + (time.second >= 30 ? 1 : 0);
  final lines = (minutes / step).round();
  return DateTime(time.year, time.month, time.day, 0, lines * step);
}
