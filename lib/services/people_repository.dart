import 'package:flutter/widgets.dart';

import '../models/person.dart';
import 'mcp_client.dart';
import 'response_cache.dart';

/// Who the user wants to be with, and where: people, their circles, and
/// the locations events happen at. The app talks to this rather than to
/// MCP directly, so screens can be exercised without a server. See
/// [PeopleScope] for how screens find it.
abstract class PeopleRepository {
  /// Everyone, whatever their status, and every circle. Self is always
  /// among them ([PeopleList.withSelf]).
  Future<PeopleList> people();

  /// What [people] last returned, kept from an earlier run of the app;
  /// null if there's nothing kept.
  Future<PeopleList?> cachedPeople();

  /// Creates a person from [person]'s fields; returns them as created,
  /// with their id.
  Future<Person> createPerson(Person person);

  /// Saves [changes], keyed as `update_person` takes them, to person
  /// [id]; a null clears that field. Returns them as saved.
  Future<Person> updatePerson(String id, Map<String, Object?> changes);

  /// Creates a circle from [circle]'s fields; returns it with its id.
  Future<Circle> createCircle(Circle circle);

  /// Saves [changes] to circle [id]; a null clears its note.
  Future<Circle> updateCircle(String id, Map<String, Object?> changes);

  /// Deletes circle [id]: everyone in it just leaves it.
  Future<void> deleteCircle(String id);

  /// Every location, by name.
  Future<List<Location>> locations();

  /// What [locations] last returned, kept from an earlier run of the
  /// app; null if there's nothing kept.
  Future<List<Location>?> cachedLocations();

  /// Creates a location from [location]'s fields; returns it with its id.
  Future<Location> createLocation(Location location);

  /// Saves [changes] to location [id]; a null clears its hint.
  Future<Location> updateLocation(String id, Map<String, Object?> changes);

  /// Deletes location [id].
  Future<void> deleteLocation(String id);
}

/// Reaches people, circles and locations via the Time Tracker MCP
/// server's tools.
class McpPeopleRepository implements PeopleRepository {
  McpPeopleRepository(this._client, {this._cache});

  final McpClient _client;
  final ResponseCache? _cache;

  static const _peopleKey = 'people';
  static const _locationsKey = 'locations';

  static PeopleList _decodePeople(Object? result) {
    final json = (result as Map).cast<String, dynamic>();
    return PeopleList(
      people: [
        for (final p in json['people'] as List)
          Person.fromJson((p as Map).cast<String, dynamic>()),
      ],
      circles: [
        for (final c in json['circles'] as List)
          Circle.fromJson((c as Map).cast<String, dynamic>()),
      ],
    );
  }

  static List<Location> _decodeLocations(Object? result) => [
    for (final l in result as List)
      Location.fromJson((l as Map).cast<String, dynamic>()),
  ];

  /// What's kept under [key], decoded; null if nothing is, or it can't
  /// be read.
  Future<T?> _cached<T>(String key, T Function(Object?) decode) async {
    try {
      final result = await _cache?.read(key);
      return result == null ? null : decode(result);
    } catch (_) {
      return null; // From an older version of the app, perhaps.
    }
  }

  @override
  Future<PeopleList?> cachedPeople() => _cached(_peopleKey, _decodePeople);

  @override
  Future<List<Location>?> cachedLocations() =>
      _cached(_locationsKey, _decodeLocations);

  static Map<String, dynamic> _map(Object? result) =>
      (result as Map).cast<String, dynamic>();

  /// [changes] as an update takes them: what's null goes in clear_fields.
  static Map<String, Object?> _update(
    String kind,
    String id,
    Map<String, Object?> changes,
  ) {
    final clear = [
      for (final MapEntry(:key, :value) in changes.entries)
        if (value == null) key,
    ];
    return {
      kind: {
        'id': id,
        for (final MapEntry(:key, :value) in changes.entries) key: ?value,
      },
      if (clear.isNotEmpty) 'clear_fields': clear,
    };
  }

