import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:time_tracker_client/models/note.dart';
import 'package:time_tracker_client/services/mcp_client.dart';
import 'package:time_tracker_client/services/notes_repository.dart';

void main() {
  test('handshakes, keeps the session id, and decodes SSE tool results', () async {
    final methods = <String>[];
    final mock = MockClient((request) async {
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      methods.add(body['method'] as String);
      expect(request.headers['Authorization'], 'Bearer secret');
      switch (body['method']) {
        case 'initialize':
          return http.Response(
            jsonEncode({
              'jsonrpc': '2.0',
              'id': body['id'],
              'result': {'protocolVersion': '2025-06-18'},
            }),
            200,
            headers: {
              'content-type': 'application/json',
              'mcp-session-id': 'abc',
            },
          );
        case 'notifications/initialized':
          return http.Response('', 202);
        default:
          expect(request.headers['Mcp-Session-Id'], 'abc');
          expect(body['params']['name'], 'get_notes');
          final result = {
            'content': [
              {'type': 'text', 'text': '[]'},
            ],
            'structuredContent': {
              'result': [
                {
                  'timestamp': '2026-09-28T16:00:00Z',
                  'description': 'b',
                  'compaction_id': null,
                },
                {
                  'timestamp': '2026-09-28T14:00:00Z',
                  'description': 'a',
                  'compaction_id': null,
                },
              ],
            },
          };
          return http.Response(
            'event: message\ndata: ${jsonEncode({'jsonrpc': '2.0', 'id': body['id'], 'result': result})}\n\n',
            200,
            headers: {'content-type': 'text/event-stream'},
          );
      }
    });

    final repo = McpNotesRepository(
      McpClient(
        endpoint: Uri.parse('https://example.com/mcp'),
        auth: _FixedAuth('secret'),
        httpClient: mock,
      ),
    );
    final notes = await repo.uncompactedNotes();

    expect(methods, ['initialize', 'notifications/initialized', 'tools/call']);
    expect(notes.map((n) => n.description), ['a', 'b']);
  });

  test('keeps note ids, and edits and deletes notes by id', () async {
    final calls = <Map<String, dynamic>>[];
    final mock = MockClient((request) async {
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      if (body['method'] != 'tools/call') {
        return http.Response(
          jsonEncode({'jsonrpc': '2.0', 'id': body['id'], 'result': {}}),
          body['id'] == null ? 202 : 200,
          headers: {'content-type': 'application/json'},
        );
      }
      final params = body['params'] as Map<String, dynamic>;
      calls.add(params);
      final Object structured = switch (params['name']) {
        'get_notes' => {
          'result': [
            {
              'id': '2026-09-28T14:00:00+00:00#7',
              'timestamp': '2026-09-28T14:00:00+00:00',
              'description': 'a',
            },
          ],
        },
        'edit_note' => {
          'id': '2026-09-28T15:00:00+00:00#7',
          'timestamp': '2026-09-28T15:00:00+00:00',
          'description': 'b',
        },
        _ => {'timestamp': '2026-09-28T15:00:00+00:00'},
      };
      return http.Response(
        jsonEncode({
          'jsonrpc': '2.0',
          'id': body['id'],
          'result': {'content': [], 'structuredContent': structured},
        }),
        200,
        headers: {'content-type': 'application/json'},
      );
    });
    final repo = McpNotesRepository(
      McpClient(
        endpoint: Uri.parse('https://example.com/mcp'),
        auth: _FixedAuth('secret'),
        httpClient: mock,
      ),
    );

    final note = (await repo.uncompactedNotes()).single;
    expect(note.id, '2026-09-28T14:00:00+00:00#7');

    final edited = await repo.editNote(
      note.id!,
      timestamp: DateTime.utc(2026, 9, 28, 15),
      description: 'b',
    );
    expect(edited.id, '2026-09-28T15:00:00+00:00#7');
    final editArgs = calls[1]['arguments'] as Map<String, dynamic>;
    expect(calls[1]['name'], 'edit_note');
    expect(editArgs['note_id'], '2026-09-28T14:00:00+00:00#7');
    expect(
      DateTime.parse(editArgs['timestamp'] as String)
          .isAtSameMomentAs(DateTime.utc(2026, 9, 28, 15)),
      isTrue,
    );
    expect(editArgs['description'], 'b');

    // Only what changed is sent.
    await repo.editNote(edited.id!, description: '');
    expect(calls[2]['arguments'], {
      'note_id': '2026-09-28T15:00:00+00:00#7',
      'description': '',
    });

    await repo.deleteNote(edited.id!);
    expect(calls[3]['name'], 'delete_note');
    expect(calls[3]['arguments'], {'note_id': '2026-09-28T15:00:00+00:00#7'});
  });

  test('the in-memory store edits and deletes like the server', () async {
    final repo = InMemoryNotesRepository();
    final note = await repo.addNote(
      Note(timestamp: DateTime(2026, 9, 28, 14), description: 'a'),
    );
    expect(note.id, endsWith('#1'));

    final described = await repo.editNote(note.id!, description: 'b');
    expect(described.id, note.id); // same time, same id
    final retimed = await repo.editNote(
      note.id!,
      timestamp: DateTime(2026, 9, 28, 15),
    );
    expect(retimed.id, isNot(note.id));
    expect(retimed.description, 'b');
    await expectLater(repo.editNote(note.id!), throwsA(isA<McpException>()));

    await repo.editNote(retimed.id!, description: '');
    expect((await repo.uncompactedNotes()).single.description, isNull);
    await repo.deleteNote(retimed.id!);
    expect(await repo.uncompactedNotes(), isEmpty);
  });

  test('refreshes once on 401, then asks for sign-in', () async {
    final auth = _FixedAuth('old');
    final seen = <String?>[];
    final mock = MockClient((request) async {
      seen.add(request.headers['Authorization']);
      return http.Response('', 401);
    });
    final client = McpClient(
      endpoint: Uri.parse('https://example.com/mcp'),
      auth: auth,
      httpClient: mock,
    );

    await expectLater(
      client.callTool('get_notes'),
      throwsA(isA<SignInRequiredException>()),
    );
    expect(seen, ['Bearer old', 'Bearer old-refreshed']);
  });

  test('note sends its timestamp in the device time zone, with offset', () {
    final instant = DateTime.utc(2026, 9, 28, 9);
    final local = instant.toLocal();
    final json = Note(timestamp: instant, description: 'x').toJson();

    final sent = json['timestamp'] as String;
    expect(
      sent,
      startsWith(isoTimestampWithOffset(local, Duration.zero).substring(0, 19)),
      reason: 'local wall-clock time',
    );
    expect(sent, matches(RegExp(r'[+-]\d\d:\d\d$')), reason: 'an offset');
    expect(DateTime.parse(sent).isAtSameMomentAs(instant), isTrue);
    expect(json['description'], 'x');
  });

  test('formats offsets on either side of UTC', () {
    final wallClock = DateTime(2026, 9, 30, 8, 15, 4);
    expect(
      isoTimestampWithOffset(wallClock, const Duration(hours: -7)),
      '2026-09-30T08:15:04-07:00',
    );
    expect(
      isoTimestampWithOffset(wallClock, const Duration(hours: 5, minutes: 30)),
      '2026-09-30T08:15:04+05:30',
    );
    expect(
      isoTimestampWithOffset(wallClock, Duration.zero),
      '2026-09-30T08:15:04+00:00',
    );
    expect(
      isoTimestampWithOffset(
        DateTime(2026, 1, 2, 3, 4, 5, 60, 7),
        const Duration(hours: -3, minutes: -30),
      ),
      '2026-01-02T03:04:05.060007-03:30',
    );
  });

  test('round-trips through JSON as the same moment', () {
    final note = Note(timestamp: DateTime(2026, 9, 30, 8, 15, 4, 250));
    final parsed = Note.fromJson(note.toJson()).timestamp;
    expect(parsed.isAtSameMomentAs(note.timestamp), isTrue);
  });
}

class _FixedAuth implements McpAuth {
  _FixedAuth(this.token);
  String token;

  @override
  Future<String> accessToken() async => token;

  @override
  Future<void> rejected(String accessToken) async =>
      token = '$accessToken-refreshed';
}
