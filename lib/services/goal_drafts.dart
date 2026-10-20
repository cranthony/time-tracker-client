import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A goal being set in the New goal sheet, kept on the device as it's
/// typed, and never sent: until it's added, or thrown away.
@immutable
class GoalDraft {
  const GoalDraft({
    required this.title,
    required this.day,
    this.description,
    this.definitionOfDone,
    this.parentId,
    this.withIds = const [],
    this.forIds = const [],
  });

  /// As typed, untrimmed.
  final String title;

  /// The day it's due, at its end: midnight starting it, local.
  final DateTime day;

  /// HTML, as the goal's; null for none.
  final String? description;
  final String? definitionOfDone;

  /// The goal it goes under; null for the top level.
  final String? parentId;

  /// Who it's done with, and who it's for, by person id, as a goal's
  /// with_ids and for_ids: no one in both.
  final List<String> withIds;
  final List<String> forIds;

  factory GoalDraft.fromJson(Map<String, dynamic> json) => GoalDraft(
    title: json['title'] as String? ?? '',
    day: DateTime.parse(json['day'] as String),
    description: json['description'] as String?,
    definitionOfDone: json['definition_of_done'] as String?,
    parentId: json['parent_id'] as String?,
    withIds: [for (final id in json['with_ids'] as List? ?? const []) '$id'],
    forIds: [for (final id in json['for_ids'] as List? ?? const []) '$id'],
  );

  Map<String, dynamic> toJson() => {
    'title': title,
    'day': DateTime(day.year, day.month, day.day).toIso8601String(),
    'description': ?description,
    'definition_of_done': ?definitionOfDone,
    'parent_id': ?parentId,
    if (withIds.isNotEmpty) 'with_ids': withIds,
    if (forIds.isNotEmpty) 'for_ids': forIds,
  };
}

/// The one [GoalDraft], kept on the device ([GoalDrafts.device]) so it
/// outlasts the sheet it's typed in, and the app: the next New goal sheet
/// carries on with it. Each change is made here at once, and written
/// after the ones before it.
class GoalDrafts extends ChangeNotifier {
  GoalDrafts.device({SharedPreferencesAsync? prefs})
    : _prefs = prefs ?? SharedPreferencesAsync();

  /// Kept only while the app runs: for tests, and the offline demo.
  GoalDrafts.inMemory() : _prefs = null;

  static const _key = 'goal_draft';
  final SharedPreferencesAsync? _prefs;

  GoalDraft? _draft;
  Future<void> _writing = Future.value();
  bool _disposed = false;

  /// Whether one's been changed here: what's read later doesn't undo it.
  bool _changed = false;

  GoalDraft? get draft => _draft;

  /// Reads what's kept from an earlier run of the app, unless it's been
  /// changed here meanwhile.
  Future<void> load() async {
    final prefs = _prefs;
    if (prefs == null) return;
    try {
      final json = await prefs.getString(_key);
      if (json == null || _changed) return;
      _draft = GoalDraft.fromJson(
        (jsonDecode(json) as Map).cast<String, dynamic>(),
      );
      _notify();
    } catch (e) {
      debugPrint("Couldn't read the goal draft: $e");
    }
  }

  /// Keeps [draft], in place of the one before.
  Future<void> put(GoalDraft draft) {
    _changed = true;
    _draft = draft;
    _notify();
    return _write();
  }

  /// Throws the draft away, if there is one.
  Future<void> remove() {
    _changed = true;
    if (_draft == null) return _writing;
    _draft = null;
    _notify();
    return _write();
  }

  /// Writes the draft as it is by then, after any write before.
  Future<void> _write() {
    final prefs = _prefs;
    if (prefs == null) return Future.value();
    return _writing = _writing.then((_) async {
      try {
        final draft = _draft;
        await (draft == null
            ? prefs.remove(_key)
            : prefs.setString(_key, jsonEncode(draft.toJson())));
      } catch (e) {
        debugPrint("Couldn't keep the goal draft: $e");
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