  @override
  Future<PeopleList> people() async {
    final people = await _client.callTool('get_people', {
      'statuses': personStatuses.keys.toList(),
    });
    final circles = await _client.callTool('get_circles', {});
    final result = {'people': people, 'circles': circles};
    await _cache?.write(_peopleKey, result);
    return _decodePeople(result);
  }

  @override
  Future<Person> createPerson(Person person) async => Person.fromJson(
    _map(
      _map(
        await _client.callTool('create_person', {
          'person': person.toJson()..remove('id'),
        }),
      )['person'],
    ),
  );

  @override
  Future<Person> updatePerson(String id, Map<String, Object?> changes) async =>
      Person.fromJson(
        _map(
          await _client.callTool(
            'update_person',
            _update('person', id, changes),
          ),
        ),
      );

  @override
  Future<Circle> createCircle(Circle circle) async => Circle.fromJson(
    _map(
      _map(
        await _client.callTool('create_circle', {
          'circle': circle.toJson()..remove('id'),
        }),
      )['circle'],
    ),
  );

  @override
  Future<Circle> updateCircle(String id, Map<String, Object?> changes) async =>
      Circle.fromJson(
        _map(
          await _client.callTool(
            'update_circle',
            _update('circle', id, changes),
          ),
        ),
      );

  @override
  Future<void> deleteCircle(String id) =>
      _client.callTool('delete_circle', {'circle_id': id});

  @override
  Future<List<Location>> locations() async {
    final result = await _client.callTool('get_locations', {});
    await _cache?.write(_locationsKey, result);
    return _decodeLocations(result);
  }

  @override
  Future<Location> createLocation(Location location) async => Location.fromJson(
    _map(
      _map(
        await _client.callTool('create_location', {
          'location': location.toJson()..remove('id'),
        }),
      )['location'],
    ),
  );

  @override
  Future<Location> updateLocation(
    String id,
    Map<String, Object?> changes,
  ) async => Location.fromJson(
    _map(
      await _client.callTool(
        'update_location',
        _update('location', id, changes),
      ),
    ),
  );

  @override
  Future<void> deleteLocation(String id) =>
      _client.callTool('delete_location', {'location_id': id});
}

/// Keeps people, circles and locations in memory, checked as the server
/// checks them. Used when no server is configured, and in tests: it rates
/// no one, giving back the health it was made with.
class InMemoryPeopleRepository implements PeopleRepository {
  InMemoryPeopleRepository({
    List<Person> people = const [],
    List<Circle> circles = const [],
    List<Location> locations = const [],
  }) : _people = [...people],
       _circles = [...circles],
       _locations = [...locations];

  final List<Person> _people;
  final List<Circle> _circles;
  final List<Location> _locations;

  @override
  Future<PeopleList?> cachedPeople() async => null;

  @override
  Future<List<Location>?> cachedLocations() async => null;

  @override
  Future<PeopleList> people() async => PeopleList(
    people: [..._people],
    circles: [
      for (final c in _circles)
        Circle(
          id: c.id,
          name: c.name,
          note: c.note,
          memberIds: [
            for (final p in _people)
              if (p.circleIds.contains(c.id)) p.id,
          ],
        ),
    ],
  );

  String _id(String name, Iterable<String> taken) {
    final base = name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-');
    var id = base.isEmpty ? 'item' : base;
    for (var n = 2; taken.contains(id) || id == selfPersonId; n++) {
      id = '$base-$n';
    }
    return id;
  }

  void _checkPerson(Person person) {
    if (person.name.trim().isEmpty) throw McpException('Give them a name.');
    final same = _people.where(
      (p) =>
          p.id != person.id &&
          p.name.toLowerCase() == person.name.toLowerCase() &&
          p.context == person.context,
    );
    if (same.isNotEmpty) {
      throw McpException(
        'There\'s already a ${person.name}${person.context == null ? '' : ' (${person.context})'}: '
        'give one a context to tell them apart.',
      );
    }
  }

