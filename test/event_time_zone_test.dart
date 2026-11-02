import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:time_tracker_client/models/event.dart';
import 'package:time_tracker_client/models/recurrence.dart';
import 'package:time_tracker_client/models/time_zones.dart';
import 'package:time_tracker_client/services/people_repository.dart';
import 'package:time_tracker_client/widgets/event_summary_dialog.dart';
import 'package:time_tracker_client/widgets/recurrence_dialog.dart';

// The device's zone is whatever the machine's is: times here are
// instants, and nothing said depends on it.

/// 6pm New York on Tue, Nov 3, 2026 (EST): 11pm UTC.
final _sixInNewYork = DateTime.utc(2026, 11, 3, 23);

void main() {
  group('time zones', () {
    test('say where they are, and how far from UTC', () {
      expect(
        zoneLabel('America/New_York', _sixInNewYork),
        'New York (EST, UTC−5)',
      );
      expect(
        zoneLabel('Asia/Kolkata', _sixInNewYork),
        'Kolkata (IST, UTC+5:30)',
      );
      expect(zoneLabel('UTC', _sixInNewYork), 'UTC');
      expect(zoneOffset('UTC', _sixInNewYork), Duration.zero);
      // Before the US's daylight saving ended, after Europe's.
      expect(
        zoneOffset('America/New_York', DateTime.utc(2026, 10, 28, 12)),
        const Duration(hours: -4),
      );
      expect(
        zoneOffset('Europe/London', DateTime.utc(2026, 10, 28, 12)),
        Duration.zero,
      );
      expect(zonePlace('America/Indiana/Knox'), 'Indiana/Knox');
    });

    test('are offered by region, without old aliases', () {
      final names = zoneNames();
      expect(names, containsAll(['UTC', 'Europe/London', 'America/New_York']));
      expect(names, isNot(contains('US/Eastern')));
    });

    test('move a time to the same time of day in another', () {
      final there = sameClock(
        _sixInNewYork,
        'America/New_York',
        'Europe/London',
      );
      expect(there.isAtSameMomentAs(DateTime.utc(2026, 11, 3, 18)), isTrue);
      final clock = clockIn(_sixInNewYork, 'Europe/London');
      expect((clock.hour, clock.minute), (23, 0));
      expect(zoneOf('Mars/Olympus'), isNull);
    });
  });

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

  final meeting = Event(
    id: 'e1',
    summary: 'Call',
    start: _sixInNewYork.toLocal(),
    end: _sixInNewYork.add(const Duration(hours: 1)).toLocal(),
    properties: const {'time_zone': 'America/New_York'},
  );

  /// Opens the time zone row, and picks London.
  Future<void> pickLondon(WidgetTester tester) async {
    await tester.tap(find.textContaining('New York (EST, UTC−5)'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Pick a time zone…'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'london');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Europe/London'));
    await tester.pumpAndSettle();
  }

  testWidgets('an event shows its time zone, and moves to another at the '
      'same time of day', (tester) async {
    final saved = await open(tester, meeting);
    expect(find.textContaining('New York (EST, UTC−5)'), findsOneWidget);

    await pickLondon(tester);
    expect(find.textContaining('London (GMT, UTC)'), findsWidgets);
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    final changes = saved()!;
    expect(changes['time_zone'], 'Europe/London');
    // 6pm, now in London.
    expect(
      DateTime.parse(changes['start']! as String)
          .isAtSameMomentAs(DateTime.utc(2026, 11, 3, 18)),
      isTrue,
    );
    expect(
      DateTime.parse(changes['end']! as String)
          .isAtSameMomentAs(DateTime.utc(2026, 11, 3, 19)),
      isTrue,
    );
  });

  testWidgets('an event moves to another time zone keeping its moment', (
    tester,
  ) async {
    final saved = await open(tester, meeting);

    await pickLondon(tester);
    await tester.tap(find.textContaining('Keep the moment'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(saved(), {'time_zone': 'Europe/London'});
  });

  testWidgets('a time zone picked and then put back changes nothing', (
    tester,
  ) async {
    await open(tester, meeting);

    await pickLondon(tester);
    await tester.tap(find.text('Keep the one it had'));
    await tester.pumpAndSettle();

    expect(find.byTooltip('Changed'), findsNothing);
  });

  testWidgets("one without its own says it's the calendar's", (tester) async {
    await open(
      tester,
      Event(
        id: 'e2',
        summary: 'Lunch',
        start: _sixInNewYork.toLocal(),
        end: _sixInNewYork.add(const Duration(hours: 1)).toLocal(),
      ),
    );

    expect(find.text("The calendar's time zone"), findsOneWidget);
  });

  testWidgets("a series' time zone changes for the events picked", (
    tester,
  ) async {
    (Map<String, Object?>, SeriesScope)? saved;
    final series = Recurrence(
      id: 's1',
      summary: 'Weekly call',
      start: _sixInNewYork.toLocal(),
      end: _sixInNewYork.add(const Duration(hours: 1)).toLocal(),
      properties: const {'time_zone': 'America/New_York'},
    );
    await tester.pumpWidget(
      PeopleScope(
        repository: InMemoryPeopleRepository(),
        child: MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () => showSeriesSummaryDialog(
                context,
                series,
                fromEventId: 's1_20261110',
                fromEventStart: _sixInNewYork.add(const Duration(days: 7)),
                save: (changes, scope) async {
                  saved = (changes, scope);
                  return [series];
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

    await pickLondon(tester);
    await tester.tap(find.textContaining('Keep the moment'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('This and following events'));
    await tester.pumpAndSettle();

    expect(saved?.$1, {'time_zone': 'Europe/London'});
    expect(saved?.$2, SeriesScope.following);
  });
}
