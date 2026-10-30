import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:time_tracker_client/widgets/focus_keeper.dart';

void main() {
  late DateTime now;
  bool? windowFocused;

  Widget app({bool askable = false}) {
    now = DateTime(2026, 10, 30, 12);
    windowFocused = askable ? true : null;
    return MaterialApp(
      builder: (context, child) => FocusKeeper(
        windowFocused: () => windowFocused,
        onWindowFocus: (_) => () {},
        clock: () => now,
        child: child!,
      ),
      home: const Scaffold(
        body: Column(
          children: [
            TextField(key: ValueKey('a')),
            TextField(key: ValueKey('b')),
          ],
        ),
      ),
    );
  }

  FocusNode field(WidgetTester tester, String key) => tester
      .widget<EditableText>(
        find.descendant(
          of: find.byKey(ValueKey(key)),
          matching: find.byType(EditableText),
        ),
      )
      .focusNode;

  Future<void> lifecycle(WidgetTester tester, AppLifecycleState state) async {
    tester.binding.handleAppLifecycleStateChanged(state);
    await tester.pumpAndSettle();
  }

  Future<void> away(WidgetTester tester) async {
    await lifecycle(tester, AppLifecycleState.inactive);
    await lifecycle(tester, AppLifecycleState.hidden);
  }

  Future<void> back(WidgetTester tester) async {
    await lifecycle(tester, AppLifecycleState.inactive);
    await lifecycle(tester, AppLifecycleState.resumed);
  }

  testWidgets('a field let go of as the window goes away has focus once '
      'it is back', (tester) async {
    await tester.pumpWidget(app(askable: true));
    await tester.tap(find.byKey(const ValueKey('b')));
    await tester.pumpAndSettle();
    // As a browser does: the field's input closed, the window unfocused.
    windowFocused = false;
    field(tester, 'b').unfocus();
    await tester.pumpAndSettle();
    await away(tester);
    expect(field(tester, 'b').hasFocus, isFalse);

    windowFocused = true;
    await back(tester);
    expect(field(tester, 'b').hasFocus, isTrue);
  });

  testWidgets('where the window cannot be asked, a field let go of just '
      'before the app goes away', (tester) async {
    await tester.pumpWidget(app());
    await tester.tap(find.byKey(const ValueKey('a')));
    await tester.pumpAndSettle();
    field(tester, 'a').unfocus();
    await tester.pumpAndSettle();
    now = now.add(const Duration(milliseconds: 100));
    await away(tester);
    await back(tester);
    expect(field(tester, 'a').hasFocus, isTrue);
  });

  testWidgets('a field let go of while the app was in front stays let go '
      'of', (tester) async {
    await tester.pumpWidget(app());
    await tester.tap(find.byKey(const ValueKey('a')));
    await tester.pumpAndSettle();
    field(tester, 'a').unfocus();
    await tester.pumpAndSettle();
    now = now.add(const Duration(seconds: 5));
    await away(tester);
    await back(tester);
    expect(field(tester, 'a').hasFocus, isFalse);
  });

  testWidgets('focus put elsewhere since stays there', (tester) async {
    await tester.pumpWidget(app(askable: true));
    await tester.tap(find.byKey(const ValueKey('a')));
    await tester.pumpAndSettle();
    windowFocused = false;
    field(tester, 'a').unfocus();
    await tester.pumpAndSettle();
    await away(tester);
    windowFocused = true;
    field(tester, 'b').requestFocus();
    await tester.pumpAndSettle();
    await back(tester);
    expect(field(tester, 'b').hasFocus, isTrue);
    expect(field(tester, 'a').hasFocus, isFalse);
  });
}
