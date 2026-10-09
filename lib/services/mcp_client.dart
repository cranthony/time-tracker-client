import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'client_health.dart';

import 'server_errors.dart';

class McpException implements Exception {
  McpException(this.message, {this.statusCode, this.serverMessage});
  final String message;

  /// The HTTP status the server answered with, when it wasn't a 200.
  final int? statusCode;

  /// What the server said, when a tool refused: its own words, for the
  /// user (see `describeServerError`).
  final String? serverMessage;

  @override
  String toString() => 'McpException: $message';
}

/// Thrown when the server needs the user to (re-)sign in.
class SignInRequiredException implements Exception {
  @override
  String toString() => 'Sign-in required';
}

/// Supplies bearer tokens for MCP requests.
abstract class McpAuth {
  /// A currently valid access token. Throws [SignInRequiredException] if
  /// there is none and one can't be obtained without the user.
  Future<String> accessToken();

  /// Called when the server rejected [accessToken] with a 401.
  Future<void> rejected(String accessToken);
}

/// A minimal client for an MCP server over the Streamable HTTP transport.
///
/// It supports just enough of the protocol to call tools: the `initialize`
/// handshake, session ids, JSON or SSE-framed responses, and bearer auth.
///
/// It also retries what's safe to, so callers don't: a session the server
/// forgot is started again, and a call that fails before it reaches the
/// server -- the connection refused, the handshake dropped -- is sent
/// again, whatever the tool. A call that fails after it was sent (the
/// connection reset, a timeout, a 502/503/504) may have done its work
/// already, so it's only sent again for a tool that only reads (see
/// [readsOnly]); for any other, the user decides, from the error sheet.
class McpClient {
  McpClient({
    required this.endpoint,
    this.auth,
    this.health,
    http.Client? httpClient,
    this.retryDelays = const [
      Duration(milliseconds: 500),
      Duration(seconds: 1),
      Duration(seconds: 2),
    ],
  }) : _http = httpClient ?? http.Client();

  static const _protocolVersion = '2025-06-18';

  final Uri endpoint;
  final McpAuth? auth;
  final http.Client _http;

  /// Where each tool call is recorded -- how long it took, retries and
  /// all, and whether it failed -- for the Diagnostics page; nowhere,
  /// without it.
  final ClientHealthRecorder? health;

  /// How long to wait before each retry of a call that failed in a way
  /// that may well pass (see the class docs): one try more than there are
  /// delays.
  final List<Duration> retryDelays;

  String? _sessionId;
  bool _initialized = false;
  int _nextId = 1;

  /// Whether the tool [name] only reads, so calling it again is always
  /// safe.
  static bool readsOnly(String name) =>
      name.startsWith('get_') ||
      name.startsWith('list_') ||
      const {'prepare_judgments'}.contains(name);

  /// Calls [name] with [arguments] and returns the tool's result, decoded
  /// from JSON where possible -- retried as the class docs say. Recorded
  /// in [health], if there is one.
  Future<Object?> callTool(
    String name, [
    Map<String, Object?> arguments = const {},
  ]) async {
    final health = this.health;
    if (health == null) return _callTool(name, arguments);
    final watch = Stopwatch()..start();
    try {
      final result = await _callTool(name, arguments);
      health.recordCall(name, watch.elapsedMilliseconds);
      return result;
    } catch (e) {
      health.recordCall(name, watch.elapsedMilliseconds, error: e);
      rethrow;
    }
  }

  Future<Object?> _callTool(String name, Map<String, Object?> arguments) async {
    final safe = readsOnly(name);
    for (var attempt = 0; ; attempt++) {
      // Whether the call's been sent: before it, any failure is safe to
      // retry. Per call: calls run side by side.
      final sent = [false];
      try {
        return await _callOnce(name, arguments, sent);
      } catch (e) {
        final again =
            attempt < retryDelays.length &&
            (!sent.first || neverSent(e) || (safe && isTransient(e)));
        if (!again || !(e is http.ClientException || isTransient(e))) {
          rethrow;
        }
        await Future<void>.delayed(retryDelays[attempt]);
      }
    }
  }

