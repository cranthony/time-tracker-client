import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:time_tracker_client/models/goal.dart';
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
}
