import 'package:flutter_test/flutter_test.dart';
import 'package:time_tracker_client/models/goal.dart';
import 'package:time_tracker_client/models/measure.dart';

void main() {
  test('describes each kind of measure', () {
    expect(
      describeMeasure({'kind': 'duration', 'target_min': 90}),
      '1h 30m per day',
    );
    expect(
      describeMeasure({
        'kind': 'duration',
        'target_min': 600,
        'interval_days': 7,
      }),
      '10h per 7 days',
    );
    expect(
      describeMeasure({'kind': 'count', 'target': 1, 'noun': 'dinners'}),
      '1 dinner per day',
    );
    expect(
      describeMeasure({
        'kind': 'count',
        'target': 1,
        'noun': 'visits',
        'interval_days': 60,
        'zero_at_days': 90,
      }),
      '1 visit per 60 days, 0 at 90 days',
    );
    expect(
      describeMeasure({
        'kind': 'wake_time',
        'target': '07:00',
        'grace_min': 10,
      }),
      'Up by 07:00',
    );
    expect(
      describeMeasure({
        'kind': 'wake_time',
        'target': '07:00',
        'grace_min': 10,
      }, full: true),
      'Up by 07:00 (10 min grace)',
    );
    expect(
      describeMeasure({'kind': 'subjective', 'prompt': 'How was it?'}),
      'Your rating',
    );
    expect(
      describeMeasure({
        'kind': 'subjective',
        'prompt': 'How was it?',
        'interval_days': 7,
      }, full: true),
      'Your rating, asked every 7 days\n“How was it?”',
    );
    expect(
      describeMeasure({'kind': 'llm', 'rubric': 'Kind?'}),
      "Claude's judgement",
    );
    expect(describeMeasure({'kind': 'rollup'}), 'Average sub-goal rating');
    expect(
      describeMeasure({
        'kind': 'rollup',
        'agg': 'weighted',
        'weights': {'a': 1},
      }),
      'Weighted average of sub-goals',
    );
    expect(
      describeMeasure({'kind': 'rollup', 'agg': 'percentile', 'percentile': 0}),
      'Lowest sub-goal rating',
    );
    expect(
      describeMeasure({
        'kind': 'rollup',
        'agg': 'percentile',
        'percentile': 100,
      }),
      'Highest sub-goal rating',
    );
    expect(
      describeMeasure({
        'kind': 'rollup',
        'agg': 'percentile',
        'percentile': 50,
      }),
      '50th percentile of sub-goals',
    );
    // From before percentiles.
    expect(
      describeMeasure({'kind': 'rollup', 'agg': 'min'}),
      'Lowest sub-goal rating',
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
      measureProblem({'kind': 'count', 'target': 1, 'interval_days': 0}),
      contains('look back'),
    );
    expect(
      measureProblem({
        'kind': 'count',
        'target': 1,
        'interval_days': 60,
        'zero_at_days': 60,
      }),
      contains('Zero at'),
    );
    expect(
      measureProblem({
        'kind': 'count',
        'target': 1,
        'interval_days': 60,
        'zero_at_days': 90,
      }),
      isNull,
    );
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
    expect(measureProblem({'kind': 'llm'}), contains('rate the day'));
    expect(measureProblem({'kind': 'subjective'}), contains('question'));
    expect(
      measureProblem({'kind': 'subjective', 'prompt': '?', 'interval_days': 7}),
      isNull,
    );
    expect(measureProblem({'kind': 'rollup', 'agg': 'mean'}), isNull);
    expect(
      measureProblem({'kind': 'rollup', 'agg': 'weighted'}),
      contains('weight'),
    );
    expect(
      measureProblem({
        'kind': 'rollup',
        'agg': 'weighted',
        'weights': {'a': 2},
      }),
      isNull,
    );
    expect(
      measureProblem({
        'kind': 'rollup',
        'agg': 'percentile',
        'percentile': 120,
      }),
      contains('percentile'),
    );
    expect(measureProblem({'kind': 'rollup', 'agg': 'max'}), contains('Pick'));
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
