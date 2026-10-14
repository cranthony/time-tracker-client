import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:time_tracker_client/models/event.dart';
import 'package:time_tracker_client/models/person.dart';
import 'package:time_tracker_client/services/people_repository.dart';
import 'package:time_tracker_client/widgets/event_summary_dialog.dart';

void main() {
  testWidgets("an event with no map location opens its location's, until "
      'it has its own', (tester) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    Map<String, Object?>? created;
    final people = InMemoryPeopleRepository(
      locations: const [
        Location(id: 'home', name: 'Home', mapLocation: '1 Main St'),
        Location(id: 'park', name: 'The park'),
      ],
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
                initial: const {
                  'summary': 'Dinner',
                  'facts': {'location_id': 'home'},
                },
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
    expect(find.text('Home'), findsOneWidget);
    expect(find.byTooltip('Open in Maps'), findsOneWidget);

    // The sheet's map page shows the location's as a hint, and a location
    // without one has none.
    await tester.tap(find.text('Home'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(Tab, 'Map location'));
    await tester.pumpAndSettle();
    expect(find.text("The location's: 1 Main St"), findsOneWidget);
    expect(find.widgetWithText(TextButton, 'Open in Maps'), findsOneWidget);
    await tester.tap(find.widgetWithText(Tab, 'Location'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(RadioListTile<String>, 'The park'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Done'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Open in Maps'), findsNothing);

    // Its own, a link, wins over the location's.
    await tester.tap(find.text('The park'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(RadioListTile<String>, 'Home'));
    await tester.tap(find.widgetWithText(Tab, 'Map location'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byType(TextField).last,
      'https://maps.app.goo.gl/abc123',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Done'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Open link'), findsOneWidget);
    expect(find.byTooltip('Open in Maps'), findsNothing);

    await tester.tap(find.text('Create'));
    await tester.pumpAndSettle();
    expect(created!['location'], 'https://maps.app.goo.gl/abc123');
  });

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
    await tester.tap(find.widgetWithText(RadioListTile<String>, 'Home'));
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

  group('a new event can repeat', () {
    Future<List<Map<String, Object?>>> open(WidgetTester tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final created = <Map<String, Object?>>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () => showNewEventDialog(
                context,
                start: DateTime(2026, 10, 1, 18),
                end: DateTime(2026, 10, 1, 20),
                repeatable: true,
                create: (fields) async {
                  created.add(fields);
                  return const <Event>[];
                },
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, 'Run');
      await tester.pumpAndSettle();
      return created;
    }

    testWidgets("weekly at first, then however it's changed", (tester) async {
      final created = await open(tester);
      await tester.tap(find.text('No recurrence'));
      await tester.pumpAndSettle();
      expect(find.text('Every week on Thu'), findsOneWidget);

      await tester.tap(find.text('Day'));
      await tester.pumpAndSettle();
      expect(find.text('Every day'), findsOneWidget);
      await tester.tap(find.text('Create'));
      await tester.pumpAndSettle();
      expect(created.single['repeat'], {'every': 'day', 'interval': 1});
    });

    testWidgets("\"Don't repeat\" takes it back", (tester) async {
      final created = await open(tester);
      await tester.tap(find.text('No recurrence'));
      await tester.pumpAndSettle();
      await tester.tap(find.text("Don't repeat"));
      await tester.pumpAndSettle();
      expect(find.text('No recurrence'), findsOneWidget);
      await tester.tap(find.text('Create'));
      await tester.pumpAndSettle();
      expect(created.single.containsKey('repeat'), isFalse);
    });
  });
}
