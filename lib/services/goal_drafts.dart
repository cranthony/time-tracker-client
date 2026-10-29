import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/named.dart';
import '../models/text_format.dart';

/// A goal being set in the New goal sheet, kept on the device as it's
/// typed, and never sent: until it's added, or thrown away.
@immutable
class GoalDraft {
  const GoalDraft({
    required this.title,
    required this.day,
    this.description,
    this.descriptionFormat,
    this.priority,
    this.parentId,
    this.withWhom = const [],
    this.forWhom = const [],
  });

  /// As typed, untrimmed.
  final String title;

  /// The day it's due, at its end: midnight starting it, local.
  final DateTime day;

  /// As the goal's; null for none.
  final String? description;

  /// How [description] is written; null, as it looks.
  final TextFormat? descriptionFormat;

  /// Its own priority; null to inherit its parent's.
  final int? priority;

  /// The goal it goes under; null for the top level.
  final String? parentId;

  /// Who it's done with, and who it's for -- people and circles, a plain
  /// circle with its except -- as a goal's with_ids and for_ids: no one in
  /// both.
  final List<Named> withWhom;
  final List<Named> forWhom;

  /// Their ids.
  List<String> get withIds => namedIds(withWhom);
  List<String> get forIds => namedIds(forWhom);

  factory GoalDraft.fromJson(Map<String, dynamic> json) => GoalDraft(
    title: json['title'] as String? ?? '',
    day: DateTime.parse(json['day'] as String),
    description: json['description'] as String?,
    descriptionFormat: TextFormat.fromJson(json['description_format']),
    priority: (json['priority'] as num?)?.toInt(),
    parentId: json['parent_id'] as String?,
    withWhom: Named.listFromJson(json['with_ids']),
    forWhom: Named.listFromJson(json['for_ids']),
  );

  Map<String, dynamic> toJson() => {
    'title': title,
    'day': DateTime(day.year, day.month, day.day).toIso8601String(),
    'description': ?description,
    'description_format': ?descriptionFormat?.wire,
    'priority': ?priority,
    'parent_id': ?parentId,
    if (withWhom.isNotEmpty) 'with_ids': namedToJson(withWhom),
    if (forWhom.isNotEmpty) 'for_ids': namedToJson(forWhom),
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
