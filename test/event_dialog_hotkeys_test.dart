import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:time_tracker_client/models/event.dart';
import 'package:time_tracker_client/services/people_repository.dart';
import 'package:time_tracker_client/widgets/event_summary_dialog.dart';
import 'package:time_tracker_client/widgets/hotkeys.dart';
import 'package:time_tracker_client/widgets/picker_search.dart';

void main() {
  late Hotkeys hotkeys;
  Map<String, Object?>? saved;

  Future<void> open(WidgetTester tester) async {
    saved = null;
    hotkeys = Hotkeys();
    final event = Event(
      id: 'e1',
      summary: 'Dentist',
      start: DateTime(2026, 10, 1, 18),
      end: DateTime(2026, 10, 1, 18, 30),
      properties: {'description': 'Checkup'},
    );
    await tester.pumpWidget(
      PeopleScope(
        repository: InMemoryPeopleRepository(),
        child: MaterialApp(
          navigatorObservers: [hotkeys],
          builder: (context, child) =>
              HotkeyScope(hotkeys: hotkeys, child: child!),
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () => showEventSummaryDialog(
                context,
                event,
                save: (changes) async {
                  saved = changes;
                  return const [];
                },
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
  }

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

  bool dialogShown() => find.byType(AlertDialog).evaluate().isNotEmpty;

  testWidgets('D opens the description', (tester) async {
    await open(tester);
    expect(find.text('Description'), findsNothing);
    await press(tester, LogicalKeyboardKey.keyD);
    expect(find.text('Description'), findsOneWidget);
  });

  testWidgets('W opens who it was with; L, where; / searches there', (
    tester,
  ) async {
    await open(tester);
    await press(tester, LogicalKeyboardKey.keyW);
    expect(find.byType(BottomSheet), findsOneWidget);
    final search = tester.widget<PickerSearchField>(
      find.byType(PickerSearchField),
    );
    search.search.focus.unfocus();
    await tester.pumpAndSettle();
    expect(search.search.focus.hasFocus, isFalse);
    await press(tester, LogicalKeyboardKey.slash);
    expect(search.search.focus.hasFocus, isTrue);

    // Out of the field, then out of the sheet.
    await press(tester, LogicalKeyboardKey.escape);
    await press(tester, LogicalKeyboardKey.escape);
    expect(find.byType(BottomSheet), findsNothing);
    await press(tester, LogicalKeyboardKey.keyL);
    expect(find.byType(BottomSheet), findsOneWidget);
  });

  testWidgets('S selects the summary, to type over; Ctrl+Enter saves', (
    tester,
  ) async {
    await open(tester);
    await press(tester, LogicalKeyboardKey.keyS);
    final field = tester.widget<EditableText>(find.byType(EditableText));
    expect(field.controller.text, 'Dentist');
    expect(
      field.controller.selection,
      const TextSelection(baseOffset: 0, extentOffset: 7),
    );

    await tester.enterText(find.byType(EditableText), 'Doctor');
    await ctrl(tester, LogicalKeyboardKey.enter);
    expect(saved?['summary'], 'Doctor');
    expect(dialogShown(), isFalse);
  });

  testWidgets('Esc closes it at once, with no changes', (tester) async {
    await open(tester);
    await press(tester, LogicalKeyboardKey.escape);
    expect(dialogShown(), isFalse);
  });

  testWidgets('Esc with changes shakes first; again, discards them', (
    tester,
  ) async {
    await open(tester);
    await press(tester, LogicalKeyboardKey.keyS);
    await tester.enterText(find.byType(EditableText), 'Doctor');
    // Out of the field first.
    await press(tester, LogicalKeyboardKey.escape);
    expect(dialogShown(), isTrue);

    await press(tester, LogicalKeyboardKey.escape);
    expect(dialogShown(), isTrue);
    expect(hotkeys.shakes.value, 1);
    expect(find.text('Press Esc again to discard your changes.'), findsOne);

    await press(tester, LogicalKeyboardKey.escape);
    expect(dialogShown(), isFalse);
    expect(saved, isNull);
  });

  testWidgets('J and K move between its parts', (tester) async {
    await open(tester);
    await press(tester, LogicalKeyboardKey.keyJ);
    final first = FocusManager.instance.primaryFocus;
    await press(tester, LogicalKeyboardKey.keyJ);
    final second = FocusManager.instance.primaryFocus;
    expect(second, isNot(first));
    await press(tester, LogicalKeyboardKey.keyK);
    expect(FocusManager.instance.primaryFocus, first);
  });
}
