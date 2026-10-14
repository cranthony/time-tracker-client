import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:time_tracker_client/models/person.dart';
import 'package:time_tracker_client/models/scoring.dart';
import 'package:time_tracker_client/models/trait.dart';
import 'package:time_tracker_client/screens/scoring_defaults_screen.dart';
import 'package:time_tracker_client/services/plan_memory.dart';
import 'package:time_tracker_client/services/traits_repository.dart';
import 'package:time_tracker_client/widgets/parts_editor.dart';
import 'package:time_tracker_client/widgets/person_dialog.dart';
import 'package:time_tracker_client/widgets/trait_dialog.dart';

/// Opens what [open] opens, from a button.
Future<void> _open(
  WidgetTester tester,
  Future<void> Function(BuildContext context) open,
) async {
  tester.view.physicalSize = const Size(900, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () => open(context),
          child: const Text('Open'),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
}

Finder _field(String label) => find.widgetWithText(TextField, label);

void main() {
  testWidgets("a trait's parts are weighed, and combined, as its scoring "
      'says; a part let go takes its weight with it', (tester) async {
    Trait? saved;
    await _open(
      tester,
      (context) => showTraitEditor(
        context,
        trait: const Trait(
          id: 'reliable',
          name: 'Reliable',
          parts: [
            {'id': 'calls', 'kind': 'count', 'target': 1},
            {'id': 'gone', 'kind': 'continuity'},
          ],
          scoring: Aggregation(weights: {'gone': 2}),
        ),
        save: (trait) async => saved = trait,
      ),
    );

    expect(find.text('Mean, weighted'), findsOneWidget);
    await tester.tap(find.byTooltip('Edit how its parts combine'));
    await tester.pumpAndSettle();
    await tester.enterText(_field('any event every 30 days'), '3');
    await tester.tap(find.text('Percentile'));
    await tester.pump();
    await tester.enterText(_field('Percentile, 0 to 100'), '101');
    await tester.pump();
    // Not a percentile: not done till it is.
    expect(find.text('The percentile must be from 0 to 100.'), findsOneWidget);
    await tester.enterText(_field('Percentile, 0 to 100'), '25');
    await tester.pump();
    expect(find.text('25th percentile, weighted'), findsOneWidget);
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();

    // Continuity let go.
    await tester.tap(find.byTooltip('Remove part 2'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(saved!.scoring!.toJson(), {
      'statistic': 'percentile',
      'percentile': 25,
      'weights': {'calls': 3},
    });
  });

  testWidgets("a judgment's judgments combine by time, only the best hours "
      'counting', (tester) async {
    List<Part>? edited;
    await _open(
      tester,
      (context) async => edited = await showPartsEditor(
        context,
        title: 'Daring',
        parts: const [
          {
            'id': 'j1',
            'kind': 'judgment',
            'rubric': 'New?',
            'ratings': {'0': 'No', '1': 'Yes'},
            'facts': ['action'],
          },
        ],
      ),
    );

    expect(
      find.text(
        'Scores the mean of its judgments, each a share of the top rating.',
      ),
      findsOneWidget,
    );
    await tester.tap(find.text('Its time'));
    await tester.pump();
    await tester.tap(find.text('Only some of their time'));
    await tester.pump();
    await tester.tap(find.text('Best'));
    await tester.pump();
    await tester.enterText(_field('1h'), '1h 30m');
    await tester.pump();
    expect(
      find.text(
        'Scores the mean of the best 1h 30m, by time of its judgments, '
        'each a share of the top rating.',
      ),
      findsOneWidget,
    );
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();

    expect(edited!.single['scoring'], {
      'weight_by': 'duration',
      'limit': 1.5,
      'limit_by': 'best',
    });
  });

  testWidgets("a circle's people combine as its own scoring says", (
    tester,
  ) async {
    Map<String, Object?>? fields;
    await _open(
      tester,
      (context) => showCircleDialog(
        context,
        circle: const Circle(id: 'fam', name: 'Family'),
        members: const {'sam': 'Sam', 'jo': 'Jo'},
        defaultScoring: Aggregation.lowest,
        save: (saved) async => fields = saved,
      ),
    );

    expect(find.text("The defaults': lowest"), findsNothing);
    expect(find.text("The defaults': mean of the worst 1"), findsOneWidget);
    await tester.tap(find.byTooltip('Edit how its people combine'));
    await tester.pumpAndSettle();
    await tester.enterText(_field('Sam'), '2');
    await tester.pump();
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(fields!['scoring'], {
      'weights': {'sam': 2},
    });
  });

  testWidgets('the scoring defaults are saved, and the scores worked out '
      'with them', (tester) async {
    final repository = InMemoryTraitsRepository(
      traits: const [Trait(id: 'kind', name: 'Kind')],
    );
    final memory = PlanMemory();
    await memory.loadTraits(repository);
    await _open(
      tester,
      (context) =>
          showScoringDefaults(context, repository: repository, memory: memory),
    );

    expect(find.text('Lowest'), findsOneWidget);
    await tester.tap(find.byTooltip("Edit a circle's people"));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Only some people count'));
    await tester.pump();
    await tester.enterText(_field('How many'), '2');
    await tester.pump();
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(repository.defaults.circles?.toJson(), {
      'limit': 2,
      'limit_by': 'worst',
    });
    expect(memory.scoringDefaults.circles?.limit, 2);
  });
}
