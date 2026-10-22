import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:time_tracker_client/models/goal.dart';
import 'package:time_tracker_client/widgets/color_picker.dart';
import 'package:time_tracker_client/widgets/goal_tile.dart';
import 'package:time_tracker_client/widgets/goals_due_strip.dart';

Goal _goal(String id, String title, String? deadline, {String? status}) =>
    Goal(id: id, title: title, deadline: deadline, status: status ?? 'active');

void main() {
  final day = DateTime(2026, 10, 18);
  final goals = [
    _goal('a', 'Zebra', '2026-10-18'),
    _goal('b', 'Apple', '2026-10-18'),
    _goal('c', 'Late', '2026-10-18T17:00'),
    _goal('d', 'Early', '2026-10-18T09:30', status: 'done'),
    _goal('e', 'Tomorrow', '2026-10-19'),
    _goal('f', 'None', null),
  ];

  test('goalsDueOn takes the day\'s, open ones first, timed ones first', () {
    expect(goalsDueOn(goals, day).map((g) => g.id), ['c', 'b', 'a', 'd']);
    expect(goalsDueOn(goals, DateTime(2026, 10, 17)), isEmpty);
  });

  test('goalsDueOn: by status, then as byPriority has each', () {
    final mixed = [
      _goal('obsolete', 'A', '2026-10-18T08:00', status: 'obsolete'),
      _goal('missed', 'A', '2026-10-18T08:00', status: 'missed'),
      _goal('done late', 'B', '2026-10-18T20:00', status: 'done'),
      _goal('done', 'A', '2026-10-18', status: 'done'),
      _goal('done early', 'C', '2026-10-18T08:00', status: 'done'),
      _goal('inactive', 'A', '2026-10-18T08:00', status: 'inactive'),
      _goal('active', 'Z', '2026-10-18'),
      _goal('active early', 'Z', '2026-10-18T23:00'),
    ];
    expect(goalsDueOn(mixed, day).map((g) => g.id), [
      'active early',
      'active',
      'inactive',
      'done early',
      'done late',
      'done',
      'missed',
      'obsolete',
    ]);
    final active = mixed.where((g) => g.active);
    expect(
      goalsDueOn(active, day).map((g) => g.id),
      byPriority(active).map((g) => g.id),
    );
  });

  test('goalsDueOn: within a status, the highest priority first, '
      'inherited from goals not listed', () {
    const parent = Goal(id: 'parent', title: 'Parent', priority: 0);
    final due = [
      _goal('p3 early', 'A', '2026-10-18T08:00'),
      _goal('p1', 'B', '2026-10-18'),
      Goal(
        id: 'inherits p0',
        title: 'C',
        parentId: 'parent',
        deadline: '2026-10-18T20:00',
      ),
      _goal('done p0', 'D', '2026-10-18', status: 'done'),
    ];
    final withPriorities = [
      for (final g in due)
        switch (g.id) {
          'p1' => Goal.fromJson({...g.toJson(), 'priority': 1}),
          'done p0' => Goal.fromJson({...g.toJson(), 'priority': 0}),
          _ => g,
        },
    ];
    expect(
      goalsDueOn(
        withPriorities,
        day,
        GoalTree([parent, ...withPriorities]),
      ).map((g) => g.id),
      ['inherits p0', 'p1', 'p3 early', 'done p0'],
    );
  });

  test('overdueGoalsOn: the open goals due before the day, active first, '
      'then the highest priority, then the longest overdue', () {
    final mixed = [
      _goal('today', 'Today', '2026-10-18'),
      _goal('yesterday', 'Yesterday', '2026-10-17T17:00'),
      _goal('older', 'Older', '2026-10-10'),
      _goal('inactive', 'Inactive', '2026-10-01', status: 'inactive'),
      _goal('done', 'Done', '2026-10-01', status: 'done'),
      _goal('missed', 'Missed', '2026-10-01', status: 'missed'),
      _goal('obsolete', 'Obsolete', '2026-10-01', status: 'obsolete'),
      _goal('none', 'None', null),
      Goal.fromJson({
        ..._goal('urgent', 'Urgent', '2026-10-15').toJson(),
        'priority': 0,
      }),
    ];
    expect(overdueGoalsOn(mixed, day).map((g) => g.id), [
      'urgent',
      'older',
      'yesterday',
      'inactive',
    ]);
    expect(overdueGoalsOn(mixed, DateTime(2026, 10, 1)), isEmpty);
    expect(overdueGoalsOn(mixed, DateTime(2026, 10, 2)).map((g) => g.id), [
      'inactive',
    ]);
    const parent = Goal(id: 'parent', title: 'Parent', priority: 0);
    final child = Goal(
      id: 'child',
      title: 'Child',
      parentId: 'parent',
      deadline: '2026-10-17',
    );
    expect(
      overdueGoalsOn(
        [...mixed, child],
        day,
        tree: GoalTree([parent, ...mixed, child]),
      ).map((g) => g.id).take(2),
      ['urgent', 'child'],
    );
  });

  test("overdueGoalsOn: on a day ahead of today, only what's overdue "
      'today, not what falls due before the day shown', () {
    final ahead = [
      _goal('past', 'Past', '2026-10-17'),
      _goal('today', 'Today', '2026-10-18'),
      _goal('soon', 'Soon', '2026-10-20'),
    ];
    expect(overdueGoalsOn(ahead, DateTime(2026, 10, 25)).map((g) => g.id), [
      'past',
      'today',
      'soon',
    ]);
    expect(
      overdueGoalsOn(
        ahead,
        DateTime(2026, 10, 25),
        today: day,
      ).map((g) => g.id),
      ['past'],
    );
    expect(
      overdueGoalsOn(
        ahead,
        day,
        today: DateTime(2026, 10, 25),
      ).map((g) => g.id),
      ['past'],
    );
  });

  Future<void> pump(
    WidgetTester tester, {
    required bool collapsed,
    ValueChanged<bool>? onCollapsed,
    ValueChanged<Goal>? onTap,
  }) => tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: GoalsDueStrip(
          goals: goalsDueOn(goals, day),
          collapsed: collapsed,
          onCollapsed: onCollapsed ?? (_) {},
          onTap: onTap,
        ),
      ),
    ),
  );

  testWidgets('open, a pill each; tapping one opens it', (tester) async {
    Goal? tapped;
    await pump(tester, collapsed: false, onTap: (g) => tapped = g);
    expect(find.textContaining('Zebra'), findsOneWidget);
    expect(find.textContaining('5:00 PM'), findsOneWidget);
    expect(find.byIcon(Icons.check), findsOneWidget);
    await tester.tap(find.textContaining('Apple'));
    expect(tapped?.id, 'b');
  });

  testWidgets('collapsed, one line; tapping it opens', (tester) async {
    bool? collapsed;
    await pump(tester, collapsed: true, onCollapsed: (c) => collapsed = c);
    expect(find.textContaining('4 goals due (3 open)'), findsOneWidget);
    await tester.tap(find.textContaining('4 goals due'));
    expect(collapsed, isFalse);
  });

  testWidgets("overdue goals follow the day's, each saying the day it was "
      'due, in the error color; tapping one opens it; nothing on a past '
      'or future day', (tester) async {
    Goal? tapped;
    final late = [
      _goal('o', 'Late report', '2026-10-17'),
      _goal('t', 'Timed', '2026-10-16T09:00'),
    ];
    Future<void> show({
      required DateTime today,
      required bool collapsed,
      List<Goal>? due,
    }) => tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: GoalsDueStrip(
            goals: due ?? goalsDueOn(goals, day),
            overdue: late,
            day: day,
            today: today,
            collapsed: collapsed,
            onCollapsed: (_) {},
            onTap: (g) => tapped = g,
          ),
        ),
      ),
    );
    await show(today: day, collapsed: false);
    expect(find.text('Overdue'), findsOneWidget);
    expect(find.textContaining('due Oct 17'), findsOneWidget);
    expect(find.textContaining('due Oct 16'), findsOneWidget);
    expect(find.textContaining('9:00 AM'), findsNothing);
    final colors = Theme.of(tester.element(find.byType(GoalsDueStrip)))
        .colorScheme;
    Material pillOf(String text) => tester.widget<Material>(
      find
          .ancestor(
            of: find.textContaining(text),
            matching: find.byType(Material),
          )
          .first,
    );
    expect(
      (pillOf('due Oct 17').shape! as StadiumBorder).side.color,
      colors.error,
    );
    expect(
      (pillOf('Zebra').shape! as StadiumBorder).side.color,
      isNot(colors.error),
    );
    await tester.tap(find.textContaining('due Oct 17'));
    expect(tapped?.id, 'o');

    await show(today: day, collapsed: true);
    expect(
      find.textContaining('4 goals due (3 open), 2 overdue · '),
      findsOneWidget,
    );
    expect(find.textContaining('Late report, Timed'), findsOneWidget);
    await show(today: day, collapsed: true, due: const []);
    expect(
      find.textContaining('2 goals overdue · Late report, Timed'),
      findsOneWidget,
    );

    // The day shown is past: just its own.
    await show(today: DateTime(2026, 10, 19), collapsed: false);
    expect(find.text('Overdue'), findsNothing);
    expect(find.textContaining('due Oct'), findsNothing);
    expect(find.textContaining('Zebra'), findsOneWidget);
    await show(today: DateTime(2026, 10, 19), collapsed: true);
    expect(find.textContaining('overdue'), findsNothing);
    await show(today: DateTime(2026, 10, 19), collapsed: false, due: const []);
    expect(find.byType(InkWell), findsNothing);

    // The day shown is ahead: just its own too.
    await show(today: DateTime(2026, 10, 17), collapsed: false);
    expect(find.text('Overdue'), findsNothing);
    expect(find.textContaining('due Oct'), findsNothing);
    expect(find.textContaining('Zebra'), findsOneWidget);
  });

  testWidgets("each pill is in its priority's color: filled when open, "
      "outlined when closed; a goal with none takes its parent's", (
    tester,
  ) async {
    final ranked = [
      Goal(id: 'p', title: 'Parent', priority: 1),
      Goal(
        id: 'k',
        title: 'Kid',
        parentId: 'p',
        deadline: '2026-10-18',
        status: 'active',
      ),
      Goal(id: 'u', title: 'Urgent', priority: 0, deadline: '2026-10-18'),
      Goal(
        id: 'x',
        title: 'Finished',
        priority: 2,
        deadline: '2026-10-18',
        status: 'done',
      ),
    ];
    final tree = GoalTree(ranked);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: GoalsDueStrip(
            goals: goalsDueOn(ranked, day, tree),
            tree: tree,
            collapsed: false,
            onCollapsed: (_) {},
          ),
        ),
      ),
    );
    Material pillOf(String text) => tester.widget<Material>(
      find
          .ancestor(
            of: find.textContaining(text),
            matching: find.byType(Material),
          )
          .first,
    );
    expect(pillOf('Kid').color, priorityColor(1));
    expect(pillOf('Urgent').color, priorityColor(0));
    expect(pillOf('Finished').color, Colors.transparent);
    expect(
      (pillOf('Finished').shape! as StadiumBorder).side.color,
      priorityColor(2),
    );
  });

  testWidgets('nothing, with nothing due', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: GoalsDueStrip(
          goals: const [],
          collapsed: false,
          onCollapsed: (_) {},
        ),
      ),
    );
    expect(find.byType(InkWell), findsNothing);
  });

  test("leftLabel: what's left of the expected time, or how far over", () {
    final goal = Goal.fromJson({
      ..._goal('g', 'G', '2026-10-18').toJson(),
      'expected_minutes': 600,
    });
    expect(leftLabel(goal, null), '10h left');
    expect(
      leftLabel(goal, const Duration(hours: 6, minutes: 20)),
      '3h 40m left',
    );
    expect(leftLabel(goal, const Duration(hours: 10)), '0m left');
    expect(leftLabel(goal, const Duration(hours: 11)), '1h over');
    expect(leftLabel(_goal('n', 'N', '2026-10-18'), Duration.zero), isNull);
  });

  testWidgets("an open goal's pill says what's left of its expected time; "
      "a closed one's doesn't", (tester) async {
    Goal expecting(Goal g) =>
        Goal.fromJson({...g.toJson(), 'expected_minutes': 120});
    final due = [
      expecting(_goal('o', 'Open', '2026-10-18')),
      expecting(_goal('x', 'Over', '2026-10-18')),
      expecting(_goal('d', 'Done', '2026-10-18', status: 'done')),
      _goal('n', 'No estimate', '2026-10-18'),
    ];
    Future<void> show(Map<String, Duration>? spent) => tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: GoalsDueStrip(
            goals: due,
            spent: spent,
            collapsed: false,
            onCollapsed: (_) {},
          ),
        ),
      ),
    );
    await show(const {
      'o': Duration(minutes: 45),
      'x': Duration(hours: 3),
      'd': Duration(minutes: 30),
    });
    expect(find.textContaining('1h 15m left'), findsOneWidget);
    expect(find.textContaining('1h over'), findsOneWidget);
    expect(find.textContaining('1h 30m left'), findsNothing);
    expect(find.textContaining('left'), findsNWidgets(1));
    await show(null);
    expect(find.textContaining('left'), findsNothing);
    expect(find.textContaining('over'), findsNothing);
  });
}
