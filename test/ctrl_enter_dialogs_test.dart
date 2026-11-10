import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:time_tracker_client/models/trait.dart';
import 'package:time_tracker_client/widgets/error_sheet.dart';
import 'package:time_tracker_client/widgets/hotkeys.dart';
import 'package:time_tracker_client/widgets/trait_dialog.dart';

void main() {
  /// A page that calls [open] when its button is tapped.
  Future<void> pump(
    WidgetTester tester,
    void Function(BuildContext context) open,
  ) async {
    final hotkeys = Hotkeys();
    await tester.pumpWidget(
      MaterialApp(
        navigatorObservers: [hotkeys],
        builder: (context, child) =>
            HotkeyScope(hotkeys: hotkeys, child: child!),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => open(context),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
  }

  Future<void> ctrlEnter(WidgetTester tester) async {
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
  }

  testWidgets('Ctrl+Enter adds a fact, once it has what it needs', (
    tester,
  ) async {
    TraitFact? made;
    await pump(tester, (context) async {
      made = await showFactDialog(context);
    });
    await ctrlEnter(tester);
    expect(find.text('New fact'), findsOneWidget);

    await tester.enterText(find.byType(TextField).at(0), 'What matters');
    await tester.enterText(find.byType(TextField).at(1), 'A list of it');
    await tester.pump();
    await ctrlEnter(tester);
    expect(find.text('New fact'), findsNothing);
    expect(made?.name, 'What matters');
  });

  testWidgets('Ctrl+Enter tries again from an error sheet that offers to', (
    tester,
  ) async {
    var tries = 0;
    await pump(tester, (context) {
      showErrorSheet(
        context,
        title: "Couldn't save",
        error: Exception('offline'),
        onRetry: () => tries++,
      );
    });
    await ctrlEnter(tester);
    expect(tries, 1);
    expect(find.text("Couldn't save"), findsNothing);
  });

  testWidgets("Ctrl+Enter does nothing on an error sheet that can't retry", (
    tester,
  ) async {
    await pump(tester, (context) {
      showErrorSheet(
        context,
        title: "Couldn't save",
        error: Exception('offline'),
      );
    });
    await ctrlEnter(tester);
    expect(find.text("Couldn't save"), findsOneWidget);
  });
}
