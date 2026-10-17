import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:time_tracker_client/models/person.dart';
import 'package:time_tracker_client/outbox/event_outbox.dart';
import 'package:time_tracker_client/outbox/outbox_store.dart';
import 'package:time_tracker_client/outbox/write_queue.dart';
import 'package:time_tracker_client/services/events_repository.dart';
import 'package:time_tracker_client/services/mcp_client.dart';
import 'package:time_tracker_client/services/people_repository.dart';
import 'package:time_tracker_client/services/response_cache.dart';

/// A server, as the queue sees it: each call recorded; answered by
/// [answer], or else as the server would answer a write it made.
class _Server {
  final calls =
      <({String tool, Map<String, Object?> arguments, String writeId})>[];

  /// What the next call does: throws, or gives something; null for the
  /// default.
  final answers =
      <Object? Function(String tool, Map<String, Object?> arguments)>[];

  bool offline = false;
  var version = 1;

  Future<Object?> call(
    String tool,
    Map<String, Object?> arguments,
    String writeId,
  ) async {
    calls.add((tool: tool, arguments: arguments, writeId: writeId));
    if (offline) throw http.ClientException('Failed host lookup');
    if (answers.isNotEmpty) return answers.removeAt(0)(tool, arguments);
    final item = (arguments.values.first as Map).cast<String, Object?>();
    return tool.startsWith('create_')
        ? {
            arguments.keys.first: {...item, 'version': 1},
            'created_id': item['id'],
          }
        : {...item, 'version': ++version};
  }
}

McpException _conflict(Map<String, Object?>? current) => McpException(
  'Tool failed: changed after version 1 was read',
  serverMessage: 'changed after version 1 was read',
  meta: {
    'conflict': {'current': current},
  },
);

