import 'package:flutter_test/flutter_test.dart';
import 'package:time_tracker_client/widgets/cursor_snap.dart';

void main() {
  DateTime at(int hour, [int minute = 0]) =>
      DateTime(2026, 10, 8, hour, minute);
  CursorStops stops({
    Duration? grid = const Duration(minutes: 15),
    List<DateTime> edges = const [],
    List<DateTime> notes = const [],
  }) => CursorStops(
    from: at(0),
    to: DateTime(2026, 10, 9),
    grid: grid,
    edges: edges,
    notes: notes,
  );

  group('next', () {
    test("steps to the grid's next line, either way", () {
      expect(stops().next(at(9), later: true), at(9, 15));
      expect(stops().next(at(9), later: false), at(8, 45));
      // Off the grid: to the line past it.
      expect(stops().next(at(9, 7), later: true), at(9, 15));
      expect(stops().next(at(9, 7), later: false), at(9));
    });

    test('stops at an edge or a note before the line', () {
      final s = stops(edges: [at(9, 10)], notes: [at(9, 5)]);
      expect(s.next(at(9), later: true), at(9, 5));
      expect(s.next(at(9, 5), later: true), at(9, 10));
      expect(s.next(at(9, 10), later: true), at(9, 15));
      expect(s.next(at(9, 15), later: false), at(9, 10));
    });

    test("from the server's times, in UTC: on from the line it's on", () {
      final utc = at(9).toUtc();
      final s = stops(edges: [utc]);
      expect(s.next(utc, later: true), at(9, 15));
      expect(s.next(utc, later: false), at(8, 45));
    });

    test('with no grid, a minute at a time; none past the ends', () {
      expect(stops(grid: null).next(at(9), later: true), at(9, 1));
      expect(stops().next(at(0), later: false), isNull);
    });

    // The day the clocks fall back, where this machine's zone has one:
    // 25 hours long, so after the repeated hour the time since midnight
    // runs an hour ahead of the clock. Lines are by the clock.
    final fallBack = [DateTime(2026, 10, 25), DateTime(2026, 11, 1)]
        .where(
          (d) =>
              DateTime(d.year, d.month, d.day + 1).difference(d) ==
              const Duration(hours: 25),
        )
        .firstOrNull;
    test('by the clock, on the day the clocks fall back', () {
      final day = fallBack!;
      final s = CursorStops(
        from: day,
        to: DateTime(day.year, day.month, day.day + 1),
        grid: const Duration(minutes: 15),
      );
      final ten = DateTime(day.year, day.month, day.day, 10);
      expect(s.next(ten, later: true), ten.add(const Duration(minutes: 15)));
      expect(
        s.next(ten, later: false),
        ten.subtract(const Duration(minutes: 15)),
      );
    }, skip: fallBack == null ? 'no fall-back day in this time zone' : false);
  });

  group('nearest', () {
    const reach = Duration(minutes: 4);

    test('an edge or note within reach, the nearest', () {
      final s = stops(edges: [at(9, 10)], notes: [at(9, 13)]);
      expect(s.nearest(at(9, 11), reach: reach), at(9, 10));
      expect(s.nearest(at(9, 12), reach: reach), at(9, 13));
    });

    test("else the grid's nearest line", () {
      final s = stops(edges: [at(9, 10)]);
      expect(s.nearest(at(9, 22), reach: reach), at(9, 15));
      expect(stops(grid: null).nearest(at(9, 22), reach: reach), at(9, 22));
    });
  });
}
