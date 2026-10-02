/// A goal: something the user is working toward, mirroring the Time Tracker
/// MCP server's `Goal`. Goals form a tree through [parentId], and each
/// active goal colors its events through a calendar label.
///
/// Only the fields the app uses so far are typed; everything the server
/// sent stays in [properties].
class Goal {
  const Goal({
    this.id,
    this.parentId,
    this.name,
    this.active = true,
    this.backgroundColor,
    this.priority,
    this.fixedTime,
    this.cadence,
    this.path,
    this.properties = const {},
  });

  final String? id;

  /// The goal this is a sub-goal of; null for a top-level goal.
  final String? parentId;
  final String? name;

  /// Whether the user is still working on it. Only active goals take up a
  /// calendar label.
  final bool active;

  /// Its label's color, e.g. "#a4bdfc"; null to follow its priority.
  final String? backgroundColor;
  final int? priority;

  /// Whether its events stay at their set time; null if it doesn't say.
  final bool? fixedTime;

  /// How often its health is assessed: daily, weekly, monthly or
  /// every_2_months; null if it never is.
  final String? cadence;

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
    active: json['active'] != false,
    backgroundColor: json['background_color'] as String?,
    priority: json['priority'] as int?,
    fixedTime: json['fixed_time'] as bool?,
    cadence: json['cadence'] as String?,
    path: json['path'] as String?,
    properties: Map.unmodifiable(json),
  );
}

/// The goals, and how many of the calendar's event labels they use.
class GoalList {
  const GoalList({
    required this.goals,
    this.labelSlotsUsed = 0,
    this.labelSlotsTotal = 200,
  });

  /// Parents before their children.
  final List<Goal> goals;
  final int labelSlotsUsed;
  final int labelSlotsTotal;

  factory GoalList.fromJson(Map<String, dynamic> json) => GoalList(
    goals: [
      for (final goal in json['goals'] as List)
        Goal.fromJson((goal as Map).cast<String, dynamic>()),
    ],
    labelSlotsUsed: json['label_slots_used'] as int? ?? 0,
    labelSlotsTotal: json['label_slots_total'] as int? ?? 200,
  );
}

/// [goal]'s name, or "(no name)".
String goalName(Goal goal) {
  final name = goal.name;
  return name == null || name.isEmpty ? '(no name)' : name;
}

/// The cadences a goal can have, as the server names them, and as the app
/// shows them.
const cadences = {
  'daily': 'Daily',
  'weekly': 'Weekly',
  'monthly': 'Monthly',
  'every_2_months': 'Every 2 months',
};
