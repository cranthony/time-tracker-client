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

/// Keeps every entry in one SharedPreferences value.
class PrefsResponseCache implements ResponseCache {
  PrefsResponseCache({
    this.key = 'response_cache',
    SharedPreferencesAsync? prefs,
  }) : _prefs = prefs ?? SharedPreferencesAsync();

  final String key;
  final SharedPreferencesAsync _prefs;

  late final Future<Map<String, Object?>> _entries = _load();

  /// The last save, so saves land in order.
  Future<void> _saving = Future.value();

  Future<Map<String, Object?>> _load() async {
    try {
      final json = await _prefs.getString(key);
      if (json != null) return (jsonDecode(json) as Map).cast();
    } catch (_) {
      // Unreadable: start over.
    }
    return {};
  }

  @override
  Future<Object?> read(String key) async => (await _entries)[key];

  @override
  Future<void> write(String key, Object? value) async {
    final entries = await _entries;
    entries[key] = value;
    await _save(() => _prefs.setString(this.key, jsonEncode(entries)));
  }

  @override
  Future<void> clear() async {
    (await _entries).clear();
    await _save(() => _prefs.remove(key));
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
