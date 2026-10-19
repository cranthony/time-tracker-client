import 'scoring.dart';
import 'trait.dart';

/// What compaction changed in one of a person's trait facts, logged on
/// the event whose notes showed it: one of `get_fact_logs`'
/// `LoggedChange`s.
class FactLog {
  const FactLog({
    this.eventId,
    this.eventSummary,
    this.eventStart,
    required this.traitId,
    required this.factId,
    required this.log,
    this.loggedAt,
  });

  final String? eventId;
  final String? eventSummary;
  final DateTime? eventStart;
  final String traitId;
  final String factId;
  final String log;
  final DateTime? loggedAt;

  factory FactLog.fromJson(Map<String, dynamic> json) {
    DateTime? time(Object? value) =>
        value is String ? DateTime.tryParse(value)?.toLocal() : null;
    return FactLog(
      eventId: json['event_id'] as String?,
      eventSummary: json['event_summary'] as String?,
      eventStart: time(json['event_start']),
      traitId: json['trait_id'] as String? ?? '',
      factId: json['fact_id'] as String? ?? '',
      log: json['log'] as String? ?? '',
      loggedAt: time(json['logged_at']),
    );
  }
}

/// [changes] to person [id] as `update_person` takes them: their trait
/// facts' summaries (`facts`, {trait id: {fact id: summary}}) beside the
/// person, the rest under "person" -- a null going in clear_fields --
/// with the [version] last seen.
Map<String, Object?> personUpdate(
  String id,
  Map<String, Object?> changes, {
  int? version,
}) {
  final fields = {...changes}..remove('facts');
  final clear = [
    for (final MapEntry(:key, :value) in fields.entries)
      if (value == null) key,
  ];
  return {
    'person': {
      'id': id,
      for (final MapEntry(:key, :value) in fields.entries) key: ?value,
      'version': ?version,
    },
    if (clear.isNotEmpty) 'clear_fields': clear,
    'facts': ?changes['facts'],
  };
}

/// Who the user wants to be with, mirroring the Time Tracker MCP server's
/// `ListedPerson` (its utilities/people.py): a person, who can belong to
/// any number of [Circle]s. "Self" is always one of them ([selfPersonId]),
/// first, even when no one else is.
///
/// Unlike actions, people don't take up the calendar's event labels: an
/// event says who it was with and for in its facts (see facts.dart).
class Person {
  const Person({
    required this.id,
    required this.name,
    this.context,
    this.status = 'active',
    this.circleIds = const [],
    this.facts = const {},
    this.traits = const PersonTraits(),
    this.foundations,
    this.cancelledEvents = const [],
  });

  final String id;
  final String name;

  /// What tells them apart from others of the same name, e.g. "met at
  /// salsa": a name and context together are unique.
  final String? context;

  /// One of [personStatuses]' keys. Self is always active.
  final String status;

  /// The circles they're in, by id: any number of them.
  final List<String> circleIds;

  /// Their summary of each trait fact, by trait id and then fact id
  /// (see [TraitFact]): what each trait keeps about them, for its
  /// judgments, as compaction (or the user) last wrote it. Markdown. Only
  /// those that say anything; edited apart from them, with
  /// `update_person`'s `facts`.
  final Map<String, Map<String, String>> facts;

  /// Their summary of [trait]'s fact [factId], if they have one.
  String? summary(String trait, String factId) =>
      switch (facts[trait]?[factId]) {
        final text? when text.trim().isNotEmpty => text,
        _ => null,
      };

  /// Which traits apply to them, and their own parts for any.
  final PersonTraits traits;

  /// What their relationship is built on, on the habit graph: habits, by
  /// `habit:<id>`, and people, by id. Null when they aren't on it; empty
  /// when they are, built on nothing.
  final List<String>? foundations;

  /// Whether they're on the habit graph by themselves.
  bool get onHabitGraph => foundations != null;

  /// The events the user cancelled that count against their
  /// follow-through, newest first, as the server recorded them: not sent
  /// back.
  final List<CancelledEvent> cancelledEvents;

