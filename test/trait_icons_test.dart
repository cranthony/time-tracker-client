import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:time_tracker_client/models/event.dart';
import 'package:time_tracker_client/models/person.dart';
import 'package:time_tracker_client/models/trait.dart';
import 'package:time_tracker_client/models/trait_icon.dart';
import 'package:time_tracker_client/screens/trait_screen.dart';
import 'package:time_tracker_client/services/mcp_client.dart';
import 'package:time_tracker_client/services/traits_repository.dart';
import 'package:time_tracker_client/widgets/day_timeline.dart';
import 'package:time_tracker_client/widgets/event_summary_dialog.dart';
import 'package:time_tracker_client/widgets/trait_icon.dart';

const _star =
    '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" '
    'fill="none" stroke="currentColor"><path d="M12 3l3 6 6 1-4 4 1 6-6-3-6 '
    '3 1-6-4-4 6-1z"/></svg>';

const _part = {
  'kind': 'judgment',
  'rubric': 'Was it calm?',
  'ratings': {'0': 'No', '1': 'Mostly', '2': 'Yes'},
  'facts': ['general_notes'],
};

const _calm = Trait(id: 'calm', name: 'Calm', parts: [_part], icon: _star);
const _curious = Trait(
  id: 'curious',
  name: 'Curious',
  parts: [_part],
  icon: _star,
);
const _plain = Trait(id: 'plain', name: 'Plain', parts: [_part]);

Map<String, Object?> _judged(Map<String, Map<String, int>> ratings) => {
  for (final MapEntry(key: person, value: traits) in ratings.entries)
    person: {
      for (final MapEntry(key: trait, value: rating) in traits.entries)
        trait: {
          'judgment': {'rating': rating, 'scale': 2},
        },
    },
};

