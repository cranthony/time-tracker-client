import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:time_tracker_client/models/event.dart';
import 'package:time_tracker_client/models/facts.dart';
import 'package:time_tracker_client/models/note.dart';
import 'package:time_tracker_client/models/person.dart';
import 'package:time_tracker_client/models/trait.dart';

import 'dart:async';

import 'package:time_tracker_client/screens/events_screen.dart';
import 'package:time_tracker_client/screens/person_screen.dart';
import 'package:time_tracker_client/screens/traits_pane.dart';
import 'package:time_tracker_client/services/event_store.dart';
import 'package:time_tracker_client/services/events_repository.dart';
import 'package:time_tracker_client/services/mcp_client.dart';
import 'package:time_tracker_client/services/people_repository.dart';
import 'package:time_tracker_client/services/plan_memory.dart';
import 'package:time_tracker_client/services/traits_repository.dart';
import 'package:time_tracker_client/widgets/event_summary_dialog.dart';
import 'package:time_tracker_client/widgets/facts_dialog.dart';

const Part _novelty = {
  'kind': 'judgment',
  'rubric': 'Was this activity or place new?',
  'ratings': {
    '0': 'Routine',
    '1': 'A twist',
    '2': 'New activity or place',
    '3': 'Both new',
  },
  'facts': [
    'action',
    {'fact': 'location_history', 'lookback_days': 180},
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
    {'kind': 'count', 'action': 'call', 'target': 1, 'interval_days': 7},
  ],
);

