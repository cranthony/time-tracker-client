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
  Goal.fromJson({
    'id': 'email',
    'title': 'Answer the email',
    'status': 'done',
    'history': [
      {'status': 'active', 'at': '2026-10-20T09:00:00'},
      {'status': 'done', 'at': '2026-10-20T11:00:00'},
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

    // Open goals only: the closed ones aren't offered.
    expect(find.text('Old idea'), findsNothing);
    expect(find.text('Answer the email'), findsNothing);
    await tester.tap(find.text('Write the pane'));
    await tester.pumpAndSettle();

    // Its chip, tapped, sets its share.
    await tester.tap(find.widgetWithText(InputChip, 'Write the pane'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Duration'));
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

  testWidgets('offers the goals closed after the event started', (
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
              picked: const [],
              eventMinutes: 60,
              eventStart: DateTime(2026, 10, 20, 10),
            ),
            child: const Text('Open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    // Done at 11:00, after the event's 10:00 start, it's offered, its
    // status beside it; the one obsolete since 1 October isn't.
    expect(find.text('Old idea'), findsNothing);
    // "Done" twice: its status, and the sheet's button.
    expect(find.text('Done'), findsNWidgets(2));
    await tester.tap(find.text('Answer the email'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Done'));
    await tester.pumpAndSettle();
    expect(picked, const [GoalShare('email')]);
  });

  testWidgets('a goal is added, named as typed, and picked', (tester) async {
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final asked = <String>[];
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
              addGoal: (title) async {
                asked.add(title);
                final added = Goal.fromJson({
                  'id': 'docs',
                  'title': title,
                  'parent_id': 'ship',
                  'history': [
                    {'status': 'active', 'at': '2026-10-01T09:00:00'},
                  ],
                });
                return (added: added, goals: [..._goals, added]);
              },
            ),
            child: const Text('Open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'Write the docs');
    await tester.pump();
    await tester.tap(find.text('Add goal “Write the docs”…'));
    await tester.pumpAndSettle();
    expect(asked, ['Write the docs']);

    // Picked, the search cleared, and offered with the rest.
    expect(find.widgetWithText(InputChip, 'Write the docs'), findsOne);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      isEmpty,
    );
    expect(find.text('Write the pane'), findsOne);

    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(picked, const [GoalShare('ship'), GoalShare('docs')]);
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

    await tester.tap(find.text('Duration'));
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

  testWidgets('a share is given a duration as one is written', (tester) async {
    GoalShare? set;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async => set = await showGoalShareDialog(
              context,
              goal: _goals.first,
              share: const GoalShare('ship'),
              eventMinutes: 90,
            ),
            child: const Text('Open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Duration'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '1h 15m');
    await tester.pump();
    // And an hour more, past the event: too long to set.
    await tester.tap(find.byTooltip('An hour more'));
    await tester.pump();
    final setButton = find.widgetWithText(FilledButton, 'Set');
    expect(tester.widget<FilledButton>(setButton).onPressed, isNull);
    await tester.tap(find.byTooltip('An hour less'));
    await tester.pump();
    await tester.tap(setButton);
    await tester.pumpAndSettle();
    expect(set, const GoalShare('ship', minutes: 75));
  });
}
