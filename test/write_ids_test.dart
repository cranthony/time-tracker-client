import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:time_tracker_client/models/note.dart';
import 'package:time_tracker_client/outbox/action_outbox.dart';
import 'package:time_tracker_client/outbox/note_outbox.dart';
import 'package:time_tracker_client/outbox/outbox_store.dart';
import 'package:time_tracker_client/outbox/write_queue.dart';
import 'package:time_tracker_client/services/actions_repository.dart';
import 'package:time_tracker_client/services/mcp_client.dart';
import 'package:time_tracker_client/services/notes_repository.dart';

/// A server over HTTP: each tools/call's name and write_id recorded; a
/// call fails, unanswered, while [failing] says so.
class _Server {
  final calls = <(String, String?)>[];
  var failing = 0;

  late final client = McpClient(
    endpoint: Uri.parse('https://example.com/mcp'),
    httpClient: MockClient((request) async {
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      Map<String, Object?> result = {};
      switch (body['method']) {
        case 'notifications/initialized':
          return http.Response('', 202);
        case 'tools/call':
          final params = body['params'] as Map;
          calls.add((
            params['name'] as String,
            (params['_meta'] as Map?)?['write_id'] as String?,
          ));
          if (failing > 0) {
            failing--;
            return http.Response('', 503);
          }
          result = {
            'content': [
              {'type': 'text', 'text': '{}'},
            ],
            'structuredContent': switch (params['name']) {
              'get_notes' => {'result': <Object?>[]},
              _ => {
                'timestamp': '2026-10-16T12:00:00Z',
                'description': 'Tea',
                'id': 'n1',
              },
            },
          };
      }
      return http.Response(
        jsonEncode({'jsonrpc': '2.0', 'id': body['id'], 'result': result}),
        200,
        headers: {'content-type': 'application/json'},
      );
    }),
  );
}

void main() {
  test('a write made in a scope has a write_id from it, numbered by tool, '
      'the same each time', () async {
    Future<List<String>> ids() => WriteScope.run('item1', () async {
      final scope = WriteScope.current!;
      return [
        scope.next('update_event'),
        scope.next('update_event'),
        scope.next('note'),
      ];
    });

    expect(await ids(), [
      'item1/update_event',
      'item1/update_event/2',
      'item1/note',
    ]);
    expect(await ids(), await ids());
    expect(WriteScope.current, isNull);
  });

  test("a note's write is sent with its write_id, the same when it's tried "
      'again; a read with none', () async {
    final server = _Server()..failing = 1;
    final outbox = NoteOutbox(
      store: InMemoryOutboxStore(),
      repository: McpNotesRepository(server.client),
    );
    final pending = await outbox.add(
      Note(timestamp: DateTime.utc(2026, 10, 16, 12), description: 'Tea'),
    );
    await outbox.flush();
    await outbox.retryNow();

    final writes = [
      for (final (tool, id) in server.calls)
        if (tool == 'note') id,
    ];
    expect(writes, hasLength(greaterThanOrEqualTo(2)));
    expect(writes.toSet(), {'${pending.id}/note'});
    // The read checking whether it was made: no write_id.
    expect([
      for (final (tool, id) in server.calls)
        if (tool == 'get_notes') id,
    ], everyElement(isNull));
    outbox.dispose();
  });

  test('a change to a write that was tried is a write of its own', () async {
    var offline = true;
    final queue = WriteQueue(
      store: InMemoryOutboxStore(),
      call: (tool, arguments, writeId) async => offline
          ? throw http.ClientException('offline')
          : {arguments.keys.first: arguments.values.first},
    );
    final id = queue.create(WriteKind.location, {'name': 'Home'});
    await queue.flush();
    final tried = queue.items.single;

    queue.update(WriteKind.location, id, {'hint': 'flat'});
    await pumpEventQueue();

    expect(queue.items, hasLength(2));
    expect(queue.items.first.id, tried.id);
    expect(queue.items.first.changes, {'name': 'Home'});
    expect(queue.items.last.op, WriteOp.update);
    // Waits for the create; deleting it now follows it, too.
    queue.delete(WriteKind.location, id);
    await pumpEventQueue();
    expect(queue.items.map((w) => w.op), [WriteOp.create, WriteOp.delete]);
    offline = false;
    queue.dispose();
  });

  test("a change to an action save that was tried is a new write", () async {
    final repository = _FailingActions();
    final outbox = ActionOutbox(
      store: InMemoryOutboxStore(),
      repository: repository,
    );
    outbox.update('a1', {'name': 'Run'}, group: false);
    await pumpEventQueue();
    final first = outbox.saves.single.id;
    await outbox.flush();
    outbox.update('a1', {'note': 'fast'}, group: false);
    await pumpEventQueue();

    expect(outbox.saves.single.id, isNot(first));
    expect(outbox.saves.single.changes, {'name': 'Run', 'note': 'fast'});
    outbox.dispose();
  });
}

class _FailingActions extends InMemoryActionsRepository {
  @override
  Future<void> updateAction(action, Map<String, Object?> changes) async =>
      throw http.ClientException('offline');
}
