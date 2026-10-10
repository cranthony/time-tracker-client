import 'dart:async';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:time_tracker_client/models/event.dart';
import 'package:time_tracker_client/models/note.dart';
import 'package:time_tracker_client/models/person.dart';
import 'package:time_tracker_client/models/plan_action.dart';
import 'package:time_tracker_client/models/trait.dart';
import 'package:time_tracker_client/services/event_store.dart';
import 'package:time_tracker_client/services/events_repository.dart';
import 'package:time_tracker_client/services/plan_memory.dart';

import 'flutter_test_config.dart';

const _present = Trait(
  id: 'present',
  name: 'Present',
  parts: [
    {
      'kind': 'judgment',
      'rubric': 'How present was I?',
      'ratings': {'0': 'Distracted', '3': 'Fully'},
      'facts': ['general_notes'],
    },
  ],
);

/// Yesterday evening's event, rated fully present.
Event _yesterday() {
  final now = DateTime.now();
  return Event.fromJson({
    'id': 'e1',
    'summary': 'Dinner',
    'start': localIsoTimestamp(DateTime(now.year, now.month, now.day - 1, 19)),
    'end': localIsoTimestamp(DateTime(now.year, now.month, now.day - 1, 20)),
    'judgments': {
      'self': {
        'present': {
          'judgment': {'rating': 3, 'scale': 3, 'reasoning': 'All there'},
        },
      },
    },
  });
}

/// A memory with a trait, Self, and a day of events, warmed.
Future<PlanMemory> _memory() async {
  final memory =
      PlanMemory(
          eventStore: EventStore(
            repository: InMemoryEventsRepository([_yesterday()]),
          ),
        )
        ..traits = [_present]
        ..people = const PeopleList()
        ..actions = const ActionList(actions: []);
  await memory.eventStore!.warm();
  return memory;
}

/// Reads [memory]'s scores until they're in, as a listener would.
Future<void> _scored(PlanMemory memory) async {
  if (memory.scores != null && !memory.rescoring) return;
  final done = Completer<void>();
  void heard() {
    if (memory.scores != null && !memory.rescoring && !done.isCompleted) {
      done.complete();
    }
  }

  memory.addListener(heard);
  await done.future.timeout(const Duration(seconds: 10));
  memory.removeListener(heard);
}

void main() {
  tearDown(useScoresHere);

  test('works the scores out on another isolate, and tells listeners once '
      "they're in", () async {
    var runs = 0;
    PlanMemory.runScores = (work) {
      runs++;
      return Isolate.run(work);
    };
    final memory = await _memory();
    var told = 0;
    memory.addListener(() => told++);

    // Not in yet: none, while they're worked out.
    expect(memory.scores, isNull);
    expect(memory.rescoring, isTrue);
    await _scored(memory);

    expect(told, greaterThan(0));
    expect(memory.scores!.history.single.score, 100);
    expect(runs, 1);
  });

  test('not worked out again for what loads again alike, but for what '
      'changes', () async {
    var runs = 0;
    PlanMemory.runScores = (work) {
      runs++;
      return SynchronousFuture(work());
    };
    final memory = await _memory();
    final first = memory.scores;
    expect(runs, 1);

    // Loaded again, alike: new objects, the same content.
    memory
      ..traits = [Trait.fromJson(_present.toJson())]
      ..people = const PeopleList(people: [])
      ..actions = const ActionList(actions: []);
    final version = memory.eventStore!.version;
    await memory.eventStore!.refresh(
      DateTime.now().subtract(const Duration(days: 2)),
      DateTime.now(),
    );
    // The same events, fetched again: nothing's changed.
    expect(memory.eventStore!.version, version);
    expect(identical(memory.scores, first), isTrue);
    expect(runs, 1);

    // A trait changed: worked out again.
    memory.traits = [
      Trait.fromJson({..._present.toJson(), 'name': 'Here'}),
    ];
    expect(identical(memory.scores, first), isFalse);
    expect(runs, 2);
  });

  test('while worked out again, shows them as they were', () async {
    final pending = <Completer<void>>[];
    PlanMemory.runScores = (work) async {
      final gate = Completer<void>();
      pending.add(gate);
      await gate.future;
      return work();
    };
    final memory = await _memory();
    memory.scores;
    pending.removeAt(0).complete();
    await _scored(memory);
    final first = memory.scores;

    memory.traits = [
      Trait.fromJson({..._present.toJson(), 'name': 'Here'}),
    ];
    expect(identical(memory.scores, first), isTrue);
    expect(memory.rescoring, isTrue);
    pending.removeAt(0).complete();
    await _scored(memory);
    expect(identical(memory.scores, first), isFalse);
  });
}
