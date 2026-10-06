import 'package:flutter_test/flutter_test.dart';
import 'package:time_tracker_client/models/event.dart';
import 'package:time_tracker_client/models/note.dart';
import 'package:time_tracker_client/models/trait.dart';
import 'package:time_tracker_client/services/event_store.dart';
import 'package:time_tracker_client/services/events_repository.dart';
import 'package:time_tracker_client/services/people_repository.dart';
import 'package:time_tracker_client/services/plan_memory.dart';
import 'package:time_tracker_client/services/response_cache.dart';
import 'package:time_tracker_client/services/traits_repository.dart';

/// Today, at noon.
final _now = DateTime(2026, 10, 8, 12);

DateTime _day(int offset) => DateTime(2026, 10, 8 + offset);

Event _event(String id, int dayOffset, {int hour = 12, int hours = 1}) {
  final start = DateTime(2026, 10, 8 + dayOffset, hour);
  return Event.fromJson({
    'id': id,
    'summary': id,
    'start': localIsoTimestamp(start),
    'end': localIsoTimestamp(start.add(Duration(hours: hours))),
  });
}

/// Says what was asked for: each range's first and last day, from today.
class _CountingEvents extends InMemoryEventsRepository {
  _CountingEvents(super.events);

  final asked = <(int, int)>[];

  @override
  Future<List<Event>> events(DateTime from, DateTime to, {bool keep = false}) {
    asked.add((
      from.difference(_day(0)).inDays,
      to.difference(_day(0)).inDays - 1,
    ));
    return super.events(from, to, keep: keep);
  }
}

void main() {
  test('warming asks for the week either side of today, and for what '
      "isn't kept further out, once", () async {
    final repository = _CountingEvents([
      _event('today', 0),
      _event('old', -20),
      _event('soon', 3),
    ]);
    final cache = InMemoryResponseCache();
    final store = EventStore(
      repository: repository,
      cache: cache,
      clock: () => _now,
    );

    await store.warm(back: 30, ahead: 10);
    expect(repository.asked, [(-7, 7), (-30, -8), (8, 10)]);
    expect(store.between(_day(-30), _day(11)).map((e) => e.id), [
      'old',
      'today',
      'soon',
    ]);
    expect(store.day(_day(-20))?.single.id, 'old');
    expect(store.day(_day(-19)), isEmpty);
    expect(store.has(_day(-31)), isFalse);

    // Again: only the week either side.
    repository.asked.clear();
    await store.warm(back: 30, ahead: 10);
    expect(repository.asked, [(-7, 7)]);

    // Next run, from what was kept: still only the week either side.
    await store.save();
    final next = EventStore(
      repository: repository,
      cache: cache,
      clock: () => _now,
    );
    repository.asked.clear();
    await next.warm(back: 30, ahead: 10);
    expect(repository.asked, [(-7, 7)]);
    expect(next.day(_day(-20))?.single.id, 'old');

    // Signing out forgets them.
    await next.clear();
    expect(next.has(_day(-20)), isFalse);
    expect(await cache.read('event_days'), isNull);
  });

  test(
    'an event across midnight is in both days, and once between them',
    () async {
      final store = EventStore(
        repository: InMemoryEventsRepository([
          _event('sleep', -1, hour: 23, hours: 8),
        ]),
        clock: () => _now,
      );
      await store.warm();

      expect(store.day(_day(-1))?.single.id, 'sleep');
      expect(store.day(_day(0))?.single.id, 'sleep');
      expect(store.between(_day(-1), _day(1)).map((e) => e.id), ['sleep']);
    },
  );

  test("a day put in replaces what's kept, and a saved event moves to "
      'the days it is in now', () async {
    final store = EventStore(
      repository: InMemoryEventsRepository([_event('call', -1)]),
      clock: () => _now,
    );
    await store.warm();
    var changes = 0;
    store.addListener(() => changes++);

    store.putDay(_day(-2), [_event('walk', -2)]);
    expect(store.day(_day(-2))?.single.id, 'walk');

    // Moved from yesterday to today.
    store.putEvents([_event('call', 0)]);
    expect(store.day(_day(-1)), isEmpty);
    expect(store.day(_day(0))?.single.id, 'call');
    expect(changes, 2);
  });

  test('warming the scores loads as far back as the traits read, from '
      'each day scored', () async {
    final repository = _CountingEvents([]);
    final memory = PlanMemory(
      eventStore: EventStore(repository: repository, clock: () => _now),
    );

    await memory.warmScores(
      traits: InMemoryTraitsRepository(
        traits: const [
          Trait(
            id: 'reliable',
            name: 'Reliable',
            parts: [
              {
                'kind': 'count',
                'target': 1,
                'interval_days': 14,
                'zero_at_days': 40,
              },
              {'kind': 'continuity', 'next_within_days': 21},
            ],
          ),
        ],
      ),
      people: InMemoryPeopleRepository(),
    );

    // 7 days scored, each reading 40 back; continuity 21 ahead.
    expect(repository.asked, [(-7, 7), (-48, -8), (8, 21)]);
    expect(memory.scores?.days, hasLength(PlanMemory.scoredDays));
  });
}
