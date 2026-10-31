// A goal's page names its parent, tapped to open its page, with Move to
// put it under another goal or at the top level; a top-level goal's
// says so, with a way to put it under one.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:time_tracker_client/models/goal.dart';
import 'package:time_tracker_client/screens/goal_screen.dart';
import 'package:time_tracker_client/services/goals_repository.dart';
import 'package:time_tracker_client/services/plan_memory.dart';
import 'package:time_tracker_client/widgets/goal_fields.dart';
import 'package:time_tracker_client/widgets/goal_tile.dart';
import 'package:time_tracker_client/widgets/hotkeys.dart';

Goal _goal(String id, String title, {String? parentId}) => Goal.fromJson({
  'id': id,
  'title': title,
  'status': 'active',
  'parent_id': ?parentId,
  'history': [
    {'status': 'active', 'at': '2026-10-01T09:00:00'},
  ],
});

void main() {
  late PlanMemory memory;

  Future<void> pump(
    WidgetTester tester,
    String goalId, {
    bool hotkeys = false,
  }) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final goals = InMemoryGoalsRepository([
      _goal('house', 'Buy a house'),
      _goal('save', 'Save the deposit', parentId: 'house'),
      _goal('bank', 'Open a savings account', parentId: 'save'),
      _goal('fit', 'Get fit'),
    ], () => DateTime(2026, 10, 30, 9));
    memory = PlanMemory();
    await memory.loadGoals(goals);
    final keys = Hotkeys();
    await tester.pumpWidget(
      MaterialApp(
        navigatorObservers: [if (hotkeys) keys],
        builder: hotkeys
            ? (context, child) => HotkeyScope(hotkeys: keys, child: child!)
            : null,
        home: GoalScreen(goalId: goalId, repository: goals, memory: memory),
      ),
    );
    await tester.pumpAndSettle();
  }

  Finder parentField() => find.widgetWithText(GoalField, 'Parent');

  testWidgets('names its parent, tapped to open its page', (tester) async {
    await pump(tester, 'save');
    final chip = find.descendant(
      of: parentField(),
      matching: find.widgetWithText(ActionChip, 'Buy a house'),
    );
    expect(chip, findsOneWidget);
    await tester.tap(chip);
    await tester.pumpAndSettle();
    final pages = tester.widgetList<GoalScreen>(find.byType(GoalScreen));
    expect(pages.last.goalId, 'house');
  });

  testWidgets('Move puts it under another goal', (tester) async {
    await pump(tester, 'save');
    await tester.tap(
      find.descendant(of: parentField(), matching: find.text('Move…')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ListTile, 'Get fit'));
    await tester.pumpAndSettle();
    expect(memory.goals!.firstWhere((g) => g.id == 'save').parentId, 'fit');
    expect(
      find.descendant(
        of: parentField(),
        matching: find.widgetWithText(ActionChip, 'Get fit'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('Move puts it at the top level', (tester) async {
    await pump(tester, 'save');
    await tester.tap(
      find.descendant(of: parentField(), matching: find.text('Move…')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('To the top level'));
    await tester.pumpAndSettle();
    expect(memory.goals!.firstWhere((g) => g.id == 'save').parentId, isNull);
    expect(
      find.descendant(
        of: parentField(),
        matching: find.text('None: at the top level'),
      ),
      findsOneWidget,
    );
  });

  testWidgets("a top-level goal's can be put under one", (tester) async {
    await pump(tester, 'fit');
    expect(
      find.descendant(of: parentField(), matching: find.byType(ActionChip)),
      findsNothing,
    );
    await tester.tap(
      find.descendant(
        of: parentField(),
        matching: find.text('Put it under a goal…'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ListTile, 'Buy a house'));
    await tester.pumpAndSettle();
    expect(memory.goals!.firstWhere((g) => g.id == 'fit').parentId, 'house');
  });

  testWidgets('Tab reaches it; J and K pass it by', (tester) async {
    await pump(tester, 'save', hotkeys: true);
    T? focused<T extends Widget>() => FocusManager
        .instance
        .primaryFocus
        ?.context
        ?.findAncestorWidgetOfExactType<T>();
    bool onParent() =>
        (focused<ActionChip>()?.label as Text?)?.data == 'Buy a house';

    await tester.sendKeyEvent(LogicalKeyboardKey.keyJ);
    await tester.pumpAndSettle();
    expect(focused<GoalTile>()?.goal.id, 'bank');
    expect(onParent(), isFalse);

    for (var tabs = 0; !onParent(); tabs++) {
      expect(tabs, lessThan(40), reason: 'Tab never got to it');
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();
    }
  });
}
