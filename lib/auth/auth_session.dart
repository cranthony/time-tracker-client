import 'dart:convert';

import '../services/mcp_client.dart';
import 'oauth.dart';
import 'redirect_receiver.dart';
import 'token_store.dart';

/// Keeps the app signed in to the MCP server: hands out a valid access
/// token, refreshing it when needed, and runs the browser sign-in on request.
class AuthSession implements McpAuth {
  AuthSession({
    required this._oauth,
    required this._store,
    required this._receiver,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final OAuthClient _oauth;
  final TokenStore _store;
  final RedirectReceiver _receiver;
  final DateTime Function() _clock;

  late final String _clientKey = 'oauth_client:${_oauth.mcpEndpoint}';
  late final String _tokensKey = 'oauth_tokens:${_oauth.mcpEndpoint}';

  TokenSet? _tokens;
  bool _loaded = false;
  Future<TokenSet>? _refreshing;

  Future<bool> get isSignedIn async {
    await _load();
    return _tokens != null;
  }

  @override
  Future<String> accessToken() async {
    await _load();
    final tokens = _tokens;
    if (tokens == null) throw SignInRequiredException();
    if (!tokens.isExpired(_clock())) return tokens.accessToken;
    return (await _refresh()).accessToken;
  }

  @override
  Future<void> rejected(String accessToken) async {
    final tokens = _tokens;
    if (tokens == null || tokens.accessToken != accessToken) return;
    // Treat the token as expired, so the next accessToken() refreshes it.
    _tokens = TokenSet(
      accessToken: tokens.accessToken,
      refreshToken: tokens.refreshToken,
      expiresAt: DateTime(0),
    );
  }

  /// Runs the browser sign-in flow, registering this app with the
  /// authorization server first if it hasn't been already.
  Future<void> signIn() async {
    final client = await _clientRegistration();
    final pending = await _oauth.startAuthorization(client);
    final redirect = await _receiver.authorize(pending.url);
    await _save(await _oauth.finishAuthorization(client, pending, redirect));
  }

  Future<void> signOut() async {
    _tokens = null;
    await _store.delete(_tokensKey);
  }

  Future<TokenSet> _refresh() => _refreshing ??= () async {
    try {
      final refreshToken = _tokens?.refreshToken;
      final client = await _storedClient();
      if (refreshToken == null || client == null) {
        await signOut();
        throw SignInRequiredException();
      }
      try {
        final tokens = await _oauth.refresh(client, refreshToken);
        await _save(tokens);
        return tokens;
      } on OAuthException {
        // Refresh token revoked or expired: only a new sign-in will do.
        await signOut();
        throw SignInRequiredException();
      }
    } finally {
      _refreshing = null;
    }
  }();

  Future<ClientRegistration> _clientRegistration() async {
    final stored = await _storedClient();
    if (stored != null &&
        stored.redirectUri == _receiver.redirectUri.toString()) {
      return stored;
    }
    final client = await _oauth.register(_receiver.redirectUri);
    await _store.write(_clientKey, jsonEncode(client.toJson()));
    return client;
  }

  Future<ClientRegistration?> _storedClient() async {
    final json = await _store.read(_clientKey);
    return json == null
        ? null
        : ClientRegistration.fromJson(jsonDecode(json) as Map<String, dynamic>);
  }

  Future<void> _load() async {
    if (_loaded) return;
    final json = await _store.read(_tokensKey);
    if (json != null) {
      _tokens = TokenSet.fromJson(jsonDecode(json) as Map<String, dynamic>);
    }
    _loaded = true;
  }

  Future<void> _save(TokenSet tokens) async {
    _tokens = tokens;
    _loaded = true;
    await _store.write(_tokensKey, jsonEncode(tokens.toJson()));
  }
}
