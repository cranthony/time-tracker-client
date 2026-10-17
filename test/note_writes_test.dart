import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:time_tracker_client/models/note.dart';
import 'package:time_tracker_client/outbox/note_writes.dart';
import 'package:time_tracker_client/outbox/legacy_writes.dart';
import 'package:time_tracker_client/outbox/outbox_store.dart';
import 'package:time_tracker_client/outbox/write_queue.dart';
import 'package:time_tracker_client/services/mcp_client.dart';
import 'package:time_tracker_client/services/notes_repository.dart';

/// The server's notes, for reads: one, at version 2.
class _Client extends McpClient {
  _Client() : super(endpoint: Uri.parse('http://localhost'));

  @override
  Future<Object?> callTool(
    String name, [
    Map<String, Object?> arguments = const {},
    String? writeId,
  ]) async => switch (name) {
    'get_notes' => [
      {
        'id': 'tea',
        'timestamp': '2026-10-16T09:00:00+00:00',
        'description': 'Tea',
        'compaction_id': null,
        'version': 2,
      },
    ],
    _ => throw http.ClientException('offline'),
  };
}

McpException _conflict(Map<String, Object?>? current) => McpException(
  'Tool failed: changed after version 2 was read',
  serverMessage: 'changed after version 2 was read',
  meta: {
    'conflict': {'current': current},
  },
);

