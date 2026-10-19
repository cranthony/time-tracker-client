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

  test('goalsDueOn takes the day\'s, timed ones first', () {
    expect(goalsDueOn(goals, day).map((g) => g.id), ['d', 'c', 'b', 'a']);
    expect(goalsDueOn(goals, DateTime(2026, 10, 17)), isEmpty);
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
