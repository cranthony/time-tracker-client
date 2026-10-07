import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:time_tracker_client/models/event.dart';
import 'package:time_tracker_client/models/note.dart';
import 'package:time_tracker_client/models/person.dart';
import 'package:time_tracker_client/models/trait.dart';
import 'package:time_tracker_client/screens/locations_pane.dart';
import 'package:time_tracker_client/screens/people_pane.dart';
import 'package:time_tracker_client/services/event_store.dart';
import 'package:time_tracker_client/services/events_repository.dart';
import 'package:time_tracker_client/services/people_repository.dart';
import 'package:time_tracker_client/services/plan_memory.dart';
import 'package:time_tracker_client/services/traits_repository.dart';
import 'package:time_tracker_client/widgets/health.dart';

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

/// Yesterday's visit to Mom, judged 9 of 10 for her: her health, 90.
Event _visit() {
  final now = DateTime.now();
  return Event.fromJson({
    'id': 'visit',
    'summary': 'Visit Mom',
    'start': localIsoTimestamp(DateTime(now.year, now.month, now.day - 1, 12)),
    'end': localIsoTimestamp(DateTime(now.year, now.month, now.day - 1, 14)),
    'facts': {
      'with_ids': ['mom'],
    },
    'judgments': {
      'mom': {
        'caring': {
          'judgment': {'rating': 9, 'scale': 10},
        },
      },
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

  group('PeoplePane', () {
    Future<InMemoryPeopleRepository> pump(
      WidgetTester tester, {
      List<Person> people = _people,
      List<Circle> circles = _circles,
    }) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final repository = InMemoryPeopleRepository(
        people: people,
        circles: circles,
      );
      // Scored by how caring their events were.
      final memory = PlanMemory(
        eventStore: EventStore(
          repository: InMemoryEventsRepository([_visit()]),
        ),
      )..traits = const [_caring];
      await memory.eventStore!.warm();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: _Fill(
              child: PeoplePane(
                repository: repository,
                memory: memory,
                traits: InMemoryTraitsRepository(traits: _traits),
                actions: const {'call': 'Call'},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return repository;
    }

    testWidgets('shows Self even when no one else is there', (tester) async {
      await pump(tester, people: const [], circles: const []);

      expect(find.text('Self'), findsOneWidget);
      expect(find.text('You'), findsOneWidget);
      expect(
        find.text('Tap + to add the people you want to spend time with.'),
        findsOneWidget,
      );
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
      final repository = await pump(tester);

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
      final repository = await pump(tester);

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
