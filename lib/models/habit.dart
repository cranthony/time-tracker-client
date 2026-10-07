import 'person.dart';
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
class Habit {
  const Habit({
    required this.id,
    required this.name,
    required this.actionId,
    this.actionPath,
    this.status = 'active',
    this.note,
    this.traits = const PersonTraits(),
    this.cancelledEvents = const [],
  });

  final String id;
  final String name;

  /// The action, or group of actions, whose events it's about.
  final String actionId;

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
    actionPath: actionPath,
    status: status,
    note: note,
    traits: traits,
    cancelledEvents: events,
  );

  factory Habit.fromJson(Map<String, dynamic> json) => Habit(
    id: json['id'] as String,
    name: json['name'] as String? ?? '',
    actionId: json['action_id'] as String? ?? '',
    actionPath: json['action_path'] as String?,
    status: json['status'] as String? ?? 'active',
    note: switch (json['note']) {
      final String note when note.trim().isNotEmpty => note,
      _ => null,
    },
    traits: PersonTraits.fromJson(json['traits']),
    cancelledEvents: [
      for (final e in json['cancelled_events'] as List? ?? const [])
        ?CancelledEvent.fromJson(e),
    ],
  );

  /// As `create_habit` and `update_habit` take it: only what the server
  /// keeps.
  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'action_id': actionId,
    'status': status,
    'note': ?note,
    if (!traits.isDefault) 'traits': traits.toJson(),
  };
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
