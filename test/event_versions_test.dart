import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:time_tracker_client/models/event.dart';
import 'package:time_tracker_client/models/note.dart';
import 'package:time_tracker_client/outbox/event_outbox.dart';
import 'package:time_tracker_client/outbox/outbox_store.dart';
import 'package:time_tracker_client/outbox/pending_write.dart';
import 'package:time_tracker_client/services/events_repository.dart';
import 'package:time_tracker_client/services/mcp_client.dart';
import 'package:time_tracker_client/widgets/other_events.dart';
import 'package:time_tracker_client/widgets/write_conflict_dialog.dart';

DateTime _at(int hour) => DateTime(2026, 9, 30, hour);

Map<String, Object?> _lunch({
  String summary = 'Lunch',
  String? description,
  String etag = 'e1',
}) => {
  'id': 'lunch',
  'summary': summary,
  'description': ?description,
  'start': localIsoTimestamp(_at(12)),
  'end': localIsoTimestamp(_at(13)),
  'etag': etag,
};

/// The server's events, as each change found them: what it was sent, and
/// [answers] -- a conflict, say -- to give, in order, before making them.
class _Server extends InMemoryEventsRepository {
  _Server() : super([Event.fromJson(_lunch())]);

  final sent = <Map<String, Object?>>[];
  final created = <Map<String, Object?>>[];
  final answers = <Object>[];

  @override
  Future<List<Event>> updateEvent(
    Event event,
    Map<String, Object?> changes, {
    bool allowCompactedChanges = false,
  }) async {
    sent.add({...event.toJson(), ...changes});
    if (answers.isNotEmpty) throw answers.removeAt(0);
    return super.updateEvent(event, changes);
  }

  @override
  Future<List<Event>> deleteEvent(
    Event event, {
    bool countsAgainstFollowThrough = false,
    bool allowCompactedChanges = false,
  }) async {
    sent.add({'cancel': event.id, 'etag': event.properties['etag']});
    if (answers.isNotEmpty) throw answers.removeAt(0);
    return super.deleteEvent(event);
  }

  @override
  Future<List<Event>> createEvent(Map<String, Object?> fields) async {
    created.add(fields);
    return super.createEvent(fields);
  }

  /// Each batch sent, as the events in it are versioned: each update's
  /// and cancel's etag, by event.
  final batches = <Map<String, Object?>>[];

  @override
  Future<List<Event>> makeRoom(
    Overwrite over, {
    bool allowCompactedChanges = false,
  }) async {
    batches.add({
      for (final (e, changes) in over.updates)
        e.id!: (e.properties['etag'], changes),
      for (final e in over.cancels) e.id!: (e.properties['etag'], null),
      'creates': (over.creates.map((c) => c['id']).toList(), null),
    });
    if (answers.isNotEmpty) throw answers.removeAt(0);
    return const [];
  }
}

Map<String, Object?> _gym({String summary = 'Gym', String etag = 'g1'}) => {
  'id': 'gym',
  'summary': summary,
  'start': localIsoTimestamp(_at(13)),
  'end': localIsoTimestamp(_at(14)),
  'etag': etag,
};

McpException _conflict(Map<String, Object?>? current) => McpException(
  'Tool update_event failed: event changed after it was read',
  serverMessage: 'event changed after it was read',
  meta: {
    'conflict': {'kind': 'event', 'current': current},
  },
);

