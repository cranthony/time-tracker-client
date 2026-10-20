import 'package:flutter/widgets.dart';

import '../models/goal.dart';
import '../models/goal_changes.dart';
import '../outbox/write_queue.dart';
import 'mcp_client.dart';
import 'response_cache.dart';

/// The user's goals. The app talks to this rather than to MCP directly,
/// so screens can be exercised without a server. See [GoalsScope] for how
/// screens find it.
abstract class GoalsRepository {
  /// Every goal, whatever its status.
  Future<List<Goal>> goals();

  /// What [goals] last returned, kept from an earlier run of the app;
  /// null if there's nothing kept.
  Future<List<Goal>?> cachedGoals();

  /// Creates a goal from [goal]'s fields; returns it as created, with its
  /// id.
  Future<Goal> createGoal(Goal goal);

  /// Saves [changes], keyed as `update_goal` takes them, to goal [id]; a
  /// null clears that field. [ordered] -- as it is unless it's said
  /// otherwise -- it's saved only after every goal change already
  /// waiting, never joined with one: a goal closed after its sub-goals
  /// stays behind them. Returns it as saved.
  Future<Goal> updateGoal(
    String id,
    Map<String, Object?> changes, {
    bool ordered = true,
  });

  /// Deletes goal [id]. It mustn't have sub-goals by then. [ordered], as
  /// for [updateGoal].
  Future<void> deleteGoal(String id, {bool ordered = true});

  /// Makes [changes] -- to several goals -- all at once, checked whole, as
  /// `update_goals` makes them: the rules hold for the result, not each
  /// step. A goal made ([GoalCreate]) is named by the id it's given here,
  /// which the changes after it may name it by (as a parent); gives each
  /// one's own id, by that one.
  Future<Map<String, String>> changeGoals(List<GoalChange> changes);
}

/// Reaches goals via the Time Tracker MCP server's tools.
class McpGoalsRepository implements GoalsRepository {
  /// With [writes], goals are written through it: queued, kept on the
  /// device and sent once -- and what's read is shown with them made.
  McpGoalsRepository(this._client, {this._cache, this._writes});

  final McpClient _client;
  final ResponseCache? _cache;
  final WriteQueue? _writes;

  static const _goalsKey = 'goals';

  /// [result], `get_goals`', with the writes waiting made to it.
  Object? _shown(Object? result) =>
      _writes?.shown(WriteKind.goal, [
        for (final g in result as List) (g as Map).cast<String, Object?>(),
      ]) ??
      result;

  static List<Goal> _decode(Object? result) => [
    for (final g in result as List)
      Goal.fromJson((g as Map).cast<String, dynamic>()),
  ];

  static Map<String, dynamic> _map(Object? result) =>
      (result as Map).cast<String, dynamic>();

  @override
  Future<List<Goal>?> cachedGoals() async {
    try {
      final result = await _cache?.read(_goalsKey);
      return result == null ? null : _decode(_shown(result));
    } catch (_) {
      return null; // From an older version of the app, perhaps.
    }
  }

  @override
  Future<List<Goal>> goals() async {
    final result = await _client.callTool('get_goals', {
      'statuses': goalStatuses.keys.toList(),
    });
    await _cache?.write(_goalsKey, result);
    return _decode(_shown(result));
  }

  @override
  Future<Goal> createGoal(Goal goal) async => switch (_writes) {
    final writes? => Goal.fromJson(
      writes.created(WriteKind.goal, goal.toJson()).cast(),
    ),
    null => Goal.fromJson(
      _map(
        _map(
          await _client.callTool('create_goal', {
            'goal': goal.toJson()..remove('id'),
          }),
        )['goal'],
      ),
    ),
  };

  @override
  Future<Goal> updateGoal(
    String id,
    Map<String, Object?> changes, {
    bool ordered = true,
  }) async => switch (_writes) {
    final writes? => Goal.fromJson(
      writes.update(WriteKind.goal, id, changes, ordered: ordered).cast(),
    ),
    null => Goal.fromJson(
      _map(
        await _client.callTool('update_goal', {
          'goal': {
            'id': id,
            for (final MapEntry(:key, :value) in changes.entries) key: ?value,
          },
          if ([
                for (final MapEntry(:key, :value) in changes.entries)
                  if (value == null) key,
              ]
              case final clear when clear.isNotEmpty)
            'clear_fields': clear,
        }),
      ),
    ),
  };

  @override
  Future<Map<String, String>> changeGoals(List<GoalChange> changes) async {
    final writes = _writes;
    final ids = {
      for (final c in changes)
        if (c is GoalCreate) c.goal.id: writes?.newId() ?? c.goal.id,
    };
    final named = renamed(changes, ids);
    final creates = [
      for (final c in named)
        if (c is GoalCreate) c.goal.toJson()..remove('version'),
    ];
    final updates = [
      for (final c in named)
        if (c is GoalUpdate) (c.id, c.changes),
    ];
    final deletes = [
      for (final c in named)
        if (c is GoalDelete) c.id,
    ];
    if (writes != null) {
      writes.batch(
        WriteKind.goal,
        creates: creates,
        updates: updates,
        deletes: deletes,
      );
      return ids;
    }
    final result = _map(
      await _client.callTool('update_goals', {
        if (creates.isNotEmpty)
          'creates': [
            for (final c in creates) {...c}..remove('id'),
          ],
        if (updates.isNotEmpty)
          'updates': [
            for (final (id, changes) in updates)
              {
                'goal': {
                  'id': id,
                  for (final MapEntry(:key, :value) in changes.entries)
                    key: ?value,
                },
                if ([
                      for (final MapEntry(:key, :value) in changes.entries)
                        if (value == null) key,
                    ]
                    case final clear when clear.isNotEmpty)
                  'clear_fields': clear,
              },
          ],
        if (deletes.isNotEmpty)
          'deletes': [
            for (final id in deletes) {'goal_id': id},
          ],
      }),
    );
    // Made without ids of the app's own: the server's, by title, in order.
    final made = [
      for (final g in result['goals'] as List? ?? const [])
        Goal.fromJson((g as Map).cast<String, dynamic>()),
    ];
    return {
      for (final c in changes)
        if (c is GoalCreate)
          c.goal.id:
              made.where((g) => g.title == c.goal.title).firstOrNull?.id ??
              c.goal.id,
    };
  }

