import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:time_tracker_client/models/goal.dart';
import 'package:time_tracker_client/outbox/action_writes.dart';
import 'package:time_tracker_client/screens/goal_screen.dart';
import 'package:time_tracker_client/screens/plan_screen.dart';
import 'package:time_tracker_client/services/actions_repository.dart';
import 'package:time_tracker_client/services/events_repository.dart';
import 'package:time_tracker_client/services/goals_repository.dart';
import 'package:time_tracker_client/services/notes_repository.dart';
import 'package:time_tracker_client/widgets/goal_editor.dart';
import 'package:time_tracker_client/widgets/goal_tile.dart';
import 'package:time_tracker_client/widgets/hotkeys.dart';

void main() {
  late Hotkeys hotkeys;

  Widget withHotkeys(Widget home) {
    hotkeys = Hotkeys();
    return MaterialApp(
      navigatorObservers: [hotkeys],
      builder: (context, child) => HotkeyScope(hotkeys: hotkeys, child: child!),
      home: home,
    );
  }

  Future<void> press(WidgetTester tester, LogicalKeyboardKey key) async {
    await tester.sendKeyEvent(key);
    await tester.pumpAndSettle();
  }

  Goal goal(String id, String title, {String? parent}) => Goal.fromJson({
    'id': id,
    'title': title,
    'parent_id': parent,
    'status': 'active',
    'deadline': '2026-12-01',
    'history': [
      {'status': 'active', 'at': '2026-10-01T09:00:00'},
    ],
  });

  /// A goal's page, with two sub-goals.
  Future<void> pumpGoal(WidgetTester tester) async {
    // Tall enough for the page's fields and its sub-goals under them.
    tester.view.physicalSize = const Size(800, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final repo = InMemoryActionsRepository();
    await tester.pumpWidget(
      withHotkeys(
        GoalsScope(
          repository: InMemoryGoalsRepository([
            goal('ship', 'Ship the app'),
            goal('pane', 'Write the pane', parent: 'ship'),
            goal('icon', 'Draw the icon', parent: 'ship'),
          ], () => DateTime(2026, 10, 17, 9)),
          child: PlanScreen(
            repository: repo,
            outbox: ActionWrites.local(repo)..start(),
            serverLabel: 'offline demo',
            eventsRepository: InMemoryEventsRepository(const []),
            notesRepository: InMemoryNotesRepository(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ship the app'));
    await tester.pumpAndSettle();
    expect(find.byType(GoalScreen), findsOneWidget);
  }

  /// The sub-goal highlighted: its row, not a button in it.
  String? highlighted() {
    final context = FocusManager.instance.primaryFocus?.context;
    if (context?.findAncestorWidgetOfExactType<IconButton>() != null) {
      return null;
    }
    return context?.findAncestorWidgetOfExactType<GoalTile>()?.goal.title;
  }

  testWidgets("J and K go from sub-goal to sub-goal on a goal's page, not "
      'to the buttons over them or the history under them', (tester) async {
    await pumpGoal(tester);
    final titles = [
      for (final tile in tester.widgetList<GoalTile>(
        find.descendant(
          of: find.byType(GoalScreen),
          matching: find.byType(GoalTile),
        ),
      ))
        tile.goal.title,
    ];
    expect(titles, hasLength(2));

    await press(tester, LogicalKeyboardKey.keyJ);
    expect(highlighted(), titles[0]);
    await press(tester, LogicalKeyboardKey.keyJ);
    expect(highlighted(), titles[1]);
    await press(tester, LogicalKeyboardKey.keyJ);
    expect(highlighted(), titles[1]);
    await press(tester, LogicalKeyboardKey.keyK);
    expect(highlighted(), titles[0]);
  });

  testWidgets("Home and End go to a goal's first and last sub-goal", (
    tester,
  ) async {
    await pumpGoal(tester);
    final titles = [
      for (final tile in tester.widgetList<GoalTile>(
        find.descendant(
          of: find.byType(GoalScreen),
          matching: find.byType(GoalTile),
        ),
      ))
        tile.goal.title,
    ];
    await press(tester, LogicalKeyboardKey.end);
    expect(highlighted(), titles.last);
    await press(tester, LogicalKeyboardKey.home);
    expect(highlighted(), titles.first);
  });

  /// The status on the goal's page that's on top.
  String status(WidgetTester tester) => tester
      .widget<Text>(
        find.descendant(
          of: find.descendant(
            of: find.byType(GoalScreen).last,
            matching: find.byType(Chip),
          ),
          matching: find.byType(Text),
        ),
      )
      .data!;

  /// The page of a sub-goal of [pumpGoal]'s, with none under it.
  Future<void> pumpSubGoal(WidgetTester tester) async {
    await pumpGoal(tester);
    await tester.tap(find.text('Write the pane'));
    await tester.pumpAndSettle();
    expect(status(tester), 'Active');
  }

  testWidgets("D on a goal's page marks it done", (tester) async {
    await pumpSubGoal(tester);
    await press(tester, LogicalKeyboardKey.keyD);
    expect(status(tester), 'Done');
    // Done, it can't be again.
    await press(tester, LogicalKeyboardKey.keyD);
    expect(status(tester), 'Done');
  });

  testWidgets("M on a goal's page marks it missed", (tester) async {
    await pumpSubGoal(tester);
    await press(tester, LogicalKeyboardKey.keyM);
    expect(status(tester), 'Missed');
  });

  testWidgets("T on a goal's page marks it missed to try again, by a day "
      'picked', (tester) async {
    await pumpSubGoal(tester);
    await press(tester, LogicalKeyboardKey.keyT);
    expect(find.text('Try again by'), findsOneWidget);
  });

  testWidgets("E on a goal's page edits it", (tester) async {
    await pumpGoal(tester);
    await press(tester, LogicalKeyboardKey.keyE);
    final editor = tester.widget<GoalEditorPage>(find.byType(GoalEditorPage));
    expect(editor.goal?.id, 'ship');
  });

  testWidgets("U goes up a level: from a goal's editor to its page, and "
      'from there to the Plan page', (tester) async {
    await pumpGoal(tester);
    await press(tester, LogicalKeyboardKey.keyE);
    expect(find.byType(GoalEditorPage), findsOneWidget);

    await press(tester, LogicalKeyboardKey.keyU);
    expect(find.byType(GoalEditorPage), findsNothing);
    expect(find.byType(GoalScreen), findsOneWidget);

    await press(tester, LogicalKeyboardKey.keyU);
    expect(find.byType(GoalScreen), findsNothing);
    expect(find.byType(PlanScreen), findsOneWidget);

    // Nothing over the first page: nothing to go up from.
    await press(tester, LogicalKeyboardKey.keyU);
    expect(find.byType(PlanScreen), findsOneWidget);
  });

  testWidgets('Esc goes up a level as U does', (tester) async {
    await pumpGoal(tester);
    await press(tester, LogicalKeyboardKey.keyE);
    await press(tester, LogicalKeyboardKey.escape);
    expect(find.byType(GoalEditorPage), findsNothing);
    expect(find.byType(GoalScreen), findsOneWidget);

    await press(tester, LogicalKeyboardKey.escape);
    expect(find.byType(GoalScreen), findsNothing);
    expect(find.byType(PlanScreen), findsOneWidget);
  });

  testWidgets('Enter presses nothing in a pane swiped away from', (
    tester,
  ) async {
    await pumpGoal(tester);
    await press(tester, LogicalKeyboardKey.keyU);
    // A goal highlighted on the Goals pane, then off to the Actions pane.
    await press(tester, LogicalKeyboardKey.keyJ);
    expect(
      FocusManager.instance.primaryFocus?.context
          ?.findAncestorWidgetOfExactType<GoalTile>(),
      isNotNull,
    );
    await press(tester, LogicalKeyboardKey.keyA);
    await press(tester, LogicalKeyboardKey.enter);
    expect(find.byType(GoalScreen), findsNothing);
  });

  testWidgets('J and K do nothing in a dialog with no list; Tab goes on', (
    tester,
  ) async {
    await tester.pumpWidget(withHotkeys(const Scaffold()));
    final context = tester.element(find.byType(Scaffold));
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        content: const Text('Sure?'),
        actions: [
          TextButton(onPressed: () {}, child: const Text('No')),
          TextButton(onPressed: () {}, child: const Text('Yes')),
        ],
      ),
    );
    await tester.pumpAndSettle();
    final before = FocusManager.instance.primaryFocus;
    await press(tester, LogicalKeyboardKey.keyJ);
    expect(FocusManager.instance.primaryFocus, before);
    await press(tester, LogicalKeyboardKey.tab);
    expect(FocusManager.instance.primaryFocus, isNot(before));
  });
}
