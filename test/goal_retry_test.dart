import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:time_tracker_client/models/goal.dart';
import 'package:time_tracker_client/screens/goal_screen.dart';
import 'package:time_tracker_client/services/goals_repository.dart';
import 'package:time_tracker_client/services/plan_memory.dart';
import 'package:time_tracker_client/widgets/goal_tile.dart';

void main() {
  late InMemoryGoalsRepository repository;
  late PlanMemory memory;

  Future<void> pump(
    WidgetTester tester, {
    String status = 'active',
    String deadline = '2026-01-05',
    List<Map<String, Object?>>? history,
  }) async {
    repository = InMemoryGoalsRepository([
      Goal.fromJson({
        'id': 'recipe',
        'title': 'Recipe sent to Kopal',
        'status': status,
        'deadline': deadline,
        'history':
            history ??
            [
              {'status': status, 'at': '2026-01-01T09:00:00'},
            ],
      }),
    ]);
    memory = PlanMemory();
    await memory.loadGoals(repository);
    await tester.pumpWidget(
      MaterialApp(
        home: GoalScreen(
          goalId: 'recipe',
          repository: repository,
          memory: memory,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Goal goal() => memory.goals!.single;

  /// The page's menu, in its bar (the sub-goals' status filter is one too).
  final menu = find.descendant(
    of: find.byType(AppBar),
    matching: find.byType(PopupMenuButton<String>),
  );

  testWidgets('an overdue goal is missed and tried again by a day picked, '
      'keeping its status', (tester) async {
    await pump(tester);
    // Overdue: the button beside its status, as well as the menu.
    await tester.tap(find.widgetWithText(OutlinedButton, 'Missed, try again…'));
    await tester.pumpAndSettle();
    expect(find.text('Try again by'), findsOneWidget);
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    final tomorrow = DateTime.now().add(const Duration(days: 1));
    final g = goal();
    expect(g.status, 'active');
    expect(g.deadline, deadlineOf(tomorrow));
    expect(g.history.map((h) => h.status), ['active', 'missed', 'active']);
    expect(g.history[1].deadline, '2026-01-05');
    expect(g.history[2].deadline, deadlineOf(tomorrow));
    expect((await repository.goals()).single.history.length, 3);

    // The page says so, and so does a tile.
    expect(find.text('Missed'), findsWidgets);
    // Dates as formatMediumDate has them: "Mon, Jan 5".
    expect(find.textContaining('once, last due Mon, Jan 5'), findsOneWidget);
    expect(find.textContaining('· due Mon, Jan 5'), findsOneWidget);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: GoalTile(goal: g)),
      ),
    );
    expect(find.textContaining('Missed once'), findsOneWidget);
  });

  testWidgets('an inactive goal tried again stays inactive, from the menu', (
    tester,
  ) async {
    await pump(tester, status: 'inactive', deadline: '2099-01-05');
    // Not overdue: only in the menu.
    expect(
      find.widgetWithText(OutlinedButton, 'Missed, try again…'),
      findsNothing,
    );
    await tester.tap(menu);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Missed, try again…'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    final g = goal();
    expect(g.status, 'inactive');
    expect(g.history.map((h) => h.status), ['inactive', 'missed', 'inactive']);
    expect(g.history[1].deadline, '2099-01-05');
  });

  testWidgets('a goal due at a time is tried again at that time', (
    tester,
  ) async {
    await pump(tester, deadline: '2026-01-05T17:30');
    await tester.tap(find.widgetWithText(OutlinedButton, 'Missed, try again…'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    final tomorrow = DateTime.now().add(const Duration(days: 1));
    expect(goal().deadline, '${deadlineOf(tomorrow)}T17:30');
  });

  testWidgets('a closed goal has no retry', (tester) async {
    await pump(tester, status: 'done');
    expect(find.text('Missed, try again…'), findsNothing);
    await tester.tap(menu);
    await tester.pumpAndSettle();
    expect(find.text('Missed, try again…'), findsNothing);
  });
}
