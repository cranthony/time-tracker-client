import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:time_tracker_client/widgets/app_menu.dart';
import 'package:time_tracker_client/widgets/hotkeys.dart';

void main() {
  late Hotkeys hotkeys;
  late int shown;
  late int hidden;

  /// A page with a list that refreshes, and another, offstage, that's
  /// not shown; and a text field.
  Widget app() {
    hotkeys = Hotkeys();
    shown = hidden = 0;
    return MaterialApp(
      navigatorObservers: [hotkeys],
      builder: (context, child) => HotkeyScope(hotkeys: hotkeys, child: child!),
      home: Scaffold(
        body: Column(
          children: [
            const TextField(),
            Expanded(
              child: RefreshIndicator(
                onRefresh: () async => shown++,
                child: ListView(children: const [Text('shown')]),
              ),
            ),
            Offstage(
              child: SizedBox(
                height: 100,
                child: RefreshIndicator(
                  onRefresh: () async => hidden++,
                  child: ListView(children: const [Text('hidden')]),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  testWidgets('R refreshes what the page shows, as pulling it down does', (
    tester,
  ) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    await tester.sendKeyEvent(LogicalKeyboardKey.keyR);
    await tester.pumpAndSettle();

    expect(shown, 1);
    expect(hidden, 0);
  });

  testWidgets("R presses the page's refresh button, where it has one", (
    tester,
  ) async {
    hotkeys = Hotkeys();
    final pressed = Completer<void>();
    var presses = 0;
    var pulled = 0;
    await tester.pumpWidget(
      MaterialApp(
        navigatorObservers: [hotkeys],
        builder: (context, child) =>
            HotkeyScope(hotkeys: hotkeys, child: child!),
        home: Scaffold(
          appBar: AppBar(
            actions: [
              RefreshButton(
                onRefresh: () {
                  presses++;
                  return pressed.future;
                },
              ),
            ],
          ),
          body: RefreshIndicator(
            onRefresh: () async => pulled++,
            child: ListView(children: const [Text('shown')]),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.sendKeyEvent(LogicalKeyboardKey.keyR);
    await tester.pump();

    expect(presses, 1);
    expect(pulled, 0);
    // Spinning, till it's done.
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyR);
    await tester.pump();
    expect(presses, 1);

    pressed.complete();
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.refresh), findsOneWidget);
  });

  testWidgets('R types an R in a text field', (tester) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await tester.tap(find.byType(TextField));
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.keyR);
    await tester.pumpAndSettle();

    expect(shown, 0);
  });

  testWidgets('a quiet refresh shows no spinner', (tester) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    expect(hotkeys.refreshShown(quietly: true), isTrue);
    await tester.pump();

    expect(find.byType(RefreshProgressIndicator), findsNothing);
    expect(shown, 1);
    expect(hidden, 0);
  });

  testWidgets('R is in the list of hotkeys', (tester) async {
    expect(Hotkey.all, contains(Hotkey.refresh));
    expect(Hotkey.refresh.keys, 'R');
  });
}
