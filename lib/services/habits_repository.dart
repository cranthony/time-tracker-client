import 'package:flutter/widgets.dart';

import '../models/habit.dart';
import 'mcp_client.dart';
import 'response_cache.dart';

/// The user's habits. The app talks to this rather than to MCP directly,
/// so screens can be exercised without a server. See [HabitsScope] for
/// how screens find it.
abstract class HabitsRepository {
  /// Every habit, whatever its status.
  Future<List<Habit>> habits();

  /// What [habits] last returned, kept from an earlier run of the app;
  /// null if there's nothing kept.
  Future<List<Habit>?> cachedHabits();

  /// Creates a habit from [habit]'s fields; returns it as created, with
  /// its id.
  Future<Habit> createHabit(Habit habit);

  /// Saves [changes], keyed as `update_habit` takes them, to habit [id]; a
  /// null clears that field. Returns it as saved.
  Future<Habit> updateHabit(String id, Map<String, Object?> changes);
}

/// Reaches habits via the Time Tracker MCP server's tools.
class McpHabitsRepository implements HabitsRepository {
  McpHabitsRepository(this._client, {this._cache});

  final McpClient _client;
  final ResponseCache? _cache;

  static const _habitsKey = 'habits';

  static List<Habit> _decode(Object? result) => [
    for (final h in result as List)
      Habit.fromJson((h as Map).cast<String, dynamic>()),
  ];

  static Map<String, dynamic> _map(Object? result) =>
      (result as Map).cast<String, dynamic>();

  @override
  Future<List<Habit>?> cachedHabits() async {
    try {
      final result = await _cache?.read(_habitsKey);
      return result == null ? null : _decode(result);
    } catch (_) {
      return null; // From an older version of the app, perhaps.
    }
  }

  @override
  Future<List<Habit>> habits() async {
    final result = await _client.callTool('get_habits', {
      'statuses': habitStatuses.keys.toList(),
    });
    await _cache?.write(_habitsKey, result);
    return _decode(result);
  }

  @override
  Future<Habit> createHabit(Habit habit) async => Habit.fromJson(
    _map(
      _map(
        await _client.callTool('create_habit', {
          'habit': habit.toJson()..remove('id'),
        }),
      )['habit'],
    ),
  );

  @override
  Future<Habit> updateHabit(String id, Map<String, Object?> changes) async {
    final clear = [
      for (final MapEntry(:key, :value) in changes.entries)
        if (value == null) key,
    ];
    return Habit.fromJson(
      _map(
        await _client.callTool('update_habit', {
          'habit': {
            'id': id,
            for (final MapEntry(:key, :value) in changes.entries) key: ?value,
          },
          if (clear.isNotEmpty) 'clear_fields': clear,
        }),
      ),
    );
  }
}

/// Keeps habits in memory, checked as the server checks them. Used when
/// no server is configured, and in tests.
class InMemoryHabitsRepository implements HabitsRepository {
  InMemoryHabitsRepository([List<Habit> habits = const []])
    : _habits = [...habits];

  final List<Habit> _habits;

  @override
  Future<List<Habit>?> cachedHabits() async => null;

  @override
  Future<List<Habit>> habits() async => [..._habits];

  void _check(Habit habit) {
    if (habit.name.trim().isEmpty) throw McpException('Give it a name.');
    if (habit.actionId.isEmpty) {
      throw McpException('Pick the action or group it is about.');
    }
    if (_habits.any(
      (h) =>
          h.id != habit.id &&
          h.status != 'deleted' &&
          h.name.toLowerCase() == habit.name.toLowerCase(),
    )) {
      throw McpException("There's already a habit named ${habit.name}.");
    }
  }

  @override
  Future<Habit> createHabit(Habit habit) async {
    _check(habit);
    final base = habit.name.toLowerCase().replaceAll(
      RegExp(r'[^a-z0-9]+'),
      '-',
    );
    var id = base.isEmpty ? 'habit' : base;
    for (var n = 2; _habits.any((h) => h.id == id); n++) {
      id = '$base-$n';
    }
    final created = Habit.fromJson({...habit.toJson(), 'id': id});
    _habits.add(created);
    return created;
  }

  @override
  Future<Habit> updateHabit(String id, Map<String, Object?> changes) async {
    final i = _habits.indexWhere((h) => h.id == id);
    if (i < 0) throw McpException("'$id' isn't a habit");
    final before = _habits[i];
    final updated = Habit.fromJson({...before.toJson(), ...changes})
        .withCancelledEvents(before.cancelledEvents);
    _check(updated);
    _habits[i] = updated;
    return updated;
  }
}

/// Provides a [HabitsRepository] to the screens and dialogs below it, so
/// it needn't be passed through each. Without one, habits aren't offered.
class HabitsScope extends InheritedWidget {
  const HabitsScope({
    super.key,
    required this.repository,
    required super.child,
  });

  final HabitsRepository repository;

  /// The nearest [HabitsScope]'s repository, or null if there's none.
  static HabitsRepository? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<HabitsScope>()?.repository;

  @override
  bool updateShouldNotify(HabitsScope oldWidget) =>
      repository != oldWidget.repository;
}
