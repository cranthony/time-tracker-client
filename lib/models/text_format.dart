/// How a piece of free text is written -- a goal's description, a
/// habit's note, an event's -- mirroring the Time Tracker MCP server's
/// `TextFormat`: plain text, Markdown or HTML. A text with none is read
/// as it always was: HTML if it has tags, else plain text ([of]).
enum TextFormat {
  plain('plain', 'Plain text'),
  markdown('markdown', 'Markdown'),
  html('html', 'HTML');

  const TextFormat(this.wire, this.label);

  /// As the server names it.
  final String wire;

  /// As the app shows it.
  final String label;

  static TextFormat? fromJson(Object? json) =>
      values.where((f) => f.wire == json).firstOrNull;

  /// [format], or with none, what [text] looks like: HTML if it has
  /// tags, else plain text.
  static TextFormat of(String? text, TextFormat? format) =>
      format ?? (text != null && looksLikeHtml(text) ? html : plain);
}

/// A text and how it's written, as an editor gives it back.
typedef FormattedText = ({String text, TextFormat format});

/// Whether [text] looks like HTML, rather than plain text.
bool looksLikeHtml(String text) =>
    RegExp(r'<(/?[a-zA-Z][a-zA-Z0-9]*)(\s[^>]*)?/?>').hasMatch(text);