  /// Them, with [events] as their cancellations: what the server keeps
  /// apart from them, kept through an edit.
  Person withCancelledEvents(List<CancelledEvent> events) => Person(
    id: id,
    name: name,
    context: context,
    status: status,
    circleIds: circleIds,
    facts: facts,
    traits: traits,
    foundations: foundations,
    cancelledEvents: events,
  );

  bool get isSelf => id == selfPersonId;
  bool get active => status == 'active';

  factory Person.fromJson(Map<String, dynamic> json) => Person(
    id: json['id'] as String,
    name: json['name'] as String? ?? '',
    context: _text(json['context']),
    status: json['status'] as String? ?? 'active',
    circleIds: [for (final id in json['circles'] as List? ?? const []) '$id'],
    facts: {
      if (json['facts'] case final Map byTrait)
        for (final MapEntry(:key, :value) in byTrait.entries)
          if (value is Map)
            '$key': {
              for (final MapEntry(key: fact, value: text) in value.entries)
                if (text is String) '$fact': text,
            },
    },
    traits: PersonTraits.fromJson(json['traits']),
    foundations: switch (json['foundations']) {
      final List items => [for (final f in items) '$f'],
      _ => null,
    },
    cancelledEvents: [
      for (final e in json['cancelled_events'] as List? ?? const [])
        ?CancelledEvent.fromJson(e),
    ],
  );

  /// As `create_person` and `update_person` take them: only what the
  /// server keeps.
  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'context': ?context,
    'status': status,
    'circles': circleIds,
    if (!traits.isDefault) 'traits': traits.toJson(),
    'foundations': ?foundations,
  };
}

/// An event the user cancelled, as it counts against one person's
/// follow-through: one of the server's `CancelledEvent`s (its
/// utilities/people.py), recorded when a compaction found it didn't
/// happen, or it was deleted as counting against them.
class CancelledEvent {
  const CancelledEvent({
    this.eventId,
    this.summary,
    required this.start,
    required this.end,
    this.actionIds = const [],
    this.engagement = 'with',
    this.parts = const [],
    this.cancelledAt,
    this.source,
  });

  final String? eventId;
  final String? summary;

  /// When it was planned.
  final DateTime start;
  final DateTime end;

  /// What was to be done at it.
  final List<String> actionIds;

  /// "with" (they were to be there) or "for" (it was to be done for them
  /// while they weren't).
  final String engagement;

  /// The follow-through parts it counted against when it was recorded,
  /// `"trait id/part key"`.
  final List<String> parts;

  final DateTime? cancelledAt;

  /// What cancelled it: `"compaction <id>"`, or `"delete_event"`.
  final String? source;

  /// The ids of the traits it counted against, each once.
  List<String> get traitIds =>
      {for (final part in parts) part.split('/').first}.toList();

  /// Whether a compaction found it didn't happen, rather than its being
  /// deleted.
  bool get byCompaction => source?.startsWith('compaction') ?? false;

  /// One from the server; null without when it was planned.
  static CancelledEvent? fromJson(Object? json) {
    if (json is! Map) return null;
    DateTime? time(Object? value) =>
        value is String ? DateTime.tryParse(value)?.toLocal() : null;
    final start = time(json['start']);
    if (start == null) return null;
    return CancelledEvent(
      eventId: json['event_id'] as String?,
      summary: json['summary'] as String?,
      start: start,
      end: time(json['end']) ?? start,
      actionIds: [
        for (final id in json['action_ids'] as List? ?? const []) '$id',
      ],
      engagement: json['engagement'] == 'for' ? 'for' : 'with',
      parts: [for (final p in json['parts'] as List? ?? const []) '$p'],
      cancelledAt: time(json['cancelled_at']),
      source: json['source'] as String?,
    );
  }
}

/// Which traits apply to a person, and their own parts for any, as the
/// server's `traits` field has it: {"select": "all" or [trait ids],
/// "parts": {trait id: [parts]}, "facts": {trait id: {fact id:
/// prompts}}}.
class PersonTraits {
  const PersonTraits({
    this.select,
    this.parts = const {},
    this.partScoring = const {},
    this.scoring,
    this.facts = const {},
  });