  @override
  Future<Person> createPerson(Person person) async {
    _checkPerson(person);
    final created = Person.fromJson({
      ...person.toJson(),
      'id': _id(person.name, _people.map((p) => p.id)),
    });
    _people.add(created);
    return created;
  }

  @override
  Future<Person> updatePerson(String id, Map<String, Object?> changes) async {
    final i = _people.indexWhere((p) => p.id == id);
    final before = i >= 0
        ? _people[i]
        : id == selfPersonId
        ? defaultSelf
        : throw McpException("'$id' isn't a person");
    if (before.isSelf && (changes['status'] ?? 'active') != 'active') {
      throw McpException('Self is always active.');
    }
    final updated = Person.fromJson({...before.toJson(), ...changes})
        .withCancelledEvents(before.cancelledEvents);
    _checkPerson(updated);
    if (i >= 0) {
      _people[i] = updated;
    } else {
      _people.insert(0, updated);
    }
    return updated;
  }

  @override
  Future<Circle> createCircle(Circle circle) async {
    if (circle.name.trim().isEmpty) throw McpException('Give it a name.');
    final created = Circle(
      id: _id(circle.name, _circles.map((c) => c.id)),
      name: circle.name,
      note: circle.note,
    );
    _circles.add(created);
    return created;
  }

  @override
  Future<Circle> updateCircle(String id, Map<String, Object?> changes) async {
    final i = _circles.indexWhere((c) => c.id == id);
    if (i < 0) throw McpException("'$id' isn't a circle");
    final before = _circles[i];
    final updated = Circle(
      id: id,
      name: changes['name'] as String? ?? before.name,
      note: changes.containsKey('note')
          ? changes['note'] as String?
          : before.note,
    );
    if (updated.name.trim().isEmpty) throw McpException('Give it a name.');
    _circles[i] = updated;
    return updated;
  }

  @override
  Future<void> deleteCircle(String id) async {
    _circles.removeWhere((c) => c.id == id);
    for (final (i, person) in _people.indexed) {
      if (person.circleIds.contains(id)) {
        _people[i] = Person.fromJson({
          ...person.toJson(),
          'circles': [
            for (final c in person.circleIds)
              if (c != id) c,
          ],
        }).withCancelledEvents(person.cancelledEvents);
      }
    }
  }

  @override
  Future<List<Location>> locations() async =>
      [..._locations]..sort((a, b) => a.name.compareTo(b.name));

  void _checkLocation(Location location) {
    if (location.name.trim().isEmpty) throw McpException('Give it a name.');
    if (_locations.any(
      (l) =>
          l.id != location.id &&
          l.name.toLowerCase() == location.name.toLowerCase(),
    )) {
      throw McpException('There\'s already a location named ${location.name}.');
    }
  }

  @override
  Future<Location> createLocation(Location location) async {
    final created = Location(
      id: _id(location.name, _locations.map((l) => l.id)),
      name: location.name,
      hint: location.hint,
    );
    _checkLocation(created);
    _locations.add(created);
    return created;
  }

  @override
  Future<Location> updateLocation(
    String id,
    Map<String, Object?> changes,
  ) async {
    final i = _locations.indexWhere((l) => l.id == id);
    if (i < 0) throw McpException("'$id' isn't a location");
    final updated = Location.fromJson({..._locations[i].toJson(), ...changes});
    _checkLocation(updated);
    _locations[i] = updated;
    return updated;
  }

  @override
  Future<void> deleteLocation(String id) async =>
      _locations.removeWhere((l) => l.id == id);
}

/// Provides a [PeopleRepository] to the screens and dialogs below it, so
/// it needn't be passed through each. Without one, people and locations
/// aren't offered.
class PeopleScope extends InheritedWidget {
  const PeopleScope({
    super.key,
    required this.repository,
    required super.child,
  });

  final PeopleRepository repository;

  /// The nearest [PeopleScope]'s repository, or null if there's none.
  static PeopleRepository? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<PeopleScope>()?.repository;

  @override
  bool updateShouldNotify(PeopleScope oldWidget) =>
      repository != oldWidget.repository;
}