void main() {
  group('Facts', () {
    test('read from the server and written back without what is unset', () {
      final facts = Facts.fromJson({
        'location_id': 'hall',
        'with_ids': ['sam'],
        'for_ids': null,
        'notes': {'sam': 'Tired', selfPersonId: ' '},
      })!;

      expect(facts.toJson(), {
        'location_id': 'hall',
        'with_ids': ['sam'],
        'notes': {'sam': 'Tired'},
      });
      expect(Facts.fromJson(null), isNull);
    });

    test('described in a line, naming people and the location', () {
      const facts = Facts(
        withIds: ['sam'],
        forIds: ['priya'],
        locationId: 'home',
      );

      expect(
        facts.describe({'sam': 'Sam', 'priya': 'Priya'}, {'home': 'Home'}),
        'With Sam · For Priya · @ Home',
      );
    });

    test('are checked as the server checks them', () {
      expect(const Facts(withIds: [selfPersonId]).problem, isNotNull);
      expect(const Facts(withIds: ['sam'], forIds: ['sam']).problem, isNotNull);
      expect(
        const Facts(forIds: ['sam'], notes: {'sam': 'Happy'}).problem,
        'Notes are only for those who were there.',
      );
      expect(
        const Facts(
          withIds: ['sam'],
          notes: {'sam': 'Happy', selfPersonId: 'Tired'},
        ).problem,
        isNull,
      );
    });
  });

  test("an event's judgments are read by person, trait and part", () {
    final judgments = judgmentsFromJson({
      'sam': {
        'adventurous': {
          'judgment': {'rating': 2, 'scale': 3, 'reasoning': 'A new club'},
          'broken': {'scale': 3},
        },
      },
    }, eventId: 'e1');

    expect(judgments, [
      const Judgment(
        eventId: 'e1',
        personId: 'sam',
        traitId: 'adventurous',
        part: 'judgment',
        rating: 2,
        scale: 3,
        reasoning: 'A new club',
      ),
    ]);
    expect(judgmentsToJson(judgments), {
      'sam': {
        'adventurous': {
          'judgment': {'rating': 2, 'scale': 3, 'reasoning': 'A new club'},
        },
      },
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
      expect(partProblem(const {'kind': 'facet'}), 'pick a kind.');
      expect(
        partProblem(const {'kind': 'count', 'target': 1, 'weight': -1}),
        'the weight must be 0 or more.',
      );
      expect(
        partProblem(const {
          'kind': 'count',
          'target': 1,
          'engagement_type': 'near',
        }),
        'pick whether it reads events with them or for them.',
      );
      expect(
        partProblem(const {'kind': 'follow_through', 'penalty': 120}),
        'lost per cancellation must be from 0 to 100.',
      );
    });

    test('checks a judgment whole', () {
      Part judgment(Map<String, Object?> changes) => {..._novelty, ...changes};

      expect(partProblem(judgment({'rubric': null})), 'rubric is needed.');
      expect(
        partProblem(
          judgment({
            'ratings': {'0': 'None'},
          }),
        ),
        'give it at least two ratings.',
      );
      expect(
        partProblem(
          judgment({
            'ratings': ['None', 'Also none'],
          }),
        ),
        'each rating needs a score of its own.',
      );
      expect(
        partProblem(
          judgment({
            'ratings': {'0': 'None', 'x': 'Some'},
          }),
        ),
        'each rating needs a whole-number score, from 0.',
      );
      expect(
        partProblem(
          judgment({
            'ratings': {'0': 'None', '1': ' '},
          }),
        ),
        'say what each rating means.',
      );
      expect(
        partProblem(judgment({'facts': const []})),
        'pick at least one fact to judge by.',
      );
      expect(
        partProblem(
          judgment({
            'facts': [
              {'fact': 'action_history', 'lookback_days': 0},
            ],
          }),
        ),
        'a lookback must be a whole number of days, 1 or more.',
      );
      expect(
        partProblem(
          judgment({
            'facts': ['action', 'person_notes', 'what_matters'],
          }),
        ),
        isNull,
      );
      expect(
        partProblem(
          judgment({
            'facts': ['mood'],
          }),
        ),
        "it has a fact the app doesn't know.",
      );
    });
  });

  group('parts', () {
    test('are described in a line', () {
      expect(
        describePart(_novelty),
        'Judgment: Was this activity or place new? (0-3, with them)',
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

    test("a judgment's ratings and facts are read in order", () {
      expect(judgmentRatings(_novelty).map((r) => r.score), [0, 1, 2, 3]);
      expect(judgmentFactsOf(_novelty), {
        'action': null,
        'location_history': 180,
      });
      expect(
        judgmentFactsOf(const {
          'facts': ['action_history'],
        }),
        {'action_history': defaultLookbackDays},
      );
      expect(judgmentFactsJson({'action': null, 'action_history': 90}), [
        'action',
        {'fact': 'action_history', 'lookback_days': 90},
      ]);
    });
  });

  test('McpTraitsRepository sends the server what it takes', () async {
    final client = _RecordingClient(
      (name, _) => {
        'id': 'kind',
        'name': 'Kind',
        'parts': [_novelty],
      },
    );
    final repository = McpTraitsRepository(client);

    await repository.updateTrait('kind', {
      'name': 'Kind',
      'definition': null,
      'parts': [_novelty],
    });

    expect(client.calls.single.$1, 'update_trait');
    expect(client.calls.single.$2, ({
      'trait': {
        'id': 'kind',
        'name': 'Kind',
        'parts': [_novelty],
      },
      'clear_fields': ['definition'],
    }));
  });

  group('TraitsPane', () {
    /// Yesterday's dinner with Sam: a new place for Sam (3 of 3), the
    /// usual for Self (1 of 3).
    List<Event> dinner() => [
      _yesterday(
        'dinner',
        'Dinner',
        withIds: ['sam'],
        judgments: {
          'sam': {
            'adventurous': {
              'judgment': {'rating': 3, 'scale': 3},
            },
          },
          selfPersonId: {
            'adventurous': {
              'judgment': {'rating': 1, 'scale': 3},
            },
          },
        },
      ),
    ];

    Future<InMemoryTraitsRepository> pump(
      WidgetTester tester, {
      List<Event>? events,
    }) async {
      final repository = InMemoryTraitsRepository(
        traits: [_adventurous, _reliable],
      );
      final memory = await _scoredMemory(events ?? dinner());
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TraitsPane(
              repository: repository,
              memory: memory,
              actions: const {'call': 'Social › Call', 'social': 'Social'},
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
      expect(find.text('1 judgment'), findsOneWidget);
      // Everyone's mean: Sam's 100 and Self's 33.
      expect(find.text('67'), findsOneWidget);
      expect(find.text('Reliable'), findsOneWidget);
    });

    testWidgets("tapping one opens its page: its health, everyone's mean, "
        'and its parts', (tester) async {
      await pump(tester);

      await tester.tap(find.text('Adventurous'));
      await tester.pumpAndSettle();
      expect(find.text('Health'), findsOneWidget);
      expect(find.text('${_dayKey(-1)} · mean of 2 people'), findsOneWidget);
      expect(find.text('67'), findsOneWidget);
      expect(find.text('Parts'), findsOneWidget);
      expect(find.text('Applies to'), findsNothing);

      // Its days, and how one person's day was scored, from the events.
      await tester.tap(find.text('Health'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(_dayKey(-1)));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sam'));
      await tester.pumpAndSettle();
      expect(
        find.text('Mean of 1 judgment(s) in the last 30 days'),
        findsOneWidget,
      );
      expect(find.textContaining('Dinner — With Sam'), findsOneWidget);
    });

    testWidgets("one with nothing to score it by says so", (tester) async {
      await pump(tester, events: const []);

      await tester.tap(find.text('Adventurous'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Not scored yet'), findsOneWidget);
    });

    testWidgets('searches them by name, definition and parts', (tester) async {
      await pump(tester);

      await tester.enterText(find.byType(TextField), 'new together');
      await tester.pumpAndSettle();
      expect(find.text('Adventurous'), findsOneWidget);
      expect(find.text('Reliable'), findsNothing);

      // A part's action, by its path.
      await tester.enterText(find.byType(TextField), 'social call');
      await tester.pumpAndSettle();
      expect(find.text('Adventurous'), findsNothing);
      expect(find.text('Reliable'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'kindness');
      await tester.pumpAndSettle();
      expect(find.text('Nothing matches “kindness”.'), findsOneWidget);
    });

    testWidgets('creates a trait from a judgment, checking it first', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(800, 3200);
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
      // Read for them, from their notes too, looking back a fortnight.
      await tester.tap(find.text('For them'));
      await tester.tap(find.text('Person notes'));
      await tester.tap(find.text('Location history'));
      await tester.pump();
      await tester.enterText(find.widgetWithText(TextField, 'Lookback'), '14');
      await tester.pump();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      final created = (await repository.traits()).last;
      expect(created.id, 'kind');
      expect(created.parts.single, {
        'kind': 'judgment',
        'engagement_type': 'for',
        'rubric': 'Was I kind?',
        'ratings': {'0': 'No', '1': 'A little', '2': 'Yes', '3': 'Very'},
        'facts': [
          'action',
          'general_notes',
          'person_notes',
          {'fact': 'location_history', 'lookback_days': 14},
        ],
      });
    });

    testWidgets('picks the action or group a cadence counts', (tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final repository = await pump(tester);

      // Its page first, then its editor from the pencil.
      await tester.tap(find.text('Reliable'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Edit Reliable'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Social › Call'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Social').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(
        (await repository.traits()).firstWhere((t) => t.id == 'reliable').parts,
        [
          {
            'kind': 'count',
            'action': 'social',
            'target': 1,
            'interval_days': 7,
          },
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

  group("a person's page", () {
    final traits = InMemoryTraitsRepository(traits: [_adventurous, _reliable]);
    final jazz = _yesterday(
      'e1',
      'Jazz night',
      actions: ['listen_music'],
      withIds: ['sam'],
      location: 'cellar',
      notes: {'sam': 'Loved the trumpet'},
      judgments: {
        'sam': {
          'adventurous': {
            'judgment': {'rating': 2, 'scale': 3, 'reasoning': 'A new club'},
          },
        },
      },
    );
    final sam = Person(
      id: 'sam',
      name: 'Sam',
      context: 'from salsa',
      circleIds: ['close'],
      whatMatters: '- loves jazz',
      traits: PersonTraits(
        parts: {
          'reliable': [
            {
              'kind': 'count',
              'action': 'call',
              'target': 1,
              'interval_days': 14,
            },
          ],
        },
      ),
      // Called off the day before yesterday, against Reliable.
      cancelledEvents: [
        CancelledEvent(
          eventId: 'coffee',
          summary: 'Coffee with Sam',
          start: DateTime(2026, 10, 3, 8),
          end: DateTime(2026, 10, 3, 9),
          actionIds: const ['call'],
          parts: const ['reliable/follow_through'],
          cancelledAt: DateTime(2026, 10, 3, 7),
          source: 'delete_event',
        ),
      ],
    );

    Future<void> pump(WidgetTester tester, {PlanMemory? memory}) async {
      // Tall enough to show the whole page at once.
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: PersonScreen(
            person: sam,
            traits: traits,
            memory: memory,
            circles: const [Circle(id: 'close', name: 'Close friends')],
            personNames: const {'sam': 'Sam'},
            actionNames: const {
              'listen_music': 'Listen to music',
              'call': 'Call',
            },
            locationNames: const {'cellar': 'The Cellar'},
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets("shows who they are, their traits and own parts, scores, "
        "history and events, and Claude's judgments behind a score", (
      tester,
    ) async {
      await pump(tester, memory: await _scoredMemory([jazz], people: [sam]));

      expect(find.text('from salsa'), findsOneWidget);
      expect(find.text('Close friends'), findsOneWidget);
      expect(find.text('Every active trait'), findsOneWidget);
      expect(find.text('Reliable, their own'), findsOneWidget);
      expect(find.text('call every 14 days'), findsOneWidget);
      // Adventurous's 67, and no call in 14 days, 0: 34 yesterday.
      expect(find.text('34 · ${_dayKey(-1)}'), findsOneWidget);
      expect(find.text('Relationship health'), findsOneWidget);
      expect(find.text('- loves jazz'), findsOneWidget);
      expect(find.textContaining('Listen to music ×1'), findsOneWidget);
      expect(find.text('Jazz night'), findsOneWidget);
      expect(find.textContaining('“Loved the trumpet”'), findsOneWidget);
      // What was cancelled, against their follow-through.
      expect(find.text('Cancelled'), findsOneWidget);
      expect(find.text('Coffee with Sam'), findsOneWidget);
      expect(find.textContaining('with them'), findsOneWidget);
      expect(find.textContaining('Call'), findsWidgets);
      expect(find.textContaining('— deleted'), findsOneWidget);
      expect(find.textContaining('Counts against Reliable'), findsOneWidget);

      await tester.tap(find.text('Adventurous'));
      await tester.pumpAndSettle();

      expect(
        find.text('Mean of 1 judgment(s) in the last 30 days'),
        findsOneWidget,
      );
      expect(
        find.textContaining('Jazz night — With Sam · @ The Cellar'),
        findsOneWidget,
      );
      expect(find.textContaining('Rated 2: A new club'), findsOneWidget);
    });

    testWidgets("leaves out scores and history where they aren't worked "
        'out', (tester) async {
      await pump(tester);

      expect(find.text('Every active trait'), findsOneWidget);
      expect(find.text('- loves jazz'), findsOneWidget);
      expect(find.text('History'), findsNothing);
      expect(find.text('Events'), findsNothing);
    });
  });

  testWidgets('what happened at an event is edited and saved with it, '
      'with its judgments shown', (tester) async {
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
        'facts': {'location_id': 'home'},
        'judgments': {
          selfPersonId: {
            'adventurous': {
              'judgment': {'rating': 1, 'scale': 3, 'reasoning': 'Usual'},
            },
          },
        },
      },
    );
    final people = InMemoryPeopleRepository(
      people: const [
        Person(id: 'sam', name: 'Sam'),
        Person(id: 'priya', name: 'Priya'),
      ],
      locations: const [Location(id: 'home', name: 'Home')],
    );
    await tester.pumpWidget(
      TraitsScope(
        repository: InMemoryTraitsRepository(traits: [_adventurous]),
        child: PeopleScope(
          repository: people,
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
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(find.text('@ Home'), findsOneWidget);
    expect(find.text('1 judgment by Claude'), findsOneWidget);
    await tester.tap(find.text('@ Home'));
    await tester.pumpAndSettle();
    // Self is at every event: not to pick.
    expect(find.widgetWithText(FilterChip, 'Self'), findsNothing);
    expect(
      find.textContaining('Self · Adventurous: 1 of 3 — Usual'),
      findsOneWidget,
    );
    await tester.tap(find.widgetWithText(FilterChip, 'Sam').first);
    await tester.tap(find.widgetWithText(FilterChip, 'Priya').last);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Notes on Sam'),
      'Glad to be out',
    );
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(find.text('With Sam · For Priya · @ Home'), findsOneWidget);
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(saved, {
      'facts': {
        'location_id': 'home',
        'with_ids': ['sam'],
        'for_ids': ['priya'],
        'notes': {'sam': 'Glad to be out'},
      },
    });
  });

  testWidgets('the Events page loads everyone, every location and every '
      'trait as it opens, for an event to name them', (tester) async {
    final people = _CountingPeopleRepository();
    final memory = PlanMemory();
    await tester.pumpWidget(
      TraitsScope(
        repository: InMemoryTraitsRepository(traits: [_adventurous]),
        child: PeopleScope(
          repository: people,
          child: MaterialApp(
            builder: (context, child) =>
                PlanMemoryScope(memory: memory, child: child!),
            home: EventsScreen(
              repository: InMemoryEventsRepository(),
              serverLabel: 'test',
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(people.calls, ['people', 'locations']);
    expect([for (final p in memory.people!.people) p.id], ['sam']);
    expect([for (final l in memory.locations!) l.id], ['home']);
    expect([for (final t in memory.traits!) t.id], ['adventurous']);
  });

  testWidgets("an event's dialogs name its people and location at once, "
      "from what's loaded, while they're asked for again", (tester) async {
    final people = _CountingPeopleRepository()..gate = Completer<void>();
    final memory = PlanMemory()
      ..people = const PeopleList(
        people: [Person(id: 'sam', name: 'Sam')],
      )
      ..locations = const [Location(id: 'home', name: 'Home')];
    final event = Event(
      id: 'e1',
      summary: 'Dinner',
      start: DateTime(2026, 10, 1, 18),
      end: DateTime(2026, 10, 1, 20),
      properties: const {
        'facts': {
          'location_id': 'home',
          'with_ids': ['sam'],
        },
      },
    );
    await tester.pumpWidget(
      PeopleScope(
        repository: people,
        child: MaterialApp(
          builder: (context, child) =>
              PlanMemoryScope(memory: memory, child: child!),
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () => showEventSummaryDialog(
                context,
                event,
                save: (_) async => [event],
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    // Asked for, but not answered: named from what's loaded.
    expect(people.calls, ['people', 'locations']);
    expect(find.text('With Sam · @ Home'), findsOneWidget);
    await tester.tap(find.text('With Sam · @ Home'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(FilterChip, 'Sam'), findsWidgets);
    expect(find.text('Home'), findsWidgets);
    // Asked once, not again for the facts.
    expect(people.calls, ['people', 'locations']);
    people.gate!.complete();
    await tester.pumpAndSettle();
  });

  testWidgets('someone picked as there is taken off those it was for', (
    tester,
  ) async {
    Facts? edited;
    await tester.pumpWidget(
      PeopleScope(
        repository: InMemoryPeopleRepository(
          people: const [Person(id: 'sam', name: 'Sam')],
        ),
        child: MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () async => edited = await showFactsDialog(
                context,
                const Facts(forIds: ['sam']),
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilterChip, 'Sam').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();

    expect(edited?.withIds, ['sam']);
    expect(edited?.forIds, isEmpty);
  });

  testWidgets('a new location is added from what happened', (tester) async {
    final people = InMemoryPeopleRepository();
    Map<String, Object?>? saved;
    final event = Event(
      id: 'e1',
      summary: 'Dinner',
      start: DateTime(2026, 10, 1, 18),
      end: DateTime(2026, 10, 1, 20),
    );
    await tester.pumpWidget(
      PeopleScope(
        repository: people,
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
    await tester.tap(find.text('Add what happened'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Not said'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('New location…').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Name'), 'Home');
    await tester.pump();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect((await people.locations()).single.name, 'Home');
    expect(saved, {
      'facts': {'location_id': 'home'},
    });
  });
}

/// Records each tool call, and answers with [answer].
class _RecordingClient extends McpClient {
  _RecordingClient(this.answer) : super(endpoint: Uri.parse('http://test'));

  final Object? Function(String name, Map<String, Object?> arguments) answer;
  final calls = <(String, Map<String, Object?>)>[];

  @override
  Future<Object?> callTool(
    String name, [
    Map<String, Object?> arguments = const {},
  ]) async {
    calls.add((name, arguments));
    return answer(name, arguments);
  }
}

/// Says what it was asked for; while [gate] is set, answers once it's
/// done.
class _CountingPeopleRepository extends InMemoryPeopleRepository {
  _CountingPeopleRepository()
    : super(
        people: const [Person(id: 'sam', name: 'Sam')],
        locations: const [Location(id: 'home', name: 'Home')],
      );

  final calls = <String>[];
  Completer<void>? gate;

  @override
  Future<PeopleList> people() async {
    calls.add('people');
    await gate?.future;
    return super.people();
  }

  @override
  Future<List<Location>> locations() async {
    calls.add('locations');
    await gate?.future;
    return super.locations();
  }
}

/// [EventStore.dayKey] of [offset] days from today.
String _dayKey(int offset) {
  final now = DateTime.now();
  return EventStore.dayKey(DateTime(now.year, now.month, now.day + offset));
}

/// An event from 6 to 8 pm yesterday, with its facts and judgments.
Event _yesterday(
  String id,
  String summary, {
  List<String> actions = const [],
  List<String> withIds = const [],
  String? location,
  Map<String, String> notes = const {},
  Map<String, Object?> judgments = const {},
}) {
  final now = DateTime.now();
  return Event.fromJson({
    'id': id,
    'summary': summary,
    'start': localIsoTimestamp(DateTime(now.year, now.month, now.day - 1, 18)),
    'end': localIsoTimestamp(DateTime(now.year, now.month, now.day - 1, 20)),
    'action_ids': actions,
    'facts': Facts(
      withIds: withIds,
      locationId: location,
      notes: notes,
    ).toJson(),
    if (judgments.isNotEmpty) 'judgments': judgments,
  });
}

/// A memory that scores [people] (and Self) by [_adventurous] and
/// [_reliable] from [events], loaded.
Future<PlanMemory> _scoredMemory(
  List<Event> events, {
  List<Person> people = const [Person(id: 'sam', name: 'Sam')],
}) async {
  final memory =
      PlanMemory(
          eventStore: EventStore(repository: InMemoryEventsRepository(events)),
        )
        ..traits = [_adventurous, _reliable]
        ..people = PeopleList(people: people);
  await memory.eventStore!.warm();
  return memory;
}
