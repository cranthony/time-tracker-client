import 'package:flutter_test/flutter_test.dart';
import 'package:time_tracker_client/models/event.dart';
import 'package:time_tracker_client/widgets/event_room.dart';

void main() {
  DateTime at(int hour, [int minute = 0]) =>
      DateTime(2026, 9, 30, hour, minute);

  final room = EventRoom([
    Event(id: 'a', start: at(8), end: at(8, 50)),
    Event(id: 'me', start: at(9), end: at(10, 30)),
    Event(id: 'b', start: at(11), end: at(12)),
    Event(id: 'x', start: at(9, 30), end: at(9, 45), isCancelled: true),
  ], except: 'me');

  test('leaves out the event itself and cancelled ones', () {
    expect([for (final e in room.others) e.id], ['a', 'b']);
  });

  test('finds the free time either side', () {
    expect(room.earliestStart(at(9)), at(8, 50));
    expect(room.latestEnd(at(10, 30)), at(11));
    expect(room.earliestStart(at(8)), isNull);
    expect(room.latestEnd(at(12)), isNull);
  });

  test('the quick buttons step by quarter hours, up to the events '
      'either side', () {
    expect(room.earlierStart(at(9)), at(8, 50));
    expect(room.earlierStart(at(8, 50)), isNull);
    expect(room.earlierStart(at(9, 10)), at(9));
    expect(room.laterStart(at(9), at(10, 30)), at(9, 15));
    // Never shorter than a quarter hour.
    expect(room.laterStart(at(10, 15), at(10, 30)), isNull);
    expect(room.earlierEnd(at(9), at(10, 30)), at(10, 15));
    expect(room.earlierEnd(at(9), at(9, 15)), isNull);
    expect(room.laterEnd(at(10, 30)), at(10, 45));
    expect(room.laterEnd(at(10, 50)), at(11));
    expect(room.laterEnd(at(11)), isNull);
    expect(const EventRoom.none().laterEnd(at(23, 50)), DateTime(2026, 10, 1));
  });

  test('a picked start inside an event moves to its end, keeping the '
      'length until the next', () {
    expect(room.moveStart(at(8, 30), const Duration(hours: 1)), (
      at(8, 50),
      at(9, 50),
    ));
    expect(room.moveStart(at(10, 30), const Duration(hours: 1)), (
      at(10, 30),
      at(11),
    ));
  });

  test('a picked end past the next event comes back to its start', () {
    expect(room.fitEnd(at(9), at(11, 30)), at(11));
    expect(room.fitEnd(at(9), at(10, 45)), at(10, 45));
  });

  test('says what a time would overlap', () {
    expect(room.overlapping(at(10), at(11, 15))?.id, 'b');
    expect(room.overlapping(at(8, 50), at(11)), isNull);
  });
}
