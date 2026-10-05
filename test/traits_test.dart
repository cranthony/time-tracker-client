import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:time_tracker_client/models/event.dart';
import 'package:time_tracker_client/models/facets.dart';
import 'package:time_tracker_client/models/person.dart';
import 'package:time_tracker_client/models/trait.dart';
import 'package:time_tracker_client/screens/person_screen.dart';
import 'package:time_tracker_client/screens/traits_section.dart';
import 'package:time_tracker_client/services/people_repository.dart';
import 'package:time_tracker_client/services/traits_repository.dart';
import 'package:time_tracker_client/widgets/event_summary_dialog.dart';

const Part _novelty = {
  'kind': 'facet',
  'rubric': 'Was this activity or place new?',
  'engagement': 'with',
  'ratings': [
    {'score': 0, 'label': 'Routine'},
    {'score': 1, 'label': 'A twist'},
    {'score': 2, 'label': 'New activity or place'},
    {'score': 3, 'label': 'Both new'},
  ],
  'primitives': [
    {'name': 'action'},
    {'name': 'location_history', 'lookback_days': 180},
  ],
};

const _adventurous = Trait(
  id: 'adventurous',
  name: 'Adventurous',
  definition: 'Try new things together.',
  parts: [_novelty],
);
const _reliable = Trait(
  id: 'reliable',
  name: 'Reliable',
  parts: [
    {'kind': 'count', 'action_id': 'call', 'target': 1, 'interval_days': 7},
  ],
);

