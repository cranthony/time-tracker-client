import 'package:flutter_test/flutter_test.dart';
import 'package:time_tracker_client/models/goal.dart';
import 'package:time_tracker_client/widgets/day_summary.dart';
import 'package:time_tracker_client/widgets/goals_time_summary.dart';

void main() {
  Goal goal(
    String id,
    int day,
    int week, {
    String? parent,
    int? priority,
    String status = 'active',
  }) => Goal(
    id: id,
    parentId: parent,
    name: id,
    status: status,
    effectivePriority: priority,
    minutes24h: day,
    minutes7d: week,
  );

  /// Each share's label and minutes.
  Map<String, int> minutes(List<SummarySlice> slices) => {
    for (final slice in slices) slice.label: slice.time.inMinutes,
  };

  final goals = [
    goal(overallGoalId, 420, 2610),
    goal('work', 240, 1500, priority: 1),
    goal('cook', 120, 270, priority: 2),
    goal('tofu', 120, 200, parent: 'cook'),
    goal('wake', 60, 420, priority: 0),
    goal('host', 0, 150),
    goal('top', 0, 260, parent: overallGoalId, priority: 3),
  ];

  group('topLevelShares', () {
    test('the top goals, the rest, then the rest of the window', () {
      expect(
        minutes(topLevelShares(goals, {'active'}, week: false, onGoals: 420)),
        {'work': 240, 'cook': 120, 'wake': 60, 'Not on goals': 1020},
      );
      expect(
        minutes(topLevelShares(goals, {'active'}, week: true, onGoals: 2610)),
        {
          'work': 1500,
          'wake': 420,
          // Under the overall goal: top-level.
          'cook': 270,
          '2 other goals': 410,
          'Not on goals': 7470,
        },
      );
    });

    test('scales down to the time on goals, each event once', () {
      expect(
        minutes(topLevelShares(goals, {'active'}, week: false, onGoals: 210)),
        {'work': 120, 'cook': 60, 'wake': 30, 'Not on goals': 1230},
      );
    });
  });

  test("goalPriorityShares counts each goal's own time toward its "
      'priority', () {
    // Tofu's 200 minutes count as its own priority's, the default; Cook
    // has 70 of its own.
    expect(
      minutes(goalPriorityShares(goals, {'active'}, week: true, onGoals: 2610)),
      {
        'P0 goals': 420,
        'P1 goals': 1500,
        'P2 goals': 270 + 150,
        'P3 goals': 260,
        'Not on goals': 7470,
      },
    );
  });
}
