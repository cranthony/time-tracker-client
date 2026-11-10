// The quick New goal sheet, active and inactive, on a phone and wider, in
// build/screenshots/.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:time_tracker_client/widgets/goal_sheet.dart';

void main() {
  final now = DateTime(2026, 11, 10, 9, 30);

  Future<void> open(WidgetTester tester, double width) async {
    tester.view.physicalSize = Size(width, 520);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showAddGoalSheet(
                context,
                keep: (_) async {},
                title: 'Book the dentist',
                now: () => now,
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

  for (final (name, width) in [('phone', 412.0), ('wide', 760.0)]) {
    testWidgets('active, on a $name', (tester) async {
      await open(tester, width);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goal_sheet_active_$name.png'),
      );
    });

    testWidgets('inactive, on a $name', (tester) async {
      await open(tester, width);
      await tester.tap(find.text('Starts'));
      await tester.pumpAndSettle();
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goal_sheet_inactive_$name.png'),
      );
    });
  }
}
