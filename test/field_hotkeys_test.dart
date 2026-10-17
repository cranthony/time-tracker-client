import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:time_tracker_client/models/plan_action.dart';
import 'package:time_tracker_client/widgets/action_dialog.dart';
import 'package:time_tracker_client/widgets/hotkeys.dart';
import 'package:time_tracker_client/widgets/plan_pane.dart';

void main() {
  /// Panes swiped between, as the Plan page's are, each a search over a
  /// long list.
  Widget panes(Hotkeys hotkeys, {required List<String> titles}) => MaterialApp(
    navigatorObservers: [hotkeys],
    builder: (context, child) => HotkeyScope(hotkeys: hotkeys, child: child!),
    home: DefaultTabController(
      length: titles.length,
      child: Scaffold(
        appBar: AppBar(
          bottom: TabBar(tabs: [for (final t in titles) Tab(text: t)]),
        ),
        body: TabBarView(
          children: [
            for (final t in titles)
              PlanPane(
                searchHint: 'Search $t',
                onSearch: (_) {},
                child: ListView(
                  key: ValueKey(t),
                  children: [
                    for (var i = 0; i < 100; i++)
                      ListTile(title: Text('$t $i')),
                  ],
                ),
              ),
          ],
        ),
      ),
    ),
  );

  double offsetOf(WidgetTester tester, String pane) => tester
      .state<ScrollableState>(
        find.descendant(
          of: find.byKey(ValueKey(pane)),
          matching: find.byType(Scrollable),
        ),
      )
      .position
      .pixels;

  EditableText field(WidgetTester tester, String hint) =>
      tester.widget<EditableText>(
        find.descendant(
          of: find.widgetWithText(TextField, hint),
          matching: find.byType(EditableText),
        ),
      );

  testWidgets('↓ scrolls the pane shown, not one swiped away', (tester) async {
    final hotkeys = Hotkeys();
    await tester.pumpWidget(panes(hotkeys, titles: ['Actions', 'Locations']));
    await tester.tap(find.text('Locations'));
    await tester.pumpAndSettle();

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(offsetOf(tester, 'Locations'), greaterThan(0));
    // Kept, swiped away: built, but not scrolled.
    await tester.tap(find.text('Actions'));
    await tester.pumpAndSettle();
    expect(offsetOf(tester, 'Actions'), 0);
  });

  testWidgets('/ goes to the search of the pane shown, what is in it '
      'selected', (tester) async {
    final hotkeys = Hotkeys();
    await tester.pumpWidget(panes(hotkeys, titles: ['Actions', 'Locations']));
    await tester.tap(find.text('Locations'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Search Locations'),
      'park',
    );
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();

    await tester.sendKeyEvent(LogicalKeyboardKey.slash);
    await tester.pumpAndSettle();
    final locations = field(tester, 'Search Locations');
    expect(locations.focusNode.hasFocus, isTrue);
    expect(locations.controller.selection.start, 0);
    expect(locations.controller.selection.end, 4);
    expect(locations.controller.text, 'park', reason: 'no "/" typed');
  });

  testWidgets('a field letter goes to its text field, flips its switch, and '
      'not while a text field has focus', (tester) async {
    final hotkeys = Hotkeys();
    final name = TextEditingController(text: 'Home');
    var on = false;
    await tester.pumpWidget(
      MaterialApp(
        navigatorObservers: [hotkeys],
        builder: (context, child) =>
            HotkeyScope(hotkeys: hotkeys, child: child!),
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => Column(
              children: [
                FieldHotkey(
                  'N',
                  child: TextField(
                    controller: name,
                    decoration: const InputDecoration(labelText: 'Name'),
                  ),
                ),
                FieldHotkey(
                  'O',
                  child: SwitchListTile(
                    title: const Text('On'),
                    value: on,
                    onChanged: (v) => setState(() => on = v),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.keyO);
    await tester.pumpAndSettle();
    expect(on, isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.keyN);
    await tester.pumpAndSettle();
    final editable = field(tester, 'Name');
    expect(editable.focusNode.hasFocus, isTrue);
    expect(name.selection, const TextSelection(baseOffset: 0, extentOffset: 4));

    // Typed, in the field: not a hotkey.
    await tester.sendKeyEvent(LogicalKeyboardKey.keyO);
    await tester.pumpAndSettle();
    expect(on, isTrue);
  });

  testWidgets("an action's dialog: Esc leaves its name, and letters then "
      'go to its fields and pick its choices', (tester) async {
    final hotkeys = Hotkeys();
    Map<String, Object?>? saved;
    const action = PlanAction(id: 'tofu', name: 'Tofu', status: 'active');
    await tester.pumpWidget(
      MaterialApp(
        navigatorObservers: [hotkeys],
        builder: (context, child) =>
            HotkeyScope(hotkeys: hotkeys, child: child!),
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => showActionDialog(
              context,
              action,
              actions: const [action],
              save: (_, changes) async {
                saved = changes;
                return const ActionList(actions: [action]);
              },
            ),
            child: const Text('Open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    // N: the name, selected, to type over.
    await tester.sendKeyEvent(LogicalKeyboardKey.keyN);
    await tester.pumpAndSettle();
    final name = field(tester, 'Name');
    expect(name.focusNode.hasFocus, isTrue);
    expect(name.controller.selection.end, 4);
    // Esc leaves the field rather than closing the dialog.
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(name.focusNode.hasFocus, isFalse);

    // S: the next status; P: the next priority; M: a way to commute.
    await tester.sendKeyEvent(LogicalKeyboardKey.keyS);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyP);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyM);
    await tester.pumpAndSettle();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    expect(saved, {'status': 'archived', 'priority': 0, 'commute': true});
  });
}