void main() {
  late _Server server;
  late WriteQueue queue;

  WriteQueue make([InMemoryOutboxStore<PendingWrite>? store]) =>
      WriteQueue(store: store ?? InMemoryOutboxStore(), call: server.call);

  setUp(() {
    server = _Server();
    queue = make();
  });

  tearDown(() => queue.dispose());

  test('a new item has its id at once, and is made with it, once', () async {
    final id = queue.create(WriteKind.location, {'name': 'Home', 'hint': null});
    await queue.flush();

    expect(server.calls.single.tool, 'create_location');
    expect(server.calls.single.arguments, {
      'location': {'name': 'Home', 'id': id},
    });
    expect(server.calls.single.writeId, isNot(id));
    expect(queue.items, isEmpty);
  });

  test('offline, a write waits on the device, shown, and is sent once '
      'back online', () async {
    server.offline = true;
    final id = queue.create(WriteKind.location, {'name': 'Home'});
    await queue.flush();

    expect(queue.items, hasLength(1));
    expect(queue.items.single.lastError, isNotNull);
    expect(queue.shown(WriteKind.location, const []).single, {
      'name': 'Home',
      'id': id,
    });

    server.offline = false;
    await queue.retryNow();
    expect(queue.items, isEmpty);
    expect(server.calls.map((c) => c.writeId).toSet(), hasLength(1));
  });

  test(
    'nothing is dropped unless the user drops it: a refusal waits',
    () async {
      server.answers.add(
        (_, _) => throw McpException(
          'Tool failed',
          serverMessage: 'A location is already called "Home"',
        ),
      );
      queue.create(WriteKind.location, {'name': 'Home'});
      await queue.flush();

      expect(queue.items.single.refused, isTrue);
      expect(await queue.drop(queue.items.single), isTrue);
      expect(queue.items, isEmpty);
    },
  );

  test(
    'a change to a new item waiting joins it; deleting it drops it',
    () async {
      server.offline = true;
      final id = queue.create(WriteKind.location, {
        'name': 'Home',
        'hint': 'flat',
      });
      queue.update(WriteKind.location, id, {
        'hint': null,
        'map_location': '12 Fifth Ave',
      });
      await queue.flush();

      expect(queue.items.single.changes, {
        'name': 'Home',
        'map_location': '12 Fifth Ave',
      });

      queue.delete(WriteKind.location, id);
      await pumpEventQueue();
      expect(queue.items, isEmpty);
      expect(queue.shown(WriteKind.location, const []), isEmpty);
    },
  );

  test(
    "changes to one the server has join, made to the version last seen",
    () async {
      queue.shown(WriteKind.location, [
        {'id': 'loc1', 'name': 'Home', 'hint': 'flat', 'version': 4},
      ]);
      server.offline = true;
      queue.update(WriteKind.location, 'loc1', {'name': 'Flat'});
      queue.update(WriteKind.location, 'loc1', {'hint': null});
      await queue.flush();
      server.offline = false;
      server.calls.clear();
      await queue.retryNow();

      expect(server.calls.single.arguments, {
        'location': {'id': 'loc1', 'name': 'Flat', 'version': 4},
        'clear_fields': ['hint'],
      });
    },
  );

  test(
    'a write naming a new item waits for it; one after, to it too',
    () async {
      server.offline = true;
      final home = queue.create(WriteKind.location, {'name': 'Home'});
      queue.update(WriteKind.person, 'sam', {'context': 'lives at $home'});
      queue.update(WriteKind.person, 'kim', {
        'circles': ['family'],
      });
      await pumpEventQueue();

      final [making, naming, other] = queue.items;
      expect(queue.making, {home});
      // As the outbox asks: the first, and the one naming nothing waiting,
      // are due; the one naming it waits.
      server.offline = false;
      server.calls.clear();
      await queue.retryNow();
      expect(server.calls.map((c) => c.tool), [
        'create_location',
        'update_person',
        'update_person',
      ]);
      expect([making, naming, other], hasLength(3));
    },
  );

  test('changes waiting behind a write to the same item are made to what '
      'it saved', () async {
    queue.shown(WriteKind.location, [
      {'id': 'loc1', 'name': 'Home', 'version': 1},
    ]);
    final release = Completer<void>();
    server.answers.add((tool, arguments) async {
      await release.future;
      return {'id': 'loc1', 'name': 'Flat', 'version': 2};
    });
    queue.update(WriteKind.location, 'loc1', {'name': 'Flat'});
    await pumpEventQueue();
    final sending = queue.flush();
    await pumpEventQueue();
    // Being sent: a new change waits behind it, not in it.
    queue.update(WriteKind.location, 'loc1', {'hint': 'upstairs'});
    await pumpEventQueue();
    release.complete();
    await sending;
    await queue.flush();

    expect(server.calls.last.arguments, {
      'location': {'id': 'loc1', 'hint': 'upstairs', 'version': 2},
    });
  });

  test(
    'changed elsewhere in other fields: merged, made to it as it is',
    () async {
      queue.shown(WriteKind.location, [
        {'id': 'loc1', 'name': 'Home', 'hint': 'flat', 'version': 1},
      ]);
      server.answers.add(
        (_, _) => throw _conflict({
          'id': 'loc1',
          'name': 'Home',
          'hint': 'upstairs',
          'version': 2,
        }),
      );
      queue.update(WriteKind.location, 'loc1', {'name': 'Flat'});
      await queue.flush();

      expect(queue.items, isEmpty);
      expect(server.calls.last.arguments, {
        'location': {'id': 'loc1', 'name': 'Flat', 'version': 2},
      });
      // The same write: made once.
      expect(server.calls.map((c) => c.writeId).toSet(), hasLength(1));
    },
  );

  test('changed elsewhere in the same field: waits, conflicted, for the '
      'user -- who can keep theirs', () async {
    queue.shown(WriteKind.location, [
      {'id': 'loc1', 'name': 'Home', 'version': 1},
    ]);
    final elsewhere = {'id': 'loc1', 'name': 'House', 'version': 2};
    server.answers.add((_, _) => throw _conflict(elsewhere));
    queue.update(WriteKind.location, 'loc1', {'name': 'Flat'});
    await queue.flush();
    await pumpEventQueue();

    final waiting = queue.items.single;
    expect((waiting.conflicted, waiting.refused), (true, true));
    expect(waiting.current, elsewhere);

    await queue.overwrite(waiting);
    await queue.flush();
    expect(queue.items, isEmpty);
    expect(server.calls.last.arguments, {
      'location': {'id': 'loc1', 'name': 'Flat'},
    });
  });

  test('deleted elsewhere: waits, conflicted, with nothing as it is', () async {
    queue.shown(WriteKind.location, [
      {'id': 'loc1', 'name': 'Home', 'version': 1},
    ]);
    server.answers.add((_, _) => throw _conflict(null));
    queue.update(WriteKind.location, 'loc1', {'name': 'Flat'});
    await queue.flush();
    await pumpEventQueue();

    expect(queue.items.single.conflicted, isTrue);
    expect(queue.items.single.current, isNull);
    expect(queue.items.single.lastError, 'Deleted elsewhere since');
  });

  test('a deletion of one changed elsewhere waits to be asked about', () async {
    queue.shown(WriteKind.location, [
      {'id': 'loc1', 'name': 'Home', 'version': 1},
    ]);
    server.answers.add(
      (_, _) => throw _conflict({'id': 'loc1', 'name': 'House', 'version': 2}),
    );
    queue.delete(WriteKind.location, 'loc1');
    await queue.flush();
    await pumpEventQueue();

    expect(server.calls.single.arguments, {
      'location_id': 'loc1',
      'if_version': 1,
    });
    expect(queue.items.single.conflicted, isTrue);
  });

  test('what waits is kept on the device, for the next run', () async {
    final store = InMemoryOutboxStore<PendingWrite>();
    queue = make(store);
    server.offline = true;
    queue.shown(WriteKind.location, [
      {'id': 'loc1', 'name': 'Home', 'version': 3},
    ]);
    queue.update(WriteKind.location, 'loc1', {'hint': null});
    await queue.flush();

    final again = make(store);
    await again.refresh();
    final kept = PendingWrite.fromJson(again.items.single.toJson());
    expect(
      (kept.op, kept.itemId, kept.baseVersion),
      (WriteOp.update, 'loc1', 3),
    );
    expect(kept.changes, {'hint': null});
    again.dispose();
  });

  test("an event's write naming a location being made waits for it", () async {
    server.offline = true;
    final home = queue.create(WriteKind.location, {'name': 'Home'});
    await pumpEventQueue();
    final events = EventOutbox(
      store: InMemoryOutboxStore(),
      events: InMemoryEventsRepository(const []),
      making: () => queue.making,
    );
    await events.create({
      'summary': 'Lunch',
      'start': '2026-10-16T12:00:00',
      'end': '2026-10-16T13:00:00',
      'facts': {
        'location_ids': [home],
      },
    });

    expect(events.waits(events.pending.single), isTrue);
    server.offline = false;
    await queue.retryNow();
    expect(events.waits(events.pending.single), isFalse);
    events.dispose();
  });

  group('the people repository, with the queue', () {
    test('a location made offline is made at once, and shown', () async {
      final client = _Offline();
      final repository = McpPeopleRepository(
        client,
        cache: InMemoryResponseCache(),
        writes: WriteQueue(store: InMemoryOutboxStore(), call: server.call),
      );
      server.offline = true;

      final made = await repository.createLocation(
        const Location(id: '', name: 'Home', hint: 'the flat'),
      );

      expect(made.id, isNotEmpty);
      expect(made.name, 'Home');
    });
  });
}

class _Offline extends McpClient {
  _Offline() : super(endpoint: Uri.parse('http://localhost'));

  @override
  Future<Object?> callTool(
    String name, [
    Map<String, Object?> arguments = const {},
    String? writeId,
  ]) async => throw http.ClientException('Failed host lookup');
}
