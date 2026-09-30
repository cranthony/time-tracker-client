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
    this._receiver,
    TokenStore? registrationStore,
    DateTime Function()? clock,
  }) : _registrationStore = registrationStore ?? _store,
       _clock = clock ?? DateTime.now;

  final OAuthClient _oauth;

  /// Holds the tokens.
  final TokenStore _store;

  /// Holds the client registration, which isn't secret (a public client:
  /// no client secret, PKCE instead). Separate so it can outlive tokens
  /// kept only for a browser session, rather than registering a new
  /// client with the authorization server every session.
  final TokenStore _registrationStore;

  /// Null for a session that can't sign in interactively (the Android
  /// background task); it can still use and refresh existing tokens.
  final RedirectReceiver? _receiver;
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
    final receiver = _receiver;
    if (receiver == null) throw StateError('This session cannot sign in');
    // Before the first await: see RedirectReceiver.prepare.
    receiver.prepare();
    final ClientRegistration client;
    final PendingAuthorization pending;
    try {
      client = await _clientRegistration(receiver);
      pending = await _oauth.startAuthorization(client);
    } catch (_) {
      receiver.cancel();
      rethrow;
    }
    final redirect = await receiver.authorize(pending.url);
    await _save(await _oauth.finishAuthorization(client, pending, redirect));
  }

  /// Forgets the cached tokens, so the next use reads them from the store
  /// again: the Android background task may have refreshed them.
  void reload() {
    if (_refreshing != null) return;
    _loaded = false;
    _tokens = null;
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
        // Another copy of this session (the Android background task) may
        // have refreshed first, using up the refresh token we have. If so,
        // take the tokens it stored.
        final stored = await _read();
        if (stored != null && stored.refreshToken != refreshToken) {
          _tokens = stored;
          if (!stored.isExpired(_clock())) return stored;
          final storedRefreshToken = stored.refreshToken;
          if (storedRefreshToken != null) {
            try {
              final tokens = await _oauth.refresh(client, storedRefreshToken);
              await _save(tokens);
              return tokens;
            } on OAuthException {
              // Fall through.
            }
          }
        }
        // Refresh token revoked or expired: only a new sign-in will do.
        await signOut();
        throw SignInRequiredException();
      }
    } finally {
      _refreshing = null;
    }
  }();

  Future<ClientRegistration> _clientRegistration(
    RedirectReceiver receiver,
  ) async {
    final stored = await _storedClient();
    if (stored != null &&
        stored.redirectUri == receiver.redirectUri.toString()) {
      return stored;
    }
    final client = await _oauth.register(receiver.redirectUri);
    await _registrationStore.write(_clientKey, jsonEncode(client.toJson()));
    return client;
  }

  Future<ClientRegistration?> _storedClient() async {
    final json = await _registrationStore.read(_clientKey);
    return json == null
        ? null
        : ClientRegistration.fromJson(jsonDecode(json) as Map<String, dynamic>);
  }

  Future<void> _load() async {
    if (_loaded) return;
    _tokens = await _read();
    _loaded = true;
  }

  Future<TokenSet?> _read() async {
    final json = await _store.read(_tokensKey);
    return json == null
        ? null
        : TokenSet.fromJson(jsonDecode(json) as Map<String, dynamic>);
  }

  Future<void> _save(TokenSet tokens) async {
    _tokens = tokens;
    _loaded = true;
    await _store.write(_tokensKey, jsonEncode(tokens.toJson()));
  }
}
