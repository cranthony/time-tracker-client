import 'package:flutter/widgets.dart';

import '../models/circadian.dart';
import 'diagnostics_repository.dart';
import 'mcp_client.dart';
import 'response_cache.dart';

/// The user's circadian rhythm ([CircadianRhythm]): when they woke
/// naturally, and the windows worked out from it.
abstract class CircadianRepository {
  /// The rhythm, afresh; null from a server without it -- an older one.
  Future<CircadianRhythm?> rhythm();

  /// What [rhythm] last returned, kept from an earlier run of the app;
  /// null if there's nothing kept.
  Future<CircadianRhythm?> cachedRhythm();

  /// Says the user woke naturally at [hour]:[minute] on [date], in place
  /// of what was said of that day; [note] left out, it has none.
  Future<CircadianRhythm> setNaturalWakeTime(
    DateTime date, {
    required int hour,
    required int minute,
    String? note,
  });

  /// Sets how the minimum and its windows are worked out.
  Future<CircadianRhythm> setWindows(CircadianWindows windows);
}

/// Whether [error] says the server has no such tool: one from before it.
bool _noSuchTool(Object error) =>
    isUnknownTool(error) || '$error'.toLowerCase().contains('tool not found');

/// Reads and sets it with the server's `get_circadian_rhythm`,
/// `set_natural_wake_time` and `set_circadian_windows`, keeping what it
/// last read in [_cache].
class McpCircadianRepository implements CircadianRepository {
  McpCircadianRepository(this._client, {this._cache});

  final McpClient _client;
  final ResponseCache? _cache;

  static const _key = 'circadian_rhythm';

  static CircadianRhythm _decode(Object? result) =>
      CircadianRhythm.fromJson((result as Map).cast<String, dynamic>());

  Future<CircadianRhythm> _kept(Object? result) async {
    await _cache?.write(_key, result);
    return _decode(result);
  }

  @override
  Future<CircadianRhythm?> rhythm() async {
    final Object? result;
    try {
      result = await _client.callTool('get_circadian_rhythm');
    } catch (e) {
      if (!_noSuchTool(e)) rethrow;
      await _cache?.write(_key, null);
      return null;
    }
    return _kept(result);
  }

  @override
  Future<CircadianRhythm?> cachedRhythm() async {
    try {
      final kept = await _cache?.read(_key);
      return kept == null ? null : _decode(kept);
    } catch (_) {
      return null; // From an older version of the app, perhaps.
    }
  }

  @override
  Future<CircadianRhythm> setNaturalWakeTime(
    DateTime date, {
    required int hour,
    required int minute,
    String? note,
  }) async => _kept(
    await _client.callTool('set_natural_wake_time', {
      'date': circadianDate(date),
      'time': circadianTime(hour, minute),
      'note': ?note,
    }),
  );

  @override
  Future<CircadianRhythm> setWindows(CircadianWindows windows) async =>
      _kept(await _client.callTool('set_circadian_windows', windows.toJson()));
}

/// Keeps what it's given, as the server would: for the sample data, and
/// tests.
class InMemoryCircadianRepository implements CircadianRepository {
  InMemoryCircadianRepository([this.current = const CircadianRhythm()]);

  CircadianRhythm current;

  @override
  Future<CircadianRhythm?> rhythm() async => current;

  @override
  Future<CircadianRhythm?> cachedRhythm() async => null;

  @override
  Future<CircadianRhythm> setNaturalWakeTime(
    DateTime date, {
    required int hour,
    required int minute,
    String? note,
  }) async {
    final day = DateTime(date.year, date.month, date.day);
    return current = CircadianRhythm(
      windows: current.windows,
      timeZone: current.timeZone,
      revisions: [
        for (final r in current.revisions)
          if (r.date != day) r,
        WakeRevision(
          id: 'w${day.millisecondsSinceEpoch}',
          date: day,
          hour: hour,
          minute: minute,
          note: note,
        ),
      ]..sort((a, b) => a.date.compareTo(b.date)),
    );
  }

  @override
  Future<CircadianRhythm> setWindows(CircadianWindows windows) async =>
      current = CircadianRhythm(
        windows: windows,
        timeZone: current.timeZone,
        revisions: current.revisions,
      );
}

/// The rhythm the app shows ([rhythm]): kept from before, then afresh,
/// and as the user sets it.
class Circadian extends ChangeNotifier {
  Circadian(this.repository);

  final CircadianRepository repository;

  /// Null till it's loaded, or from a server without it.
  CircadianRhythm? rhythm;

  /// Loads what was kept, then afresh. Best effort: offline, what was
  /// kept stays.
  Future<void> load() async {
    rhythm ??= await repository.cachedRhythm();
    notifyListeners();
    await refresh();
  }

  /// Fetches it afresh. Best effort.
  Future<void> refresh() async {
    try {
      rhythm = await repository.rhythm();
      notifyListeners();
    } catch (_) {}
  }

  /// See [CircadianRepository.setNaturalWakeTime]: throws what the server
  /// refuses it with.
  Future<void> setNaturalWakeTime(
    DateTime date, {
    required int hour,
    required int minute,
    String? note,
  }) async {
    rhythm = await repository.setNaturalWakeTime(
      date,
      hour: hour,
      minute: minute,
      note: note,
    );
    notifyListeners();
  }

  /// See [CircadianRepository.setWindows]: throws what the server
  /// refuses them with.
  Future<void> setWindows(CircadianWindows windows) async {
    rhythm = await repository.setWindows(windows);
    notifyListeners();
  }

  /// The nearest [CircadianScope]'s, rebuilding as it changes; null if
  /// there's none.
  static Circadian? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<CircadianScope>()?.notifier;
}

/// Makes a [Circadian] available to everything below it.
class CircadianScope extends InheritedNotifier<Circadian> {
  const CircadianScope({
    super.key,
    required Circadian circadian,
    required super.child,
  }) : super(notifier: circadian);
}
