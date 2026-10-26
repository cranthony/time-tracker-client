import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:time_tracker_client/models/event.dart';
import 'package:time_tracker_client/models/habit.dart';
import 'package:time_tracker_client/models/note.dart';
import 'package:time_tracker_client/models/person.dart';
import 'package:time_tracker_client/models/scoring.dart';
import 'package:time_tracker_client/models/trait.dart';
import 'package:time_tracker_client/models/trait_scores.dart';
import 'package:time_tracker_client/widgets/relationship_habit_dialog.dart';

const _judgment = {
  'kind': 'judgment',
  'rubric': 'Good?',
  'ratings': {'0': 'No', '1': 'A little', '2': 'Yes'},
  'facts': ['action'],
};

const _traits = [
  Trait(id: 'reliable', name: 'Reliable', parts: [_judgment]),
  Trait(id: 'kind', name: 'Kind', parts: [_judgment]),
];

/// An event yesterday with [who], each judged as [ratings] (by trait id,
/// out of 2).
Event _with(String id, String who, Map<String, int> ratings) {
  final start = DateTime(2026, 10, 1, 12);
  return Event.fromJson({
    'id': id,
    'summary': id,
    'start': localIsoTimestamp(start),
    'end': localIsoTimestamp(start.add(const Duration(hours: 1))),
    'facts': {
      'with_ids': [who],
    },
    'judgments': {
      who: {
        for (final MapEntry(:key, :value) in ratings.entries)
          key: {
            'judgment': {'rating': value, 'scale': 2},
          },
      },
    },
  });
}

void main() {
  group("a person's or circle's habit", () {
    test('is read and sent with whose it is, and no action', () {
      final habit = Habit.fromJson({
        'id': 'h1',
        'name': 'Sam · except Kind',
        'default_name': 'Sam · except Kind',
        'person_id': 'sam',
        'status': 'active',
        'traits': {
          'select': 'all',
          'except': ['kind'],
        },
      });

      expect(habit.isRelationship, isTrue);
      expect(habit.ownName, isFalse);
      expect(habit.traits.applies('reliable'), isTrue);
      expect(habit.traits.applies('kind'), isFalse);
      expect(habit.toJson(), {
        'id': 'h1',
        'name': 'Sam · except Kind',
        'person_id': 'sam',
        'status': 'active',
        'traits': {
          'select': 'all',
          'except': ['kind'],
        },
      });
    });

    test('is named by them and its traits, as the server names it', () {
      const names = {'reliable': 'Reliable', 'kind': 'Kind', 'fun': 'Fun'};
      String name(PersonTraits traits) =>
          relationshipHabitName('Sam', traits, names);

      expect(name(const PersonTraits()), 'Sam');
      expect(name(const PersonTraits(select: ['reliable'])), 'Sam · Reliable');
      expect(
        name(const PersonTraits(select: ['reliable', 'kind', 'fun'])),
        'Sam · Reliable, Kind +1',
      );
      expect(
        name(const PersonTraits(except: ['reliable'])),
        'Sam · except Reliable',
      );
    });

    test('keeps all but a few as those left out, else those picked', () {
      const all = ['a', 'b', 'c', 'd', 'e'];
      PersonTraits picked(Set<String> on) => relationshipSelection(on, all);

      expect(picked({...all}).isDefault, isTrue);
      expect(picked({'a', 'b', 'c'}).except, ['d', 'e']);
      expect(picked({'a', 'b'}).select, ['a', 'b']);
    });

    test("is scored by their judgments, on the traits it picks of theirs; a "
        "circle's, as the circle combines its people", () {
      const sam = Person(id: 'sam', name: 'Sam');
      const ana = Person(id: 'ana', name: 'Ana');
      final events = [
        _with('e1', 'sam', {'reliable': 2, 'kind': 0}),
        _with('e2', 'ana', {'reliable': 0, 'kind': 2}),
      ];
      TraitScores compute(List<Habit> habits, {Aggregation? circles}) =>
          TraitScores.compute(
            traits: _traits,
            people: const [sam, ana],
            habits: habits,
            circles: const [
              Circle(id: 'pals', name: 'Pals', memberIds: ['sam', 'ana']),
            ],
            events: events,
            today: DateTime(2026, 10, 2),
            days: 1,
            defaults: ScoringDefaults(circles: circles),
          );
      const reliable = Habit(
        id: 'r',
        name: 'Sam · Reliable',
        actionId: '',
        personId: 'sam',
        traits: PersonTraits(select: ['reliable']),
      );
      const rest = Habit(
        id: 'k',
        name: 'Sam · except Reliable',
        actionId: '',
        personId: 'sam',
        traits: PersonTraits(except: ['reliable']),
      );
      const pals = Habit(
        id: 'p',
        name: 'Pals · Reliable',
        actionId: '',
        circleId: 'pals',
        traits: PersonTraits(select: ['reliable']),
      );

      final scores = compute(const [reliable, rest, pals]);
      expect(scores.health('sam'), 50);
      expect(scores.health(reliable.subject), 100);
      expect(scores.health(rest.subject), 0);
      // Sam's 100 and Ana's 0, by the mean; or the lowest.
      expect(scores.health(pals.subject), 50);
      expect(
        compute(const [pals], circles: Aggregation.lowest).health(pals.subject),
        0,
      );
      expect(scores.digest(reliable.subject).eventsCounted, 1);
    });
  });

  testWidgets('its editor names it by the traits picked, again whenever '
      'they change', (tester) async {
    Map<String, Object?>? saved;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => showRelationshipHabitEditor(
              context,
              whose: 'Sam',
              targetField: 'person_id',
              targetId: 'sam',
              traits: _traits,
              save: (fields) async {
                saved = fields;
                return Habit.fromJson({'id': 'h', ...fields});
              },
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(TextField, 'Sam'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'Mine');
    await tester.tap(find.widgetWithText(FilterChip, 'Kind'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(TextField, 'Sam · except Kind'), findsOneWidget);

    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(saved, {
      'name': 'Sam · except Kind',
      'person_id': 'sam',
      'traits': {
        'select': 'all',
        'except': ['kind'],
      },
    });
  });
}
