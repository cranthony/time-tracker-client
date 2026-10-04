import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:time_tracker_client/models/goal.dart';
import 'package:time_tracker_client/widgets/goals_picker.dart';

const _goals = [
  Goal(id: overallGoalId, name: 'Overall', path: 'Overall'),
  Goal(id: 'cook', name: 'Cooking', path: 'Cooking'),
  Goal(id: 'tofu', parentId: 'cook', name: 'Tofu', path: 'Cooking › Tofu'),
  Goal(id: 'dal', parentId: 'cook', name: 'Dal', path: 'Cooking › Dal'),
  Goal(id: 'run', name: 'Running', path: 'Running'),
  Goal(id: '10k', parentId: 'run', name: '10k', path: 'Running › 10k'),
  Goal(id: 'old', name: 'Old', path: 'Old', status: 'archived'),
];

/// Pumps a picker over [_goals], starting with [picked]; returns the ids
/// as they're changed.
Future<List<String>> _pump(WidgetTester tester, List<String> picked) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: StatefulBuilder(
          builder: (context, setState) => GoalsPicker(
            goals: _goals,
            picked: picked,
            onChanged: (ids) => setState(() {
              picked
                ..clear()
                ..addAll(ids);
            }),
            marker: (_) => const SizedBox(width: 8),
          ),
        ),
      ),
    ),
  );
  return picked;
}

void main() {
  testWidgets('opens only the branches holding a picked goal', (tester) async {
    await _pump(tester, ['10k']);
    // Not the overall goal, nor an inactive one not picked.
    expect(find.text('Overall'), findsNothing);
    expect(find.text('Old'), findsNothing);
    expect(find.text('Cooking'), findsOneWidget);
    expect(find.text('Tofu'), findsNothing);
    // Picked: a chip, and its row, opened down to it.
    expect(find.text('10k'), findsNWidgets(2));

    await tester.tap(find.byTooltip('Show 2 sub-goals'));
    await tester.pumpAndSettle();
    expect(find.text('Tofu'), findsOneWidget);
    await tester.tap(find.byTooltip('Hide sub-goals').first);
    await tester.pumpAndSettle();
    expect(find.text('Tofu'), findsNothing);
  });

  testWidgets('searches every goal by its whole path', (tester) async {
    final picked = await _pump(tester, []);
    await tester.enterText(find.byType(TextField), 'cook to');
    await tester.pumpAndSettle();
    // Out of the tree, with where it sits.
    expect(find.text('Tofu'), findsOneWidget);
    expect(find.text('Cooking'), findsOneWidget);
    expect(find.text('Dal'), findsNothing);
    expect(find.text('Running'), findsNothing);

    // Enter picks the top match, and clears the search.
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(picked, ['tofu']);
    expect(find.text('Running'), findsOneWidget);
    // Shown where it sits in the tree, and the search kept for the next.
    expect(find.text('Tofu'), findsNWidgets(2));
    expect(
      tester.widget<TextField>(find.byType(TextField)).focusNode?.hasFocus,
      isTrue,
    );

    await tester.enterText(find.byType(TextField), 'nothing like it');
    await tester.pumpAndSettle();
    expect(find.text('No goals match.'), findsOneWidget);
  });

  testWidgets('keeps the picking order; the first is primary', (tester) async {
    final picked = await _pump(tester, ['run']);
    await tester.tap(find.text('Cooking'));
    await tester.pumpAndSettle();
    expect(picked, ['run', 'cook']);
    expect(find.byTooltip('Primary goal'), findsOneWidget);

    // The primary goal's ✕ makes the next one primary.
    await tester.tap(find.byTooltip('Remove').first);
    await tester.pumpAndSettle();
    expect(picked, ['cook']);
  });

  testWidgets('lists an inactive goal already picked', (tester) async {
    await _pump(tester, ['old']);
    expect(find.text('Old'), findsNWidgets(2));
  });
}
