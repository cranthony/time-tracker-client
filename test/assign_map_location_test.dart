import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:time_tracker_client/models/event.dart';
import 'package:time_tracker_client/models/person.dart';
import 'package:time_tracker_client/services/people_repository.dart';
import 'package:time_tracker_client/services/plan_memory.dart';
import 'package:time_tracker_client/widgets/event_summary_dialog.dart';

void main() {
  /// A new event's dialog, starting with [location] as its map location,
  /// opened; what it creates goes to [created].
  Future<void> open(
    WidgetTester tester,
    InMemoryPeopleRepository people,
    String location,
    void Function(Map<String, Object?> fields) created,
  ) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      PeopleScope(
        repository: people,
        // The Events page's, as the app has: the locations, as saved.
        child: PlanMemoryScope(
          memory: PlanMemory(),
          child: MaterialApp(
            home: Builder(
              builder: (context) => TextButton(
                onPressed: () => showNewEventDialog(
                  context,
                  start: DateTime(2026, 10, 1, 18),
                  end: DateTime(2026, 10, 1, 20),
                  initial: {'summary': 'Dinner', 'location': location},
                  create: (fields) async {
                    created(fields);
                    return const <Event>[];
                  },
                ),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    // Its location's sheet, on its map location's page.
    await tester.tap(find.text(location));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(Tab, 'Map location'));
    await tester.pumpAndSettle();
  }

  /// A field in the dialog over the rest, with [text] in it.
  Finder inDialog(String text) => find.descendant(
    of: find.byType(AlertDialog),
    matching: find.widgetWithText(TextField, text),
  );

  final assign = find.widgetWithText(TextButton, 'Assign to a location');

  testWidgets("an event's map location, given to a location that has "
      "none, is that location's: the event's at it, with none of its own", (
    tester,
  ) async {
    Map<String, Object?>? created;
    final people = InMemoryPeopleRepository(
      locations: const [
        Location(id: 'home', name: 'Home', mapLocation: '1 Main St'),
        Location(id: 'park', name: 'The park'),
      ],
    );
    await open(tester, people, '12 Fifth Ave', (f) => created = f);

    await tester.tap(assign);
    await tester.pumpAndSettle();
    // A picker over the sheet.
    expect(
      find.text('The location to give "12 Fifth Ave" to, as its map location'),
      findsOneWidget,
    );
    await tester.tap(find.text('The park').hitTestable());
    await tester.pumpAndSettle();
    // Saved at once, with no dialog, and the picker closed.
    expect(find.text('Edit location'), findsNothing);
    expect(
      (await people.locations()).firstWhere((l) => l.id == 'park').mapLocation,
      '12 Fifth Ave',
    );
    expect(find.text("The location's: 12 Fifth Ave"), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Done'));
    await tester.pumpAndSettle();
    expect(find.text('The park'), findsOneWidget);
    expect(find.byTooltip('Open in Maps'), findsOneWidget);
    await tester.tap(find.text('Create'));
    await tester.pumpAndSettle();
    expect(created!['location'], isNull);
    expect(created!['facts'], {
      'location_ids': ['park'],
    });
  });

  testWidgets('given to a location with another, its dialog shows both; or '
      "it's given to a new one, named as it's typed", (tester) async {
    Map<String, Object?>? created;
    final people = InMemoryPeopleRepository(
      locations: const [
        Location(id: 'home', name: 'Home', mapLocation: '1 Main St'),
      ],
    );
    await open(tester, people, 'Cafe Roma, 3 Elm St', (f) => created = f);
    // Nothing typed, nothing to give.
    await tester.enterText(find.byType(TextField).last, '');
    await tester.pump();
    expect(tester.widget<TextButton>(assign).onPressed, isNull);
    await tester.enterText(find.byType(TextField).last, 'Cafe Roma, 3 Elm St');
    await tester.pump();

    await tester.tap(assign);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Home').hitTestable());
    await tester.pumpAndSettle();
    expect(find.text('Edit location'), findsOneWidget);
    expect(inDialog('Cafe Roma, 3 Elm St'), findsOneWidget);
    expect(find.text('Was: 1 Main St'), findsOneWidget);
    // Called off, it's kept, and the picker stays.
    await tester.tap(find.text('Cancel').last);
    await tester.pumpAndSettle();
    expect((await people.locations()).single.mapLocation, '1 Main St');
    expect(find.text('Assign to a location'), findsWidgets);

    await tester.enterText(find.byType(TextField).last, 'Cafe Roma');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add location “Cafe Roma”…'));
    await tester.pumpAndSettle();
    expect(find.text('New location'), findsOneWidget);
    expect(inDialog('Cafe Roma, 3 Elm St'), findsOneWidget);
    await tester.tap(find.text('Save').last);
    await tester.pumpAndSettle();
    final made = (await people.locations()).firstWhere(
      (l) => l.name == 'Cafe Roma',
    );
    expect(made.mapLocation, 'Cafe Roma, 3 Elm St');

    await tester.tap(find.widgetWithText(FilledButton, 'Done'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Create'));
    await tester.pumpAndSettle();
    expect(created!['location'], isNull);
    expect(created!['facts'], {
      'location_ids': [made.id],
    });
  });
}
