import 'package:flutter/gestures.dart' show kLongPressTimeout;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:time_tracker_client/models/goal.dart';
import 'package:time_tracker_client/screens/goals_pane.dart';
import 'package:time_tracker_client/services/goals_repository.dart';
import 'package:time_tracker_client/services/plan_memory.dart';
import 'package:time_tracker_client/widgets/goal_tile.dart';

Goal _goal(
  String id,
  String title,
  String deadline, {
  int? priority,
  String? parent,
}) => Goal.fromJson({
  'id': id,
  'title': title,
  'parent_id': parent,
  'status': 'active',
  'deadline': deadline,
  'priority': priority,
  'history': [
    {'status': 'active', 'at': '2026-10-01T09:00:00'},
  ],
});

void main() {
  late InMemoryGoalsRepository repository;

  Future<void> pump(WidgetTester tester, [List<Goal>? goals]) async {
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    repository = InMemoryGoalsRepository(
      goals ??
          [
            _goal('top', 'Top', '2026-12-05', priority: 0),
            _goal('a', 'Alpha', '2026-12-01'),
            _goal('b', 'Beta', '2026-12-01T09:00'),
          ],
      () => DateTime(2026, 10, 17, 9),
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

  /// Holds [title]'s tile, then drags it [by] rows (up, if less than 0),
  /// leaving it held.
  Future<TestGesture> drag(WidgetTester tester, String title, int by) async {
    final rowHeight = tester.getSize(find.byType(GoalTile).first).height;
    final gesture = await tester.startGesture(
      tester.getCenter(find.text(title)),
    );
    await tester.pump(kLongPressTimeout + const Duration(milliseconds: 100));
    for (var i = 0; i < 10; i++) {
      await gesture.moveBy(Offset(0, by * rowHeight / 10));
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.pump(const Duration(milliseconds: 300));
    return gesture;
  }

  testWidgets('a goal held and dragged among those listed alike stays where '
      "it's dropped, its order saved", (tester) async {
    await pump(tester);
    // The day's timed one first, with no order of their own.
    expect(listed(tester), ['Top', 'Beta', 'Alpha']);

    final gesture = await drag(tester, 'Alpha', -1);
    expect(find.textContaining("can't go"), findsNothing);
    await gesture.up();
    await tester.pumpAndSettle();

    expect(listed(tester), ['Top', 'Alpha', 'Beta']);
    final saved = {for (final g in await repository.goals()) g.id: g};
    expect(saved['a']!.sortOrder, 1000);
    expect(saved['b']!.sortOrder, isNull);
  });

  testWidgets('dragged above a higher-priority goal, it says it can\'t go '
      'there, and is dropped below it', (tester) async {
    await pump(tester);

    final gesture = await drag(tester, 'Alpha', -2);
    expect(
      find.text("It can't go above a higher-priority goal."),
      findsOneWidget,
    );
    await gesture.up();
    await tester.pumpAndSettle();

    expect(find.textContaining("can't go"), findsNothing);
    expect(listed(tester), ['Top', 'Alpha', 'Beta']);
  });

  final tree = [
    _goal('a', 'Alpha', '2026-12-01'),
    _goal('b', 'Beta', '2026-12-01T09:00'),
    _goal('b1', 'Bee one', '2026-12-01', parent: 'b'),
    _goal('b2', 'Bee two', '2026-12-01T08:00', parent: 'b'),
  ];

  testWidgets('a goal dragged above another goal beside it goes above it, '
      "what's under that one too", (tester) async {
    await pump(tester, tree);
    expect(listed(tester), ['Beta', 'Bee two', 'Bee one', 'Alpha']);

    final gesture = await drag(tester, 'Alpha', -3);
    await gesture.up();
    await tester.pumpAndSettle();

    expect(listed(tester), ['Alpha', 'Beta', 'Bee two', 'Bee one']);
    final saved = {for (final g in await repository.goals()) g.id: g};
    expect(saved['a']!.sortOrder, 1000);
  });

  testWidgets("a goal dropped among another's sub-goals stays where it was", (
    tester,
  ) async {
    await pump(tester, tree);

    final gesture = await drag(tester, 'Alpha', -1);
    await gesture.up();
    await tester.pumpAndSettle();

    expect(listed(tester), ['Beta', 'Bee two', 'Bee one', 'Alpha']);
    final saved = {for (final g in await repository.goals()) g.id: g};
    expect(saved['a']!.sortOrder, isNull);
  });

  testWidgets('a sub-goal is dragged among those beside it', (tester) async {
    await pump(tester, tree);

    final gesture = await drag(tester, 'Bee one', -1);
    await gesture.up();
    await tester.pumpAndSettle();

    expect(listed(tester), ['Beta', 'Bee one', 'Bee two', 'Alpha']);
  });
}
