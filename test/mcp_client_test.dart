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
        bearerToken: 'secret',
        httpClient: mock,
      ),
    );
    final notes = await repo.uncompactedNotes();

    expect(methods, ['initialize', 'notifications/initialized', 'tools/call']);
    expect(notes.map((n) => n.description), ['a', 'b']);
  });

  test('note serialises timestamps as UTC', () {
    final json = Note(
      timestamp: DateTime.utc(2026, 9, 28, 9),
      description: 'x',
    ).toJson();
    expect(json, {'timestamp': '2026-09-28T09:00:00.000Z', 'description': 'x'});
  });
}
