import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:time_tracker_client/widgets/picker_sheet.dart';

void main() {
  testWidgets('searches by every word, picks the top match with Enter, and '
      'shows the picked as chips to take off', (tester) async {
    var picked = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => ListPicker<String>(
              items: const ['Sam Lee', 'Priya Shah', 'Sam Ortiz'],
              id: (name) => name,
              label: (name) => name,
              picked: picked,
              hint: 'Who was there',
              empty: 'No one yet',
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
}
