/// Who the user wants to be with: a person, who can belong to any number
/// of [Circle]s, with a relationship health rating. "Self" is always one
/// of them ([selfPersonId]), even when no one else is.
///
/// Unlike actions, people don't take up the calendar's event labels: an
/// event says who it was with and for in its private properties (see
/// facets.dart).
class Person {
  const Person({
    required this.id,
    required this.name,
    this.status = 'active',
    this.circleIds = const [],
    this.notes,
    this.traitWeights = const {},
    this.health,
    this.healthTrend = const [],
    this.properties = const {},
  });

  final String id;
  final String name;

  /// One of [personStatuses]' keys.
  final String status;

  /// The circles they're in, by id: any number of them. Self is in none.
  final List<String> circleIds;

  /// What matters to them, and anything else worth remembering about
  /// them; for Self, about the user. Markdown.
  final String? notes;

  /// How much each trait counts toward their relationship health, by
  /// trait id; a trait not named weighs 1, and 0 leaves it out.
  final Map<String, num> traitWeights;

  /// Their relationship health (0-100), from their traits' scores; null
  /// until it's been rated.
  final int? health;

  /// Its last 8 days, oldest first; null for a day with none.
  final List<int?> healthTrend;

  /// The person as the server sent them.
  final Map<String, dynamic> properties;

  bool get isSelf => id == selfPersonId;
  bool get active => status == 'active';

  factory Person.fromJson(Map<String, dynamic> json) => Person(
    id: json['id'] as String,
    name: json['name'] as String? ?? '',
    status: json['status'] as String? ?? 'active',
    circleIds: [
      for (final id in json['circle_ids'] as List? ?? const []) '$id',
    ],
    notes: json['notes'] as String?,
    traitWeights: {
      for (final MapEntry(:key, :value)
          in (json['trait_weights'] as Map? ?? const {}).entries)
        if (value is num) '$key': value,
    },
    health: (json['health'] as num?)?.round(),
    healthTrend: _trend(json['health_trend']),
    properties: Map.unmodifiable(json),
  );

  /// As `create_person` and `update_person` take them, with what the
  /// server sent kept.
  Map<String, Object?> toJson() => {
    ...properties,
    'id': id,
    'name': name,
    'status': status,
    'circle_ids': circleIds,
    'notes': notes,
    'trait_weights': traitWeights,
    'health': health,
    'health_trend': _trendJson(healthTrend),
  };
}

/// A named group of people -- family, dance friends, work -- with its
/// own relationship health. People can be in more than one.
class Circle {
  const Circle({
    required this.id,
    required this.name,
    this.color,
    this.health,
    this.healthTrend = const [],
    this.properties = const {},
  });

  final String id;
  final String name;

  /// e.g. "#7986cb"; null for none.
  final String? color;
  final int? health;
  final List<int?> healthTrend;
  final Map<String, dynamic> properties;

  factory Circle.fromJson(Map<String, dynamic> json) => Circle(
    id: json['id'] as String,
    name: json['name'] as String? ?? '',
    color: json['color'] as String?,
    health: (json['health'] as num?)?.round(),
    healthTrend: _trend(json['health_trend']),
    properties: Map.unmodifiable(json),
  );

  Map<String, Object?> toJson() => {
    ...properties,
    'id': id,
    'name': name,
    'color': color,
    'health': health,
    'health_trend': _trendJson(healthTrend),
  };
}

/// Everyone, and their circles.
class PeopleList {
  const PeopleList({this.people = const [], this.circles = const []});

  /// Self first, then everyone else in the order the user keeps them.
  final List<Person> people;
  final List<Circle> circles;

  /// Self, as the server has them, or as they are before they've ever
  /// been changed.
  Person get self => people.where((p) => p.isSelf).firstOrNull ?? defaultSelf;

  /// [people], with Self first whether or not the server listed them.
  List<Person> get withSelf => [
    self,
    for (final person in people)
      if (!person.isSelf) person,
  ];

  /// The people in [circleId], Self left out.
  List<Person> inCircle(String circleId) => [
    for (final person in people)
      if (person.circleIds.contains(circleId)) person,
  ];

  factory PeopleList.fromJson(Map<String, dynamic> json) => PeopleList(
    people: [
      for (final p in json['people'] as List? ?? const [])
        Person.fromJson((p as Map).cast<String, dynamic>()),
    ],
    circles: [
      for (final c in json['circles'] as List? ?? const [])
        Circle.fromJson((c as Map).cast<String, dynamic>()),
    ],
  );

  Map<String, Object?> toJson() => {
    'people': [for (final p in people) p.toJson()],
    'circles': [for (final c in circles) c.toJson()],
  };
}

/// The id of the user themself, who's always among the people.
const selfPersonId = 'self';

/// Self, before they've been changed.
const defaultSelf = Person(id: selfPersonId, name: 'Self');

/// The statuses a person can have, as the server names them, and as the
/// app shows them.
const personStatuses = {'active': 'Active', 'archived': 'Archived'};

/// [person]'s name, or "(no name)".
String personName(Person person) =>
    person.name.isEmpty ? '(no name)' : person.name;

List<int?> _trend(Object? json) => [
  for (final cell
      in ((json as String?) ?? '').split(',').where((c) => c.isNotEmpty))
    int.tryParse(cell),
];

String _trendJson(List<int?> trend) =>
    trend.map((r) => r?.toString() ?? '-').join(',');
