import 'package:flutter/gestures.dart' show kLongPressTimeout;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:time_tracker_client/models/goal.dart';
import 'package:time_tracker_client/models/goal_activation.dart';
import 'package:time_tracker_client/screens/goals_pane.dart';
import 'package:time_tracker_client/services/goals_repository.dart';
import 'package:time_tracker_client/services/plan_memory.dart';
import 'package:time_tracker_client/widgets/goal_tile.dart';

Goal _goal(
  String id, {
  String status = 'inactive',
  String deadline = '2026-12-31',
  List<String> after = const [],
  bool held = false,
}) => Goal.fromJson({
  'id': id,
  'title': id,
  'status': status,
  'deadline': deadline,
  if (status == 'inactive' && !held)
    'activate_when': {
      'after': [
        for (final a in after) {'goal_closed': a},
      ],
    },
  'history': [
    {'status': status, 'at': '2026-11-01T09:00:00'},
  ],
});

void main() {
  late InMemoryGoalsRepository repository;

  Future<void> pump(WidgetTester tester, List<Goal> goals) async {
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    repository = InMemoryGoalsRepository(
      goals,
      () => DateTime(2026, 11, 21, 9),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: GoalsPane(repository: repository, memory: PlanMemory()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Show the backlog'));
    await tester.pumpAndSettle();
  }

  List<String> listed(WidgetTester tester) => [
    for (final tile in tester.widgetList<GoalTile>(find.byType(GoalTile)))
      tile.goal.title,
  ];

  final queue = [
    _goal('Work', status: 'active', deadline: '2026-11-25'),
    _goal('Draft', after: ['Work']),
    _goal('Review', after: ['Draft']),
    _goal('Send', after: ['Review']),
  ];

  testWidgets('the backlog lists each queue in order, under what starts it, '
      'with forks and goals waiting for two', (tester) async {
    await pump(tester, [
      ...queue,
      _goal('Side', after: ['Draft'], deadline: '2026-12-01'),
      _goal('Other', status: 'active', deadline: '2027-01-15'),
      _goal('Both', after: ['Draft', 'Other']),
      _goal('Someday', held: true),
    ]);
    expect(listed(tester), [
      'Work',
      'Draft',
      'Side',
      'Review',
      'Send',
      'Other',
      'Both',
      'Someday',
    ]);
    expect(find.text('Active: the next starts as it closes'), findsNWidgets(2));
    expect(find.text('On hold: starts when you start it'), findsOneWidget);
    expect(
      find.text('Then 2 branches start together: “Side”, “Review”'),
      findsOneWidget,
    );
    expect(find.text('Also waits for “Draft”'), findsOneWidget);
  });

  testWidgets('a goal dragged up its queue goes there, the queue closing up '
      'where it was, in one change', (tester) async {
    await pump(tester, queue);
    expect(listed(tester), ['Work', 'Draft', 'Review', 'Send']);

    final rowHeight = tester.getSize(find.byType(GoalTile).first).height;
    final gesture = await tester.startGesture(
      tester.getCenter(find.text('Send')),
    );
    await tester.pump(kLongPressTimeout + const Duration(milliseconds: 100));
    for (var i = 0; i < 10; i++) {
      await gesture.moveBy(Offset(0, -2 * rowHeight / 10));
      await tester.pump(const Duration(milliseconds: 50));
    }
    await gesture.up();
    await tester.pumpAndSettle();

    expect(listed(tester), ['Work', 'Send', 'Draft', 'Review']);
    final saved = GoalTree(await repository.goals());
    expect(waitsFor(saved['Send']!), ['Work']);
    expect(waitsFor(saved['Draft']!), ['Send']);
    expect(waitsFor(saved['Review']!), ['Draft']);
  });
}
