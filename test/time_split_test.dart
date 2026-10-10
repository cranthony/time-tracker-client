import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:time_tracker_client/models/event.dart';
import 'package:time_tracker_client/models/note.dart';
import 'package:time_tracker_client/models/time_split.dart';

/// [timeByEvent] as it was, each stretch looking at every event: what the
/// sweep must match.
Map<Event?, Duration> _everyEvent(
  List<Event> events,
  DateTime from,
  DateTime to,
) {
  DateTime clip(DateTime t) =>
      t.isBefore(from) ? from : (t.isAfter(to) ? to : t);
  final shown = [
    for (final event in events)
      if (!event.isCancelled && clip(event.end).isAfter(clip(event.start)))
        event,
  ];
  final edges = {
    from,
    to,
    for (final event in shown) ...[clip(event.start), clip(event.end)],
  }.toList()..sort();
  final time = <Event?, Duration>{};
  for (var i = 0; i + 1 < edges.length; i++) {
    final (start, end) = (edges[i], edges[i + 1]);
    final during = [
      for (final event in shown)
        if (!event.start.isAfter(start) && !event.end.isBefore(end)) event,
    ];
    final length = end.difference(start);
    if (during.isEmpty) time[null] = (time[null] ?? Duration.zero) + length;
    for (final event in during) {
      time[event] = (time[event] ?? Duration.zero) + length ~/ during.length;
    }
  }
  return time;
}

void main() {
  final from = DateTime(2026, 10, 1);
  final to = DateTime(2026, 10, 8);

  Event event(int i, DateTime start, DateTime end, {bool cancelled = false}) =>
      Event.fromJson({
        'id': 'e$i',
        'summary': 'E$i',
        'start': localIsoTimestamp(start),
        'end': localIsoTimestamp(end),
        'is_cancelled': cancelled,
      });

  test('splits the time as it always has: overlaps evenly, gaps to none, '
      'and the ends clipped', () {
    final a = event(1, DateTime(2026, 9, 30, 23), DateTime(2026, 10, 1, 2));
    final b = event(2, DateTime(2026, 10, 1, 1), DateTime(2026, 10, 1, 3));
    final time = timeByEvent([a, b], from, DateTime(2026, 10, 1, 4));
    expect(time[a], const Duration(hours: 1, minutes: 30));
    expect(time[b], const Duration(hours: 1, minutes: 30));
    expect(time[null], const Duration(hours: 1));
  });

  test('matches every event looked at for every stretch, for many events '
      'at random', () {
    final random = Random(7);
    for (var round = 0; round < 50; round++) {
      final events = [
        for (var i = 0; i < 60; i++)
          () {
            // Some before the span, some after, many overlapping, some
            // starting where others end.
            final start = from.add(
              Duration(minutes: (random.nextInt(8 * 24 * 4) - 24 * 4) * 15),
            );
            return event(
              i,
              start,
              start.add(Duration(minutes: 15 * (1 + random.nextInt(16)))),
              cancelled: random.nextInt(10) == 0,
            );
          }(),
      ];
      expect(timeByEvent(events, from, to), _everyEvent(events, from, to));
    }
  });
}
