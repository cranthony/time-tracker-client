import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:time_tracker_client/models/goal.dart';
import 'package:time_tracker_client/widgets/goals_due_strip.dart';

void main() {
  final roti = Goal(
    id: 'roti',
    title: 'Make roti',
    deadline: '2026-10-31',
    path: const ['Cook'],
  );
  final raabia = Goal(
    id: 'raabia',
    title: 'Check in with Raabia',
    deadline: '2026-10-31',
  );
  final bank = Goal(id: 'bank', title: 'Call the bank', deadline: '2026-10-31');

  testWidgets('Tab goes in the order shown after the goals are re-sorted', (
    tester,
  ) async {
    final focus = GoalsStripFocus();
    addTearDown(focus.dispose);
    Future<void> show(List<Goal> goals) => tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: GoalsDueStrip(
            goals: goals,
            collapsed: false,
            onCollapsed: (_) {},
            onTap: (_) {},
            focus: focus,
          ),
        ),
      ),
    );

    String? focused() {
      final context = FocusManager.instance.primaryFocus?.context;
      for (final g in [roti, raabia, bank]) {
        final inIt = find.descendant(
          of: find.byElementPredicate((e) => e == context),
          matching: find.textContaining(g.title),
        );
        if (inIt.evaluate().isNotEmpty) return g.title;
      }
      return null;
    }

    await show([roti, raabia, bank]);
    // Re-sorted: the first and last pills are rebuilt -- one loses its
    // parent's tooltip, the other gains it -- the middle one is kept.
    await show([raabia, bank, roti]);
    expect(focus.focusFirst(focus.due), isTrue);
    await tester.pump();
    expect(focused(), 'Check in with Raabia');
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    expect(focused(), 'Call the bank');
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    expect(focused(), 'Make roti');
  });
}
