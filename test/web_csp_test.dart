import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../tool/web_csp.dart';

void main() {
  test('the policy allows the given origins and only the app\'s scripts', () {
    final policy = contentSecurityPolicy([
      'https://mcp.example',
      'https://auth.example',
    ]);
    expect(policy, contains("script-src 'self' 'wasm-unsafe-eval';"));
    expect(
      policy,
      contains(
        "connect-src 'self' https://mcp.example https://auth.example "
        'https://fonts.gstatic.com https://api.open-meteo.com '
        'https://ensemble-api.open-meteo.com;',
      ),
    );
    expect(policy, isNot(contains("'unsafe-eval'")));
  });

  test('the meta tag goes first in the head, before any script', () {
    const html =
        '<html>\n<head>\n  <base href="/">\n'
        '  <script src="a.js"></script>\n</head></html>';
    final result = withPolicy(html, "default-src 'self'");
    expect(
      result,
      startsWith(
        '<html>\n<head>\n  <meta http-equiv="Content-Security-Policy" '
        'content="default-src \'self\'">\n  <base href="/">',
      ),
    );
  });

  test('a page that already has a policy is refused', () {
    final once = withPolicy('<head></head>', "default-src 'self'");
    expect(() => withPolicy(once, "default-src 'self'"), throwsStateError);
  });

  group('the origins allowed', () {
    test("a relative MCP_URL's are the page's own: nothing more", () async {
      var asked = false;
      final client = MockClient((_) async {
        asked = true;
        return http.Response('', 500);
      });

      expect(await connectOrigins('/mcp', client: client), isEmpty);
      expect(asked, isFalse);
    });

    test("a server's, and its authorization servers'", () async {
      final client = MockClient((request) async {
        expect(
          request.url.toString(),
          'https://mcp.example/.well-known/oauth-protected-resource/mcp',
        );
        return http.Response(
          jsonEncode({
            'authorization_servers': ['https://auth.example/'],
          }),
          200,
        );
      });

      expect(await connectOrigins('https://mcp.example/mcp', client: client), [
        'https://mcp.example',
        'https://auth.example',
      ]);
    });

    test("a server without sign-in's alone", () async {
      final client = MockClient((_) async => http.Response('Not Found', 404));

      expect(await connectOrigins('https://mcp.example/mcp', client: client), [
        'https://mcp.example',
      ]);
    });
  });
}
