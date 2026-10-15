import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:time_tracker_client/widgets/picker_search.dart';
import 'package:time_tracker_client/widgets/picker_sheet.dart';
import 'package:time_tracker_client/widgets/tree_picker.dart';

const _places = [
  PickerNode(id: 'bk', label: 'Brooklyn', path: 'Brooklyn', group: true),
  PickerNode(
    id: 'home',
    label: 'Home',
    parentId: 'bk',
    path: 'Brooklyn › Home',
  ),
  PickerNode(id: 'work', label: 'Work', path: 'Work'),
];

void main() {
  testWidgets('searches by every word, picks the top match with Enter, and '
      'shows the picked as chips to take off', (tester) async {
    var picked = <String>[];
    final search = PickerSearch();
    addTearDown(search.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => TreePicker(
              nodes: const [
                PickerNode(id: 'Sam Lee', label: 'Sam Lee'),
                PickerNode(id: 'Priya Shah', label: 'Priya Shah'),
                PickerNode(id: 'Sam Ortiz', label: 'Sam Ortiz'),
              ],
              picked: picked,
              caption: 'Who was there',
              empty: 'No one yet',
              search: search,
              onChanged: (ids) => setState(() => picked = ids),
            ),
          ),
        ),
      ),
    );
    await tester.enterText(find.byType(TextField), 'ortiz sam');
    await tester.pump();
    expect(find.widgetWithText(CheckboxListTile, 'Sam Lee'), findsNothing);
    expect(find.widgetWithText(CheckboxListTile, 'Sam Ortiz'), findsOneWidget);
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(picked, ['Sam Ortiz']);
    // The search cleared, ready for the next.
    expect(find.widgetWithText(CheckboxListTile, 'Priya Shah'), findsOneWidget);

    await tester.tap(find.widgetWithText(CheckboxListTile, 'Priya Shah'));
    await tester.pump();
    expect(picked, ['Sam Ortiz', 'Priya Shah']);
    await tester.tap(
      find.descendant(
        of: find.widgetWithText(InputChip, 'Sam Ortiz'),
        matching: find.byIcon(Icons.clear),
      ),
    );
    await tester.pump();
    expect(picked, ['Priya Shah']);
  });

  testWidgets('a PickerField picks a group with a tap, starts with it open '
      'and its search focused, closes it with its arrow, and picks none', (
    tester,
  ) async {
    String? value;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => PickerField(
              label: 'From',
              nodes: _places,
              value: value,
              none: 'None',
              groupsPickable: true,
              onChanged: (picked) => setState(() => value = picked),
            ),
          ),
        ),
      ),
    );
    Future<void> open() async {
      await tester.tap(find.widgetWithText(InputDecorator, 'From'));
      await tester.pumpAndSettle();
    }

    await open();
    await tester.tap(find.widgetWithText(ListTile, 'Brooklyn'));
    await tester.pumpAndSettle();
    expect(value, 'bk');
    expect(find.byType(BottomSheet), findsNothing);

    await open();
    expect(
      tester.widget<EditableText>(find.byType(EditableText)).focusNode.hasFocus,
      isTrue,
    );
    // Open to start with; its arrow closes it, and opens it, without
    // picking it.
    expect(find.widgetWithText(ListTile, 'Home'), findsOneWidget);
    await tester.tap(find.byTooltip("Hide what's inside"));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(ListTile, 'Home'), findsNothing);
    await tester.tap(find.byTooltip('Show 1 inside'));
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsOneWidget);
    await tester.tap(find.widgetWithText(ListTile, 'Home'));
    await tester.pumpAndSettle();
    expect(value, 'home');
    expect(find.text('Brooklyn › Home'), findsOneWidget);

    await open();
    await tester.tap(find.widgetWithText(ListTile, 'None'));
    await tester.pumpAndSettle();
    expect(value, isNull);
  });

  testWidgets("a group that can't be picked is a folder, open to start "
      'with, closed and opened by a tap', (tester) async {
    var picked = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => TreePicker(
              nodes: _places,
              picked: picked,
              onChanged: (ids) => setState(() => picked = ids),
            ),
          ),
        ),
      ),
    );
    expect(find.widgetWithText(CheckboxListTile, 'Brooklyn'), findsNothing);
    await tester.tap(find.widgetWithText(CheckboxListTile, 'Home'));
    await tester.pump();
    expect(picked, ['home']);
    await tester.tap(find.text('Brooklyn'));
    await tester.pump();
    expect(find.widgetWithText(CheckboxListTile, 'Home'), findsNothing);
    await tester.tap(find.text('Brooklyn'));
    await tester.pump();
    expect(find.widgetWithText(CheckboxListTile, 'Home'), findsOneWidget);
  });
}
