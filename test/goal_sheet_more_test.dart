import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:time_tracker_client/services/goals_repository.dart';
import 'package:time_tracker_client/services/plan_memory.dart';
import 'package:time_tracker_client/widgets/goal_flows.dart';

void main() {
  testWidgets('an inactive goal goes on to the full New goal page inactive, '
      'starting when it was to, and due that day', (tester) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final repository = InMemoryGoalsRepository();
    final memory = PlanMemory();
    await memory.loadGoals(repository);
    await tester.pumpWidget(
      PlanMemoryScope(
        memory: memory,
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => addGoalInSheet(
                  context,
                  repository: repository,
                  memory: memory,
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
    await tester.enterText(find.byType(TextField), 'Book the dentist');
    await tester.tap(find.text('Starts'));
    await tester.pump();
    await tester.tap(find.text('More'));
    await tester.pumpAndSettle();

    expect(find.text('New goal'), findsOneWidget);
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    final today = DateTime.now();
    final tomorrow = DateTime(today.year, today.month, today.day + 1);
    final day =
        '${tomorrow.year}-'
        '${tomorrow.month.toString().padLeft(2, '0')}-'
        '${tomorrow.day.toString().padLeft(2, '0')}';
    final goal = (await repository.goals()).single;
    expect(goal.title, 'Book the dentist');
    expect(goal.status, 'inactive');
    expect(goal.activateWhen, {
      'after': [
        {'at': day},
      ],
    });
    expect(goal.deadlineRule, {
      'after_start': {'days': 0},
    });
  });
}
