import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:time_tracker_client/models/event.dart';
import 'package:time_tracker_client/models/person.dart';
import 'package:time_tracker_client/services/people_repository.dart';
import 'package:time_tracker_client/widgets/event_summary_dialog.dart';

void main() {
  testWidgets("a new event's dialog has who, where and notes, as an "
      "event's, and creates it with them", (tester) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    Map<String, Object?>? created;
    final people = InMemoryPeopleRepository(
      people: const [
        Person(id: 'sam', name: 'Sam'),
        Person(id: 'priya', name: 'Priya'),
      ],
      locations: const [Location(id: 'home', name: 'Home')],
    );
    await tester.pumpWidget(
      PeopleScope(
        repository: people,
        child: MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () => showNewEventDialog(
                context,
                start: DateTime(2026, 10, 1, 18),
                end: DateTime(2026, 10, 1, 20),
                create: (fields) async {
                  created = fields;
                  return const <Event>[];
                },
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(find.text('Add who'), findsOneWidget);
    expect(find.text('Add location'), findsOneWidget);
    expect(find.text('Add what happened'), findsOneWidget);
    await tester.enterText(find.byType(TextField).first, 'Dinner');
    await tester.pumpAndSettle();

    // Who, with and for, in a sheet.
    await tester.tap(find.text('Add who'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(CheckboxListTile, 'Sam'));
    await tester.tap(find.widgetWithText(Tab, 'For'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(CheckboxListTile, 'Priya'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Done'));
    await tester.pumpAndSettle();
    expect(find.text('With Sam · For Priya'), findsOneWidget);

    // Where, from the list.
    await tester.tap(find.text('Add location'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(CheckboxListTile, 'Home'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Done'));
    await tester.pumpAndSettle();
    expect(find.text('Home'), findsOneWidget);

    await tester.tap(find.text('Create'));
    await tester.pumpAndSettle();

    expect(created!['summary'], 'Dinner');
    expect(created!['facts'], {
      'location_id': 'home',
      'with_ids': ['sam'],
      'for_ids': ['priya'],
    });
  });
}
