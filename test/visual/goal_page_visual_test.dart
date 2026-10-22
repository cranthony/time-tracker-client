// A sub-goal's page and its edit page, side by side in build/screenshots/,
// to see that the two lay its fields out alike.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:time_tracker_client/models/goal.dart';
import 'package:time_tracker_client/screens/goal_screen.dart';
import 'package:time_tracker_client/services/goals_repository.dart';
import 'package:time_tracker_client/services/plan_memory.dart';

void main() {
  Goal goal(Map<String, Object?> json) => Goal.fromJson({
    'status': 'active',
    'history': [
      {'status': 'active', 'at': '2026-10-01T09:00:00'},
    ],
    ...json,
  });

  Future<void> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(412, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final repository = InMemoryGoalsRepository([
      goal({
        'id': 'ship',
        'title': 'Ship the app',
        'priority': 1,
        'deadline': '2026-12-01',
      }),
      goal({
        'id': 'pane',
        'title': 'Write the goals pane',
        'parent_id': 'ship',
        'required': true,
        'deadline': '2026-11-24',
        'deadline_offset_minutes': 7 * 24 * 60,
        'expected_minutes': 600,
        'description': '<p>The pane that lists every goal.</p>',
      }),
    ]);
    final memory = PlanMemory();
    await memory.loadGoals(repository);
    await tester.pumpWidget(
      PlanMemoryScope(
        memory: memory,
        child: MaterialApp(
          home: GoalScreen(
            goalId: 'pane',
            repository: repository,
            memory: memory,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets("a sub-goal's page", (tester) async {
    await pump(tester);
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goal_page.png'),
    );
  });

  testWidgets("a sub-goal's edit page", (tester) async {
    await pump(tester);
    await tester.tap(find.byTooltip('Edit'));
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goal_edit_page.png'),
    );
  });
}
