import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:time_tracker_client/widgets/day_picker.dart';
import 'package:time_tracker_client/widgets/hotkeys.dart';

void main() {
  late Hotkeys hotkeys;
  DateTime? picked;
  var closed = false;

  Widget app({DateTime? initial, bool typed = false}) {
    hotkeys = Hotkeys();
    picked = null;
    closed = false;
    return MaterialApp(
      navigatorObservers: [hotkeys],
      builder: (context, child) => HotkeyScope(hotkeys: hotkeys, child: child!),
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () async {
              picked = await showDayPicker(
                context,
                initialDate: initial ?? DateTime(2026, 10, 30),
                firstDate: DateTime(2000),
                lastDate: DateTime(2100),
                currentDate: DateTime(2026, 10, 30),
                typed: typed,
              );
              closed = true;
            },
            child: const Text('Pick'),
          ),
        ),
      ),
    );
  }

  Future<void> open(
    WidgetTester tester, {
    DateTime? initial,
    bool typed = false,
  }) async {
    await tester.pumpWidget(app(initial: initial, typed: typed));
    await tester.tap(find.text('Pick'));
    await tester.pumpAndSettle();
  }

  Future<void> press(WidgetTester tester, LogicalKeyboardKey key) async {
    await tester.sendKeyEvent(key);
    await tester.pumpAndSettle();
  }

  Future<void> ctrlEnter(WidgetTester tester) async {
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
  }

  testWidgets('J and K step a day, across months; Ctrl+Enter goes with it', (
    tester,
  ) async {
    await open(tester);
    await press(tester, LogicalKeyboardKey.keyJ);
    await press(tester, LogicalKeyboardKey.keyJ);
    // November, shown.
    expect(find.text('November 2026'), findsOneWidget);
    await press(tester, LogicalKeyboardKey.keyK);
    await ctrlEnter(tester);
    expect(closed, isTrue);
    expect(picked, DateTime(2026, 10, 31));
  });

  testWidgets('H and L go a month, to the same day or the last of a '
      'shorter one', (tester) async {
    await open(tester, initial: DateTime(2026, 3, 31));
    await press(tester, LogicalKeyboardKey.keyH);
    expect(find.text('February 2026'), findsOneWidget);
    await press(tester, LogicalKeyboardKey.keyL);
    await press(tester, LogicalKeyboardKey.keyL);
    await ctrlEnter(tester);
    // The 28th, from February: a month on goes to the same day of it.
    expect(picked, DateTime(2026, 4, 28));
  });

  testWidgets('T picks today; the arrows step a day or a week', (tester) async {
    await open(tester, initial: DateTime(2025, 1, 15));
    await press(tester, LogicalKeyboardKey.keyT);
    expect(find.text('October 2026'), findsOneWidget);
    await press(tester, LogicalKeyboardKey.arrowDown);
    await press(tester, LogicalKeyboardKey.arrowLeft);
    await ctrlEnter(tester);
    expect(picked, DateTime(2026, 11, 5));
  });

  testWidgets('a day tapped, then a key, goes on from it', (tester) async {
    await open(tester);
    await tester.tap(find.text('12'));
    await tester.pumpAndSettle();
    await press(tester, LogicalKeyboardKey.keyJ);
    await ctrlEnter(tester);
    expect(picked, DateTime(2026, 10, 13));
  });

  testWidgets('E types the date, selected; Enter goes with what is typed', (
    tester,
  ) async {
    await open(tester);
    await press(tester, LogicalKeyboardKey.keyE);
    final field = tester.widget<EditableText>(find.byType(EditableText));
    expect(field.focusNode.hasFocus, isTrue);
    final text = field.controller.value;
    expect(text.text, '10/30/2026');
    expect(
      text.selection,
      const TextSelection(baseOffset: 0, extentOffset: 10),
    );

    await tester.enterText(find.byType(EditableText), '12/25/2026');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(picked, DateTime(2026, 12, 25));
  });

  testWidgets('Ctrl+Enter goes with what is typed; nothing, if it is no '
      'date', (tester) async {
    await open(tester, typed: true);
    await tester.enterText(find.byType(EditableText), 'soon');
    await ctrlEnter(tester);
    expect(closed, isFalse);
    await tester.enterText(find.byType(EditableText), '1/2/2027');
    await ctrlEnter(tester);
    expect(picked, DateTime(2027, 1, 2));
  });

  testWidgets('out of the text, a key goes back to the calendar from what '
      'was typed', (tester) async {
    await open(tester, typed: true);
    await tester.enterText(find.byType(EditableText), '5/5/2026');
    await press(tester, LogicalKeyboardKey.escape);
    expect(hotkeys.dialogOpen, isTrue);
    await press(tester, LogicalKeyboardKey.keyJ);
    expect(find.byType(EditableText), findsNothing);
    expect(find.text('May 2026'), findsOneWidget);
    await ctrlEnter(tester);
    expect(picked, DateTime(2026, 5, 6));
  });

  testWidgets('Enter goes with the day picked, as Ctrl+Enter does', (
    tester,
  ) async {
    await open(tester);
    await press(tester, LogicalKeyboardKey.enter);
    expect(picked, DateTime(2026, 10, 30));

    await open(tester);
    await tester.tap(find.text('12'));
    await tester.pumpAndSettle();
    await press(tester, LogicalKeyboardKey.keyJ);
    await press(tester, LogicalKeyboardKey.enter);
    expect(picked, DateTime(2026, 10, 13));
  });

  testWidgets('Enter on a button Tab went to presses it', (tester) async {
    await open(tester);
    await press(tester, LogicalKeyboardKey.keyJ);
    final cancel = find.ancestor(
      of: find.text('Cancel'),
      matching: find.byType(TextButton),
    );
    Focus.of(tester.element(find.text('Cancel'))).requestFocus();
    await tester.pumpAndSettle();
    expect(cancel, findsOneWidget);
    await press(tester, LogicalKeyboardKey.enter);
    expect(closed, isTrue);
    expect(picked, isNull);
  });

  testWidgets('a title, for what it is for', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => showDayPicker(
              context,
              initialDate: DateTime(2026, 10, 30),
              firstDate: DateTime(2000),
              lastDate: DateTime(2100),
              helpText: 'Try again by',
            ),
            child: const Text('Pick'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Pick'));
    await tester.pumpAndSettle();
    expect(find.text('Try again by'), findsOneWidget);
    expect(find.text('Select date'), findsNothing);
  });

  testWidgets('Esc calls it off', (tester) async {
    await open(tester);
    await press(tester, LogicalKeyboardKey.keyJ);
    await press(tester, LogicalKeyboardKey.escape);
    expect(closed, isTrue);
    expect(picked, isNull);
  });
}
