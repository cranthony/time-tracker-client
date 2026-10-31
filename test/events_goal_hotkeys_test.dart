import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:time_tracker_client/models/goal.dart';
import 'package:time_tracker_client/screens/events_screen.dart';
import 'package:time_tracker_client/services/app_settings.dart';
import 'package:time_tracker_client/services/events_repository.dart';
import 'package:time_tracker_client/services/goals_repository.dart';
import 'package:time_tracker_client/services/plan_memory.dart';
import 'package:time_tracker_client/widgets/hotkeys.dart';

Goal _goal(String id, String title, String deadline) =>
    Goal(id: id, title: title, deadline: deadline);

void main() {
  final now = DateTime(2026, 9, 30, 12, 30);
  final goals = [
    _goal('report', 'Send the report', '2026-09-30'),
    _goal('call', 'Call the bank', '2026-09-30'),
    _goal('taxes', 'File taxes', '2026-09-27'),
    _goal('trip', 'Book the trip', '2026-10-05'),
    _goal('gift', 'Buy a gift', '2026-10-08'),
  ];

  late Hotkeys hotkeys;

  Future<void> open(WidgetTester tester, {List<Goal>? shown}) async {
    tester.view.physicalSize = const Size(1000, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    hotkeys = Hotkeys();
    final memory = PlanMemory()..goals = shown ?? goals;
    await tester.pumpWidget(
      PlanMemoryScope(
        memory: memory,
        child: GoalsScope(
          repository: InMemoryGoalsRepository(shown ?? goals),
          child: MaterialApp(
            navigatorObservers: [hotkeys],
            builder: (context, child) =>
                HotkeyScope(hotkeys: hotkeys, child: child!),
            home: AppSettingsScope(
              settings: AppSettings(persist: false),
              child: EventsScreen(
                repository: InMemoryEventsRepository(const []),
                serverLabel: 'offline demo',
                clock: () => now,
                memory: memory,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> press(WidgetTester tester, LogicalKeyboardKey key) async {
    await tester.sendKeyEvent(key);
    await tester.pumpAndSettle();
  }

  Future<void> shiftTab(WidgetTester tester) async {
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pumpAndSettle();
  }

  /// The title of the goal whose pill has focus, if one has.
  String? focused(WidgetTester tester) {
    final focus = FocusManager.instance.primaryFocus;
    final context = focus?.context;
    if (context == null ||
        !focus!.ancestors.any((n) => n.debugLabel == 'Goals strip')) {
      return null;
    }
    for (final g in goals) {
      final inIt = find.descendant(
        of: find.byElementPredicate((e) => e == context),
        matching: find.textContaining(g.title),
      );
      if (inIt.evaluate().isNotEmpty) return g.title;
    }
    return null;
  }

  testWidgets("G, O and U go to the day's, overdue and upcoming goals", (
    tester,
  ) async {
    await open(tester);
    await press(tester, LogicalKeyboardKey.keyG);
    expect(focused(tester), 'Call the bank');
    await press(tester, LogicalKeyboardKey.keyO);
    expect(focused(tester), 'File taxes');
    await press(tester, LogicalKeyboardKey.keyU);
    expect(focused(tester), 'Book the trip');
  });

  testWidgets('Tab and Shift+Tab go round the goals, not out of them', (
    tester,
  ) async {
    await open(tester);
    await press(tester, LogicalKeyboardKey.keyG);
    await press(tester, LogicalKeyboardKey.tab);
    expect(focused(tester), 'Send the report');
    await press(tester, LogicalKeyboardKey.tab);
    expect(focused(tester), 'File taxes');
    await press(tester, LogicalKeyboardKey.tab);
    await press(tester, LogicalKeyboardKey.tab);
    expect(focused(tester), 'Buy a gift');
    // Past the last, round to the first.
    await press(tester, LogicalKeyboardKey.tab);
    expect(focused(tester), 'Call the bank');
    await shiftTab(tester);
    expect(focused(tester), 'Buy a gift');
  });

  testWidgets('Esc leaves the goals', (tester) async {
    await open(tester);
    await press(tester, LogicalKeyboardKey.keyU);
    expect(focused(tester), 'Book the trip');
    await press(tester, LogicalKeyboardKey.escape);
    expect(focused(tester), isNull);
  });

  testWidgets('Enter on a goal opens it, not the event highlighted', (
    tester,
  ) async {
    await open(tester);
    await press(tester, LogicalKeyboardKey.keyO);
    await press(tester, LogicalKeyboardKey.enter);
    expect(hotkeys.pageOpen, isTrue);
  });

  testWidgets('G with the strip collapsed shows it first', (tester) async {
    await open(tester);
    await tester.tap(find.byTooltip('Hide goals due'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Show goals due'), findsOneWidget);
    await press(tester, LogicalKeyboardKey.keyG);
    expect(find.byTooltip('Hide goals due'), findsOneWidget);
    expect(focused(tester), 'Call the bank');
  });

  testWidgets('O with none overdue says so', (tester) async {
    await open(tester, shown: goals.where((g) => g.id != 'taxes').toList());
    await press(tester, LogicalKeyboardKey.keyO);
    expect(find.text('No goals overdue'), findsOneWidget);
    await tester.pump(const Duration(seconds: 4));
  });
}
