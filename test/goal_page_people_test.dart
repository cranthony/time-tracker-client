// A goal's page names who it's done with and for, each tapped to open
// their page, or a circle's.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:time_tracker_client/models/goal.dart';
import 'package:time_tracker_client/models/person.dart';
import 'package:time_tracker_client/screens/circle_screen.dart';
import 'package:time_tracker_client/screens/goal_screen.dart';
import 'package:time_tracker_client/screens/person_screen.dart';
import 'package:time_tracker_client/services/goals_repository.dart';
import 'package:time_tracker_client/services/people_repository.dart';
import 'package:time_tracker_client/services/plan_memory.dart';

const _sam = Person(id: 'sam', name: 'Sam', circleIds: ['fam']);
const _uly = Person(id: 'uly', name: 'Ulyssie', circleIds: ['fam']);
const _family = Circle(id: 'fam', name: 'Family', memberIds: ['sam', 'uly']);

final _goal = Goal.fromJson({
  'id': 'move',
  'title': 'Help Sam move',
  'status': 'active',
  'with_ids': [
    {
      'circle_id': 'fam',
      'except': ['uly'],
    },
  ],
  'for_ids': ['sam', 'gone'],
});

void main() {
  Future<void> pump(WidgetTester tester, {bool scoped = true}) async {
    final goals = InMemoryGoalsRepository([_goal]);
    final people = InMemoryPeopleRepository(
      people: const [_sam, _uly],
      circles: const [_family],
    );
    final memory = PlanMemory();
    await memory.loadGoals(goals);
    await memory.loadPeople(people);
    final page = GoalScreen(goalId: 'move', repository: goals, memory: memory);
    await tester.pumpWidget(
      MaterialApp(
        home: scoped ? PeopleScope(repository: people, child: page) : page,
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('names them, each in a chip', (tester) async {
    await pump(tester);
    expect(find.text('With'), findsOneWidget);
    expect(find.text('For'), findsOneWidget);
    expect(find.text('Family (except Ulyssie)'), findsOneWidget);
    expect(find.widgetWithText(ActionChip, 'Sam'), findsOneWidget);
    // Someone it doesn't know is just named.
    expect(find.widgetWithText(ActionChip, 'gone'), findsNothing);
    expect(find.widgetWithText(Chip, 'gone'), findsOneWidget);
  });

  testWidgets("a person's opens their page", (tester) async {
    await pump(tester);
    await tester.tap(find.widgetWithText(ActionChip, 'Sam'));
    // Past the page's way in: its history goes on loading.
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.byType(PersonScreen), findsOneWidget);
  });

  testWidgets("a circle's opens its page", (tester) async {
    await pump(tester);
    await tester.tap(
      find.widgetWithText(ActionChip, 'Family (except Ulyssie)'),
    );
    await tester.pumpAndSettle();
    expect(find.byType(CircleScreen), findsOneWidget);
  });

  testWidgets('with no people to open, they are only named', (tester) async {
    await pump(tester, scoped: false);
    expect(find.byType(ActionChip), findsNothing);
    expect(find.widgetWithText(Chip, 'Sam'), findsOneWidget);
  });
}
