import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'pending_action_save.dart';
import 'pending_event_write.dart';
import 'pending_note.dart';

/// Keeps unsaved changes, of type [T], across app restarts.
abstract class OutboxStore<T> {
  Future<List<T>> load();
  Future<void> save(List<T> items);
}

/// SharedPreferences on Android, a file in AppData on Windows, and
/// localStorage on the web. The async API doesn't cache, so the app and its
/// Android background task (which may run in another isolate) always see
/// each other's latest writes.
class PrefsOutboxStore<T> implements OutboxStore<T> {
  PrefsOutboxStore({
    required this.key,
    required this._fromJson,
    required this._toJson,
    SharedPreferencesAsync? prefs,
  }) : _prefs = prefs ?? SharedPreferencesAsync();

  /// Where notes waiting to be saved are kept.
  static PrefsOutboxStore<PendingNote> notes({SharedPreferencesAsync? prefs}) =>
      PrefsOutboxStore(
        key: 'note_outbox',
        fromJson: PendingNote.fromJson,
        toJson: (note) => note.toJson(),
        prefs: prefs,
      );

  /// Where action saves waiting to be sent, or that failed, are kept.
  static PrefsOutboxStore<PendingActionSave> actions({
    SharedPreferencesAsync? prefs,
  }) => PrefsOutboxStore(
    // Named from when actions were goals: kept, so saves waiting from an
    // older version aren't lost.
    key: 'goal_outbox',
    fromJson: PendingActionSave.fromJson,
    toJson: (save) => save.toJson(),
    prefs: prefs,
  );

  /// Where changes to events, and the proposal, waiting to be saved are
  /// kept.
  static PrefsOutboxStore<PendingEventWrite> events({
    SharedPreferencesAsync? prefs,
  }) => PrefsOutboxStore(
    key: 'event_outbox',
    fromJson: PendingEventWrite.fromJson,
    toJson: (write) => write.toJson(),
    prefs: prefs,
  );

  final String key;
  final T Function(Map<String, dynamic> json) _fromJson;
  final Map<String, dynamic> Function(T item) _toJson;
  final SharedPreferencesAsync _prefs;

  @override
  Future<List<T>> load() async {
    final json = await _prefs.getString(key);
    if (json == null) return [];
    return (jsonDecode(json) as List)
        .map((n) => _fromJson((n as Map).cast<String, dynamic>()))
        .toList();
  }

  @override
  Future<void> save(List<T> items) => items.isEmpty
      ? _prefs.remove(key)
      : _prefs.setString(key, jsonEncode(items.map(_toJson).toList()));
}

class InMemoryOutboxStore<T> implements OutboxStore<T> {
  List<T> items = [];

  @override
  Future<List<T>> load() async => [...items];

  @override
  Future<void> save(List<T> items) async => this.items = [...items];
}
