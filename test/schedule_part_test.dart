import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:time_tracker_client/models/trait.dart';
import 'package:time_tracker_client/widgets/parts_editor.dart';

void main() {
  testWidgets("a schedule's measure, days and slack are edited, slack only "
      'for what it covers', (tester) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    List<Part>? edited;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async => edited = await showPartsEditor(
              context,
              title: 'Work',
              actions: const {'work': 'Work'},
              parts: const [
                {
                  'id': 'p1',
                  'kind': 'schedule',
                  'action': 'work',
                  'from': '10:00',
                  'to': '18:00',
                  'measure': 'starts',
                },
              ],
            ),
            child: const Text('Open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(find.text('From 10:00'), findsOneWidget);
    expect(find.text('To 18:00'), findsOneWidget);
    expect(find.textContaining('Slack'), findsNothing);

    await tester.tap(find.text('Covers it'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, "Slack: what it needn't cover (optional)"),
      '1h',
    );
    await tester.tap(find.widgetWithText(FilterChip, 'Sat'));
    await tester.tap(find.widgetWithText(FilterChip, 'Sun'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();

    expect(edited, [
      {
        'id': 'p1',
        'kind': 'schedule',
        'action': 'work',
        'from': '10:00',
        'to': '18:00',
        'measure': 'covered',
        'slack_minutes': 60,
        'days': ['mon', 'tue', 'wed', 'thu', 'fri'],
      },
    ]);
  });
}
