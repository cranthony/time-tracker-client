import 'package:flutter/widgets.dart';

import '../models/person.dart';
import 'mcp_client.dart';

/// Who the user wants to be with: people and their circles. The app talks
/// to this rather than to MCP directly, so screens can be exercised
/// without a server. See [PeopleScope] for how screens find it.
abstract class PeopleRepository {
  /// Everyone, whatever their status, and every circle. Self is always
  /// among them ([PeopleList.withSelf]).
  Future<PeopleList> people();

  /// Creates [person]; returns them as created, with their id.
  Future<Person> createPerson(Person person);

  /// Saves [changes], keyed as `update_person` takes them, to person
  /// [id]; a null clears that field. Returns them as saved.
  Future<Person> updatePerson(String id, Map<String, Object?> changes);

  /// Creates [circle]; returns it as created, with its id.
  Future<Circle> createCircle(Circle circle);

  /// Saves [changes] to circle [id]. Returns it as saved.
  Future<Circle> updateCircle(String id, Map<String, Object?> changes);

  /// Deletes circle [id], taking everyone out of it.
  Future<void> deleteCircle(String id);
}

/// Reaches people via the Time Tracker MCP server.
///
/// The server doesn't have these tools yet: until it does, the People
/// section says it couldn't load them.
class McpPeopleRepository implements PeopleRepository {
  McpPeopleRepository(this._client);

  final McpClient _client;

  Map<String, dynamic> _map(Object? result) =>
      (result as Map).cast<String, dynamic>();

  @override
  Future<PeopleList> people() async =>
      PeopleList.fromJson(_map(await _client.callTool('get_people', {})));

  @override
  Future<Person> createPerson(Person person) async => Person.fromJson(
    _map(
      await _client.callTool('create_person', {
        'person': {...person.toJson()..remove('id')},
      }),
    ),
  );

  @override
  Future<Person> updatePerson(String id, Map<String, Object?> changes) async =>
      Person.fromJson(
        _map(
          await _client.callTool('update_person', {
            'person': {'id': id, ...changes},
          }),
        ),
      );

  @override
  Future<Circle> createCircle(Circle circle) async => Circle.fromJson(
    _map(
      await _client.callTool('create_circle', {
        'circle': {...circle.toJson()..remove('id')},
      }),
    ),
  );

  @override
  Future<Circle> updateCircle(String id, Map<String, Object?> changes) async =>
      Circle.fromJson(
        _map(
          await _client.callTool('update_circle', {
            'circle': {'id': id, ...changes},
          }),
        ),
      );

  @override
  Future<void> deleteCircle(String id) =>
      _client.callTool('delete_circle', {'circle_id': id});
}

/// Keeps people in memory. Used when no server is configured, and in
/// tests: it rates no one, giving back the health it was made with.
class InMemoryPeopleRepository implements PeopleRepository {
  InMemoryPeopleRepository({
    List<Person> people = const [],
    List<Circle> circles = const [],
  }) : _people = [...people],
       _circles = [...circles];

  final List<Person> _people;
  final List<Circle> _circles;

  @override
  Future<PeopleList> people() async =>
      PeopleList(people: [..._people], circles: [..._circles]);

  String _id(String name, Iterable<String> taken) {
    final base = name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-');
    var id = base.isEmpty ? 'person' : base;
    for (var n = 2; taken.contains(id) || id == selfPersonId; n++) {
      id = '$base-$n';
    }
    return id;
  }

  @override
  Future<Person> createPerson(Person person) async {
    if (person.name.trim().isEmpty) throw McpException('Give them a name.');
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
      throw McpException("Self can't be archived.");
    }
    final updated = Person.fromJson({...before.toJson(), ...changes});
    if (updated.name.trim().isEmpty) throw McpException('Give them a name.');
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
    final created = Circle.fromJson({
      ...circle.toJson(),
      'id': _id(circle.name, _circles.map((c) => c.id)),
    });
    _circles.add(created);
    return created;
  }

  @override
  Future<Circle> updateCircle(String id, Map<String, Object?> changes) async {
    final i = _circles.indexWhere((c) => c.id == id);
    if (i < 0) throw McpException("'$id' isn't a circle");
    final updated = Circle.fromJson({..._circles[i].toJson(), ...changes});
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
          'circle_ids': [
            for (final c in person.circleIds)
              if (c != id) c,
          ],
        });
      }
    }
  }
}

/// Provides a [PeopleRepository] to the screens and dialogs below it, so
/// it needn't be passed through each. Without one, people aren't offered.
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
