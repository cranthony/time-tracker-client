import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:time_tracker_client/services/mcp_client.dart';
import 'package:time_tracker_client/services/server_errors.dart';
import 'package:time_tracker_client/widgets/error_sheet.dart';

/// A server that answers the handshake, and each `tools/call` with what
/// [toolCall] says -- counting them.
class _Server {
  _Server(this.toolCall);

  final Future<http.Response> Function(int call, Map<String, dynamic> body)
  toolCall;
  int initializes = 0;
  int calls = 0;

  /// Thrown by the next handshake, if set.
  Object? failHandshake;

  late final client = McpClient(
    endpoint: Uri.parse('https://example.com/mcp'),
    httpClient: MockClient(_answer),
    retryDelays: const [Duration.zero, Duration.zero, Duration.zero],
  );

  Future<http.Response> _answer(http.Request request) async {
    final body = jsonDecode(request.body) as Map<String, dynamic>;
    switch (body['method']) {
      case 'initialize':
        if (failHandshake case final error?) {
          failHandshake = null;
          throw error;
        }
        initializes++;
        return http.Response(
          jsonEncode({'jsonrpc': '2.0', 'id': body['id'], 'result': {}}),
          200,
          headers: {
            'content-type': 'application/json',
            'mcp-session-id': 'session$initializes',
          },
        );
      case 'notifications/initialized':
        return http.Response('', 202);
      default:
        return toolCall(++calls, body);
    }
  }
}

http.Response _result(Map<String, dynamic> body, Object? value) =>
    http.Response(
      jsonEncode({
        'jsonrpc': '2.0',
        'id': body['id'],
        'result': {
          'content': const [],
          'structuredContent': {'result': value},
        },
      }),
      200,
      headers: {'content-type': 'application/json'},
    );

void main() {
  group('McpClient retries', () {
    test(
      'a session the server forgot is started again, for any call',
      () async {
        final server = _Server(
          (call, body) async => call == 1
              ? http.Response('Bad Request: No valid session ID provided', 400)
              : _result(body, 'ok'),
        );

        expect(await server.client.callTool('amend_proposal'), 'ok');
        expect((server.initializes, server.calls), (2, 2));
      },
    );

    test(
      'a call that only reads is sent again after the connection resets',
      () async {
        final server = _Server((call, body) async {
          if (call < 3) throw http.ClientException('Connection reset by peer');
          return _result(body, 'ok');
        });

        expect(await server.client.callTool('get_proposal'), 'ok');
        expect(server.calls, 3);
      },
    );

    test('and after the server has trouble', () async {
      final server = _Server(
        (call, body) async =>
            call == 1 ? http.Response('busy', 503) : _result(body, 'ok'),
      );

      expect(await server.client.callTool('list_events'), 'ok');
    });

    test(
      'a write that may have reached the server is not sent again',
      () async {
        final server = _Server(
          (call, body) async =>
              throw http.ClientException('Connection reset by peer'),
        );

        await expectLater(
          server.client.callTool('confirm_proposal'),
          throwsA(isA<http.ClientException>()),
        );
        expect(server.calls, 1);
      },
    );

    test('a write is sent again when it never reached the server', () async {
      final server = _Server((call, body) async => _result(body, 'ok'))
        ..failHandshake = http.ClientException(
          'Connection closed while receiving data',
        );

      expect(await server.client.callTool('confirm_proposal'), 'ok');
      expect(server.calls, 1);
    });

    test('gives up after its retries, with the last error', () async {
      final server = _Server(
        (call, body) async =>
            throw http.ClientException('Connection reset by peer'),
      );

      await expectLater(
        server.client.callTool('get_notes'),
        throwsA(isA<http.ClientException>()),
      );
      expect(server.calls, 4);
    });

    test("a tool's refusal is never sent again", () async {
      final server = _Server(
        (call, body) async => http.Response(
          jsonEncode({
            'jsonrpc': '2.0',
            'id': body['id'],
            'result': {
              'isError': true,
              'content': [
                {'type': 'text', 'text': 'That note was compacted'},
              ],
            },
          }),
          200,
          headers: {'content-type': 'application/json'},
        ),
      );

      await expectLater(
        server.client.callTool('get_notes'),
        throwsA(
          isA<McpException>().having(
            (e) => e.serverMessage,
            'serverMessage',
            'That note was compacted',
          ),
        ),
      );
      expect(server.calls, 1);
    });
  });

  group('describeServerError', () {
    test('says what kind of failure it was, in words', () {
      expect(
        describeServerError(SignInRequiredException()).kind,
        FailureKind.signIn,
      );
      expect(
        describeServerError(http.ClientException('Connection reset')).kind,
        FailureKind.connection,
      );
      expect(
        describeServerError(TimeoutException('slow')).kind,
        FailureKind.timeout,
      );
      expect(
        describeServerError(
          McpException('tools/call: HTTP 502', statusCode: 502),
        ).kind,
        FailureKind.server,
      );
      final refused = describeServerError(
        McpException('Tool amend_proposal failed: Overlaps lunch'),
      );
      expect(
        (refused.kind, refused.message),
        (FailureKind.refused, 'Overlaps lunch'),
      );
      expect(refused.transient, isFalse);
    });
  });

  group('the error sheet', () {
    Future<void> show(
      WidgetTester tester,
      Future<void> Function(BuildContext) open,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => open(context),
                child: const Text('Go'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Go'));
      await tester.pumpAndSettle();
    }

    testWidgets('offers to try again after a failure that might pass', (
      tester,
    ) async {
      var retried = 0;
      await show(
        tester,
        (context) => showErrorSheet(
          context,
          title: "Couldn't move it",
          error: http.ClientException('Connection reset by peer'),
          onRetry: () => retried++,
        ),
      );

      expect(find.text("Couldn't move it"), findsOneWidget);
      expect(
        find.text("Couldn't reach the server, or the connection dropped."),
        findsOneWidget,
      );
      expect(find.text('This is usually brief.'), findsOneWidget);
      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();
      expect(retried, 1);
      expect(find.byType(ErrorSheet), findsNothing);
    });

    testWidgets("doesn't, after a refusal or being signed out", (tester) async {
      for (final error in [
        McpException('No room for it.'),
        SignInRequiredException(),
      ]) {
        await show(
          tester,
          (context) => showErrorSheet(
            context,
            title: "Couldn't save",
            error: error,
            onRetry: () {},
          ),
        );
        expect(find.text('Try again'), findsNothing);
        await tester.tap(find.text('Close'));
        await tester.pumpAndSettle();
      }
    });

    testWidgets('runOrShowError runs it again until it works', (tester) async {
      var tries = 0;
      bool? ran;
      await show(tester, (context) async {
        ran = await runOrShowError(
          context,
          title: "Couldn't save",
          action: () async {
            if (++tries < 3) throw TimeoutException('slow');
          },
        );
      });

      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();
      expect((tries, ran), (3, true));
      expect(find.byType(ErrorSheet), findsNothing);
    });
  });
}