void main() {
  group('Facets', () {
    test('read from the server and written back without what is unset', () {
      final facets = Facets.fromJson({
        'with_person_ids': ['sam'],
        'location': 'the hall',
        'notes': null,
        'person_notes': {'sam': 'Tired', 'priya': ' '},
        'judgments': [
          {'trait_id': 'adventurous', 'person_id': 'sam', 'rating': 2},
          {'trait_id': 'broken'},
        ],
      })!;

      expect(facets.toJson(), {
        'with_person_ids': ['sam'],
        'location': 'the hall',
        'person_notes': {'sam': 'Tired'},
        'judgments': [
          {'trait_id': 'adventurous', 'person_id': 'sam', 'rating': 2},
        ],
      });
      expect(Facets.fromJson(null), isNull);
    });

    test('described in a line, naming people', () {
      const facets = Facets(
        withPersonIds: ['sam'],
        forPersonIds: [selfPersonId],
        location: 'home',
      );

      expect(
        facets.describe({'sam': 'Sam', selfPersonId: 'Self'}),
        'With Sam · For Self · @ home',
      );
    });

    test("keep Claude's judgments only for the people still there", () {
      const facets = Facets(
        withPersonIds: ['sam', 'priya'],
        judgments: [
          FacetJudgment(personId: 'sam', rating: 1),
          FacetJudgment(personId: 'priya', rating: 2),
        ],
      );

      final edited = facets.edited(
        withPersonIds: ['sam'],
        forPersonIds: const [],
        personNotes: {'sam': 'Happy', 'priya': 'Gone'},
      );

      expect(edited.judgments, [
        const FacetJudgment(personId: 'sam', rating: 1),
      ]);
      expect(edited.personNotes, {'sam': 'Happy'});
    });
  });

  group('traitProblem', () {
    test('accepts well-formed traits', () {
      expect(traitProblem(_adventurous), isNull);
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
              _novelty,
              {'kind': 'duration'},
            ],
          ),
        ),
        'Part 2: target, minutes is needed.',
      );
      expect(partProblem(const {'kind': 'nope'}), 'pick a kind.');
      expect(
        partProblem(const {'kind': 'count', 'target': 1, 'weight': -1}),
        'the weight must be 0 or more.',
      );
    });

    test('checks a facet whole', () {
      Part facet(Map<String, Object?> changes) => {..._novelty, ...changes};

      expect(partProblem(facet({'rubric': null})), 'rubric is needed.');
      expect(
        partProblem(facet({'engagement': 'near'})),
        'pick whether it rates events with them or for them.',
      );
      expect(
        partProblem(
          facet({
            'ratings': [
              {'score': 0, 'label': 'None'},
            ],
          }),
        ),
        'give it at least two ratings.',
      );
      expect(
        partProblem(
          facet({
            'ratings': [
              {'score': 0, 'label': 'None'},
              {'score': 0, 'label': 'Also none'},
            ],
          }),
        ),
        'each rating needs a score of its own.',
      );
      expect(
        partProblem(
          facet({
            'ratings': [
              {'score': 0, 'label': 'None'},
              {'score': 'x', 'label': 'Some'},
            ],
          }),
        ),
        'each rating needs a whole-number score.',
      );
      expect(
        partProblem(
          facet({
            'ratings': [
              {'score': 0, 'label': 'None'},
              {'score': 1, 'label': ' '},
            ],
          }),
        ),
        'say what each rating means.',
      );
      expect(
        partProblem(facet({'primitives': const []})),
        'pick at least one primitive.',
      );
      expect(
        partProblem(
          facet({
            'primitives': [
              {'name': 'action_history', 'lookback_days': 0},
            ],
          }),
        ),
        'a lookback must be a whole number of days, 1 or more.',
      );
    });
  });

  group('parts', () {
    test('are described in a line', () {
      expect(
        describePart(_novelty),
        'Facet: Was this activity or place new? (0-3, with them)',
      );
      expect(
        describePart(_reliable.parts.single, {'call': 'Call'}),
        'call every 7 days',
      );
      expect(
        describePart(const {
          'kind': 'duration',
          'target_min': 60,
          'interval_days': 7,
        }),
        '60 min of events every 7 days',
      );
    });

    test("a facet's ratings and primitives are read in order", () {
      expect(facetRatings(_novelty).map((r) => r.score), [0, 1, 2, 3]);
      expect(facetPrimitivesOf(_novelty), {
        'action': null,
        'location_history': 180,
      });
      expect(
        facetPrimitivesOf(const {
          'primitives': [
            {'name': 'action_history'},
          ],
        }),
        {'action_history': defaultLookbackDays},
      );
    });
  });

  group('TraitsSection', () {
    Future<InMemoryTraitsRepository> pump(WidgetTester tester) async {
      final repository = InMemoryTraitsRepository(
        traits: [_adventurous, _reliable],
        history: const [
          TraitDay(
            traitId: 'adventurous',
            name: 'Adventurous',
            day: '2026-10-01',
            score: 70,
            people: {'sam': 80, selfPersonId: 60},
          ),
        ],
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: _Open(
                (expanded, onExpanded) => TraitsSection(
                  repository: repository,
                  expanded: expanded,
                  onExpanded: onExpanded,
                  actions: const {'call': 'Call'},
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return repository;
    }

    testWidgets('lists the traits with their latest scores', (tester) async {
      await pump(tester);

      expect(find.text('Adventurous'), findsOneWidget);
      expect(find.text('Try new things together.'), findsOneWidget);
      expect(find.text('1 facet'), findsOneWidget);
      expect(find.text('70'), findsOneWidget);
      expect(find.text('Reliable'), findsOneWidget);
    });

    testWidgets('folds away from its heading', (tester) async {
      await pump(tester);

      await tester.tap(find.byIcon(Icons.expand_more));
      await tester.pumpAndSettle();

      expect(find.text('Adventurous'), findsNothing);
    });

    testWidgets('creates a trait from a facet, checking it first', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(800, 3000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final repository = await pump(tester);

      await tester.tap(find.byTooltip('New trait'));
      await tester.pumpAndSettle();
      await tester.enterText(find.widgetWithText(TextField, 'Name'), 'Kind');
      await tester.pump();
      expect(find.text('Give it at least one part.'), findsOneWidget);

      await tester.tap(find.text('Add part'));
      await tester.pumpAndSettle();
      expect(find.text('Part 1: rubric is needed.'), findsOneWidget);
      await tester.enterText(
        find.widgetWithText(TextField, 'Rubric'),
        'Was I kind?',
      );
      await tester.pump();
      expect(find.text('Part 1: say what each rating means.'), findsOneWidget);
      for (final (i, means) in ['No', 'A little', 'Yes', 'Very'].indexed) {
        await tester.enterText(
          find.widgetWithText(TextField, 'Means').at(i),
          means,
        );
      }
      // Rated for them, from their notes too, looking back a month.
      await tester.tap(find.text('For them'));
      await tester.tap(find.text('Person notes'));
      await tester.tap(find.text('Location history'));
      await tester.pump();
      await tester.enterText(find.widgetWithText(TextField, 'Lookback'), '30');
      await tester.pump();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      final created = (await repository.traits()).last;
      expect(created.id, 'kind');
      expect(created.parts.single, {
        'kind': 'facet',
        'rubric': 'Was I kind?',
        'engagement': 'for',
        'ratings': [
          {'score': 0, 'label': 'No'},
          {'score': 1, 'label': 'A little'},
          {'score': 2, 'label': 'Yes'},
          {'score': 3, 'label': 'Very'},
        ],
        'primitives': [
          {'name': 'action'},
          {'name': 'general_notes'},
          {'name': 'person_notes'},
          {'name': 'location_history', 'lookback_days': 30},
        ],
      });
    });

    testWidgets('picks the action a cadence counts', (tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final repository = await pump(tester);

      await tester.tap(find.text('Reliable'));
      await tester.pumpAndSettle();
      expect(find.text('Call'), findsOneWidget);
      await tester.tap(find.text('Call'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Any action').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(
        (await repository.traits()).firstWhere((t) => t.id == 'reliable').parts,
        [
          {'kind': 'count', 'target': 1, 'interval_days': 7},
        ],
      );
    });

    testWidgets('turns a trait off from its menu', (tester) async {
      final repository = await pump(tester);

      await tester.tap(find.byTooltip('More for Reliable'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Turn off'));
      await tester.pumpAndSettle();

      expect(
        (await repository.traits())
            .firstWhere((t) => t.id == 'reliable')
            .status,
        'off',
      );
    });
  });

  testWidgets("a person's page shows their traits, notes, history and "
      "events, and Claude's judgments behind a score", (tester) async {
    // Tall enough to show the whole page at once.
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final repository = InMemoryTraitsRepository(
      ratings: {
        'sam': const TraitsRating(
          rating: 67,
          day: '2026-10-01',
          traits: [
            TraitScore(
              traitId: 'adventurous',
              name: 'Adventurous',
              weight: 2,
              score: 67,
              parts: [
                PartScore(
                  key: 'facet',
                  kind: 'facet',
                  score: 67,
                  rubric: 'Was this activity or place new?',
                  said: 'Mean rating 2.0 of 3 over 1 event',
                  eventIds: ['e1'],
                  judgments: [
                    FacetJudgment(eventId: 'e1', rating: 2, why: 'A new club'),
                  ],
                ),
              ],
            ),
          ],
        ),
      },
      digests: {
        'sam': const PersonDigest(
          personId: 'sam',
          eventsCounted: 1,
          actions: [
            DigestEntry(
              label: 'listen_music',
              count: 1,
              first: '2026-10-01',
              last: '2026-10-01',
            ),
          ],
          events: [
            {
              'id': 'e1',
              'summary': 'Jazz night',
              'start': '2026-10-01T18:00:00',
              'end': '2026-10-01T20:00:00',
              'goal_ids': ['listen_music'],
              'facets': {
                'with_person_ids': ['sam'],
                'location': 'the cellar',
                'person_notes': {'sam': 'Loved the trumpet'},
              },
            },
          ],
        ),
      },
    );
    await tester.pumpWidget(
      MaterialApp(
        home: PersonScreen(
          person: const Person(
            id: 'sam',
            name: 'Sam',
            circleIds: ['close'],
            notes: '- loves jazz',
            health: 67,
          ),
          traits: repository,
          circles: const [Circle(id: 'close', name: 'Close friends')],
          personNames: const {'sam': 'Sam'},
          actionNames: const {'listen_music': 'Listen to music'},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Close friends'), findsOneWidget);
    expect(find.text('67 · 2026-10-01'), findsOneWidget);
    expect(find.text('Adventurous ×2'), findsOneWidget);
    expect(find.text('- loves jazz'), findsOneWidget);
    expect(find.textContaining('Listen to music ×1'), findsOneWidget);
    expect(find.text('Jazz night'), findsOneWidget);
    expect(find.textContaining('“Loved the trumpet”'), findsOneWidget);

    await tester.tap(find.text('Adventurous ×2'));
    await tester.pumpAndSettle();

    expect(find.text('Mean rating 2.0 of 3 over 1 event'), findsOneWidget);
    expect(
      find.textContaining('Jazz night — With Sam · @ the cellar'),
      findsOneWidget,
    );
    expect(find.textContaining('Rated 2: A new club'), findsOneWidget);
  });

  testWidgets("what happened at an event is edited and saved with it", (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    Map<String, Object?>? saved;
    final event = Event(
      id: 'e1',
      summary: 'Dinner',
      start: DateTime(2026, 10, 1, 18),
      end: DateTime(2026, 10, 1, 20),
      properties: const {
        'facets': {'location': 'home'},
      },
    );
    await tester.pumpWidget(
      PeopleScope(
        repository: InMemoryPeopleRepository(
          people: const [Person(id: 'sam', name: 'Sam')],
        ),
        child: MaterialApp(
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
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(find.text('@ home'), findsOneWidget);
    await tester.tap(find.text('@ home'));
    await tester.pumpAndSettle();
    // Self is always there to pick.
    expect(find.widgetWithText(FilterChip, 'Self'), findsNWidgets(2));
    await tester.tap(find.widgetWithText(FilterChip, 'Sam').first);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Notes on Sam'),
      'Glad to be out',
    );
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(find.text('With Sam · @ home'), findsOneWidget);
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(saved, {
      'facets': {
        'with_person_ids': ['sam'],
        'location': 'home',
        'person_notes': {'sam': 'Glad to be out'},
      },
    });
  });
}

/// A section, opened and folded as its heading's tapped.
class _Open extends StatefulWidget {
  const _Open(this.builder);

  final Widget Function(bool expanded, ValueChanged<bool> onExpanded) builder;

  @override
  State<_Open> createState() => _OpenState();
}

class _OpenState extends State<_Open> {
  bool _expanded = true;

  @override
  Widget build(BuildContext context) =>
      widget.builder(_expanded, (open) => setState(() => _expanded = open));
}
