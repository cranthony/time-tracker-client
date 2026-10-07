import 'package:flutter_test/flutter_test.dart';
import 'package:time_tracker_client/models/event.dart';
import 'package:time_tracker_client/models/habit.dart';
import 'package:time_tracker_client/models/note.dart';
import 'package:time_tracker_client/models/person.dart';
import 'package:time_tracker_client/models/trait.dart';
import 'package:time_tracker_client/models/trait_scores.dart';

/// The day scored: Thursday, October 1st, midnight to midnight.
final _start = DateTime(2026, 10, 1);
final _end = DateTime(2026, 10, 2);

const _sam = Person(id: 'sam', name: 'Sam');
const _self = Person(id: selfPersonId, name: 'Self');

/// An event [daysAgo] days before [_end], at [hour] for [hours], with Sam
/// or for him, of [actions], judged [judgments].
Event _event(
  String id,
  num daysAgo, {
  int hour = 12,
  int hours = 1,
  List<String> actions = const [],
  List<String> withIds = const [],
  List<String> forIds = const [],
  Map<String, Object?>? judgments,
}) {
  final start = DateTime(_end.year, _end.month, _end.day)
      .subtract(Duration(minutes: (daysAgo * 24 * 60).round()))
      .add(Duration(hours: hour));
  return Event.fromJson({
    'id': id,
    'summary': id,
    'start': localIsoTimestamp(start),
    'end': localIsoTimestamp(start.add(Duration(hours: hours))),
    'action_ids': actions,
    'facts': {'with_ids': withIds, 'for_ids': forIds},
    'judgments': ?judgments,
  });
}

Trait _trait(List<Part> parts) => Trait(id: 't', name: 'T', parts: parts);

/// Sam's score of a trait made of [parts], from [events], and its parts'.
TraitScore _score(
  List<Part> parts,
  List<Event> events, {
  Person person = _sam,
  String? Function(String id)? parentOf,
}) => scorePerson(
  person,
  [_trait(parts)],
  _start,
  _end,
  events,
  parentOf: parentOf,
).single;

const _judgment = {
  'kind': 'judgment',
  'rubric': 'New?',
  'ratings': {'0': 'No', '1': 'A little', '2': 'Yes'},
  'facts': ['action'],
};

Map<String, Object?> _judged(
  String person,
  int rating, {
  String key = 'judgment',
}) => {
  person: {
    't': {
      key: {'rating': rating, 'scale': 2},
    },
  },
};

