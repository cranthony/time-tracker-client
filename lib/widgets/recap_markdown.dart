/// Claude's Markdown, as the server asks it to write it -- bold, italics,
/// code, bullet and numbered lists -- drawn in the app's own text styles.
/// Headings, quotes and code blocks are drawn plainly too; images by their
/// alt text. Links show as their text: nothing in it is opened.
library;

import 'package:flutter/material.dart';
import 'package:markdown/markdown.dart' as md;

List<md.Node> _parse(String text) =>
    md.Document(encodeHtml: false).parse(text.replaceAll('\r\n', '\n'));

const _blockTags = {
  'p', 'h1', 'h2', 'h3', 'h4', 'h5', 'h6', 'ul', 'ol', 'li', //
  'blockquote', 'pre', 'hr', 'table',
};

/// [text]'s Markdown as one run of text, for a line or two: its blocks
/// each on a line of their own, list items with their bullet or number.
TextSpan recapSpan(String text, {Color? codeBackground}) {
  final spans = <InlineSpan>[];
  void line(List<InlineSpan> parts) {
    if (spans.isNotEmpty) spans.add(const TextSpan(text: '\n'));
    spans.addAll(parts);
  }

  void blocks(List<md.Node> nodes, String prefix) {
    final inline = <md.Node>[];
    void flush() {
      if (inline.isEmpty) return;
      line([
        if (prefix.isNotEmpty) TextSpan(text: prefix),
        ..._inline(inline, codeBackground),
      ]);
      prefix = '';
      inline.clear();
    }

    for (final node in nodes) {
      if (node is md.Element && _blockTags.contains(node.tag)) {
        flush();
        switch (node.tag) {
          case 'ul' || 'ol':
            var n = int.tryParse(node.attributes['start'] ?? '') ?? 1;
            for (final li in node.children ?? const <md.Node>[]) {
              if (li is! md.Element) continue;
              blocks(
                li.children ?? const [],
                node.tag == 'ol' ? '${n++}. ' : '• ',
              );
            }
          case 'hr':
            break;
          case 'pre':
            line([TextSpan(text: node.textContent.trimRight())]);
          default:
            blocks(node.children ?? const [], prefix);
            prefix = '';
        }
      } else {
        inline.add(node);
      }
    }
    flush();
  }

  blocks(_parse(text), '');
  return TextSpan(children: spans);
}

/// [nodes], inline: bold, italics, struck through, code, line breaks.
List<InlineSpan> _inline(List<md.Node> nodes, Color? codeBackground) => [
  for (final node in nodes)
    switch (node) {
      md.Text(:final text) => TextSpan(text: text),
      md.Element(tag: 'br') => const TextSpan(text: '\n'),
      md.Element(tag: 'img') => TextSpan(text: node.attributes['alt'] ?? ''),
      md.Element(tag: 'code') => TextSpan(
        text: node.textContent,
        style: TextStyle(
          fontFamily: 'monospace',
          backgroundColor: codeBackground,
        ),
      ),
      md.Element(:final tag) => TextSpan(
        style: switch (tag) {
          'strong' => const TextStyle(fontWeight: FontWeight.w700),
          'em' => const TextStyle(fontStyle: FontStyle.italic),
          'del' => const TextStyle(decoration: TextDecoration.lineThrough),
          'a' => const TextStyle(decoration: TextDecoration.underline),
          _ => null,
        },
        children: _inline(node.children ?? const [], codeBackground),
      ),
      _ => TextSpan(text: node.textContent),
    },
];

/// [text]'s Markdown, in full: paragraphs, and lists nested as written.
class RecapMarkdown extends StatelessWidget {
  const RecapMarkdown(this.text, {super.key, this.style});

  final String text;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = this.style ?? theme.textTheme.bodyMedium;
    final code = theme.colorScheme.surfaceContainerHighest;
    return DefaultTextStyle.merge(
      style: style,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: _blocks(_parse(text), theme, code),
      ),
    );
  }

  static List<Widget> _blocks(
    List<md.Node> nodes,
    ThemeData theme,
    Color code,
  ) {
    final out = <Widget>[];
    final inline = <md.Node>[];
    void add(Widget block) {
      if (out.isNotEmpty) out.add(const SizedBox(height: 6));
      out.add(block);
    }

    void flush() {
      if (inline.isEmpty) return;
      add(Text.rich(TextSpan(children: _inline([...inline], code))));
      inline.clear();
    }

    for (final node in nodes) {
      if (node is md.Element && _blockTags.contains(node.tag)) {
        flush();
        add(_block(node, theme, code));
      } else {
        inline.add(node);
      }
    }
    flush();
    return out;
  }

  static Widget _block(md.Element e, ThemeData theme, Color code) {
    final children = e.children ?? const <md.Node>[];
    switch (e.tag) {
      case 'ul' || 'ol':
        var n = int.tryParse(e.attributes['start'] ?? '') ?? 1;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final li in children)
              if (li is md.Element)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 22,
                        child: Text(e.tag == 'ol' ? '${n++}.' : '•'),
                      ),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: _blocks(
                            li.children ?? const [],
                            theme,
                            code,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
          ],
        );
      case 'hr':
        return const Divider(height: 8);
      case 'pre':
        return Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: code,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            e.textContent.trimRight(),
            style: const TextStyle(fontFamily: 'monospace'),
          ),
        );
      case 'blockquote':
        return Container(
          padding: const EdgeInsets.only(left: 10),
          decoration: BoxDecoration(
            border: Border(
              left: BorderSide(
                color: theme.colorScheme.outlineVariant,
                width: 3,
              ),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: _blocks(children, theme, code),
          ),
        );
      case final h when h.length == 2 && h.startsWith('h'):
        return Text.rich(
          TextSpan(children: _inline(children, code)),
          style: const TextStyle(fontWeight: FontWeight.w700),
        );
      default:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: _blocks(children, theme, code),
        );
    }
  }
}
