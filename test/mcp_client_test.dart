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
