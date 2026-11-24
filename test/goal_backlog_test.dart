import 'package:flutter/gestures.dart' show kLongPressTimeout;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
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

  setUp(
    () => SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty(),
  );

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

  testWidgets('the queues come first, with every open goal; the status '
      'view is the other', (tester) async {
    await pump(tester, [
      ...queue,
      _goal('Alone', status: 'active', deadline: '2026-12-10'),
    ]);
    expect(listed(tester), ['Work', 'Draft', 'Review', 'Send', 'Alone']);
    expect(find.text('Active'), findsOneWidget);

    await tester.tap(find.byTooltip('Show the goal tree'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Show the queues'), findsOneWidget);
    expect(find.text('Active: the next starts as it closes'), findsNothing);
  });

  testWidgets('a search shows the queues with a goal it matches', (
    tester,
  ) async {
    await pump(tester, [
      ...queue,
      _goal('Alone', status: 'active', deadline: '2026-12-10'),
    ]);
    await tester.enterText(find.byType(TextField), 'review');
    await tester.pumpAndSettle();
    expect(listed(tester), ['Work', 'Draft', 'Review', 'Send']);

    await tester.enterText(find.byType(TextField), 'nothing like it');
    await tester.pumpAndSettle();
    expect(listed(tester), isEmpty);
    expect(find.text('Nothing matches “nothing like it”.'), findsOneWidget);
  });

  testWidgets('a queue folds to its first line, and stays folded when '
      'shown again', (tester) async {
    await pump(tester, queue);
    await tester.tap(find.text('Active: the next starts as it closes'));
    await tester.pumpAndSettle();
    expect(listed(tester), isEmpty);
    expect(find.text('4 goals'), findsOneWidget);

    // As when the app's opened again.
    await tester.pumpWidget(const SizedBox());
    await pump(tester, queue);
    expect(listed(tester), isEmpty);
    await tester.tap(find.text('Active: the next starts as it closes'));
    await tester.pumpAndSettle();
    expect(listed(tester), ['Work', 'Draft', 'Review', 'Send']);
  });

  testWidgets('a queue waiting to start says when it is expected to', (
    tester,
  ) async {
    await pump(tester, [
      Goal.fromJson({
        'id': 'Dated',
        'title': 'Dated',
        'status': 'inactive',
        'deadline': '2026-12-31',
        'activate_when': {
          'after': [
            {'at': '2026-12-08'},
          ],
        },
        'history': [
          {'status': 'inactive', 'at': '2026-11-01T09:00:00'},
        ],
      }),
    ]);
    expect(find.text('Waiting to start · expected Tue, Dec 8'), findsOneWidget);
  });
}
