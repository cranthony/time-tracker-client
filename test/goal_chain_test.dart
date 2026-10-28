import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:time_tracker_client/models/goal.dart';
import 'package:time_tracker_client/screens/goal_screen.dart';
import 'package:time_tracker_client/services/goals_repository.dart';
import 'package:time_tracker_client/services/plan_memory.dart';

void main() {
  late InMemoryGoalsRepository repository;
  late PlanMemory memory;

  Future<void> pump(WidgetTester tester) async {
    repository = InMemoryGoalsRepository([
      Goal.fromJson({
        'id': 'draft',
        'title': 'Draft the plan',
        'status': 'active',
        'deadline': '2099-11-01',
        'history': [
          {'status': 'active', 'at': '2026-01-01T09:00:00'},
        ],
      }),
    ]);
    memory = PlanMemory();
    await memory.loadGoals(repository);
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: GoalScreen(
          goalId: 'draft',
          repository: repository,
          memory: memory,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  final menu = find.descendant(
    of: find.byType(AppBar),
    matching: find.byType(PopupMenuButton<String>),
  );

  testWidgets('the next goal waits for this one, starts when it closes, '
      'and says so', (tester) async {
    await pump(tester);
    await tester.tap(menu);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add next goal…'));
    await tester.pumpAndSettle();

    // Inactive, waiting for this one, due a week after it starts.
    expect(find.text('After “Draft the plan” closes'), findsOneWidget);
    expect(
      tester
          .widget<ChoiceChip>(
            find.widgetWithText(ChoiceChip, 'After it starts'),
          )
          .selected,
      isTrue,
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Title'),
      'Send the plan',
    );
    await tester.tap(find.text('Then wait until the next day'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    final next = (await repository.goals()).firstWhere(
      (g) => g.title == 'Send the plan',
    );
    expect(next.status, 'inactive');
    expect(next.activateWhen, {
      'after': [
        {'goal_closed': 'draft'},
      ],
      'delay': 'next_day',
    });
    expect(next.deadlineRule, {
      'after_start': {'days': 7},
    });
    // On this one's page, what starts after it.
    expect(find.text('Starts after it'), findsOneWidget);
    expect(find.widgetWithText(ActionChip, 'Send the plan'), findsOneWidget);

    // Its own page says what it waits for, and when it's expected.
    await tester.tap(find.widgetWithText(ActionChip, 'Send the plan'));
    await tester.pumpAndSettle();
    expect(find.text('After “Draft the plan” closes'), findsOneWidget);
    expect(find.text('Then the next day'), findsOneWidget);
    expect(find.textContaining('Expected to start'), findsOneWidget);
    expect(find.text('1w after it starts'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();

    // Without the next day, it starts as this one's done, and says so.
    await repository.updateGoal(next.id, {
      'activate_when': {
        'after': [
          {'goal_closed': 'draft'},
        ],
      },
    });
    await memory.loadGoals(repository, again: true);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(OutlinedButton, 'Mark done'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Mark done'));
    await tester.pumpAndSettle();
    expect(find.text('“Send the plan” is now active'), findsOneWidget);
    final started = (await repository.goals()).firstWhere(
      (g) => g.id == next.id,
    );
    expect((started.status, started.activateWhen), ('active', null));
    expect(started.deadline, isNotNull);
  });
}
