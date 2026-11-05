/// A Markdown (or HTML) table, drawn in the app's own text styles: its
/// header row bold on a tint, its cells in a grid of thin lines. Each
/// column is as wide as its widest cell, up to [maxCellWidth] -- wider
/// cells wrap -- and a table too wide for the room it has scrolls across.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

/// How wide a cell's text can be before it wraps.
const maxCellWidth = 240.0;

/// Around a cell's text.
const _cellPadding = EdgeInsets.symmetric(horizontal: 8, vertical: 4);

/// The grid's lines.
const _lineWidth = 1.0;

/// A table's cells, row by row: the first row its header if [header].
class TableCells {
  const TableCells(this.rows, {this.header = true, this.aligns = const []});

  final List<List<InlineSpan>> rows;
  final bool header;

  /// Each column's alignment, as written; one not given is at the start.
  final List<TextAlign> aligns;

  int get columns => rows.fold(0, (n, r) => math.max(n, r.length));

  TextAlign align(int column) =>
      column < aligns.length ? aligns[column] : TextAlign.start;

  /// The cell at [row], [column] -- empty, for a row short of cells --
  /// bold in the header.
  InlineSpan cell(int row, int column) {
    final cells = rows[row];
    final span = column < cells.length ? cells[column] : const TextSpan();
    return header && row == 0
        ? TextSpan(
            style: const TextStyle(fontWeight: FontWeight.w700),
            children: [span],
          )
        : span;
  }

  /// As plain text: a row a line, its cells between bars.
  String toPlainText() => [
    for (final i in Iterable<int>.generate(rows.length))
      [
        for (final c in Iterable.generate(columns))
          cell(i, c).toPlainText(includePlaceholders: false).trim(),
      ].join(' | '),
  ].join('\n');

  /// A cell's alignment, from how the HTML or Markdown wrote it: an
  /// `align` attribute, or a `text-align` in its style.
  static TextAlign alignOf(Map<Object, String> attributes) {
    final style = attributes['style'] ?? '';
    final align =
        attributes['align'] ??
        RegExp(r'text-align:\s*(\w+)').firstMatch(style)?.group(1);
    return switch (align) {
      'center' => TextAlign.center,
      'right' => TextAlign.end,
      _ => TextAlign.start,
    };
  }
}

/// How [TableCells] lay out: each column's width and each row's height,
/// lines and padding included, and the whole table's.
class TableLayout {
  const TableLayout(this.widths, this.heights);

  final List<double> widths;
  final List<double> heights;

  // The grid's lines are drawn over the cells' edges, taking no room.
  double get width => widths.fold(0, (w, c) => w + c);
  double get height => heights.fold(0, (h, r) => h + r);
}

/// How [table] lays out in [style]: an icon in it (a [WidgetSpan]) taken
/// as [placeholder] in size.
TableLayout layoutTable(
  TableCells table, {
  TextStyle? style,
  required TextDirection direction,
  required TextScaler scaler,
  Size placeholder = const Size(19, 16),
}) {
  TextPainter painter(InlineSpan span, double maxWidth) {
    var icons = 0;
    span.visitChildren((s) {
      if (s is WidgetSpan) icons++;
      return true;
    });
    return TextPainter(
        text: TextSpan(style: style, children: [span]),
        textDirection: direction,
        textScaler: scaler,
      )
      ..setPlaceholderDimensions(
        List.filled(
          icons,
          PlaceholderDimensions(
            size: placeholder,
            alignment: PlaceholderAlignment.middle,
          ),
        ),
      )
      ..layout(maxWidth: maxWidth);
  }

  final columns = table.columns;
  final text = List.filled(columns, 0.0);
  for (final r in Iterable<int>.generate(table.rows.length)) {
    for (final c in Iterable<int>.generate(columns)) {
      final p = painter(table.cell(r, c), maxCellWidth);
      text[c] = math.max(text[c], p.maxIntrinsicWidth.ceilToDouble());
      p.dispose();
    }
  }
  final widths = [
    for (final w in text) math.min(w, maxCellWidth) + _cellPadding.horizontal,
  ];
  final heights = [
    for (final r in Iterable<int>.generate(table.rows.length))
      Iterable<int>.generate(columns).fold(0.0, (h, c) {
            final p = painter(
              table.cell(r, c),
              widths[c] - _cellPadding.horizontal,
            );
            final height = p.height;
            p.dispose();
            return math.max(h, height);
          }) +
          _cellPadding.vertical,
  ];
  return TableLayout(widths, heights);
}

/// [table], in [style] (or the context's), laid out as [layoutTable] has
/// it -- by [layout], if it's been laid out already.
class MarkdownTable extends StatelessWidget {
  const MarkdownTable(this.table, {super.key, this.style, this.layout});

  final TableCells table;
  final TextStyle? style;
  final TableLayout? layout;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = this.style ?? DefaultTextStyle.of(context).style;
    final layout =
        this.layout ??
        layoutTable(
          table,
          style: style,
          direction: Directionality.of(context),
          scaler: MediaQuery.textScalerOf(context),
        );
    final columns = table.columns;
    if (columns == 0) return const SizedBox.shrink();
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Table(
        columnWidths: {
          for (final (i, w) in layout.widths.indexed) i: FixedColumnWidth(w),
        },
        border: TableBorder.all(
          color: theme.colorScheme.outlineVariant,
          width: _lineWidth,
        ),
        children: [
          for (final r in Iterable<int>.generate(table.rows.length))
            TableRow(
              decoration: table.header && r == 0
                  ? BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHighest,
                    )
                  : null,
              children: [
                for (final c in Iterable<int>.generate(columns))
                  Padding(
                    padding: _cellPadding,
                    child: Text.rich(
                      TextSpan(children: [table.cell(r, c)]),
                      style: style,
                      textAlign: table.align(c),
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}