  Future<Object?> _callOnce(
    String name,
    Map<String, Object?> arguments,
    List<bool> sent,
  ) async {
    await _ensureInitialized();
    sent.first = true;
    final result = await _request('tools/call', {
      'name': name,
      'arguments': arguments,
    });
    if (result['isError'] == true) {
      final said = _textContent(result);
      throw McpException('Tool $name failed: $said', serverMessage: said);
    }
    // FastMCP wraps non-object return values as {"result": ...}.
    final structured = result['structuredContent'];
    if (structured is Map) {
      return structured.length == 1 && structured.containsKey('result')
          ? structured['result']
          : structured;
    }
    final text = _textContent(result);
    try {
      return jsonDecode(text);
    } on FormatException {
      return text;
    }
  }

  void close() => _http.close();

  Future<void> _ensureInitialized() async {
    if (_initialized) return;
    await _request('initialize', {
      'protocolVersion': _protocolVersion,
      'capabilities': {},
      'clientInfo': {'name': 'time-tracker-client', 'version': '1.0.0'},
    });
    await _post({'jsonrpc': '2.0', 'method': 'notifications/initialized'});
    _initialized = true;
  }

  Future<Map<String, dynamic>> _request(
    String method,
    Map<String, Object?> params,
  ) async {
    final id = _nextId++;
    final response = await _post({
      'jsonrpc': '2.0',
      'id': id,
      'method': method,
      'params': params,
    });

    // A session the server forgot (it expired, or the server restarted):
    // it ran nothing, so start over and send it again, once.
    if (_sessionLost(response) &&
        _sessionId != null &&
        method != 'initialize') {
      _sessionId = null;
      _initialized = false;
      await _ensureInitialized();
      return _request(method, params);
    }
    if (response.statusCode != 200) {
      throw McpException(
        '$method: HTTP ${response.statusCode} ${response.body}',
        statusCode: response.statusCode,
      );
    }

    final message = _findResponse(response, id);
    final error = message['error'];
    if (error != null) {
      throw McpException('$method: ${error is Map ? error['message'] : error}');
    }
    return (message['result'] as Map).cast<String, dynamic>();
  }

  static bool _sessionLost(http.Response response) =>
      response.statusCode == 404 ||
      (response.statusCode == 400 &&
          response.body.toLowerCase().contains('session'));

  Future<http.Response> _post(
    Map<String, Object?> body, {
    bool retryUnauthorized = true,
  }) async {
    final token = await auth?.accessToken();
    final response = await _http.post(
      endpoint,
      headers: {
        'Content-Type': 'application/json',
        'Accept': 'application/json, text/event-stream',
        'MCP-Protocol-Version': _protocolVersion,
        'Mcp-Session-Id': ?_sessionId,
        if (token != null) 'Authorization': 'Bearer $token',
      },
      body: jsonEncode(body),
    );
    if (response.statusCode == 401) {
      if (auth == null) throw SignInRequiredException();
      await auth!.rejected(token!);
      // Once with a refreshed token; after that, only signing in will help.
      if (!retryUnauthorized) throw SignInRequiredException();
      return _post(body, retryUnauthorized: false);
    }
    _sessionId = response.headers['mcp-session-id'] ?? _sessionId;
    return response;
  }

  /// Extracts the JSON-RPC response with [id] from a plain JSON body or an
  /// SSE stream (which may interleave notifications before the response).
  Map<String, dynamic> _findResponse(http.Response response, int id) {
    final contentType = response.headers['content-type'] ?? '';
    final body = utf8.decode(response.bodyBytes);
    final Iterable<String> payloads;
    if (contentType.contains('text/event-stream')) {
      payloads = _sseData(body);
    } else {
      payloads = [body];
    }
    for (final payload in payloads) {
      final decoded = jsonDecode(payload);
      if (decoded is Map && decoded['id'] == id) {
        return decoded.cast<String, dynamic>();
      }
    }
    throw McpException('No response for request $id');
  }

  static Iterable<String> _sseData(String body) sync* {
    final data = <String>[];
    for (final line in const LineSplitter().convert(body)) {
      if (line.isEmpty) {
        if (data.isNotEmpty) yield data.join('\n');
        data.clear();
      } else if (line.startsWith('data:')) {
        data.add(line.substring(5).trimLeft());
      }
    }
    if (data.isNotEmpty) yield data.join('\n');
  }

  static String _textContent(Map<String, dynamic> result) {
    final content = result['content'];
    if (content is! List) return '';
    return content
        .whereType<Map>()
        .where((c) => c['type'] == 'text')
        .map((c) => c['text'] as String)
        .join('\n');
  }
}
