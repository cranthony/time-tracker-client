import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// The server's last answers, by key, so a page can show them while it
/// asks again. Best effort: anything that goes wrong reading or writing it
/// just means nothing is cached.
///
/// Kept, with [PrefsResponseCache], where the outbox keeps unsaved notes:
/// SharedPreferences on Android, a file in AppData on Windows, and
/// localStorage on the web.
abstract class ResponseCache {
  /// The JSON value last [write]n under [key], or null if there's none.
  Future<Object?> read(String key);

  /// Keeps [value], which must be encodable as JSON, under [key].
  Future<void> write(String key, Object? value);

  /// Forgets everything, e.g. on signing out.
  Future<void> clear();
}

/// Keeps each entry in a SharedPreferences value of its own, under [key]
/// and its own -- "response_cache/proposal" -- read afresh each time. The
/// app and its background task (another isolate, with a cache of its own)
/// each see what the other last kept, and keeping one entry never puts
/// back another as it was: one big value, read once and written whole,
/// left each blind to the other's, and undoing them.
class PrefsResponseCache implements ResponseCache {
  PrefsResponseCache({
    this.key = 'response_cache',
    SharedPreferencesAsync? prefs,
  }) : _prefs = prefs ?? SharedPreferencesAsync();

  final String key;
  final SharedPreferencesAsync _prefs;

  String _keyOf(String entry) => '$key/$entry';

  /// The entries kept as one value, by an earlier version of the app, each
  /// kept as its own -- unless it has one already -- then that let go.
  late final Future<void> _split = () async {
    try {
      final json = await _prefs.getString(key);
      if (json == null) return;
      final entries = (jsonDecode(json) as Map).cast<String, Object?>();
      for (final MapEntry(key: entry, :value) in entries.entries) {
        if (value == null || await _prefs.getString(_keyOf(entry)) != null) {
          continue;
        }
        await _prefs.setString(_keyOf(entry), jsonEncode(value));
      }
      await _prefs.remove(key);
    } catch (_) {
      // Unreadable: start over.
    }
  }();

  /// The last save, so saves land in order.
  Future<void> _saving = Future.value();

  @override
  Future<Object?> read(String key) async {
    await _split;
    await _saving;
    try {
      final json = await _prefs.getString(_keyOf(key));
      return json == null ? null : jsonDecode(json);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> write(String key, Object? value) async {
    await _split;
    final json = value == null ? null : jsonEncode(value);
    await _save(
      () => json == null
          ? _prefs.remove(_keyOf(key))
          : _prefs.setString(_keyOf(key), json),
    );
  }

  @override
  Future<void> clear() async {
    await _split;
    await _save(() async {
      final keys = await _prefs.getKeys();
      for (final k in keys) {
        if (k.startsWith('$key/')) await _prefs.remove(k);
      }
      await _prefs.remove(key);
    });
  }

  Future<void> _save(Future<void> Function() save) =>
      _saving = _saving.then((_) => save()).catchError((Object _) {});
}

class InMemoryResponseCache implements ResponseCache {
  final entries = <String, Object?>{};

  @override
  Future<Object?> read(String key) async => entries[key];

  @override
  Future<void> write(String key, Object? value) async => entries[key] = value;

  @override
  Future<void> clear() async => entries.clear();
}
