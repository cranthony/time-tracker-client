import 'package:flutter_test/flutter_test.dart';
import 'package:time_tracker_client/widgets/pending_event_box.dart';

/// Holds [finder] down for [holdToDrag], then drags it [by]: how the
/// pending event box, and its "+"s, are moved.
Future<void> holdAndDrag(WidgetTester tester, Finder finder, Offset by) async {
  final gesture = await tester.startGesture(
    tester.getCenter(finder, warnIfMissed: false),
  );
  await tester.pump(holdToDrag + const Duration(milliseconds: 50));
  for (var i = 0; i < 4; i++) {
    await gesture.moveBy(by / 4);
    await tester.pump();
  }
  await gesture.up();
  await tester.pump();
}
