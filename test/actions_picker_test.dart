import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:time_tracker_client/models/plan_action.dart';
import 'package:time_tracker_client/widgets/actions_picker.dart';

const _actions = [
  PlanAction(id: 'cook', name: 'Cooking', path: 'Cooking'),
  PlanAction(
    id: 'tofu',
    parentId: 'cook',
    name: 'Tofu',
    path: 'Cooking › Tofu',
  ),
  PlanAction(id: 'dal', parentId: 'cook', name: 'Dal', path: 'Cooking › Dal'),
  PlanAction(id: 'run', name: 'Running', path: 'Running'),
  PlanAction(id: '10k', parentId: 'run', name: '10k', path: 'Running › 10k'),
  PlanAction(id: 'old', name: 'Old', path: 'Old', status: 'archived'),
];

/// Pumps a picker over [_actions], starting with [picked]; returns the ids
/// as they're changed.
Future<List<String>> _pump(WidgetTester tester, List<String> picked) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: StatefulBuilder(
          builder: (context, setState) => ActionsPicker(
            actions: _actions,
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
  testWidgets('opens only the branches holding a picked action', (
    tester,
  ) async {
    await _pump(tester, ['10k']);
    // Not one put away, not picked.
    expect(find.text('Old'), findsNothing);
    expect(find.text('Cooking'), findsOneWidget);
    expect(find.text('Tofu'), findsNothing);
    // Picked: a chip, and its row, opened down to it.
    expect(find.text('10k'), findsNWidgets(2));

    await tester.tap(find.byTooltip('Show 2 inside'));
    await tester.pumpAndSettle();
    expect(find.text('Tofu'), findsOneWidget);
    await tester.tap(find.byTooltip("Hide what's inside").first);
    await tester.pumpAndSettle();
    expect(find.text('Tofu'), findsNothing);
  });

  testWidgets('searches every action by its whole path', (tester) async {
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
      tester.widget<EditableText>(find.byType(EditableText)).focusNode.hasFocus,
      isTrue,
    );

    await tester.enterText(find.byType(TextField), 'nothing like it');
    await tester.pumpAndSettle();
    expect(find.text('No actions match.'), findsOneWidget);
  });

  testWidgets('keeps the picking order; the first is primary', (tester) async {
    final picked = await _pump(tester, ['run']);
    await tester.tap(find.text('Cooking'));
    await tester.pumpAndSettle();
    expect(picked, ['run', 'cook']);
    expect(find.byTooltip('Primary action'), findsOneWidget);

    // The primary action's ✕ makes the next one primary.
    await tester.tap(find.byTooltip('Remove').first);
    await tester.pumpAndSettle();
    expect(picked, ['cook']);
  });

  testWidgets('lists an inactive action already picked', (tester) async {
    await _pump(tester, ['old']);
    expect(find.text('Old'), findsNWidgets(2));
  });

  test('actionAndSubActions is an action and everything under it', () {
    expect(actionAndSubActions(_actions, 'cook'), {'cook', 'tofu', 'dal'});
    expect(actionAndSubActions(_actions, 'tofu'), {'tofu'});
  });

  testWidgets('a ActionField picks one action in a dialog, or none', (
    tester,
  ) async {
    String? value = 'tofu';
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => ActionField(
              actions: _actions,
              value: value,
              noneLabel: 'None',
              exclude: actionAndSubActions(_actions, 'run'),
              marker: (_) => const SizedBox(width: 8),
              onChanged: (id) => setState(() => value = id),
            ),
          ),
        ),
      ),
    );
    // Its whole path.
    expect(find.text('Cooking › Tofu'), findsOneWidget);

    await tester.tap(find.byType(ActionField));
    await tester.pumpAndSettle();
    // Opened down to the action picked; not those excluded; inactive ones
    // too.
    expect(find.text('Dal'), findsOneWidget);
    expect(find.text('Running'), findsNothing);
    expect(find.text('10k'), findsNothing);
    expect(find.text('Old'), findsOneWidget);
    // Picked on a tap, which closes it.
    await tester.tap(find.text('Dal'));
    await tester.pumpAndSettle();
    expect(value, 'dal');
    expect(find.byType(ActionsPicker), findsNothing);
    expect(find.text('Cooking › Dal'), findsOneWidget);

    // Searched, and picked with Enter.
    await tester.tap(find.byType(ActionField));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'old');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(value, 'old');

    // Cancel keeps it; None clears it.
    await tester.tap(find.byType(ActionField));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(value, 'old');
    await tester.tap(find.byType(ActionField));
    await tester.pumpAndSettle();
    await tester.tap(find.text('None'));
    await tester.pumpAndSettle();
    expect(value, isNull);
    expect(find.text('None'), findsOneWidget);
  });
}
