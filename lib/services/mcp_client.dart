import 'dart:convert';

import 'package:http/http.dart' as http;

class McpException implements Exception {
  McpException(this.message);
  final String message;
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
class McpClient {
  McpClient({required this.endpoint, this.auth, http.Client? httpClient})
    : _http = httpClient ?? http.Client();

  static const _protocolVersion = '2025-06-18';

  final Uri endpoint;
  final McpAuth? auth;
  final http.Client _http;

  String? _sessionId;
  bool _initialized = false;
  int _nextId = 1;

  /// Calls [name] with [arguments] and returns the tool's result, decoded
  /// from JSON where possible.
  Future<Object?> callTool(
    String name, [
    Map<String, Object?> arguments = const {},
  ]) async {
    await _ensureInitialized();
    final result = await _request('tools/call', {
      'name': name,
      'arguments': arguments,
    });
    if (result['isError'] == true) {
      throw McpException('Tool $name failed: ${_textContent(result)}');
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

    // A session that expired server-side: start over once.
    if (response.statusCode == 404 &&
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
      );
    }

    final message = _findResponse(response, id);
    final error = message['error'];
    if (error != null) {
      throw McpException('$method: ${error is Map ? error['message'] : error}');
    }
    return (message['result'] as Map).cast<String, dynamic>();
  }

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
