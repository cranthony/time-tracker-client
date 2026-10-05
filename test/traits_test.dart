import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:time_tracker_client/models/event.dart';
import 'package:time_tracker_client/models/facets.dart';
import 'package:time_tracker_client/models/goal.dart';
import 'package:time_tracker_client/models/measure.dart';
import 'package:time_tracker_client/models/trait.dart';
import 'package:time_tracker_client/screens/goal_traits_screen.dart';
import 'package:time_tracker_client/screens/traits_screen.dart';
import 'package:time_tracker_client/services/traits_repository.dart';
import 'package:time_tracker_client/widgets/event_summary_dialog.dart';
import 'package:time_tracker_client/widgets/measure_editor.dart';

const _reliable = Trait(
  id: 'reliable',
  name: 'Reliable',
  definition: 'Keep contact going.',
  parts: [
    {'kind': 'continuity'},
  ],
);
const _generous = Trait(
  id: 'generous',
  name: 'Generous',
  parts: [
    {'kind': 'attention'},
  ],
);

void main() {
  group('Facets', () {
    test('read from the server and written back without what is unset', () {
      final facets = Facets.fromJson({
        'with_goal_ids': ['p1'],
        'activity': 'salsa social',
        'new': 'place',
        'attention': 3,
        'why': null,
      })!;

      expect(facets.toJson(), {
        'with_goal_ids': ['p1'],
        'activity': 'salsa social',
        'new': 'place',
        'attention': 3,
      });
      expect(Facets.fromJson(null), isNull);
    });

    test('described in a line, naming goals', () {
      const facets = Facets(
        withGoalIds: ['p1'],
        forGoalIds: ['p2'],
        activity: 'dinner',
        place: 'home',
        newness: 'none',
        effort: 2,
        attention: 3,
      );

      expect(
        facets.describe({'p1': 'Person', 'p2': 'Other'}),
        'With Person · For Other · dinner @ home · effort 2, attention 3',
      );
    });
  });

  group('traitProblem', () {
    test('accepts a well-formed trait', () {
      expect(traitProblem(_reliable), isNull);
    });

    test('says what is wrong, part by part', () {
      expect(traitProblem(const Trait(name: ' ')), 'Give it a name.');
      expect(
        traitProblem(const Trait(name: 'Kind')),
        'Give it at least one part.',
      );
      expect(
        traitProblem(
          const Trait(
            name: 'Kind',
            parts: [
              {'kind': 'prep'},
              {'kind': 'effort_paid'},
            ],
          ),
        ),
        'Part 2: target, effort-minutes is needed.',
      );
      expect(partProblem(const {'kind': 'nope'}), 'pick a kind.');
      expect(
        partProblem(const {'kind': 'prep_regularity', 'weeks': 0}),
        'weeks must be a whole number, 1 or more.',
      );
      expect(
        partProblem(const {'kind': 'together_creative', 'min_creative': 4}),
        'at least creative must be 1, 2 or 3.',
      );
      expect(
        partProblem(const {'kind': 'prep', 'weight': -1}),
        'the weight must be 0 or more.',
      );
    });
  });

  group('withWhatMatters', () {
    test("replaces the section's text, keeping the rest", () {
      const description =
          'Old friend.\n\n## What matters to them\n\n- old\n\n## Other\n\nMore.';

      expect(
        withWhatMatters(description, '- new'),
        'Old friend.\n\n## What matters to them\n\n- new\n\n## Other\n\nMore.',
      );
    });

    test('adds the section if there is none', () {
      expect(
        withWhatMatters('Old friend.', '- likes tea'),
        'Old friend.\n\n## What matters to them\n\n- likes tea',
      );
      expect(
        withWhatMatters('', '- likes tea'),
        '## What matters to them\n\n- likes tea',
      );
    });
  });

  group('traits measure', () {
    test('is described and checked', () {
      expect(
        describeMeasure(const {'kind': 'traits', 'traits': 'all'}),
        'All traits',
      );
      expect(
        describeMeasure(const {
          'kind': 'traits',
          'traits': ['reliable', 'generous'],
          'weights': {'generous': 2},
        }),
        'Reliable, Generous ×2',
      );
      expect(measureProblem(const {'kind': 'traits', 'traits': 'all'}), isNull);
      expect(
        measureProblem(const {'kind': 'traits', 'traits': <String>[]}),
        'Pick the traits it rates by, or all of them.',
      );
      expect(
        measureProblem(const {
          'kind': 'traits',
          'traits': 'all',
          'weights': {'reliable': -1},
        }),
        "Each trait's weight must be 0 or more.",
      );
    });

    testWidgets('picks traits and their weights', (tester) async {
      final changes = <Measure?>[];
      await tester.pumpWidget(
        TraitsScope(
          repository: InMemoryTraitsRepository(traits: [_reliable, _generous]),
          child: MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: MeasureEditor(
                  measure: const {'kind': 'traits', 'traits': 'all'},
                  onChanged: changes.add,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Every active trait'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilterChip, 'Generous'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'Generous weight'),
        '2',
      );
      await tester.pump();

      expect(changes.last, {
        'kind': 'traits',
        'traits': ['generous'],
        'weights': {'generous': 2},
      });
    });
  });

  group('TraitsScreen', () {
    Future<InMemoryTraitsRepository> pump(WidgetTester tester) async {
      final repository = InMemoryTraitsRepository(
        traits: [_reliable, _generous],
        history: const [
          TraitDay(
            traitId: 'reliable',
            name: 'Reliable',
            day: '2026-10-01',
            score: 70,
            goals: {'p1': 80, 'p2': 60},
          ),
        ],
      );
      await tester.pumpWidget(
        MaterialApp(home: TraitsScreen(repository: repository)),
      );
      await tester.pumpAndSettle();
      return repository;
    }

    testWidgets('lists the traits with their latest scores', (tester) async {
      await pump(tester);

      expect(find.text('Reliable'), findsOneWidget);
      expect(find.text('Keep contact going.'), findsOneWidget);
      expect(find.text('70'), findsOneWidget);
      expect(find.text('Generous'), findsOneWidget);
    });

    testWidgets('creates a trait, refusing one without parts', (tester) async {
      final repository = await pump(tester);

      await tester.tap(find.byTooltip('New trait'));
      await tester.pumpAndSettle();
      await tester.enterText(find.widgetWithText(TextField, 'Name'), 'Kind');
      await tester.pump();
      expect(find.text('Give it at least one part.'), findsOneWidget);

      await tester.tap(find.text('Add part'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      final traits = await repository.traits();
      expect(traits.last.id, 'kind');
      expect(traits.last.parts, [
        {'kind': 'prep'},
      ]);
    });

    testWidgets('turns a trait off from its menu', (tester) async {
      final repository = await pump(tester);

      await tester.tap(find.byTooltip('More for Generous'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Turn off'));
      await tester.pumpAndSettle();

      expect(
        (await repository.traits())
            .firstWhere((t) => t.id == 'generous')
            .status,
        'off',
      );
    });
  });

  group('GoalTraitsScreen', () {
    testWidgets('shows its traits, what matters, history and events, and '
        'what is behind a score', (tester) async {
      final repository = InMemoryTraitsRepository(
        ratings: {
          'p1': const TraitsRating(
            rating: 75,
            day: '2026-10-01',
            traits: [
              TraitScore(
                traitId: 'generous',
                name: 'Generous',
                score: 100,
                parts: [
                  PartScore(
                    key: 'attention',
                    kind: 'attention',
                    score: 100,
                    said: 'Mean attention 3.0 of 3 over 1 events',
                    eventIds: ['e1'],
                  ),
                ],
              ),
            ],
          ),
        },
        digests: {
          'p1': GoalDigest(
            goalId: 'p1',
            eventsCounted: 1,
            withFacets: 1,
            activities: const [
              DigestEntry(
                label: 'jazz club',
                count: 1,
                first: '2026-10-01',
                last: '2026-10-01',
              ),
            ],
            whatMatters: '- 2026-09-01: loves jazz',
            events: [
              {
                'id': 'e1',
                'summary': 'Jazz night',
                'start': '2026-10-01T18:00:00',
                'end': '2026-10-01T20:00:00',
                'facets': {'activity': 'jazz club', 'attention': 3},
              },
            ],
          ),
        },
      );
      await tester.pumpWidget(
        MaterialApp(
          home: GoalTraitsScreen(
            goal: const Goal(id: 'p1', name: 'Person'),
            repository: repository,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('75 · 2026-10-01'), findsOneWidget);
      expect(find.text('- 2026-09-01: loves jazz'), findsOneWidget);
      expect(find.textContaining('jazz club ×1'), findsOneWidget);
      expect(find.text('Jazz night'), findsOneWidget);

      await tester.tap(find.text('Generous'));
      await tester.pumpAndSettle();

      expect(
        find.text('Mean attention 3.0 of 3 over 1 events'),
        findsOneWidget,
      );
      expect(
        find.textContaining('Jazz night — jazz club · attention 3'),
        findsOneWidget,
      );
    });

    testWidgets('edits what matters to them in the description', (
      tester,
    ) async {
      final repository = InMemoryTraitsRepository(
        ratings: {'p1': const TraitsRating(rating: 50)},
        descriptions: {'p1': 'Old friend.'},
      );
      await tester.pumpWidget(
        MaterialApp(
          home: GoalTraitsScreen(
            goal: const Goal(id: 'p1', name: 'Person'),
            repository: repository,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Edit what matters to them'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '- likes tea');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(
        await repository.description('p1'),
        'Old friend.\n\n## What matters to them\n\n- likes tea',
      );
    });
  });

  testWidgets("an event's facets are edited and saved with it", (tester) async {
    Map<String, Object?>? saved;
    final event = Event(
      id: 'e1',
      summary: 'Dinner',
      start: DateTime(2026, 10, 1, 18),
      end: DateTime(2026, 10, 1, 20),
      properties: const {
        'facets': {'activity': 'dinner'},
      },
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => showEventSummaryDialog(
              context,
              event,
              save: (changes) async {
                saved = changes;
                return [event];
              },
            ),
            child: const Text('Open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(find.text('dinner'), findsOneWidget);
    await tester.tap(find.text('dinner'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('3').last);
    await tester.tap(find.text('3').last); // Attention.
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(saved, {
      'facets': {'activity': 'dinner', 'attention': 3},
    });
  });
}
