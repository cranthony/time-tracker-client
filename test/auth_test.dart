import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:time_tracker_client/auth/auth_session.dart';
import 'package:time_tracker_client/auth/oauth.dart';
import 'package:time_tracker_client/auth/redirect_receiver.dart';
import 'package:time_tracker_client/auth/token_store.dart';
import 'package:time_tracker_client/services/mcp_client.dart';

const _mcp = 'https://tt.example.com/mcp';
const _authkit = 'https://tenant.authkit.app';

/// Fakes the MCP server's metadata plus WorkOS AuthKit's endpoints.
class _FakeAuthKit {
  final registrations = <Map<String, dynamic>>[];
  final tokenRequests = <Map<String, String>>[];
  bool failRegistration = false;
  int _issued = 0;

  /// Refresh tokens rotate: each one works once, like AuthKit's.
  final _usedRefreshTokens = <String>{};

  final proxied = <String>[];

  late final client = MockClient((request) async {
    var url = request.url.toString();
    // The MCP server's forwarding routes (OAuthClient.viaResourceServer).
    if (url.startsWith('https://tt.example.com/oauth/')) {
      proxied.add(request.url.path);
      url = url.replaceFirst(
        'https://tt.example.com/oauth/',
        '$_authkit/oauth2/',
      );
    }
    if (url ==
        'https://tt.example.com/.well-known/oauth-protected-resource/mcp') {
      return _json({
        'resource': _mcp,
        'authorization_servers': [_authkit],
      });
    }
    if (url == '$_authkit/.well-known/oauth-authorization-server') {
      return _json({
        'issuer': _authkit,
        'authorization_endpoint': '$_authkit/oauth2/authorize',
        'token_endpoint': '$_authkit/oauth2/token',
        'registration_endpoint': '$_authkit/oauth2/register',
        'scopes_supported': ['openid', 'offline_access'],
      });
    }
    if (url == '$_authkit/oauth2/register') {
      if (failRegistration) return _json({'error': 'invalid_request'}, 400);
      registrations.add(jsonDecode(request.body) as Map<String, dynamic>);
      return _json({'client_id': 'client_123'}, 201);
    }
    if (url == '$_authkit/oauth2/token') {
      final form = Uri.splitQueryString(request.body);
      tokenRequests.add(form);
      final refreshToken = form['refresh_token'];
      if (refreshToken == 'revoked' ||
          (refreshToken != null && !_usedRefreshTokens.add(refreshToken))) {
        return _json({'error': 'invalid_grant'}, 400);
      }
      _issued++;
      return _json({
        'access_token': 'access_$_issued',
        'refresh_token': 'refresh_$_issued',
        'expires_in': 300,
      });
    }
    return http.Response('not found', 404);
  });

  static http.Response _json(Object body, [int status = 200]) => http.Response(
    jsonEncode(body),
    status,
    headers: {'content-type': 'application/json'},
  );
}

/// Plays the browser + user: approves and redirects straight back.
class _FakeReceiver extends RedirectReceiver {
  Uri? lastAuthorizationUrl;
  final calls = <String>[];

  @override
  void prepare() => calls.add('prepare');

  @override
  void cancel() => calls.add('cancel');

  @override
  Uri get redirectUri => Uri.parse('http://localhost:47291/callback');

  @override
  Future<Uri> authorize(Uri authorizationUrl) async {
    calls.add('authorize');
    lastAuthorizationUrl = authorizationUrl;
    final state = authorizationUrl.queryParameters['state'];
    return redirectUri.replace(
      queryParameters: {'code': 'the_code', 'state': state},
    );
  }
}

