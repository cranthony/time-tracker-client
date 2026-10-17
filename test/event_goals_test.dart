import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:time_tracker_client/models/event.dart';
import 'package:time_tracker_client/models/goal.dart';
import 'package:time_tracker_client/services/goals_repository.dart';
import 'package:time_tracker_client/services/people_repository.dart';
import 'package:time_tracker_client/services/plan_memory.dart';
import 'package:time_tracker_client/widgets/event_summary_dialog.dart';

Goal _goal(String id, String title, {String status = 'active'}) =>
    Goal.fromJson({
      'id': id,
      'title': title,
      'status': status,
      'deadline': status == 'active' ? '2026-12-01' : null,
      'history': [
        {'status': status, 'at': '2026-09-01T09:00:00'},
      ],
    });

void main() {
  late InMemoryGoalsRepository repository;
  late PlanMemory memory;

  /// Opens [event]'s dialog, returning what a save sends.
  Future<Map<String, Object?>? Function()> open(
    WidgetTester tester,
    Event event,
  ) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final goals = [
      _goal('ship', 'Ship the app'),
      _goal('read', 'Read more', status: 'inactive'),
    ];
    repository = InMemoryGoalsRepository(goals);
    memory = PlanMemory()..goals = await repository.goals();
    Map<String, Object?>? saved;
    await tester.pumpWidget(
      PlanMemoryScope(
        memory: memory,
        child: GoalsScope(
          repository: repository,
          child: PeopleScope(
            repository: InMemoryPeopleRepository(),
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

  Event focus({List<Map<String, Object?>> goals = const []}) => Event(
    id: 'e1',
    summary: 'Focus',
    start: DateTime(2026, 10, 1, 9),
    end: DateTime(2026, 10, 1, 10),
    properties: {'goals': goals},
  );

  testWidgets('shows its goals, with what each takes', (tester) async {
    await open(
      tester,
      focus(
        goals: [
          {'goal_id': 'ship', 'minutes': 45},
        ],
      ),
    );

    expect(find.text('Ship the app'), findsOneWidget);
    expect(find.text('45m'), findsOneWidget);
  });

  testWidgets('tags it with a goal, activating an inactive one from its '
      'start', (tester) async {
    final saved = await open(tester, focus());
    expect(find.text('Add goals'), findsOneWidget);

    await tester.tap(find.text('Add goals'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Read more'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();

    expect(find.text('Activate it?'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Activate'));
    await tester.pumpAndSettle();
    // It needs a deadline.
    await tester.tap(find.text('End of this week'));
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Activate'));
    await tester.pumpAndSettle();

    final read = (await repository.goals()).firstWhere((g) => g.id == 'read');
    expect(read.active, isTrue);
    expect(read.startedAt!.isAtSameMomentAs(DateTime(2026, 10, 1, 9)), isTrue);

    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(saved()?['goals'], [
      {'goal_id': 'read'},
    ]);
  });
}
