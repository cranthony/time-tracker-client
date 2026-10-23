import 'package:flutter/widgets.dart';

import '../models/person.dart';
import '../models/scoring.dart';
import '../models/travel_time.dart';
import '../models/trait_scores.dart' show traitsWithPartIds;
import '../outbox/write_queue.dart';
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

  /// What compaction changed in person [personId]'s trait facts -- of
  /// trait [traitId], if given -- newest first.
  Future<List<FactLog>> factLogs(String personId, {String? traitId});

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

  /// Saves [changes] to location [id]; a null clears its hint or map
  /// location.
  Future<Location> updateLocation(String id, Map<String, Object?> changes);

  /// Deletes location [id].
  Future<void> deleteLocation(String id);

  /// Every location group, enclosing ones before those inside them.
  Future<List<LocationGroup>> locationGroups();

  /// Creates a location group from [group]'s fields; returns it with its
  /// id.
  Future<LocationGroup> createLocationGroup(LocationGroup group);

  /// Saves [changes] to location group [id]; a null clears its note, or
  /// takes it out of the group it was in.
  Future<LocationGroup> updateLocationGroup(
    String id,
    Map<String, Object?> changes,
  );

  /// Deletes location group [id]: what was in it moves up into the group
  /// it was in.
  Future<void> deleteLocationGroup(String id);

  /// Every travel time.
  Future<List<TravelTime>> travelTimes();

  /// Creates a travel time from [travel]'s fields; returns it with its id.
  Future<TravelTime> createTravelTime(TravelTime travel);

  /// Saves [changes] to travel time [id]: its `times` are replaced whole,
  /// and a null note clears it.
  Future<TravelTime> updateTravelTime(String id, Map<String, Object?> changes);

  /// Deletes travel time [id].
  Future<void> deleteTravelTime(String id);
}

/// Reaches people, circles and locations via the Time Tracker MCP
/// server's tools. With [writes], people and locations are written
/// through it: queued, kept on the device and sent once, so a write never
/// waits on the server -- and what's read is shown with them made.
class McpPeopleRepository implements PeopleRepository {
  McpPeopleRepository(this._client, {this._cache, this._writes});

  final McpClient _client;
  final ResponseCache? _cache;
  final WriteQueue? _writes;

  /// [items], the [kind]s the server gave, with the writes waiting made
  /// to them.
  List<Map<String, Object?>> _shown(WriteKind kind, Object? items) {
    final list = [
      for (final i in items as List) (i as Map).cast<String, Object?>(),
    ];
    return _writes?.shown(kind, list) ?? list;
  }

  /// [fetch]ed -- or, if that fails while [kind]'s writes wait (offline,
  /// say), what's [kept], with them made: so what was just written shows,
  /// though the server can't be asked.
  Future<T> _orKept<T>(
    WriteKind kind,
    Future<T> Function() fetch,
    Future<T?> Function() kept,
  ) async {
    try {
      return await fetch();
    } on SignInRequiredException {
      rethrow;
    } catch (_) {
      final waiting = _writes?.items.any((w) => w.kind == kind.name) ?? false;
      if (!waiting) rethrow;
      return await kept() ?? (throw StateError('nothing kept'));
    }
  }

  /// [result], `get_people`'s and `get_circles`', with the people's
  /// writes waiting made to it.
  Object? _withPeopleWrites(Object? result) {
    if (_writes == null) return result;
    final json = (result as Map).cast<String, Object?>();
    return {
      ...json,
      'people': _shown(WriteKind.person, json['people']),
      'circles': _shown(WriteKind.circle, json['circles']),
    };
  }

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
  Future<PeopleList?> cachedPeople() =>
      _cached(_peopleKey, (r) => _decodePeople(_withPeopleWrites(r)));

  @override
  Future<List<Location>?> cachedLocations() => _cached(
    _locationsKey,
    (r) => _decodeLocations(_shown(WriteKind.location, r)),
  );

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
  Future<PeopleList> people() =>
      _orKept(WriteKind.person, _fetchPeople, cachedPeople);

  @override
  Future<List<FactLog>> factLogs(String personId, {String? traitId}) async => [
    for (final log in await _client.callTool('get_fact_logs', {
      'person_id': personId,
      'trait_id': ?traitId,
    }) as List)
      FactLog.fromJson((log as Map).cast<String, dynamic>()),
  ];

  Future<PeopleList> _fetchPeople() async {
    final people = await _client.callTool('get_people', {
      'statuses': personStatuses.keys.toList(),
    });
    final circles = await _client.callTool('get_circles', {});
    final result = {'people': people, 'circles': circles};
    await _cache?.write(_peopleKey, result);
    return _decodePeople(_withPeopleWrites(result));
  }

