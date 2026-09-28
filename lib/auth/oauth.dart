import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

/// The OAuth 2.1 client side of MCP authorization, as the Time Tracker MCP
/// server expects it: the server is only a Resource Server, and WorkOS
/// AuthKit is the Authorization Server. So, like Claude.ai does, this
/// discovers AuthKit from the server's protected-resource metadata,
/// registers itself via Dynamic Client Registration, and then runs the
/// authorization-code flow with PKCE, asking for a token scoped to the
/// server (the `resource` parameter, which the server checks as `aud`).
///
/// See https://modelcontextprotocol.io/specification/2025-06-18/basic/authorization

class OAuthException implements Exception {
  OAuthException(this.message);
  final String message;
  @override
  String toString() => 'OAuthException: $message';
}

class AuthServerMetadata {
  AuthServerMetadata({
    required this.resource,
    required this.authorizationEndpoint,
    required this.tokenEndpoint,
    required this.registrationEndpoint,
    required this.scopes,
  });

  /// The server's canonical resource URL: the token's audience.
  final String resource;
  final Uri authorizationEndpoint;
  final Uri tokenEndpoint;
  final Uri? registrationEndpoint;

  /// Scopes to request, or empty to leave `scope` out entirely.
  final List<String> scopes;
}

/// A client id obtained from Dynamic Client Registration. It is only valid
/// for the redirect URI it was registered with.
class ClientRegistration {
  ClientRegistration({
    required this.clientId,
    required this.redirectUri,
    this.clientSecret,
  });

  final String clientId;
  final String? clientSecret;
  final String redirectUri;

  factory ClientRegistration.fromJson(Map<String, dynamic> json) =>
      ClientRegistration(
        clientId: json['client_id'] as String,
        clientSecret: json['client_secret'] as String?,
        redirectUri: json['redirect_uri'] as String,
      );

  Map<String, dynamic> toJson() => {
    'client_id': clientId,
    'client_secret': ?clientSecret,
    'redirect_uri': redirectUri,
  };
}

class TokenSet {
  TokenSet({required this.accessToken, this.refreshToken, this.expiresAt});

  final String accessToken;
  final String? refreshToken;
  final DateTime? expiresAt;

  /// True if the access token has expired, or will within [leeway].
  bool isExpired(
    DateTime now, {
    Duration leeway = const Duration(minutes: 1),
  }) => expiresAt != null && now.add(leeway).isAfter(expiresAt!);

  factory TokenSet.fromJson(Map<String, dynamic> json) => TokenSet(
    accessToken: json['access_token'] as String,
    refreshToken: json['refresh_token'] as String?,
    expiresAt: json['expires_at'] == null
        ? null
        : DateTime.parse(json['expires_at'] as String),
  );

  Map<String, dynamic> toJson() => {
    'access_token': accessToken,
    'refresh_token': ?refreshToken,
    'expires_at': ?expiresAt?.toUtc().toIso8601String(),
  };
}

/// An authorization request in flight: the URL to open in a browser, and
/// what's needed to check and redeem the redirect that comes back.
class PendingAuthorization {
  PendingAuthorization({
    required this.url,
    required this.state,
    required this.codeVerifier,
  });

  final Uri url;
  final String state;
  final String codeVerifier;
}

class OAuthClient {
  OAuthClient({
    required this.mcpEndpoint,
    required this.clientName,
    http.Client? httpClient,
    DateTime Function()? clock,
    Random? random,
  }) : _http = httpClient ?? http.Client(),
       _clock = clock ?? DateTime.now,
       _random = random ?? Random.secure();

  final Uri mcpEndpoint;
  final String clientName;
  final http.Client _http;
  final DateTime Function() _clock;
  final Random _random;

  AuthServerMetadata? _metadata;

  /// Finds the authorization server via the MCP server's protected-resource
  /// metadata (RFC 9728), then reads that server's own metadata (RFC 8414).
  Future<AuthServerMetadata> discover() async {
    if (_metadata != null) return _metadata!;

    final origin = mcpEndpoint.replace(path: '', query: null, fragment: null);
    final path = mcpEndpoint.path == '/' ? '' : mcpEndpoint.path;
    final resourceMetadata = await _getFirstJson([
      origin.replace(path: '/.well-known/oauth-protected-resource$path'),
      origin.replace(path: '/.well-known/oauth-protected-resource'),
    ]);
    final servers =
        (resourceMetadata['authorization_servers'] as List?)?.cast<String>() ??
        [];
    if (servers.isEmpty) {
      throw OAuthException(
        '$mcpEndpoint does not name an authorization server',
      );
    }

    final issuer = Uri.parse(servers.first);
    final issuerPath = issuer.path == '/' ? '' : issuer.path;
    final serverMetadata = await _getFirstJson([
      issuer.replace(
        path: '/.well-known/oauth-authorization-server$issuerPath',
      ),
      issuer.replace(path: '/.well-known/openid-configuration$issuerPath'),
      issuer.replace(path: '$issuerPath/.well-known/openid-configuration'),
    ]);

    final resourceScopes =
        (resourceMetadata['scopes_supported'] as List?)?.cast<String>() ?? [];
    final serverScopes =
        (serverMetadata['scopes_supported'] as List?)?.cast<String>() ?? [];
    final registration = serverMetadata['registration_endpoint'] as String?;
    return _metadata = AuthServerMetadata(
      resource:
          resourceMetadata['resource'] as String? ?? mcpEndpoint.toString(),
      authorizationEndpoint: Uri.parse(
        serverMetadata['authorization_endpoint'] as String,
      ),
      tokenEndpoint: Uri.parse(serverMetadata['token_endpoint'] as String),
      registrationEndpoint: registration == null
          ? null
          : Uri.parse(registration),
      // offline_access is what gets us a refresh token, so signing in
      // isn't needed every time the (short-lived) access token expires.
      scopes: [
        ...resourceScopes,
        if (serverScopes.contains('offline_access') &&
            !resourceScopes.contains('offline_access'))
          'offline_access',
      ],
    );
  }

