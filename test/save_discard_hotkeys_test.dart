import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:time_tracker_client/models/event.dart';
import 'package:time_tracker_client/widgets/tree_picker.dart';
import 'package:time_tracker_client/widgets/share_dialog.dart';
import 'package:time_tracker_client/models/share.dart';
import 'package:time_tracker_client/outbox/action_writes.dart';
import 'package:time_tracker_client/outbox/note_writes.dart';
import 'package:time_tracker_client/screens/home_screen.dart';
import 'package:time_tracker_client/services/actions_repository.dart';
import 'package:time_tracker_client/services/events_repository.dart';
import 'package:time_tracker_client/services/notes_repository.dart';
import 'package:time_tracker_client/services/people_repository.dart';
import 'package:time_tracker_client/widgets/event_summary_dialog.dart';
import 'package:time_tracker_client/widgets/hotkeys.dart';
import 'package:time_tracker_client/widgets/picker_sheet.dart';

void main() {
  late Hotkeys hotkeys;

  /// An app with hotkeys, its home [home].
  Widget app(Widget home) {
    hotkeys = Hotkeys();
    return PeopleScope(
      repository: InMemoryPeopleRepository(),
      child: MaterialApp(
        navigatorObservers: [hotkeys],
        builder: (context, child) =>
            HotkeyScope(hotkeys: hotkeys, child: child!),
        home: home,
      ),
    );
  }

  Widget homeScreen() => HomeScreen(
    notesRepository: InMemoryNotesRepository(),
    eventsRepository: InMemoryEventsRepository(const []),
    actionsRepository: InMemoryActionsRepository(),
    outbox: NoteWrites.local(InMemoryNotesRepository()),
    actionWrites: ActionWrites.local(InMemoryActionsRepository()),
  );

  Future<void> press(WidgetTester tester, LogicalKeyboardKey key) async {
    await tester.sendKeyEvent(key);
    await tester.pumpAndSettle();
  }

  Future<void> ctrl(WidgetTester tester, LogicalKeyboardKey key) async {
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(key);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
  }

  Future<void> afterCtrlB(WidgetTester tester, LogicalKeyboardKey key) async {
    await ctrl(tester, LogicalKeyboardKey.keyB);
    await press(tester, key);
  }

  group('a description, read', () {
    late Future<String?> result;

    Future<void> open(WidgetTester tester, String? text) async {
      await tester.pumpWidget(
        app(
          Builder(
            builder: (context) => TextButton(
              onPressed: () => result = showTextSheet(
                context,
                title: 'Description',
                text: text,
                hint: 'Add description',
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
    }

    testWidgets('E edits it; Ctrl+Enter saves it and closes', (tester) async {
      await open(tester, 'Checkup');
      expect(find.byType(EditableText), findsNothing);
      await press(tester, LogicalKeyboardKey.keyE);
      expect(find.byType(EditableText), findsOneWidget);

      await tester.enterText(find.byType(EditableText), 'Cleaning');
      await ctrl(tester, LogicalKeyboardKey.enter);
      expect(find.text('Description'), findsNothing);
      expect(await result, 'Cleaning');
    });

    testWidgets('Esc, changed, warns, from the field; again, discards', (
      tester,
    ) async {
      await open(tester, 'Checkup');
      await press(tester, LogicalKeyboardKey.keyE);
      await tester.enterText(find.byType(EditableText), 'Cleaning');

      await press(tester, LogicalKeyboardKey.escape);
      expect(find.text('Description'), findsOneWidget);
      expect(hotkeys.shakes.value, 1);
      expect(find.text(SaveOrDiscard.warning), findsOneWidget);

      await press(tester, LogicalKeyboardKey.escape);
      expect(find.text('Description'), findsNothing);
      expect(await result, isNull);
      expect(find.text(SaveOrDiscard.warning), findsNothing);
    });

    testWidgets('Esc, unchanged, closes at once', (tester) async {
      await open(tester, 'Checkup');
      await press(tester, LogicalKeyboardKey.escape);
      expect(find.text('Description'), findsNothing);
      expect(hotkeys.shakes.value, 0);
    });

    testWidgets('a warning lapses: Esc a while later warns again', (
      tester,
    ) async {
      await open(tester, 'Checkup');
      await press(tester, LogicalKeyboardKey.keyE);
      await tester.enterText(find.byType(EditableText), 'Cleaning');
      await press(tester, LogicalKeyboardKey.escape);
      await tester.pump(const Duration(seconds: 4));
      await press(tester, LogicalKeyboardKey.escape);
      expect(find.text('Description'), findsOneWidget);
      expect(hotkeys.shakes.value, 2);
      // The warning's let go.
      await tester.pump(const Duration(seconds: 4));
    });
  });

  testWidgets("Delete asks to cancel the event, as its trash can does", (
    tester,
  ) async {
    final event = Event(
      id: 'e1',
      summary: 'Dentist',
      start: DateTime(2026, 10, 1, 18),
      end: DateTime(2026, 10, 1, 18, 30),
    );
    await tester.pumpWidget(
      app(
        Builder(
          builder: (context) => TextButton(
            onPressed: () => showEventSummaryDialog(
              context,
              event,
              save: (_) async => const [],
              cancel: (_) async => const [],
            ),
            child: const Text('Open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);

    await press(tester, LogicalKeyboardKey.delete);
    expect(find.byType(AlertDialog), findsNWidgets(2));
  });

  testWidgets('Ctrl+B, then S, opens the menu', (tester) async {
    await tester.pumpWidget(app(homeScreen()));
    await tester.pumpAndSettle();
    expect(find.text('Settings'), findsNothing);
    await afterCtrlB(tester, LogicalKeyboardKey.keyS);
    expect(find.text('Settings'), findsOneWidget);
  });

  testWidgets('J and K go down and up the menu; Enter picks', (tester) async {
    await tester.pumpWidget(app(homeScreen()));
    await tester.pumpAndSettle();
    await afterCtrlB(tester, LogicalKeyboardKey.keyS);

    /// Whether [label]'s item is the one highlighted.
    bool on(String label) => find
        .descendant(
          of: find.byElementPredicate(
            (e) => e == FocusManager.instance.primaryFocus?.context,
          ),
          matching: find.text(label),
        )
        .evaluate()
        .isNotEmpty;

    await press(tester, LogicalKeyboardKey.keyJ);
    expect(on('Settings'), isTrue);
    await press(tester, LogicalKeyboardKey.keyJ);
    expect(on('Settings'), isFalse);
    await press(tester, LogicalKeyboardKey.keyK);
    expect(on('Settings'), isTrue);

    await press(tester, LogicalKeyboardKey.enter);
    expect(find.text('Snap to grid'), findsOneWidget);
  });

  testWidgets('the arrow keys scroll the list of hotkeys', (tester) async {
    tester.view.physicalSize = const Size(800, 500);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(app(homeScreen()));
    await tester.pumpAndSettle();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.slash, character: '?');
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pumpAndSettle();

    final list = tester.state<ScrollableState>(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(Scrollable),
      ),
    );
    expect(list.position.pixels, 0);
    await press(tester, LogicalKeyboardKey.arrowDown);
    expect(list.position.pixels, greaterThan(0));
    await press(tester, LogicalKeyboardKey.arrowUp);
    expect(list.position.pixels, 0);
  });

  testWidgets('on the Plan page, H and L go between panes; J highlights '
      'down the one shown', (tester) async {
    await tester.pumpWidget(app(homeScreen()));
    await tester.pumpAndSettle();
    await afterCtrlB(tester, LogicalKeyboardKey.keyP);
    TabController tabs() =>
        DefaultTabController.of(tester.element(find.byType(TabBarView)));
    expect(tabs().index, 0);

    await press(tester, LogicalKeyboardKey.keyL);
    expect(tabs().index, 1);
    await press(tester, LogicalKeyboardKey.keyL);
    await press(tester, LogicalKeyboardKey.keyH);
    expect(tabs().index, 1);
    await press(tester, LogicalKeyboardKey.keyH);
    await press(tester, LogicalKeyboardKey.keyH);
    expect(tabs().index, 0);

    final before = FocusManager.instance.primaryFocus;
    await press(tester, LogicalKeyboardKey.keyJ);
    final first = FocusManager.instance.primaryFocus;
    expect(first, isNot(before));
    expect(
      first?.context?.findAncestorWidgetOfExactType<TabBarView>(),
      isNotNull,
    );
  });

  group('Ctrl+Enter presses Done, or Save', () {
    Future<void> open(
      WidgetTester tester,
      VoidCallback Function(BuildContext) opens,
    ) async {
      await tester.pumpWidget(
        app(
          Builder(
            builder: (context) => TextButton(
              onPressed: opens(context),
              child: const Text('Open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
    }

    testWidgets('in a picker sheet, from its search', (tester) async {
      List<String>? result;
      await open(
        tester,
        (context) =>
            () async => result = await pickNodes(
              context,
              title: 'Who',
              nodes: const [PickerNode(id: 'sam', label: 'Sam')],
              picked: const ['sam'],
            ),
      );
      await tester.enterText(find.byType(TextField), 'sam');
      await ctrl(tester, LogicalKeyboardKey.enter);
      expect(result, ['sam']);
      expect(find.text('Who'), findsNothing);
    });

    testWidgets("in a share's dialog, once it can be set", (tester) async {
      LocationShare? result;
      var closed = false;
      await open(
        tester,
        (context) => () async {
          result = await showShareDialog(
            context,
            title: 'Home',
            share: const LocationShare('home'),
            eventMinutes: 60,
            kind: 'location',
            rest: 'The rest',
            make: (minutes, percent, remaining) => LocationShare(
              'home',
              minutes: minutes,
              percent: percent,
              remaining: remaining,
            ),
          );
          closed = true;
        },
      );
      await tester.tap(find.text('Minutes'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '0');
      await tester.pump();
      // Nothing to set: Save can't be pressed, nor Ctrl+Enter save.
      await ctrl(tester, LogicalKeyboardKey.enter);
      expect(closed, isFalse);
      await tester.enterText(find.byType(TextField), '45');
      await tester.pump();
      await ctrl(tester, LogicalKeyboardKey.enter);
      expect(closed, isTrue);
      expect(result?.minutes, 45);
    });
  });
}
