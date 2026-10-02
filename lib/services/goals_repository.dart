import '../models/assessment.dart';
import '../models/goal.dart';
import 'mcp_client.dart';
import 'response_cache.dart';

/// Where goals come from. The app talks to this rather than to MCP directly
/// so screens can be exercised without a server.
abstract class GoalsRepository {
  /// Every goal, whatever its status, parents before their children.
  Future<GoalList> goals();

  /// What [goals] last returned, kept from an earlier run of the app; null
  /// if there's nothing kept.
  Future<GoalList?> cachedGoals();

  /// Creates a goal from [fields], keyed as `create_goal` takes them.
  /// Returns every goal, as [goals] does.
  Future<GoalList> createGoal(Map<String, Object?> fields);

  /// Saves [changes], keyed as `update_goal` takes them, to [goal]; a null
  /// clears that property. Returns every goal, as [goals] does.
  Future<GoalList> updateGoal(Goal goal, Map<String, Object?> changes);

  /// [goal]'s recent assessments (its last 12 periods), proposed and
  /// confirmed, oldest first.
  Future<List<Assessment>> history(Goal goal);
}

/// Reads and writes goals via the Time Tracker MCP server.
class McpGoalsRepository implements GoalsRepository {
  McpGoalsRepository(this._client, {this._cache});

  final McpClient _client;
  final ResponseCache? _cache;

  static const _cacheKey = 'goals';

  @override
  Future<GoalList> goals() async {
    final result = await _client.callTool('get_goals', {
      'statuses': goalStatuses.keys.toList(),
    });
    await _cache?.write(_cacheKey, result);
    return _decode(result);
  }

  @override
  Future<GoalList?> cachedGoals() async {
    try {
      final result = await _cache?.read(_cacheKey);
      return result == null ? null : _decode(result);
    } catch (_) {
      return null; // From an older version of the app, perhaps.
    }
  }

  @override
  Future<GoalList> createGoal(Map<String, Object?> fields) async {
    await _client.callTool('create_goal', {
      'goal': {
        for (final MapEntry(:key, :value) in fields.entries) key: ?value,
      },
    });
    // create_goal answers with only some of them.
    return goals();
  }

  @override
  Future<GoalList> updateGoal(Goal goal, Map<String, Object?> changes) async {
    // The server keeps whatever is left out or null, and clears what
    // clear_fields names.
    final clear = [
      for (final MapEntry(:key, :value) in changes.entries)
        if (value == null) key,
    ];
    await _client.callTool('update_goal', {
      'goal': {
        'id': goal.id,
        for (final MapEntry(:key, :value) in changes.entries) key: ?value,
      },
      if (clear.isNotEmpty) 'clear_fields': clear,
    });
    // update_goal answers with only some of them.
    return goals();
  }

  @override
  Future<List<Assessment>> history(Goal goal) async {
    final result = await _client.callTool('get_goal_history', {
      'goal_ids': [goal.id],
    });
    return [
      for (final item in result as List)
        Assessment.fromJson((item as Map).cast<String, dynamic>()),
    ];
  }

  static GoalList _decode(Object? result) =>
      GoalList.fromJson((result as Map).cast<String, dynamic>());
}

/// Keeps goals in memory. Used when no server is configured, and in tests.
class InMemoryGoalsRepository implements GoalsRepository {
  InMemoryGoalsRepository([
    List<Goal> goals = const [],
    this.assessments = const {},
  ]) : _goals = [...goals];

  /// Each goal's history, by goal id.
  final Map<String, List<Assessment>> assessments;

  @override
  Future<List<Assessment>> history(Goal goal) async =>
      assessments[goal.id] ?? const [];

  final List<Goal> _goals;
  int _nextId = 1;

  @override
  Future<GoalList> goals() async {
    final byParent = <String?, List<Goal>>{};
    for (final goal in _goals) {
      byParent.putIfAbsent(goal.parentId, () => []).add(goal);
    }
    final ordered = <Goal>[];
    void visit(Goal goal, String path) {
      ordered.add(Goal.fromJson({..._json(goal), 'path': path}));
      for (final child in byParent[goal.id] ?? const <Goal>[]) {
        visit(child, '$path › ${goalName(child)}');
      }
    }

    for (final root in byParent[null] ?? const <Goal>[]) {
      visit(root, goalName(root));
    }
    return GoalList(
      goals: ordered,
      labelSlotsUsed: _goals.where((g) => g.active).length,
    );
  }

  @override
  Future<GoalList?> cachedGoals() async => null;

  @override
  Future<GoalList> createGoal(Map<String, Object?> fields) async {
    _goals.add(
      Goal.fromJson({'status': 'active', ...fields, 'id': 'g${_nextId++}'}),
    );
    return goals();
  }

  @override
  Future<GoalList> updateGoal(Goal goal, Map<String, Object?> changes) async {
    final i = _goals.indexWhere((g) => g.id == goal.id);
    if (i < 0) throw StateError('No goal ${goal.id}');
    _goals[i] = Goal.fromJson({..._json(_goals[i]), ...changes});
    return goals();
  }

  static Map<String, Object?> _json(Goal goal) => {
    ...goal.properties,
    'id': goal.id,
    'parent_id': goal.parentId,
    'name': goal.name,
    'status': goal.status,
    'background_color': goal.backgroundColor,
    'priority': goal.priority,
    'fixed_time': goal.fixedTime,
    'cadence': goal.cadence,
    'measure': goal.measure,
    'effective_color': goal.effectiveColor,
    'health': goal.health,
    'health_period': goal.healthPeriod,
    'health_trend': goal.healthTrend.map((r) => r?.toString() ?? '-').join(','),
    'stale_periods': goal.stalePeriods,
  };
}
