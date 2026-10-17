import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:time_tracker_client/models/goal.dart';
import 'package:time_tracker_client/widgets/goal_picker.dart';

final _goals = [
  Goal.fromJson({
    'id': 'ship',
    'title': 'Ship the app',
    'deadline': '2026-12-01',
    'history': [
      {'status': 'active', 'at': '2026-10-01T09:00:00'},
    ],
  }),
  Goal.fromJson({
    'id': 'pane',
    'title': 'Write the pane',
    'parent_id': 'ship',
    'deadline': '2026-11-01',
    'history': [
      {'status': 'active', 'at': '2026-10-01T09:00:00'},
    ],
  }),
  Goal.fromJson({
    'id': 'old',
    'title': 'Old idea',
    'status': 'obsolete',
    'history': [
      {'status': 'obsolete', 'at': '2026-10-01T09:00:00'},
    ],
  }),
];

void main() {
  testWidgets('picks goals, each chip tapped to set what it takes', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    List<GoalShare>? picked;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async => picked = await showGoalsSheet(
              context,
              goals: _goals,
              picked: const [GoalShare('ship')],
              eventMinutes: 60,
            ),
            child: const Text('Open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    // Open goals only: the obsolete one isn't offered.
    expect(find.text('Old idea'), findsNothing);
    await tester.tap(find.text('Write the pane'));
    await tester.pumpAndSettle();

    // Its chip, tapped, sets its share.
    await tester.tap(find.widgetWithText(InputChip, 'Write the pane'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Minutes'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, '45');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Set'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(InputChip, 'Write the pane · 45m'), findsOne);

    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(picked, const [GoalShare('ship'), GoalShare('pane', minutes: 45)]);
  });

  testWidgets("a share can't take more than the event", (tester) async {
    GoalShare? set;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async => set = await showGoalShareDialog(
              context,
              goal: _goals.first,
              share: const GoalShare('ship'),
              eventMinutes: 30,
            ),
            child: const Text('Open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Minutes'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '31');
    await tester.pump();
    final setButton = find.widgetWithText(FilledButton, 'Set');
    expect(tester.widget<FilledButton>(setButton).onPressed, isNull);

    await tester.tap(find.text('Percent'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '25');
    await tester.pump();
    await tester.tap(setButton);
    await tester.pumpAndSettle();
    expect(set, const GoalShare('ship', percent: 25));
  });
}
