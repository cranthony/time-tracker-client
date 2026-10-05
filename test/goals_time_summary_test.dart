import 'package:flutter_test/flutter_test.dart';
import 'package:time_tracker_client/models/goal.dart';
import 'package:time_tracker_client/widgets/goals_time_summary.dart';
import 'package:time_tracker_client/widgets/time_summary.dart';

void main() {
  Goal goal(String id, int day, int week, {String? parent}) => Goal(
    id: id,
    parentId: parent,
    name: id,
    minutes24h: day,
    minutes7d: week,
  );

  /// Each share's label and minutes.
  Map<String, int> minutes(List<SummarySlice> slices) => {
    for (final slice in slices) slice.label: slice.time.inMinutes,
  };

  group('visibleGoalShares', () {
    final work = goal('work', 240, 1500);
    final cook = goal('cook', 120, 300);
    final tofu = goal('tofu', 90, 200, parent: 'cook');
    final curry = goal('curry', 20, 60, parent: 'cook');
    final pickle = goal('pickle', 10, 30, parent: 'curry');
    final wake = goal('wake', 60, 420);
    final byId = {
      for (final goal in [work, cook, tofu, curry, pickle, wake]) goal.id: goal,
    };

    Map<String, int> shares(List<Goal> visible, {int onGoals = 420}) => minutes(
      visibleGoalShares(
        visible,
        byId,
        {'active'},
        week: false,
        onGoals: onGoals,
      ),
    );

    test('a collapsed goal has its sub-goals\' time', () {
      expect(shares([work, cook, wake]), {
        'work': 240,
        'cook': 120,
        'wake': 60,
        'Not on goals': 1020,
      });
    });

    test('an expanded goal keeps only what its sub-goals shown '
        "don't have", () {
      expect(shares([work, cook, tofu, curry, wake]), {
        'work': 240,
        'tofu': 90,
        'wake': 60,
        '2 other goals': 30, // Curry's 20, and Cook's own 10.
        'Not on goals': 1020,
      });
    });

    test('a goal shown under a hidden one counts toward the nearest '
        'shown', () {
      // As when Curry's status is filtered out, but Pickle's isn't.
      expect(shares([cook, pickle], onGoals: 120), {
        'cook': 110,
        'pickle': 10,
        'Not on goals': 1320,
      });
    });

    test('scales down to the time on goals, each event once', () {
      expect(shares([work, cook, wake], onGoals: 210), {
        'work': 120,
        'cook': 60,
        'wake': 30,
        'Not on goals': 1230,
      });
    });
  });

  test('windowPriorityShares takes the server\'s split, the rest with no '
      'priority last', () {
    const split = [
      PriorityMinutes(priority: null, minutes24h: 465, minutes7d: 3820),
      PriorityMinutes(priority: 2, minutes24h: 225, minutes7d: 1100),
      PriorityMinutes(priority: 0, minutes24h: 0, minutes7d: 300),
      PriorityMinutes(priority: 1, minutes24h: 750, minutes7d: 4860),
    ];
    expect(minutes(windowPriorityShares(split, week: false)), {
      'P1': 750,
      'P2': 225,
      'No priority': 465,
    });
    expect(minutes(windowPriorityShares(split, week: true)), {
      'P0': 300,
      'P1': 4860,
      'P2': 1100,
      'No priority': 3820,
    });
  });

  test('GoalList reads the time by priority', () {
    final list = GoalList.fromJson({
      'goals': [],
      'minutes_by_priority': [
        {'priority': 1, 'minutes_24h': 60, 'minutes_7d': 420},
        {'priority': null, 'minutes_24h': 1380, 'minutes_7d': 9660},
      ],
    });
    expect(
      [
        for (final part in list.minutesByPriority!)
          (part.priority, part.minutes24h, part.minutes7d),
      ],
      [(1, 60, 420), (null, 1380, 9660)],
    );
    expect(GoalList.fromJson({'goals': []}).minutesByPriority, isNull);
  });
}
