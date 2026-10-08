import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:time_tracker_client/models/event.dart';
import 'package:time_tracker_client/models/habit.dart';
import 'package:time_tracker_client/models/note.dart';
import 'package:time_tracker_client/models/people_times.dart';
import 'package:time_tracker_client/models/person.dart';
import 'package:time_tracker_client/models/time_split.dart';
import 'package:time_tracker_client/models/trait.dart';
import 'package:time_tracker_client/screens/locations_pane.dart';
import 'package:time_tracker_client/screens/people_pane.dart';
import 'package:time_tracker_client/services/event_store.dart';
import 'package:time_tracker_client/services/events_repository.dart';
import 'package:time_tracker_client/services/focus_store.dart';
import 'package:time_tracker_client/services/habits_repository.dart';
import 'package:time_tracker_client/services/people_repository.dart';
import 'package:time_tracker_client/services/plan_memory.dart';
import 'package:time_tracker_client/services/traits_repository.dart';
import 'package:time_tracker_client/widgets/edit_page.dart';
import 'package:time_tracker_client/widgets/health.dart';
import 'package:time_tracker_client/widgets/plan_summaries.dart';

const _circles = [
  Circle(id: 'family', name: 'Family'),
  Circle(id: 'dance', name: 'Dance friends', note: 'Thursday salsa'),
];

const _people = [
  Person(id: 'mom', name: 'Mom', circleIds: ['family']),
  Person(
    id: 'sam',
    name: 'Sam',
    context: 'from salsa',
    circleIds: ['dance', 'family'],
  ),
  Person(id: 'jordan', name: 'Jordan', circleIds: ['dance']),
  Person(id: 'casey', name: 'Casey', status: 'archived'),
];

/// How caring an event was, judged out of 10.
const _caring = Trait(
  id: 'caring',
  name: 'Caring',
  parts: [
    {
      'kind': 'judgment',
      'rubric': 'Was it caring?',
      'ratings': {'0': 'Not at all', '10': 'Entirely'},
      'facts': ['general_notes'],
    },
  ],
);

/// Yesterday's visit to Mom, judged 9 of 10 for her: her health, 90. With
/// [self], judged so for Self too.
Event _visit({bool self = false}) {
  final now = DateTime.now();
  final judged = {
    'caring': {
      'judgment': {'rating': 9, 'scale': 10},
    },
  };
  return Event.fromJson({
    'id': 'visit',
    'summary': 'Visit Mom',
    'start': localIsoTimestamp(DateTime(now.year, now.month, now.day - 1, 12)),
    'end': localIsoTimestamp(DateTime(now.year, now.month, now.day - 1, 14)),
    'facts': {
      'with_ids': ['mom'],
    },
    'judgments': {'mom': judged, if (self) selfPersonId: judged},
  });
}

/// A call with Mom this morning.
Event _call() {
  final now = DateTime.now();
  return Event.fromJson({
    'id': 'call',
    'summary': 'Call Mom',
    'start': localIsoTimestamp(DateTime(now.year, now.month, now.day, 9)),
    'end': localIsoTimestamp(DateTime(now.year, now.month, now.day, 10)),
    'facts': {
      'with_ids': ['mom'],
    },
  });
}

const _traits = [
  Trait(
    id: 'present',
    name: 'Present',
    parts: [
      {'kind': 'follow_through'},
    ],
  ),
  Trait(
    id: 'reliable',
    name: 'Reliable',
    parts: [
      {'kind': 'count', 'target': 1, 'interval_days': 7},
    ],
  ),
];

