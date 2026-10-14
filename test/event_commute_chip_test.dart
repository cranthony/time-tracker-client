import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:time_tracker_client/models/event.dart';
import 'package:time_tracker_client/services/people_repository.dart';
import 'package:time_tracker_client/widgets/event_summary_dialog.dart';

void main() {
  /// Opens [event]'s dialog, returning what a save sends.
  Future<Map<String, Object?>? Function()> open(
    WidgetTester tester,
    Event event,
  ) async {
    Map<String, Object?>? saved;
    await tester.pumpWidget(
      PeopleScope(
        repository: InMemoryPeopleRepository(),
        child: MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () => showEventSummaryDialog(
                context,
                event,
                save: (changes) async {
                  saved = changes;
                  return [event];
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
    return () => saved;
  }

  Event drive(Map<String, Object?> facts) => Event(
    id: 'e1',
    summary: 'Drive home',
    start: DateTime(2026, 10, 1, 18),
    end: DateTime(2026, 10, 1, 18, 30),
    properties: {'facts': facts},
  );

  testWidgets("the commute chip opens a switch that makes it part of a "
      'commute, keeping its other facts', (tester) async {
    final saved = await open(
      tester,
      drive({
        'location_ids': ['home'],
      }),
    );
    expect(find.byTooltip('Not part of a commute'), findsOneWidget);
    expect(find.text('This event is part of a commute'), findsNothing);

    await tester.tap(find.text('Commute'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('This event is part of a commute'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Part of a commute'), findsOneWidget);
    // Marked changed by its chip, not by the rest of its facts' rows.
    expect(find.byTooltip('Changed'), findsOneWidget);
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(saved(), {
      'facts': {
        'location_ids': ['home'],
        'commute': true,
      },
    });
  });

  testWidgets('a commute is made not one by its switch', (tester) async {
    final saved = await open(
      tester,
      drive({
        'location_ids': ['home'],
        'commute': true,
      }),
    );
    expect(find.byTooltip('Part of a commute'), findsOneWidget);

    await tester.tap(find.text('Commute'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('This event is part of a commute'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(saved(), {
      'facts': {
        'location_ids': ['home'],
      },
    });
  });
}