  /// Registers this app as a public client (no secret; PKCE instead).
  Future<ClientRegistration> register(Uri redirectUri) async {
    final metadata = await discover();
    final endpoint = metadata.registrationEndpoint;
    if (endpoint == null) {
      throw OAuthException(
        'The authorization server has no registration endpoint. In WorkOS, '
        'enable Dynamic Client Registration under Connect → Configuration.',
      );
    }
    final response = await _http.post(
      endpoint,
      headers: {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      },
      body: jsonEncode({
        'client_name': clientName,
        'redirect_uris': [redirectUri.toString()],
        'grant_types': ['authorization_code', 'refresh_token'],
        'response_types': ['code'],
        'token_endpoint_auth_method': 'none',
      }),
    );
    final json = _decode(response, 'Client registration');
    return ClientRegistration(
      clientId: json['client_id'] as String,
      clientSecret: json['client_secret'] as String?,
      redirectUri: redirectUri.toString(),
    );
  }

  Future<PendingAuthorization> startAuthorization(
    ClientRegistration client,
  ) async {
    final metadata = await discover();
    final verifier = _randomString(64);
    final state = _randomString(32);
    final challenge = base64UrlEncode(
      sha256.convert(ascii.encode(verifier)).bytes,
    ).replaceAll('=', '');
    final url = metadata.authorizationEndpoint.replace(
      queryParameters: {
        ...metadata.authorizationEndpoint.queryParameters,
        'response_type': 'code',
        'client_id': client.clientId,
        'redirect_uri': client.redirectUri,
        'code_challenge': challenge,
        'code_challenge_method': 'S256',
        'state': state,
        'resource': metadata.resource,
        if (metadata.scopes.isNotEmpty) 'scope': metadata.scopes.join(' '),
      },
    );
    return PendingAuthorization(url: url, state: state, codeVerifier: verifier);
  }

  /// Checks the browser's redirect back to us and trades its code for tokens.
  Future<TokenSet> finishAuthorization(
    ClientRegistration client,
    PendingAuthorization pending,
    Uri redirect,
  ) async {
    final params = redirect.queryParameters;
    if (params['error'] != null) {
      throw OAuthException(
        'Sign-in failed: ${params['error_description'] ?? params['error']}',
      );
    }
    if (params['state'] != pending.state) {
      throw OAuthException('Sign-in failed: state mismatch');
    }
    final code = params['code'];
    if (code == null) {
      throw OAuthException('Sign-in failed: no code in redirect');
    }

    return _tokenRequest(client, {
      'grant_type': 'authorization_code',
      'code': code,
      'redirect_uri': client.redirectUri,
      'code_verifier': pending.codeVerifier,
    });
  }

  Future<TokenSet> refresh(
    ClientRegistration client,
    String refreshToken,
  ) async {
    final tokens = await _tokenRequest(client, {
      'grant_type': 'refresh_token',
      'refresh_token': refreshToken,
    });
    // Servers that don't rotate refresh tokens leave it out of the response.
    return tokens.refreshToken == null
        ? TokenSet(
            accessToken: tokens.accessToken,
            refreshToken: refreshToken,
            expiresAt: tokens.expiresAt,
          )
        : tokens;
  }

  Future<TokenSet> _tokenRequest(
    ClientRegistration client,
    Map<String, String> params,
  ) async {
    final metadata = await discover();
    final response = await _http.post(
      metadata.tokenEndpoint,
      headers: {'Accept': 'application/json'},
      body: {
        ...params,
        'client_id': client.clientId,
        'client_secret': ?client.clientSecret,
        'resource': metadata.resource,
      },
    );
    final json = _decode(response, 'Token request');
    final expiresIn = json['expires_in'] as num?;
    return TokenSet(
      accessToken: json['access_token'] as String,
      refreshToken: json['refresh_token'] as String?,
      expiresAt: expiresIn == null
          ? null
          : _clock().add(Duration(seconds: expiresIn.toInt())),
    );
  }

  Future<Map<String, dynamic>> _getFirstJson(List<Uri> candidates) async {
    for (final uri in candidates) {
      final response = await _http.get(
        uri,
        headers: {'Accept': 'application/json'},
      );
      if (response.statusCode == 200) {
        return (jsonDecode(utf8.decode(response.bodyBytes)) as Map)
            .cast<String, dynamic>();
      }
    }
    throw OAuthException('No OAuth metadata found at ${candidates.join(', ')}');
  }

  static Map<String, dynamic> _decode(http.Response response, String what) {
    Object? json;
    try {
      json = jsonDecode(utf8.decode(response.bodyBytes));
    } on FormatException {
      json = null;
    }
    if (response.statusCode < 200 ||
        response.statusCode >= 300 ||
        json is! Map) {
      final detail = json is Map
          ? (json['error_description'] ?? json['error'])
          : response.body;
      throw OAuthException(
        '$what failed (HTTP ${response.statusCode}): $detail',
      );
    }
    return json.cast<String, dynamic>();
  }

  static const _unreserved =
      'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~';

  String _randomString(int length) => List.generate(
    length,
    (_) => _unreserved[_random.nextInt(_unreserved.length)],
  ).join();
}