  /// Their own prompts for a trait's facts, by trait id and then fact
  /// id: kept for a trait that doesn't apply to them too. Only a
  /// person's, not a habit's.
  final Map<String, Map<String, FactPromptOverride>> facts;

  /// Their own prompts for [traitId]'s fact [factId], if they have any.
  FactPromptOverride? factPrompts(String traitId, String factId) =>
      facts[traitId]?[factId];

  /// These, with their own prompts for [traitId]'s fact [factId] as
  /// [prompts] -- none, with null or empty ones.
  PersonTraits withFactPrompts(
    String traitId,
    String factId,
    FactPromptOverride? prompts,
  ) {
    final byFact = {...?facts[traitId]};
    if (prompts == null || prompts.isEmpty) {
      byFact.remove(factId);
    } else {
      byFact[factId] = prompts;
    }
    return PersonTraits(
      select: select,
      parts: parts,
      partScoring: partScoring,
      scoring: scoring,
      facts: {
        for (final MapEntry(:key, :value) in facts.entries)
          if (key != traitId) key: value,
        if (byFact.isNotEmpty) traitId: byFact,
      },
    );
  }

  /// The traits that apply to them, by id; null for every active one.
  final List<String>? select;

  /// Their own parts for a trait, replacing the trait's for them alone:
  /// their own cadence, say.
  final Map<String, List<Part>> parts;

  /// How a trait's parts combine for them alone, by trait id, in place of
  /// the trait's own scoring: weights by part id (their own parts', if
  /// they have them).
  final Map<String, Aggregation> partScoring;

  /// How their traits combine into their score, in place of the
  /// defaults': weights by trait id.
  final Aggregation? scoring;

  /// Whether it's as for everyone: every active trait, with its parts,
  /// combined as everyone's are.
  bool get isDefault =>
      select == null &&
      parts.isEmpty &&
      partScoring.isEmpty &&
      scoring == null &&
      facts.isEmpty;

  /// Whether [traitId] applies to them, if it's active.
  bool applies(String traitId) => select?.contains(traitId) ?? true;

  factory PersonTraits.fromJson(Object? json) {
    if (json is! Map) return const PersonTraits();
    return PersonTraits(
      select: switch (json['select']) {
        final List ids => [for (final id in ids) '$id'],
        _ => null,
      },
      parts: {
        for (final MapEntry(:key, :value)
            in (json['parts'] as Map? ?? const {}).entries)
          if (value is List)
            '$key': [
              for (final part in value)
                if (part is Map) Map<String, Object?>.of(part.cast()),
            ],
      },
      partScoring: {
        for (final MapEntry(:key, :value)
            in (json['part_scoring'] as Map? ?? const {}).entries)
          '$key': ?Aggregation.fromJson(value),
      },
      scoring: Aggregation.fromJson(json['scoring']),
      facts: {
        for (final MapEntry(:key, :value)
            in (json['facts'] as Map? ?? const {}).entries)
          if (value is Map)
            if ({
                  for (final MapEntry(key: fact, value: prompts)
                      in value.entries)
                    if (FactPromptOverride.fromJson(prompts) case final o?
                        when !o.isEmpty)
                      '$fact': o,
                }
                case final byFact when byFact.isNotEmpty)
              '$key': byFact,
      },
    );
  }

  Map<String, Object?> toJson() => {
    'select': select ?? 'all',
    if (parts.isNotEmpty) 'parts': parts,
    if (partScoring.isNotEmpty)
      'part_scoring': {
        for (final MapEntry(:key, :value) in partScoring.entries)
          key: value.toJson(),
      },
    'scoring': ?scoring?.toJson(),
    if (facts.isNotEmpty)
      'facts': {
        for (final MapEntry(:key, :value) in facts.entries)
          key: {
            for (final MapEntry(key: fact, value: prompts) in value.entries)
              fact: prompts.toJson(),
          },
      },
  };
}

/// One of a person's own prompts for a trait fact: its [text], in place
/// of the trait's prompt, or -- [append] -- after it.
class PromptOverride {
  const PromptOverride(this.text, {this.append = false});

