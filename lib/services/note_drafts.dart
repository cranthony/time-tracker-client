import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/note.dart';

/// A note being written, kept on the device as it's typed, and never sent:
/// a new note until it's added, or an edit of one until it's saved. Shown
/// on the Notes page as a draft, to be finished or thrown away.
@immutable
class NoteDraft {
  const NoteDraft({
    required this.id,
    required this.timestamp,
    this.description,
    this.original,
  });

  /// Local only. A draft edit's is [editId] of its note's.
  final String id;
  final DateTime timestamp;

  /// As typed, untrimmed.
  final String? description;

  /// For a draft edit, the note it's of, as it was shown when the edit
  /// began; null for a new note.
  final Note? original;

  bool get isEdit => original != null;

  /// The note as it'd be, with the edited note's id.
  Note get note => Note(
    timestamp: timestamp,
    description: switch (description?.trim()) {
      final d? when d.isNotEmpty => d,
      _ => null,
    },
    id: original?.id,
  );

  /// The id of the draft edit of the note [noteId]: one per note.
  static String editId(String noteId) => 'edit:$noteId';

  factory NoteDraft.fromJson(Map<String, dynamic> json) => NoteDraft(
    id: json['id'] as String,
    timestamp: DateTime.parse(json['timestamp'] as String),
    description: json['description'] as String?,
    original: switch (json['original']) {
      final Map original => Note.fromJson(original.cast<String, dynamic>()),
      _ => null,
    },
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'timestamp': timestamp.toUtc().toIso8601String(),
    'description': ?description,
    // With its id, which Note.toJson leaves out.
    if (original case final original?)
      'original': {...original.toJson(), 'id': original.id},
  };
}

/// The [NoteDraft]s, kept on the device ([NoteDrafts.device]) so they
/// outlast the sheet they're typed in, and the app: each change is made
/// here at once, and written after the ones before it.
class NoteDrafts extends ChangeNotifier {
  NoteDrafts.device({SharedPreferencesAsync? prefs})
    : _prefs = prefs ?? SharedPreferencesAsync();

  /// Kept only while the app runs: for tests, and the offline demo.
  NoteDrafts.inMemory() : _prefs = null;

  static const _key = 'note_drafts';
  final SharedPreferencesAsync? _prefs;

  List<NoteDraft> _drafts = [];
  Future<void> _writing = Future.value();
  bool _disposed = false;

  List<NoteDraft> get drafts => List.unmodifiable(_drafts);

  NoteDraft? byId(String id) => _drafts.where((d) => d.id == id).firstOrNull;

  /// Reads what's kept: those of an earlier run of the app. Any made here
  /// meanwhile stay as they are.
  Future<void> load() async {
    final prefs = _prefs;
    if (prefs == null) return;
    try {
      final json = await prefs.getString(_key);
      if (json == null) return;
      final kept = [
        for (final d in jsonDecode(json) as List)
          NoteDraft.fromJson((d as Map).cast<String, dynamic>()),
      ];
      final here = {for (final d in _drafts) d.id};
      _drafts = [..._drafts, ...kept.where((d) => !here.contains(d.id))];
      _notify();
    } catch (e) {
      debugPrint("Couldn't read the note drafts: $e");
    }
  }

  /// Keeps [draft], in place of one with its id.
  Future<void> put(NoteDraft draft) {
    final i = _drafts.indexWhere((d) => d.id == draft.id);
    final next = [..._drafts];
    if (i < 0) {
      next.add(draft);
    } else {
      next[i] = draft;
    }
    _drafts = next;
    _notify();
    return _write();
  }

  /// Throws away the draft with [id], if there is one.
  Future<void> remove(String id) {
    if (byId(id) == null) return _writing;
    _drafts = [
      for (final d in _drafts)
        if (d.id != id) d,
    ];
    _notify();
    return _write();
  }

  /// Writes the drafts as they are by then, after any write before.
  Future<void> _write() {
    final prefs = _prefs;
    if (prefs == null) return Future.value();
    return _writing = _writing.then((_) async {
      try {
        await (_drafts.isEmpty
            ? prefs.remove(_key)
            : prefs.setString(
                _key,
                jsonEncode([for (final d in _drafts) d.toJson()]),
              ));
      } catch (e) {
        debugPrint("Couldn't keep the note drafts: $e");
      }
    });
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
