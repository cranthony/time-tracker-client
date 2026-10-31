import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:time_tracker_client/models/goal.dart';
import 'package:time_tracker_client/widgets/day_picker.dart';
import 'package:time_tracker_client/widgets/goal_editor.dart';
import 'package:time_tracker_client/widgets/hotkeys.dart';
import 'package:time_tracker_client/widgets/text_editor.dart';

void main() {
  final now = DateTime(2026, 10, 30, 12);

  Goal goal({String status = 'active'}) => Goal(
    id: 'plan',
    title: 'Plan the trip',
    status: status,
    deadline: deadlineOf(DateTime(2026, 11, 2)),
    expectedMinutes: 90,
    attributionHints: 'Trip planning',
  );

  Future<void> open(WidgetTester tester, {String status = 'active'}) async {
    // Tall enough for the whole page.
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final hotkeys = Hotkeys();
    await tester.pumpWidget(
      MaterialApp(
        navigatorObservers: [hotkeys],
        builder: (context, child) =>
            HotkeyScope(hotkeys: hotkeys, child: child!),
        home: GoalEditorPage(
          goal: goal(status: status),
          goals: [goal(status: status)],
          now: () => now,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> press(WidgetTester tester, LogicalKeyboardKey key) async {
    await tester.sendKeyEvent(key);
    await tester.pumpAndSettle();
  }

  /// The section highlighted, by its focus node's label.
  String? highlighted() => FocusManager.instance.primaryFocus?.debugLabel;

  /// The text field with focus, if one has: its text, and what's selected.
  TextEditingValue? typing(WidgetTester tester) {
    for (final field in tester.widgetList<EditableText>(
      find.byType(EditableText),
    )) {
      if (field.focusNode.hasFocus) return field.controller.value;
    }
    return null;
  }

  testWidgets('J and K go from section to section', (tester) async {
    await open(tester);
    await press(tester, LogicalKeyboardKey.keyJ);
    expect(highlighted(), 'Goal title');
    await press(tester, LogicalKeyboardKey.keyJ);
    expect(highlighted(), 'Goal status');
    await press(tester, LogicalKeyboardKey.keyJ);
    expect(highlighted(), 'Goal deadline');
    // Starts shows only for an inactive goal: passed by.
    await press(tester, LogicalKeyboardKey.keyJ);
    expect(highlighted(), 'Goal priority');
    await press(tester, LogicalKeyboardKey.keyK);
    expect(highlighted(), 'Goal deadline');
  });

  testWidgets('K from nothing goes to the last; Enter goes into a section, '
      'its text selected', (tester) async {
    await open(tester);
    await press(tester, LogicalKeyboardKey.keyK);
    expect(highlighted(), 'Goal hints');
    await press(tester, LogicalKeyboardKey.enter);
    expect(
      typing(tester),
      const TextEditingValue(
        text: 'Trip planning',
        selection: TextSelection(baseOffset: 0, extentOffset: 13),
      ),
    );
  });

  testWidgets('D goes to Deadline; D again picks its date', (tester) async {
    await open(tester);
    await press(tester, LogicalKeyboardKey.keyD);
    expect(highlighted(), 'Goal deadline');
    expect(find.byType(DayPickerDialog), findsNothing);
    await press(tester, LogicalKeyboardKey.keyD);
    expect(find.byType(DayPickerDialog), findsOneWidget);
    // Its day: the 2nd.
    await press(tester, LogicalKeyboardKey.keyJ);
    await press(tester, LogicalKeyboardKey.enter);
    expect(find.textContaining('Nov 3'), findsOneWidget);
  });

  testWidgets('D, then D a while later, only goes to Deadline', (tester) async {
    await open(tester);
    await press(tester, LogicalKeyboardKey.keyD);
    await tester.pump(GoalEditorPage.chordWindow * 2);
    await press(tester, LogicalKeyboardKey.keyD);
    expect(find.byType(DayPickerDialog), findsNothing);
    expect(highlighted(), 'Goal deadline');
    await tester.pump(GoalEditorPage.chordWindow);
  });

  testWidgets('D, then E edits the description; D, then O the definition '
      'of done', (tester) async {
    await open(tester);
    await press(tester, LogicalKeyboardKey.keyD);
    await press(tester, LogicalKeyboardKey.keyE);
    expect(
      tester.widget<TextEditorPage>(find.byType(TextEditorPage)).title,
      'Description',
    );
    tester.state<NavigatorState>(find.byType(Navigator)).pop();
    await tester.pumpAndSettle();

    await press(tester, LogicalKeyboardKey.keyD);
    await press(tester, LogicalKeyboardKey.keyO);
    expect(
      tester.widget<TextEditorPage>(find.byType(TextEditorPage)).title,
      'Definition of done',
    );
  });

  testWidgets('O alone does nothing', (tester) async {
    await open(tester);
    await press(tester, LogicalKeyboardKey.keyO);
    expect(find.byType(TextEditorPage), findsNothing);
  });

  testWidgets('E puts the cursor in Expected time, its text selected', (
    tester,
  ) async {
    await open(tester);
    await press(tester, LogicalKeyboardKey.keyE);
    final value = typing(tester)!;
    expect(value.text, isNotEmpty);
    expect(value.selection.start, 0);
    expect(value.selection.end, value.text.length);
    expect(find.byType(TextEditorPage), findsNothing);
  });

  testWidgets('H puts the cursor in the attribution hints', (tester) async {
    await open(tester);
    await press(tester, LogicalKeyboardKey.keyH);
    expect(typing(tester)?.text, 'Trip planning');
  });

  testWidgets('P goes to Priority; W picks its people', (tester) async {
    await open(tester);
    await press(tester, LogicalKeyboardKey.keyP);
    expect(highlighted(), 'Goal priority');
    await press(tester, LogicalKeyboardKey.keyW);
    expect(find.text('Who you’ll do it with'), findsOneWidget);
  });

  testWidgets('S goes to Starts, for an inactive goal; S again picks a day '
      'it starts from', (tester) async {
    await open(tester, status: 'inactive');
    await press(tester, LogicalKeyboardKey.keyS);
    expect(highlighted(), 'Goal starts');
    await press(tester, LogicalKeyboardKey.keyS);
    expect(find.byType(DayPickerDialog), findsOneWidget);
    await press(tester, LogicalKeyboardKey.enter);
    expect(find.textContaining('From Sat, Oct 31'), findsOneWidget);
  });

  testWidgets('S, for an active goal, says Starts is not shown', (
    tester,
  ) async {
    await open(tester);
    await press(tester, LogicalKeyboardKey.keyS);
    expect(find.text("Starts shows while it's inactive"), findsOneWidget);
    await tester.pump(const Duration(seconds: 4));
  });
}
