/// The server's MCP endpoint, from MCP_URL as the app was built with it: a
/// full URL ("https://your-service.onrender.com/mcp"), or -- on the web
/// only -- one relative to the page the app is served from ("/mcp"), for
/// a server on the app's own origin. A relative one is resolved against
/// [page] (by default the page's address, [Uri.base]) as a link on the
/// page would be: "/mcp" from the origin's root, "mcp" from the app's own
/// path. Elsewhere there's no page to resolve one against, so it's
/// refused, saying so.
Uri serverEndpoint(String mcpUrl, {required bool web, Uri? page}) {
  final url = Uri.parse(mcpUrl.trim());
  if (url.hasScheme) return url;
  if (!web) {
    throw ArgumentError.value(
      mcpUrl,
      'MCP_URL',
      'is relative, which only the web app can use (it resolves it against '
          "the page it's served from); give the server's full URL, e.g. "
          'https://your-service.onrender.com/mcp',
    );
  }
  // As a link would be: the page's own query and fragment (the app's
  // route, say) don't carry over.
  return (page ?? Uri.base).resolveUri(url);
}
