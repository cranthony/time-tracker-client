import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:time_tracker_client/auth/sign_in_mode.dart';
import 'package:time_tracker_client/main.dart';
import 'package:time_tracker_client/outbox/action_outbox.dart';
import 'package:time_tracker_client/outbox/note_outbox.dart';
import 'package:time_tracker_client/outbox/outbox_store.dart';
import 'package:time_tracker_client/services/actions_repository.dart';
import 'package:time_tracker_client/services/events_repository.dart';
import 'package:time_tracker_client/services/notes_repository.dart';
import 'package:time_tracker_client/services/mcp_client.dart';
import 'package:time_tracker_client/widgets/sign_in_off_banner.dart';

/// A server that answers the handshake with [handshake] and every tool
/// call with `[]`, or a 401 every time with [wantsToken]; [seen] gets each
/// request's Authorization header.
MockClient _server(
  List<String?> seen, {
  Map<String, Object?> handshake = const {'protocolVersion': '2025-06-18'},
  bool wantsToken = false,
}) => MockClient((request) async {
  seen.add(request.headers['Authorization']);
  if (wantsToken) return http.Response('', 401);
  final body = jsonDecode(request.body) as Map<String, dynamic>;
  if (body['method'] == 'notifications/initialized') {
    return http.Response('', 202);
  }
  final result = body['method'] == 'initialize'
      ? handshake
      : {
          'content': [
            {'type': 'text', 'text': '[]'},
          ],
        };
  return http.Response(
    jsonEncode({'jsonrpc': '2.0', 'id': body['id'], 'result': result}),
    200,
    headers: {'content-type': 'application/json', 'mcp-session-id': 's'},
  );
});

class _FixedAuth implements McpAuth {
  @override
  Future<String> accessToken() async => 'secret';

  @override
  Future<void> rejected(String accessToken) async {}
}

void main() {
  test('true, 1 and yes, in any case, turn sign-in off', () {
    for (final value in ['true', 'TRUE', 'True', '1', 'yes', ' yes ']) {
      expect(turnsSignInOff(value), isTrue, reason: value);
    }
    for (final value in ['', 'false', '0', 'no', 'on', 'truee']) {
      expect(turnsSignInOff(value), isFalse, reason: value);
    }
  });

  test('this build says which it is', () {
    expect(
      signInOff,
      turnsSignInOff(const String.fromEnvironment('DISABLE_AUTH')),
    );
    expect(appName, signInOff ? 'Time Tracker (no sign-in)' : 'Time Tracker');
  });

  group('signing in off', () {
    test('sends no token, even with a way to get one', () async {
      final seen = <String?>[];
      final client = McpClient(
        endpoint: Uri.parse('https://corp.example/mcp'),
        signInOff: true,
        httpClient: _server(seen),
      );

      await client.callTool('get_notes', {});

      expect(seen, hasLength(3));
      expect(seen.nonNulls, isEmpty);
    });

    test('says so when the server wants a token', () async {
      final client = McpClient(
        endpoint: Uri.parse('https://corp.example/mcp'),
        signInOff: true,
        httpClient: _server([], wantsToken: true),
      );

      await expectLater(
        client.callTool('get_notes', {}),
        throwsA(
          isA<ServerRequiresSignInException>().having(
            (e) => e.message,
            'message',
            allOf(
              contains('https://corp.example/mcp requires it'),
              contains('AUTH_DISABLED'),
            ),
          ),
        ),
      );
    });

    test('a signed-in client still sends its token', () async {
      final seen = <String?>[];
      final client = McpClient(
        endpoint: Uri.parse('https://corp.example/mcp'),
        auth: _FixedAuth(),
        httpClient: _server(seen),
      );

      await client.callTool('get_notes', {});

      expect(seen.toSet(), {'Bearer secret'});
    });
  });

  test("learns from the server's handshake whether it skips sign-in", () async {
    final off = ValueNotifier(false);
    final client = McpClient(
      endpoint: Uri.parse('https://corp.example/mcp'),
      auth: _FixedAuth(),
      serverSignInOff: off,
      httpClient: _server(
        [],
        handshake: {
          'protocolVersion': '2025-06-18',
          'serverInfo': {
            'name': 'time-tracking',
            'version': '',
            'title': 'time-tracking (sign-in off)',
          },
          'instructions': 'Authentication is disabled in this build.',
        },
      ),
    );

    await client.callTool('get_notes', {});

    expect(off.value, isTrue);
    expect(handshakeSaysSignInOff({'protocolVersion': '2025-06-18'}), isFalse);
  });

  group('the banner', () {
    Future<void> pump(
      WidgetTester tester, {
      required bool thisBuild,
      required ValueNotifier<bool> server,
    }) => tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => SignInOffBanner(
          thisBuild: thisBuild,
          server: server,
          child: child!,
        ),
        home: const Scaffold(body: Text('Events')),
      ),
    );

    testWidgets('is over every screen of a build with sign-in off', (
      tester,
    ) async {
      await pump(tester, thisBuild: true, server: ValueNotifier(false));

      expect(
        find.text('Sign-in off: this build trusts its network'),
        findsOneWidget,
      );
      expect(
        tester.getTopLeft(find.byIcon(Icons.lock_open)).dy,
        lessThan(tester.getTopLeft(find.text('Events')).dy),
      );
    });

    testWidgets('shows, too, when the server says it skips sign-in', (
      tester,
    ) async {
      final server = ValueNotifier(false);
      await pump(tester, thisBuild: false, server: server);
      expect(find.byIcon(Icons.lock_open), findsNothing);

      server.value = true;
      await tester.pump();

      expect(
        find.text('Sign-in off: the server trusts every request'),
        findsOneWidget,
      );
    });
  });

  testWidgets('the app has the banner, and says so in its title, exactly when '
      'this build skips sign-in', (tester) async {
    final notes = InMemoryNotesRepository();
    final actions = InMemoryActionsRepository();
    await tester.pumpWidget(
      TimeTrackerApp(
        repository: notes,
        eventsRepository: InMemoryEventsRepository(),
        actionsRepository: actions,
        outbox: NoteOutbox(store: InMemoryOutboxStore(), repository: notes),
        actionOutbox: ActionOutbox(
          store: InMemoryOutboxStore(),
          repository: actions,
        ),
      ),
    );
    await tester.pump();

    expect(
      find.text('Sign-in off: this build trusts its network'),
      signInOff ? findsOneWidget : findsNothing,
    );
    expect(tester.widget<MaterialApp>(find.byType(MaterialApp)).title, appName);
  });
}