void main() {
  test('parts are keyed by kind, then kind#2 for a second', () {
    expect(
      partKeys([
        {'kind': 'judgment'},
        {'kind': 'count'},
        {'kind': 'judgment'},
      ]),
      ['judgment', 'count', 'judgment#2'],
    );
  });

  test('reach says how far back and ahead the parts read', () {
    expect(reach([]), (back: 30, ahead: 0));
    expect(
      reach([
        {'kind': 'count', 'target': 1, 'interval_days': 14, 'zero_at_days': 45},
        {'kind': 'continuity', 'next_within_days': 21},
      ]),
      (back: 45, ahead: 21),
    );
  });

  group('a judgment', () {
    test("is the mean of the person's judgments in its window, as a share "
        'of their scale', () {
      final score = _score(
        [_judgment],
        [
          _event('a', 1, withIds: ['sam'], judgments: _judged('sam', 2)),
          _event('b', 5, withIds: ['sam'], judgments: _judged('sam', 1)),
          // Too long ago, someone else's, or after the day.
          _event('old', 31, withIds: ['sam'], judgments: _judged('sam', 0)),
          _event('other', 2, withIds: ['sam'], judgments: _judged('jo', 0)),
          _event('later', -1, withIds: ['sam'], judgments: _judged('sam', 0)),
        ],
      );

      expect(score.score, 75);
      final part = score.parts.single;
      expect(part.said, 'Mean of 2 judgment(s) in the last 30 days');
      expect(part.eventIds, ['a', 'b']);
      expect(part.judgments.map((j) => j.rating), [2, 1]);
    });

    test("reads only the events they were at, or for them, by its "
        'engagement; Self is at every one', () {
      final events = [
        _event('with', 1, withIds: ['sam'], judgments: _judged('sam', 2)),
        _event('for', 2, forIds: ['sam'], judgments: _judged('sam', 0)),
        _event('alone', 3, judgments: _judged(selfPersonId, 1)),
      ];

      expect(_score([_judgment], events).score, 100);
      expect(
        _score([
          {..._judgment, 'engagement_type': 'for'},
        ], events).score,
        0,
      );
      expect(_score([_judgment], events, person: _self).score, 50);
    });

    test('has no score with nothing judged', () {
      final score = _score(
        [_judgment],
        [
          _event('a', 1, withIds: ['sam']),
        ],
      );

      expect(score.score, isNull);
      expect(score.parts.single.said, 'No judgments in the last 30 days');
    });
  });

  group('continuity', () {
    const part = {
      'kind': 'continuity',
      'last_within_days': 7,
      'next_within_days': 7,
    };

    test('is 100 for an event recently and one soon, 50 for one, 0 for '
        'neither', () {
      expect(
        _score(
          [part],
          [
            _event('last', 3, withIds: ['sam']),
            _event('next', -3, withIds: ['sam']),
          ],
        ).score,
        100,
      );
      expect(
        _score(
          [part],
          [
            _event('last', 3, withIds: ['sam']),
          ],
        ).score,
        50,
      );
      expect(
        _score(
          [part],
          [
            _event('long ago', 10, withIds: ['sam']),
            _event('far off', -10, withIds: ['sam']),
          ],
        ).score,
        0,
      );
      expect(
        _score(
          [part],
          [
            _event('next', -3, hour: 0, withIds: ['sam']),
          ],
        ).parts.single.said,
        'None before; next in 3 days (within 7 and 7 days)',
      );
    });
  });

  group('a count', () {
    test('is its events in the interval against the target, capped at 100', () {
      const part = {'kind': 'count', 'target': 4, 'interval_days': 7};
      final score = _score(
        [part],
        [
          for (final day in [1, 2, 3]) _event('e$day', day, withIds: ['sam']),
          _event('old', 8, withIds: ['sam']),
        ],
      );

      expect(score.score, 75);
      expect(score.parts.single.said, '3 of 4 events in the last 7 days');
      expect(
        _score(
          [part],
          [
            for (final day in [1, 2, 3, 4, 5])
              _event('e$day', day, withIds: ['sam']),
          ],
        ).score,
        100,
      );
    });

    test("counts only its action's events, or those of any action in its "
        'group', () {
      const part = {
        'kind': 'count',
        'action': 'social',
        'target': 2,
        'interval_days': 7,
      };
      final events = [
        _event('call', 1, actions: ['call'], withIds: ['sam']),
        _event('visit', 2, actions: ['visit'], withIds: ['sam']),
        _event('work', 3, actions: ['work'], withIds: ['sam']),
      ];
      final groups = {
        'call': 'social',
        'visit': 'in_person',
        'in_person': 'social',
      };

      expect(_score([part], events, parentOf: (id) => groups[id]).score, 100);
      expect(_score([part], events).score, 0);
    });

    test('with zero_at, falls from 100 when it was last met to 0 by then', () {
      const part = {
        'kind': 'count',
        'target': 1,
        'interval_days': 7,
        'zero_at_days': 17,
      };
      // Last met until 5 days ago (an event 12 days ago left the window
      // then): 5 of the 10 days' grace gone.
      final score = _score(
        [part],
        [
          _event('call', 12, hour: 0, withIds: ['sam']),
        ],
      );

      expect(score.score, closeTo(50, 1));
      expect(score.parts.single.said, contains('0 after 17 days'));
      expect(
        _score(
          [part],
          [
            _event('call', 30, withIds: ['sam']),
          ],
        ).score,
        0,
      );
    });
  });

  test('a duration is the minutes in its interval against its target', () {
    const part = {'kind': 'duration', 'target_min': 240, 'interval_days': 7};
    final score = _score(
      [part],
      [
        _event('a', 1, hours: 2, withIds: ['sam']),
        _event('b', 2, hours: 1, withIds: ['sam']),
      ],
    );

    expect(score.score, 75);
    expect(score.parts.single.said, '180 of 240 minutes in the last 7 days');
  });

  group('follow-through', () {
    /// Sam, with the events the user cancelled that count against him.
    Person samWith(List<CancelledEvent> cancelled) =>
        Person(id: 'sam', name: 'Sam', cancelledEvents: cancelled);

    /// A cancellation [daysAgo] days before [_end], at noon.
    CancelledEvent cancelled(
      int daysAgo, {
      String engagement = 'with',
      List<String> actions = const [],
    }) {
      final start = DateTime(_end.year, _end.month, _end.day - daysAgo, 12);
      return CancelledEvent(
        eventId: 'c$daysAgo',
        summary: 'Coffee',
        start: start,
        end: start.add(const Duration(hours: 1)),
        engagement: engagement,
        actionIds: actions,
        parts: const ['t/follow_through'],
        source: 'delete_event',
      );
    }

    test('loses the penalty per cancellation and wins back the recovery '
        'each day one was kept', () {
      const part = {'kind': 'follow_through'};
      final sam = samWith([cancelled(4), cancelled(4)]);

      // 50 after two on one day; back to 75 on the day an event was kept.
      final kept = _score(
        [part],
        [
          _event('a', 1, withIds: ['sam']),
        ],
        person: sam,
      );
      expect(kept.score, 75);
      expect(kept.parts.single.said, '1 kept (+25) that day, from 50');
      expect(kept.parts.single.eventIds, ['a']);

      final none = _score([part], const [], person: sam);
      expect(none.score, 50);
      expect(
        none.parts.single.said,
        'Nothing cancelled or kept that day, from 50',
      );

      // Its own penalty, and only as far back as it looks.
      expect(
        _score(
          [
            {'kind': 'follow_through', 'penalty': 10},
          ],
          const [],
          person: sam,
        ).score,
        80,
      );
      expect(
        _score(
          [
            {'kind': 'follow_through', 'look_back_days': 3},
          ],
          const [],
          person: sam,
        ).score,
        100,
      );
    });

    test('counts only cancellations of its engagement, and its action', () {
      final sam = samWith([
        cancelled(2, engagement: 'for'),
        cancelled(3, actions: ['work']),
      ]);

      expect(
        _score(
          [
            const {'kind': 'follow_through'},
          ],
          const [],
          person: sam,
        ).score,
        75,
      );
      expect(
        _score(
          [
            const {'kind': 'follow_through', 'engagement_type': 'for'},
          ],
          const [],
          person: sam,
        ).score,
        75,
      );
      expect(
        _score(
          [
            const {'kind': 'follow_through', 'action': 'social'},
          ],
          const [],
          person: sam,
        ).score,
        100,
      );
    });

    test("are read from a person, as the server lists them", () {
      final person = Person.fromJson({
        'id': 'dad',
        'name': 'Dad',
        'cancelled_events': [
          {
            'event_id': 'e1',
            'summary': 'Visit',
            'start': '2026-10-01T10:00:00',
            'end': '2026-10-01T11:00:00',
            'action_ids': ['deep_talk'],
            'engagement': 'with',
            'parts': ['reliable/follow_through', 'reliable/follow_through#2'],
            'cancelled_at': '2026-10-02T09:00:00',
            'source': 'compaction c-1',
          },
          {'summary': 'No time'},
        ],
      });

      final visit = person.cancelledEvents.single;
      expect(visit.start, DateTime(2026, 10, 1, 10));
      expect(visit.traitIds, ['reliable']);
      expect(visit.byCompaction, isTrue);
      // Kept apart from them: not sent back.
      expect(person.toJson().containsKey('cancelled_events'), isFalse);
    });
  });

  test("a trait is its parts' weighted mean, leaving out those with no "
      'score and those that aren\'t well formed', () {
    final score = _score(
      [
        {'kind': 'count', 'target': 1, 'interval_days': 7, 'weight': 3},
        {'kind': 'continuity', 'last_within_days': 7, 'next_within_days': 7},
        _judgment,
        {'kind': 'count'},
      ],
      [
        _event('a', 1, withIds: ['sam']),
      ],
    );

    // (100 x 3 + 50) / 4.
    expect(score.score, 88);
    expect(score.parts.last.weight, 0);
    expect(score.parts.last.said, startsWith('Not scored'));
  });

  test("only the active traits that apply to someone score them, with "
      'their own parts', () {
    final traits = [
      _trait([_judgment]),
      const Trait(id: 'off', name: 'Off', status: 'off', parts: [_judgment]),
      const Trait(
        id: 'own',
        name: 'Own',
        parts: [
          {'kind': 'count', 'target': 1},
        ],
      ),
    ];
    const jo = Person(
      id: 'jo',
      name: 'Jo',
      traits: PersonTraits(
        select: ['own'],
        parts: {
          'own': [
            {'kind': 'count', 'target': 2},
          ],
        },
      ),
    );

    final scores = scorePerson(jo, traits, _start, _end, [
      _event('a', 1, withIds: ['jo']),
    ]);
    expect([for (final s in scores) s.traitId], ['own']);
    expect(scores.single.score, 50);
  });

  group('TraitScores', () {
    final today = DateTime(2026, 10, 8);
    TraitScores compute(List<Event> events) => TraitScores.compute(
      traits: [
        _trait([_judgment]),
      ],
      people: const [
        _self,
        _sam,
        Person(id: 'jo', name: 'Jo'),
      ],
      events: events,
      today: today,
    );

    test("scores each of the last week's days; a trait's day is everyone's "
        'mean', () {
      // Two days before today: Sam 2 of 2, Self 1 of 2.
      final scores = compute([
        Event.fromJson({
          'id': 'dinner',
          'start': localIsoTimestamp(DateTime(2026, 10, 6, 18)),
          'end': localIsoTimestamp(DateTime(2026, 10, 6, 20)),
          'facts': {
            'with_ids': ['sam'],
            'location_id': 'home',
          },
          'action_ids': ['eat'],
          'judgments': {..._judged('sam', 2), ..._judged(selfPersonId, 1)},
        }),
      ]);

      expect(scores.days.first, '2026-10-01');
      expect(scores.days.last, '2026-10-07');
      expect(
        [for (final d in scores.history) d.day],
        ['2026-10-06', '2026-10-07'],
      );
      expect(scores.history.last.people, {selfPersonId: 50, 'sam': 100});
      expect(scores.history.last.score, 75);
      expect(scores.health('sam'), 100);
      expect(scores.healthTrend('sam'), [
        null,
        null,
        null,
        null,
        null,
        100,
        100,
      ]);
      expect(scores.health('jo'), isNull);
      expect(scores.groupHealth(['sam', 'jo', selfPersonId]), 75);
      expect(scores.rating('sam', '2026-10-05')?.rating, isNull);

      final digest = scores.digest('sam');
      expect(digest.eventsCounted, 1);
      expect(digest.actions.single.label, 'eat');
      expect(digest.locations.single.label, 'home');
      expect(digest.locations.single.first, '2026-10-06');
      expect(scores.eventsBehind(scores.rating('sam')!.traits.single).keys, [
        'dinner',
      ]);
    });
  });

  group('habits', () {
    // Guitar, a group: Play guitar and Practice guitar. And Walk.
    const parents = {'play': 'guitar', 'practice': 'guitar'};
    String? parentOf(String id) => parents[id];
    const guitar = Habit(id: 'h', name: 'Practice', actionId: 'guitar');

    TraitScore score(
      List<Part> parts,
      List<Event> events, {
      Habit habit = guitar,
    }) => scoreSubject(
      Subject.habit(habit),
      [_trait(parts)],
      _start,
      _end,
      events,
      parentOf: parentOf,
    ).single;

    test("read their judgments under habit:<id>, of Self's events in "
        'their group', () {
      final events = [
        _event(
          'practice',
          1,
          actions: ['practice'],
          judgments: _judged('habit:h', 2),
        ),
        _event('play', 2, actions: ['play'], judgments: _judged('habit:h', 0)),
        // Out of it, though judged for it.
        _event('walk', 3, actions: ['walk'], judgments: _judged('habit:h', 0)),
        // Self's judgment, not the habit's.
        _event(
          'self',
          4,
          actions: ['practice'],
          judgments: _judged(selfPersonId, 0),
        ),
      ];

      final over = score([_judgment], events);
      expect(over.score, 50);
      expect(over.parts.single.eventIds, ['practice', 'play']);
      // On one action alone, only its events.
      expect(
        score(
          [_judgment],
          events,
          habit: const Habit(id: 'h', name: 'Practice', actionId: 'practice'),
        ).score,
        100,
      );
    });

    test("count their events; a part's own action narrows them, never "
        'widens them', () {
      final events = [
        _event('practice', 1, actions: ['practice']),
        _event('play', 2, actions: ['play']),
        _event('walk', 3, actions: ['walk']),
      ];

      expect(
        score([
          {'kind': 'count', 'target': 2},
        ], events).score,
        100,
      );
      expect(
        score([
          {'kind': 'count', 'target': 2, 'action': 'practice'},
        ], events).score,
        50,
      );
      expect(
        score([
          {'kind': 'count', 'target': 2, 'action': 'walk'},
        ], events).score,
        0,
      );
    });

    test('follow through by their own cancellations', () {
      final habit = guitar.withCancelledEvents([
        CancelledEvent(
          start: _start.add(const Duration(hours: 19)),
          end: _start.add(const Duration(hours: 20)),
          actionIds: const ['practice'],
        ),
      ]);

      final scored = score(
        [
          {'kind': 'follow_through'},
        ],
        [
          _event('walk', 0.5, actions: ['walk']),
        ],
        habit: habit,
      );
      expect(scored.score, 75);
      expect(scored.parts.single.said, '1 cancelled (−25) that day, from 100');
      // Without its own, nothing's cancelled.
      expect(
        score([
          {'kind': 'follow_through'},
        ], const []).score,
        100,
      );
    });

    test("leave out parts for someone: they're always with you", () {
      final events = [
        _event(
          'practice',
          1,
          actions: ['practice'],
          judgments: {
            'habit:h': {
              't': {
                'judgment#2': {'rating': 2, 'scale': 2},
              },
            },
          },
        ),
      ];

      final scored = score([
        {..._judgment, 'engagement_type': 'for'},
        _judgment,
      ], events);
      // Keyed among all its parts, as the server judges them.
      expect([for (final p in scored.parts) p.key], ['judgment#2']);
      expect(scored.score, 100);
      expect(
        scoreSubject(
          Subject.habit(guitar),
          [
            _trait([
              {..._judgment, 'engagement_type': 'for'},
            ]),
          ],
          _start,
          _end,
          events,
          parentOf: parentOf,
        ),
        isEmpty,
      );
    });

    test('are scored beside people, but not in a trait\'s day', () {
      final today = DateTime(2026, 10, 8);
      final scores = TraitScores.compute(
        traits: [
          _trait([_judgment]),
          const Trait(
            id: 'for',
            name: 'For',
            parts: [
              {
                'kind': 'judgment',
                'engagement_type': 'for',
                'rubric': 'For them?',
                'ratings': {'0': 'No', '1': 'Yes'},
              },
            ],
          ),
        ],
        people: const [_self],
        habits: [
          guitar,
          const Habit(
            id: 'old',
            name: 'Old',
            actionId: 'guitar',
            status: 'archived',
          ),
        ],
        events: [
          Event.fromJson({
            'id': 'practice',
            'start': localIsoTimestamp(DateTime(2026, 10, 6, 18)),
            'end': localIsoTimestamp(DateTime(2026, 10, 6, 19)),
            'action_ids': ['practice'],
            'judgments': {
              ..._judged('habit:h', 1),
              ..._judged(selfPersonId, 2),
            },
          }),
          Event.fromJson({
            'id': 'walk',
            'start': localIsoTimestamp(DateTime(2026, 10, 6, 20)),
            'end': localIsoTimestamp(DateTime(2026, 10, 6, 21)),
            'action_ids': ['walk'],
          }),
        ],
        today: today,
        parentOf: parentOf,
      );

      expect(scores.health('habit:h'), 50);
      expect(scores.healthTrend('habit:h').last, 50);
      expect(scores.rating('habit:h')!.leftOut, ['For']);
      expect(scores.health('habit:old'), isNull);
      expect(scores.history.last.people, {selfPersonId: 100});
      expect(scores.digest('habit:h').eventsCounted, 1);
      expect(scores.digest('habit:h').actions.single.label, 'practice');
    });
  });
}