void main() {
  group('relationship health', () {
    test('runs from gray, disconnected, to green, healthy', () {
      expect(relationshipColor(0), relationshipColor(15));
      expect(relationshipColor(100), relationshipColor(85));
      expect(relationshipColor(0), isNot(relationshipColor(100)));
      final mid = relationshipColor(50);
      expect(mid, isNot(relationshipColor(0)));
      expect(mid, isNot(relationshipColor(100)));
      expect(relationshipBand(10), 'disconnected');
      expect(relationshipBand(50), 'drifting');
      expect(relationshipBand(80), 'healthy');
    });
  });

  group('people', () {
    test('always have Self, first', () {
      expect(const PeopleList().withSelf.map((p) => p.id), [selfPersonId]);
      expect(
        const PeopleList(
          people: [
            Person(id: 'sam', name: 'Sam'),
            Person(id: selfPersonId, name: 'Me'),
          ],
        ).withSelf.map((p) => p.name),
        ['Me', 'Sam'],
      );
    });

    test('are read as the server lists them, and sent back as it takes '
        'them', () {
      final sam = Person.fromJson({
        'id': 'sam',
        'name': 'Sam',
        'context': 'from salsa',
        'status': 'active',
        'circles': ['dance'],
        'circle_names': ['Dance friends'],
        'what_matters': '- loves jazz',
        'traits': {
          'select': ['present'],
          'parts': {
            'present': [
              {'kind': 'follow_through'},
            ],
          },
        },
      });

      expect(sam.circleIds, ['dance']);
      expect(sam.traits.select, ['present']);
      expect(sam.traits.applies('reliable'), isFalse);
      expect(sam.toJson(), {
        'id': 'sam',
        'name': 'Sam',
        'context': 'from salsa',
        'status': 'active',
        'circles': ['dance'],
        'what_matters': '- loves jazz',
        'traits': {
          'select': ['present'],
          'parts': {
            'present': [
              {'kind': 'follow_through'},
            ],
          },
        },
      });
      // As for everyone, it's left out.
      expect(
        Person.fromJson({'id': 'p', 'name': 'P'})
            .toJson()
            .containsKey('traits'),
        isFalse,
      );
      expect(personName(sam, context: true), 'Sam (from salsa)');
    });
  });

  group('PeopleTimes', () {
    final asOf = DateTime(2026, 10, 8);
    Event event(String id, DateTime start, int hours, List<String> withIds) =>
        Event.fromJson({
          'id': id,
          'summary': id,
          'start': localIsoTimestamp(start),
          'end': localIsoTimestamp(start.add(Duration(hours: hours))),
          'facts': {'with_ids': withIds},
        });
    final events = [
      event('old', DateTime(2026, 10, 1, 12), 1, ['sam']),
      event('dinner', DateTime(2026, 10, 7, 18), 2, ['sam', 'mom']),
      event('coffee', DateTime(2026, 10, 9, 8), 1, ['sam']),
      event('call', DateTime(2026, 10, 12, 8), 1, ['sam']),
    ];

    test("split each event's time among those there, as By person does, "
        'and find the last event with each', () {
      final times = PeopleTimes.compute(
        window: SummaryWindow(asOf: asOf),
        windowEvents: events,
        known: events,
      );

      expect(times.day('sam'), const Duration(hours: 1));
      expect(times.week('sam'), const Duration(hours: 2));
      expect(times.day('jo'), Duration.zero);
      expect(times.nearest('sam')!.id, 'dinner');
      expect(times.nearest('mom')!.id, 'dinner');
      expect(times.nearest('jo'), isNull);
    });

    test('look on to the next, with the summary', () {
      final times = PeopleTimes.compute(
        window: SummaryWindow(asOf: asOf, forward: true),
        windowEvents: events,
        known: events,
      );

      // The coffee's a day on; the call, four.
      expect(times.day('sam'), Duration.zero);
      expect(times.week('sam'), const Duration(hours: 2));
      expect(times.nearest('sam')!.id, 'coffee');
      expect(times.nearest('mom'), isNull);
    });

    test("aren't measured until the window's events are in", () {
      final times = PeopleTimes.compute(
        window: SummaryWindow(asOf: asOf),
        windowEvents: null,
        known: events,
      );

      expect(times.measured, isFalse);
      expect(times.day('sam'), isNull);
      expect(times.nearest('sam')!.id, 'dinner');
    });

    test('sort people either way, those with nothing to sort by last, Self '
        'first', () {
      final times = PeopleTimes.compute(
        window: SummaryWindow(asOf: asOf),
        windowEvents: events,
        known: events,
      );
      const people = [
        defaultSelf,
        Person(id: 'jo', name: 'Jo'),
        Person(id: 'mom', name: 'Mom'),
        Person(id: 'sam', name: 'Sam'),
      ];
      const health = {'mom': 90, 'sam': 40};
      List<String> sorted(PeopleSort sort, {required bool ascending}) => [
        for (final p in sortPeople(
          people,
          sort,
          ascending: ascending,
          health: (id) => health[id],
          times: times,
        ))
          p.id,
      ];

      expect(sorted(PeopleSort.listed, ascending: true), [
        selfPersonId,
        'jo',
        'mom',
        'sam',
      ]);
      expect(sorted(PeopleSort.health, ascending: true), [
        selfPersonId,
        'sam',
        'mom',
        'jo',
      ]);
      expect(sorted(PeopleSort.health, ascending: false), [
        selfPersonId,
        'mom',
        'sam',
        'jo',
      ]);
      expect(sorted(PeopleSort.week, ascending: false), [
        selfPersonId,
        'sam',
        'mom',
        'jo',
      ]);
      // Sam and Mom were last seen at the same dinner: as listed.
      expect(sorted(PeopleSort.seen, ascending: false), [
        selfPersonId,
        'mom',
        'sam',
        'jo',
      ]);
    });
  });

  group('PeoplePane', () {
    /// Midnight today: the summary's window ends, or starts, there.
    DateTime today() {
      final now = DateTime.now();
      return DateTime(now.year, now.month, now.day);
    }

    Future<(InMemoryPeopleRepository, PlanMemory)> pump(
      WidgetTester tester, {
      List<Person> people = _people,
      List<Circle> circles = _circles,
      List<String> prioritized = const [],
      List<Habit> habits = const [],
      List<String> focusHabits = const [],
      bool forward = false,
      bool durations = true,
      bool selfJudged = false,
    }) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final repository = InMemoryPeopleRepository(
        people: people,
        circles: circles,
      );
      final events = [_visit(self: selfJudged), _call()];
      // Scored by how caring their events were.
      final memory = PlanMemory(
        eventStore: EventStore(repository: InMemoryEventsRepository(events)),
        focus: FocusStore(
          persist: false,
          people: prioritized,
          habits: focusHabits,
        ),
      )..traits = const [_caring];
      await memory.eventStore!.warm();
      final window = SummaryWindow(asOf: today(), forward: forward);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: _Fill(
              child: PeoplePane(
                repository: repository,
                memory: memory,
                traits: InMemoryTraitsRepository(traits: _traits),
                habits: InMemoryHabitsRepository(habits),
                actions: const {'call': 'Call'},
                summary: SummaryView(
                  window: window,
                  lastCompaction: null,
                  dayOffset: 0,
                  collapsed: true,
                  durations: durations,
                  onDays: (_) {},
                  onForward: (_) {},
                  onCollapsed: (_) {},
                  onDurations: (_) {},
                  events: events,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return (repository, memory);
    }

    /// Opens everyone, from the pane.
    Future<void> openAll(WidgetTester tester) async {
      await tester.tap(find.text('All people and circles'));
      await tester.pumpAndSettle();
    }

    testWidgets('is Self, then the people prioritized, each section open '
        'until folded away', (tester) async {
      await pump(tester, prioritized: ['mom']);

      expect(find.text('Self'), findsOneWidget);
      expect(find.text('People'), findsOneWidget);
      expect(find.text('All habits and scores'), findsOneWidget);
      expect(find.text('Mom'), findsOneWidget);
      // Only those prioritized.
      expect(find.text('Sam'), findsNothing);

      await tester.tap(find.text('People'));
      await tester.pumpAndSettle();
      expect(find.text('Mom'), findsNothing);
      expect(find.text('All people and circles'), findsNothing);

      await tester.tap(find.text('Self'));
      await tester.pumpAndSettle();
      expect(find.text('All habits and scores'), findsNothing);

      await tester.tap(find.text('People'));
      await tester.pumpAndSettle();
      expect(find.text('Mom'), findsOneWidget);
    });

    testWidgets("Self's head has their health and its trend", (tester) async {
      await pump(tester, selfJudged: true);

      final head = find.ancestor(
        of: find.text('Self'),
        matching: find.byType(InkWell),
      );
      expect(
        find.descendant(of: head, matching: find.byType(HealthDot)),
        findsOneWidget,
      );
      expect(
        find.descendant(of: head, matching: find.byType(TrendSparkline)),
        findsOneWidget,
      );
    });

    testWidgets('a person says their time with you and when you last saw '
        'them, as the summary measures it', (tester) async {
      await pump(tester, prioritized: ['mom']);

      expect(find.text('24h 2h · 7d 2h'), findsOneWidget);
      expect(find.textContaining('Last: Visit Mom · '), findsOneWidget);
    });

    testWidgets('as shares, and the next time, looking on', (tester) async {
      await pump(tester, prioritized: ['mom'], forward: true, durations: false);

      expect(find.text('+24h 4% · +7d 1%'), findsOneWidget);
      expect(find.textContaining('Next: Call Mom · '), findsOneWidget);
    });

    testWidgets('shows the habits focused on, under Self', (tester) async {
      const guitar = Habit(id: 'h1', name: 'Practice', actionId: 'guitar');
      await pump(
        tester,
        habits: const [
          guitar,
          Habit(id: 'h2', name: 'Walk', actionId: 'w'),
        ],
        focusHabits: ['h1'],
      );

      expect(find.text('Practice'), findsOneWidget);
      expect(find.text('Walk'), findsNothing);
    });

    testWidgets('says how to prioritize people, with none', (tester) async {
      await pump(tester);

      expect(find.textContaining('Prioritize up to 3 people'), findsOneWidget);
    });

    testWidgets('shows Self even when no one else is there', (tester) async {
      await pump(tester, people: const [], circles: const []);

      expect(find.text('Self'), findsOneWidget);
      expect(
        find.text('Tap + to add the people you want to spend time with.'),
        findsOneWidget,
      );
    });

    testWidgets('has no search, with so few: everyone has theirs', (
      tester,
    ) async {
      await pump(tester);

      expect(find.byType(TextField), findsNothing);
      // Adding stays.
      expect(find.byTooltip('Add a person or circle'), findsOneWidget);

      await openAll(tester);
      await tester.enterText(find.byType(TextField).first, 'salsa');
      await tester.pumpAndSettle();
      expect(find.text('Sam'), findsOneWidget);
      expect(find.text('Mom'), findsNothing);
    });

    testWidgets('prioritizes someone by the star on their page, or as '
        "they're edited, on a page of its own", (tester) async {
      final (_, memory) = await pump(tester, prioritized: ['sam']);
      await openAll(tester);

      await tester.tap(find.text('Mom'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Prioritize Mom'));
      await tester.pumpAndSettle();
      expect(memory.focus.people, ['sam', 'mom']);

      await tester.tap(find.byTooltip('Edit Mom'));
      await tester.pumpAndSettle();
      expect(find.byType(EditPage), findsOneWidget);
      expect(find.byType(AlertDialog), findsNothing);
      await tester.tap(find.byTooltip("Don't prioritize Mom"));
      await tester.pumpAndSettle();
      expect(memory.focus.people, ['sam']);
      expect(find.byTooltip('Prioritize Mom'), findsOneWidget);

      // Called off: nothing saved, but the star's kept.
      await tester.tap(find.byType(CloseButton));
      await tester.pumpAndSettle();
      expect(find.byType(EditPage), findsNothing);
      expect(find.byTooltip('Prioritize Mom'), findsOneWidget);
    });

    testWidgets("Self isn't prioritized", (tester) async {
      await pump(tester);
      await tester.tap(find.text('All habits and scores'));
      await tester.pumpAndSettle();

      expect(find.byTooltip('Prioritize Self'), findsNothing);
    });

    testWidgets('prioritizes up to three people from their menu', (
      tester,
    ) async {
      final (_, memory) = await pump(tester, prioritized: ['sam', 'jordan']);
      await openAll(tester);

      await tester.tap(find.byTooltip('More for Mom'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Prioritize'));
      await tester.pumpAndSettle();
      expect(memory.focus.people, ['sam', 'jordan', 'mom']);

      await tester.tap(find.byTooltip('Show archived people'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('More for Casey'));
      await tester.pumpAndSettle();
      expect(find.text('Prioritize (3 already)'), findsOneWidget);
      await tester.tap(find.text('Prioritize (3 already)'));
      await tester.pumpAndSettle();
      expect(memory.focus.people, ['sam', 'jordan', 'mom']);

      // Off the menu, and back to the pane.
      await tester.tapAt(const Offset(4, 300));
      await tester.pumpAndSettle();
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('Mom'), findsOneWidget);
    });

    testWidgets('sorts everyone, either way', (tester) async {
      await pump(tester);
      await openAll(tester);

      List<String> shown() =>
          [
            for (final name in ['Self', 'Mom', 'Sam', 'Jordan'])
              if (find.text(name).evaluate().isNotEmpty) name,
          ]..sort(
            (a, b) => tester
                .getTopLeft(find.text(a))
                .dy
                .compareTo(tester.getTopLeft(find.text(b)).dy),
          );

      expect(shown(), ['Self', 'Mom', 'Sam', 'Jordan']);
      await tester.tap(find.byTooltip('Sort people'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Time in 7d'));
      await tester.pumpAndSettle();
      // Mom's two hours, then no one's.
      expect(shown().take(2), ['Self', 'Mom']);
      expect(find.text('By time in 7d, descending'), findsOneWidget);

      await tester.tap(find.byTooltip('Sort people'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Time in 7d'));
      await tester.pumpAndSettle();
      expect(find.text('By time in 7d, ascending'), findsOneWidget);
      expect(shown().last, 'Mom');
    });

    testWidgets("lists everyone with their context, circles and health, "
        'archived only when asked', (tester) async {
      await pump(tester);
      await openAll(tester);

      expect(find.text('Self'), findsOneWidget);
      expect(find.text('from salsa · Family, Dance friends'), findsOneWidget);
      // Mom's, worked out from her events; no one else has any judged.
      expect(find.text('90'), findsOneWidget);
      expect(find.byType(HealthDot), findsOneWidget);
      // Her circle's too.
      expect(
        find.byTooltip('Family: health 90, ${relationshipBand(90)}'),
        findsOneWidget,
      );
      expect(find.text('Casey'), findsNothing);

      await tester.tap(find.byTooltip('Show archived people'));
      await tester.pumpAndSettle();

      expect(find.text('Casey'), findsOneWidget);
    });

    testWidgets('shows no health for those not rated', (tester) async {
      await pump(
        tester,
        people: const [Person(id: 'sam', name: 'Sam')],
        circles: const [],
      );
      await openAll(tester);

      expect(find.byType(HealthDot), findsNothing);
    });

    testWidgets('shows only the people in a circle picked', (tester) async {
      await pump(tester);
      await openAll(tester);

      await tester.tap(find.widgetWithText(FilterChip, 'Dance friends'));
      await tester.pumpAndSettle();

      expect(find.text('Sam'), findsOneWidget);
      expect(find.text('Jordan'), findsOneWidget);
      expect(find.text('Mom'), findsNothing);
      expect(find.text('Self'), findsNothing);
      expect(find.text('Dance friends: 2 people'), findsOneWidget);
    });

    testWidgets('adds a person to circles, with the traits that apply and '
        'their own parts for one', (tester) async {
      final (repository, _) = await pump(tester);

      await tester.tap(find.byTooltip('Add a person or circle'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('New person'));
      await tester.pumpAndSettle();
      await tester.enterText(find.widgetWithText(TextField, 'Name'), 'Priya');
      await tester.enterText(
        find.widgetWithText(TextField, 'Context (optional)'),
        'college',
      );
      await tester.tap(find.widgetWithText(FilterChip, 'Family').last);
      // Only Present, with a part of her own.
      await tester.tap(find.text('Every active trait'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.widgetWithText(ListTile, 'Reliable'),
          matching: find.byType(Checkbox),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Their own Present parts'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'Over, in days (optional)'),
        '14',
      );
      await tester.pump();
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      final priya = (await repository.people()).people.last;
      expect(priya.id, 'priya');
      expect(priya.context, 'college');
      expect(priya.circleIds, ['family']);
      expect(priya.traits.select, ['present']);
      expect(priya.traits.parts, {
        'present': [
          {'kind': 'follow_through', 'look_back_days': 14},
        ],
      });
      await openAll(tester);
      expect(find.text('Priya'), findsOneWidget);
    });

    testWidgets("two people of a name need contexts to tell them apart", (
      tester,
    ) async {
      await pump(tester);

      await tester.tap(find.byTooltip('Add a person or circle'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('New person'));
      await tester.pumpAndSettle();
      await tester.enterText(find.widgetWithText(TextField, 'Name'), 'Mom');
      await tester.pump();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(find.text("Couldn't save"), findsOneWidget);
    });

    testWidgets("Self can't be archived, or prioritized", (tester) async {
      await pump(tester);
      await openAll(tester);

      await tester.tap(find.byTooltip('More for Self'));
      await tester.pumpAndSettle();

      expect(find.text('Edit'), findsOneWidget);
      expect(find.text('Archive'), findsNothing);
      expect(find.text('Prioritize'), findsNothing);
    });

    testWidgets('adds a circle, and deletes one, keeping its people', (
      tester,
    ) async {
      final (repository, _) = await pump(tester);
      await openAll(tester);

      await tester.tap(find.byTooltip('Add a person or circle'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('New circle'));
      await tester.pumpAndSettle();
      await tester.enterText(find.widgetWithText(TextField, 'Name'), 'Work');
      await tester.pump();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(FilterChip, 'Work'), findsOneWidget);

      await tester.tap(find.widgetWithText(FilterChip, 'Dance friends'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Edit Dance friends'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete').last);
      await tester.pumpAndSettle();

      final people = await repository.people();
      expect(people.circles.map((c) => c.id), ['family', 'work']);
      expect(people.people.firstWhere((p) => p.id == 'sam').circleIds, [
        'family',
      ]);
      expect(find.text('Jordan'), findsOneWidget);
    });
  });

  group('LocationsPane', () {
    Future<InMemoryPeopleRepository> pump(WidgetTester tester) async {
      final repository = InMemoryPeopleRepository(
        locations: const [
          Location(id: 'hall', name: 'The hall', hint: 'salsa on Thursdays'),
        ],
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: _Fill(
              child: LocationsPane(
                repository: repository,
                memory: PlanMemory(),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return repository;
    }

    testWidgets('lists the locations with their hints', (tester) async {
      await pump(tester);

      expect(find.text('The hall'), findsOneWidget);
      expect(find.text('salsa on Thursdays'), findsOneWidget);
    });

    testWidgets('adds one, edits one, and deletes one', (tester) async {
      final repository = await pump(tester);

      await tester.tap(find.byTooltip('New location'));
      await tester.pumpAndSettle();
      await tester.enterText(find.widgetWithText(TextField, 'Name'), 'Home');
      await tester.enterText(
        find.widgetWithText(TextField, 'Hint (optional)'),
        "'my place'",
      );
      await tester.pump();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(find.text('Home'), findsOneWidget);

      await tester.tap(find.text('The hall'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'Hint (optional)'),
        '',
      );
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(find.text('salsa on Thursdays'), findsNothing);

      await tester.tap(find.text('Home'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete').last);
      await tester.pumpAndSettle();

      final locations = await repository.locations();
      expect(locations.map((l) => (l.name, l.hint)), [('The hall', null)]);
    });
  });
}

/// [child], as tall as the screen: a pane fills what it's given.
class _Fill extends StatelessWidget {
  const _Fill({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => SizedBox.expand(child: child);
}
