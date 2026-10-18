import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:time_tracker_client/models/event.dart';
import 'package:time_tracker_client/models/goal.dart';
import 'package:time_tracker_client/outbox/action_writes.dart';
import 'package:time_tracker_client/outbox/note_writes.dart';
import 'package:time_tracker_client/screens/events_screen.dart';
import 'package:time_tracker_client/screens/notes_screen.dart';
import 'package:time_tracker_client/screens/plan_screen.dart';
import 'package:time_tracker_client/services/actions_repository.dart';
import 'package:time_tracker_client/services/app_settings.dart';
import 'package:time_tracker_client/services/events_repository.dart';
import 'package:time_tracker_client/services/goals_repository.dart';
import 'package:time_tracker_client/services/notes_repository.dart';
import 'package:time_tracker_client/widgets/goal_editor.dart';
import 'package:time_tracker_client/widgets/hotkeys.dart';
import 'package:time_tracker_client/widgets/pending_event_box.dart';

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

  /// +, as typed: Shift and = on most keyboards.
  Future<void> plus(WidgetTester tester) async {
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.equal, character: '+');
    await tester.sendKeyUpEvent(LogicalKeyboardKey.equal);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pumpAndSettle();
  }

  /// What the hints say while Ctrl is held.
  Future<List<String>> hints(WidgetTester tester) async {
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump(const Duration(milliseconds: 400));
    final shown = [
      for (final badge in tester.widgetList<HotkeyBadge>(
        find.byType(HotkeyBadge),
      ))
        badge.label,
    ];
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    return shown;
  }

  Goal goal(String id, String title) => Goal.fromJson({
    'id': id,
    'title': title,
    'status': 'active',
    'history': [
      {'status': 'active', 'at': '2026-10-01T09:00:00'},
    ],
  });

  Future<void> pumpPlan(WidgetTester tester) async {
    final repo = InMemoryActionsRepository();
    await tester.pumpWidget(
      withHotkeys(
        GoalsScope(
          repository: InMemoryGoalsRepository([
            goal('ship', 'Ship the app'),
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
  }

  testWidgets('+ on the Goals pane makes a goal; on a goal, a sub-goal', (
    tester,
  ) async {
    await pumpPlan(tester);
    expect(await hints(tester), contains('+'));

    await plus(tester);
    expect(find.byType(GoalEditorPage), findsOneWidget);
    expect(
      tester.widget<GoalEditorPage>(find.byType(GoalEditorPage)).parent,
      isNull,
    );
    tester.state<NavigatorState>(find.byType(Navigator).first).pop();
    await tester.pumpAndSettle();

    await tester.tap(find.text('Ship the app'));
    await tester.pumpAndSettle();
    await plus(tester);
    expect(
      tester.widget<GoalEditorPage>(find.byType(GoalEditorPage)).parent?.id,
      'ship',
    );
  });

  testWidgets('+ on the Actions pane offers a new action or group', (
    tester,
  ) async {
    await pumpPlan(tester);
    await tester.tap(find.text('Actions'));
    await tester.pumpAndSettle();
    await plus(tester);
    expect(find.text('New action'), findsOneWidget);
    expect(find.text('New group'), findsOneWidget);
  });

  testWidgets('+ on the Events page does what C does, and the hint on its '
      '+ says both', (tester) async {
    final now = DateTime(2026, 9, 30, 12, 30);
    await tester.pumpWidget(
      withHotkeys(
        AppSettingsScope(
          // A grid of an hour, and no other stops, as for C's own test.
          settings: AppSettings(persist: false, grid: const Duration(hours: 1))
            ..setSnap(const {}),
          child: EventsScreen(
            repository: InMemoryEventsRepository([
              Event(
                id: 'lunch',
                start: DateTime(2026, 9, 30, 12),
                end: DateTime(2026, 9, 30, 13),
                summary: 'Lunch',
              ),
            ]),
            serverLabel: 'offline demo',
            clock: () => now,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(await hints(tester), contains('C / +'));

    await plus(tester);
    expect(find.byType(PendingEventBoxView), findsOneWidget);
  });

  testWidgets('+ on the Notes page adds a note, and the hint on its + says '
      'Ctrl+M too', (tester) async {
    final repo = InMemoryNotesRepository();
    await tester.pumpWidget(
      withHotkeys(
        NotesScreen(
          repository: repo,
          outbox: NoteWrites.local(repo)..start(),
          clock: () => DateTime(2026, 9, 30, 12, 30),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(await hints(tester), contains('Ctrl+M / +'));

    await plus(tester);
    expect(find.text('New note'), findsOneWidget);
  });

  testWidgets('the list of hotkeys gives both keys for what has two', (
    tester,
  ) async {
    await tester.pumpWidget(withHotkeys(const Scaffold()));
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.slash, character: '?');
    await tester.sendKeyUpEvent(LogicalKeyboardKey.slash);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pumpAndSettle();
    final keys = [
      for (final badge in tester.widgetList<HotkeyBadge>(
        find.byType(HotkeyBadge),
      ))
        badge.label,
    ];
    expect(keys, containsAll(['C / +', 'Ctrl+M / +', '+']));
  });
}
