import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:time_tracker_client/models/facts.dart';
import 'package:time_tracker_client/models/plan_action.dart';
import 'package:time_tracker_client/widgets/actions_picker.dart';
import 'package:time_tracker_client/widgets/picker_search.dart';
import 'package:time_tracker_client/widgets/picker_sheet.dart';
import 'package:time_tracker_client/widgets/tree_picker.dart';

const _actions = [
  PlanAction(
    id: 'cook',
    name: 'Cooking',
    path: 'Cooking',
    properties: {'kind': 'group'},
  ),
  PlanAction(
    id: 'tofu',
    parentId: 'cook',
    name: 'Tofu',
    path: 'Cooking › Tofu',
  ),
  PlanAction(id: 'run', name: 'Running', path: 'Running'),
];

void main() {
  group('PickerQuery', () {
    const names = ['Lunch with Sam', 'Sam', 'Dinner', 'Lunch'];

    test('matches every word, in order', () {
      expect(PickerQuery('sam lunch').filter(names, (n) => n), [
        'Lunch with Sam',
      ]);
    });

    test('with any, matches any word, the most matched first', () {
      expect(PickerQuery('lunch sam', any: true).filter(names, (n) => n), [
        'Lunch with Sam',
        'Sam',
        'Lunch',
      ]);
    });

    test('nothing typed is empty', () {
      expect(PickerQuery('  ').isEmpty, isTrue);
    });
  });

  testWidgets('a TreePicker matches any word, edits on a long press, and '
      'adds what was typed', (tester) async {
    final search = PickerSearch();
    addTearDown(search.dispose);
    String? edited, added;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TreePicker(
            nodes: const [
              PickerNode(id: 'Sam Lee', label: 'Sam Lee'),
              PickerNode(id: 'Priya Shah', label: 'Priya Shah'),
              PickerNode(id: 'Alex Ortiz', label: 'Alex Ortiz'),
            ],
            picked: const [],
            caption: 'Who was there',
            empty: 'No one yet',
            search: search,
            onChanged: (_) {},
            onEdit: (node) => edited = node.id,
            add: (
              noun: 'person',
              icon: Icons.person_add_alt,
              onAdd: (name) => added = name,
            ),
          ),
        ),
      ),
    );
    await tester.enterText(find.byType(TextField), 'priya sam');
    await tester.pump();
    expect(find.text('Nothing matches.'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilterChip, 'Any'));
    await tester.pump();
    expect(find.widgetWithText(CheckboxListTile, 'Sam Lee'), findsOneWidget);
    expect(find.widgetWithText(CheckboxListTile, 'Priya Shah'), findsOneWidget);
    expect(find.widgetWithText(CheckboxListTile, 'Alex Ortiz'), findsNothing);

    await tester.longPress(find.widgetWithText(CheckboxListTile, 'Sam Lee'));
    expect(edited, 'Sam Lee');

    await tester.tap(find.text('Add person “priya sam”…'));
    expect(added, 'priya sam');
  });

  testWidgets('an ActionsPicker opens a group tapped anywhere, edits on a '
      'long press, and starts with its search selected', (tester) async {
    final search = PickerSearch(text: 'cooking run', matchAny: true);
    addTearDown(search.dispose);
    PlanAction? edited;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ActionsPicker(
            actions: _actions,
            picked: const [],
            leavesOnly: true,
            autofocus: true,
            search: search,
            marker: (_) => const SizedBox(width: 8),
            onChanged: (_) {},
            onEdit: (action) => edited = action,
          ),
        ),
      ),
    );
    await tester.pump();
    // Each word's matches, the selection over what's typed, to type over.
    expect(find.text('Running'), findsOneWidget);
    expect(find.text('Tofu'), findsOneWidget);
    expect(search.focus.hasFocus, isTrue);
    expect(search.controller.selection.start, 0);
    expect(search.controller.selection.end, 'cooking run'.length);

    search.controller.clear();
    await tester.pump();
    expect(find.text('Tofu'), findsNothing);
    await tester.tap(find.text('Cooking'));
    await tester.pump();
    expect(find.text('Tofu'), findsOneWidget);
    await tester.tap(find.text('Cooking'));
    await tester.pump();
    expect(find.text('Tofu'), findsNothing);

    await tester.longPress(find.text('Cooking'));
    expect(edited?.id, 'cook');
  });

  testWidgets('the Who sheet starts each tab with the summary, and keeps '
      'what each had as it is swiped between, selecting it', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () =>
                showWhoWhereSheet(context, const Facts(), query: 'Lunch'),
            child: const Text('Open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    TextField field() =>
        tester.widget<TextField>(find.byType(TextField).hitTestable());
    expect(field().controller!.text, 'Lunch');
    expect(field().focusNode!.hasFocus, isTrue);
    expect(field().controller!.selection.end, 'Lunch'.length);

    await tester.enterText(find.byType(TextField).hitTestable(), 'Sam');
    await tester.tap(find.text('For'));
    await tester.pumpAndSettle();
    expect(field().controller!.text, 'Lunch');
    expect(field().focusNode!.hasFocus, isTrue);
    expect(field().controller!.selection.end, 'Lunch'.length);

    await tester.tap(find.text('With'));
    await tester.pumpAndSettle();
    expect(field().controller!.text, 'Sam');
    expect(field().focusNode!.hasFocus, isTrue);
    expect(field().controller!.selection.end, 'Sam'.length);
  });

  testWidgets('the Location sheet selects the map location swiped to', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => showWhoWhereSheet(
              context,
              const Facts(),
              where: true,
              mapLocation: '1 Main St',
            ),
            child: const Text('Open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Map location'));
    await tester.pumpAndSettle();

    final field = tester.widget<TextField>(
      find.byType(TextField).hitTestable(),
    );
    expect(field.controller!.text, '1 Main St');
    expect(field.focusNode!.hasFocus, isTrue);
    expect(field.controller!.selection.end, '1 Main St'.length);
  });
}
