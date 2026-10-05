import '../models/goal.dart';
import 'mcp_client.dart';
import 'response_cache.dart';

/// Where actions, and the groups they're in, come from: each a [Goal], a
/// group's [Goal.isGroup] set. The app talks to this rather than to MCP
/// directly so screens can be exercised without a server.
abstract class GoalsRepository {
  /// Whether siblings can be put in an order of their own.
  bool get reorderable;

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
}

/// Reads and writes actions and their groups via the Time Tracker MCP
/// server's action tools: `get_actions` and `get_action_groups`, listed
/// together as one tree, and `create_`/`update_action` or
/// `create_`/`update_action_group` for a group. They aren't kept in an
/// order of their own there yet.
class McpGoalsRepository implements GoalsRepository {
  McpGoalsRepository(this._client, {this._cache});

  final McpClient _client;
  final ResponseCache? _cache;

  static const _cacheKey = 'actions';

  @override
  bool get reorderable => false;

  @override
  Future<GoalList> goals() async {
    final actions = await _client.callTool('get_actions', {
      'statuses': goalStatuses.keys.toList(),
    });
    final groups = await _client.callTool('get_action_groups', {});
    final result = {'actions': actions, 'groups': groups};
    await _cache?.write(_cacheKey, result);
    return actionTree(result);
  }

  @override
  Future<GoalList?> cachedGoals() async {
    try {
      final result = await _cache?.read(_cacheKey);
      return result == null ? null : actionTree(result);
    } catch (_) {
      return null; // From an older version of the app, perhaps.
    }
  }

  /// [fields], keyed as the Plan page edits them, as the server's tools
  /// take them: a parent is a group_id, and only what an action (or a
  /// group, with [group]) has is sent.
  static Map<String, Object?> _fields(
    Map<String, Object?> fields, {
    required bool group,
  }) => {
    for (final MapEntry(:key, :value) in fields.entries)
      if (key == 'parent_id')
        'group_id': value
      else if (_actionFields.contains(key) && !(group && key == 'status'))
        key: value,
  };

  static const _actionFields = {
    'name',
    'status',
    'background_color',
    'priority',
    'note',
  };

  @override
  Future<String?> createGoal(Map<String, Object?> fields) async {
    final group = fields['kind'] == 'group';
    final result = await _client.callTool(
      group ? 'create_action_group' : 'create_action',
      {
        group ? 'group' : 'action': {
          for (final MapEntry(:key, :value) in _fields(
            fields,
            group: group,
          ).entries)
            key: ?value,
          // Made by the user, so not waiting for their review.
          if (!group) 'status': fields['status'] ?? 'active',
        },
      },
    );
    return (result as Map)['created_id'] as String?;
  }

  @override
  Future<void> updateGoal(Goal goal, Map<String, Object?> changes) async {
    // The server keeps whatever is left out or null, and clears what
    // clear_fields names.
    final fields = _fields(changes, group: goal.isGroup);
    final clear = [
      for (final MapEntry(:key, :value) in fields.entries)
        if (value == null) key,
    ];
    await _client.callTool(
      goal.isGroup ? 'update_action_group' : 'update_action',
      {
        goal.isGroup ? 'group' : 'action': {
          'id': goal.id,
          for (final MapEntry(:key, :value) in fields.entries) key: ?value,
        },
        if (clear.isNotEmpty) 'clear_fields': clear,
      },
    );
  }

  @override
  Future<GoalList> reorderGoals(List<String> ids) =>
      throw UnsupportedError("The server doesn't keep an order of its own.");
}

/// What `get_actions` and `get_action_groups` answered, as [result]'s
/// "actions" and "groups", as one tree: each group, then what's in it,
/// groups before actions.
GoalList actionTree(Object? result) {
  final json = (result as Map).cast<String, dynamic>();
  final list = (json['actions'] as Map).cast<String, dynamic>();
  final nodes = [
    for (final group in json['groups'] as List? ?? const [])
      Goal.fromJson({
        ...(group as Map).cast<String, dynamic>(),
        'parent_id': group['group_id'],
        'status': 'active',
        'kind': 'group',
      }),
    for (final action in list['actions'] as List? ?? const [])
      Goal.fromJson({
        ...(action as Map).cast<String, dynamic>(),
        'parent_id': action['group_id'],
      }),
  ];
  final ids = {for (final node in nodes) node.id};
  final children = <String?, List<Goal>>{};
  for (final node in nodes) {
    final parent = ids.contains(node.parentId) ? node.parentId : null;
    children.putIfAbsent(parent, () => []).add(node);
  }
  final ordered = <Goal>[];
  void visit(Goal node) {
    ordered.add(node);
    children[node.id]?.forEach(visit);
  }

  children[null]?.forEach(visit);
  return GoalList(
    goals: ordered,
    labelSlotsUsed: list['label_slots_used'] as int? ?? 0,
    labelSlotsTotal: list['label_slots_total'] as int? ?? 200,
  );
}

/// Keeps actions in memory, with the time spent on them, as the sample
/// data has it. Used when no server is configured, and in tests.
class InMemoryGoalsRepository implements GoalsRepository {
  InMemoryGoalsRepository([
    List<Goal> goals = const [],
    this.asOf,
    this.minutesByStatuses,
    this.minutesByPriority,
  ]) : _goals = [...goals];

  @override
  bool get reorderable => true;

  /// The last compaction, as [GoalList.asOf] gives it.
  final DateTime? asOf;

  /// The time on goals by status, as [GoalList.minutesByStatuses] gives it.
  final List<StatusMinutes>? minutesByStatuses;

  /// The time by priority, as [GoalList.minutesByPriority] gives it.
  final List<PriorityMinutes>? minutesByPriority;

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
      labelSlotsUsed: _goals.where((g) => g.active && !g.isGroup).length,
      asOf: asOf,
      minutesByStatuses: minutesByStatuses,
      minutesByPriority: minutesByPriority,
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
