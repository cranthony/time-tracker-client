/// A Google Calendar event's description, drawn in the app's own text
/// styles. Google keeps what's written on the web as HTML -- bold,
/// italics, underlines, links, line breaks and lists -- and what's
/// written elsewhere as plain text; both are shown, links tappable. So is
/// any free text of the app's own -- a goal's description, say -- in the
/// format it's written in ([TextFormat]): Markdown too. A link into the
/// app ([EntityLink] -- `goal:ship-goals-pane`, `person:sam`) is drawn
/// with the icon of what it names and, where its text is only the id (or
/// there's none), its current name; tapped, it opens what it names
/// ([EntityLinks]).
library;

import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html;
import 'package:markdown/markdown.dart' as md;
import 'package:url_launcher/url_launcher.dart';

import '../models/entity_link.dart';
import '../models/text_format.dart';
import 'entity_links.dart';

/// [text] as HTML, as it's written in [format] (or looks, with none);
/// null for plain text.
String? _asHtml(String text, TextFormat? format) =>
    switch (TextFormat.of(text, format)) {
      TextFormat.plain => null,
      TextFormat.html => text,
      TextFormat.markdown => md.markdownToHtml(
        text.replaceAll('\r\n', '\n'),
        extensionSet: md.ExtensionSet.gitHubFlavored,
      ),
    };

/// Bare web addresses in plain text, to make links of -- and links into
/// the app ([EntityLink.pattern]), after them, so one in an address's
/// path is part of the address.
final _links = RegExp(
  r'https?://[^\s<>"]+[^\s<>".,;:!?)\]]|' + EntityLink.pattern.pattern,
  caseSensitive: false,
);

/// How far across a link's icon is: as the text is tall, near enough.
const _iconSize = 16.0;

/// Opens [url] in the app it belongs to: the browser, the dialer, mail.
Future<void> _open(String url) async {
  final uri = Uri.tryParse(url);
  if (uri == null || !{'http', 'https', 'mailto', 'tel'}.contains(uri.scheme)) {
    return;
  }
  await launchUrl(uri, mode: LaunchMode.externalApplication);
}

/// A paragraph of a description, or one of a list's items: its [marker]
/// (a bullet, or its number) hung out to the left of its text, [depth]
/// lists in.
class DescriptionBlock {
  const DescriptionBlock(this.span, {this.marker, this.depth = 0});

  final TextSpan span;
  final String? marker;
  final int depth;

  bool get isItem => marker != null;
}

