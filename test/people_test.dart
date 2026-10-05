import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:time_tracker_client/models/person.dart';
import 'package:time_tracker_client/models/trait.dart';
import 'package:time_tracker_client/screens/people_section.dart';
import 'package:time_tracker_client/services/people_repository.dart';
import 'package:time_tracker_client/services/traits_repository.dart';
import 'package:time_tracker_client/widgets/health.dart';

const _circles = [
  Circle(id: 'family', name: 'Family', color: '#f6bf26', health: 80),
  Circle(id: 'dance', name: 'Dance friends'),
];

const _people = [
  Person(id: 'mom', name: 'Mom', circleIds: ['family'], health: 90),
  Person(id: 'sam', name: 'Sam', circleIds: ['dance', 'family'], health: 40),
  Person(id: 'jordan', name: 'Jordan', circleIds: ['dance'], health: 5),
  Person(id: 'casey', name: 'Casey', status: 'archived'),
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

  group('PeopleList', () {
    test('always has Self, first', () {
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

    test('reads people back as the server sends them', () {
      final list = PeopleList.fromJson({
        'people': [
          {
            'id': 'sam',
            'name': 'Sam',
            'circle_ids': ['dance'],
            'trait_weights': {'adventurous': 2},
            'health': 72.4,
            'health_trend': '70,-,72',
          },
        ],
        'circles': [
          {'id': 'dance', 'name': 'Dance friends', 'health': 60},
        ],
      });

      final sam = list.people.single;
      expect(sam.circleIds, ['dance']);
      expect(sam.traitWeights, {'adventurous': 2});
      expect(sam.health, 72);
      expect(sam.healthTrend, [70, null, 72]);
      expect(list.circles.single.health, 60);
      expect(Person.fromJson(sam.toJson()).toJson(), sam.toJson());
    });
  });

  group('PeopleSection', () {
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
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: PeopleSection(
                repository: repository,
                traits: InMemoryTraitsRepository(
                  traits: const [
                    Trait(
                      id: 'present',
                      name: 'Present',
                      parts: [
                        {'kind': 'follow_through'},
                      ],
                    ),
                  ],
                ),
                expanded: true,
                onExpanded: (_) {},
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

    testWidgets("lists everyone with their circles and health, archived "
        'only when asked', (tester) async {
      await pump(tester);

      expect(find.text('Self'), findsOneWidget);
      expect(find.text('Dance friends, Family'), findsNothing);
      expect(find.text('Family, Dance friends'), findsOneWidget);
      expect(find.text('90'), findsOneWidget);
      expect(find.text('Casey'), findsNothing);

      await tester.tap(find.byTooltip('Show archived people'));
      await tester.pumpAndSettle();

      expect(find.text('Casey'), findsOneWidget);
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

    testWidgets('adds a person to circles, with trait weights', (tester) async {
      final repository = await pump(tester);

      await tester.tap(find.byTooltip('Add a person or circle'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('New person'));
      await tester.pumpAndSettle();
      await tester.enterText(find.widgetWithText(TextField, 'Name'), 'Priya');
      await tester.tap(find.widgetWithText(FilterChip, 'Family').last);
      await tester.enterText(
        find.widgetWithText(TextField, 'Present weight'),
        '2',
      );
      await tester.pump();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      final priya = (await repository.people()).people.last;
      expect(priya.id, 'priya');
      expect(priya.circleIds, ['family']);
      expect(priya.traitWeights, {'present': 2});
      expect(find.text('Priya'), findsOneWidget);
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
}
