import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:time_tracker_client/models/text_format.dart';
import 'package:time_tracker_client/widgets/event_description.dart';
import 'package:time_tracker_client/widgets/markdown_table.dart';
import 'package:time_tracker_client/widgets/recap_markdown.dart';

const _table =
    'Before\n\n'
    '| Day | Hours | Note |\n'
    '|:----|------:|:----:|\n'
    '| Mon | 3 | **long** |\n'
    '| Tue | 1 | [doc](https://example.com) |\n\n'
    'After';

/// Each cell's text, row by row.
List<List<String>> _texts(TableCells t) => [
  for (final row in t.rows)
    [for (final c in row) c.toPlainText(includePlaceholders: false)],
];

void main() {
  final recognizers = <TapGestureRecognizer>[];
  tearDown(() {
    for (final r in recognizers) {
      r.dispose();
    }
    recognizers.clear();
  });
  List<DescriptionBlock> blocks(String text, {TextFormat? format}) =>
      descriptionBlocks(
        text,
        format: format,
        linkColor: Colors.blue,
        recognizer: (_) {
          final r = TapGestureRecognizer();
          recognizers.add(r);
          return r;
        },
      );

  test("a Markdown description's table is a block of its own: its cells "
      "row by row, its header's first, each column's alignment kept", () {
    final result = blocks(_table, format: TextFormat.markdown);
    expect(
      [for (final b in result) b.toPlainText()],
      ['Before', 'Day | Hours | Note\nMon | 3 | long\nTue | 1 | doc', 'After'],
    );
    final table = result[1].table!;
    expect(table.header, isTrue);
    expect(_texts(table), [
      ['Day', 'Hours', 'Note'],
      ['Mon', '3', 'long'],
      ['Tue', '1', 'doc'],
    ]);
    expect(table.aligns, [TextAlign.start, TextAlign.end, TextAlign.center]);
    // Its links are links still.
    expect(recognizers, hasLength(1));
  });

  test("an HTML table's header is the first row only if it's th cells; "
      'a cell with paragraphs keeps them as lines', () {
    final table = blocks(
      '<table><tr><td>a</td><td><p>b</p><p>c</p></td></tr></table>',
      format: TextFormat.html,
    ).single.table!;
    expect(table.header, isFalse);
    expect(_texts(table), [
      ['a', 'b\nc'],
    ]);
  });

  test("a task list's items show their boxes: icons, drawn, and "
      'characters, as plain text', () {
    const tasks = '- [x] done\n- [ ] not';
    final result = blocks(tasks, format: TextFormat.markdown);
    expect(
      [
        for (final b in result)
          [
            for (final s in b.span.children!)
              if (s is WidgetSpan)
                ((s.child as Padding).child! as Icon).icon
              else
                s.toPlainText(),
          ],
      ],
      [
        [Icons.check_box_outlined, 'done'],
        [Icons.check_box_outline_blank, 'not'],
      ],
    );
    expect(
      descriptionText(tasks, format: TextFormat.markdown),
      '• ☑ done\n• ☐ not',
    );
  });

  test('as plain text, a table is a row a line', () {
    expect(
      descriptionText(_table, format: TextFormat.markdown),
      'Before\nDay | Hours | Note\nMon | 3 | long\n'
      'Tue | 1 | doc (https://example.com)\nAfter',
    );
  });

  test("Claude's recap, as a line or two, has a table's rows a line each", () {
    expect(
      recapSpan(_table).toPlainText(),
      'Before\nDay | Hours | Note\nMon | 3 | long\nTue | 1 | doc\nAfter',
    );
  });

  for (final (name, widget) in [
    (
      'a description',
      const EventDescription(_table, format: TextFormat.markdown),
    ),
    ("Claude's recap", const RecapMarkdown(_table)),
  ]) {
    testWidgets('$name draws its table as a grid, its header bold', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: SizedBox(width: 400, child: widget)),
        ),
      );
      expect(find.byType(Table), findsOneWidget);
      expect(find.byType(MarkdownTable), findsOneWidget);
      final table = tester.widget<Table>(find.byType(Table));
      expect(table.children, hasLength(3));
      expect(table.children.first.decoration, isNotNull);
      expect(find.text('Before'), findsOneWidget);
      expect(find.text('After'), findsOneWidget);
      expect(find.text('Hours'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('a table too wide for its room scrolls across, its long '
      'cells wrapping', (tester) async {
    final wide = [
      '| ${List.generate(6, (i) => 'Column $i').join(' | ')} |',
      '|${List.filled(6, '---').join('|')}|',
      '| ${List.filled(6, 'word ' * 60).join(' | ')} |',
    ].join('\n');
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 300,
            child: EventDescription(
              wide,
              format: TextFormat.markdown,
              maxLines: null,
            ),
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    final size = tester.getSize(find.byType(Table));
    expect(size.width, greaterThan(300));
    expect(size.width, lessThanOrEqualTo(6 * (maxCellWidth + 16)));
    // As measured, so a long one is cut off where it should be.
    final measured = layoutTable(
      blocks(wide, format: TextFormat.markdown).single.table!,
      style: Theme.of(tester.element(find.byType(Table))).textTheme.bodyMedium,
      direction: TextDirection.ltr,
      scaler: TextScaler.noScaling,
    );
    expect(size.height, moreOrLessEquals(measured.height, epsilon: 1));
  });

  testWidgets('a long table is cut off with "More", as a long text is', (
    tester,
  ) async {
    final long = [
      '| Day | Hours |',
      '|---|---|',
      for (var i = 0; i < 30; i++) '| Day $i | $i |',
    ].join('\n');
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: EventDescription(long, format: TextFormat.markdown),
          ),
        ),
      ),
    );
    expect(find.text('More'), findsOneWidget);
    await tester.tap(find.text('More'));
    await tester.pump();
    expect(find.text('Less'), findsOneWidget);
  });
}
