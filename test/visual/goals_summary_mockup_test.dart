// Mockup only: the Goals page's time summary in each style.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:time_tracker_client/demo/sample_data.dart';
import 'package:time_tracker_client/outbox/goal_outbox.dart';
import 'package:time_tracker_client/outbox/outbox_store.dart';
import 'package:time_tracker_client/screens/goals_screen.dart';
import 'package:time_tracker_client/services/goals_repository.dart';
import 'package:time_tracker_client/theme.dart';
import 'package:time_tracker_client/widgets/day_summary.dart';
import 'package:time_tracker_client/widgets/goals_time_summary.dart';

void main() {
  final sample = SampleData(DateTime(2026, 10, 2, 13, 30));
  for (final brightness in [Brightness.light]) {
    for (final (name, style, step) in [
      ('a_stacked', GoalsSummaryStyle.stacked, null),
      ('b_windows_24h', GoalsSummaryStyle.windows, null),
      ('b_windows_7d', GoalsSummaryStyle.windows, 'swipe'),
      ('c_toggle_goals_24h', GoalsSummaryStyle.toggle, null),
      ('c_toggle_goals_7d', GoalsSummaryStyle.toggle, '7d'),
      ('c_toggle_priorities_7d', GoalsSummaryStyle.toggle, '7d+swipe'),
    ]) {
      testWidgets(name, (tester) async {
        goalsSummaryStyle = style;
        tester.view.physicalSize = const Size(390, 844) * 2;
        tester.view.devicePixelRatio = 2;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(
          MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: appTheme(brightness),
            home: GoalsScreen(
              outbox: GoalOutbox(
                store: InMemoryOutboxStore(),
                repository: InMemoryGoalsRepository(),
              ),
              repository: sample.goalsRepository(),
              serverLabel: 'sample',
            ),
          ),
        );
        await tester.pumpAndSettle();
        if (step != null && step.contains('7d')) {
          await tester.tap(find.text('7d').first);
          await tester.pumpAndSettle();
        }
        if (step != null && step.contains('swipe')) {
          await tester.fling(
            find.byType(SummaryPages),
            const Offset(-300, 0),
            1000,
          );
          await tester.pumpAndSettle();
        }
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile('goals_summary_$name.png'),
        );
      });
    }
  }
}
