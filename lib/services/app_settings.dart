import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/schedule_hints.dart';
import '../widgets/cursor_modes.dart';
import '../widgets/cursor_snap.dart';

/// The app's settings, kept on this device only: the [grid] a cursor on
/// the timeline snaps to, what else cursors stop at ([snap]), what a new
/// event does with the events in its way ([endMode]), and when background
/// fetches run ([refreshDelay], [retryInterval], [expectsProposal]).
/// Listeners hear every change.
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

  /// What a cursor stops at, besides the grid, until it's changed.
  static const defaultSnap = {SnapTo.events, SnapTo.notes};

  Set<SnapTo> _snap = defaultSnap;

  static const _endModeKey = 'settings_end_mode';
  EndMode _endMode = EndMode.trim;

  /// What a new event's end does with the events the box reaches, as last
  /// picked.
  EndMode get endMode => _endMode;

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
      if (await prefs.getStringList(_expectingKey) case final keys?) {
        _expecting = {...keys};
      }
      _endMode =
          EndMode.values.asNameMap()[await prefs.getString(_endModeKey)] ??
          _endMode;
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