  final String text;
  final bool append;

  static PromptOverride? fromJson(Object? json) => switch (json) {
    {'text': final String text} when text.trim().isNotEmpty => PromptOverride(
      text,
      append: json['how'] == 'append',
    ),
    _ => null,
  };

  Map<String, Object?> toJson() => {
    'text': text,
    'how': append ? 'append' : 'replace',
  };

  /// The prompt it makes of the trait's [prompt]: its text in place of
  /// it, or after it (alone when the trait has none).
  String applied(String? prompt) =>
      append && prompt != null && prompt.trim().isNotEmpty
      ? '$prompt\n\n$text'
      : text;

  @override
  bool operator ==(Object other) =>
      other is PromptOverride && other.text == text && other.append == append;

  @override
  int get hashCode => Object.hash(text, append);
}

/// A person's own prompts for one trait fact, as their traits' `facts`
/// keep them: each optional, null for the trait's.
class FactPromptOverride {
  const FactPromptOverride({this.summaryPrompt, this.logPrompt});

  final PromptOverride? summaryPrompt;
  final PromptOverride? logPrompt;

  bool get isEmpty => summaryPrompt == null && logPrompt == null;

  static FactPromptOverride? fromJson(Object? json) => json is Map
      ? FactPromptOverride(
          summaryPrompt: PromptOverride.fromJson(json['summary_prompt']),
          logPrompt: PromptOverride.fromJson(json['log_prompt']),
        )
      : null;

  Map<String, Object?> toJson() => {
    'summary_prompt': ?summaryPrompt?.toJson(),
    'log_prompt': ?logPrompt?.toJson(),
  };

  @override
  bool operator ==(Object other) =>
      other is FactPromptOverride &&
      other.summaryPrompt == summaryPrompt &&
      other.logPrompt == logPrompt;

  @override
  int get hashCode => Object.hash(summaryPrompt, logPrompt);
}

/// A named group of people -- family, dance friends, work -- mirroring
/// the server's `ListedCircle`. People can be in more than one.
class Circle {
  const Circle({
    required this.id,
    required this.name,
    this.note,
    this.scoring,
    this.memberIds = const [],
  });

  final String id;
  final String name;
  final String? note;

  /// How its people's scores combine into its own, in place of the
  /// defaults': weights by person id.
  final Aggregation? scoring;

  /// The people in it, as the server lists them.
  final List<String> memberIds;

  factory Circle.fromJson(Map<String, dynamic> json) => Circle(
    id: json['id'] as String,
    name: json['name'] as String? ?? '',
    note: _text(json['note']),
    scoring: Aggregation.fromJson(json['scoring']),
    memberIds: [
      for (final id in json['member_ids'] as List? ?? const []) '$id',
    ],
  );

  /// As `create_circle` and `update_circle` take it.
  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'note': ?note,
    'scoring': ?scoring?.toJson(),
  };
}

/// A place events happen -- home, the salsa studio -- with a hint for
/// recognizing when an event or note refers to it, and where it is on a
/// map, mirroring the server's `Location` (its stores/locations.rs).
class Location {
  const Location({
    required this.id,
    required this.name,
    this.hint,
    this.mapLocation,
    this.groupId,
    this.path,
  });

  final String id;
  final String name;

  /// Other names for it, an address, what happens there: "the apartment;
  /// 'home', 'my place'".
  final String? hint;

  /// Where it is, as a maps app would find it -- an address, a place's
  /// name, or a link -- opened for an event there with no map location
  /// of its own.
  final String? mapLocation;

  /// The location group it's in, if any.
  final String? groupId;

  /// Its name after its groups' ("New York › Brooklyn › Home"), as the
  /// server lists it; null where it isn't listed so.
  final String? path;

  factory Location.fromJson(Map<String, dynamic> json) => Location(
    id: json['id'] as String,
    name: json['name'] as String? ?? '',
    hint: _text(json['hint']),
    mapLocation: _text(json['map_location']),
    groupId: _text(json['group_id']),
    path: _text(json['path']),
  );

