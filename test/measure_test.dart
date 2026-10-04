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
        'kind': 'time_constraint',
        'edge': 'start',
        'target': '07:00',
        'grace_min': 10,
      }),
      'Starts by 07:00',
    );
    expect(
      describeMeasure({
        'kind': 'time_constraint',
        'edge': 'start',
        'target': '07:00',
        'grace_min': 10,
      }, full: true),
      'Starts by 07:00 (10 min grace)',
    );
    expect(
      describeMeasure(
        {
          'kind': 'time_constraint',
          'edge': 'end',
          'target': '17:30',
          'events_of': 'work',
        },
        goalNames: {'work': 'Work'},
      ),
      'Ends by 17:30, of Work',
    );
    expect(
      describeMeasure({
        'kind': 'time_constraint',
        'edge': 'start',
        'target': '08:00',
        'when': 'after',
      }),
      'Starts not before 08:00',
    );
    expect(
      describeMeasure(
        {
          'kind': 'duration',
          'target_min': 2400,
          'interval_days': 7,
          'events_of': 'work',
          'include_sub_goals': false,
        },
        goalNames: {'work': 'Work'},
      ),
      '40h per 7 days, of Work (not sub-goals)',
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
      measureProblem({
        'kind': 'time_constraint',
        'edge': 'start',
        'target': '7am',
      }),
      contains('target time'),
    );
    expect(
      measureProblem({'kind': 'time_constraint', 'target': '07:00'}),
      contains("first event's start"),
    );
    expect(
      measureProblem({
        'kind': 'time_constraint',
        'edge': 'end',
        'target': '07:00',
        'grace_min': 10,
        'zero_at_min': 5,
      }),
      contains('Zero at'),
    );
    expect(
      measureProblem({'kind': 'duration', 'target_min': 60, 'events_of': ''}),
      contains('Choose the goal'),
    );
    expect(
      measureProblem({'kind': 'wake_time', 'target': '07:00'}),
      contains('kind'),
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

  test('describeMeasureSettings lists what a measure sets', () {
    expect(
      describeMeasureSettings({
        'kind': 'duration',
        'target_min': 600,
        'interval_days': 7,
      }),
      [
        ('Target', '10h'),
        ('Over', '7 days'),
        ('Events of', 'This goal and its sub-goals'),
      ],
    );
    expect(
      describeMeasureSettings(
        {
          'kind': 'count',
          'target': 1,
          'noun': 'visits',
          'interval_days': 60,
          'zero_at_days': 90,
          'events_of': 'g',
          'include_sub_goals': false,
        },
        goalNames: {'g': 'Family'},
      ),
      [
        ('Target', '1 visit'),
        ('Over', '60 days'),
        ('Zero at', '90 days'),
        ('Events of', 'Family only'),
      ],
    );
    expect(
      describeMeasureSettings({
        'kind': 'time_constraint',
        'edge': 'end',
        'when': 'after',
        'target': '17:30',
        'grace_min': 10,
        'zero_at_min': 60,
      }),
      [
        ('When', 'Last event ends not before 17:30'),
        ('Grace', '10 min'),
        ('Zero at', '60 min off'),
        ('Events of', 'This goal and its sub-goals'),
      ],
    );
    expect(
      describeMeasureSettings({'kind': 'subjective', 'prompt': 'How was it?'}),
      [('Question', 'How was it?'), ('Asked', 'every day')],
    );
    expect(describeMeasureSettings({'kind': 'llm', 'rubric': 'Kind?'}), [
      ('Rubric', 'Kind?'),
    ]);
    expect(
      describeMeasureSettings(
        {
          'kind': 'rollup',
          'agg': 'weighted',
          'weights': {'a': 2},
        },
        goalNames: {'a': 'Tofu'},
      ),
      [('Combines', 'Weighted'), ('Tofu', 'weight 2')],
    );
    expect(
      describeMeasureSettings({
        'kind': 'rollup',
        'agg': 'percentile',
        'percentile': 50,
      }),
      [('Combines', 'Percentile'), ('Percentile', '50th')],
    );
  });

  test('a time window and only_if are described, checked and listed', () {
    const lunch = {
      'kind': 'time_window',
      'from': '11:30',
      'to': '13:30',
      'grace_min': 15,
      'zero_at_min': 60,
      'events_of': 'eat',
      'include_sub_goals': false,
    };
    const names = {'eat': 'Eat well', 'salsa': 'Practice salsa'};
    expect(
      describeMeasure(lunch, goalNames: names),
      'Between 11:30 and 13:30, of Eat well (not sub-goals)',
    );
    expect(
      describeMeasure(lunch, full: true, goalNames: names),
      'Between 11:30 and 13:30 (15 min grace), of Eat well (not sub-goals)',
    );
    expect(measureProblem(lunch), isNull);
    expect(describeMeasureSettings(lunch, goalNames: names), [
      ('Window', '11:30 to 13:30'),
      ('Grace', '15 min'),
      ('Zero at', '60 min off'),
      ('Events of', 'Eat well only'),
    ]);
    expect(
      measureProblem({'kind': 'time_window', 'from': '11:30'}),
      contains("window's start and end"),
    );
    expect(measureProblem({...lunch, 'zero_at_min': 10}), contains('Zero at'));

    // Any kind can be rated only on days with events.
    const practice = {
      'kind': 'subjective',
      'prompt': 'How did practice go?',
      'only_if': {'events_of': 'salsa'},
    };
    expect(
      describeMeasure(practice, full: true, goalNames: names),
      'Your rating, only on days with events of Practice salsa\n'
      '“How did practice go?”',
    );
    expect(describeMeasureSettings(practice, goalNames: names), [
      ('Question', 'How did practice go?'),
      ('Asked', 'every day'),
      ('Only on days with', 'events of Practice salsa'),
    ]);
    expect(measureProblem(practice), isNull);
    expect(
      describeMeasure({
        'kind': 'duration',
        'target_min': 30,
        'only_if': <String, Object?>{},
      }),
      '30m per day, only on days with its events',
    );
    expect(
      describeMeasure({
        'kind': 'llm',
        'rubric': 'r',
        'only_if': {'include_sub_goals': false},
      }),
      "Claude's judgement, only on days with its own events",
    );
    expect(
      measureProblem({
        'kind': 'llm',
        'rubric': 'r',
        'only_if': {'events_of': ''},
      }),
      contains('Choose the goal'),
    );
  });

  test('Goal.fromJson reads its measure', () {
    final goal = Goal.fromJson({
      'id': 'g',
      'measure': {'kind': 'count', 'target': 2},
    });
    expect(goal.measure, {'kind': 'count', 'target': 2});
    expect(Goal.fromJson({'id': 'g'}).measure, isNull);
  });

  test('a follow-through measure is described, checked and listed', () {
    const word = {'kind': 'follow_through'};
    const tuned = {
      'kind': 'follow_through',
      'penalty': 50,
      'recovery': 20,
      'look_back_days': 60,
      'events_of': 'promise',
    };
    const names = {'promise': 'Keep promises'};
    expect(describeMeasure(word), 'Follow-through');
    expect(
      describeMeasure(word, full: true),
      'Follow-through (−25 per cancellation, +25 per day kept, over 30 days)',
    );
    expect(
      describeMeasure(tuned, full: true, goalNames: names),
      'Follow-through (−50 per cancellation, +20 per day kept, over 60 days)'
      ', of Keep promises',
    );
    expect(describeMeasureSettings(word), [
      ('Per cancellation', '−25'),
      ('Per day kept', '+25'),
      ('Over', '30 days'),
      ('Events of', 'This goal and its sub-goals'),
    ]);
    expect(measureProblem(word), isNull);
    expect(measureProblem(tuned), isNull);
    expect(
      measureProblem({...word, 'penalty': 0}),
      contains('lost per cancellation'),
    );
    expect(
      measureProblem({...word, 'recovery': -1}),
      contains('won back per day'),
    );
    expect(
      measureProblem({...word, 'look_back_days': 7.5}),
      contains('whole number'),
    );
    expect(measureKinds, contains('follow_through'));
  });
}
