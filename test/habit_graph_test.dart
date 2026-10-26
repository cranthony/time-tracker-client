import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:time_tracker_client/models/habit.dart';
import 'package:time_tracker_client/models/habit_graph.dart';
import 'package:time_tracker_client/models/person.dart';
import 'package:time_tracker_client/widgets/foundations_field.dart';
import 'package:time_tracker_client/widgets/health.dart';

Habit _habit(String id, [List<String> foundations = const []]) =>
    Habit(id: id, name: id, actionId: 'a', foundations: foundations);

/// Sleep and eat; exercise on both; family on exercise; read on family.
final _graph = HabitGraph(
  habits: [
    _habit('sleep'),
    _habit('eat'),
    _habit('gym', ['habit:sleep', 'habit:eat']),
    _habit('read', ['fam', 'habit:gone']),
    const Habit(id: 'gone', name: 'Gone', actionId: 'a', status: 'deleted'),
  ],
  people: const [
    Person(id: 'fam', name: 'Family', foundations: ['habit:gym']),
    Person(id: 'pal', name: 'Pal'),
    Person(id: 'old', name: 'Old', status: 'deleted', foundations: []),
  ],
);

void main() {
  test('its nodes are the habits and the people on it, not deleted', () {
    expect(_graph.nodes.keys.toSet(), {
      'habit:sleep',
      'habit:eat',
      'habit:gym',
      'habit:read',
      'fam',
    });
    expect(_graph.nodes['fam']!.isPerson, isTrue);
    expect(_graph.foundationsOf('habit:read'), ['fam']);
  });

  test('a person built on, though not on it, is a node too', () {
    final graph = HabitGraph(
      habits: [
        _habit('call', ['pal']),
      ],
      people: const [Person(id: 'pal', name: 'Pal')],
    );
    expect(graph.nodes.keys, containsAll(['habit:call', 'pal']));
    expect(graph.layerOf('habit:call'), 1);
  });

  test('a layer is one above the highest of its foundations', () {
    expect(
      [
        for (final id in ['habit:sleep', 'habit:gym', 'fam', 'habit:read'])
          _graph.layerOf(id),
      ],
      [0, 1, 2, 3],
    );
  });

  test("a cycle, which the server refuses, doesn't hang it", () {
    final graph = HabitGraph(
      habits: [
        _habit('a', ['habit:b']),
        _habit('b', ['habit:a']),
      ],
    );
    expect(graph.layerOf('habit:a'), anyOf(0, 1));
    expect(graph.builtOn('habit:a'), containsAll(['habit:b']));
  });

  test('says what each is built on, and what is built on it', () {
    expect(_graph.withFoundations(['fam']), {
      'fam',
      'habit:gym',
      'habit:sleep',
      'habit:eat',
    });
    expect(_graph.builtOn('habit:eat'), {'habit:gym', 'fam', 'habit:read'});
  });

  test('unlocks what has every foundation shown and on track', () {
    expect(_graph.unlocked((_) => true), _graph.nodes.keys.toSet());
    expect(_graph.unlocked((id) => id != 'habit:eat'), {
      'habit:sleep',
      'habit:eat',
    });
    // Those it isn't among are left out of foundations.
    expect(
      _graph.unlocked(
        (id) => id != 'habit:eat',
        among: {'habit:sleep', 'habit:gym'},
      ),
      {'habit:sleep', 'habit:gym'},
    );
  });

  test('foundations can be anything on it but itself and what is built on '
      'it', () {
    final choices = foundationChoices(_graph, id: 'habit:gym');
    expect([for (final c in choices) c.id], ['habit:eat', 'habit:sleep']);
  });

  testWidgets('consistency is shown under the rating, to 30 days', (
    tester,
  ) async {
    expect(consistencyLabel(1), '1d');
    expect(consistencyLabel(30), '30d');
    expect(consistencyLabel(31), '>30d');
    await tester.pumpWidget(
      const MaterialApp(
        home: Row(
          children: [
            HealthDot(rating: 80, consistency: 7),
            HealthDot(rating: 40),
          ],
        ),
      ),
    );
    expect(find.text('7d'), findsOneWidget);
    expect(find.text('80'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('7d')).dy,
      greaterThan(tester.getTopLeft(find.text('80')).dy),
    );
    expect(find.textContaining('d'), findsOneWidget);
  });
}