  @override
  Future<Person> createPerson(Person person) async {
    if (_writes case final writes?) {
      final fields = person.toJson()..remove('id');
      final id = writes.create(WriteKind.person, fields);
      return Person.fromJson({...fields, 'id': id});
    }
    return _createPerson(person);
  }

  Future<Person> _createPerson(Person person) async => Person.fromJson(
    _map(
      _map(
        await _client.callTool('create_person', {
          'person': person.toJson()..remove('id'),
        }),
      )['person'],
    ),
  );

  @override
  Future<Person> updatePerson(String id, Map<String, Object?> changes) async {
    if (_writes case final writes?) {
      return Person.fromJson(
        writes.update(WriteKind.person, id, changes).cast<String, dynamic>(),
      );
    }
    return _updatePerson(id, changes);
  }

  Future<Person> _updatePerson(String id, Map<String, Object?> changes) async =>
      Person.fromJson(
        _map(
          await _client.callTool('update_person', personUpdate(id, changes)),
        ),
      );

  @override
  Future<Circle> createCircle(Circle circle) async => switch (_writes) {
    final writes? => Circle.fromJson(
      writes.created(WriteKind.circle, circle.toJson()).cast(),
    ),
    null => await _createCircle(circle),
  };

  Future<Circle> _createCircle(Circle circle) async => Circle.fromJson(
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
      switch (_writes) {
        final writes? => Circle.fromJson(
          writes.update(WriteKind.circle, id, changes).cast(),
        ),
        null => await _updateCircle(id, changes),
      };

  Future<Circle> _updateCircle(String id, Map<String, Object?> changes) async =>
      Circle.fromJson(
        _map(
          await _client.callTool(
            'update_circle',
            _update('circle', id, changes),
          ),
        ),
      );

  @override
  Future<void> deleteCircle(String id) async => switch (_writes) {
    final writes? => writes.delete(WriteKind.circle, id),
    null => await _deleteCircle(id),
  };

  Future<void> _deleteCircle(String id) =>
      _client.callTool('delete_circle', {'circle_id': id});

  @override
  Future<List<Location>> locations() =>
      _orKept(WriteKind.location, _fetchLocations, cachedLocations);

  Future<List<Location>> _fetchLocations() async {
    final result = await _client.callTool('get_locations', {});
    await _cache?.write(_locationsKey, result);
    return _decodeLocations(_shown(WriteKind.location, result));
  }

  @override
  Future<Location> createLocation(Location location) async {
    if (_writes case final writes?) {
      final fields = location.toJson()..remove('id');
      final id = writes.create(WriteKind.location, fields);
      return Location.fromJson({...fields, 'id': id});
    }
    return _createLocation(location);
  }

  Future<Location> _createLocation(Location location) async =>
      Location.fromJson(
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
  ) async {
    if (_writes case final writes?) {
      return Location.fromJson(
        writes.update(WriteKind.location, id, changes).cast<String, dynamic>(),
      );
    }
    return _updateLocation(id, changes);
  }

  Future<Location> _updateLocation(
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
  Future<void> deleteLocation(String id) async {
    if (_writes case final writes?) {
      return writes.delete(WriteKind.location, id);
    }
    await _client.callTool('delete_location', {'location_id': id});
  }

  @override
  Future<List<LocationGroup>> locationGroups() async => [
    for (final g in _shown(
      WriteKind.locationGroup,
      await _client.callTool('get_location_groups', {}),
    ))
      LocationGroup.fromJson((g as Map).cast<String, dynamic>()),
  ];

  @override
  Future<LocationGroup> createLocationGroup(LocationGroup group) async =>
      switch (_writes) {
        final writes? => LocationGroup.fromJson(
          writes.created(WriteKind.locationGroup, group.toJson()).cast(),
        ),
        null => await _createLocationGroup(group),
      };

  Future<LocationGroup> _createLocationGroup(LocationGroup group) async =>
      LocationGroup.fromJson(
        _map(
          _map(
            await _client.callTool('create_location_group', {
              'group': group.toJson()..remove('id'),
            }),
          )['group'],
        ),
      );

  @override
  Future<LocationGroup> updateLocationGroup(
    String id,
    Map<String, Object?> changes,
  ) async => switch (_writes) {
    final writes? => LocationGroup.fromJson(
      writes.update(WriteKind.locationGroup, id, changes).cast(),
    ),
    null => await _updateLocationGroup(id, changes),
  };

  Future<LocationGroup> _updateLocationGroup(
    String id,
    Map<String, Object?> changes,
  ) async => LocationGroup.fromJson(
    _map(
      await _client.callTool(
        'update_location_group',
        _update('group', id, changes),
      ),
    ),
  );

  @override
  Future<void> deleteLocationGroup(String id) async => switch (_writes) {
    final writes? => writes.delete(WriteKind.locationGroup, id),
    null => await _deleteLocationGroup(id),
  };

  Future<void> _deleteLocationGroup(String id) =>
      _client.callTool('delete_location_group', {'group_id': id});

  @override
  Future<List<TravelTime>> travelTimes() async => [
    for (final t in _shown(
      WriteKind.travelTime,
      await _client.callTool('get_travel_times', {}),
    ))
      TravelTime.fromJson((t as Map).cast<String, dynamic>()),
  ];

  @override
  Future<TravelTime> createTravelTime(TravelTime travel) async =>
      switch (_writes) {
        final writes? => TravelTime.fromJson(
          writes.created(WriteKind.travelTime, travel.toJson()).cast(),
        ),
        null => await _createTravelTime(travel),
      };

  Future<TravelTime> _createTravelTime(TravelTime travel) async =>
      TravelTime.fromJson(
        _map(
          _map(
            await _client.callTool('create_travel_time', {
              'travel_time': travel.toJson()..remove('id'),
            }),
          )['travel_time'],
        ),
      );

  @override
  Future<TravelTime> updateTravelTime(
    String id,
    Map<String, Object?> changes,
  ) async => switch (_writes) {
    final writes? => TravelTime.fromJson(
      writes.update(WriteKind.travelTime, id, changes).cast(),
    ),
    null => await _updateTravelTime(id, changes),
  };

  Future<TravelTime> _updateTravelTime(
    String id,
    Map<String, Object?> changes,
  ) async => TravelTime.fromJson(
    _map(
      await _client.callTool(
        'update_travel_time',
        _update('travel_time', id, changes),
      ),
    ),
  );

  @override
  Future<void> deleteTravelTime(String id) async => switch (_writes) {
    final writes? => writes.delete(WriteKind.travelTime, id),
    null => await _deleteTravelTime(id),
  };

  Future<void> _deleteTravelTime(String id) =>
      _client.callTool('delete_travel_time', {'travel_time_id': id});
}

/// Keeps people, circles and locations in memory, checked as the server
/// checks them. Used when no server is configured, and in tests: it rates
/// no one, giving back the health it was made with.
class InMemoryPeopleRepository implements PeopleRepository {
  InMemoryPeopleRepository({
    List<Person> people = const [],
    List<Circle> circles = const [],
    List<Location> locations = const [],
    List<LocationGroup> locationGroups = const [],
    List<TravelTime> travelTimes = const [],
    this._factLogs = const {},
  }) : _people = [for (final p in people) _withIds(p)],
       _circles = [...circles],
       _locations = [...locations],
       _groups = [...locationGroups],
       _travel = [...travelTimes];

  final List<Person> _people;

  /// Each person's fact logs, by id, newest first.
  final Map<String, List<FactLog>> _factLogs;
  final List<Circle> _circles;
  final List<Location> _locations;
  final List<LocationGroup> _groups;
  final List<TravelTime> _travel;

  /// [person] with an id for each of their own parts, as the server keeps
  /// them: a new one's made, with [fresh].
  static Person _withIds(Person person, {bool fresh = false}) =>
      person.traits.parts.isEmpty
      ? person
      : Person.fromJson({
          ...person.toJson(),
          'facts': person.facts,
          'traits': traitsWithPartIds(person.traits, fresh: fresh).toJson(),
        }).withCancelledEvents(person.cancelledEvents);

  @override
  Future<List<FactLog>> factLogs(String personId, {String? traitId}) async => [
    for (final log in _factLogs[personId] ?? const <FactLog>[])
      if (traitId == null || log.traitId == traitId) log,
  ];

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
    final created = _withIds(
      Person.fromJson({
        ...person.toJson(),
        'id': _id(person.name, _people.map((p) => p.id)),
      }),
      fresh: true,
    );
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
    final updated = _withIds(
      Person.fromJson({
        ...before.toJson(),
        ...changes,
        'facts': {
          for (final MapEntry(:key, :value) in before.facts.entries)
            key: {...value},
          if (changes['facts'] case final Map given)
            for (final MapEntry(:key, :value) in given.entries)
              '$key': {...?before.facts['$key'], ...(value as Map).cast()},
        },
      }).withCancelledEvents(before.cancelledEvents),
      fresh: true,
    );
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
      scoring: circle.scoring,
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
      scoring: changes.containsKey('scoring')
          ? Aggregation.fromJson(changes['scoring'])
          : before.scoring,
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
  Future<List<Location>> locations() async => [
    for (final l in [..._locations]..sort((a, b) => a.name.compareTo(b.name)))
      Location(
        id: l.id,
        name: l.name,
        hint: l.hint,
        mapLocation: l.mapLocation,
        groupId: l.groupId,
        path: groupPath(l.name, l.groupId, _groups),
      ),
  ];

  void _checkLocation(Location location) {
    if (location.name.trim().isEmpty) throw McpException('Give it a name.');
    if (location.groupId case final group?
        when !_groups.any((g) => g.id == group)) {
      throw McpException("'$group' isn't a location group.");
    }
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
      mapLocation: location.mapLocation,
      groupId: location.groupId,
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

  @override
  Future<List<LocationGroup>> locationGroups() async {
    // Enclosing groups first, as the server lists them.
    final ordered = <LocationGroup>[];
    void visit(String? parent) {
      for (final g in _groups.where((g) => g.groupId == parent)) {
        ordered.add(
          LocationGroup(
            id: g.id,
            name: g.name,
            groupId: g.groupId,
            note: g.note,
            path: groupPath(g.name, g.groupId, _groups),
          ),
        );
        visit(g.id);
      }
    }

    visit(null);
    return ordered;
  }

  void _checkGroup(LocationGroup group) {
    if (group.name.trim().isEmpty) throw McpException('Give it a name.');
    if (_groups.any(
      (g) =>
          g.id != group.id && g.name.toLowerCase() == group.name.toLowerCase(),
    )) {
      throw McpException(
        "There's already a location group named ${group.name}.",
      );
    }
    if (group.groupId case final parent?) {
      if (!_groups.any((g) => g.id == parent)) {
        throw McpException("'$parent' isn't a location group.");
      }
      final others = [..._groups.where((g) => g.id != group.id), group];
      if (enclosingGroupIds(parent, others).contains(group.id)) {
        throw McpException("A group can't be inside itself.");
      }
    }
  }

  @override
  Future<LocationGroup> createLocationGroup(LocationGroup group) async {
    final created = LocationGroup(
      id: _id(group.name, [
        ..._groups.map((g) => g.id),
        ..._locations.map((l) => l.id),
      ]),
      name: group.name,
      groupId: group.groupId,
      note: group.note,
    );
    _checkGroup(created);
    _groups.add(created);
    return created;
  }

  @override
  Future<LocationGroup> updateLocationGroup(
    String id,
    Map<String, Object?> changes,
  ) async {
    final i = _groups.indexWhere((g) => g.id == id);
    if (i < 0) throw McpException("'$id' isn't a location group");
    final updated = LocationGroup.fromJson({
      ..._groups[i].toJson(),
      ...changes,
    });
    _checkGroup(updated);
    _groups[i] = updated;
    return updated;
  }

  @override
  Future<void> deleteLocationGroup(String id) async {
    final i = _groups.indexWhere((g) => g.id == id);
    if (i < 0) return;
    final up = _groups.removeAt(i).groupId;
    for (final (j, g) in _groups.indexed) {
      if (g.groupId == id) {
        _groups[j] = LocationGroup.fromJson({...g.toJson(), 'group_id': up});
      }
    }
    for (final (j, l) in _locations.indexed) {
      if (l.groupId == id) {
        _locations[j] = Location.fromJson({...l.toJson(), 'group_id': up});
      }
    }
  }

  @override
  Future<List<TravelTime>> travelTimes() async => [..._travel];

  void _checkTravel(TravelTime travel) {
    bool place(String id) =>
        _locations.any((l) => l.id == id) || _groups.any((g) => g.id == id);
    if (!place(travel.fromId) || !place(travel.toId)) {
      throw McpException('Pick where it is from and to.');
    }
    if (travel.fromId == travel.toId) {
      throw McpException("It can't be from a place to itself.");
    }
    for (final t in travel.times) {
      if (t.minutes <= 0) throw McpException('A time takes more than 0m.');
      if (t.maxMinutes case final max? when max < t.minutes) {
        throw McpException("A time can't take less at most than at least.");
      }
    }
  }

  @override
  Future<TravelTime> createTravelTime(TravelTime travel) async {
    final created = TravelTime.fromJson({
      ...travel.toJson(),
      'id': _id('travel', _travel.map((t) => t.id)),
    });
    _checkTravel(created);
    _travel.add(created);
    return created;
  }

  @override
  Future<TravelTime> updateTravelTime(
    String id,
    Map<String, Object?> changes,
  ) async {
    final i = _travel.indexWhere((t) => t.id == id);
    if (i < 0) throw McpException("'$id' isn't a travel time");
    final updated = TravelTime.fromJson({..._travel[i].toJson(), ...changes});
    _checkTravel(updated);
    _travel[i] = updated;
    return updated;
  }

  @override
  Future<void> deleteTravelTime(String id) async =>
      _travel.removeWhere((t) => t.id == id);
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
