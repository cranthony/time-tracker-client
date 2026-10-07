import 'package:flutter_test/flutter_test.dart';
import 'package:time_tracker_client/demo/sample_data.dart';

void main() {
  test("the sample's events never overlap: the one-offs take their time "
      "out of the routine", () async {
    final now = DateTime(2026, 10, 2, 13, 30);
    final events =
        (await SampleData(now).eventsRepository().events(
            now.subtract(const Duration(days: 10)),
            now.add(const Duration(days: 10)),
          )).where((e) => !e.isCancelled).toList()
          ..sort((a, b) => a.start.compareTo(b.start));
    expect(events, isNotEmpty);
    // Each starts no sooner than all before it have ended.
    var last = events.first;
    for (final e in events.skip(1)) {
      expect(
        e.start.isBefore(last.end),
        isFalse,
        reason:
            '${last.summary} (${last.start}–${last.end}) '
            'overlaps ${e.summary} (${e.start}–${e.end})',
      );
      if (e.end.isAfter(last.end)) last = e;
    }
  });
}
