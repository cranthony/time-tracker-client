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
/// with the [version] last seen. Foundations, which a person had before
/// they were on the habit graph by their habits, are let go of: one
/// still waiting to be sent from then isn't sent.
Map<String, Object?> personUpdate(
  String id,
  Map<String, Object?> changes, {
  int? version,
}) {
  final fields = {...changes}
    ..remove('facts')
    ..remove('foundations');
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

/// [changes] to circle [id] as `update_circle` takes them: a community's
/// trait facts' summaries (`facts`, {trait id: {fact id: summary}})
/// beside the circle, the rest under "circle" -- a null going in
/// clear_fields -- with the [version] last seen.
Map<String, Object?> circleUpdate(
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
    'circle': {
      'id': id,
      for (final MapEntry(:key, :value) in fields.entries) key: ?value,
      'version': ?version,
    },
    if (clear.isNotEmpty) 'clear_fields': clear,
    'facts': ?changes['facts'],
  };
}

/// Whom the traits judge and score as a subject of their own -- a
/// person, or a community: which traits apply to them, their summary of
/// each trait fact, and the events the user cancelled that count
/// against their follow-through. The server keeps judgments, trait facts
/// and cancellations by their id alike.
abstract interface class Judged {
  String get id;

  /// Whether they're scored.
  bool get active;

  /// Which traits apply to them, and their own parts for any.
  PersonTraits get traits;

  /// Their summary of each trait fact, by trait id and then fact id.
  Map<String, Map<String, String>> get facts;

  /// Their summary of [trait]'s fact [factId], if they have one.
  String? summary(String trait, String factId);

  /// The events the user cancelled that count against their
  /// follow-through, newest first.
  List<CancelledEvent> get cancelledEvents;
}

/// `facts` as the server lists a person's or a community's: {trait id:
/// {fact id: summary}}; empty for none.
Map<String, Map<String, String>> factsFromJson(Object? json) => {
  if (json case final Map byTrait)
    for (final MapEntry(:key, :value) in byTrait.entries)
      if (value is Map)
        '$key': {
          for (final MapEntry(key: fact, value: text) in value.entries)
            if (text is String) '$fact': text,
        },
};

/// Who the user wants to be with, mirroring the Time Tracker MCP server's
/// `ListedPerson` (its utilities/people.py): a person, who can belong to
/// any number of [Circle]s. "Self" is always one of them ([selfPersonId]),
/// first, even when no one else is.
///
/// Unlike actions, people don't take up the calendar's event labels: an
/// event says who it was with and for in its facts (see facts.dart).
class Person implements Judged {
  const Person({
    required this.id,
    required this.name,
    this.context,
    this.status = 'active',
    this.circleIds = const [],
    this.facts = const {},
    this.traits = const PersonTraits(),
    this.cancelledEvents = const [],
  });

  @override
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
  @override
  final Map<String, Map<String, String>> facts;

  @override
  String? summary(String trait, String factId) =>
      switch (facts[trait]?[factId]) {
        final text? when text.trim().isNotEmpty => text,
        _ => null,
      };

  @override
  final PersonTraits traits;

