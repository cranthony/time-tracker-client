import 'package:flutter_test/flutter_test.dart';
import 'package:time_tracker_client/models/goal.dart';
import 'package:time_tracker_client/models/measure.dart';

void main() {
  test('describes each kind of measure at its cadence', () {
    expect(
      describeMeasure({'kind': 'duration', 'target_min': 600}, 'weekly'),
      '10h per week',
    );
    expect(
      describeMeasure({'kind': 'duration', 'target_min': 90}, 'daily'),
      '1h 30m per day',
    );
    expect(
      describeMeasure({
        'kind': 'count',
        'target': 1,
        'noun': 'dinners',
      }, 'weekly'),
      '1 dinner per week',
    );
    expect(
      describeMeasure({'kind': 'count', 'target': 3}, 'every_2_months'),
      '3 events per 2 months',
    );
    expect(
      describeMeasure({
        'kind': 'wake_time',
        'target': '07:00',
        'grace_min': 10,
      }, 'daily'),
      'Up by 07:00, daily',
    );
    expect(
      describeMeasure(
        {'kind': 'wake_time', 'target': '07:00', 'grace_min': 10},
        'daily',
        full: true,
      ),
      'Up by 07:00 (10 min grace), daily',
    );
    expect(
      describeMeasure({'kind': 'subjective', 'prompt': 'How was it?'}, null),
      'Your rating',
    );
    expect(
      describeMeasure(
        {'kind': 'subjective', 'prompt': 'How was it?'},
        'weekly',
        full: true,
      ),
      'Your rating, weekly\n“How was it?”',
    );
    expect(
      describeMeasure({'kind': 'llm', 'rubric': 'Kind?'}, 'monthly'),
      "Claude's judgement, monthly",
    );
    expect(
      describeMeasure({'kind': 'rollup', 'agg': 'mean'}, 'monthly'),
      'Average sub-goal rating, monthly',
    );
    expect(
      describeMeasure({'kind': 'rollup'}, 'monthly'),
      'Lowest sub-goal rating, monthly',
    );
  });

  test("names what's wrong with a measure, as the server would", () {
    expect(measureProblem({'kind': 'duration', 'target_min': 600}), isNull);
    expect(measureProblem({'kind': 'duration'}), contains('target time'));
    expect(
      measureProblem({'kind': 'duration', 'target_min': '10 hours'}),
      contains('target time'),
    );
    expect(measureProblem({'kind': 'count', 'target': 0}), contains('above 0'));
    expect(
      measureProblem({'kind': 'wake_time', 'target': '7am'}),
      contains('target time'),
    );
    expect(
      measureProblem({
        'kind': 'wake_time',
        'target': '07:00',
        'grace_min': 10,
        'zero_at_min': 5,
      }),
      contains('Zero at'),
    );
    expect(measureProblem({'kind': 'llm'}), contains('rate the period'));
    expect(measureProblem({'kind': 'subjective'}), isNull);
    expect(measureProblem({'kind': 'rollup', 'agg': 'mean'}), isNull);
    expect(measureProblem({'kind': 'hours'}), contains('kind'));
  });

  test('Goal.fromJson reads its measure', () {
    final goal = Goal.fromJson({
      'id': 'g',
      'measure': {'kind': 'count', 'target': 2},
    });
    expect(goal.measure, {'kind': 'count', 'target': 2});
    expect(Goal.fromJson({'id': 'g'}).measure, isNull);
  });
}
