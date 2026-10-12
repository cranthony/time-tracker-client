/// A Google Calendar event's description, drawn in the app's own text
/// styles. Google keeps what's written on the web as HTML -- bold,
/// italics, underlines, links, line breaks and lists -- and what's
/// written elsewhere as plain text; both are shown, links tappable.
library;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html;
import 'package:url_launcher/url_launcher.dart';

/// Whether [text] looks like HTML, rather than plain text.
bool _isHtml(String text) =>
    RegExp(r'<(/?[a-zA-Z][a-zA-Z0-9]*)(\s[^>]*)?/?>').hasMatch(text);

/// Bare web addresses in plain text, to make links of.
final _url = RegExp(r'https?://[^\s<>"]+[^\s<>".,;:!?)\]]');

/// Opens [url] in the app it belongs to: the browser, the dialer, mail.
Future<void> _open(String url) async {
  final uri = Uri.tryParse(url);
  if (uri == null || !{'http', 'https', 'mailto', 'tel'}.contains(uri.scheme)) {
    return;
  }
  await launchUrl(uri, mode: LaunchMode.externalApplication);
}

/// Builds [text] as spans, making a recognizer for each link with
/// [recognizer]: the caller disposes of them.
TextSpan descriptionSpan(
  String text, {
  required Color linkColor,
  required TapGestureRecognizer Function(String url) recognizer,
}) {
  final link = TextStyle(
    color: linkColor,
    decoration: TextDecoration.underline,
    decorationColor: linkColor,
  );
  // Plain text: its lines as written, its addresses links.
  List<TextSpan> plain(String text) {
    final spans = <TextSpan>[];
    var at = 0;
    for (final match in _url.allMatches(text)) {
      if (match.start > at) {
        spans.add(TextSpan(text: text.substring(at, match.start)));
      }
      final url = match.group(0)!;
      spans.add(TextSpan(text: url, style: link, recognizer: recognizer(url)));
      at = match.end;
    }
    if (at < text.length) spans.add(TextSpan(text: text.substring(at)));
    return spans;
  }

  if (!_isHtml(text)) {
    return TextSpan(children: plain(text.replaceAll('\r\n', '\n').trim()));
  }

  final spans = <InlineSpan>[];
  // Whether the text so far ends a line, so a block starts on a new one
  // without leaving a blank one.
  var atLineStart = true;
  void add(InlineSpan span, String text) {
    if (text.isEmpty) return;
    spans.add(span);
    atLineStart = text.endsWith('\n');
  }

  void newLine() {
    if (!atLineStart) add(const TextSpan(text: '\n'), '\n');
  }

  void walk(dom.Node node, TextStyle? style, {String? href}) {
    if (node is dom.Text) {
      // As HTML lays it out: runs of whitespace are one space.
      var text = node.text.replaceAll(RegExp(r'\s+'), ' ');
      if (atLineStart) text = text.trimLeft();
      if (href != null) {
        add(
          TextSpan(text: text, style: style, recognizer: recognizer(href)),
          text,
        );
      } else {
        for (final span in plain(text)) {
          add(
            TextSpan(
              text: span.text,
              style: style?.merge(span.style) ?? span.style,
              recognizer: span.recognizer,
            ),
            span.text!,
          );
        }
      }
      return;
    }
    if (node is! dom.Element) {
      for (final child in node.nodes) {
        walk(child, style, href: href);
      }
      return;
    }
    final tag = node.localName;
    final own = switch (tag) {
      'b' || 'strong' => const TextStyle(fontWeight: FontWeight.w700),
      'i' || 'em' => const TextStyle(fontStyle: FontStyle.italic),
      'u' => const TextStyle(decoration: TextDecoration.underline),
      's' ||
      'strike' ||
      'del' => const TextStyle(decoration: TextDecoration.lineThrough),
      'a' when node.attributes['href'] != null => link,
      _ => null,
    };
    final merged = own == null ? style : (style?.merge(own) ?? own);
    final linkTo = tag == 'a' ? node.attributes['href'] ?? href : href;
    switch (tag) {
      case 'br':
        add(const TextSpan(text: '\n'), '\n');
      case 'ul' || 'ol':
        newLine();
        var n = 1;
        for (final li in node.children) {
          if (li.localName != 'li') continue;
          newLine();
          final bullet = tag == 'ol' ? '${n++}. ' : '•  ';
          add(TextSpan(text: bullet), bullet);
          atLineStart = true;
          for (final child in li.nodes) {
            walk(child, merged, href: linkTo);
          }
        }
        newLine();
      case 'p' || 'div' || 'h1' || 'h2' || 'h3' || 'h4' || 'blockquote':
        newLine();
        for (final child in node.nodes) {
          walk(child, merged, href: linkTo);
        }
        newLine();
      case 'script' || 'style':
        break;
      default:
        for (final child in node.nodes) {
          walk(child, merged, href: linkTo);
        }
    }
  }

  walk(html.parseFragment(text), null);
  // No blank line at the foot.
  while (spans.isNotEmpty &&
      spans.last is TextSpan &&
      (spans.last as TextSpan).text == '\n') {
    spans.removeLast();
  }
  return TextSpan(children: spans);
}

