import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:time_tracker_client/widgets/create_mode_icon.dart';
import 'package:time_tracker_client/widgets/new_event_box.dart';

void main() {
  testWidgets("draws the modes Material has no icon for, and shows the "
      "rest's", (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Column(
          children: [
            for (final mode in CreateMode.values) CreateModeIcon(mode),
          ],
        ),
      ),
    );
    final drawn = [
      for (final mode in CreateMode.values)
        if (mode.icon == null) mode,
    ];
    expect(drawn, [CreateMode.trimPush, CreateMode.splitPush]);
    expect(find.byType(Icon), findsNWidgets(CreateMode.values.length - 2));
    for (final mode in drawn) {
      expect(find.bySemanticsLabel(mode.label), findsOneWidget);
      expect(
        tester.getSize(
          find.descendant(
            of: find.byWidgetPredicate(
              (w) => w is CreateModeIcon && w.mode == mode,
            ),
            matching: find.byType(CustomPaint),
          ),
        ),
        const Size.square(24),
      );
    }
  });
}
