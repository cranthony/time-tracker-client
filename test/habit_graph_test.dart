import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:time_tracker_client/models/habit.dart';
import 'package:time_tracker_client/models/habit_graph.dart';
import 'package:time_tracker_client/widgets/foundations_field.dart';
import 'package:time_tracker_client/widgets/health.dart';

Habit _habit(String id, [List<String> foundations = const []]) =>
    Habit(id: id, name: id, actionId: 'a', foundations: foundations);

/// Sleep and eat; exercise on both; family's on exercise; read on
/// family's.
final _graph = HabitGraph(
  habits: [
    _habit('sleep'),
    _habit('eat'),
    _habit('gym', ['habit:sleep', 'habit:eat']),
    const Habit(
      id: 'fam',
      name: 'Family',
      actionId: '',
      personId: 'fam',
      foundations: ['habit:gym'],
    ),
    _habit('read', ['habit:fam', 'habit:gone', 'pal']),
    const Habit(id: 'gone', name: 'Gone', actionId: 'a', status: 'deleted'),
  ],
);

void main() {
  test('its nodes are the habits, not deleted: people by theirs', () {
    expect(_graph.nodes.keys.toSet(), {
      'habit:sleep',
      'habit:eat',
      'habit:gym',
      'habit:fam',
      'habit:read',
    });
    expect(_graph.nodes['habit:fam']!.isRelationship, isTrue);
    // A person, deleted habit or anything else is no node.
    expect(_graph.foundationsOf('habit:read'), ['habit:fam']);
  });

  test('a layer is one above the highest of its foundations', () {
    expect(
      [
        for (final id in [
          'habit:sleep',
          'habit:gym',
          'habit:fam',
          'habit:read',
        ])
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
    expect(_graph.withFoundations(['habit:fam']), {
      'habit:fam',
      'habit:gym',
      'habit:sleep',
      'habit:eat',
    });
    expect(_graph.builtOn('habit:eat'), {
      'habit:gym',
      'habit:fam',
      'habit:read',
    });
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
