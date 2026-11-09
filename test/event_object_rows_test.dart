import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:time_tracker_client/models/event.dart';
import 'package:time_tracker_client/models/goal.dart';
import 'package:time_tracker_client/models/person.dart';
import 'package:time_tracker_client/services/goals_repository.dart';
import 'package:time_tracker_client/services/people_repository.dart';
import 'package:time_tracker_client/services/plan_memory.dart';
import 'package:time_tracker_client/widgets/event_summary_dialog.dart';

Goal _goal(String id, String title) => Goal.fromJson({
  'id': id,
  'title': title,
  'status': 'active',
  'deadline': '2026-12-01',
  'history': [
    {'status': 'active', 'at': '2026-09-01T09:00:00'},
  ],
});

void main() {
  /// Opens the dialog of an event with people, a circle, locations and
  /// goals; gives what it saved.
  Future<Map<String, Object?>? Function()> open(WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final goals = InMemoryGoalsRepository([
      _goal('ship', 'Ship the app'),
      _goal('read', 'Read more'),
    ]);
    final memory = PlanMemory()..goals = await goals.goals();
    final event = Event(
      id: 'e1',
      summary: 'Dinner',
      start: DateTime(2026, 10, 1, 18),
      end: DateTime(2026, 10, 1, 19),
      properties: {
        'location': 'Room 4',
        'goals': [
          {'goal_id': 'ship', 'minutes': 30},
          {'goal_id': 'read'},
        ],
        'facts': {
          'with_ids': [
            'sam',
            {'circle_id': 'fam', 'minutes': 10},
          ],
          'for_ids': [
            {'person_id': 'priya', 'percent': 25},
          ],
          'location_ids': ['home', 'park'],
        },
      },
    );
    Map<String, Object?>? saved;
    await tester.pumpWidget(
      PlanMemoryScope(
        memory: memory,
        child: GoalsScope(
          repository: goals,
          child: PeopleScope(
            repository: InMemoryPeopleRepository(
              people: const [
                Person(id: 'sam', name: 'Sam'),
                Person(id: 'priya', name: 'Priya'),
              ],
              circles: const [
                Circle(
                  id: 'fam',
                  name: 'Family',
                  memberIds: [selfPersonId, 'sam'],
                ),
              ],
              locations: const [
                Location(id: 'home', name: 'Home', mapLocation: '1 Main St'),
                Location(id: 'park', name: 'The park'),
              ],
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
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    return () => saved;
  }

  testWidgets('who, where and goals each list one to a line, with a chip '
      'and an icon that opens it', (tester) async {
    await open(tester);
    expect(find.text('Sam'), findsOneWidget);
    expect(find.text('Family'), findsOneWidget);
    expect(find.text('for Priya'), findsOneWidget);
    expect(find.text('Home'), findsOneWidget);
    expect(find.text('The park'), findsOneWidget);
    expect(find.text('Ship the app'), findsOneWidget);
    expect(find.text('Read more'), findsOneWidget);

    // Sam takes what the circle's 10 minutes leave; Priya, alone among
    // those it's for, has her own.
    expect(find.text('10m'), findsOneWidget);
    expect(find.text('25%'), findsOneWidget);
    expect(find.text('30m'), findsOneWidget);
    expect(find.text('The rest'), findsNWidgets(2));
    expect(find.text('Split the rest'), findsNWidgets(2));

    expect(find.byTooltip('Open person'), findsNWidgets(2));
    expect(find.byTooltip('Open circle'), findsOneWidget);
    expect(find.byTooltip('Open location'), findsNWidgets(2));
    expect(find.byTooltip('Open goal'), findsNWidgets(2));
  });

  testWidgets('a location opens in Maps from the end of its line, and icons '
      'line up within a row, not across rows', (tester) async {
    await open(tester);
    // Home's, and the one typed for the event, on its own line.
    expect(find.text('Room 4'), findsOneWidget);
    expect(find.byTooltip('Open in Maps'), findsNWidgets(2));

    final right = [
      for (final e in find.byTooltip('Open location').evaluate())
        tester.getTopRight(find.byWidget(e.widget)).dx,
    ];
    expect(right[0], right[1]);
    expect(
      tester.getTopRight(find.byTooltip('Open in Maps').first).dx,
      greaterThan(right[0]),
    );
    // A row with no map button takes no room for one.
    expect(
      tester.getTopRight(find.byTooltip('Open goal').first).dx,
      greaterThan(right[0]),
    );
  });

  testWidgets("a person's chip sets their share, and saves it", (tester) async {
    final saved = await open(tester);
    await tester.tap(find.text('The rest').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Percent'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Percent'), '35');
    await tester.pump();
    await tester.tap(find.text('Set'));
    await tester.pumpAndSettle();
    expect(find.text('35%'), findsOneWidget);

    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect((saved()!['facts'] as Map)['with_ids'], [
      {'person_id': 'sam', 'percent': 35},
      {'circle_id': 'fam', 'minutes': 10},
    ]);
  });

  testWidgets("a location's and a goal's chips set theirs", (tester) async {
    final saved = await open(tester);
    await tester.tap(find.text('Split the rest').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Percent'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Percent'), '40');
    await tester.pump();
    await tester.tap(find.text('Set'));
    await tester.pumpAndSettle();
    expect(find.text('40%'), findsOneWidget);

    await tester.tap(find.text('30m'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('The rest').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Set'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    final changes = saved()!;
    expect((changes['facts'] as Map)['location_ids'], [
      {'location_id': 'home', 'percent': 40},
      'park',
    ]);
    expect(changes['goals'], [
      {'goal_id': 'ship'},
      {'goal_id': 'read'},
    ]);
  });

  testWidgets('tapping a line elsewhere opens the picker, not its page', (
    tester,
  ) async {
    await open(tester);
    await tester.tap(find.text('Sam'));
    await tester.pumpAndSettle();
    expect(find.text('Who'), findsOneWidget);
    expect(find.byTooltip('Clear search'), findsWidgets);
  });
}