  /// The events the user cancelled that count against their
  /// follow-through, newest first, as the server recorded them: not sent
  /// back.
  @override
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
    cancelledEvents: events,
  );

  bool get isSelf => id == selfPersonId;

  @override
  bool get active => status == 'active';

  factory Person.fromJson(Map<String, dynamic> json) => Person(
    id: json['id'] as String,
    name: json['name'] as String? ?? '',
    context: _text(json['context']),
    status: json['status'] as String? ?? 'active',
    circleIds: [for (final id in json['circles'] as List? ?? const []) '$id'],
    facts: factsFromJson(json['facts']),
    traits: PersonTraits.fromJson(json['traits']),
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
/// "except": [trait ids], "parts": {trait id: [parts]}, "facts": {trait
/// id: {fact id: prompts}}}.
class PersonTraits {
  const PersonTraits({
    this.select,
    this.except = const [],
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
      except: except,
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

  /// Traits that don't apply to them, by id, though [select] has them:
  /// with every one selected, those added later apply.
  final List<String> except;

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
      except.isEmpty &&
      parts.isEmpty &&
      partScoring.isEmpty &&
      scoring == null &&
      facts.isEmpty;

  /// Whether [traitId] applies to them, if it's active.
  bool applies(String traitId) =>
      (select?.contains(traitId) ?? true) && !except.contains(traitId);

  /// These, with only the traits [filter] picks of them applying -- a
  /// person's, for one of their habits.
  PersonTraits narrowedTo(PersonTraits filter) => PersonTraits(
    select: switch ((select, filter.select)) {
      (null, final picked) => picked,
      (final mine?, null) => mine,
      (final mine?, final picked?) => [
        for (final id in mine)
          if (picked.contains(id)) id,
      ],
    },
    except: {...except, ...filter.except}.toList(),
    parts: parts,
    partScoring: partScoring,
    scoring: scoring,
    facts: facts,
  );

  factory PersonTraits.fromJson(Object? json) {
    if (json is! Map) return const PersonTraits();
    return PersonTraits(
      select: switch (json['select']) {
        final List ids => [for (final id in ids) '$id'],
        _ => null,
      },
      except: [for (final id in json['except'] as List? ?? const []) '$id'],
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
    if (except.isNotEmpty) 'except': except,
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

/// What a circle is, set when it's made and never changed: a plain
/// circle, or a community.
enum CircleKind {
  /// Its members, named together: an event or goal naming it is with or
  /// for each of its current members (but any its except leaves out). It
  /// has no traits or judgments of its own; its score is its members',
  /// combined.
  circle,

  /// A subject in its own right -- a team, a club -- with traits, facts
  /// and judgments of its own, scored by them alone; its members are a
  /// roster, never stood for. An event or goal naming it is with or for
  /// it, not them.
  community;

  /// As the server names it.
  String get json => name;

  /// "circle" or "community"; anything else, a plain circle, as every
  /// circle was before kinds.
  static CircleKind fromJson(Object? json) =>
      json == 'community' ? community : circle;
}

/// A named group of people -- family, dance friends, work -- mirroring
/// the server's `ListedCircle`. People can be in more than one. Its
/// [kind] says whether it stands for its people or for itself: a
/// community is [Judged] as a person is, by its own [traits], with its
/// own [facts] and [cancelledEvents]; a plain circle has none of them.
class Circle implements Judged {
  const Circle({
    required this.id,
    required this.name,
    this.kind = CircleKind.circle,
    this.note,
    this.scoring,
    this.memberIds = const [],
    this.traits = const PersonTraits(),
    this.facts = const {},
    this.cancelledEvents = const [],
  });

  @override
  final String id;
  final String name;

  /// A plain circle, or a community: given when it's made, never changed.
  final CircleKind kind;

  bool get isCommunity => kind == CircleKind.community;

  /// A circle is always scored: a plain one as its people combined, a
  /// community as itself.
  @override
  bool get active => true;

  final String? note;

  /// How its people's scores combine into its own, in place of the
  /// defaults': weights by person id. A community's score is its own, so
  /// it takes none.
  final Aggregation? scoring;

  /// The people in it, as the server lists them: whom a plain circle
  /// stands for; a community's roster.
  final List<String> memberIds;

  /// A community's: which traits apply to it, and its own parts for
  /// any, as a person's. A plain circle takes none: it's scored by its
  /// people.
  @override
  final PersonTraits traits;

  /// A community's summary of each trait fact, by trait id and then
  /// fact id, as a person's (see [Person.facts]); edited apart from it,
  /// with `update_circle`'s `facts`. A plain circle has none.
  @override
  final Map<String, Map<String, String>> facts;

  @override
  String? summary(String trait, String factId) =>
      switch (facts[trait]?[factId]) {
        final text? when text.trim().isNotEmpty => text,
        _ => null,
      };

  /// The events the user cancelled that count against a community's
  /// follow-through, newest first, as the server recorded them: not sent
  /// back. A plain circle has none.
  @override
  final List<CancelledEvent> cancelledEvents;

  /// It, with [events] as its cancellations: what the server keeps apart
  /// from it, kept through an edit.
  Circle withCancelledEvents(List<CancelledEvent> events) => Circle(
    id: id,
    name: name,
    kind: kind,
    note: note,
    scoring: scoring,
    memberIds: memberIds,
    traits: traits,
    facts: facts,
    cancelledEvents: events,
  );

  /// One from the server: a community's own `traits`, `facts` and
  /// `cancelled_events` read as a person's, null for a plain circle's.
  factory Circle.fromJson(Map<String, dynamic> json) => Circle(
    id: json['id'] as String,
    name: json['name'] as String? ?? '',
    kind: CircleKind.fromJson(json['kind']),
    note: _text(json['note']),
    scoring: Aggregation.fromJson(json['scoring']),
    memberIds: [
      for (final id in json['member_ids'] as List? ?? const []) '$id',
    ],
    traits: PersonTraits.fromJson(json['traits']),
    facts: factsFromJson(json['facts']),
    cancelledEvents: [
      for (final e in json['cancelled_events'] as List? ?? const [])
        ?CancelledEvent.fromJson(e),
    ],
  );

  /// As `create_circle` and `update_circle` take it: its kind too, which
  /// an update may repeat but never change, and a community's traits
  /// (its facts go beside it, as a person's do).
  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'kind': kind.json,
    'note': ?note,
    'scoring': ?scoring?.toJson(),
    if (!traits.isDefault) 'traits': traits.toJson(),
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

  /// The circle [id] names, if any.
  Circle? circle(String? id) =>
      id == null ? null : circles.where((c) => c.id == id).firstOrNull;

  /// Everyone's name by id, Self among them, and every circle's: for
  /// naming whom events and goals are with and for.
  Map<String, String> get names => {
    for (final p in withSelf) p.id: personName(p),
    for (final c in circles) c.id: circleName(c),
  };
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

/// [circle]'s name, or "(no name)".
String circleName(Circle circle) =>
    circle.name.isEmpty ? '(no name)' : circle.name;

String? _text(Object? value) =>
    value is String && value.trim().isNotEmpty ? value : null;
