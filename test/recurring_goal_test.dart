import 'package:flutter_test/flutter_test.dart';
import 'package:time_tracker_client/models/event.dart';
import 'package:time_tracker_client/models/goal.dart';
import 'package:time_tracker_client/models/habit.dart';
import 'package:time_tracker_client/models/note.dart';
import 'package:time_tracker_client/models/person.dart';
import 'package:time_tracker_client/models/recurring_goal.dart';
import 'package:time_tracker_client/models/trait.dart';
import 'package:time_tracker_client/models/trait_scores.dart';

const _weekly = RecurringGoal(period: 'week', ratePeriods: 4);

/// Habit h1's goal for the week starting [start], [status] -- done or
/// missed at [closed].
Goal _goal(String start, String status, [DateTime? closed]) => Goal(
  id: 'h1_$start',
  title: 'Call Mom',
  habitId: 'h1',
  status: status,
  history: [
    StatusChange('active', DateTime.parse(start)),
    if (closed != null) StatusChange(status, closed),
  ],
);

void main() {
  test('a period follows the calendar: weeks from Sunday', () {
    // 2026-10-28 is a Wednesday.
    expect(periodOf(DateTime(2026, 10, 28, 15), 'week'), (
      DateTime(2026, 10, 25),
      DateTime(2026, 11, 1),
    ));
    expect(periodOf(DateTime(2026, 10, 25), 'week').$1, DateTime(2026, 10, 25));
    expect(periodOf(DateTime(2026, 12, 9), 'month'), (
      DateTime(2026, 12),
      DateTime(2027, 1),
    ));
    expect(periodOf(DateTime(2026, 12, 9, 8), 'day'), (
      DateTime(2026, 12, 9),
      DateTime(2026, 12, 10),
    ));
  });

  test("a habit's goal's id names it, and no other goal's does", () {
    expect(habitOfGoalId('h1_2026-11-01'), 'h1');
    expect(habitOfGoalId('h1-2026-11-01'), isNull);
    expect(habitOfGoalId('plain'), isNull);
    expect(habitOfGoalId('_2026-11-01'), isNull);
  });

  test('a recurring goal\'s habit is read and sent with no action', () {
    final habit = Habit.fromJson({
      'id': 'h1',
      'name': 'Call Mom',
      'recurring_goal': {'period': 'week', 'rate_periods': 4},
      'traits': {'select': <String>[]},
      'status': 'active',
    });
    expect(habit.isGoal, isTrue);
    expect(habit.recurringGoal!.ratedPeriods, 4);
    expect(habit.toJson(), {
      'id': 'h1',
      'name': 'Call Mom',
      'recurring_goal': {'period': 'week', 'rate_periods': 4},
      'status': 'active',
      'traits': {'select': <String>[]},
    });
    expect(const RecurringGoal().ratedPeriods, defaultRatePeriods);
    final goal = Goal.fromJson({'id': 'h1_2026-10-25', 'habit_id': 'h1'});
    expect(goal.habitId, 'h1');
    expect(goalWire(goal.toJson()).containsKey('habit_id'), isFalse);
  });

  test('the goal rate counts the periods before this one with a goal done '
      'in them, back to its first', () {
    final goals = [
      _goal('2026-10-04', 'done', DateTime(2026, 10, 6, 18)),
      // Missed, then done in its second week: that week counts.
      Goal(
        id: 'h1_2026-10-11',
        title: 'Call Mom',
        habitId: 'h1',
        status: 'done',
        history: [
          StatusChange('active', DateTime(2026, 10, 11)),
          StatusChange('missed', DateTime(2026, 10, 18)),
          StatusChange('active', DateTime(2026, 10, 18)),
          StatusChange('done', DateTime(2026, 10, 20, 9)),
        ],
      ),
      _goal('2026-10-25', 'active'),
    ];

    // Wednesday 28th: the weeks of the 4th, 11th and 18th are over.
    final rate = goalRate('h1', _weekly, goals, DateTime(2026, 10, 29));
    expect((rate.done, rate.counted, rate.score), (2, 3, 67));
    expect(rate.said, '2 of 3 weeks done');
    // Counted back no further than its rate periods.
    final later = goalRate('h1', _weekly, goals, DateTime(2026, 11, 12));
    expect((later.done, later.counted), (1, 4));
    // None over yet.
    final first = goalRate('h1', _weekly, [
      _goal('2026-10-25', 'active'),
    ], DateTime(2026, 10, 29));
    expect((first.counted, first.score), (0, null));
  });

  test("a recurring goal's habit is scored by its goal rate, and judged on "
      'the events tagged with its goals', () {
    const habit = Habit(
      id: 'h1',
      name: 'Call Mom',
      actionId: '',
      recurringGoal: _weekly,
      traits: PersonTraits(select: []),
    );
    final start = DateTime(2026, 10, 27, 12);
    Event event(String id, String goalId) => Event.fromJson({
      'id': id,
      'summary': id,
      'start': localIsoTimestamp(start),
      'end': localIsoTimestamp(start.add(const Duration(hours: 1))),
      'goals': [
        {'goal_id': goalId},
      ],
    });
    final scores = TraitScores.compute(
      traits: const [
        Trait(
          id: 'kind',
          name: 'Kind',
          parts: [
            {'kind': 'count', 'target': 1},
          ],
        ),
      ],
      people: const [],
      habits: const [habit],
      goals: [
        _goal('2026-10-11', 'done', DateTime(2026, 10, 12, 9)),
        _goal('2026-10-18', 'missed', DateTime(2026, 10, 25)),
        _goal('2026-10-25', 'active'),
      ],
      events: [event('mine', 'h1_2026-10-25'), event('other', 'plain')],
      today: DateTime(2026, 10, 29),
      days: 1,
    );

    final rating = scores.rating(habit.subject)!;
    expect(rating.rating, 50);
    expect([for (final t in rating.traits) t.traitId], [goalRateId]);
    expect(rating.traits.single.parts.single.said, '1 of 2 weeks done');
    expect(
      [for (final e in scores.digest(habit.subject).events) e['id']],
      ['mine'],
    );
  });
}
