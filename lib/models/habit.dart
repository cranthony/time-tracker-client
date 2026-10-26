import 'person.dart';
import 'recurring_goal.dart';
import 'trait.dart';

/// A habit of the user's (Self's), mirroring the Time Tracker MCP
/// server's `ListedHabit`: traits to be held to at the events of one
/// action, or of any action under one group -- practicing guitar
/// mindfully, say. Which events those are is worked out when they're
/// used, from the action tree as it is then.
///
/// The user is always at its events: its traits' parts that read events
/// done for someone (`engagement_type: for`) don't apply to it. Claude's
/// judgments for it are kept on events beside everyone's, under
/// [subject].
///
/// Or a person's or circle's habit ([personId], [circleId]): some of
/// their traits, as they're scored for them -- a layer of the
/// relationship on the habit graph. Its traits only pick which.
///
/// Or a recurring goal's ([recurringGoal]): a goal for each day, week or
/// month, made by the server; its events are those tagged with its goals,
/// and it's scored by its goal rate, and by its traits once it's given
/// some.
class Habit {
  const Habit({
    required this.id,
    required this.name,
    required this.actionId,
    this.personId,
    this.circleId,
    this.recurringGoal,
    this.defaultName,
    this.actionPath,
    this.status = 'active',
    this.note,
    this.traits = const PersonTraits(),
    this.foundations = const [],
    this.cancelledEvents = const [],
  });

  final String id;
  final String name;

  /// The action, or group of actions, whose events it's about; empty for
  /// a person's or circle's habit.
  final String actionId;

  /// For a person's habit, theirs.
  final String? personId;

  /// For a circle's habit, its.
  final String? circleId;

  /// For a recurring goal's habit, the goal made for each period.
  final RecurringGoal? recurringGoal;

  /// Whether it's a recurring goal's habit.
  bool get isGoal => recurringGoal != null;

  /// For a person's or circle's habit, the name it has without its own,
  /// as the server last said: [name], unless it has its own.
  final String? defaultName;

  /// Whether it's a person's or circle's habit.
  bool get isRelationship => personId != null || circleId != null;

  /// Whether its name is its own, not the default.
  bool get ownName => !isRelationship || name != defaultName;

  /// Its action's or group's name, under its groups, as the server last
  /// said: "Creative › Guitar". Not sent back.
  final String? actionPath;

  /// One of [habitStatuses]' keys.
  final String status;

  /// What it's for, which Claude judges its events with in mind.
  final String? note;

  /// Which traits apply to it, and its own parts for any: as a person's,
  /// every active trait unless it says.
  final PersonTraits traits;

  /// What it's built on, on the habit graph: other habits, by
  /// [habitSubject], and people, by id.
  final List<String> foundations;

  /// The events the user cancelled that count against its
  /// follow-through, newest first, as the server recorded them: not sent
  /// back.
  final List<CancelledEvent> cancelledEvents;

  bool get active => status == 'active';

  /// Who its judgments are of, on an event: `habit:<id>`.
  String get subject => habitSubject(id);

  /// It, with [events] as its cancellations: what the server keeps apart
  /// from it, kept through an edit.
  Habit withCancelledEvents(List<CancelledEvent> events) => Habit(
    id: id,
    name: name,
    actionId: actionId,
    personId: personId,
    circleId: circleId,
    recurringGoal: recurringGoal,
    defaultName: defaultName,
    actionPath: actionPath,
    status: status,
    note: note,
    traits: traits,
    foundations: foundations,
    cancelledEvents: events,
  );

  factory Habit.fromJson(Map<String, dynamic> json) => Habit(
    id: json['id'] as String,
    name: json['name'] as String? ?? '',
    actionId: json['action_id'] as String? ?? '',
    personId: _id(json['person_id']),
    circleId: _id(json['circle_id']),
    recurringGoal: RecurringGoal.fromJson(json['recurring_goal']),
    defaultName: _id(json['default_name']),
    actionPath: json['action_path'] as String?,
    status: json['status'] as String? ?? 'active',
    note: switch (json['note']) {
      final String note when note.trim().isNotEmpty => note,
      _ => null,
    },
    traits: PersonTraits.fromJson(json['traits']),
    foundations: [
      for (final f in json['foundations'] as List? ?? const []) '$f',
    ],
    cancelledEvents: [
      for (final e in json['cancelled_events'] as List? ?? const [])
        ?CancelledEvent.fromJson(e),
    ],
  );

