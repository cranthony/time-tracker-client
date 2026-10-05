import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:time_tracker_client/models/event.dart';
import 'package:time_tracker_client/models/goal.dart';
import 'package:time_tracker_client/widgets/color_picker.dart';
import 'package:time_tracker_client/widgets/day_timeline.dart';

void main() {
  final day = DateTime(2026, 9, 30);
  final dayEnd = DateTime(2026, 10, 1);
  DateTime at(int hour, [int minute = 0]) =>
      DateTime(2026, 9, 30, hour, minute);

  Event event(
    String summary,
    DateTime start,
    DateTime end, {
    int? priority,
    List<String> goals = const [],
    List<String>? names,
    bool cancelled = false,
  }) => Event(
    start: start,
    end: end,
    summary: summary,
    isCancelled: cancelled,
    properties: {
      'effective_priority': ?priority,
      'goal_ids': goals,
      'goal_names': ?names,
    },
  );

  group('placeEvents', () {
    List<TimelinePlacement> place(List<Event> events, {double min = 30}) =>
        placeEvents(
          events,
          day: day,
          dayEnd: dayEnd,
          scale: 1,
          minHeight: (_) => min,
        );

    test('puts each event at its times, at the scale', () {
      final [work] = place([event('Work', at(9), at(10))]);
      expect(work.trueTop, 12 + 9 * 60);
      expect(work.trueBottom, 12 + 10 * 60);
      expect((work.top, work.bottom), (work.trueTop, work.trueBottom));
      expect(work.compressed, isFalse);
      expect(work.displaced, isFalse);
    });

    test('draws an event too short for its text taller, and pushes the '
        'next one down, never moving one up', () {
      final [call, plants, lunch] = place([
        event('Lunch', at(14), at(15)),
        event('Call', at(13), at(13, 5)),
        event('Plants', at(13, 5), at(13, 10)),
      ]);
      expect(call.event.summary, 'Call');
      expect(call.compressed, isTrue);
      expect(call.displaced, isFalse);
      expect(call.bottom, call.top + 30);

      expect(plants.displaced, isTrue);
      expect(plants.top, call.bottom);
      expect(plants.compressed, isTrue);

      // There's room again by its start.
      expect(lunch.displaced, isFalse);
      expect(lunch.top, lunch.trueTop);
    });

    test('an event pushed down, but long enough, is drawn shorter than '
        'it lasts, ending where it ends', () {
      final [call, work] = place([
        event('Call', at(9), at(9, 5)),
        event('Work', at(9, 5), at(11)),
      ]);
      expect(call.compressed, isTrue);
      expect(call.shortened, isFalse);
      expect(work.displaced, isTrue);
      expect(work.shortened, isTrue);
      expect(work.compressed, isFalse);
      expect(work.bottom, work.trueBottom);
    });

    test('clips an event from the day before to midnight', () {
      final [sleep] = place([event('Sleep', DateTime(2026, 9, 29, 23), at(7))]);
      expect(sleep.trueTop, 12);
      expect(sleep.trueBottom, 12 + 7 * 60);
    });
  });

  group('priorityRuns', () {
    test("is the most important event's priority, clear where there's "
        'none, with no priority counting as 2', () {
      final runs = priorityRuns(
        [
          event('Work', at(9), at(12), priority: 1),
          event('Call', at(10), at(10, 30), priority: 0),
          event('Lunch', at(12), at(13)),
          event('Reading', at(13), at(14), priority: 2),
          event('Cancelled', at(15), at(16), priority: 0, cancelled: true),
          event('Walk', at(17), at(18), priority: 3),
        ],
        day: day,
        dayEnd: dayEnd,
      );
      expect(runs, [
        PriorityRun(at(9), at(10), 1),
        PriorityRun(at(10), at(10, 30), 0),
        PriorityRun(at(10, 30), at(12), 1),
        // Lunch and Reading, end to end, are one run.
        PriorityRun(at(12), at(14), 2),
        PriorityRun(at(17), at(18), 3),
      ]);
    });
  });

  test('placeLabels keeps the first of overlapping labels', () {
    final placed = placeLabels(
      [0.0, 100.0, 5.0, 50.0, 112.0, 120.0],
      top: (y) => y,
      height: 14,
    );
    expect(placed, [0.0, 100.0, 50.0, 120.0]);
  });

  group('eventColor', () {
    const goals = {
      'host': Goal(id: 'host', name: 'Host', effectiveColor: '#f4511e'),
      'plain': Goal(id: 'plain', name: 'Plain'),
    };

    test("is its primary goal's color", () {
      expect(
        eventColor(
          event('Dinner', at(18), at(20), goals: ['host'], priority: 1),
          goals,
        ),
        const Color(0xFFF4511E),
      );
    });

    test("is its priority's without a primary goal with a color", () {
      for (final ids in [
        <String>[],
        ['plain', 'host'],
        ['unknown'],
      ]) {
        expect(
          eventColor(event('E', at(1), at(2), goals: ids, priority: 1), goals),
          priorityColor(1),
        );
      }
      // With none, the default priority's.
      expect(eventColor(event('E', at(1), at(2)), goals), priorityColor(null));
    });
  });

  group('DayTimeline', () {
    Widget timeline(List<Event> events, {Map<String, Goal> goals = const {}}) =>
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: DayTimeline(events: events, day: day, goals: goals),
            ),
          ),
        );

    testWidgets("shows each event's summary, then its goals, primary first", (
      tester,
    ) async {
      await tester.pumpWidget(
        timeline(
          [
            event(
              'Dinner',
              at(0, 10),
              at(2),
              goals: ['host', 'tofu'],
              names: ['Host friends', 'Tofu tikka'],
            ),
          ],
          goals: {
            'host': const Goal(
              id: 'host',
              name: 'Host friends weekly',
              effectiveColor: '#f4511e',
            ),
          },
        ),
      );
      double top(String text) => tester.getTopLeft(find.text(text)).dy;
      // A listed goal by its name now; another by the event's.
      expect(top('Dinner'), lessThan(top('Host friends weekly')));
      expect(top('Host friends weekly'), lessThan(top('Tofu tikka')));
      // How long it is, and its priority: none, so the default.
      expect(find.text('1h 50m'), findsOneWidget);
      expect(find.text('P2'), findsOneWidget);
    });

    testWidgets('says how long an event too short for its text is', (
      tester,
    ) async {
      await tester.pumpWidget(
        timeline([
          event(
            'Call Mom',
            at(0, 10),
            at(0, 15),
            goals: ['a', 'b'],
            priority: 0,
          ),
        ]),
      );
      expect(find.text('Call Mom'), findsOneWidget);
      expect(find.text('5m'), findsOneWidget);
      expect(find.text('P0'), findsOneWidget);
    });

    testWidgets('a tap on an event says which', (tester) async {
      Event? tapped;
      final work = event('Work', at(0, 10), at(1));
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: DayTimeline(
                events: [work],
                day: day,
                onTap: (e) => tapped = e,
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Work'));
      expect(tapped, same(work));
    });
  });
}
