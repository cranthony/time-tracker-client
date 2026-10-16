import 'package:flutter_test/flutter_test.dart';
import 'package:time_tracker_client/models/event.dart';
import 'package:time_tracker_client/models/note.dart';
import 'package:time_tracker_client/widgets/event_lists.dart';
import 'package:time_tracker_client/widgets/other_events.dart';

void main() {
  DateTime at(int hour, [int minute = 0]) =>
      DateTime(2026, 9, 30, hour, minute);
  String t(DateTime time) => localIsoTimestamp(time);
  Event event(String id, DateTime start, DateTime end) =>
      Event(id: id, start: start, end: end, summary: id.toUpperCase());

  /// [o] as ids, changes, and the new events' times, to compare.
  String shown(Overwrite o) => [
    [for (final e in o.cancels) e.id],
    {for (final (e, fields) in o.updates) e.id: fields},
    [for (final c in o.creates) (c['start'], c['end'])],
  ].toString();

  BoxEffect effect(
    List<Event> events,
    DateTime start,
    DateTime end, {
    Map<EventList, Set<String>> lists = const {},
  }) => BoxEffect(OtherEvents(events), start: start, end: end, lists: lists);

  group('with no lists, it trims, as overwriting did', () {
    final events = [
      event('a', at(9), at(10, 30)),
      event('b', at(10, 45), at(11)),
      event('c', at(11, 30), at(13)),
    ];

    test('shortening, cancelling, and the start moved on', () {
      expect(
        shown(effect(events, at(10), at(12)).overwrite),
        shown(OtherEvents(events).overwrite(at(10), at(12))),
      );
    });

    test('splitting one it falls inside of', () {
      expect(
        shown(effect(events, at(12), at(12, 30)).overwrite),
        shown(OtherEvents(events).overwrite(at(12), at(12, 30))),
      );
    });
  });

  test('pushed down: moved whole to below the box, one after another, '
      'what they run into trimmed', () {
    final e = effect(
      [
        event('a', at(10, 30), at(11, 30)),
        event('b', at(11, 30), at(12)),
        event('c', at(12, 10), at(13)),
      ],
      at(10),
      at(11),
      lists: {
        EventList.pushDown: {'a', 'b'},
      },
    );
    expect(e.span, (at(10), at(12, 30)));
    expect(
      shown(e.overwrite),
      shown(
        Overwrite(
          updates: [
            (
              event('a', at(10, 30), at(11, 30)),
              {'start': t(at(11)), 'end': t(at(12))},
            ),
            (
              event('b', at(11, 30), at(12)),
              {'start': t(at(12)), 'end': t(at(12, 30))},
            ),
            (event('c', at(12, 10), at(13)), {'start': t(at(12, 30))}),
          ],
        ),
      ),
    );
    expect(e.blocked, isFalse);
  });

  test("pushed up: to just above the box; one the box doesn't reach, left", () {
    final e = effect(
      [event('a', at(9, 30), at(10, 30)), event('z', at(7), at(8))],
      at(10),
      at(11),
      lists: {
        EventList.pushUp: {'a', 'z'},
      },
    );
    expect(e.span, (at(9), at(11)));
    expect(
      shown(e.overwrite),
      shown(
        Overwrite(
          updates: [
            (
              event('a', at(9, 30), at(10, 30)),
              {'start': t(at(9)), 'end': t(at(10))},
            ),
          ],
        ),
      ),
    );
  });

  test('an event to keep in the way: blocked', () {
    final e = effect(
      [event('a', at(10, 30), at(11, 30)), event('k', at(11, 45), at(12))],
      at(10),
      at(11),
      lists: {
        EventList.pushDown: {'a'},
        EventList.keep: {'k'},
      },
    );
    // A pushed to 11-12, into K.
    expect(e.blocked, isTrue);
    expect(
      effect(
        [event('k', at(11), at(12))],
        at(10),
        at(11),
        lists: {
          EventList.keep: {'k'},
        },
      ).blocked,
      isFalse,
    );
  });

  test('to cancel: cancelled whole, wherever it is', () {
    final e = effect(
      [event('x', at(15), at(16))],
      at(10),
      at(11),
      lists: {
        EventList.cancel: {'x'},
      },
    );
    expect(
      shown(e.overwrite),
      shown(Overwrite(cancels: [event('x', at(15), at(16))])),
    );
  });

  group("one to push that sticks out of the box, split at the box's edge", () {
    // A, 11-3; the box, 12-1.
    final a = Event(
      id: 'a',
      start: at(11),
      end: at(15),
      summary: 'A',
      properties: const {
        'summary': 'A',
        'description': 'Lunch and a walk',
        'action_ids': ['eat'],
        'actions_from_label': true,
        'priority': 2,
        'facts': {
          'notes': {'self': 'Sunny'},
        },
        'judgments': {
          'self': {
            'calm': {
              'mood': {'rating': 4, 'scale': 5},
            },
          },
        },
        'recurring_event_id': 'series',
      },
    );

    test('pushed down: the part above the box kept, the rest pushed whole, '
        'just below it', () {
      final e = effect(
        [a],
        at(12),
        at(13),
        lists: {
          EventList.pushDown: {'a'},
        },
      );
      expect(
        shown(e.overwrite),
        shown(
          Overwrite(
            updates: [
              (a, {'end': t(at(12))}),
            ],
            creates: [
              {'start': t(at(13)), 'end': t(at(16))},
            ],
          ),
        ),
      );
      expect(e.pushed, [(a, at(13), at(16), true)]);
      expect(e.span, (at(12), at(16)));
    });

    test('pushed up: the part below the box kept, the rest pushed whole, '
        'just above it', () {
      final e = effect(
        [a],
        at(12),
        at(13),
        lists: {
          EventList.pushUp: {'a'},
        },
      );
      expect(
        shown(e.overwrite),
        shown(
          Overwrite(
            updates: [
              (a, {'start': t(at(13))}),
            ],
            creates: [
              {'start': t(at(10)), 'end': t(at(12))},
            ],
          ),
        ),
      );
      expect(e.pushed, [(a, at(10), at(12), true)]);
    });

    test('nothing of it on the kept side: pushed whole, itself', () {
      final e = effect(
        [a],
        at(11),
        at(12),
        lists: {
          EventList.pushDown: {'a'},
        },
      );
      expect(
        shown(e.overwrite),
        shown(
          Overwrite(
            updates: [
              (a, {'start': t(at(12)), 'end': t(at(16))}),
            ],
          ),
        ),
      );
    });

    test('the part pushed, as the event: everything of it that can be '
        'written but its id and times', () {
      final rest = effect(
        [a],
        at(12),
        at(13),
        lists: {
          EventList.pushDown: {'a'},
        },
      ).overwrite.creates.single;
      expect(rest, {
        'summary': 'A',
        'description': 'Lunch and a walk',
        'action_ids': ['eat'],
        'actions_from_label': true,
        'priority': 2,
        'facts': {
          'notes': {'self': 'Sunny'},
        },
        'judgments': {
          'self': {
            'calm': {
              'mood': {'rating': 4, 'scale': 5},
            },
          },
        },
        'start': t(at(13)),
        'end': t(at(16)),
      });
    });

    test('with no list, trimmed around the box as before', () {
      expect(
        shown(effect([a], at(12), at(13)).overwrite),
        shown(OtherEvents([a]).overwrite(at(12), at(13))),
      );
    });
  });
}
