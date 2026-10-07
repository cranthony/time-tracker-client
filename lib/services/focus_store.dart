import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Who and what the People pane keeps in front: the habits the user
/// focuses on (up to [maxHabits]) and the people they prioritize (up to
/// [maxPeople]), each in the order picked. Picked in the app and kept on
/// this device only, not on the server. Listeners hear every change.
class FocusStore extends ChangeNotifier {
  /// Kept on the device with [persist]; otherwise only while the app
  /// runs. Starts with [habits] and [people], until what's kept is
  /// [load]ed.
  FocusStore({
    this.persist = true,
    List<String> habits = const [],
    List<String> people = const [],
  }) : _habits = [...habits],
       _people = [...people];

  static const maxHabits = 2;
  static const maxPeople = 3;

  final bool persist;
  List<String> _habits;
  List<String> _people;
  Future<void>? _loading;

  /// The focus habits' ids, in the order picked.
  List<String> get habits => List.unmodifiable(_habits);

  /// The prioritized people's ids, in the order picked.
  List<String> get people => List.unmodifiable(_people);

  /// Reads what's kept on the device, once. Best effort.
  Future<void> load() => _loading ??= () async {
    if (!persist) return;
    try {
      final json = await SharedPreferencesAsync().getString(_key);
      if (json == null) return;
      final kept = jsonDecode(json) as Map;
      _habits = [for (final id in kept['habits'] as List? ?? const []) '$id'];
      _people = [for (final id in kept['people'] as List? ?? const []) '$id'];
      notifyListeners();
    } catch (_) {
      // Nowhere to keep it, or from an older version.
    }
  }();

  bool isFocusHabit(String id) => _habits.contains(id);
  bool isPrioritized(String id) => _people.contains(id);

  /// Whether another habit can be focused on, or person prioritized.
  bool get habitsFull => _habits.length >= maxHabits;
  bool get peopleFull => _people.length >= maxPeople;

  /// Focuses on habit [id], or stops; none past [maxHabits].
  void setFocusHabit(String id, bool on) => _set(_habits, id, on, maxHabits);

  /// Prioritizes person [id], or stops; none past [maxPeople].
  void setPrioritized(String id, bool on) => _set(_people, id, on, maxPeople);

  void _set(List<String> ids, String id, bool on, int max) {
    if (on == ids.contains(id) || (on && ids.length >= max)) return;
    on ? ids.add(id) : ids.remove(id);
    notifyListeners();
    if (!persist) return;
    try {
      SharedPreferencesAsync()
          .setString(_key, jsonEncode({'habits': _habits, 'people': _people}))
          .catchError((_) {});
    } catch (_) {
      // Nowhere to keep it: it lasts until the app closes.
    }
  }

  static const _key = 'people_focus';
}
