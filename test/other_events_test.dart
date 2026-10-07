import 'package:flutter_test/flutter_test.dart';
import 'package:time_tracker_client/models/event.dart';
import 'package:time_tracker_client/models/note.dart';
import 'package:time_tracker_client/widgets/other_events.dart';

void main() {
  DateTime at(int hour, [int minute = 0]) =>
      DateTime(2026, 9, 30, hour, minute);

  final others = OtherEvents([
    Event(id: 'a', start: at(8), end: at(8, 50)),
    Event(id: 'me', start: at(9), end: at(10, 30)),
    Event(id: 'b', start: at(11), end: at(12)),
    Event(id: 'x', start: at(9, 30), end: at(9, 45), isCancelled: true),
  ], except: 'me');

  test('leaves out the event itself and cancelled ones', () {
    expect([for (final e in others.events) e.id], ['a', 'b']);
  });

  test('finds the free time either side', () {
    expect(others.earliestStart(at(9)), at(8, 50));
    expect(others.latestEnd(at(10, 30)), at(11));
    expect(others.earliestStart(at(8)), isNull);
    expect(others.latestEnd(at(12)), isNull);
  });

  test('the quick buttons step by quarter hours, up to the events '
      'either side', () {
    expect(others.earlierStart(at(9)), at(8, 50));
    expect(others.earlierStart(at(8, 50)), isNull);
    expect(others.earlierStart(at(9, 10)), at(9));
    expect(others.laterStart(at(9), at(10, 30)), at(9, 15));
    // Never shorter than a quarter hour.
    expect(others.laterStart(at(10, 15), at(10, 30)), isNull);
    expect(others.earlierEnd(at(9), at(10, 30)), at(10, 15));
    expect(others.earlierEnd(at(9), at(9, 15)), isNull);
    expect(others.laterEnd(at(10, 30)), at(10, 45));
    expect(others.laterEnd(at(10, 50)), at(11));
    expect(others.laterEnd(at(11)), isNull);
    expect(
      const OtherEvents.none().laterEnd(at(23, 50)),
      DateTime(2026, 10, 1),
    );
  });

  test('a picked start inside an event moves to its end, keeping the '
      'length until the next', () {
    expect(others.moveStart(at(8, 30), const Duration(hours: 1)), (
      at(8, 50),
      at(9, 50),
    ));
    expect(others.moveStart(at(10, 30), const Duration(hours: 1)), (
      at(10, 30),
      at(11),
    ));
  });

  test('a picked end past the next event comes back to its start', () {
    expect(others.fitEnd(at(9), at(11, 30)), at(11));
    expect(others.fitEnd(at(9), at(10, 45)), at(10, 45));
  });

  test('says what a time would overlap', () {
    expect(others.overlapping(at(10), at(11, 15))?.id, 'b');
    expect(others.overlapping(at(8, 50), at(11)), isNull);
  });

  test('overwriting cancels what it covers, shortens what it overlaps, and '
      'splits what it falls inside of', () {
    final others = OtherEvents([
      Event.fromJson({
        'id': 'long',
        'summary': 'Work',
        'start': localIsoTimestamp(at(8)),
        'end': localIsoTimestamp(at(16)),
        'action_ids': ['work'],
        'judgments': {'self': {}},
      }),
    ]);
    final split = others.overwrite(at(12), at(13));
    expect(split.cancels, isEmpty);
    expect(split.updates.single.$2, {'end': localIsoTimestamp(at(12))});
    expect(split.creates.single, {
      'summary': 'Work',
      'action_ids': ['work'],
      'start': localIsoTimestamp(at(13)),
      'end': localIsoTimestamp(at(16)),
    });

    final around = OtherEvents([
      Event(id: 'before', start: at(9), end: at(11)),
      Event(id: 'inside', start: at(11, 30), end: at(12)),
      Event(id: 'after', start: at(12, 30), end: at(14)),
      Event(id: 'clear', start: at(14), end: at(15)),
    ]);
    final over = around.overwrite(at(10), at(13));
    expect([for (final e in over.cancels) e.id], ['inside']);
    expect([for (final (e, _) in over.updates) e.id], ['before', 'after']);
    expect(over.updates.first.$2, {'end': localIsoTimestamp(at(10))});
    expect(over.updates.last.$2, {'start': localIsoTimestamp(at(13))});
    expect(over.creates, isEmpty);
    expect(over.count, 3);
  });

  test('a box fits from its anchor: out of an event, keeping its length, '
      'and no further than the next', () {
    // Out of 'me' isn't counted: a at 8-8:50, b at 11-12.
    expect(others.fitFrom(at(9), at(10)), (at(9), at(10)));
    // From inside a, its end; an hour, then.
    expect(others.fitFrom(at(8, 30), at(9, 30)), (at(8, 50), at(9, 50)));
    // Down to b, no further.
    expect(others.fitFrom(at(10), at(11, 30)), (at(10), at(11)));
    // Upward: from inside b, its start; no further up than a's end.
    expect(others.fitFrom(at(11, 30), at(10)), (at(11), at(9, 30)));
    expect(others.fitFrom(at(10), at(8)), (at(10), at(8, 50)));
  });

  test('a box moved fits as near as it can, or fills the nearest gap', () {
    // Free: before 8, 8:50-11, after 12.
    expect(
      others.fitMoved(
        at(10, 30),
        const Duration(hours: 1),
        from: at(0),
        to: at(24),
      ),
      (at(10), at(11)),
    );
    expect(
      others.fitMoved(
        at(11, 15),
        const Duration(hours: 1),
        from: at(0),
        to: at(24),
      ),
      (at(12), at(13)),
    );
    expect(
      others.fitMoved(at(7), const Duration(hours: 1), from: at(0), to: at(24)),
      (at(7), at(8)),
    );
    final tight = OtherEvents([
      Event(id: 'x', start: at(9), end: at(10)),
      Event(id: 'y', start: at(10, 30), end: at(11)),
      Event(id: 'z', start: at(11, 20), end: at(12)),
    ]);
    // Three hours can go before 9 (moved 4 hours) or after 12 (moved 2).
    expect(
      tight.fitMoved(at(10), const Duration(hours: 3), from: at(0), to: at(24)),
      (at(12), at(15)),
    );
    // An hour fits nowhere near: the nearest gap, filled.
    final tighter = OtherEvents([
      Event(id: 'x', start: at(0), end: at(10)),
      Event(id: 'y', start: at(10, 30), end: at(11)),
      Event(id: 'z', start: at(11, 20), end: at(23)),
    ]);
    expect(
      tighter.fitMoved(
        at(11),
        const Duration(hours: 2),
        from: at(0),
        to: at(24),
      ),
      (at(11), at(11, 20)),
    );
  });
}