  /// As `create_location` and `update_location` take it: without its
  /// path, which is the server's to work out.
  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'hint': ?hint,
    'map_location': ?mapLocation,
    'group_id': ?groupId,
  };
}

/// A group of locations -- a neighborhood, a city -- inside another, if
/// it has a [groupId], mirroring the server's `LocationGroup`. A location
/// is in at most one.
class LocationGroup {
  const LocationGroup({
    required this.id,
    required this.name,
    this.groupId,
    this.note,
    this.path,
  });

  final String id;
  final String name;

  /// The group it's inside, if any.
  final String? groupId;
  final String? note;

  /// Its name after the groups it's inside ("New York › Brooklyn").
  final String? path;

  factory LocationGroup.fromJson(Map<String, dynamic> json) => LocationGroup(
    id: json['id'] as String,
    name: json['name'] as String? ?? '',
    groupId: _text(json['group_id']),
    note: _text(json['note']),
    path: _text(json['path']),
  );

  /// As `create_location_group` and `update_location_group` take it.
  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'group_id': ?groupId,
    'note': ?note,
  };
}

/// [groups]' and their ancestors' ids, from [id] out: the groups a
/// location or group in [id] is inside, nearest first. Stops at a group
/// that isn't there, or one already passed.
List<String> enclosingGroupIds(String? id, List<LocationGroup> groups) {
  final out = <String>[];
  var next = id;
  while (next != null && !out.contains(next)) {
    final current = next;
    final group = groups.where((g) => g.id == current).firstOrNull;
    if (group == null) break;
    out.add(group.id);
    next = group.groupId;
  }
  return out;
}

/// [name] after the names of the groups [groupId] is inside, outermost
/// first ("New York › Brooklyn › Home").
String groupPath(String name, String? groupId, List<LocationGroup> groups) =>
    [?groupsPath(groupId, groups), name].join(' › ');

/// The names of group [groupId] and the groups it's inside, outermost
/// first ("New York › Brooklyn"); null for none.
String? groupsPath(String? groupId, List<LocationGroup> groups) {
  final names = [
    for (final id in enclosingGroupIds(groupId, groups).reversed)
      groups.firstWhere((g) => g.id == id).name,
  ];
  return names.isEmpty ? null : names.join(' › ');
}

/// What tells [location] apart in a list: the groups it's in, and its
/// hint; null if it has neither.
String? locationDetail(Location location, List<LocationGroup> groups) {
  final detail = [?groupsPath(location.groupId, groups), ?location.hint];
  return detail.isEmpty ? null : detail.join(' · ');
}

/// Everyone, and their circles.
class PeopleList {
  const PeopleList({this.people = const [], this.circles = const []});

  /// Self first, then everyone else, as the server lists them.
  final List<Person> people;
  final List<Circle> circles;

  /// Self, as the server has them, or as they are before they've ever
  /// been changed.
  Person get self => people.where((p) => p.isSelf).firstOrNull ?? defaultSelf;

  /// [people], with Self first whether or not they were listed.
  List<Person> get withSelf => [
    self,
    for (final person in people)
      if (!person.isSelf) person,
  ];

  /// The people in [circleId].
  List<Person> inCircle(String circleId) => [
    for (final person in people)
      if (person.circleIds.contains(circleId)) person,
  ];
}

/// The id of the user themself, who's always among the people.
const selfPersonId = 'self';

/// Self, before they've been changed.
const defaultSelf = Person(id: selfPersonId, name: 'Self');

/// The statuses a person can have, as the server names them, and as the
/// app shows them.
const personStatuses = {
  'active': 'Active',
  'archived': 'Archived',
  'deleted': 'Deleted',
};

/// [person]'s name, or "(no name)", with their context if they have one:
/// "Sam (from salsa)".
String personName(Person person, {bool context = false}) {
  final name = person.name.isEmpty ? '(no name)' : person.name;
  return context && person.context != null ? '$name (${person.context})' : name;
}

String? _text(Object? value) =>
    value is String && value.trim().isNotEmpty ? value : null;
