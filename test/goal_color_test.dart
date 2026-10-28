// A goal's color: its own, its nearest parent's that has one, or its
// priority's -- where it shows and where it's set.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:time_tracker_client/models/goal.dart';
import 'package:time_tracker_client/screens/goal_screen.dart';
import 'package:time_tracker_client/services/goals_repository.dart';
import 'package:time_tracker_client/services/plan_memory.dart';
import 'package:time_tracker_client/widgets/color_picker.dart';
import 'package:time_tracker_client/widgets/goal_color.dart';
import 'package:time_tracker_client/widgets/goal_editor.dart';
import 'package:time_tracker_client/widgets/goals_due_strip.dart';

Goal _goal(
  String id, {
  String? parent,
  int? priority,
  String? color,
  String? effective,
  String deadline = '2026-12-01',
}) => Goal.fromJson({
  'id': id,
  'title': id,
  'parent_id': ?parent,
  'priority': ?priority,
  'background_color': ?color,
  'effective_color': ?effective,
  'status': 'active',
  'deadline': deadline,
});

final _goals = [
  _goal('top', color: '#123456'),
  _goal('mid', parent: 'top', deadline: '2026-11-20'),
  _goal('leaf', parent: 'mid', priority: 0, deadline: '2026-11-10'),
  _goal('own', parent: 'mid', color: '#654321', deadline: '2026-11-10'),
  _goal('plain', priority: 1),
];

void main() {
  final tree = GoalTree(_goals);
  final day = DateTime(2026, 10, 17);

  test("a goal's color is its own, or its nearest parent's that has one, "
      "or else its priority's; the server's says so too", () {
    expect(tree.colorSourceOf('top')?.id, 'top');
    expect(tree.colorSourceOf('mid')?.id, 'top');
    expect(tree.colorSourceOf('leaf')?.id, 'top');
    expect(tree.colorSourceOf('own')?.id, 'own');
    expect(tree.colorSourceOf('plain'), isNull);
    expect(tree.colorSourceOf('nosuch'), isNull);

    expect(colorOfGoal(tree['mid']!, tree: tree), const Color(0xFF123456));
    expect(colorOfGoal(tree['own']!, tree: tree), const Color(0xFF654321));
    expect(colorOfGoal(tree['plain']!, tree: tree), priorityColor(1));
    // Without the tree: as the server last said, else its own priority's.
    expect(
      colorOfGoal(_goal('listed', effective: '#abcdef')),
      const Color(0xFFABCDEF),
    );
    expect(colorOfGoal(_goal('listed', priority: 2)), priorityColor(2));
    expect(colorOfGoal(_goal('listed')), priorityColor(defaultGoalPriority));
  });

  test('its own color goes to the server; the one it shows never does', () {
    final goal = _goal('mid', parent: 'top', effective: '#123456');
    expect(goal.toJson()['effective_color'], '#123456');
    expect(goalWire(goal.toJson()).containsKey('effective_color'), isFalse);
    expect(goalWire({'background_color': '#654321'}), {
      'background_color': '#654321',
    });
    expect(goalWire({'background_color': null}), {'background_color': null});
  });

  Future<void> pumpPage(WidgetTester tester, String id) async {
    final goals = InMemoryGoalsRepository(_goals);
    final memory = PlanMemory();
    await memory.loadGoals(goals);
    await tester.pumpWidget(
      MaterialApp(
        home: GoalScreen(goalId: id, repository: goals, memory: memory),
      ),
    );
    await tester.pumpAndSettle();
  }

  Color dot(WidgetTester tester) =>
      tester.widget<ColorDot>(find.byType(ColorDot)).color;

  testWidgets("a goal's page shows its color and where it comes from", (
    tester,
  ) async {
    await pumpPage(tester, 'leaf');
    expect(find.text('Color'), findsOneWidget);
    expect(find.text('From top'), findsOneWidget);
    expect(dot(tester), const Color(0xFF123456));

    await pumpPage(tester, 'own');
    expect(find.text('Its own'), findsOneWidget);
    expect(dot(tester), const Color(0xFF654321));

    await pumpPage(tester, 'plain');
    expect(find.text("Its priority's (P1)"), findsOneWidget);
    expect(dot(tester), priorityColor(1));
  });

  testWidgets("the due strip's pills are filled in it", (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: GoalsDueStrip(
            goals: [tree['mid']!, tree['plain']!],
            tree: tree,
            upcoming: const [],
            day: day,
            today: day,
            collapsed: false,
            onCollapsed: (_) {},
            onTap: (_) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    Material pillOf(String text) => tester.widget<Material>(
      find
          .ancestor(
            of: find.textContaining(text),
            matching: find.byType(Material),
          )
          .first,
    );
    expect(pillOf('mid').color, const Color(0xFF123456));
    expect(pillOf('plain').color, priorityColor(1));
  });

  /// Opens [goal]'s editor; what it gives on saving lands in [saved].
  Future<void> pumpEditor(
    WidgetTester tester,
    Goal goal,
    List<Map<String, Object?>?> saved,
  ) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async => saved.add(
                await showGoalEditor(
                  context,
                  goal: goal,
                  goals: _goals,
                  now: () => DateTime(2026, 10, 17, 9),
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  final hexField = find.byWidgetPredicate(
    (w) => w is TextField && w.decoration?.hintText == 'No color',
  );

  Future<void> save(WidgetTester tester) async {
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
  }

  testWidgets("the editor's Color field says what a goal with none takes, "
      'and a color typed there is the change saved', (tester) async {
    final saved = <Map<String, Object?>?>[];
    await pumpEditor(tester, tree['mid']!, saved);
    expect(find.text("With none, it takes top's."), findsOneWidget);

    await tester.enterText(hexField, '#abcdef');
    await tester.pumpAndSettle();
    expect(find.text("With none, it takes top's."), findsNothing);
    await save(tester);
    expect(saved, [
      {'background_color': '#abcdef'},
    ]);
  });

  testWidgets("a goal with none up its tree takes its priority's; clearing "
      'its own is a change too', (tester) async {
    final saved = <Map<String, Object?>?>[];
    await pumpEditor(tester, tree['own']!, saved);
    expect(find.textContaining('With none'), findsNothing);

    await tester.enterText(hexField, '');
    await tester.pumpAndSettle();
    expect(find.text("With none, it takes top's."), findsOneWidget);
    await save(tester);
    expect(saved, [
      {'background_color': null},
    ]);

    await pumpEditor(tester, tree['plain']!, saved);
    expect(
      find.text("With none, it takes its priority's (P1)."),
      findsOneWidget,
    );
  });
}
