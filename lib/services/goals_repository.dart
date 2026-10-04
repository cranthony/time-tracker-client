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
  /// Returns its id, or null if it can't be told apart from the others.
  /// Call [goals] for every goal as they are now: saving one after another,
  /// that's only needed after the last.
  Future<String?> createGoal(Map<String, Object?> fields);

  /// Saves [changes], keyed as `update_goal` takes them, to [goal]; a null
  /// clears that property. Call [goals] for every goal as they are now.
  Future<void> updateGoal(Goal goal, Map<String, Object?> changes);

  /// Puts sibling goals (sharing a parent), by id, in this order, among
  /// the places they hold. Returns every goal, as [goals] does.
  Future<GoalList> reorderGoals(List<String> ids);

  /// [goal]'s recent assessments (its last 12 days and today), proposed
  /// and confirmed, oldest first.
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
  Future<String?> createGoal(Map<String, Object?> fields) async {
    final result = await _client.callTool('create_goal', {
      'goal': {
        for (final MapEntry(:key, :value) in fields.entries) key: ?value,
      },
    });
    if ((result as Map)['created_id'] case final String id) return id;
    // From a server too old to say which is new: a name is only used once
    // among siblings.
    return _decode(result).goals
        .where(
          (g) => g.parentId == fields['parent_id'] && g.name == fields['name'],
        )
        .firstOrNull
        ?.id;
  }

  @override
  Future<void> updateGoal(Goal goal, Map<String, Object?> changes) async {
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
  }

  @override
  Future<GoalList> reorderGoals(List<String> ids) async {
    await _client.callTool('reorder_goals', {'goal_ids': ids});
    // reorder_goals answers with only some of them.
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
    this.asOf,
    this.minutesByStatuses,
  ]) : _goals = [...goals];

  /// Each goal's history, by goal id.
  final Map<String, List<Assessment>> assessments;

  /// The last compaction, as [GoalList.asOf] gives it.
  final DateTime? asOf;

  /// The time on goals by status, as [GoalList.minutesByStatuses] gives it.
  final List<StatusMinutes>? minutesByStatuses;

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
    // Each with what it inherits, as the server gives it.
    void visit(Goal goal, Goal? parent, String path) {
      final listed = Goal.fromJson({
        ...goal.toJson(),
        'path': path,
        'effective_priority': goal.priority ?? parent?.effectivePriority,
        'effective_fixed_time': goal.fixedTime ?? parent?.effectiveFixedTime,
      });
      ordered.add(listed);
      for (final child in byParent[goal.id] ?? const <Goal>[]) {
        visit(child, listed, '$path › ${goalName(child)}');
      }
    }

    for (final root in byParent[null] ?? const <Goal>[]) {
      visit(root, null, goalName(root));
    }
    return GoalList(
      goals: ordered,
      labelSlotsUsed: _goals.where((g) => g.active && !g.isOverall).length,
      asOf: asOf,
      minutesByStatuses: minutesByStatuses,
    );
  }

  @override
  Future<GoalList?> cachedGoals() async => null;

  @override
  Future<GoalList> reorderGoals(List<String> ids) async {
    final places = [
      for (final (i, goal) in _goals.indexed)
        if (ids.contains(goal.id)) i,
    ];
    final byId = {for (final goal in _goals) goal.id: goal};
    for (var i = 0; i < places.length; i++) {
      _goals[places[i]] = byId[ids[i]]!;
    }
    return goals();
  }

  @override
  Future<String> createGoal(Map<String, Object?> fields) async {
    final id = 'g${_nextId++}';
    _goals.add(Goal.fromJson({'status': 'active', ...fields, 'id': id}));
    return id;
  }

  @override
  Future<void> updateGoal(Goal goal, Map<String, Object?> changes) async {
    final i = _goals.indexWhere((g) => g.id == goal.id);
    if (i < 0) throw StateError('No goal ${goal.id}');
    _goals[i] = Goal.fromJson({..._goals[i].toJson(), ...changes});
  }
}
