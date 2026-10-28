import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:time_tracker_client/models/plan_action.dart';
import 'package:time_tracker_client/widgets/quick_add_sheet.dart';

void main() {
  /// The quick New action sheet, opened, with [actions] to pick a group
  /// from; a group added goes to [addedGroups], the action to [added].
  Future<void> open(
    WidgetTester tester, {
    List<PlanAction> actions = const [],
    required List<Map<String, Object?>> addedGroups,
    required List<Map<String, Object?>> added,
  }) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    var all = actions;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => showAddActionSheet<String>(
              context,
              name: 'Make tofu',
              actions: actions,
              save: (fields) async {
                added.add(fields);
                return 'new';
              },
              addGroup: (fields) async {
                addedGroups.add(fields);
                final id = 'g${addedGroups.length}';
                all = [
                  ...all,
                  PlanAction(
                    id: id,
                    name: fields['name'] as String,
                    parentId: fields['parent_id'] as String?,
                    status: 'active',
                    properties: const {'kind': 'group'},
                  ),
                ];
                return (id: id, actions: all);
              },
            ),
            child: const Text('Open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
  }

  testWidgets('a note typed is saved with it', (tester) async {
    final added = <Map<String, Object?>>[];
    await open(tester, addedGroups: [], added: added);

    await tester.enterText(
      find.widgetWithText(TextField, 'Note (optional)'),
      '  Pressed, not silken  ',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Add'));
    await tester.pumpAndSettle();

    expect(added, [
      {'name': 'Make tofu', 'parent_id': null, 'note': 'Pressed, not silken'},
    ]);
  });

  testWidgets('with no note, none is sent', (tester) async {
    final added = <Map<String, Object?>>[];
    await open(tester, addedGroups: [], added: added);

    await tester.tap(find.widgetWithText(FilledButton, 'Add'));
    await tester.pumpAndSettle();

    expect(added.single.containsKey('note'), isFalse);
  });

  testWidgets('a group added from the picker, named as typed, is picked', (
    tester,
  ) async {
    final addedGroups = <Map<String, Object?>>[];
    final added = <Map<String, Object?>>[];
    await open(
      tester,
      actions: const [
        PlanAction(
          id: 'food',
          name: 'Food',
          status: 'active',
          properties: {'kind': 'group'},
        ),
      ],
      addedGroups: addedGroups,
      added: added,
    );

    await tester.tap(find.byType(ActionGroupField));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'Cooking');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add group “Cooking”…'));
    await tester.pumpAndSettle();

    // The quick sheet, named as typed, put inside Food.
    expect(find.text('New group'), findsOneWidget);
    await tester.tap(find.byType(ActionGroupField).last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Food').last);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Add').last);
    await tester.pumpAndSettle();

    expect(addedGroups, [
      {'name': 'Cooking', 'parent_id': 'food', 'kind': 'group'},
    ]);
    // Back on the action's sheet, it's the group picked.
    expect(find.text('New group'), findsNothing);
    expect(find.text('Cooking'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Add'));
    await tester.pumpAndSettle();
    expect(added.single['parent_id'], 'g1');
  });
}
