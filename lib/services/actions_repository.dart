import '../models/plan_action.dart';
import 'mcp_client.dart';
import 'response_cache.dart';

/// Where actions, and the groups they're in, come from: each a [PlanAction], a
/// group's [PlanAction.isGroup] set. The app talks to this rather than to MCP
/// directly so screens can be exercised without a server.
abstract class ActionsRepository {
  /// Whether siblings can be put in an order of their own.
  bool get reorderable;

  /// Every action, whatever its status, parents before their children.
  Future<ActionList> actions();

  /// What [actions] last returned, kept from an earlier run of the app; null
  /// if there's nothing kept.
  Future<ActionList?> cachedActions();

  /// Creates an action from [fields], keyed as `create_action` takes them.
  /// Returns its id, or null if it can't be told apart from the others.
  /// Call [actions] for every action as they are now: saving one after another,
  /// that's only needed after the last.
  Future<String?> createAction(Map<String, Object?> fields);

  /// Saves [changes], keyed as `update_action` takes them, to [action]; a null
  /// clears that property. Call [actions] for every action as they are now.
  Future<void> updateAction(PlanAction action, Map<String, Object?> changes);

  /// Puts sibling actions (sharing a parent), by id, in this order, among
  /// the places they hold. Returns every action, as [actions] does.
  Future<ActionList> reorderActions(List<String> ids);
}

/// Reads and writes actions and their groups via the Time Tracker MCP
/// server's action tools: `get_actions` and `get_action_groups`, listed
/// together as one tree, and `create_`/`update_action` or
/// `create_`/`update_action_group` for a group. They aren't kept in an
/// order of their own there yet.
class McpActionsRepository implements ActionsRepository {
  McpActionsRepository(this._client, {this._cache});

  final McpClient _client;
  final ResponseCache? _cache;

  static const _cacheKey = 'actions';

  @override
  bool get reorderable => false;

  @override
  Future<ActionList> actions() async {
    final actions = await _client.callTool('get_actions', {
      'statuses': actionStatuses.keys.toList(),
    });
    final groups = await _client.callTool('get_action_groups', {});
    final result = {'actions': actions, 'groups': groups};
    await _cache?.write(_cacheKey, result);
    return actionTree(result);
  }

  @override
  Future<ActionList?> cachedActions() async {
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
  Future<String?> createAction(Map<String, Object?> fields) async {
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
  Future<void> updateAction(
    PlanAction action,
    Map<String, Object?> changes,
  ) async {
    // The server keeps whatever is left out or null, and clears what
    // clear_fields names.
    final fields = _fields(changes, group: action.isGroup);
    final clear = [
      for (final MapEntry(:key, :value) in fields.entries)
        if (value == null) key,
    ];
    await _client.callTool(
      action.isGroup ? 'update_action_group' : 'update_action',
      {
        action.isGroup ? 'group' : 'action': {
          'id': action.id,
          for (final MapEntry(:key, :value) in fields.entries) key: ?value,
        },
        if (clear.isNotEmpty) 'clear_fields': clear,
      },
    );
  }

  @override
  Future<ActionList> reorderActions(List<String> ids) =>
      throw UnsupportedError("The server doesn't keep an order of its own.");
}

/// What `get_actions` and `get_action_groups` answered, as [result]'s
/// "actions" and "groups", as one tree: each group, then what's in it,
/// groups before actions.
ActionList actionTree(Object? result) {
  final json = (result as Map).cast<String, dynamic>();
  final list = (json['actions'] as Map).cast<String, dynamic>();
  final nodes = [
    for (final group in json['groups'] as List? ?? const [])
      PlanAction.fromJson({
        ...(group as Map).cast<String, dynamic>(),
        'parent_id': group['group_id'],
        'status': 'active',
        'kind': 'group',
      }),
    for (final action in list['actions'] as List? ?? const [])
      PlanAction.fromJson({
        ...(action as Map).cast<String, dynamic>(),
        'parent_id': action['group_id'],
      }),
  ];
  final ids = {for (final node in nodes) node.id};
  final children = <String?, List<PlanAction>>{};
  for (final node in nodes) {
    final parent = ids.contains(node.parentId) ? node.parentId : null;
    children.putIfAbsent(parent, () => []).add(node);
  }
  final ordered = <PlanAction>[];
  void visit(PlanAction node) {
    ordered.add(node);
    children[node.id]?.forEach(visit);
  }

  children[null]?.forEach(visit);
  return ActionList(
    actions: ordered,
    labelSlotsUsed: list['label_slots_used'] as int? ?? 0,
    labelSlotsTotal: list['label_slots_total'] as int? ?? 200,
  );
}

/// Keeps actions in memory. Used when no server is configured, and in
/// tests.
class InMemoryActionsRepository implements ActionsRepository {
  InMemoryActionsRepository([List<PlanAction> actions = const []])
    : _actions = [...actions];

  @override
  bool get reorderable => true;

  final List<PlanAction> _actions;
  int _nextId = 1;

  @override
  Future<ActionList> actions() async {
    final byParent = <String?, List<PlanAction>>{};
    for (final action in _actions) {
      byParent.putIfAbsent(action.parentId, () => []).add(action);
    }
    final ordered = <PlanAction>[];
    // Each with what it inherits, as the server gives it.
    void visit(PlanAction action, PlanAction? parent, String path) {
      final listed = PlanAction.fromJson({
        ...action.toJson(),
        'path': path,
        'effective_priority': action.priority ?? parent?.effectivePriority,
      });
      ordered.add(listed);
      for (final child in byParent[action.id] ?? const <PlanAction>[]) {
        visit(child, listed, '$path › ${actionName(child)}');
      }
    }

    for (final root in byParent[null] ?? const <PlanAction>[]) {
      visit(root, null, actionName(root));
    }
    return ActionList(
      actions: ordered,
      labelSlotsUsed: _actions.where((g) => g.active && !g.isGroup).length,
    );
  }

  @override
  Future<ActionList?> cachedActions() async => null;

  @override
  Future<ActionList> reorderActions(List<String> ids) async {
    final places = [
      for (final (i, action) in _actions.indexed)
        if (ids.contains(action.id)) i,
    ];
    final byId = {for (final action in _actions) action.id: action};
    for (var i = 0; i < places.length; i++) {
      _actions[places[i]] = byId[ids[i]]!;
    }
    return actions();
  }

  @override
  Future<String> createAction(Map<String, Object?> fields) async {
    final id = 'g${_nextId++}';
    _actions.add(
      PlanAction.fromJson({'status': 'active', ...fields, 'id': id}),
    );
    return id;
  }

  @override
  Future<void> updateAction(
    PlanAction action,
    Map<String, Object?> changes,
  ) async {
    final i = _actions.indexWhere((g) => g.id == action.id);
    if (i < 0) throw StateError('No action ${action.id}');
    _actions[i] = PlanAction.fromJson({..._actions[i].toJson(), ...changes});
  }
}