/// [text], written in [format] (or as it looks, with none), as paragraphs
/// and list items, making a recognizer for each link with [recognizer]:
/// the caller disposes of them. A link into the app is named by [links]
/// (or, with none, as written, or by its id), its icon before it; one
/// written bare, `goal:move`, is a link too, unless not [bareLinks].
List<DescriptionBlock> descriptionBlocks(
  String text, {
  TextFormat? format,
  required Color linkColor,
  required TapGestureRecognizer Function(String url) recognizer,
  EntityLinks? links,
  bool bareLinks = true,
}) {
  final link = TextStyle(
    color: linkColor,
    decoration: TextDecoration.underline,
    decorationColor: linkColor,
  );
  // A link into the app: its icon, then its text -- [shown], unless
  // that's only its id (or nothing), then what it names now.
  List<InlineSpan> entity(EntityLink to, String shown, TextStyle? style) {
    final text =
        shown.isEmpty ||
            shown == to.id ||
            shown.toLowerCase() == to.href.toLowerCase()
        ? links?.name(to) ?? to.id
        : shown;
    final tap = recognizer(to.href);
    return [
      WidgetSpan(
        alignment: PlaceholderAlignment.middle,
        child: GestureDetector(
          onTap: tap.onTap,
          child: Padding(
            padding: const EdgeInsetsDirectional.only(end: 3),
            child:
                links?.icon(to, size: _iconSize, color: linkColor) ??
                entityIcon(to.kind, size: _iconSize, color: linkColor),
          ),
        ),
      ),
      TextSpan(text: text, style: style?.merge(link) ?? link, recognizer: tap),
    ];
  }

  // Plain text, its addresses links, and its links into the app too.
  List<InlineSpan> plain(String text, TextStyle? style) {
    final spans = <InlineSpan>[];
    var at = 0;
    for (final match in _links.allMatches(text)) {
      if (match.start > at) {
        spans.add(
          TextSpan(text: text.substring(at, match.start), style: style),
        );
      }
      final url = match.group(0)!;
      if (EntityLink.parse(url) case final to?) {
        if (bareLinks) {
          spans.addAll(entity(to, url, style));
        } else {
          spans.add(TextSpan(text: url, style: style));
        }
      } else {
        spans.add(
          TextSpan(
            text: url,
            style: style?.merge(link) ?? link,
            recognizer: recognizer(url),
          ),
        );
      }
      at = match.end;
    }
    if (at < text.length) {
      spans.add(TextSpan(text: text.substring(at), style: style));
    }
    return spans;
  }

  final source = _asHtml(text, format);
  if (source == null) {
    final trimmed = text.replaceAll('\r\n', '\n').trim();
    return [
      if (trimmed.isNotEmpty)
        DescriptionBlock(TextSpan(children: plain(trimmed, null))),
    ];
  }

  final blocks = <DescriptionBlock>[];
  // The block being built: its spans, each with its text (an icon's, the
  // object replacement character, as a placeholder is).
  var line = <(InlineSpan, String)>[];
  String? marker;
  var depth = 0;
  var listDepth = 0;
  // Inside a pre: its whitespace kept.
  var preDepth = 0;
  const code = TextStyle(fontFamily: 'monospace');
  bool atLineStart() => line.isEmpty || line.last.$2.endsWith('\n');

  void flush() {
    // No line breaks at its end.
    while (line.isNotEmpty && line.last.$2.trim().isEmpty) {
      line.removeLast();
    }
    // Nor a space, from a line break before a list in it.
    if (line.isNotEmpty &&
        line.last.$1 is TextSpan &&
        line.last.$2 != line.last.$2.trimRight()) {
      final (span as TextSpan, text) = line.removeLast();
      line.add((
        TextSpan(
          text: text.trimRight(),
          style: span.style,
          recognizer: span.recognizer,
        ),
        text.trimRight(),
      ));
    }
    if (line.isNotEmpty) {
      blocks.add(
        DescriptionBlock(
          TextSpan(children: [for (final (span, _) in line) span]),
          marker: marker,
          depth: depth,
        ),
      );
    }
    line = [];
    marker = null;
    depth = math.max(0, listDepth - 1);
  }

  void add(InlineSpan span) {
    final text = span is TextSpan ? span.text ?? '' : '￼';
    if (text.isEmpty) return;
    line.add((span, text));
  }

  void walk(dom.Node node, TextStyle? style, String? href) {
    if (node is dom.Text) {
      if (preDepth > 0) {
        add(TextSpan(text: node.text.trimRight(), style: style));
        return;
      }
      // As HTML lays it out: runs of whitespace are one space.
      var text = node.text.replaceAll(RegExp(r'\s+'), ' ');
      if (atLineStart()) text = text.trimLeft();
      if (text.isEmpty) return;
      if (href != null) {
        add(
          TextSpan(
            text: text,
            style: style?.merge(link) ?? link,
            recognizer: recognizer(href),
          ),
        );
      } else {
        plain(text, style).forEach(add);
      }
      return;
    }
    if (node is! dom.Element) {
      for (final child in node.nodes) {
        walk(child, style, href);
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
      'code' || 'kbd' || 'pre' => code,
      _ => null,
    };
    final merged = own == null ? style : (style?.merge(own) ?? own);
    final linkTo = tag == 'a' ? node.attributes['href'] ?? href : href;
    if (tag == 'a') {
      if (EntityLink.parse(linkTo ?? '') case final to?) {
        entity(to, node.text.trim(), merged).forEach(add);
        return;
      }
    }
    switch (tag) {
      case 'br':
        add(TextSpan(text: '\n', style: merged));
      case 'ul' || 'ol':
        flush();
        listDepth++;
        var n = int.tryParse(node.attributes['start'] ?? '') ?? 1;
        for (final li in node.children) {
          if (li.localName != 'li') continue;
          flush();
          marker = tag == 'ol' ? '${n++}.' : (listDepth.isOdd ? '•' : '◦');
          depth = listDepth - 1;
          for (final child in li.nodes) {
            walk(child, merged, linkTo);
          }
          flush();
        }
        listDepth--;
        flush();
      case 'p' ||
          'div' ||
          'h1' ||
          'h2' ||
          'h3' ||
          'h4' ||
          'h5' ||
          'h6' ||
          'blockquote' ||
          'pre':
        // A paragraph inside a list item stays in it.
        final inItem = marker != null;
        if (!inItem) flush();
        if (inItem && line.isNotEmpty) add(TextSpan(text: '\n', style: merged));
        if (tag == 'pre') preDepth++;
        final heading = tag != null && tag.startsWith('h') && tag.length == 2;
        for (final child in node.nodes) {
          walk(
            child,
            heading
                ? (merged?.merge(
                        const TextStyle(fontWeight: FontWeight.w700),
                      ) ??
                      const TextStyle(fontWeight: FontWeight.w700))
                : merged,
            linkTo,
          );
        }
        if (tag == 'pre') preDepth--;
        if (!inItem) flush();
      case 'script' || 'style' || 'head' || 'title':
        break;
      default:
        for (final child in node.nodes) {
          walk(child, merged, linkTo);
        }
    }
  }

  walk(html.parseFragment(source), null, null);
  flush();
  return blocks;
}

/// [description], written in [format] (or as it looks, with none), as
/// plain text, for an event of the user's own: its paragraphs a line
/// each, its lists' items with their bullets, and a link's address after
/// its text, unless that's the address already. A link into the app is
/// its text, or with none, as written -- its id, which nothing outside
/// the app can follow.
String descriptionText(String description, {TextFormat? format}) {
  final source = _asHtml(description, format);
  if (source == null) {
    return description.replaceAll('\r\n', '\n').trim();
  }
  final fragment = html.parseFragment(source);
  for (final a in fragment.querySelectorAll('a[href]')) {
    final href = a.attributes['href']!;
    final shown = a.text.trim();
    if (EntityLink.parse(href) case final to?) {
      a.replaceWith(dom.Text(shown.isEmpty ? to.href : shown));
      continue;
    }
    final address = href.startsWith('mailto:') ? href.substring(7) : href;
    a.replaceWith(
      dom.Text(
        shown.isEmpty || shown == address ? address : '$shown ($address)',
      ),
    );
  }
  final recognizers = <TapGestureRecognizer>[];
  final blocks = descriptionBlocks(
    fragment.outerHtml,
    format: TextFormat.html,
    linkColor: const Color(0x00000000),
    bareLinks: false,
    recognizer: (_) {
      final r = TapGestureRecognizer();
      recognizers.add(r);
      return r;
    },
  );
  for (final r in recognizers) {
    r.dispose();
  }
  return [
    for (final b in blocks)
      '${'  ' * b.depth}${b.marker == null ? '' : '${b.marker} '}'
          '${b.span.toPlainText(includePlaceholders: false)}',
  ].join('\n');
}

/// [description], written in [format] (or as it looks, with none), up to
/// about [maxLines] of it until "More" is tapped -- or, with none, in
/// full: its paragraphs, and its lists' items, their bullets hung to the
/// left. Not [expandable], it's only cut off, with no "More": tapping it
/// opens it elsewhere. [selectable], its text is selected by touching
/// and holding it, to copy. Its links into the app are named and opened
/// by [links]: by default, as the context has them ([EntityLinks.of]).
class EventDescription extends StatefulWidget {
  const EventDescription(
    this.description, {
    super.key,
    this.format,
    this.maxLines = 8,
    this.expandable = true,
    this.selectable = false,
    this.links,
  });

  final String description;
  final TextFormat? format;
  final int? maxLines;
  final bool expandable;
  final bool selectable;
  final EntityLinks? links;

  @override
  State<EventDescription> createState() => _EventDescriptionState();
}

/// Between paragraphs, and between a list's items.
const _paragraphGap = 6.0;
const _itemGap = 2.0;

/// How far in a list item's text is, from its bullet, and how far in a
/// list in one is.
const _markerWidth = 20.0;
const _indent = 16.0;

class _EventDescriptionState extends State<EventDescription> {
  final _recognizers = <TapGestureRecognizer>[];
  var _expanded = false;

  /// As last built with; its memory listened to, so a link's name is
  /// what's loaded since.
  EntityLinks? _links;

  @override
  void dispose() {
    _links?.memory.removeListener(_changed);
    _disposeRecognizers();
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  void _use(EntityLinks? links) {
    if (links?.memory == _links?.memory) {
      _links = links;
      return;
    }
    _links?.memory.removeListener(_changed);
    _links = links;
    links?.memory.addListener(_changed);
  }

  void _disposeRecognizers() {
    for (final r in _recognizers) {
      r.dispose();
    }
    _recognizers.clear();
  }

  TapGestureRecognizer _recognizer(String url) {
    final r = TapGestureRecognizer()..onTap = () => _follow(url);
    _recognizers.add(r);
    return r;
  }

  /// Opens [url]: into the app, if it's a link into it and there's a way
  /// to; otherwise in the app it belongs to.
  Future<void> _follow(String url) async {
    if (EntityLink.parse(url) case final to?) {
      final links = _links;
      if (links == null) return;
      return links.open(context, to);
    }
    await _open(url);
  }

  double _gapBefore(List<DescriptionBlock> blocks, int i) => i == 0
      ? 0
      : blocks[i].isItem && blocks[i - 1].isItem
      ? _itemGap
      : _paragraphGap;

  @override
  Widget build(BuildContext context) {
    _disposeRecognizers();
    final theme = Theme.of(context);
    final style = theme.textTheme.bodyMedium;
    final links = widget.links ?? EntityLinks.of(context);
    _use(links);
    final blocks = descriptionBlocks(
      widget.description,
      format: widget.format,
      linkColor: theme.colorScheme.primary,
      recognizer: _recognizer,
      links: links,
    );
    if (blocks.isEmpty) return const SizedBox.shrink();
    final direction = Directionality.of(context);
    final scaler = MediaQuery.textScalerOf(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        double width(DescriptionBlock b) => math.max(
          0,
          constraints.maxWidth -
              b.depth * _indent -
              (b.isItem ? _markerWidth : 0),
        );
        double measure(InlineSpan span, double maxWidth) {
          var icons = 0;
          span.visitChildren((s) {
            if (s is WidgetSpan) icons++;
            return true;
          });
          final painter = TextPainter(
            text: TextSpan(style: style, children: [span]),
            textDirection: direction,
            textScaler: scaler,
          );
          painter.setPlaceholderDimensions(
            List.filled(
              icons,
              const PlaceholderDimensions(
                size: Size(_iconSize + 3, _iconSize),
                alignment: PlaceholderAlignment.middle,
              ),
            ),
          );
          painter.layout(maxWidth: maxWidth);
          final height = painter.height;
          painter.dispose();
          return height;
        }

        var height = 0.0;
        for (final (i, b) in blocks.indexed) {
          height += _gapBefore(blocks, i) + measure(b.span, width(b));
        }
        final lineHeight = measure(const TextSpan(text: 'Hg'), 1000);
        final maxLines = widget.maxLines;
        final limit = maxLines == null
            ? double.infinity
            : maxLines * lineHeight;
        // Not cut off for just a line more: "More" would take as much room.
        final long = height > limit + lineHeight + 1;
        Widget column = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final (i, b) in blocks.indexed)
              Padding(
                padding: EdgeInsetsDirectional.only(
                  start: b.depth * _indent,
                  top: _gapBefore(blocks, i),
                ),
                child: b.isItem
                    ? Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(
                            width: _markerWidth,
                            child: Text(b.marker!, style: style),
                          ),
                          Expanded(child: Text.rich(b.span, style: style)),
                        ],
                      )
                    : Text.rich(b.span, style: style),
              ),
          ],
        );
        if (widget.selectable) column = SelectionArea(child: column);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (long && !_expanded)
              // Cut off, fading out at the foot.
              ShaderMask(
                blendMode: BlendMode.dstIn,
                shaderCallback: (bounds) => const LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  stops: [0.75, 1],
                  colors: [Colors.black, Colors.transparent],
                ).createShader(bounds),
                child: SizedBox(
                  height: limit,
                  child: ClipRect(
                    child: OverflowBox(
                      alignment: AlignmentDirectional.topStart,
                      minHeight: 0,
                      maxHeight: double.infinity,
                      child: column,
                    ),
                  ),
                ),
              )
            else
              column,
            if (long && widget.expandable)
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
