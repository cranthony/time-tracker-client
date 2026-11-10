import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:time_tracker_client/models/goal.dart';
import 'package:time_tracker_client/models/goal_activation.dart';
import 'package:time_tracker_client/services/goals_repository.dart';
import 'package:time_tracker_client/services/plan_memory.dart';
import 'package:time_tracker_client/widgets/duration_field.dart';
import 'package:time_tracker_client/widgets/goal_flows.dart';

Goal _goal(
  String id, {
  String status = 'active',
  String? deadline,
  Map<String, Object?>? activateWhen,
  Map<String, Object?>? deadlineRule,
}) => Goal.fromJson({
  'id': id,
  'title': id,
  'status': status,
  'deadline': ?deadline,
  'activate_when': ?activateWhen,
  'deadline_rule': ?deadlineRule,
  'history': [
    {'status': status, 'at': '2026-10-01T09:00:00'},
  ],
});

Map<String, Object?> _at(String at) => {
  'after': [
    {'at': at},
  ],
};

void main() {
  group('starting past its deadline', () {
    final now = DateTime(2026, 11, 9, 11);

    DateTime? past(Goal goal, [List<Goal> others = const []]) =>
        startsPastDeadline(goal, GoalTree([goal, ...others]), now: now);

    test('a date to wait for after its deadline is past it', () {
      final goal = _goal(
        'g',
        status: 'inactive',
        deadline: '2026-11-20',
        activateWhen: _at('2026-12-01'),
      );
      expect(past(goal), DateTime(2026, 12, 1));
    });

    test('starting on the day it is due, it can', () {
      final goal = _goal(
        'g',
        status: 'inactive',
        deadline: '2026-12-01',
        activateWhen: _at('2026-12-01'),
      );
      expect(past(goal), isNull);
    });

    test('a deadline measured from its start has none to be past', () {
      final goal = _goal(
        'g',
        status: 'inactive',
        activateWhen: _at('2026-12-01'),
        deadlineRule: {
          'after_start': {'days': 7},
        },
      );
      expect(past(goal), isNull);
    });

    test('waiting on a goal due after its deadline is past it', () {
      final first = _goal('first', deadline: '2026-12-01');
      final goal = _goal(
        'g',
        status: 'inactive',
        deadline: '2026-11-20',
        activateWhen: {
          'after': [
            {'goal_closed': 'first'},
          ],
        },
      );
      expect(past(goal, [first]), isNotNull);
    });

    test('an active goal is not waiting to start', () {
      expect(past(_goal('g', deadline: '2026-11-20')), isNull);
    });
  });

  group('the prompt', () {
    late InMemoryGoalsRepository repository;
    late PlanMemory memory;
    final today = deadlineOf(DateTime.now());
    final nextYear = '${DateTime.now().year + 1}-06-01';

    Future<void> pump(
      WidgetTester tester,
      Goal start,
      Future<void> Function(GoalActions, Goal) run,
    ) async {
      repository = InMemoryGoalsRepository([start]);
      memory = PlanMemory();
      await memory.loadGoals(repository);
      tester.view.physicalSize = const Size(900, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => run(
                  GoalActions(
                    context: context,
                    repository: repository,
                    memory: memory,
                  ),
                  memory.goals!.single,
                ),
                child: const Text('Go'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Go'));
      await tester.pumpAndSettle();
    }

    Goal goal() => memory.goals!.single;

    /// Deactivates a goal due [deadline] until tomorrow, this time
    /// tomorrow: the deadline's today, so that's past it.
    Future<void> deactivateUntilTomorrow(
      WidgetTester tester, {
      required String deadline,
    }) async {
      await pump(
        tester,
        _goal('g', deadline: deadline),
        (a, g) => a.deactivateUntil(g),
      );
      await tester.tap(find.text('For a while…'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'OK'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Deactivate'));
      await tester.pumpAndSettle();
    }

    testWidgets('deactivating past its deadline asks, and it can be due a '
        'week after it starts', (tester) async {
      await deactivateUntilTomorrow(tester, deadline: today);

      expect(find.text('Due before it starts'), findsOneWidget);
      // Nothing's changed till it's answered.
      expect(goal().status, 'active');

      await tester.tap(find.text('Due after it starts'));
      await tester.pumpAndSettle();

      expect(find.text('Due before it starts'), findsNothing);
      expect(goal().status, 'inactive');
      expect(goal().activateWhen, isNotNull);
      expect(goal().deadline, isNull);
      expect(goal().deadlineRule, {
        'after_start': {'days': 7},
      });
    });

    testWidgets('how long after it starts can be changed', (tester) async {
      await deactivateUntilTomorrow(tester, deadline: today);

      await tester.enterText(
        find.descendant(
          of: find.byType(DurationField),
          matching: find.byType(TextField),
        ),
        '2d',
      );
      await tester.pump();
      await tester.tap(find.text('Due after it starts'));
      await tester.pumpAndSettle();

      expect(goal().deadlineRule, {
        'after_start': {'days': 2},
      });
    });

    testWidgets('another date can be picked, a week after it starts to '
        'begin with', (tester) async {
      await deactivateUntilTomorrow(tester, deadline: today);

      await tester.tap(find.text('Pick another date…'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();

      final now = DateTime.now();
      expect(goal().status, 'inactive');
      expect(goal().deadlineRule, isNull);
      expect(
        goal().deadline,
        deadlineOf(DateTime(now.year, now.month, now.day + 8)),
      );
    });

    testWidgets('the deadline can be left as it is', (tester) async {
      await deactivateUntilTomorrow(tester, deadline: today);

      await tester.tap(find.text('Leave the deadline'));
      await tester.pumpAndSettle();

      expect(goal().status, 'inactive');
      expect(goal().deadline, today);
      expect(goal().deadlineRule, isNull);
    });

    testWidgets('calling it off changes nothing', (tester) async {
      await deactivateUntilTomorrow(tester, deadline: today);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(goal().status, 'active');
      expect(goal().deadline, today);
      expect(goal().activateWhen, isNull);
    });

    testWidgets('deactivating until before its deadline asks nothing', (
      tester,
    ) async {
      await deactivateUntilTomorrow(tester, deadline: nextYear);

      expect(find.text('Due before it starts'), findsNothing);
      expect(goal().status, 'inactive');
      expect(goal().deadline, nextYear);
    });

    testWidgets('setting when it starts in the editor asks too', (
      tester,
    ) async {
      await pump(
        tester,
        _goal('g', status: 'inactive', deadline: today),
        (a, g) => a.edit(g),
      );

      await tester.tap(find.text('From a day…'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();

      expect(find.text('Due before it starts'), findsOneWidget);
      await tester.tap(find.text('Due after it starts'));
      await tester.pumpAndSettle();

      expect(goal().activateWhen, isNotNull);
      expect(goal().deadline, isNull);
      expect(goal().deadlineRule, {
        'after_start': {'days': 7},
      });
    });

    testWidgets('an edit to something else asks nothing', (tester) async {
      await pump(
        tester,
        _goal(
          'g',
          status: 'inactive',
          deadline: today,
          activateWhen: _at(nextYear),
        ),
        (a, g) => a.edit(g),
      );

      await tester.enterText(find.byType(TextField).first, 'Renamed');
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();

      expect(find.text('Due before it starts'), findsNothing);
      expect(goal().title, 'Renamed');
      expect(goal().deadline, today);
    });
  });
}