void main() {
  late _FakeAuthKit authKit;
  late _FakeReceiver receiver;
  late InMemoryTokenStore store;
  late DateTime now;

  AuthSession session({bool viaResourceServer = false}) => AuthSession(
    oauth: OAuthClient(
      mcpEndpoint: Uri.parse(_mcp),
      clientName: 'Time Tracker (test)',
      viaResourceServer: viaResourceServer,
      httpClient: authKit.client,
      clock: () => now,
    ),
    store: store,
    receiver: receiver,
    clock: () => now,
  );

  setUp(() {
    authKit = _FakeAuthKit();
    receiver = _FakeReceiver();
    store = InMemoryTokenStore();
    now = DateTime.utc(2026, 9, 28, 12);
  });

  test('requires sign-in before there are tokens', () async {
    await expectLater(
      session().accessToken(),
      throwsA(isA<SignInRequiredException>()),
    );
  });

  test('signs in with DCR + PKCE, scoped to the MCP server', () async {
    final auth = session();
    await auth.signIn();

    expect(authKit.registrations.single, {
      'client_name': 'Time Tracker (test)',
      'redirect_uris': ['http://localhost:47291/callback'],
      'grant_types': ['authorization_code', 'refresh_token'],
      'response_types': ['code'],
      'token_endpoint_auth_method': 'none',
    });

    final params = receiver.lastAuthorizationUrl!.queryParameters;
    expect(receiver.lastAuthorizationUrl!.path, '/oauth2/authorize');
    expect(params['client_id'], 'client_123');
    expect(params['code_challenge_method'], 'S256');
    expect(params['resource'], _mcp);
    expect(params['scope'], 'offline_access');

    final exchange = authKit.tokenRequests.single;
    expect(exchange['grant_type'], 'authorization_code');
    expect(exchange['code'], 'the_code');
    expect(exchange['resource'], _mcp);
    // The verifier must hash to the challenge sent earlier.
    final challenge = base64UrlEncode(
      sha256.convert(ascii.encode(exchange['code_verifier']!)).bytes,
    ).replaceAll('=', '');
    expect(params['code_challenge'], challenge);

    expect(await auth.accessToken(), 'access_1');
    // Persisted: a fresh session (e.g. after restarting the app) reuses it.
    expect(await session().accessToken(), 'access_1');
  });

  test('prepares the receiver before any network request', () async {
    final auth = session();
    final signingIn = auth.signIn();
    // Synchronously, before discovery or registration have had a chance.
    expect(receiver.calls, ['prepare']);
    expect(authKit.registrations, isEmpty);
    await signingIn;
    expect(receiver.calls, ['prepare', 'authorize']);
  });

  test('cancels the receiver if sign-in fails before authorizing', () async {
    authKit = _FakeAuthKit()..failRegistration = true;
    await expectLater(session().signIn(), throwsA(isA<OAuthException>()));
    expect(receiver.calls, ['prepare', 'cancel']);
  });

  test('can register and get tokens through the MCP server', () async {
    final auth = session(viaResourceServer: true);
    await auth.signIn();

    expect(authKit.proxied, ['/oauth/register', '/oauth/token']);
    // Authorization itself still happens at AuthKit, in the browser.
    expect(
      receiver.lastAuthorizationUrl.toString(),
      startsWith('$_authkit/oauth2/authorize'),
    );
    expect(await auth.accessToken(), 'access_1');
  });

  test('can keep the registration apart from the tokens', () async {
    final registrations = InMemoryTokenStore();
    AuthSession split() => AuthSession(
      oauth: OAuthClient(
        mcpEndpoint: Uri.parse(_mcp),
        clientName: 'Time Tracker (test)',
        httpClient: authKit.client,
        clock: () => now,
      ),
      store: store,
      receiver: receiver,
      registrationStore: registrations,
      clock: () => now,
    );

    await split().signIn();
    expect(store.values.keys, ['oauth_tokens:$_mcp']);
    expect(registrations.values.keys, ['oauth_client:$_mcp']);

    // Tokens gone (a new browser session): signing in again reuses the
    // registration rather than registering another client.
    store.values.clear();
    await split().signIn();
    expect(authKit.registrations, hasLength(1));
  });

  test('reuses the client registration on later sign-ins', () async {
    await session().signIn();
    await session().signIn();
    expect(authKit.registrations, hasLength(1));
  });

  test('refreshes an expired access token', () async {
    final auth = session();
    await auth.signIn();
    now = now.add(const Duration(minutes: 10));

    expect(await auth.accessToken(), 'access_2');
    expect(authKit.tokenRequests.last['grant_type'], 'refresh_token');
    expect(authKit.tokenRequests.last['refresh_token'], 'refresh_1');
  });

  test('refreshes after the server rejects a token', () async {
    final auth = session();
    await auth.signIn();
    await auth.rejected('access_1');
    expect(await auth.accessToken(), 'access_2');
  });

  test('adopts tokens another session refreshed first', () async {
    // E.g. the Android background task refreshed while the app was paused,
    // using up the refresh token the app still has in memory.
    final app = session();
    await app.signIn();
    now = now.add(const Duration(minutes: 10));
    final background = AuthSession(
      oauth: OAuthClient(
        mcpEndpoint: Uri.parse(_mcp),
        clientName: 'Time Tracker (test)',
        httpClient: authKit.client,
        clock: () => now,
      ),
      store: store,
      clock: () => now,
    );
    expect(await background.accessToken(), 'access_2');

    expect(await app.accessToken(), 'access_2');
    expect(await app.isSignedIn, isTrue);
  });

  test('a session without a receiver cannot sign in', () async {
    final background = AuthSession(
      oauth: OAuthClient(
        mcpEndpoint: Uri.parse(_mcp),
        clientName: 'x',
        httpClient: authKit.client,
      ),
      store: store,
    );
    await expectLater(background.signIn(), throwsStateError);
  });

  test('a failed refresh means signing in again', () async {
    await store.write(
      'oauth_client:$_mcp',
      jsonEncode({
        'client_id': 'client_123',
        'redirect_uri': 'http://localhost:47291/callback',
      }),
    );
    await store.write(
      'oauth_tokens:$_mcp',
      jsonEncode({
        'access_token': 'a',
        'refresh_token': 'revoked',
        'expires_at': '2000-01-01T00:00:00Z',
      }),
    );
    final auth = session();
    await expectLater(
      auth.accessToken(),
      throwsA(isA<SignInRequiredException>()),
    );
    expect(await auth.isSignedIn, isFalse);
  });

  test('rejects a redirect with the wrong state', () async {
    final oauth = OAuthClient(
      mcpEndpoint: Uri.parse(_mcp),
      clientName: 'x',
      httpClient: authKit.client,
    );
    final client = ClientRegistration(
      clientId: 'c',
      redirectUri: 'http://localhost:47291/callback',
    );
    final pending = await oauth.startAuthorization(client);
    await expectLater(
      oauth.finishAuthorization(
        client,
        pending,
        Uri.parse('http://localhost:47291/callback?code=x&state=evil'),
      ),
      throwsA(isA<OAuthException>()),
    );
  });

  test('loopback receiver catches the browser redirect', () async {
    final receiver = LoopbackRedirectReceiver(
      port: 47299,
      openBrowser: (url) async {
        // Stand-in for the browser following AuthKit's redirect.
        final client = HttpClient();
        final request = await client.getUrl(
          Uri.parse('http://127.0.0.1:47299/callback?code=abc&state=xyz'),
        );
        final response = await request.close();
        expect(response.statusCode, 200);
        client.close();
      },
    );
    final redirect = await receiver.authorize(
      Uri.parse('https://example.com/authorize'),
    );
    expect(redirect.queryParameters, {'code': 'abc', 'state': 'xyz'});
  });
}
