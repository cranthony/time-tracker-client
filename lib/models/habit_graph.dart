import 'habit.dart';
import 'person.dart';

/// One node of the habit graph: one of Self's habits, by its subject id
/// (`habit:<id>`), or a person, by their id.
class GraphNode {
  const GraphNode.habit(Habit this.habit) : person = null;
  const GraphNode.person(Person this.person) : habit = null;

  final Habit? habit;
  final Person? person;

  /// Its subject id: what foundations name it by, and what it's scored
  /// as.
  String get id => habit?.subject ?? person!.id;

  String get name => switch ((habit, person)) {
    (final h?, _) => habitName(h),
    (_, final p?) => p.name.isEmpty ? '(no name)' : p.name,
    _ => '',
  };

  bool get isPerson => person != null;

  /// What it's built on, as stored: unknown and deleted ones among them.
  List<String> get foundations =>
      habit?.foundations ?? person?.foundations ?? const [];

  /// Whether it's set aside: an archived habit or person.
  bool get archived => (habit?.status ?? person!.status) == 'archived';
}

/// Self's habits, and the people on the habit graph, layered by what
/// they're built on: layer 0 has those with no foundations, and each
/// other one sits a layer above the highest of its foundations.
///
/// Its nodes are every habit not deleted, every person not deleted who's
/// on the graph ([Person.onHabitGraph]), and any other person a node is
/// built on. A foundation that's no node -- deleted, say -- is left out.
class HabitGraph {
  HabitGraph({List<Habit> habits = const [], List<Person> people = const []}) {
    for (final h in habits) {
      if (h.status != 'deleted') _nodes[h.subject] = GraphNode.habit(h);
    }
    final everyone = {
      for (final p in people)
        if (p.status != 'deleted') p.id: p,
    };
    for (final p in everyone.values) {
      if (p.onHabitGraph) _nodes[p.id] = GraphNode.person(p);
    }
    // Those built on, though not on it themselves.
    for (var added = true; added;) {
      added = false;
      for (final n in [..._nodes.values]) {
        for (final f in n.foundations) {
          final p = everyone[f];
          if (p != null && !_nodes.containsKey(f)) {
            _nodes[f] = GraphNode.person(p);
            added = true;
          }
        }
      }
    }
  }

  final _nodes = <String, GraphNode>{};
  final _layers = <String, int>{};

  /// Every node, by id.
  Map<String, GraphNode> get nodes => Map.unmodifiable(_nodes);

  /// [id]'s foundations that are nodes.
  List<String> foundationsOf(String id) => [
    for (final f in _nodes[id]?.foundations ?? const <String>[])
      if (_nodes.containsKey(f) && f != id) f,
  ];

  /// [id]'s layer: 0 with no foundations, else one above the highest of
  /// theirs. A cycle, which the server refuses, counts as no foundation.
  int layerOf(String id) => _layer(id, {});

  int _layer(String id, Set<String> visiting) {
    if (_layers[id] case final known?) return known;
    if (!visiting.add(id)) return -1;
    var layer = 0;
    for (final f in foundationsOf(id)) {
      final below = _layer(f, visiting);
      if (below >= 0 && below + 1 > layer) layer = below + 1;
    }
    visiting.remove(id);
    return _layers[id] = layer;
  }

  /// [ids] and everything they're built on, directly or not.
  Set<String> withFoundations(Iterable<String> ids) {
    final out = <String>{};
    final todo = [...ids];
    while (todo.isNotEmpty) {
      final id = todo.removeLast();
      if (out.add(id)) todo.addAll(foundationsOf(id));
    }
    return out;
  }

  /// Everything built on [id], directly or not: what can't be among its
  /// foundations without a cycle.
  Set<String> builtOn(String id) {
    final out = <String>{};
    for (var added = true; added;) {
      added = false;
      for (final n in _nodes.keys) {
        if (out.contains(n)) continue;
        if (foundationsOf(n).any((f) => f == id || out.contains(f))) {
          out.add(n);
          added = true;
        }
      }
    }
    return out;
  }

  /// The ids of [among] (by default every node) shown by default: those
  /// with no foundations, and those whose every foundation is shown and
  /// [onTrack].
  Set<String> unlocked(bool Function(String id) onTrack, {Set<String>? among}) {
    final ids = among ?? _nodes.keys.toSet();
    final order = [...ids]..sort((a, b) => layerOf(a).compareTo(layerOf(b)));
    final shown = <String>{};
    for (final id in order) {
      final foundations = [
        for (final f in foundationsOf(id))
          if (ids.contains(f)) f,
      ];
      if (foundations.every((f) => shown.contains(f) && onTrack(f))) {
        shown.add(id);
      }
    }
    return shown;
  }
}
