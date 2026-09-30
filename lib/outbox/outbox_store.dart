import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'pending_note.dart';

/// Keeps unsaved notes across app restarts.
abstract class OutboxStore {
  Future<List<PendingNote>> load();
  Future<void> save(List<PendingNote> notes);
}

/// SharedPreferences on Android, a file in AppData on Windows, and
/// localStorage on the web. The async API doesn't cache, so the app and its
/// Android background task (which may run in another isolate) always see
/// each other's latest writes.
class PrefsOutboxStore implements OutboxStore {
  PrefsOutboxStore({this.key = 'note_outbox', SharedPreferencesAsync? prefs})
    : _prefs = prefs ?? SharedPreferencesAsync();

  final String key;
  final SharedPreferencesAsync _prefs;

  @override
  Future<List<PendingNote>> load() async {
    final json = await _prefs.getString(key);
    if (json == null) return [];
    return (jsonDecode(json) as List)
        .map((n) => PendingNote.fromJson((n as Map).cast<String, dynamic>()))
        .toList();
  }

  @override
  Future<void> save(List<PendingNote> notes) => notes.isEmpty
      ? _prefs.remove(key)
      : _prefs.setString(
          key,
          jsonEncode(notes.map((n) => n.toJson()).toList()),
        );
}

class InMemoryOutboxStore implements OutboxStore {
  List<PendingNote> notes = [];

  @override
  Future<List<PendingNote>> load() async => [...notes];

  @override
  Future<void> save(List<PendingNote> notes) async => this.notes = [...notes];
}