void main() {
  late List<({String tool, Map<String, Object?> arguments})> calls;
  late List<Object? Function(Map<String, Object?> arguments)> answers;
  late WriteQueue queue;
  late NoteWrites notes;
  late McpNotesRepository repository;

  setUp(() {
    calls = [];
    answers = [];
    queue = WriteQueue(
      store: InMemoryOutboxStore(),
      call: (tool, arguments) async {
        calls.add((tool: tool, arguments: arguments));
        if (answers.isEmpty) throw http.ClientException('offline');
        return answers.removeAt(0)(arguments);
      },
    );
    notes = NoteWrites(queue);
    repository = McpNotesRepository(_Client(), writes: queue);
  });

  tearDown(() => queue.dispose());

  test('a new note is made with an id of its own, in whole seconds', () async {
    final added = await notes.add(
      Note(
        timestamp: DateTime.utc(2026, 10, 16, 9, 30, 5, 250),
        description: 'Up',
      ),
    );
    answers.add(
      (arguments) => {...(arguments['noted_time'] as Map), 'version': 1},
    );
    await queue.flush();

    final made = calls.single.arguments['noted_time'] as Map;
    expect(made['id'], added.note.id);
    expect(
      DateTime.parse(made['timestamp'] as String),
      DateTime.utc(2026, 10, 16, 9, 30, 5),
    );
    expect(made['description'], 'Up');
  });

  test(
    'an edit is made to the version read, and sends only what changed',
    () async {
      final [tea] = await repository.uncompactedNotes();
      await notes.edit(
        tea,
        Note(timestamp: tea.timestamp, description: 'Green tea', id: tea.id),
      );
      answers.add((arguments) => {'id': 'tea', 'version': 3});
      await queue.flush();

      expect(calls.single.tool, 'edit_note');
      expect(calls.single.arguments, {
        'note_id': 'tea',
        'description': 'Green tea',
        'version': 2,
      });
    },
  );

  test("a second edit takes the first's place; one back to how it was "
      'leaves nothing waiting', () async {
    final [tea] = await repository.uncompactedNotes();
    Note said(String text) =>
        Note(timestamp: tea.timestamp, description: text, id: tea.id);

    await notes.edit(tea, said('Green tea'));
    await notes.edit(tea, said('Mint tea'));
    expect(notes.pending.single.note.description, 'Mint tea');
    expect(notes.pending.single.original!.description, 'Tea');

    await notes.edit(tea, said('Tea'));
    expect(notes.pending, isEmpty);
  });

  test(
    'changed elsewhere in the same field: waits, conflicted, for the user',
    () async {
      final [tea] = await repository.uncompactedNotes();
      await notes.edit(
        tea,
        Note(timestamp: tea.timestamp, description: 'Green tea', id: tea.id),
      );
      answers.add(
        (_) => throw _conflict({
          'id': 'tea',
          'timestamp': '2026-10-16T09:00:00+00:00',
          'description': 'Black tea',
          'version': 3,
        }),
      );
      await queue.flush();

      final waiting = queue.items.single;
      expect((waiting.conflicted, waiting.refused), (true, true));
      expect(WriteQueue.clashes(waiting), ['description']);
    },
  );

  test('a deletion takes the place of an edit not tried yet, and can be '
      'taken back', () async {
    final [tea] = await repository.uncompactedNotes();
    await notes.edit(
      tea,
      Note(timestamp: tea.timestamp, description: 'Green tea', id: tea.id),
    );
    final deletion = await notes.delete(tea);

    expect(notes.pending.map((p) => p.change), [NoteChange.delete]);
    expect(await notes.cancel(deletion), isTrue);
    expect(notes.pending, isEmpty);
    await notes.restore(deletion);
    answers.add((arguments) => {'id': 'tea'});
    await queue.flush();
    expect(calls.single.arguments, {'note_id': 'tea', 'if_version': 2});
  });

  group('what an older version left waiting', () {
    late SharedPreferencesAsync prefs;

    setUp(() {
      SharedPreferencesAsyncPlatform.instance =
          InMemorySharedPreferencesAsync.empty();
      prefs = SharedPreferencesAsync();
    });

    test('its notes, edits and deletions are read into the queue, each '
        'once', () async {
      final kept = jsonEncode([
        {
          'id': '1760605200000000-42',
          'note': {
            'timestamp': '2026-10-16T09:00:00+00:00',
            'description': 'Up',
          },
          'attempts': 2,
        },
        {
          'id': 'e1',
          'change': 'edit',
          'note': {
            'timestamp': '2026-10-16T10:00:00+00:00',
            'description': 'Lunch',
          },
          'original': {
            'id': '2026-10-16T10:00:00+00:00#3',
            'timestamp': '2026-10-16T10:00:00+00:00',
            'description': 'Brunch',
          },
        },
        {
          'id': 'd1',
          'change': 'delete',
          'note': {'timestamp': '2026-10-16T11:00:00+00:00'},
          'original': {
            'id': '2026-10-16T11:00:00+00:00#4',
            'timestamp': '2026-10-16T11:00:00+00:00',
          },
        },
      ]);
      await prefs.setString('note_outbox', kept);
      final store = WriteQueueStore(prefs: prefs);

      final writes = await store.load();
      expect(writes.map((w) => (w.kind, w.op, w.itemId)), [
        ('note', WriteOp.create, 'n1760605200000000-42'),
        ('note', WriteOp.update, '2026-10-16T10:00:00+00:00#3'),
        ('note', WriteOp.delete, '2026-10-16T11:00:00+00:00#4'),
      ]);
      expect(writes.first.attempts, 2);
      expect(writes[1].changes, {'description': 'Lunch'});
      expect(NoteWrites.view(writes.first)!.note.description, 'Up');

      await store.save(writes);
      expect(await prefs.getString('note_outbox'), isNull);
      // Read in again -- the app closed before the old store was emptied.
      await prefs.setString('note_outbox', kept);
      expect((await store.load()).length, 3);
    });

    test('one added meanwhile -- by an older window, still open on the '
        "web -- isn't taken out with what was read in", () async {
      Map<String, Object?> note(String id, String text) => {
        'id': id,
        'note': {'timestamp': '2026-10-16T09:00:00+00:00', 'description': text},
      };
      await prefs.setString('note_outbox', jsonEncode([note('a1', 'Up')]));
      final store = WriteQueueStore(prefs: prefs);
      final writes = await store.load();
      await prefs.setString(
        'note_outbox',
        jsonEncode([note('a1', 'Up'), note('a2', 'Tea')]),
      );

      await store.save(writes);

      final left = jsonDecode((await prefs.getString('note_outbox'))!) as List;
      expect(left.map((e) => (e as Map)['id']), ['a2']);
      expect(
        (await store.load()).map((w) => NoteWrites.view(w)!.note.description),
        ['Tea', 'Up'],
      );
    });

    test("what can't be read stays where it is, rather than be lost", () async {
      await prefs.setString(
        'note_outbox',
        jsonEncode([
          {
            'id': 'a1',
            'note': {'timestamp': '2026-10-16T09:00:00+00:00'},
          },
          {'id': 'odd', 'note': 'from a version this one does not know'},
        ]),
      );
      final store = WriteQueueStore(prefs: prefs);

      final writes = await store.load();
      expect(writes, hasLength(1));
      await store.save(writes);

      final left = jsonDecode((await prefs.getString('note_outbox'))!) as List;
      expect(left.map((e) => (e as Map)['id']), ['odd']);
      // Nor a store that isn't JSON at all: the queue reads on without it.
      await prefs.setString('goal_outbox', 'not json');
      expect(await store.load(), hasLength(1));
      await store.save(await store.load());
      expect(await prefs.getString('goal_outbox'), 'not json');
    });
  });
}