void main() {
  group('traitIconProblem', () {
    test('takes one-colour SVG with a viewBox', () {
      expect(traitIconProblem(_star), isNull);
      expect(
        traitIconProblem(
          '<svg viewBox="0 0 8 8"><rect width="8" height="8" '
          'style="fill: currentColor; stroke:none"/></svg>',
        ),
        isNull,
      );
    });

    test('says which rule an icon breaks', () {
      expect(traitIconProblem('<svg viewBox="0 0 8 8"'), contains("isn't SVG"));
      expect(
        traitIconProblem('<g viewBox="0 0 8 8"/>'),
        contains('<svg> element'),
      );
      expect(traitIconProblem('<svg/>'), contains('viewBox'));
      expect(
        traitIconProblem('<svg viewBox="0 0 8 8"><path fill="#f00"/></svg>'),
        contains('"#f00"'),
      );
      expect(
        traitIconProblem(
          '<svg viewBox="0 0 8 8"><path style="stroke:red"/></svg>',
        ),
        contains('stroke is "red"'),
      );
      expect(
        traitIconProblem(
          '<svg viewBox="0 0 8 8"><!--${'x' * traitIconMaxLength}--></svg>',
        ),
        contains('at most $traitIconMaxLength'),
      );
    });
  });

  test("an icon can't run or load anything", () {
    String svg(String inside, [String attributes = '']) =>
        '<svg viewBox="0 0 8 8"$attributes>$inside</svg>';
    expect(traitIconProblem(svg('<script/>')), contains('<script>'));
    expect(traitIconProblem(svg('<style/>')), contains('<style>'));
    expect(
      traitIconProblem(svg('', ' onload="go()"')),
      contains('event handler onload'),
    );
    expect(
      traitIconProblem(
        svg(
          '<use xmlns:xlink="http://www.w3.org/1999/xlink" '
          'xlink:href="https://example.com/a.svg#x"/>',
        ),
      ),
      contains('link within itself'),
    );
    expect(traitIconProblem(svg('<use href="#x"/>')), isNull);
    expect(
      traitIconProblem(svg('<path clip-path="url(https://example.com/c)"/>')),
      contains('url(#...)'),
    );
    expect(
      traitIconProblem(svg('<path fill="currentColor !important"/>')),
      isNull,
    );
    // Stripped of all of them on import.
    final imported = asTraitIcon(
      svg(
        '<style>.a{fill:red}</style><script>go()</script>'
            '<path class="a" onclick="go()" fill="url(#g)" '
            'mask="url(https://example.com/m)"/><use href="https://example.com/u"/>',
        ' onload="go()"',
      ),
    );
    expect(traitIconProblem(imported), isNull);
    expect(imported, contains('fill="currentColor"'));
    expect(imported, isNot(contains('go()')));
    expect(imported, isNot(contains('example.com')));
  });

  test('asTraitIcon draws an imported icon in currentColor', () {
    final icon = asTraitIcon(
      '<?xml version="1.0"?>\n<!-- Made by hand -->\n'
      '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 8 8">'
      '<!-- a box --><rect fill="#000" stroke="none" width="8" height="8" '
      'style="stroke:#123456;opacity:0.5"/></svg>',
    );
    expect(traitIconProblem(icon), isNull);
    expect(icon, startsWith('<svg'));
    expect(icon, isNot(contains('<!--')));
    expect(icon, contains('fill="currentColor"'));
    expect(icon, contains('stroke="none"'));
    expect(icon, contains('stroke:currentColor;opacity:0.5'));
  });

  test("a trait's icon is read and written, and none is left out", () {
    final trait = Trait.fromJson({..._calm.toJson()});
    expect(trait.icon, _star);
    expect(Trait.fromJson({'name': 'X', 'icon': null}).icon, isNull);
    expect(_plain.toJson().containsKey('icon'), isFalse);
  });

  test("an event marks the traits the user's judgments rated top", () {
    final traits = [_calm, _curious, _plain];
    expect(
      markedTraits(
        traits,
        judgments: _judged({
          selfPersonId: {'calm': 2, 'curious': 1, 'plain': 2},
          // Someone else's top rating doesn't mark it.
          'sam': {'curious': 2},
        }),
      ),
      [_calm, _plain],
    );
    // And a story linked to it marks its trait.
    expect(markedTraits(traits, storyTraitIds: ['curious']), [_curious]);
    expect(markedTraits(traits), isEmpty);
  });

  group('DayTimeline', () {
    Widget timeline(Event event, {double width = 400}) => MaterialApp(
      theme: ThemeData(brightness: Brightness.dark),
      home: Scaffold(
        body: SingleChildScrollView(
          child: SizedBox(
            width: width,
            child: DayTimeline(
              events: [event],
              day: DateTime(2026, 9, 30),
              markedTraits: (e) => markedTraits(const [
                _calm,
                _curious,
                _plain,
              ], judgments: e.properties['judgments']),
            ),
          ),
        ),
      ),
    );

    final walk = Event(
      start: DateTime(2026, 9, 30, 9),
      end: DateTime(2026, 9, 30, 10),
      summary: 'Walk',
      properties: {
        'judgments': _judged({
          selfPersonId: {'calm': 2, 'curious': 2, 'plain': 2},
        }),
      },
    );

    testWidgets("shows the icons of an event's traits after its summary, "
        'named, in a colour that stands out from it', (tester) async {
      await tester.pumpWidget(timeline(walk));
      final icons = find.byType(TraitIcon);
      // Not the trait without an icon.
      expect(icons, findsNWidgets(2));
      expect(find.byTooltip('Calm'), findsOneWidget);
      expect(find.byTooltip('Curious'), findsOneWidget);
      expect(
        tester.getTopLeft(icons.first).dx,
        greaterThan(tester.getTopRight(find.text('Walk')).dx),
      );
      expect(tester.widget<TraitIcon>(icons.first).color, Colors.white);
      expect(
        find.bySemanticsLabel(RegExp('Walk, .*Calm, Curious')),
        findsOneWidget,
      );
    });

    testWidgets("drops them where there's no room beside its summary", (
      tester,
    ) async {
      await tester.pumpWidget(timeline(walk, width: 90));
      expect(find.byType(TraitIcon), findsNothing);
      expect(find.text('Walk'), findsOneWidget);
    });
  });

  testWidgets("an event's dialog shows the traits it marks", (tester) async {
    final event = Event(
      id: 'e1',
      summary: 'Walk',
      start: DateTime(2026, 9, 30, 9),
      end: DateTime(2026, 9, 30, 10),
      properties: {
        'judgments': _judged({
          selfPersonId: {'calm': 2, 'curious': 1},
        }),
      },
    );
    await tester.pumpWidget(
      TraitsScope(
        repository: InMemoryTraitsRepository(traits: const [_calm, _curious]),
        child: MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () => showEventSummaryDialog(context, event),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.byType(TraitIcon), findsOneWidget);
    expect(find.text('Calm'), findsOneWidget);
    expect(find.text('Curious'), findsNothing);
  });

  group('TraitScreen', () {
    Future<List<String?>> open(
      WidgetTester tester, {
      Trait trait = _plain,
      String? file,
    }) async {
      final saved = <String?>[];
      final repository = InMemoryTraitsRepository(traits: [trait]);
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(brightness: Brightness.dark),
          home: TraitScreen(
            trait: trait,
            pickSvg: () async => file,
            onIcon: (trait, icon) async {
              saved.add(icon);
              return repository.updateTrait(trait.id!, {'icon': icon});
            },
          ),
        ),
      );
      return saved;
    }

    testWidgets('imports an .svg file as its icon, in one colour', (
      tester,
    ) async {
      final saved = await open(
        tester,
        file:
            '<svg viewBox="0 0 8 8"><rect fill="#333" width="8" height="8"/>'
            '</svg>',
      );
      expect(find.byType(TraitIcon), findsNothing);
      await tester.tap(find.byTooltip('Icon'));
      await tester.pumpAndSettle();
      expect(find.text('Remove icon'), findsNothing);
      await tester.tap(find.text('Import .svg icon'));
      await tester.pumpAndSettle();
      expect(saved, [
        '<svg viewBox="0 0 8 8"><rect fill="currentColor" width="8" '
            'height="8"/></svg>',
      ]);
      // Beside its name.
      expect(find.byType(TraitIcon), findsOneWidget);
      await tester.tap(find.byTooltip('Icon'));
      await tester.pumpAndSettle();
      expect(find.text('Remove icon'), findsOneWidget);
      expect(find.text('Replace icon from .svg'), findsOneWidget);
    });

    testWidgets("says why a file can't be its icon, and doesn't save it", (
      tester,
    ) async {
      final saved = await open(tester, file: '<svg><path/></svg>');
      await tester.tap(find.byTooltip('Icon'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Import .svg icon'));
      await tester.pumpAndSettle();
      expect(saved, isEmpty);
      expect(find.textContaining('viewBox'), findsOneWidget);
    });

    testWidgets('removes its icon', (tester) async {
      final saved = await open(tester, trait: _calm);
      expect(find.byType(TraitIcon), findsOneWidget);
      await tester.tap(find.byTooltip('Icon'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Remove icon'));
      await tester.pumpAndSettle();
      expect(saved, [null]);
      expect(find.byType(TraitIcon), findsNothing);
    });
  });

  test("the in-memory repository refuses an icon as the server would", () {
    final repository = InMemoryTraitsRepository(traits: const [_plain]);
    expect(
      repository.updateTrait('plain', {'icon': '<svg/>'}),
      throwsA(isA<McpException>()),
    );
  });
}
