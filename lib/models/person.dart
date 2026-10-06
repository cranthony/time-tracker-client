import 'trait.dart';

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
    this.whatMatters,
    this.traits = const PersonTraits(),
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

  /// What's important to them; for Self, to the user. Markdown.
  final String? whatMatters;

  /// Which traits apply to them, and their own parts for any.
  final PersonTraits traits;

  bool get isSelf => id == selfPersonId;
  bool get active => status == 'active';

  factory Person.fromJson(Map<String, dynamic> json) => Person(
    id: json['id'] as String,
    name: json['name'] as String? ?? '',
    context: _text(json['context']),
    status: json['status'] as String? ?? 'active',
    circleIds: [for (final id in json['circles'] as List? ?? const []) '$id'],
    whatMatters: _text(json['what_matters']),
    traits: PersonTraits.fromJson(json['traits']),
  );

  /// As `create_person` and `update_person` take them: only what the
  /// server keeps.
  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'context': ?context,
    'status': status,
    'circles': circleIds,
    'what_matters': ?whatMatters,
    if (!traits.isDefault) 'traits': traits.toJson(),
  };
}

/// Which traits apply to a person, and their own parts for any, as the
/// server's `traits` field has it: {"select": "all" or [trait ids],
/// "parts": {trait id: [parts]}}.
class PersonTraits {
  const PersonTraits({this.select, this.parts = const {}});

  /// The traits that apply to them, by id; null for every active one.
  final List<String>? select;

  /// Their own parts for a trait, replacing the trait's for them alone:
  /// their own cadence, say.
  final Map<String, List<Part>> parts;

  /// Whether it's as for everyone: every active trait, with its parts.
  bool get isDefault => select == null && parts.isEmpty;

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
    );
  }

  Map<String, Object?> toJson() => {
    'select': select ?? 'all',
    if (parts.isNotEmpty) 'parts': parts,
  };
}

/// A named group of people -- family, dance friends, work -- mirroring
/// the server's `ListedCircle`. People can be in more than one.
class Circle {
  const Circle({
    required this.id,
    required this.name,
    this.note,
    this.memberIds = const [],
  });

  final String id;
  final String name;
  final String? note;

  /// The people in it, as the server lists them.
  final List<String> memberIds;

  factory Circle.fromJson(Map<String, dynamic> json) => Circle(
    id: json['id'] as String,
    name: json['name'] as String? ?? '',
    note: _text(json['note']),
    memberIds: [
      for (final id in json['member_ids'] as List? ?? const []) '$id',
    ],
  );

  /// As `create_circle` and `update_circle` take it.
  Map<String, Object?> toJson() => {'id': id, 'name': name, 'note': ?note};
}

/// A place events happen -- home, the salsa studio -- with a hint for
/// recognizing when an event or note refers to it, mirroring the server's
/// `Location` (its utilities/locations.py).
class Location {
  const Location({required this.id, required this.name, this.hint});

  final String id;
  final String name;

  /// Other names for it, an address, what happens there: "the apartment;
  /// 'home', 'my place'".
  final String? hint;

  factory Location.fromJson(Map<String, dynamic> json) => Location(
    id: json['id'] as String,
    name: json['name'] as String? ?? '',
    hint: _text(json['hint']),
  );

  Map<String, Object?> toJson() => {'id': id, 'name': name, 'hint': ?hint};
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
