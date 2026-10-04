import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:time_tracker_client/models/goal.dart';
import 'package:time_tracker_client/models/measure.dart';
import 'package:time_tracker_client/widgets/measure_editor.dart';

void main() {
  group('weighted rollup', () {
    const goals = [
      Goal(id: 'cook', name: 'Cooking'),
      Goal(id: 'tofu', name: 'Tofu', parentId: 'cook'),
      Goal(id: 'soup', name: 'Soup', parentId: 'cook', status: 'inactive'),
      Goal(id: 'cake', name: 'Cake', parentId: 'cook', status: 'completed'),
      Goal(id: 'stew', name: 'Stew', parentId: 'cook', status: 'deleted'),
    ];

    Future<List<Measure?>> pump(WidgetTester tester) async {
      final changes = <Measure?>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: MeasureEditor(
                measure: const {
                  'kind': 'rollup',
                  'agg': 'weighted',
                  'weights': {'tofu': 1, 'soup': 2, 'cake': 3},
                },
                onChanged: changes.add,
                goalId: 'cook',
                goals: Future.value(goals),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return changes;
    }

    testWidgets('hides completed and deleted sub-goals', (tester) async {
      await pump(tester);

      expect(find.widgetWithText(TextField, 'Tofu'), findsOneWidget);
      expect(find.widgetWithText(TextField, 'Soup'), findsOneWidget);
      expect(find.widgetWithText(TextField, 'Cake'), findsNothing);
      expect(find.widgetWithText(TextField, 'Stew'), findsNothing);
    });

    testWidgets('greys an inactive sub-goal, saying why', (tester) async {
      await pump(tester);

      expect(
        find.text("Inactive: not rated, so it doesn't count"),
        findsOneWidget,
      );
      final tofu = tester.widget<TextField>(
        find.widgetWithText(TextField, 'Tofu'),
      );
      expect(tofu.decoration?.helperText, isNull);
    });

    testWidgets('keeps a hidden sub-goal\'s weight', (tester) async {
      final changes = await pump(tester);

      await tester.enterText(find.widgetWithText(TextField, 'Tofu'), '4');
      await tester.pump();

      expect(changes.last?['weights'], {'tofu': 4, 'soup': 2, 'cake': 3});
    });
  });

  testWidgets("a count's noun starts lower-case", (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: MeasureEditor(
              measure: const {'kind': 'count', 'target': 1},
              onChanged: (_) {},
            ),
          ),
        ),
      ),
    );

    final noun = tester.widget<TextField>(
      find.widgetWithText(TextField, "What's counted (display only)"),
    );
    expect(noun.textCapitalization, TextCapitalization.none);
  });
}
