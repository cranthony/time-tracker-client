import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:time_tracker_client/models/event.dart';
import 'package:time_tracker_client/services/people_repository.dart';
import 'package:time_tracker_client/widgets/event_summary_dialog.dart';

void main() {
  /// Opens the dialog of an event at [location], if any.
  Future<void> open(WidgetTester tester, String? location) async {
    final event = Event(
      id: 'e1',
      summary: 'Dentist',
      start: DateTime(2026, 10, 1, 18),
      end: DateTime(2026, 10, 1, 18, 30),
      properties: {'location': ?location, 'description': 'Checkup'},
    );
    await tester.pumpWidget(
      PeopleScope(
        repository: InMemoryPeopleRepository(),
        child: MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () => showEventSummaryDialog(context, event),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
  }

  /// From the location's pin down to the description's icon.
  double rowHeight(WidgetTester tester) =>
      tester.getTopLeft(find.byIcon(Icons.notes)).dy -
      tester.getTopLeft(find.byIcon(Icons.place_outlined)).dy;

  testWidgets('a location with a map button is level with its pin, its row '
      'as tall as without one', (tester) async {
    await open(tester, null);
    final plain = rowHeight(tester);

    await tester.pumpWidget(const SizedBox());
    await open(tester, '12 Fifth Ave');
    expect(find.byTooltip('Open in Maps'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('12 Fifth Ave')).dy,
      tester.getTopLeft(find.byIcon(Icons.place_outlined)).dy,
    );
    expect(rowHeight(tester), plain);
    // Still as easy to tap as an icon button: the row's height, and more.
    final button = tester.getSize(
      find.widgetWithIcon(IconButton, Icons.map_outlined),
    );
    expect(button.width, greaterThanOrEqualTo(48));
    expect(button.height, greaterThanOrEqualTo(44));
  });
}