  /// As `create_habit` and `update_habit` take it: only what the server
  /// keeps.
  Map<String, Object?> toJson() => {
    'id': id,
    // A person's or circle's habit given its default has none of its own.
    'name': name,
    if (!isRelationship && !isGoal) 'action_id': actionId,
    'person_id': ?personId,
    'circle_id': ?circleId,
    if (recurringGoal case final goal?) 'recurring_goal': goal.toJson(),
    'status': status,
    'note': ?note,
    if (!traits.isDefault) 'traits': traits.toJson(),
    if (foundations.isNotEmpty) 'foundations': foundations,
  };
}

String? _id(Object? value) => switch (value) {
  final String s when s.isNotEmpty => s,
  _ => null,
};

/// The most traits a relationship habit's name lists before "+N", as
/// the server names them.
const _namedTraits = 2;

/// The name a person's or circle's habit has without its own, as the
/// server gives it: [whose], then the traits [traits] picks, by
/// [traitNames] -- "Sam", "Sam · Reliable", "Sam · Reliable, Kind +1",
/// "Sam · except Reliable".
String relationshipHabitName(
  String whose,
  PersonTraits traits,
  Map<String, String> traitNames,
) {
  String listed(List<String> ids) {
    final named = ids.take(_namedTraits).map((id) => traitNames[id] ?? id);
    final more = ids.length - _namedTraits;
    return '${named.join(', ')}${more > 0 ? ' +$more' : ''}';
  }

  if (traits.select case final picked?) {
    final on = [
      for (final id in picked)
        if (!traits.except.contains(id)) id,
    ];
    return '$whose · ${listed(on)}';
  }
  if (traits.except.isEmpty) return whose;
  return '$whose · except ${listed(traits.except)}';
}

/// Who a habit's judgments are of, on an event: `habit:<id>`.
String habitSubject(String habitId) => 'habit:$habitId';

/// The habit [subject] names, by id; null if it names a person.
String? habitIdOf(String subject) =>
    subject.startsWith('habit:') ? subject.substring('habit:'.length) : null;

/// The statuses a habit can have, as the server names them, and as the
/// app shows them.
const habitStatuses = {
  'active': 'Active',
  'archived': 'Archived',
  'deleted': 'Deleted',
};

/// [habit]'s name, or "(no name)".
String habitName(Habit habit) => habit.name.isEmpty ? '(no name)' : habit.name;

/// Whether [actionId] is [scopeId], or under it: an event with it is one
/// of a habit on [scopeId]. [parentOf] gives an action's group.
bool inScope(
  String scopeId,
  String actionId,
  String? Function(String id) parentOf,
) {
  final seen = <String>{};
  for (String? at = actionId; at != null && seen.add(at); at = parentOf(at)) {
    if (at == scopeId) return true;
  }
  return false;
}

/// What's wrong, for a habit on [scopeId], with [parts] as its own: one
/// line each for a part that counts an action outside it, so counts
/// nothing, and for one that reads events done for someone, which a
/// habit has none of. [actionNames] names actions by id.
List<String> habitPartWarnings(
  List<Part> parts,
  String scopeId,
  String? Function(String id) parentOf, [
  Map<String?, String> actionNames = const {},
]) {
  String name(String id) => actionNames[id] ?? id;
  return [
    for (final part in parts) ...[
      if (part['action'] case final String action
          when action.isNotEmpty && !inScope(scopeId, action, parentOf))
        '${partKinds[part['kind']]?.label ?? part['kind']} of '
            '${name(action)}: outside ${name(scopeId)}, so it counts '
            'nothing here.',
      if (part['engagement_type'] == 'for')
        '${partKinds[part['kind']]?.label ?? part['kind']} reads events '
            "done for someone: you're at every one of a habit's, so it's "
            'left out.',
    ],
  ];
}
