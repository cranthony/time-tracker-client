import 'package:flutter_test/flutter_test.dart';
import 'package:time_tracker_client/models/scoring.dart';

void main() {
  group('An aggregation', () {
    const items = [('a', 90), ('b', 90), ('c', 30), ('d', null)];

    test('is by default the mean of what has a score', () {
      expect(Aggregation.mean.combine(items), 70);
      expect(Aggregation.mean.combine(const [('a', null)]), isNull);
    });

    test('weighs each item by id, 1 unless it says; 0 leaves it out', () {
      expect(const Aggregation(weights: {'c': 2}).combine(items), 60);
      expect(const Aggregation(weights: {'c': 0}).combine(items), 90);
    });

    test('takes a percentile: the lowest score with that share of the '
        'weight at or below it', () {
      Aggregation p(num n) =>
          Aggregation(statistic: 'percentile', percentile: n);
      expect(p(0).combine(items), 30);
      expect(p(33).combine(items), 30);
      expect(p(34).combine(items), 90);
      expect(p(50).combine(items), 90);
      expect(p(100).combine(items), 90);
      // Weighed: c holds half the weight.
      expect(
        const Aggregation(
          statistic: 'percentile',
          percentile: 50,
          weights: {'c': 2},
        ).combine(items),
        30,
      );
    });

    test('counts only the best or worst few', () {
      expect(Aggregation.lowest.combine(items), 30);
      expect(const Aggregation(limit: 2, limitBy: 'worst').combine(items), 60);
      expect(const Aggregation(limit: 1, limitBy: 'best').combine(items), 90);
    });

    test('is capped while any is under a threshold', () {
      const capped = Aggregation(capBelow: (threshold: 40, cap: 50));
      expect(capped.combine(items), 50);
      expect(capped.combine(const [('a', 90), ('b', 80)]), 85);
    });

    test('counts one with nothing to rate it by as missing says', () {
      expect(const Aggregation(missing: 0).combine(items), 53);
    });

    test('round-trips as the server keeps it', () {
      const json = {
        'statistic': 'percentile',
        'percentile': 25,
        'weights': {'judgment': 2},
        'limit': 2,
        'limit_by': 'worst',
        'cap_below': {'threshold': 40, 'cap': 50},
        'missing': 0,
      };
      expect(Aggregation.fromJson(json)!.toJson(), json);
      expect(Aggregation.fromJson(const {})!.isMean, isTrue);
      expect(Aggregation.fromJson(null), isNull);
    });

    test('says how it combines', () {
      expect(Aggregation.mean.describe(), 'mean');
      expect(
        const Aggregation(
          statistic: 'percentile',
          percentile: 25,
          limit: 2,
          limitBy: 'worst',
          capBelow: (threshold: 40, cap: 50),
        ).describe(),
        '25th percentile of the worst 2, at most 50 with any under 40',
      );
    });

    test('is checked as the server checks it', () {
      expect(aggregationProblem(const {'statistic': 'percentile'}), isNotNull);
      expect(aggregationProblem(const {'limit': 2}), isNotNull);
      expect(
        aggregationProblem(
          const {
            'weights': {'gone': 1},
          },
          partIds: ['judgment'],
        ),
        "a weight names a part it doesn't have.",
      );
      expect(
        aggregationProblem(const {
          'missing': 'skip',
          'limit': 1,
          'limit_by': 'best',
        }),
        isNull,
      );
    });
  });

  group("A judgment part's scoring", () {
    final at = DateTime(2026, 10, 1);
    // 100 for an hour, 50 for 3 hours, 0 for an hour, oldest first.
    final judged = [
      (score: 100.0, minutes: 60, at: at),
      (score: 50.0, minutes: 180, at: at.add(const Duration(days: 1))),
      (score: 0.0, minutes: 60, at: at.add(const Duration(days: 2))),
    ];

    test('is by default the mean, each counting once', () {
      expect(JudgmentScoring.mean.combine(judged), 50);
    });

    test('weighs each by its time', () {
      expect(const JudgmentScoring(weightBy: 'duration').combine(judged), 50);
      expect(
        const JudgmentScoring(
          weightBy: 'duration',
          statistic: 'percentile',
          percentile: 25,
        ).combine(judged),
        50,
      );
    });

    test('counts only the best, worst or most recent events or hours', () {
      expect(
        const JudgmentScoring(limit: 1, limitBy: 'recent').combine(judged),
        0,
      );
      expect(
        const JudgmentScoring(limit: 2, limitBy: 'best').combine(judged),
        75,
      );
      // The best 2 hours: the hour at 100, then one of the three at 50.
      expect(
        const JudgmentScoring(
          weightBy: 'duration',
          limit: 2,
          limitBy: 'best',
        ).combine(judged),
        75,
      );
    });

    test('says how it combined them, its hours as a duration', () {
      expect(JudgmentScoring.mean.describe(1), 'Mean of 1 judgment');
      expect(
        const JudgmentScoring(
          weightBy: 'duration',
          statistic: 'percentile',
          percentile: 50,
          limit: 10.5,
          limitBy: 'best',
        ).describe(6),
        'Median of the best 10h 30m of 6 judgments, by time',
      );
      expect(
        const JudgmentScoring(limit: 5, limitBy: 'recent').summary(),
        'mean of the most recent 5',
      );
    });

    test('is checked as the server checks it', () {
      expect(
        judgmentScoringProblem(const {'limit': 2.5, 'limit_by': 'best'}),
        isNotNull,
      );
      expect(
        judgmentScoringProblem(const {
          'weight_by': 'duration',
          'limit': 2.5,
          'limit_by': 'best',
        }),
        isNull,
      );
    });
  });
}
