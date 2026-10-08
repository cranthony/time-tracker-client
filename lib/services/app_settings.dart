import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../widgets/cursor_snap.dart';

/// The app's settings, kept on this device only: the [grid] a cursor on
/// the timeline snaps to, and what else each cursor stops at
/// ([snapFor]). Listeners hear every change.
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
  static String _snapKey(CursorRole role) => 'settings_snap_${role.key}';

  /// What a cursor stops at, besides the grid, until it's changed.
  static const defaultSnap = {SnapTo.events, SnapTo.notes};

  final _snaps = <CursorRole, Set<SnapTo>>{};

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
      for (final role in CursorRole.values) {
        final names = await prefs.getStringList(_snapKey(role));
        if (names == null) continue;
        _snaps[role] = {
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

  /// What [role]'s cursor stops at, besides the grid's lines.
  Set<SnapTo> snapFor(CursorRole role) => _snaps[role] ?? defaultSnap;

  /// Sets what [role]'s cursor stops at, and keeps it.
  Future<void> setSnap(CursorRole role, Set<SnapTo> snap) async {
    _snaps[role] = {...snap};
    notifyListeners();
    if (!persist) return;
    try {
      await SharedPreferencesAsync().setStringList(_snapKey(role), [
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
