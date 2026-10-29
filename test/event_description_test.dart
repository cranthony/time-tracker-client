import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:time_tracker_client/models/text_format.dart';
import 'package:time_tracker_client/services/maps.dart';
import 'package:time_tracker_client/widgets/event_description.dart';
import 'package:time_tracker_client/widgets/picker_sheet.dart';

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

  test('untagged, a text is HTML if it has tags, else plain text', () {
    expect(TextFormat.of('<b>Hi</b>', null), TextFormat.html);
    expect(TextFormat.of('**Hi**', null), TextFormat.plain);
    expect(TextFormat.of(null, null), TextFormat.plain);
    expect(TextFormat.of('<b>Hi</b>', TextFormat.plain), TextFormat.plain);
    expect(TextFormat.fromJson('markdown'), TextFormat.markdown);
    expect(TextFormat.fromJson('rtf'), isNull);
  });

  test("Markdown's paragraphs, lists, links and code are laid out as "
      "HTML's are", () {
    final result = blocks(
      '**Agenda**\n\n1. One\n2. Two\n   - Two and a half\n\n'
      'See the [doc](https://example.com), `code`.\n\n```\nlet a = 1;\n  b\n```',
      format: TextFormat.markdown,
    );
    expect(
      [for (final b in result) (b.marker, b.depth, b.span.toPlainText())],
      [
        (null, 0, 'Agenda'),
        ('1.', 0, 'One'),
        ('2.', 0, 'Two'),
        ('◦', 1, 'Two and a half'),
        (null, 0, 'See the doc, code.'),
        // A code block keeps its lines and indents.
        (null, 0, 'let a = 1;\n  b'),
      ],
    );
    expect(recognizers, hasLength(1));
    final bold = result.first.span.children!.first as TextSpan;
    expect(bold.style?.fontWeight, FontWeight.w700);
  });

  test('a text given as plain shows its tags as typed', () {
    final [block] = blocks('<b>Hi</b> **there**', format: TextFormat.plain);
    expect(block.span.toPlainText(), '<b>Hi</b> **there**');
    expect(
      descriptionText('- **One**\n- Two', format: TextFormat.markdown),
      '• One\n• Two',
    );
  });

  test('plain text is one paragraph, as written, its addresses links', () {
    final [block] = blocks(
      'Bring the card.\r\nReschedule: https://example.com/a.',
    );
    expect(block.marker, isNull);
    expect(
      block.span.toPlainText(),
      'Bring the card.\nReschedule: https://example.com/a.',
    );
    expect(recognizers, hasLength(1));
  });

  test("HTML's paragraphs and lists are blocks, items with their bullets "
      'or numbers, nested ones further in', () {
    final result = blocks(
      '<b>Agenda</b><ol><li>One</li><li>Two<ul><li>Two and a half</li>'
      '</ul></li></ol><p>See the <a href="https://example.com">doc</a>.</p>',
    );
    expect(
      [for (final b in result) (b.marker, b.depth, b.span.toPlainText())],
      [
        (null, 0, 'Agenda'),
        ('1.', 0, 'One'),
        ('2.', 0, 'Two'),
        ('◦', 1, 'Two and a half'),
        (null, 0, 'See the doc.'),
      ],
    );
    expect(recognizers, hasLength(1));
  });

  test("a description as plain text, for an event's own: links' addresses "
      'after their text, and lists with their bullets', () {
    expect(
      descriptionText(
        'Mocks in the <a href="https://example.com/m">design doc</a>, or ask '
        '<a href="mailto:jo@example.com">jo@example.com</a>.'
        '<ul><li>One</li><li>Two</li></ul>',
      ),
      'Mocks in the design doc (https://example.com/m), or ask '
      'jo@example.com.\n• One\n• Two',
    );
    expect(descriptionText('  Just text\r\n  '), 'Just text');
  });

  testWidgets('a long description is cut off, with "More" to show it all', (
    tester,
  ) async {
    Future<void> show(String text) => tester.pumpWidget(
      MaterialApp(home: Scaffold(body: EventDescription(text))),
    );
    await show('Short.');
    expect(find.text('More'), findsNothing);

    await show([for (var i = 0; i < 20; i++) 'Line $i'].join('\n'));
    expect(find.text('More'), findsOneWidget);
    await tester.tap(find.text('More'));
    await tester.pump();
    expect(find.text('Less'), findsOneWidget);

    // As a preview, it's only cut off: tapped, it opens elsewhere.
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: EventDescription(
            [for (var i = 0; i < 20; i++) 'Line $i'].join('<br>'),
            maxLines: 6,
            expandable: false,
          ),
        ),
      ),
    );
    expect(find.text('More'), findsNothing);
    expect(find.textContaining('<br>', findRichText: true), findsNothing);
    // Only where it's read in full is it selectable.
    expect(find.byType(SelectionArea), findsNothing);
  });

  testWidgets('the description sheet opens to read it, laid out, and the '
      'pencil edits it; blank, it opens to edit', (tester) async {
    Future<FormattedText?>? result;
    Future<void> open(String? text) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => result = showTextSheet(
                  context,
                  title: 'Description',
                  text: text,
                  hint: 'Add description',
                ),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
    }

    await open('<b>Agenda</b><br>See <a href="https://example.com">it</a>');
    expect(find.byType(TextField), findsNothing);
    expect(find.byType(EventDescription), findsOneWidget);
    expect(find.textContaining('<b>', findRichText: true), findsNothing);
    expect(find.textContaining('See it', findRichText: true), findsOneWidget);
    // Touched and held, its text is selected, to copy.
    expect(find.byType(SelectionArea), findsOneWidget);
    // Read and closed, it's unchanged.
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(await result, isNull);

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Edit'));
    await tester.pumpAndSettle();
    expect(find.byType(EventDescription), findsNothing);
    await tester.enterText(find.byType(TextField), ' Just text ');
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(await result, (text: 'Just text', format: TextFormat.html));

    await open(null);
    expect(find.byType(TextField), findsOneWidget);
    expect(find.byTooltip('Edit'), findsNothing);
  });

  test('maps links: any maps app on Android, Google Maps elsewhere', () {
    expect(
      geoSearch(' Bright Smile Dental, 5th St ').toString(),
      'geo:0,0?q=Bright%20Smile%20Dental%2C%205th%20St',
    );
    expect(
      mapsSearch('Room 4B').toString(),
      'https://www.google.com/maps/search/?api=1&query=Room+4B',
    );
  });

  test('a map location that is a link opens as one, by an arrow', () {
    expect(
      placeLink(' https://maps.app.goo.gl/abc123 ').toString(),
      'https://maps.app.goo.gl/abc123',
    );
    expect(placeLink('http://zoom.us/j/42?pwd=x'), isNotNull);
    expect(placeLink('12 Fifth Ave, New York'), isNull);
    expect(placeLink('See https://example.com'), isNull);
    expect(placeLink('mailto:jo@example.com'), isNull);
    expect(placeLink('Room 4B'), isNull);
    expect(placeLink(''), isNull);
    expect(placeButton('https://example.com/x').icon, Icons.arrow_forward);
    expect(placeButton('https://example.com/x').tooltip, 'Open link');
    expect(placeButton('Room 4B').icon, Icons.map_outlined);
    expect(placeButton('Room 4B').tooltip, 'Open in Maps');
  });
}
