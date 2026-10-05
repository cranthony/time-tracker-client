/// An action -- a verb for what the user is doing in a given moment -- or
/// a group of them, mirroring the Time Tracker MCP server's `Goal`, which
/// actions are kept as. They form a tree through [parentId]: groups are
/// names that roll up the actions under them, for targets, and actions are
/// always its leaves. Only an active action colors its events through a
/// calendar label; a group can't be given to an event.
///
/// Only the fields the app uses so far are typed; everything the server
/// sent stays in [properties].
class Goal {
  const Goal({
    this.id,
    this.parentId,
    this.name,
    this.status = 'active',
    this.backgroundColor,
    this.priority,
    this.measure,
    this.effectiveColor,
    this.effectivePriority,
    this.health,
    this.healthPeriod,
    this.healthTrend = const [],
    this.staleDays,
    this.minutes24h,
    this.minutes7d,
    this.minutesByStatuses,
    this.path,
    this.properties = const {},
  });

  final String? id;

  /// The goal this is a sub-goal of; null for a top-level goal.
  final String? parentId;
  final String? name;

  /// Where it stands: one of [goalStatuses]. Only active goals take up a
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

  /// Whether it's the overall goal, above every other: see
  /// [overallGoalId].
  bool get isOverall => id == overallGoalId;

  /// Its label's color, e.g. "#a4bdfc"; null to follow its priority.
  final String? backgroundColor;
  final int? priority;

  /// How its health is rated in each day's reflection, e.g. {"kind":
  /// "duration", "target_min": 600}; null if it isn't measured (then it's
  /// rated by its sub-goals', if any are). See measure.dart.
  final Map<String, Object?>? measure;

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

  /// Its latest confirmed rating (0-100), if it's had one.
  final int? health;

  /// The latest day it was rated for, e.g. "2026-09-30".
  final String? healthPeriod;

  /// Its last 8 days' ratings, oldest first; null for a day with none.
  final List<int?> healthTrend;

  /// How many days have ended unrated since it was last rated; null unless
  /// it's rated (it's active, with a measure or rated sub-goals).
  final int? staleDays;

  /// Minutes spent on it and its sub-goals in the 24 hours up to
  /// [GoalList.asOf]; null without one.
  final int? minutes24h;

  /// The same, over the 7 days up to [GoalList.asOf].
  final int? minutes7d;

  /// [minutes24h] and [minutes7d], split by the statuses of the goals each
  /// event was given among this one and its sub-goals; null from a server
  /// too old to say, or without a [GoalList.asOf].
  final List<StatusMinutes>? minutesByStatuses;

  /// Its minutes in the last 24 hours and 7 days through goals with any of
  /// [statuses] (itself or its sub-goals), each event once: its time,
  /// filtered as the Goals page is. Null if it isn't known.
  (int, int)? timeFor(Set<String> statuses) =>
      _timeFor(minutesByStatuses, statuses);

  /// Its names from the top of the tree down, e.g. "Cooking › Tofu".
  final String? path;

  /// The goal as the server sent it.
  final Map<String, dynamic> properties;

  /// How deep in the tree it is: 0 for a top-level goal.
  int get depth => (path ?? '').split(' › ').length - 1;

  factory Goal.fromJson(Map<String, dynamic> json) => Goal(
    id: json['id'] as String?,
    parentId: json['parent_id'] as String?,
    name: json['name'] as String?,
    status:
        json['status'] as String? ??
        // A server from before statuses.
        (json['active'] == false ? 'archived' : 'active'),
    backgroundColor: json['background_color'] as String?,
    priority: json['priority'] as int?,
    measure: switch (json['measure']) {
      final Map measure => Map.unmodifiable(measure.cast<String, Object?>()),
      _ => null,
    },
    effectiveColor: json['effective_color'] as String?,
    effectivePriority:
        json['effective_priority'] as int? ?? json['priority'] as int?,
    health: json['health'] as int?,
    healthPeriod: json['health_period'] as String?,
    healthTrend: [
      for (final cell
          in ((json['health_trend'] as String?) ?? '')
              .split(',')
              .where((c) => c.isNotEmpty))
        int.tryParse(cell),
    ],
    staleDays: json['stale_days'] as int?,
    minutes24h: json['minutes_24h'] as int?,
    minutes7d: json['minutes_7d'] as int?,
    minutesByStatuses: _statusMinutes(json['minutes_by_statuses']),
    path: json['path'] as String?,
    properties: Map.unmodifiable(json),
  );

  /// The goal as [Goal.fromJson] takes it: what the server sent, with the
  /// typed fields over it.
  Map<String, Object?> toJson() => {
    ...properties,
    'id': id,
    'parent_id': parentId,
    'name': name,
    'status': status,
    'background_color': backgroundColor,
    'priority': priority,
    'measure': measure,
    'effective_color': effectiveColor,
    'effective_priority': effectivePriority,
    'health': health,
    'health_period': healthPeriod,
    'health_trend': healthTrend.map((r) => r?.toString() ?? '-').join(','),
    'stale_days': staleDays,
    'minutes_24h': minutes24h,
    'minutes_7d': minutes7d,
    'minutes_by_statuses': minutesByStatuses?.map((m) => m.toJson()).toList(),
  };
}