void main() {
  late _Server server;
  late EventOutbox outbox;

  setUp(() {
    server = _Server();
    outbox = EventOutbox(store: InMemoryOutboxStore(), events: server);
  });

  tearDown(() => outbox.dispose());

  test(
    'a new event is made with an id of its own, in Calendar\'s form',
    () async {
      await outbox.create({
        'summary': 'Walk',
        'start': localIsoTimestamp(_at(15)),
        'end': localIsoTimestamp(_at(16)),
      });
      await outbox.flush();

      final id = server.created.single['id'] as String;
      expect(id, matches(RegExp(r'^[a-v0-9]{20}$')));
    },
  );

  test('a change is sent with the etag it was made to', () async {
    final lunch = Event.fromJson(_lunch());
    await outbox.update(lunch, {'summary': 'Brunch'});
    await outbox.flush();
    await outbox.cancel(Event.fromJson(_lunch(etag: 'e2')));
    await outbox.flush();

    expect(server.sent.map((s) => s['etag']), ['e1', 'e2']);
  });

  test('changed elsewhere in other fields: made to it as it is now', () async {
    await outbox.update(Event.fromJson(_lunch()), {'summary': 'Brunch'});
    server.answers.add(_conflict(_lunch(description: 'with Sam', etag: 'e2')));
    await outbox.flush();

    expect(outbox.items, isEmpty);
    expect(server.sent.last['etag'], 'e2');
    expect(server.sent.last['summary'], 'Brunch');
    expect(server.sent.last['description'], 'with Sam');
  });

  testWidgets('changed elsewhere in the same field: waits, conflicted, and '
      'is resolved field by field', (tester) async {
    await tester.runAsync(() async {
      await outbox.update(Event.fromJson(_lunch()), {'summary': 'Brunch'});
      server.answers.add(_conflict(_lunch(summary: 'Late lunch', etag: 'e2')));
      await outbox.flush();
      // Kept conflicted.
      await outbox.refresh();
    });

    final waiting = outbox.items.single;
    expect((waiting.conflicted, waiting.refused), (true, true));
    expect(waiting.current?['summary'], 'Late lunch');

    late BuildContext context;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (c) {
            context = c;
            return const SizedBox();
          },
        ),
      ),
    );
    final resolving = showWriteConflictDialog(
      context,
      EventConflicts(outbox),
      EventOutbox.conflictOf(waiting),
    );
    await tester.pumpAndSettle();
    expect(find.text('Late lunch'), findsOneWidget);
    expect(find.text('Brunch'), findsOneWidget);
    // Theirs.
    await tester.tap(find.text('Late lunch'));
    await tester.pump();
    await tester.tap(find.text('Save'));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pumpAndSettle();
    expect(await resolving, isTrue);

    final resent = outbox.items.single;
    expect(resent.conflicted, isFalse);
    expect(resent.event?.properties['etag'], 'e2');
    expect(resent.changes, isEmpty);
  });

  test('a cancel of one changed elsewhere waits, conflicted', () async {
    await outbox.cancel(Event.fromJson(_lunch()));
    server.answers.add(_conflict(_lunch(summary: 'Late lunch', etag: 'e2')));
    await outbox.flush();

    expect(outbox.items.single.conflicted, isTrue);
    expect(outbox.items.single.lastError, 'Changed elsewhere since');
  });

  group('a batch', () {
    Overwrite batch() => Overwrite(
      updates: [
        (
          Event.fromJson(_lunch()),
          {'end': localIsoTimestamp(_at(12).add(const Duration(minutes: 30)))},
        ),
      ],
      cancels: [Event.fromJson(_gym())],
    );

    test('sends each of its events with the etag it was made to', () async {
      await outbox.makeRoom(batch());
      await outbox.flush();

      final sent = server.batches.single;
      expect((sent['lunch']! as (Object?, Object?)).$1, 'e1');
      expect((sent['gym']! as (Object?, Object?)).$1, 'g1');
    });

    test('one of its events changed elsewhere in other fields: made to it '
        'as it is now', () async {
      await outbox.makeRoom(batch());
      server.answers.add(
        McpException(
          'Tool update_event failed: event changed after it was read',
          meta: {
            'conflict': {
              'id': 'lunch',
              'current': _lunch(description: 'with Sam', etag: 'e2'),
            },
          },
        ),
      );
      await outbox.flush();

      expect(outbox.items, isEmpty);
      expect((server.batches.last['lunch']! as (Object?, Object?)).$1, 'e2');
      expect((server.batches.last['gym']! as (Object?, Object?)).$1, 'g1');
    });

    test('one changed in the same way waits, conflicted, naming it; dropped, '
        'just its part is, and the rest is sent', () async {
      await outbox.makeRoom(batch());
      server.answers.add(
        McpException(
          'Tool update_event failed: event changed after it was read',
          meta: {
            'conflict': {
              'id': 'gym',
              'current': _gym(summary: 'Climbing', etag: 'g2'),
            },
          },
        ),
      );
      await outbox.flush();
      await outbox.refresh();

      final waiting = outbox.items.single;
      expect((waiting.conflicted, waiting.conflictId), (true, 'gym'));
      final shown = EventOutbox.conflictOf(waiting);
      expect((shown.op, shown.itemId), (WriteOp.delete, 'gym'));
      expect(EventConflicts(outbox).label(shown), 'event “Gym”');

      expect(await EventConflicts(outbox).drop(shown), isTrue);
      final rest = outbox.items.single;
      expect(rest.conflicted, isFalse);
      expect(rest.over.cancels, isEmpty);
      expect(rest.over.updates.single.$1.id, 'lunch');
    });

    test('each event it makes has an id of its own, so a batch stopped '
        'partway is safe to send again', () async {
      await outbox.makeRoom(
        Overwrite(
          creates: [
            {
              'summary': 'Rest',
              'start': localIsoTimestamp(_at(15)),
              'end': localIsoTimestamp(_at(16)),
            },
          ],
        ),
      );
      await outbox.flush();

      final ids = (server.batches.single['creates']! as (Object?, Object?)).$1;
      expect(ids, [matches(RegExp(r'^[a-v0-9]{20}$'))]);
    });

    test('every event changed elsewhere is resolved in turn before it is '
        'sent again', () async {
      await outbox.makeRoom(
        Overwrite(
          updates: [
            (Event.fromJson(_lunch()), {'summary': 'Brunch'}),
            (Event.fromJson(_gym()), {'summary': 'Swim'}),
          ],
        ),
      );
      server.answers.add(
        McpException(
          'Tool update_event failed: 2 of the things it changes changed',
          meta: {
            'conflicts': [
              {
                'id': 'lunch',
                'current': _lunch(summary: 'Late lunch', etag: 'e2'),
              },
              {'id': 'gym', 'current': _gym(summary: 'Climbing', etag: 'g2')},
            ],
          },
        ),
      );
      await outbox.flush();
      await outbox.refresh();

      var waiting = outbox.items.single;
      expect((waiting.conflicted, waiting.conflictId), (true, 'lunch'));
      expect(waiting.moreConflicts.map((c) => c['id']), ['gym']);

      final conflicts = EventConflicts(outbox);
      await conflicts.resolve(EventOutbox.conflictOf(waiting), {
        'summary': 'Brunch',
      });
      waiting = outbox.items.single;
      expect((waiting.conflicted, waiting.conflictId), (true, 'gym'));
      final sent = server.batches.length;
      await outbox.flush();
      expect(server.batches, hasLength(sent), reason: 'sent before resolved');

      await conflicts.drop(EventOutbox.conflictOf(waiting));
      await outbox.flush();
      final last = server.batches.last;
      expect((last['lunch']! as (Object?, Object?)).$1, 'e2');
      expect(last.containsKey('gym'), isFalse);
      expect(outbox.items, isEmpty);
    });
  });
}