/// [description] as plain text, for an event of the user's own: a
/// link's address after its text, unless that's the address already.
String descriptionText(String description) {
  if (!_isHtml(description)) {
    return description.replaceAll('\r\n', '\n').trim();
  }
  final fragment = html.parseFragment(description);
  for (final a in fragment.querySelectorAll('a[href]')) {
    final href = a.attributes['href']!;
    final shown = a.text.trim();
    final address = href.startsWith('mailto:') ? href.substring(7) : href;
    a.replaceWith(
      dom.Text(
        shown.isEmpty || shown == address ? address : '$shown ($address)',
      ),
    );
  }
  final recognizers = <TapGestureRecognizer>[];
  final text = descriptionSpan(
    fragment.outerHtml,
    linkColor: const Color(0x00000000),
    recognizer: (_) {
      final r = TapGestureRecognizer();
      recognizers.add(r);
      return r;
    },
  ).toPlainText();
  for (final r in recognizers) {
    r.dispose();
  }
  return text;
}

/// [description], up to [maxLines] of it until "More" is tapped.
class EventDescription extends StatefulWidget {
  const EventDescription(this.description, {super.key, this.maxLines = 6});

  final String description;
  final int maxLines;

  @override
  State<EventDescription> createState() => _EventDescriptionState();
}

class _EventDescriptionState extends State<EventDescription> {
  final _recognizers = <TapGestureRecognizer>[];
  var _expanded = false;

  @override
  void dispose() {
    for (final r in _recognizers) {
      r.dispose();
    }
    super.dispose();
  }

  TapGestureRecognizer _recognizer(String url) {
    final r = TapGestureRecognizer()..onTap = () => _open(url);
    _recognizers.add(r);
    return r;
  }

  @override
  Widget build(BuildContext context) {
    for (final r in _recognizers) {
      r.dispose();
    }
    _recognizers.clear();
    final theme = Theme.of(context);
    final style = theme.textTheme.bodyMedium;
    final span = descriptionSpan(
      widget.description,
      linkColor: theme.colorScheme.primary,
      recognizer: _recognizer,
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final painter = TextPainter(
          text: TextSpan(style: style, children: [span]),
          textDirection: Directionality.of(context),
          textScaler: MediaQuery.textScalerOf(context),
          maxLines: widget.maxLines,
        )..layout(maxWidth: constraints.maxWidth);
        final long = painter.didExceedMaxLines;
        painter.dispose();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text.rich(
              span,
              style: style,
              maxLines: _expanded ? null : widget.maxLines,
              overflow: _expanded ? null : TextOverflow.ellipsis,
            ),
            if (long)
              TextButton(
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                onPressed: () => setState(() => _expanded = !_expanded),
                child: Text(_expanded ? 'Less' : 'More'),
              ),
          ],
        );
      },
    );
  }
}
