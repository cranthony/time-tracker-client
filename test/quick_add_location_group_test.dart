import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:time_tracker_client/models/person.dart';
import 'package:time_tracker_client/widgets/quick_add_sheet.dart';

void main() {
  /// The quick New location sheet, opened, with [groups] to pick from; a
  /// group added goes to [addedGroups], a location to [addedLocations].
  Future<void> open(
    WidgetTester tester, {
    List<LocationGroup> groups = const [],
    required List<Map<String, Object?>> addedGroups,
    required List<Map<String, Object?>> addedLocations,
  }) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => showAddLocationSheet<Location>(
              context,
              name: 'Prospect Park',
              groups: groups,
              save: (fields) async {
                addedLocations.add(fields);
                return Location(id: 'new', name: fields['name'] as String);
              },
              addGroup: (fields) async {
                addedGroups.add(fields);
                return LocationGroup(
                  id: 'g${addedGroups.length}',
                  name: fields['name'] as String,
                  groupId: fields['group_id'] as String?,
                );
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

  testWidgets('a group added from the picker, named as typed, is picked', (
    tester,
  ) async {
    final addedGroups = <Map<String, Object?>>[];
    final addedLocations = <Map<String, Object?>>[];
    await open(
      tester,
      groups: const [LocationGroup(id: 'nyc', name: 'New York')],
      addedGroups: addedGroups,
      addedLocations: addedLocations,
    );

    await tester.tap(find.byType(LocationGroupField));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'Brooklyn');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add location group “Brooklyn”…'));
    await tester.pumpAndSettle();

    // The quick sheet, named as typed, put inside New York.
    expect(find.text('New location group'), findsOneWidget);
    await tester.tap(find.byType(LocationGroupField).last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('New York').last);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Add').last);
    await tester.pumpAndSettle();

    expect(addedGroups, [
      {'name': 'Brooklyn', 'note': null, 'group_id': 'nyc'},
    ]);
    // Back on the location's sheet, it's the group picked.
    expect(find.text('New location group'), findsNothing);
    expect(find.text('Brooklyn'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Add'));
    await tester.pumpAndSettle();
    expect(addedLocations.single['group_id'], 'g1');
  });

  testWidgets('with no groups yet, the first can be added', (tester) async {
    final addedGroups = <Map<String, Object?>>[];
    await open(tester, addedGroups: addedGroups, addedLocations: []);

    await tester.tap(find.byType(LocationGroupField));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add location group…'));
    await tester.pumpAndSettle();
    // Its name, which has the keyboard.
    tester.testTextInput.enterText('Parks');
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Add').last);
    await tester.pumpAndSettle();

    expect(addedGroups.single['name'], 'Parks');
    expect(find.text('Parks'), findsOneWidget);
  });
}
