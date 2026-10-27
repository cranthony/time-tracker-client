/// Someone an event's facts or a goal names, with or for: a person, or a
/// circle, by id -- and for a plain circle, those of its members it
/// leaves out ([except]), as the server's `Named` (its attendees.rs). A
/// plain circle stands for its current members but those, and never the
/// user; a community stands for itself. Sent as its bare id, or with an
/// except as `{circle_id, except}`.
class Named {
  const Named(this.id, {this.except = const []});

  final String id;

  /// Of a plain circle's members, who aren't, by person id.
  final List<String> except;

  /// One of a goal's `with_ids` or `for_ids`: a bare id, or `{circle_id,
  /// except?}`; null for anything else.
  static Named? fromJson(Object? json) => switch (json) {
    final String id when id.isNotEmpty => Named(id),
    {'circle_id': final String id} when id.isNotEmpty => Named(
      id,
      except: [
        for (final e in (json as Map)['except'] as List? ?? const []) '$e',
      ],
    ),
    // A share's, as facts name people.
    {'person_id': final String id} when id.isNotEmpty => Named(id),
    _ => null,
  };

  /// A goal's `with_ids` or `for_ids`, each as [fromJson] reads it.
  static List<Named> listFromJson(Object? json) => [
    for (final item in json as List? ?? const []) ?fromJson(item),
  ];

  /// As the server takes it: its bare id with no except, as ids always
  /// were.
  Object toJson() => except.isEmpty ? id : {'circle_id': id, 'except': except};

  Named withExcept(List<String> except) => Named(id, except: except);

  @override
  bool operator ==(Object other) =>
      other is Named &&
      other.id == id &&
      other.except.length == except.length &&
      [for (var i = 0; i < except.length; i++) other.except[i] == except[i]]
          .every((same) => same);

  @override
  int get hashCode => Object.hash(id, Object.hashAll(except));

  @override
  String toString() =>
      except.isEmpty ? 'Named($id)' : 'Named($id, except: $except)';
}

/// [named]'s ids, in order.
List<String> namedIds(Iterable<Named> named) => [for (final n in named) n.id];

/// [named] as a goal's `with_ids` or `for_ids` are sent.
List<Object> namedToJson(Iterable<Named> named) => [
  for (final n in named) n.toJson(),
];

/// [ids] each as a [Named], with no except.
List<Named> namedFrom(Iterable<String> ids) => [
  for (final id in ids) Named(id),
];

/// [named] as the server's timeline says it, by [name]: "Family (except
/// Ulyssie)", or just "Sam".
String namedLabel(Named named, String Function(String id) name) =>
    named.except.isEmpty
    ? name(named.id)
    : '${name(named.id)} (except ${named.except.map(name).join(', ')})';

/// Each of [named] as [namedLabel] says it, joined: "Sam, Family (except
/// Ulyssie)".
String namedList(Iterable<Named> named, String Function(String id) name) =>
    [for (final n in named) namedLabel(n, name)].join(', ');
