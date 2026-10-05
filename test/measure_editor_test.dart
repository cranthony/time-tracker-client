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
      Goal(id: 'pie', name: 'Pie', parentId: 'cook', status: 'proposed'),
      Goal(id: 'jam', name: 'Jam', parentId: 'cook', status: 'archived'),
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

    testWidgets('hides proposed, completed, archived and deleted '
        'sub-goals', (tester) async {
      await pump(tester);

      expect(find.widgetWithText(TextField, 'Tofu'), findsOneWidget);
      expect(find.widgetWithText(TextField, 'Soup'), findsOneWidget);
      expect(find.widgetWithText(TextField, 'Cake'), findsNothing);
      expect(find.widgetWithText(TextField, 'Stew'), findsNothing);
      expect(find.widgetWithText(TextField, 'Pie'), findsNothing);
      expect(find.widgetWithText(TextField, 'Jam'), findsNothing);
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

    testWidgets('keeps a sub-goal set aside until a day, and can bring it '
        'back', (tester) async {
      final changes = <Measure?>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: MeasureEditor(
                measure: const {
                  'kind': 'rollup',
                  'agg': 'weighted',
                  'weights': {
                    'tofu': 1,
                    'soup': {'weight': 0, 'until': '2026-11-05', 'then': 2},
                  },
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

      expect(find.textContaining('Nov 5'), findsOneWidget);
      await tester.enterText(find.widgetWithText(TextField, 'Then'), '3');
      await tester.pump();
      expect(changes.last?['weights'], {
        'tofu': 1,
        'soup': {'weight': 0, 'until': '2026-11-05', 'then': 3},
      });

      await tester.tap(find.byTooltip("Don't set it aside"));
      await tester.pump();
      expect(changes.last?['weights'], {'tofu': 1, 'soup': 0});
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

  testWidgets('a follow-through measure keeps what it was given', (
    tester,
  ) async {
    final changes = <Measure?>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: MeasureEditor(
              measure: const {'kind': 'follow_through', 'penalty': 50},
              onChanged: changes.add,
            ),
          ),
        ),
      ),
    );

    await tester.enterText(
      find.widgetWithText(TextField, 'Over the last'),
      '60',
    );
    await tester.pump();

    expect(changes.last, {
      'kind': 'follow_through',
      'penalty': 50,
      'look_back_days': 60,
    });
    expect(measureProblem(changes.last!), isNull);
  });

  group('time window, and only on days with events', () {
    const goals = [
      Goal(id: 'eat', name: 'Eat well'),
      Goal(id: 'lunch', name: 'Eat lunch', parentId: 'eat'),
      Goal(id: 'salsa', name: 'Practice salsa'),
    ];

    Future<List<Measure?>> pump(WidgetTester tester, Measure? measure) async {
      final changes = <Measure?>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: MeasureEditor(
                measure: measure,
                onChanged: changes.add,
                goalId: 'lunch',
                goals: Future.value(goals),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return changes;
    }

    testWidgets('a time window keeps what it was given, and its window', (
      tester,
    ) async {
      final changes = await pump(tester, const {
        'kind': 'time_window',
        'from': '11:30',
        'to': '13:30',
        'grace_min': 15,
        'events_of': 'eat',
        'include_sub_goals': false,
      });
      expect(find.text('From 11:30'), findsOneWidget);
      expect(find.text('to 13:30'), findsOneWidget);

      await tester.enterText(
        find.widgetWithText(TextField, 'Zero at, in minutes off'),
        '60',
      );
      await tester.pump();
      expect(changes.last, {
        'kind': 'time_window',
        'from': '11:30',
        'to': '13:30',
        'grace_min': 15,
        'zero_at_min': 60,
        'events_of': 'eat',
        'include_sub_goals': false,
      });
      expect(measureProblem(changes.last!), isNull);
    });

    testWidgets('only_if is turned on for its own goal, or another', (
      tester,
    ) async {
      final changes = await pump(tester, const {
        'kind': 'subjective',
        'prompt': 'How did practice go?',
      });
      await tester.tap(find.text('Only rate days with events'));
      await tester.pumpAndSettle();
      expect(changes.last?['only_if'], <String, Object?>{});

      await tester.tap(find.text('Another goal'));
      await tester.pumpAndSettle();
      expect(changes.last?['only_if'], {'events_of': ''});
      expect(measureProblem(changes.last!), contains('Choose the goal'));

      await tester.tap(find.text('Pick a goal'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Practice salsa').last);
      await tester.pumpAndSettle();
      expect(changes.last, {
        'kind': 'subjective',
        'prompt': 'How did practice go?',
        'only_if': {'events_of': 'salsa'},
      });

      await tester.tap(find.text('Only rate days with events'));
      await tester.pumpAndSettle();
      expect(changes.last?.containsKey('only_if'), isFalse);
    });

    testWidgets('only_if is read back as it was saved', (tester) async {
      final changes = await pump(tester, const {
        'kind': 'count',
        'target': 1,
        'only_if': {'events_of': 'salsa', 'include_sub_goals': false},
      });
      await tester.enterText(find.widgetWithText(TextField, 'Target'), '2');
      await tester.pump();
      expect(changes.last?['only_if'], {
        'events_of': 'salsa',
        'include_sub_goals': false,
      });
    });
  });
}
