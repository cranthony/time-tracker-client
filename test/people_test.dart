import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:time_tracker_client/models/event.dart';
import 'package:time_tracker_client/models/note.dart';
import 'package:time_tracker_client/models/people_times.dart';
import 'package:time_tracker_client/models/person.dart';
import 'package:time_tracker_client/models/time_split.dart';
import 'package:time_tracker_client/models/trait.dart';
import 'package:time_tracker_client/screens/locations_pane.dart';
import 'package:time_tracker_client/screens/people_pane.dart';
import 'package:time_tracker_client/screens/person_screen.dart';
import 'package:time_tracker_client/screens/traits_pane.dart';
import 'package:time_tracker_client/screens/traits_section.dart';
import 'package:time_tracker_client/services/event_store.dart';
import 'package:time_tracker_client/services/events_repository.dart';
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
        'facts': {
          'thoughtful': {'what_matters': '- loves jazz'},
        },
        'traits': {
          'select': ['present'],
          'parts': {
            'present': [
              {'kind': 'follow_through'},
            ],
          },
        },
      });

      expect(
        personUpdate('sam', {
          'context': null,
          'name': 'Sam',
          'facts': {
            'thoughtful': {'what_matters': '- jazz'},
          },
        }, version: 3),
        {
          'person': {'id': 'sam', 'name': 'Sam', 'version': 3},
          'clear_fields': ['context'],
          'facts': {
            'thoughtful': {'what_matters': '- jazz'},
          },
        },
        reason: "Their summaries go beside them, as update_person takes them",
      );
      // Foundations of their own, set or cleared before people were on the
      // habit graph by their habits, aren't sent.
      expect(personUpdate('sam', {'foundations': null}, version: 3), {
        'person': {'id': 'sam', 'version': 3},
      });
      expect(personUpdate('sam', {'foundations': <String>[]}), {
        'person': {'id': 'sam'},
      });
      expect(sam.circleIds, ['dance']);
      // Their summaries are read, and set apart from them.
      expect(sam.summary('thoughtful', 'what_matters'), '- loves jazz');
      expect(sam.summary('thoughtful', 'other'), isNull);
      expect(sam.traits.select, ['present']);
      expect(sam.traits.applies('reliable'), isFalse);
      expect(sam.toJson(), {
        'id': 'sam',
        'name': 'Sam',
        'context': 'from salsa',
        'status': 'active',
        'circles': ['dance'],
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

    test("give each there all of an event's time, as goals take it, "
        'and find the last event with each', () {
      final times = PeopleTimes.compute(
        window: SummaryWindow(asOf: asOf),
        windowEvents: events,
        known: events,
      );

      // The dinner was two hours with Sam, and with Mom.
      expect(times.day('sam'), const Duration(hours: 2));
      expect(times.day('mom'), const Duration(hours: 2));
      expect(times.week('sam'), const Duration(hours: 3));
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
      );
      // Loaded this visit, as the traits under Self are shown from.
      await memory.loadTraits(InMemoryTraitsRepository(traits: [_caring]));
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

    testWidgets('lists everyone, Self first, with no button to more', (
      tester,
    ) async {
      await pump(tester);

      for (final name in ['Self', 'Mom', 'Sam', 'Jordan']) {
        expect(find.text(name), findsOneWidget);
      }
      expect(find.text('All people and circles'), findsNothing);
      // The traits have a pane of their own.
      expect(find.byType(TraitsSection), findsNothing);
    });

    testWidgets('a person says their time with you and when you last saw '
        'them, as the summary measures it', (tester) async {
      await pump(tester);

      expect(find.text('24h 2h · 7d 2h'), findsOneWidget);
      expect(find.textContaining('Last: Visit Mom · '), findsOneWidget);
    });

    testWidgets('as shares, and the next time, looking on', (tester) async {
      await pump(tester, forward: true, durations: false);

      expect(find.text('+24h 4% · +7d 1%'), findsOneWidget);
      expect(find.textContaining('Next: Call Mom · '), findsOneWidget);
    });

    testWidgets('shows Self even when no one else is there', (tester) async {
      await pump(tester, people: const [], circles: const []);

      expect(find.text('Self'), findsOneWidget);
      expect(find.byTooltip('Add a person or circle'), findsOneWidget);
      expect(
        find.text('Tap + to add the people you want to spend time with.'),
        findsOneWidget,
      );
    });

    testWidgets('searches everyone', (tester) async {
      await pump(tester);

      await tester.enterText(find.byType(TextField).first, 'salsa');
      await tester.pumpAndSettle();
      expect(find.text('Sam'), findsOneWidget);
      expect(find.text('Mom'), findsNothing);
    });

    testWidgets('sorts everyone, either way', (tester) async {
      await pump(tester);

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

      expect(find.byType(HealthDot), findsNothing);
    });

    testWidgets('shows only the people in a circle picked', (tester) async {
      await pump(tester);

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
      await tester.pump();
      // The rest on the full page, with what's typed in the sheet.
      await tester.tap(find.text('More'));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(TextField, 'Priya'), findsOneWidget);
      expect(
        tester
            .widget<FilterChip>(find.widgetWithText(FilterChip, 'Family'))
            .selected,
        isTrue,
      );
      // How the traits combine is above them, edited by its sigma.
      expect(
        tester.getTopLeft(find.text('How the traits combine')).dy,
        lessThan(tester.getTopLeft(find.text('Every active trait')).dy),
      );
      expect(
        find.descendant(
          of: find.byTooltip('Edit how the traits combine'),
          matching: find.byIcon(Icons.functions),
        ),
        findsOneWidget,
      );
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
      expect(
        {
          for (final MapEntry(:key, :value) in priya.traits.parts.entries)
            key: [
              for (final part in value) {...part}..remove('id'),
            ],
        },
        {
          'present': [
            {'kind': 'follow_through', 'look_back_days': 14},
          ],
        },
      );
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
      await tester.tap(find.text('Add'));
      await tester.pumpAndSettle();

      // The sheet stays open, saying so, to try again.
      expect(find.textContaining("Couldn't add it"), findsOneWidget);
      expect(find.text('Try again'), findsOneWidget);
    });

    testWidgets("Self can't be archived", (tester) async {
      await pump(tester);

      await tester.tap(find.byTooltip('More for Self'));
      await tester.pumpAndSettle();

      expect(find.text('Edit'), findsOneWidget);
      expect(find.text('Archive'), findsNothing);
    });

    testWidgets('adds a circle, and deletes one, keeping its people', (
      tester,
    ) async {
      final (repository, _) = await pump(tester);

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

  group('TraitsPane', () {
    Future<void> pump(WidgetTester tester, {bool selfJudged = false}) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final memory = PlanMemory(
        eventStore: EventStore(
          repository: InMemoryEventsRepository([
            _visit(self: selfJudged),
            _call(),
          ]),
        ),
      );
      final traits = InMemoryTraitsRepository(traits: [_caring]);
      await memory.loadTraits(traits);
      await memory.eventStore!.warm();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: _Fill(
              child: TraitsPane(
                repository: traits,
                people: InMemoryPeopleRepository(
                  people: _people,
                  circles: _circles,
                ),
                memory: memory,
                actions: const {'call': 'Call'},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('is Self, then the traits, and adds one', (tester) async {
      await pump(tester);

      expect(find.text('Self'), findsOneWidget);
      expect(
        find.ancestor(
          of: find.text('Caring'),
          matching: find.byType(TraitsSection),
        ),
        findsOneWidget,
      );
      // No one else here: they're in People.
      expect(find.text('Mom'), findsNothing);

      await tester.tap(find.widgetWithText(TextButton, 'Trait'));
      await tester.pumpAndSettle();
      expect(find.byType(EditPage), findsOneWidget);
    });

    testWidgets("Self's head has their health and its trend", (tester) async {
      await pump(tester, selfJudged: true);

      final head = find
          .ancestor(of: find.text('Self'), matching: find.byType(Row))
          .first;
      expect(
        find.descendant(of: head, matching: find.byType(HealthDot)),
        findsOneWidget,
      );
      expect(
        find.descendant(of: head, matching: find.byType(TrendSparkline)),
        findsOneWidget,
      );
    });

    testWidgets('opens your page', (tester) async {
      await pump(tester);

      await tester.tap(find.byTooltip('Your page'));
      await tester.pumpAndSettle();
      expect(find.byType(PersonScreen), findsOneWidget);
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
      await tester.tap(find.text('Add'));
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

    testWidgets('gives one a map location, and takes it away', (tester) async {
      final repository = await pump(tester);

      await tester.tap(find.text('The hall'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'Map location (optional)'),
        ' 5 Hall Rd ',
      );
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect((await repository.locations()).single.mapLocation, '5 Hall Rd');

      await tester.tap(find.text('The hall'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'Map location (optional)'),
        '',
      );
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      final hall = (await repository.locations()).single;
      expect(hall.mapLocation, isNull);
      expect(hall.hint, 'salsa on Thursdays');
    });

    testWidgets('groups them, and shows each under its group', (tester) async {
      final repository = await pump(tester);

      // A city, and a neighborhood in it.
      Future<void> addGroup(String name, {String? inside}) async {
        await tester.tap(find.byTooltip('New location group'));
        await tester.pumpAndSettle();
        await tester.enterText(find.widgetWithText(TextField, 'Name'), name);
        await tester.pump();
        if (inside != null) {
          await tester.tap(
            find.widgetWithText(InputDecorator, 'Inside (optional)'),
          );
          await tester.pumpAndSettle();
          await tester.tap(find.text(inside).last);
          await tester.pumpAndSettle();
        }
        await tester.tap(find.text('Save'));
        await tester.pumpAndSettle();
      }

      await addGroup('New York');
      await addGroup('Brooklyn', inside: 'New York');
      expect((await repository.locationGroups()).map((g) => g.path), [
        'New York',
        'New York › Brooklyn',
      ]);

      // The hall goes in the neighborhood, and shows under it.
      await tester.tap(find.text('The hall'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(InputDecorator, 'Group (optional)'));
      await tester.pumpAndSettle();
      // Picked in a sheet, every group open: Brooklyn, in New York.
      await tester.tap(find.text('Brooklyn').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect((await repository.locations()).single.groupId, isNotNull);
      double left(String text) => tester.getTopLeft(find.text(text)).dx;
      expect(left('New York'), lessThan(left('Brooklyn')));
      expect(left('Brooklyn'), lessThan(left('The hall')));

      // Searched for, it says where it is.
      await tester.enterText(find.byType(TextField).first, 'hall');
      await tester.pumpAndSettle();
      expect(
        find.text('New York › Brooklyn · salsa on Thursdays'),
        findsOneWidget,
      );
      await tester.enterText(find.byType(TextField).first, '');
      await tester.pumpAndSettle();

      // Deleting the neighborhood moves the hall up into the city.
      await tester.tap(find.text('Brooklyn'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete').last);
      await tester.pumpAndSettle();
      expect((await repository.locations()).single.path, 'New York › The hall');
      expect(find.text('Brooklyn'), findsNothing);
    });

    testWidgets("a group can't go inside itself, or one inside it", (
      tester,
    ) async {
      final repository = InMemoryPeopleRepository(
        locationGroups: const [
          LocationGroup(id: 'ny', name: 'New York'),
          LocationGroup(id: 'bk', name: 'Brooklyn', groupId: 'ny'),
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

      // New York can't go in Brooklyn, inside it -- so there's nowhere
      // to put it, but a new group.
      await tester.tap(find.text('New York'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.widgetWithText(InputDecorator, 'Inside (optional)'),
      );
      await tester.pumpAndSettle();
      expect(find.text('New York › Brooklyn'), findsNothing);
      expect(find.text('Add location group…'), findsOneWidget);
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      // Brooklyn can go in New York, but not in itself.
      await tester.tap(find.text('Brooklyn'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.widgetWithText(InputDecorator, 'Inside (optional)'),
      );
      await tester.pumpAndSettle();
      expect(find.text('New York › Brooklyn'), findsNothing);
      expect(find.text('New York'), findsWidgets);
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