/// The overall goal's id: the goal above every other, whose sub-goals are
/// implied to be every top-level goal. It's rated like any goal, holds no
/// label, and can't be given to an event.
const overallGoalId = 'overall';

/// The time spent on events whose goals have exactly these [statuses]
/// between them, as the server splits it: see [GoalList.timeFor].
class StatusMinutes {
  const StatusMinutes({
    required this.statuses,
    required this.minutes24h,
    required this.minutes7d,
  });

  final Set<String> statuses;
  final int minutes24h;
  final int minutes7d;

  factory StatusMinutes.fromJson(Map<String, dynamic> json) => StatusMinutes(
    statuses: {...(json['statuses'] as List).cast<String>()},
    minutes24h: json['minutes_24h'] as int? ?? 0,
    minutes7d: json['minutes_7d'] as int? ?? 0,
  );

  Map<String, Object?> toJson() => {
    'statuses': [...statuses],
    'minutes_24h': minutes24h,
    'minutes_7d': minutes7d,
  };
}

List<StatusMinutes>? _statusMinutes(Object? json) => switch (json) {
  final List split => [
    for (final part in split)
      StatusMinutes.fromJson((part as Map).cast<String, dynamic>()),
  ],
  _ => null,
};

/// The time in the last 24 hours and 7 days that went to a [priority], as
/// the server splits it: each moment goes to the highest priority among
/// the events then, each event's own or else its goals'. Null [priority]
/// is the rest: no event, or none with a priority. A window's parts add
/// up to the whole window.
class PriorityMinutes {
  const PriorityMinutes({
    required this.priority,
    required this.minutes24h,
    required this.minutes7d,
  });

  final int? priority;
  final int minutes24h;
  final int minutes7d;

  factory PriorityMinutes.fromJson(Map<String, dynamic> json) =>
      PriorityMinutes(
        priority: json['priority'] as int?,
        minutes24h: json['minutes_24h'] as int? ?? 0,
        minutes7d: json['minutes_7d'] as int? ?? 0,
      );

  Map<String, Object?> toJson() => {
    'priority': priority,
    'minutes_24h': minutes24h,
    'minutes_7d': minutes7d,
  };
}

/// The minutes in [split] whose statuses include any of [statuses]; null
/// without a [split].
(int, int)? _timeFor(List<StatusMinutes>? split, Set<String> statuses) {
  if (split == null) return null;
  var (day, week) = (0, 0);
  for (final part in split) {
    if (part.statuses.any(statuses.contains)) {
      day += part.minutes24h;
      week += part.minutes7d;
    }
  }
  return (day, week);
}

/// The goals, and how many of the calendar's event labels they use.
class GoalList {
  const GoalList({
    required this.goals,
    this.labelSlotsUsed = 0,
    this.labelSlotsTotal = 200,
    this.asOf,
    this.minutesByStatuses,
    this.minutesByPriority,
  });

  /// Parents before their children.
  final List<Goal> goals;
  final int labelSlotsUsed;
  final int labelSlotsTotal;

  /// When notes were last compacted into the calendar, which each goal's
  /// recent time is counted up to; null if they never have been.
  final DateTime? asOf;

  /// The time spent on any goal up to [asOf], split by the statuses of
  /// the goals each event was given: the overall goal's
  /// [Goal.minutesByStatuses]. Null from a server too old to say, or
  /// without an [asOf].
  final List<StatusMinutes>? minutesByStatuses;

  /// The last 24 hours and 7 days up to [asOf], split by priority. Null
  /// from a server too old to say, or without an [asOf].
  final List<PriorityMinutes>? minutesByPriority;

  /// The overall goal, if the server has one.
  Goal? get overall => goals.where((g) => g.isOverall).firstOrNull;

  /// The minutes spent on goals with any of [statuses] in the last 24
  /// hours and 7 days, each event once; null if it isn't known.
  (int, int)? timeFor(Set<String> statuses) =>
      _timeFor(minutesByStatuses, statuses);

  factory GoalList.fromJson(Map<String, dynamic> json) => GoalList(
    goals: [
      for (final goal in json['goals'] as List)
        Goal.fromJson((goal as Map).cast<String, dynamic>()),
    ],
    labelSlotsUsed: json['label_slots_used'] as int? ?? 0,
    labelSlotsTotal: json['label_slots_total'] as int? ?? 200,
    asOf: switch (json['as_of']) {
      final String asOf => DateTime.tryParse(asOf),
      _ => null,
    },
    minutesByStatuses: _statusMinutes(json['minutes_by_statuses']),
    minutesByPriority: switch (json['minutes_by_priority']) {
      final List split => [
        for (final part in split)
          PriorityMinutes.fromJson((part as Map).cast<String, dynamic>()),
      ],
      _ => null,
    },
  );
}

/// [goal]'s name, or "(no name)".
String goalName(Goal goal) {
  final name = goal.name;
  return name == null || name.isEmpty ? '(no name)' : name;
}

/// The statuses an action can have, as the server names them, and as the
/// app shows them. Proposed is one Claude made, for the user to review.
const goalStatuses = {
  'proposed': 'Proposed',
  'active': 'Active',
  'archived': 'Archived',
  'deleted': 'Deleted',
};

/// The statuses the Plan page shows until told otherwise: the actions in
/// play.
const defaultGoalStatuses = {'proposed', 'active'};
