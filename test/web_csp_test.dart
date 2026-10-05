import 'package:flutter_test/flutter_test.dart';

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
        'https://fonts.gstatic.com;',
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
}
