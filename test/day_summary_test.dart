import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:time_tracker_client/models/event.dart';
import 'package:time_tracker_client/models/goal.dart';
import 'package:time_tracker_client/widgets/day_summary.dart';
import 'package:time_tracker_client/widgets/time_summary.dart';

void main() {
  final day = DateTime(2026, 9, 30);
  DateTime at(int hour, [int minute = 0]) =>
      DateTime(2026, 9, 30, hour, minute);

  Event event(
    DateTime start,
    DateTime end, {
    int? priority,
    List<String> goals = const [],
    bool cancelled = false,
  }) => Event(
    start: start,
    end: end,
    isCancelled: cancelled,
    properties: {'effective_priority': ?priority, 'action_ids': goals},
  );

  /// Each share's label and hours.
  Map<String, double> hours(List<SummarySlice> slices) => {
    for (final slice in slices) slice.label: slice.time.inMinutes / 60,
  };

  group('priorityShares', () {
    test('splits the day by priority, then what is unscheduled', () {
      final slices = priorityShares([
        event(at(9), at(12), priority: 1),
        event(at(13), at(14), priority: 0),
        // None counts as the default, P2.
        event(at(14), at(16)),
        event(at(18), at(19), priority: 2),
      ], day);
      expect(hours(slices), {'P0': 1, 'P1': 3, 'P2': 3, 'Unscheduled': 17});
      expect(slices.last.color, isNull);
    });

    test('counts only the part of an event on the day', () {
      final slices = priorityShares([
        event(at(22, 0).subtract(const Duration(days: 1)), at(6), priority: 3),
        event(at(23), at(2).add(const Duration(days: 1)), priority: 3),
      ], day);
      expect(hours(slices), {'P3': 7, 'Unscheduled': 17});
    });

    test('shares overlapping time, so it adds up to the day', () {
      final slices = priorityShares([
        event(at(9), at(11), priority: 1),
        event(at(10), at(12), priority: 2),
      ], day);
      expect(hours(slices), {'P1': 1.5, 'P2': 1.5, 'Unscheduled': 21});
    });

    test('leaves out cancelled events', () {
      final slices = priorityShares([
        event(at(9), at(10), priority: 1, cancelled: true),
      ], day);
      expect(hours(slices), {'Unscheduled': 24});
    });
  });

  group('goalShares', () {
    final goals = {
      for (final goal in [
        const Goal(id: 'cook', name: 'Cook', effectiveColor: '#33b679'),
        const Goal(id: 'tofu', parentId: 'cook', name: 'Tofu'),
        const Goal(id: 'curry', parentId: 'cook', name: 'Curry'),
        const Goal(id: 'work', name: 'Work'),
        const Goal(id: 'run', name: 'Run'),
        const Goal(id: 'read', name: 'Read'),
        const Goal(id: 'top', name: 'Top'),
      ])
        goal.id!: goal,
    };
    final events = [
      event(at(8), at(12), goals: ['work']),
      event(at(12), at(14), goals: ['tofu', 'curry']),
      event(at(14), at(15), goals: ['tofu']),
      event(at(15), at(16), goals: ['run']),
      event(at(16), at(16, 30), goals: ['read']),
      event(at(16, 30), at(18), goals: ['top']),
      event(at(18), at(20)),
    ];

    test('the top goals, the rest, no goal, then unscheduled', () {
      expect(hours(goalShares(events, day, goals)), {
        'Work': 4,
        'Tofu': 2,
        'Top': 1.5,
        '3 other actions': 2.5,
        'No goal': 2,
        'Unscheduled': 12,
      });
    });

    test("top-level goals count their sub-goals' time once", () {
      final slices = goalShares(events, day, goals, topLevel: true);
      expect(hours(slices), {
        'Work': 4,
        'Cook': 3,
        'Top': 1.5,
        '2 other actions': 1.5,
        'No goal': 2,
        'Unscheduled': 12,
      });
      expect(slices[1].color, const Color(0xFF33B679));
    });
  });

  testWidgets(
    'a tap anywhere on its toggle turns percentages into durations and back',
    (tester) async {
      var durations = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) => DaySummary(
                events: [
                  event(at(9), at(10, 30), priority: 1),
                  // A third of a minute each: rounded to whole minutes.
                  event(at(11), at(11, 1), priority: 2),
                  event(at(11), at(11, 1), priority: 2),
                  event(at(11), at(11, 1), priority: 3),
                ],
                day: day,
                goals: const {},
                durations: durations,
                onDurations: (value) => setState(() => durations = value),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('6%'), findsOneWidget);
      expect(find.text('1h 30m'), findsNothing);

      await tester.tap(find.byTooltip('Show durations'));
      await tester.pumpAndSettle();
      expect(durations, isTrue);
      expect(find.text('1h 30m'), findsOneWidget);
      expect(find.text('1m'), findsOneWidget);
      expect(find.text('0m'), findsOneWidget);
      expect(find.text('22h 29m'), findsOneWidget);
      expect(find.text('6%'), findsNothing);

      await tester.tap(find.byTooltip('Show percentages'));
      await tester.pumpAndSettle();
      expect(find.text('6%'), findsOneWidget);

      // Either half turns it, even the one already shown.
      await tester.tap(find.byIcon(Icons.percent));
      await tester.pumpAndSettle();
      expect(durations, isTrue);
      await tester.tap(find.byIcon(Icons.percent));
      await tester.pumpAndSettle();
      expect(durations, isFalse);
    },
  );

  testWidgets('its header fits a narrow screen, titles shrunk to fit', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 300,
              child: DaySummary(
                events: const [],
                day: day,
                goals: const {},
                onCollapsed: (_) {},
                onDurations: (_) {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    // An overflow would have thrown.
    expect(tester.takeException(), isNull);
    expect(
      tester.getTopRight(find.byTooltip('Hide summary')).dx,
      lessThanOrEqualTo(tester.getTopRight(find.byType(DaySummary)).dx),
    );
  });
}
