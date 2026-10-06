/// An action -- a verb for what the user is doing in a given moment -- or
/// a group of them, mirroring the Time Tracker MCP server's `PlanAction`, which
/// actions are kept as. They form a tree through [parentId]: groups are
/// names that roll up the actions under them, for targets, and actions are
/// always its leaves. Only an active action colors its events through a
/// calendar label; a group can't be given to an event.
///
/// Only the fields the app uses so far are typed; everything the server
/// sent stays in [properties].
class PlanAction {
  const PlanAction({
    this.id,
    this.parentId,
    this.name,
    this.status = 'active',
    this.backgroundColor,
    this.priority,
    this.effectiveColor,
    this.effectivePriority,
    this.path,
    this.properties = const {},
  });

  final String? id;

  /// The action this is a sub-action of; null for a top-level action.
  final String? parentId;
  final String? name;

  /// Where it stands: one of [actionStatuses]. Only active actions take up a
  /// calendar label.
  final String status;

  /// Whether it's in use, and so (unless it's a group) holds a calendar
  /// label.
  bool get active => status == 'active';

  /// Whether it's a group of actions, not an action: it can't be given to
  /// an event, and has no label of its own.
  bool get isGroup => properties['kind'] == 'group';

  /// Whether Claude made it, and the user hasn't looked at it yet.
  bool get proposed => status == 'proposed';

  /// Its label's color, e.g. "#a4bdfc"; null to follow its priority.
  final String? backgroundColor;
  final int? priority;

  /// The color its label is shown in: [backgroundColor], or the one it
  /// inherits from its priority or its parent. Null from a server too old
  /// to say.
  final String? effectiveColor;

  /// The priority its events take: [priority], or its nearest ancestor's;
  /// null if none of them has one. From a server too old to say, it's
  /// [priority].
  final int? effectivePriority;

  /// Whether [effectivePriority] comes from an ancestor, not its own.
  bool get inheritsPriority => priority == null && effectivePriority != null;

  /// Its names from the top of the tree down, e.g. "Cooking › Tofu".
  final String? path;

  /// The action as the server sent it.
  final Map<String, dynamic> properties;

  /// How deep in the tree it is: 0 for a top-level action.
  int get depth => (path ?? '').split(' › ').length - 1;

  factory PlanAction.fromJson(Map<String, dynamic> json) => PlanAction(
    id: json['id'] as String?,
    parentId: json['parent_id'] as String?,
    name: json['name'] as String?,
    status:
        json['status'] as String? ??
        // A server from before statuses.
        (json['active'] == false ? 'archived' : 'active'),
    backgroundColor: json['background_color'] as String?,
    priority: json['priority'] as int?,
    effectiveColor: json['effective_color'] as String?,
    effectivePriority:
        json['effective_priority'] as int? ?? json['priority'] as int?,
    path: json['path'] as String?,
    properties: Map.unmodifiable(json),
  );

  /// The action as [PlanAction.fromJson] takes it: what the server sent, with the
  /// typed fields over it.
  Map<String, Object?> toJson() => {
    ...properties,
    'id': id,
    'parent_id': parentId,
    'name': name,
    'status': status,
    'background_color': backgroundColor,
    'priority': priority,
    'effective_color': effectiveColor,
    'effective_priority': effectivePriority,
  };
}

/// The actions, and how many of the calendar's event labels they use.
class ActionList {
  const ActionList({
    required this.actions,
    this.labelSlotsUsed = 0,
    this.labelSlotsTotal = 200,
  });

  /// Parents before their children.
  final List<PlanAction> actions;
  final int labelSlotsUsed;
  final int labelSlotsTotal;

  factory ActionList.fromJson(Map<String, dynamic> json) => ActionList(
    actions: [
      for (final action in json['actions'] as List)
        PlanAction.fromJson((action as Map).cast<String, dynamic>()),
    ],
    labelSlotsUsed: json['label_slots_used'] as int? ?? 0,
    labelSlotsTotal: json['label_slots_total'] as int? ?? 200,
  );
}

/// [action]'s name, or "(no name)".
String actionName(PlanAction action) {
  final name = action.name;
  return name == null || name.isEmpty ? '(no name)' : name;
}

/// The statuses an action can have, as the server names them, and as the
/// app shows them. Proposed is one Claude made, for the user to review.
const actionStatuses = {
  'proposed': 'Proposed',
  'active': 'Active',
  'archived': 'Archived',
  'deleted': 'Deleted',
};

/// The statuses the Plan page shows until told otherwise: the actions in
/// play.
const defaultActionStatuses = {'proposed', 'active'};
