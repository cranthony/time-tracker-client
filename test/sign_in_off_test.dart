import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:time_tracker_client/auth/sign_in_mode.dart';
import 'package:time_tracker_client/services/mcp_client.dart';
import 'package:time_tracker_client/services/server_client.dart';
import 'package:time_tracker_client/widgets/sign_in_off_banner.dart';

/// A server that answers the handshake with [handshake] and every tool
/// call with `[]` -- or, with [wantsToken], a 401 to any request without
/// one; [seen] gets each request's Authorization header.
MockClient _server(
  List<String?> seen, {
  Map<String, Object?> handshake = const {'protocolVersion': '2025-06-18'},
  bool wantsToken = false,
}) => MockClient((request) async {
  final authorization = request.headers['Authorization'];
  seen.add(authorization);
  if (wantsToken && authorization == null) return http.Response('', 401);
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

/// Signed in, with a token.
class _FixedAuth implements McpAuth {
  @override
  Future<String> accessToken() async => 'secret';

  @override
  Future<void> rejected(String accessToken) async {}
}

/// Never signed in.
class _SignedOut implements McpAuth {
  @override
  Future<String> accessToken() async => throw SignInRequiredException();

  @override
  Future<void> rejected(String accessToken) async {}
}

const _noSignIn = {
  'protocolVersion': '2025-06-18',
  '_meta': {authDisabledMetaKey: true},
};

void main() {
  tearDown(() => serverSignInOff.value = false);

  group('connecting before signing in', () {
    test('a server that skips sign-in is used without one', () async {
      final seen = <String?>[];
      final client = McpClient(
        endpoint: Uri.parse('https://corp.example/mcp'),
        auth: _SignedOut(),
        httpClient: _server(seen, handshake: _noSignIn),
      );

      await client.callTool('get_notes', {});

      expect(seen, hasLength(3));
      expect(seen.nonNulls, isEmpty);
    });

    test('a server that wants a token asks for sign-in', () async {
      final client = McpClient(
        endpoint: Uri.parse('https://corp.example/mcp'),
        auth: _SignedOut(),
        httpClient: _server([], wantsToken: true),
      );

      await expectLater(
        client.callTool('get_notes', {}),
        throwsA(isA<SignInRequiredException>()),
      );
    });

    test('signed in, it sends its token', () async {
      final seen = <String?>[];
      final client = McpClient(
        endpoint: Uri.parse('https://corp.example/mcp'),
        auth: _FixedAuth(),
        httpClient: _server(seen, wantsToken: true),
      );

      await client.callTool('get_notes', {});

      expect(seen.toSet(), {'Bearer secret'});
    });
  });

  test(
    "learns from the server's handshake flag whether it skips sign-in",
    () async {
      Future<bool> says(Map<String, Object?> handshake) async {
        final off = ValueNotifier(false);
        await McpClient(
          endpoint: Uri.parse('https://corp.example/mcp'),
          auth: _FixedAuth(),
          serverSignInOff: off,
          httpClient: _server([], handshake: handshake),
        ).callTool('get_notes', {});
        return off.value;
      }

      expect(await says(_noSignIn), isTrue);
      // The words are for people: only the flag counts.
      expect(
        await says({
          'protocolVersion': '2025-06-18',
          'serverInfo': {'name': 'time-tracking', 'title': 'x (sign-in off)'},
          'instructions': 'Authentication is disabled in this build.',
        }),
        isFalse,
      );
      expect(
        await says({
          'protocolVersion': '2025-06-18',
          '_meta': {authDisabledMetaKey: 'yes'},
        }),
        isFalse,
      );
    },
  );

  testWidgets(
    "the app's client, never signed in, turns the banner on for a server "
    'that skips sign-in',
    (tester) async {
      // As the app makes it.
      final client = serverClient(
        Uri.parse('https://corp.example/mcp'),
        auth: _SignedOut(),
        httpClient: _server([], handshake: _noSignIn),
      );
      await tester.pumpWidget(
        MaterialApp(
          // The banner as the app has it: listening to what its clients
          // learn.
          builder: (context, child) => SignInOffBanner(child: child!),
          home: const Scaffold(body: Text('Events')),
        ),
      );
      expect(find.byIcon(Icons.lock_open), findsNothing);

      await tester.runAsync(() => client.callTool('get_notes', {}));
      await tester.pump();

      expect(find.text(SignInOffBanner.text), findsOneWidget);
      expect(
        tester.getTopLeft(find.byIcon(Icons.lock_open)).dy,
        lessThan(tester.getTopLeft(find.text('Events')).dy),
      );
    },
  );

  testWidgets('the banner goes when the server stops skipping sign-in', (
    tester,
  ) async {
    final server = ValueNotifier(true);
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) =>
            SignInOffBanner(server: server, child: child!),
        home: const Scaffold(body: Text('Events')),
      ),
    );
    expect(find.text(SignInOffBanner.text), findsOneWidget);

    server.value = false;
    await tester.pump();

    expect(find.text(SignInOffBanner.text), findsNothing);
  });
}
