import 'package:flutter_test/flutter_test.dart';
import 'package:time_tracker_client/demo/sample_data.dart';
import 'package:time_tracker_client/models/event.dart';
import 'package:time_tracker_client/models/habit.dart';
import 'package:time_tracker_client/models/note.dart';
import 'package:time_tracker_client/models/person.dart';
import 'package:time_tracker_client/models/scoring.dart';
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
  List<Object> actions = const [],
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

Trait _trait(List<Part> parts, {Aggregation? scoring}) =>
    Trait(id: 't', name: 'T', parts: parts, scoring: scoring);

/// Sam's score of a trait made of [parts], from [events], and its parts'.
TraitScore _score(
  List<Part> parts,
  List<Event> events, {
  Person person = _sam,
  String? Function(String id)? parentOf,
  Aggregation? scoring,
}) => scorePerson(
  person,
  [_trait(parts, scoring: scoring)],
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
  test("parts are keyed by their ids, and those without by the name they "
      'had before parts had ids', () {
    expect(
      partKeys([
        {'kind': 'judgment'},
        {'id': 'judgment', 'kind': 'judgment'},
        {'id': 'x1', 'kind': 'count'},
      ]),
      ['judgment#2', 'judgment', 'x1'],
    );
  });

  test("a judgment part's judgments combine as its scoring says", () {
    final events = [
      _event(
        'long',
        1,
        hours: 3,
        withIds: ['sam'],
        judgments: _judged('sam', 2),
      ),
      _event('short', 2, withIds: ['sam'], judgments: _judged('sam', 0)),
    ];
    final byTime = _score([
      {
        ..._judgment,
        'scoring': {'weight_by': 'duration'},
      },
    ], events);
    expect(byTime.score, 75);
    expect(
      byTime.parts.single.said,
      'Mean of 2 judgments, by time, in the last 30 days',
    );
    final recent = _score([
      {
        ..._judgment,
        'scoring': {'limit': 1, 'limit_by': 'recent'},
      },
    ], events);
    expect(recent.score, 100);
  });

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
      expect(part.said, 'Mean of 2 judgments in the last 30 days');
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
    expect(score.parts.single.said, '3h of 4h in the last 7 days');
  });

  test("a duration of an action counts only that action's share of an "
      'event, as the summaries do', () {
    const part = {
      'kind': 'duration',
      'target_min': 240,
      'interval_days': 7,
      'action': 'work',
    };
    final score = _score(
      [part],
      [
        // 30 minutes of work, and half of the 90 left: 75 minutes.
        _event(
          'a',
          1,
          hours: 2,
          withIds: ['sam'],
          actions: [
            {'action_id': 'work', 'minutes': 30, 'remaining': true},
            'mail',
          ],
        ),
        // Work alone: all of it.
        _event('b', 2, hours: 1, withIds: ['sam'], actions: ['work']),
        // Not work at all.
        _event('c', 3, hours: 1, withIds: ['sam'], actions: ['mail']),
      ],
    );

    expect(score.parts.single.said, '2h 15m of 4h in the last 7 days');
  });

  test("a duration with someone counts only their share of an event", () {
    const part = {'kind': 'duration', 'target_min': 240, 'interval_days': 7};
    final shared = _event('a', 1, hours: 2);
    final score = _score(
      [part],
      [
        Event.fromJson({
          ...shared.properties,
          'facts': {
            'with_ids': [
              {'person_id': 'sam', 'minutes': 30},
              'kim',
            ],
          },
        }),
      ],
    );

    expect(score.parts.single.said, '30m of 4h in the last 7 days');
  });

  test('parts being edited are scored as the trait would score them, '
      "leaving out those a habit doesn't read", () {
    final events = [
      for (var day = 1; day <= 5; day++)
        _event('work$day', day, hours: 7, actions: ['work']),
    ];
    const habit = Subject(id: 'habit:w', scope: 'work');
    const partial = {
      'kind': 'duration',
      'target_min': 2400,
      'interval_days': 7,
    };
    final scores = scoreParts(
      habit,
      'reliable',
      [
        partial,
        {...partial, 'zero_at_days': 14},
        {...partial, 'engagement_type': 'for'},
      ],
      _end,
      events,
    );

    // 35h of 40h: in proportion, or, never met, faded to nothing.
    expect(scores[0]!.score, 88);
    expect(scores[0]!.said, '35h of 40h in the last 7 days');
    expect(scores[1]!.score, 0);
    expect(scores[1]!.said, contains('not met in the last 14 days'));
    expect(scores[2], isNull);
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
        {'kind': 'count', 'target': 1, 'interval_days': 7},
        {'kind': 'continuity', 'last_within_days': 7, 'next_within_days': 7},
        _judgment,
        {'kind': 'count'},
      ],
      [
        _event('a', 1, withIds: ['sam']),
      ],
      // Its weights are its trait's, by part id.
      scoring: const Aggregation(weights: {'count': 3}),
    );

    // (100 x 3 + 50) / 4.
    expect(score.score, 88);
    expect(score.parts.first.weight, 3);
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
            'location_ids': ['home'],
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
      // A circle's own scoring, and a habit layer's lowest by default.
      expect(
        scores.groupHealth(['sam', selfPersonId], scoring: Aggregation.lowest),
        50,
      );
      expect(scores.layerTrend(['sam', selfPersonId]).last, 50);
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

  group('spacing', () {
    const part = {
      'kind': 'spacing',
      'action': 'meal',
      'max_gap_hours': 6,
      'exceptions': [
        {
          'actions': ['sleep'],
          'reset_hours': 1,
        },
      ],
    };
    // Asleep from 11pm the night before to 7am, and again from 11pm.
    final nights = [
      _event('night 1', 2, hour: 23, hours: 8, actions: ['sleep']),
      _event('night 2', 1, hour: 23, hours: 8, actions: ['sleep']),
    ];
    Event meal(String id, int hour, [int minutes = 0]) => Event.fromJson({
      ..._event(id, 1, hour: hour, actions: ['meal']).toJson(),
      'start': localIsoTimestamp(
        _start.add(Duration(hours: hour, minutes: minutes)),
      ),
      'end': localIsoTimestamp(
        _start.add(Duration(hours: hour + 1, minutes: minutes)),
      ),
    });
    PartScore spaced(List<Event> meals) =>
        _score([part], [...nights, ...meals], person: _self).parts.single;

    test('is 100 when the clock never ran out while awake', () {
      final score = spaced([
        meal('breakfast', 7, 30),
        meal('lunch', 12, 30),
        meal('dinner', 18),
      ]);
      expect(score.score, 100);
      expect(score.said, 'Never over 6 hours apart, in 16h');
      expect(score.eventIds, ['breakfast', 'lunch', 'dinner']);
    });

    test("is the share of the day's waking time it hadn't run out", () {
      // No lunch: 1:30pm to 6pm overdue, 4h 30m of 16h.
      final score = spaced([meal('breakfast', 7, 30), meal('dinner', 18)]);
      expect(score.score, 72);
      expect(score.said, '4h 30m overdue of 16h');
    });

    test('an exception sets the time left after it', () {
      // An hour after waking, so breakfast at 9 is an hour late.
      expect(
        spaced([meal('breakfast', 9), meal('lunch', 14), meal('dinner', 19)])
            .score,
        94,
      );
      // Without a reset, waking leaves it as it was going to sleep: 1h.
      final paused = Map<String, Object?>.of(part)
        ..['exceptions'] = [
          {
            'actions': ['sleep'],
          },
        ];
      final score = _score(
        [paused],
        [
          ...nights,
          meal('breakfast', 9),
          meal('lunch', 14),
          meal('dinner', 18),
        ],
        person: _self,
      ).parts.single;
      // Last meal before the first night unknown: its clock starts full
      // two days before, so it's run out by then; 7am to 9am overdue.
      expect(score.score, 88);
    });

    test('reads a habit\'s exceptions outside its scope', () {
      final scores = scoreSubject(
        Subject.habit(
          const Habit(
            id: 'eat',
            name: 'Eat well',
            actionId: 'meal',
            traits: PersonTraits(
              parts: {
                't': [part],
              },
            ),
          ),
        ),
        [
          _trait([_judgment]),
        ],
        _start,
        _end,
        [...nights, meal('breakfast', 7, 30), meal('dinner', 18)],
      );
      expect(scores.single.parts.single.score, 72);
    });
  });

  group('consistency', () {
    final today = DateTime(2026, 10, 8);
    // An event at noon on each of [days] days before today.
    List<Event> daily(int days, {int skipping = 0}) => [
      for (var back = 1 + skipping; back <= days + skipping; back++)
        Event.fromJson({
          'id': 'day $back',
          'start': localIsoTimestamp(DateTime(2026, 10, 8 - back, 12)),
          'end': localIsoTimestamp(DateTime(2026, 10, 8 - back, 13)),
          'action_ids': ['walk'],
        }),
    ];
    TraitScores compute(List<Event> events) => TraitScores.compute(
      traits: [
        _trait([
          {'kind': 'count', 'target': 1, 'interval_days': 1},
        ]),
      ],
      people: const [_self, _sam],
      events: events,
      today: today,
    );

    test('counts the days healthy in a row, back from yesterday', () {
      expect(compute(daily(3)).consistency(selfPersonId), 3);
      expect(compute(daily(10)).consistency(selfPersonId), 10);
      // Yesterday wasn't: none.
      expect(compute(daily(10, skipping: 1)).consistency(selfPersonId), 0);
      expect(compute(daily(10)).consistency('sam'), 0);
      expect(compute(daily(10)).consistency('nobody'), 0);
    });

    test('stops one past the most it counts', () {
      expect(compute(daily(30)).consistency(selfPersonId), 30);
      expect(
        compute(daily(45)).consistency(selfPersonId),
        maxConsistencyDays + 1,
      );
    });
  });

  test("a person's traits combine as theirs, or the defaults', say", () {
    final traits = [
      const Trait(id: 'a', name: 'A', parts: [_judgment]),
      const Trait(id: 'b', name: 'B', parts: [_judgment]),
    ];
    final events = [
      _event(
        'x',
        1,
        withIds: ['sam'],
        judgments: {
          'sam': {
            'a': {
              'judgment': {'rating': 2, 'scale': 2},
            },
            'b': {
              'judgment': {'rating': 0, 'scale': 2},
            },
          },
        },
      ),
    ];
    TraitScores compute({
      PersonTraits own = const PersonTraits(),
      ScoringDefaults defaults = const ScoringDefaults(),
    }) => TraitScores.compute(
      traits: traits,
      people: [Person(id: 'sam', name: 'Sam', traits: own)],
      events: events,
      today: DateTime(2026, 10, 2),
      days: 1,
      defaults: defaults,
    );

    expect(compute().health('sam'), 50);
    expect(
      compute(
        defaults: const ScoringDefaults(traits: Aggregation(weights: {'a': 3})),
      ).health('sam'),
      75,
    );
    // Their own, over the defaults'.
    expect(
      compute(
        own: const PersonTraits(scoring: Aggregation.lowest),
        defaults: const ScoringDefaults(traits: Aggregation(weights: {'a': 3})),
      ).health('sam'),
      0,
    );
  });

  test('scoring every day at once rates each as scoring it alone does', () {
    // What compute works out once, for every subject and day, is what
    // each would have worked out for itself.
    final now = DateTime(2026, 10, 7, 15);
    final sample = SampleData(now);
    final events = [
      for (var week = 0; week < 5; week++)
        for (final e in sample.events)
          Event.fromJson({
            ...e.toJson().cast<String, dynamic>(),
            'id': '${e.id}-$week',
            'start': localIsoTimestamp(
              e.start.subtract(Duration(days: 7 * week)),
            ),
            'end': localIsoTimestamp(e.end.subtract(Duration(days: 7 * week))),
          }),
    ];
    final parents = {
      for (final a in sample.actions)
        if (a.id != null) a.id!: a.parentId,
    };
    final scores = TraitScores.compute(
      traits: sample.traits,
      people: sample.people,
      habits: sample.habits,
      events: events,
      today: now,
      parentOf: (id) => parents[id],
    );
    final subjects = [
      for (final p in sample.people) Subject.person(p),
      for (final h in sample.habits) Subject.habit(h),
    ];
    var rated = 0;
    for (final subject in subjects.where((s) => s.active)) {
      for (final day in scores.days) {
        final start = DateTime.parse(day);
        final alone = scoreSubject(
          subject,
          sample.traits,
          start,
          DateTime(start.year, start.month, start.day + 1),
          events,
          parentOf: (id) => parents[id],
        );
        String said(List<TraitScore> traits) => [
          for (final t in traits)
            '${t.traitId} ${t.score}: '
                '${[for (final p in t.parts) '${p.key} ${p.score} ${p.said} ${p.eventIds}'].join('; ')}',
        ].join('\n');
        expect(
          said(scores.rating(subject.id, day)!.traits),
          said(alone),
          reason: '${subject.id} on $day',
        );
        rated++;
      }
    }
    expect(rated, greaterThan(20));
  });
}
