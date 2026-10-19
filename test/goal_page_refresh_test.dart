import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:time_tracker_client/models/goal.dart';
import 'package:time_tracker_client/screens/goal_screen.dart';
import 'package:time_tracker_client/services/goals_repository.dart';
import 'package:time_tracker_client/services/plan_memory.dart';

/// Goals whose titles the test can change, as if changed elsewhere,
/// counting each time they're asked for.
class _ChangingGoals extends InMemoryGoalsRepository {
  _ChangingGoals() : super(const []);

  var title = 'Ship the app';
  var asked = 0;

  @override
  Future<List<Goal>> goals() async {
    asked++;
    return [
      Goal.fromJson({
        'id': 'ship',
        'title': title,
        'status': 'active',
        'deadline': '2026-12-01',
      }),
    ];
  }
}

void main() {
  late _ChangingGoals repository;

  Future<void> pump(WidgetTester tester) async {
    repository = _ChangingGoals();
    final memory = PlanMemory();
    await memory.loadGoals(repository);
    await tester.pumpWidget(
      MaterialApp(
        home: GoalScreen(
          goalId: 'ship',
          repository: repository,
          memory: memory,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Ship the app'), findsOneWidget);
    repository.title = 'Ship it';
  }

  testWidgets("the refresh button loads a goal's page again", (tester) async {
    await pump(tester);
    final before = repository.asked;
    await tester.tap(find.byTooltip('Refresh'));
    await tester.pumpAndSettle();
    expect(repository.asked, before + 1);
    expect(find.text('Ship it'), findsOneWidget);
  });

  testWidgets("pulling a goal's page down loads it again", (tester) async {
    await pump(tester);
    final before = repository.asked;
    await tester.fling(find.byType(ListView), const Offset(0, 400), 1000);
    await tester.pumpAndSettle();
    expect(repository.asked, before + 1);
    expect(find.text('Ship it'), findsOneWidget);
  });
}
