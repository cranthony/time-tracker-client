import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:time_tracker_client/models/trait.dart';
import 'package:time_tracker_client/screens/trait_screen.dart';
import 'package:time_tracker_client/widgets/trait_dialog.dart';

const _part = {
  'id': 'calm',
  'kind': 'judgment',
  'rubric': 'Was it calm?',
  'ratings': {'0': 'No', '1': 'Mostly', '2': 'Yes'},
  'facts': ['general_notes'],
};

const _steady = Trait(
  id: 'steady',
  name: 'Steady',
  parts: [_part],
  techniques: ['Wait out the first few seconds', 'Name the feeling'],
);

Finder _field(String label) => find.widgetWithText(TextField, label);

void main() {
  test('techniques read from the server, in order, and are written back', () {
    final trait = Trait.fromJson({
      'id': 'steady',
      'name': 'Steady',
      'parts': [_part],
      'techniques': ['Ask why', ' ', 'Name the feeling'],
    });

    expect(trait.techniques, ['Ask why', 'Name the feeling']);
    expect(trait.toJson()['techniques'], ['Ask why', 'Name the feeling']);
    // A server before them: none, and none sent.
    final before = Trait.fromJson({'id': 'x', 'name': 'X'});
    expect(before.techniques, isEmpty);
    expect(before.toJson().containsKey('techniques'), isFalse);
  });

  testWidgets("a trait's page numbers its techniques", (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: TraitScreen(trait: _steady)),
    );

    expect(find.text('Techniques'), findsOneWidget);
    expect(find.text('1.'), findsOneWidget);
    expect(find.text('Wait out the first few seconds'), findsOneWidget);
    expect(find.text('2.'), findsOneWidget);
    expect(find.text('Name the feeling'), findsOneWidget);
  });

  testWidgets('techniques are added, moved, removed and saved in order', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(900, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    Trait? saved;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => showTraitEditor(
              context,
              trait: _steady,
              save: (trait) async => saved = trait,
            ),
            child: const Text('Open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Add technique'));
    await tester.pumpAndSettle();
    await tester.enterText(_field('Technique 3'), '  Ask why  ');
    await tester.tap(find.byTooltip('Move technique 3 up'));
    await tester.pump();
    await tester.tap(find.byTooltip('Remove technique 1'));
    await tester.pump();
    // A blank one isn't saved.
    await tester.tap(find.text('Add technique'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(saved?.techniques, ['Ask why', 'Name the feeling']);
  });
}
