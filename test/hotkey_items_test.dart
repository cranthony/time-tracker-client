import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:time_tracker_client/models/goal.dart';
import 'package:time_tracker_client/models/plan_action.dart';
import 'package:time_tracker_client/outbox/action_writes.dart';
import 'package:time_tracker_client/screens/goal_screen.dart';
import 'package:time_tracker_client/screens/plan_screen.dart';
import 'package:time_tracker_client/services/actions_repository.dart';
import 'package:time_tracker_client/services/events_repository.dart';
import 'package:time_tracker_client/services/goals_repository.dart';
import 'package:time_tracker_client/services/mcp_client.dart';
import 'package:time_tracker_client/services/notes_repository.dart';
import 'package:time_tracker_client/services/plan_memory.dart';
import 'package:time_tracker_client/widgets/goal_tile.dart';
import 'package:time_tracker_client/widgets/hotkeys.dart';
import 'package:time_tracker_client/widgets/status_message.dart';

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

  /// What the button highlighted says.
  String? highlighted() {
    final context = FocusManager.instance.primaryFocus?.context;
    final button = context?.findAncestorWidgetOfExactType<TextButton>();
    return (button?.child as Text?)?.data;
  }

  group('J and K, elsewhere', () {
    final list = ScrollController();
    const row = 50.0;

    /// A button over a list of 40 items that scrolls, scrolled to
    /// [offset].
    Future<void> pump(WidgetTester tester, double offset) async {
      await tester.pumpWidget(
        withHotkeys(
          Scaffold(
            body: Column(
              children: [
                TextButton(onPressed: () {}, child: const Text('Header')),
                Expanded(
                  child: HotkeyItems(
                    child: ListView(
                      controller: list,
                      itemExtent: row,
                      children: [
                        for (var i = 0; i < 40; i++)
                          TextButton(onPressed: () {}, child: Text('Item $i')),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      list.jumpTo(offset);
      await tester.pumpAndSettle();
    }

    Rect rectOf(WidgetTester tester, String text) =>
        tester.getRect(find.widgetWithText(TextButton, text));

    testWidgets('J starts at the first of the list wholly in view', (
      tester,
    ) async {
      // Item 10 cut off at the top.
      await pump(tester, 10 * row + 20);
      await press(tester, LogicalKeyboardKey.keyJ);
      expect(highlighted(), 'Item 11');
      await press(tester, LogicalKeyboardKey.keyJ);
      expect(highlighted(), 'Item 12');
    });

    testWidgets('End highlights the last item, scrolled to; Home, the '
        'first', (tester) async {
      await pump(tester, 10 * row);
      await press(tester, LogicalKeyboardKey.end);
      expect(highlighted(), 'Item 39');
      final view = tester.getRect(find.byType(ListView));
      expect(rectOf(tester, 'Item 39').bottom, lessThanOrEqualTo(view.bottom));
      await press(tester, LogicalKeyboardKey.home);
      expect(highlighted(), 'Item 0');
      expect(rectOf(tester, 'Item 0').top, greaterThanOrEqualTo(view.top));
    });

    testWidgets('K starts at the last of the list wholly in view', (
      tester,
    ) async {
      await pump(tester, 10 * row + 20);
      await press(tester, LogicalKeyboardKey.keyK);
      final last = highlighted()!;
      final n = int.parse(last.split(' ').last);
      final view = tester.getRect(find.byType(ListView));
      expect(rectOf(tester, last).bottom, lessThanOrEqualTo(view.bottom));
      expect(rectOf(tester, 'Item ${n + 1}').bottom, greaterThan(view.bottom));
    });

    testWidgets('J, after what was highlighted is scrolled away, goes on '
        'from it, scrolling the next back into view', (tester) async {
      await pump(tester, 0);
      await press(tester, LogicalKeyboardKey.keyJ);
      expect(highlighted(), 'Item 0');
      list.jumpTo(20 * row);
      await tester.pumpAndSettle();
      await press(tester, LogicalKeyboardKey.keyJ);
      expect(highlighted(), 'Item 1');
      final view = tester.getRect(find.byType(ListView));
      final item = rectOf(tester, 'Item 1');
      expect(item.top, greaterThanOrEqualTo(view.top));
      expect(item.bottom, lessThanOrEqualTo(view.bottom));
    });
  });

  group('J and K, to a list not built yet', () {
    final page = ScrollController();

    /// A page that scrolls: [above], then -- with [items] -- a list of 3
    /// items, then [below]. Too far from the view to be built, at first,
    /// past a long description, say.
    Future<void> pump(
      WidgetTester tester, {
      double above = 3000,
      double below = 3000,
      bool items = true,
    }) async {
      await tester.pumpWidget(
        withHotkeys(
          Scaffold(
            body: ListView(
              controller: page,
              children: [
                SizedBox(height: above),
                if (items)
                  HotkeyItems(
                    child: Column(
                      children: [
                        for (var i = 0; i < 3; i++)
                          TextButton(onPressed: () {}, child: Text('Item $i')),
                      ],
                    ),
                  ),
                SizedBox(height: below),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    void expectInView(WidgetTester tester, String text) {
      final view = tester.getRect(find.byType(ListView));
      // What has focus: the button, inside its tap target.
      final item = FocusManager.instance.primaryFocus!.rect;
      expect(highlighted(), text);
      expect(item.top, greaterThanOrEqualTo(view.top));
      expect(item.bottom, lessThanOrEqualTo(view.bottom));
    }

    testWidgets('J scrolls down to the first of a list further down, and '
        'highlights it', (tester) async {
      await pump(tester);
      expect(find.text('Item 0'), findsNothing);
      await press(tester, LogicalKeyboardKey.keyJ);
      expect(highlighted(), 'Item 0');
      expectInView(tester, 'Item 0');
      await press(tester, LogicalKeyboardKey.keyJ);
      expect(highlighted(), 'Item 1');
    });

    testWidgets('K scrolls up to the last of a list further up', (
      tester,
    ) async {
      await pump(tester);
      page.jumpTo(page.position.maxScrollExtent);
      await tester.pumpAndSettle();
      expect(find.text('Item 2'), findsNothing);
      await press(tester, LogicalKeyboardKey.keyK);
      expect(highlighted(), 'Item 2');
      expectInView(tester, 'Item 2');
    });

    testWidgets("J, on a goal's page, scrolls past its long description to "
        'its first sub-goal', (tester) async {
      final repository = InMemoryGoalsRepository([
        Goal.fromJson({
          'id': 'ship',
          'title': 'Ship the app',
          'status': 'active',
          'description': List.filled(200, 'A line of it.').join('\n\n'),
        }),
        Goal.fromJson({
          'id': 'test',
          'title': 'Test it',
          'parent_id': 'ship',
          'status': 'active',
        }),
      ]);
      final memory = PlanMemory();
      await memory.loadGoals(repository);
      await tester.pumpWidget(
        withHotkeys(
          GoalScreen(goalId: 'ship', repository: repository, memory: memory),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(GoalTile), findsNothing);
      await press(tester, LogicalKeyboardKey.keyJ);
      final context = FocusManager.instance.primaryFocus!.context!;
      expect(
        context.findAncestorWidgetOfExactType<GoalTile>()?.goal.id,
        'test',
      );
      expect(inScrolledView(FocusManager.instance.primaryFocus!), isTrue);
    });

    testWidgets('J scrolls nothing where there is no list', (tester) async {
      await pump(tester, items: false);
      await press(tester, LogicalKeyboardKey.keyJ);
      expect(page.offset, 0);
    });

    testWidgets('J scrolls nothing for a list further up', (tester) async {
      await pump(tester);
      page.jumpTo(page.position.maxScrollExtent);
      await tester.pumpAndSettle();
      final at = page.offset;
      await press(tester, LogicalKeyboardKey.keyJ);
      expect(page.offset, at);
      expect(highlighted(), isNull);
    });
  });

  group('the Plan page', () {
    Goal goal(String id, String title) => Goal.fromJson({
      'id': id,
      'title': title,
      'status': 'active',
      'history': [
        {'status': 'active', 'at': '2026-10-01T09:00:00'},
      ],
    });

    /// The Plan page, with two goals; their titles, as listed.
    Future<List<String>> pump(WidgetTester tester) async {
      final repo = InMemoryActionsRepository();
      await tester.pumpWidget(
        withHotkeys(
          GoalsScope(
            repository: InMemoryGoalsRepository([
              goal('a', 'Ship the app'),
              goal('b', 'Learn Rust'),
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
      return [
        for (final tile in tester.widgetList<GoalTile>(find.byType(GoalTile)))
          tile.goal.title,
      ];
    }

    /// The goal highlighted: its row, not its edit button.
    String? goalHighlighted() {
      final context = FocusManager.instance.primaryFocus?.context;
      if (context?.findAncestorWidgetOfExactType<IconButton>() != null) {
        return null;
      }
      return context?.findAncestorWidgetOfExactType<GoalTile>()?.goal.title;
    }

    testWidgets('J highlights the first goal of the Goals pane, not a button '
        'over it', (tester) async {
      final titles = await pump(tester);
      await press(tester, LogicalKeyboardKey.keyJ);
      expect(goalHighlighted(), titles.first);
    });

    testWidgets('J and K go from goal to goal, not to their edit buttons', (
      tester,
    ) async {
      final titles = await pump(tester);
      await press(tester, LogicalKeyboardKey.keyJ);
      await press(tester, LogicalKeyboardKey.keyJ);
      expect(goalHighlighted(), titles[1]);
      await press(tester, LogicalKeyboardKey.keyK);
      expect(goalHighlighted(), titles[0]);
    });

    testWidgets('J on the Actions pane highlights the first action, not '
        'the Priority colors link over them', (tester) async {
      final repo = InMemoryActionsRepository([
        const PlanAction(id: 'cook', name: 'Cooking'),
        const PlanAction(id: 'host', name: 'Hosting'),
      ]);
      await tester.pumpWidget(
        withHotkeys(
          PlanScreen(
            repository: repo,
            outbox: ActionWrites.local(repo)..start(),
            serverLabel: 'offline demo',
            eventsRepository: InMemoryEventsRepository(const []),
            notesRepository: InMemoryNotesRepository(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Priority colors'), findsOneWidget);
      await press(tester, LogicalKeyboardKey.keyJ);
      final context = FocusManager.instance.primaryFocus!.context!;
      final tile = context.findAncestorWidgetOfExactType<ListTile>();
      final title = tile?.title as Text?;
      expect(title?.data ?? (title?.textSpan as TextSpan?)?.text, 'Cooking');
    });

    testWidgets('Home and End go to the first and last goal of the pane', (
      tester,
    ) async {
      final titles = await pump(tester);
      await press(tester, LogicalKeyboardKey.end);
      expect(goalHighlighted(), titles.last);
      await press(tester, LogicalKeyboardKey.home);
      expect(goalHighlighted(), titles.first);
    });

    testWidgets('K highlights the last goal, not its edit button', (
      tester,
    ) async {
      final titles = await pump(tester);
      await press(tester, LogicalKeyboardKey.keyK);
      expect(goalHighlighted(), titles.last);
    });
  });

  group('S', () {
    testWidgets('presses the Sign in button shown', (tester) async {
      var pressed = 0;
      await tester.pumpWidget(
        withHotkeys(
          Scaffold(
            body: SignInButton(signingIn: false, onPressed: () => pressed++),
          ),
        ),
      );
      await press(tester, LogicalKeyboardKey.keyS);
      expect(pressed, 1);
    });

    testWidgets('does nothing while signing in', (tester) async {
      var pressed = 0;
      await tester.pumpWidget(
        withHotkeys(
          Scaffold(
            body: SignInButton(signingIn: true, onPressed: () => pressed++),
          ),
        ),
      );
      await press(tester, LogicalKeyboardKey.keyS);
      expect(pressed, 0);
    });

    testWidgets('signs in on the Plan page', (tester) async {
      final repo = _SignedOut();
      var signedIn = false;
      await tester.pumpWidget(
        withHotkeys(
          PlanScreen(
            repository: repo,
            outbox: ActionWrites.local(repo)..start(),
            serverLabel: 'offline demo',
            onSignIn: () async => signedIn = repo.signedIn = true,
            eventsRepository: InMemoryEventsRepository(const []),
            notesRepository: InMemoryNotesRepository(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Sign in to see your plan.'), findsOneWidget);
      await press(tester, LogicalKeyboardKey.keyS);
      expect(signedIn, isTrue);
      expect(find.text('Sign in to see your plan.'), findsNothing);
    });
  });
}

/// No actions until signed in.
class _SignedOut extends InMemoryActionsRepository {
  bool signedIn = false;

  @override
  Future<ActionList> actions() async {
    if (!signedIn) throw SignInRequiredException();
    return super.actions();
  }
}
