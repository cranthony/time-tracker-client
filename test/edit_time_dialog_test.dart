import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:time_tracker_client/widgets/cursor_sheet.dart';

void main() {
  final day = DateTime(2026, 9, 30);

  Future<DateTime? Function()> open(
    WidgetTester tester,
    DateTime initial,
  ) async {
    DateTime? picked;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async => picked = await showEditTimeDialog(
              context,
              title: 'Its time',
              initial: initial,
              day: day,
              first: DateTime(2026, 9, 29),
              last: DateTime(2026, 10, 2),
            ),
            child: const Text('Open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    return () => picked;
  }

  Future<void> tap(WidgetTester tester, String tooltip) async {
    await tester.tap(find.byTooltip(tooltip));
    await tester.pumpAndSettle();
  }

  bool enabled(WidgetTester tester, String tooltip) =>
      tester
          .widget<IconButton>(
            find
                .ancestor(
                  of: find.byTooltip(tooltip),
                  matching: find.byType(IconButton),
                )
                .first,
          )
          .onPressed !=
      null;

  testWidgets('a minute past 59 carries into the hour, and an hour past 23 '
      'into the day', (tester) async {
    final picked = await open(tester, DateTime(2026, 9, 30, 23, 59));
    expect(find.text('+0'), findsOneWidget);

    await tap(tester, 'One minute later');
    expect(find.text('+1'), findsOneWidget);
    expect(find.text('00'), findsNWidgets(2));
    // A day either side of the timeline's, no more.
    expect(enabled(tester, 'One day later'), isFalse);
    await tap(tester, 'One hour earlier');
    expect(find.text('+0'), findsOneWidget);
    expect(find.text('23'), findsOneWidget);
    await tap(tester, 'One day earlier');
    expect(find.text('−1'), findsOneWidget);
    expect(enabled(tester, 'One day earlier'), isFalse);

    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(picked(), DateTime(2026, 9, 29, 23));
  });

  testWidgets('called off, nothing', (tester) async {
    final picked = await open(tester, DateTime(2026, 9, 30, 9));
    await tap(tester, 'One hour later');
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(picked(), isNull);
  });
}
