// Adds a Content-Security-Policy to a web build's index.html, so the page
// runs only the app's own code and talks only to the MCP server and its
// authorization server. See "Content-Security-Policy" in README.md.
//
//     dart run tool/web_csp.dart build/web https://example.onrender.com/mcp
//
// The authorization server (AuthKit) is read from the MCP server's
// protected-resource metadata, as the app itself finds it.
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

/// Google's fonts server: the engine downloads Roboto, and fonts for
/// characters the bundled fonts lack (emoji, other scripts), from here.
/// Fonts are data, not code.
const fontsOrigin = 'https://fonts.gstatic.com';

/// The policy for a page that talks to [connectOrigins] besides its own.
String contentSecurityPolicy(Iterable<String> connectOrigins) => [
  "default-src 'self'",
  // Only the app's own scripts. CanvasKit is WebAssembly, which needs
  // 'wasm-unsafe-eval' to compile; unlike 'unsafe-eval' that doesn't let
  // JavaScript run text as code.
  "script-src 'self' 'wasm-unsafe-eval'",
  // The engine adds <style> elements and style attributes.
  "style-src 'self' 'unsafe-inline'",
  "img-src 'self' data: blob:",
  "connect-src 'self' ${{...connectOrigins, fontsOrigin}.join(' ')}",
  "worker-src 'self' blob:",
  "object-src 'none'",
  "base-uri 'self'",
  "form-action 'none'",
].join('; ');

/// [html] with a meta tag for [policy] as the first thing in its head,
/// before any script.
String withPolicy(String html, String policy) {
  if (html.contains('http-equiv="Content-Security-Policy"')) {
    throw StateError('The page already has a Content-Security-Policy');
  }
  final head = RegExp(r'<head[^>]*>').firstMatch(html);
  if (head == null) throw StateError('The page has no <head>');
  final escaped = const HtmlEscape(HtmlEscapeMode.attribute).convert(policy);
  return html.replaceRange(
    head.end,
    head.end,
    '\n  <meta http-equiv="Content-Security-Policy" content="$escaped">',
  );
}

/// The MCP server's authorization servers, from its protected-resource
/// metadata. Retries for a while: a sleeping Render service takes up to a
/// minute to start.
Future<List<Uri>> authorizationServers(Uri mcpEndpoint) async {
  final path = mcpEndpoint.path == '/' ? '' : mcpEndpoint.path;
  final url = mcpEndpoint.replace(
    path: '/.well-known/oauth-protected-resource$path',
  );
  for (var attempt = 1; ; attempt++) {
    try {
      final response = await http
          .get(url, headers: {'Accept': 'application/json'})
          .timeout(const Duration(seconds: 90));
      if (response.statusCode != 200) {
        throw HttpException('HTTP ${response.statusCode}', uri: url);
      }
      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final servers = (json['authorization_servers'] as List).cast<String>();
      if (servers.isEmpty) throw FormatException('No authorization servers');
      return servers.map(Uri.parse).toList();
    } catch (e) {
      if (attempt == 5) rethrow;
      stderr.writeln('Reading $url failed ($e); retrying.');
      await Future<void>.delayed(Duration(seconds: 10 * attempt));
    }
  }
}

Future<void> main(List<String> args) async {
  if (args.length != 2) {
    stderr.writeln('Usage: dart run tool/web_csp.dart <build/web> <MCP_URL>');
    exit(64);
  }
  final mcpEndpoint = Uri.parse(args[1]);
  final servers = await authorizationServers(mcpEndpoint);
  final policy = contentSecurityPolicy([
    mcpEndpoint.origin,
    for (final server in servers) server.origin,
  ]);

  final index = File('${args[0]}/index.html');
  index.writeAsStringSync(withPolicy(index.readAsStringSync(), policy));
  stdout.writeln('Content-Security-Policy: $policy');
}
