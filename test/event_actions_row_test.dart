import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:time_tracker_client/models/event.dart';
import 'package:time_tracker_client/services/people_repository.dart';
import 'package:time_tracker_client/widgets/event_summary_dialog.dart';
import 'package:time_tracker_client/widgets/plow_icon.dart';

void main() {
  /// Opens the dialog of an event with [actions], to edit.
  Future<void> open(WidgetTester tester, List<String> actions) async {
    final event = Event(
      id: 'e1',
      summary: 'Dentist',
      start: DateTime(2026, 10, 1, 18),
      end: DateTime(2026, 10, 1, 18, 30),
      properties: {
        'action_ids': [
          for (final a in actions) {'action_id': a},
        ],
        'description': 'Checkup',
      },
    );
    await tester.pumpWidget(
      PeopleScope(
        repository: InMemoryPeopleRepository(),
        child: MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () => showEventSummaryDialog(
                context,
                event,
                save: (_) async => const [],
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
  }

  /// The chip saying [label], and the room around it that taps it.
  Finder pill(String label) =>
      find.ancestor(of: find.text(label), matching: find.byType(InkWell)).first;
  Finder room(String label) =>
      find.ancestor(of: pill(label), matching: find.byType(MouseRegion)).first;

  /// Taps the first [label] chip's room [dy] below its top, 2 in from
  /// its left: outside the chip itself.
  Future<void> tapRoom(WidgetTester tester, String label, double dy) async {
    await tester.tapAt(tester.getTopLeft(room(label)) + Offset(2, dy));
    await tester.pumpAndSettle();
  }

  testWidgets("a lone action is level with the plow, its chip at the row's "
      'end with the room to tap that the map button has', (tester) async {
    await open(tester, ['Floss']);
    final text = find.text('Floss');
    // The line's padding above it aside, it starts where the plow does.
    expect(
      tester.getTopLeft(text).dy - tester.getTopLeft(find.byType(PlowIcon)).dy,
      2,
    );
    // The chip no taller than the text ...
    expect(
      tester.getSize(pill('All of it')).height,
      lessThanOrEqualTo(tester.getSize(text).height),
    );
    // ... its room to tap, as the map button's, the row's height ...
    final size = tester.getSize(room('All of it'));
    expect(size.height, greaterThanOrEqualTo(44));
    expect(
      size.width,
      greaterThanOrEqualTo(tester.getSize(pill('All of it')).width + 16),
    );
    // ... and the row no taller for it.
    expect(
      tester
          .getSize(
            find
                .ancestor(
                  of: find.byType(PlowIcon),
                  matching: find.byType(InkWell),
                )
                .first,
          )
          .height,
      48,
    );

    // Tapped above the chip, it sets the share.
    await tapRoom(tester, 'All of it', 2);
    expect(find.text('Duration'), findsOneWidget);
  });

  testWidgets("several actions' chips are each on its line, the line's "
      'height to tap', (tester) async {
    await open(tester, ['Floss', 'Brush']);
    expect(
      tester.getTopLeft(find.text('Floss')).dy -
          tester.getTopLeft(find.byType(PlowIcon)).dy,
      2,
    );
    // Lines as far apart as before: a line of text and 2 either side.
    expect(
      tester.getTopLeft(find.text('Brush')).dy -
          tester.getTopLeft(find.text('Floss')).dy,
      28,
    );
    expect(tester.getSize(room('The rest')).height, greaterThanOrEqualTo(28));
    expect(
      tester.getSize(pill('The rest')).height,
      lessThanOrEqualTo(tester.getSize(find.text('Floss')).height),
    );

    await tapRoom(tester, 'The rest', 1);
    expect(find.text('Duration'), findsOneWidget);
  });
}