  @override
  Future<void> deleteGoal(String id, {bool ordered = true}) async {
    if (_writes case final writes?) {
      writes.delete(WriteKind.goal, id, ordered: ordered);
      return;
    }
    await _client.callTool('delete_goal', {'goal_id': id});
  }
}

/// Keeps goals in memory, checked as the server checks them. Used when no
/// server is configured, and in tests.
class InMemoryGoalsRepository implements GoalsRepository {
  InMemoryGoalsRepository([List<Goal> goals = const [], this.now])
    : _goals = [...goals];

  final List<Goal> _goals;

  /// The clock a status change is stamped with; the real one by default.
  final DateTime Function()? now;

  DateTime get _now => (now ?? DateTime.now)();

  @override
  Future<List<Goal>?> cachedGoals() async => null;

  @override
  Future<List<Goal>> goals() async => [for (final g in _goals) _withPath(g)];

  Goal _withPath(Goal goal) => Goal.fromJson({
    ...goal.toJson(),
    'path': GoalTree(_goals).pathOf(goal.id),
  });

  void _check(List<Goal> goals) {
    final problems = goalProblems(goals);
    if (problems.isNotEmpty) throw McpException(problems.join(' '));
  }

  @override
  Future<Goal> createGoal(Goal goal) async {
    final base = goal.title.toLowerCase().replaceAll(
      RegExp(r'[^a-z0-9]+'),
      '-',
    );
    var id = goal.id.isNotEmpty ? goal.id : (base.isEmpty ? 'goal' : base);
    for (var n = 2; _goals.any((g) => g.id == id); n++) {
      id = '$base-$n';
    }
    final created = Goal.fromJson({
      ...goal.toJson(),
      'id': id,
      if (goal.history.isEmpty)
        'history': [
          StatusChange(goal.status, _now, deadline: goal.deadline).toJson(),
        ],
      'version': 1,
    });
    final all = followingParents([..._goals, created]);
    _check(all);
    _goals
      ..clear()
      ..addAll(all);
    return _withPath(all.last);
  }

  @override
  Future<Goal> updateGoal(
    String id,
    Map<String, Object?> changes, {
    bool ordered = true,
  }) async {
    final i = _goals.indexWhere((g) => g.id == id);
    if (i < 0) throw McpException("'$id' isn't a goal");
    final before = _goals[i];
    final json = {...before.toJson(), ...changes}
      ..removeWhere((_, v) => v == null);
    // A deadline of its own unties it from its parent's.
    if (changes.containsKey('deadline') &&
        !changes.containsKey('deadline_offset_minutes')) {
      json.remove('deadline_offset_minutes');
    }
    if (!changes.containsKey('history') && json['status'] != before.status) {
      json['history'] = [
        for (final c in before.history) c.toJson(),
        StatusChange(
          json['status'] as String,
          _now,
          deadline: json['deadline'] as String?,
        ).toJson(),
      ];
    }
    json['version'] = (before.version ?? 0) + 1;
    final all = followingParents([..._goals]..[i] = Goal.fromJson(json));
    _check(all);
    _goals
      ..clear()
      ..addAll(all);
    return _withPath(all[i]);
  }

  @override
  Future<Map<String, String>> changeGoals(List<GoalChange> changes) async {
    final ids = <String, String>{};
    for (final c in changes.whereType<GoalCreate>()) {
      final base = c.goal.title.toLowerCase().replaceAll(
        RegExp(r'[^a-z0-9]+'),
        '-',
      );
      var id = base.isEmpty ? 'goal' : base;
      for (
        var n = 2;
        _goals.any((g) => g.id == id) || ids.containsValue(id);
        n++
      ) {
        id = '$base-$n';
      }
      ids[c.goal.id] = id;
    }
    final after = applied(_goals, renamed(changes, ids), now: _now);
    _check(after);
    _goals
      ..clear()
      ..addAll(after);
    return ids;
  }

  @override
  Future<void> deleteGoal(String id, {bool ordered = true}) async {
    final rest = [
      for (final g in _goals)
        if (g.id != id) g,
    ];
    _check(rest);
    _goals
      ..clear()
      ..addAll(rest);
  }
}

/// Provides a [GoalsRepository] to the screens and dialogs below it, so
/// it needn't be passed through each. Without one, goals aren't offered.
class GoalsScope extends InheritedWidget {
  const GoalsScope({super.key, required this.repository, required super.child});

  final GoalsRepository repository;

  /// The nearest [GoalsScope]'s repository, or null if there's none.
  static GoalsRepository? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<GoalsScope>()?.repository;

  @override
  bool updateShouldNotify(GoalsScope oldWidget) =>
      repository != oldWidget.repository;
}
