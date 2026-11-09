import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:time_tracker_client/models/goal.dart';
import 'package:time_tracker_client/models/goal_changes.dart';
import 'package:time_tracker_client/services/goals_repository.dart';
import 'package:time_tracker_client/services/plan_memory.dart';
import 'package:time_tracker_client/widgets/goal_flows.dart';

final _now = DateTime(2026, 11, 9, 11);

Goal _goal(
  String id, {
  String? parent,
  String status = 'active',
  String deadline = '2026-12-01',
}) => Goal.fromJson({
  'id': id,
  'title': id,
  'parent_id': parent,
  'status': status,
  'deadline': deadline,
  'history': [
    {'status': status, 'at': '2026-10-01T09:00:00'},
  ],
});

void main() {
  group('the changes', () {
    final goals = [
      _goal('top', deadline: '2026-12-20'),
      _goal('mid', parent: 'top', deadline: '2026-11-08'),
      _goal('leaf', parent: 'mid', deadline: '2026-11-05'),
      _goal('later', deadline: '2026-11-30'),
      _goal('soon', parent: 'later', deadline: '2026-11-20'),
      _goal('soonest', parent: 'soon', deadline: '2026-11-15'),
    ];
    final tree = GoalTree(goals);

    test('only the goals due too soon are in the way', () {
      expect(
        parentsInTheWay(tree, tree['leaf']!, '2026-11-11').map((g) => g.id),
        ['mid'],
      );
      expect(parentsInTheWay(tree, tree['leaf']!, '2026-11-07'), isEmpty);
      expect(
        parentsInTheWay(tree, tree['soonest']!, '2026-12-01').map((g) => g.id),
        ['later', 'soon'],
      );
    });

    test('a parent overdue is missed and tried again; a parent still to '
        'come just moves; and the rules hold', () {
      final overdue = retryingToFit(
        tree,
        tree['leaf']!,
        '2026-11-11',
        const ExtendParents(),
        now: _now,
      );
      expect(planned(goals, [GoalBatch(overdue)], now: _now), isEmpty);
      final after = GoalTree(applied(goals, overdue, now: _now));
      expect(after['mid']!.deadline, '2026-11-11');
      expect(after['mid']!.history.map((h) => h.status), [
        'active',
        'missed',
        'active',
      ]);
      expect(after['mid']!.history[1].deadline, '2026-11-08');
      expect(after['top']!.deadline, '2026-12-20');

      final coming = retryingToFit(
        tree,
        tree['soonest']!,
        '2026-12-01',
        const ExtendParents(),
        now: _now,
      );
      expect(planned(goals, [GoalBatch(coming)], now: _now), isEmpty);
      final moved = GoalTree(applied(goals, coming, now: _now));
      expect(moved['soon']!.deadline, '2026-12-01');
      expect(moved['soon']!.history, hasLength(1));
      expect(moved['later']!.deadline, '2026-12-01');
    });

    test('an inactive parent overdue just moves: it was never under way', () {
      final waiting = [
        _goal('p', status: 'inactive', deadline: '2026-11-01'),
        _goal('c', parent: 'p', deadline: '2026-10-30'),
      ];
      final t = GoalTree(waiting);
      final after = GoalTree(
        applied(
          waiting,
          extendingParents(t, t['c']!, '2026-11-20', now: _now),
          now: _now,
        ),
      );
      expect(after['p']!.deadline, '2026-11-20');
      expect(after['p']!.history, hasLength(1));
    });

    test('moving out leaves the old parent alone', () {
      final changes = retryingToFit(
        tree,
        tree['leaf']!,
        '2026-11-11',
        const MoveOut(),
        now: _now,
      );
      expect(planned(goals, changes, now: _now), isEmpty);
      final after = GoalTree(applied(goals, changes, now: _now));
      expect(after['leaf']!.parentId, isNull);
      expect(after['leaf']!.deadline, '2026-11-11');
      expect(after['mid']!.deadline, '2026-11-08');
    });

    test('a fit goes to the server, and comes back, as retry_fit', () {
      expect(const ExtendParents().toJson(), {'kind': 'extend_parents'});
      expect(const MoveOut().toJson(), {'kind': 'move'});
      expect(const MoveOut(to: 'g').toJson(), {
        'kind': 'move',
        'parent_id': 'g',
      });
      for (final fit in const [ExtendParents(), MoveOut(), MoveOut(to: 'g')]) {
        expect(DeadlineFit.fromJson(fit.toJson()), fit);
      }
      expect(DeadlineFit.fromJson(null), isNull);
      expect(DeadlineFit.fromJson({'kind': 'other'}), isNull);
    });
  });

  group('the prompt', () {
    late InMemoryGoalsRepository repository;
    late PlanMemory memory;
    late GoalActions actions;
    final year = DateTime.now().year;

    /// A page with a button doing [run] to the goals: the parent, due
    /// [parentDue], and its sub-goal, due on the 3rd of January.
    Future<void> pump(
      WidgetTester tester,
      Future<void> Function(GoalActions, Goal) run, {
      required String parentDue,
    }) async {
      repository = InMemoryGoalsRepository([
        _goal('parent', deadline: parentDue),
        _goal('child', parent: 'parent', deadline: '$year-01-03'),
        _goal('elsewhere', deadline: '${year + 1}-06-01'),
      ]);
      memory = PlanMemory();
      await memory.loadGoals(repository);
      tester.view.physicalSize = const Size(900, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) {
                actions = GoalActions(
                  context: context,
                  repository: repository,
                  memory: memory,
                );
                return TextButton(
                  onPressed: () => run(
                    actions,
                    memory.goals!.singleWhere((g) => g.id == 'child'),
                  ),
                  child: const Text('Go'),
                );
              },
            ),
          ),
        ),
      );
      await tester.tap(find.text('Go'));
      await tester.pumpAndSettle();
    }

    Goal goal(String id) => memory.goals!.singleWhere((g) => g.id == id);

    /// Picks the first date offered: tomorrow.
    Future<void> tomorrow(WidgetTester tester) async {
      expect(find.text('Try again by'), findsOneWidget);
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
    }

    testWidgets('a retry after its overdue parent says so, and extending '
        'records the miss on the parent too', (tester) async {
      await pump(tester, (a, g) => a.retry(g), parentDue: '$year-01-05');
      await tomorrow(tester);

      expect(find.text('Due after its parent'), findsOneWidget);
      expect(find.textContaining('recorded as missed'), findsOneWidget);
      // Nothing's changed till it's answered.
      expect(goal('child').deadline, '$year-01-03');

      await tester.tap(find.text('Extend its parent'));
      await tester.pumpAndSettle();

      final due = goal('child').deadline;
      expect(due, isNot('$year-01-03'));
      expect(goal('child').history.map((h) => h.status), [
        'active',
        'missed',
        'active',
      ]);
      expect(goal('parent').deadline, due);
      expect(goal('parent').history.map((h) => h.status), [
        'active',
        'missed',
        'active',
      ]);
      expect(goal('parent').history[1].deadline, '$year-01-05');
    });

    testWidgets('a parent still to come is just moved', (tester) async {
      final today = deadlineOf(DateTime.now());
      await pump(tester, (a, g) => a.retry(g), parentDue: today);
      await tomorrow(tester);

      expect(find.textContaining('recorded as missed'), findsNothing);
      await tester.tap(find.text('Extend its parent'));
      await tester.pumpAndSettle();

      expect(goal('parent').deadline, goal('child').deadline);
      expect(goal('parent').history, hasLength(1));
    });

    testWidgets('it can move out instead: under a goal due late enough, or '
        'to the top level', (tester) async {
      await pump(tester, (a, g) => a.retry(g), parentDue: '$year-01-05');
      await tomorrow(tester);

      await tester.tap(find.text('Move it out…'));
      await tester.pumpAndSettle();
      // Not its own parent, due too soon.
      expect(find.widgetWithText(ListTile, 'parent'), findsNothing);
      expect(find.widgetWithText(ListTile, 'elsewhere'), findsOneWidget);

      await tester.tap(find.text('To the top level'));
      await tester.pumpAndSettle();

      expect(goal('child').parentId, isNull);
      expect(goal('parent').deadline, '$year-01-05');
    });

    testWidgets('calling it off changes nothing', (tester) async {
      await pump(tester, (a, g) => a.retry(g), parentDue: '$year-01-05');
      await tomorrow(tester);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(goal('child').deadline, '$year-01-03');
      expect(goal('child').history, hasLength(1));
    });

    testWidgets('another date can be picked, and it asks again if that '
        "doesn't fit either", (tester) async {
      await pump(tester, (a, g) => a.retry(g), parentDue: '$year-01-05');
      await tomorrow(tester);

      await tester.tap(find.text('Pick another date…'));
      await tester.pumpAndSettle();
      await tomorrow(tester);

      expect(find.text('Due after its parent'), findsOneWidget);
    });

    testWidgets('a retry that fits asks nothing', (tester) async {
      await pump(tester, (a, g) => a.retry(g), parentDue: '${year + 1}-01-05');
      await tomorrow(tester);

      expect(find.text('Due after its parent'), findsNothing);
      expect(goal('child').history, hasLength(3));
      expect(goal('parent').history, hasLength(1));
    });

    testWidgets('a deadline edited past its parent can be saved, and asks', (
      tester,
    ) async {
      await pump(tester, (a, g) => a.edit(g), parentDue: '$year-01-05');

      await tester.tap(find.textContaining('Jan 3'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('20'));
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();

      expect(find.text('Due after its parent'), findsOneWidget);
      // Saved as a plain edit: the sub-goal's history has no miss.
      await tester.tap(find.text('Extend its parent'));
      await tester.pumpAndSettle();
      expect(goal('child').deadline, '$year-01-20');
      expect(goal('child').history, hasLength(1));
      expect(goal('parent').deadline, '$year-01-20');
    });
  });
}
