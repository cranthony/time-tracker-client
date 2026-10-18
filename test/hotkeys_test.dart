import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:time_tracker_client/outbox/action_writes.dart';
import 'package:time_tracker_client/outbox/note_writes.dart';
import 'package:time_tracker_client/screens/events_screen.dart';
import 'package:time_tracker_client/screens/home_screen.dart';
import 'package:time_tracker_client/screens/notes_screen.dart';
import 'package:time_tracker_client/screens/plan_screen.dart';
import 'package:time_tracker_client/services/actions_repository.dart';
import 'package:time_tracker_client/services/events_repository.dart';
import 'package:time_tracker_client/services/notes_repository.dart';
import 'package:time_tracker_client/widgets/hotkeys.dart';

void main() {
  late Hotkeys hotkeys;
  late InMemoryNotesRepository notes;
  late NoteWrites outbox;

  Widget app() {
    hotkeys = Hotkeys();
    notes = InMemoryNotesRepository();
    outbox = NoteWrites.local(notes);
    return MaterialApp(
      navigatorObservers: [hotkeys],
      builder: (context, child) => HotkeyScope(hotkeys: hotkeys, child: child!),
      home: HomeScreen(
        notesRepository: notes,
        eventsRepository: InMemoryEventsRepository(const []),
        actionsRepository: InMemoryActionsRepository(),
        outbox: outbox,
        actionWrites: ActionWrites.local(InMemoryActionsRepository()),
      ),
    );
  }

  Future<void> ctrl(WidgetTester tester, LogicalKeyboardKey key) async {
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(key);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
  }

  Future<void> afterCtrlB(WidgetTester tester, LogicalKeyboardKey key) async {
    await ctrl(tester, LogicalKeyboardKey.keyB);
    await tester.sendKeyEvent(key);
    await tester.pumpAndSettle();
  }

  testWidgets('Ctrl+B, then a letter, goes to that page', (tester) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    expect(find.byType(NotesScreen), findsOneWidget);

    await afterCtrlB(tester, LogicalKeyboardKey.keyE);
    expect(find.byType(EventsScreen), findsOneWidget);
    await afterCtrlB(tester, LogicalKeyboardKey.keyP);
    expect(find.byType(PlanScreen), findsOneWidget);
    await afterCtrlB(tester, LogicalKeyboardKey.keyN);
    expect(find.byType(NotesScreen), findsOneWidget);
  });

  testWidgets('Ctrl+B, then the letter with Ctrl still held, does nothing', (
    tester,
  ) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyB);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyE);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    expect(find.byType(NotesScreen), findsOneWidget);
    expect(hotkeys.afterCtrlB, isFalse);
  });

  testWidgets('Ctrl+B shows what it waits for, until the next key', (
    tester,
  ) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await ctrl(tester, LogicalKeyboardKey.keyB);
    expect(find.textContaining('let go of Ctrl'), findsOneWidget);
    expect(find.text('E'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.textContaining('let go of Ctrl'), findsNothing);
    expect(find.byType(NotesScreen), findsOneWidget);
  });

  testWidgets('Ctrl+B, then a letter, shakes instead while a dialog is open', (
    tester,
  ) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    final context = tester.element(find.byType(NotesScreen));
    showDialog<void>(
      context: context,
      builder: (_) => const AlertDialog(title: Text('Unsaved')),
    );
    await tester.pumpAndSettle();

    await afterCtrlB(tester, LogicalKeyboardKey.keyE);
    expect(hotkeys.shakes.value, 1);
    expect(find.text('Unsaved'), findsOneWidget);
    expect(find.byType(NotesScreen), findsOneWidget);
  });

  testWidgets('Ctrl+M writes a note over the page, and goes back to it', (
    tester,
  ) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await afterCtrlB(tester, LogicalKeyboardKey.keyE);

    await ctrl(tester, LogicalKeyboardKey.keyM);
    expect(find.text('New note'), findsOneWidget);
    expect(find.byType(EventsScreen), findsOneWidget);
    // Not a second one over it.
    await ctrl(tester, LogicalKeyboardKey.keyM);
    expect(find.text('New note'), findsOneWidget);

    await tester.enterText(find.byType(TextField).last, 'Tea');
    await ctrl(tester, LogicalKeyboardKey.enter);
    expect(find.text('New note'), findsNothing);
    expect(find.byType(EventsScreen), findsOneWidget);
    expect(outbox.pending.single.note.description, 'Tea');
  });

  testWidgets('Esc leaves a text field; a letter then is a hotkey again', (
    tester,
  ) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await ctrl(tester, LogicalKeyboardKey.keyM);
    expect(find.byType(EditableText), findsOneWidget);
    final field = tester.widget<EditableText>(find.byType(EditableText));
    expect(field.focusNode.hasFocus, isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(field.focusNode.hasFocus, isFalse);
    expect(find.text('New note'), findsOneWidget);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.slash, character: '?');
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pumpAndSettle();
    expect(find.text('Hotkeys'), findsOneWidget);
  });

  testWidgets('? lists the hotkeys', (tester) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.slash, character: '?');
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pumpAndSettle();
    expect(find.text('Hotkeys'), findsOneWidget);
    expect(find.text('Ctrl+B, then E'), findsOneWidget);
    expect(find.text('Go to Events, at now'), findsOneWidget);
  });

  testWidgets('Ctrl held a moment shows the hints, until it is let go', (
    tester,
  ) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Ctrl+M / +'), findsNothing);
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Ctrl+M / +'), findsOneWidget);
    expect(find.text('Ctrl+B E'), findsOneWidget);

    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    expect(find.text('Ctrl+M / +'), findsNothing);
  });

  testWidgets('a quick Ctrl shortcut shows no hints', (tester) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Ctrl+M'), findsNothing);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  });
}
