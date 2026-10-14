/// How scores combine, as the server keeps it (its stores/scoring.rs) and
/// the app works out: a judgment part's judgments into its score
/// ([JudgmentScoring]), and -- as an [Aggregation] -- a trait's parts
/// into its score, a person's or habit's traits into theirs, a circle's
/// people into its own, and each layer of the habit graph. Where nothing
/// sets one, the [ScoringDefaults] do; failing those, the plain mean
/// (a habit layer's lowest score).
library;

import '../widgets/durations.dart' show formatMinutes;

/// The statistics a score can be: the weighted mean, or a percentile.
const scoringStatistics = {'mean': 'Mean', 'percentile': 'Percentile'};

/// Which scores an aggregation's limit keeps.
const aggregationLimitBy = {'best': 'Best', 'worst': 'Worst'};

/// Which judgments a judgment part's limit keeps.
const judgmentLimitBy = {
  'best': 'Best',
  'worst': 'Worst',
  'recent': 'Most recent',
};

/// What a judgment counts for, in a judgment part's score.
const judgmentWeightBy = {'event': 'Each event', 'duration': 'Its time'};

/// [items], each a score and its weight, as [statistic] says: the weighted
/// mean, or -- with [percentile], from 0 to 100 -- the lowest score with
/// at least that share of the weight at or below it, 0 being the lowest
/// and 100 the highest. Items weighing nothing are left out; null if
/// none is left.
double? weightedStatistic(
  List<(num score, num weight)> items,
  String statistic, [
  num? percentile,
]) {
  final weighed = [
    for (final item in items)
      if (item.$2 > 0) item,
  ];
  final total = weighed.fold<num>(0, (sum, i) => sum + i.$2);
  if (weighed.isEmpty || total <= 0) return null;
  if (statistic != 'percentile') {
    return weighed.fold<num>(0, (sum, i) => sum + i.$1 * i.$2) / total;
  }
  weighed.sort((a, b) => a.$1.compareTo(b.$1));
  final target = total * (percentile ?? 50).clamp(0, 100) / 100;
  num reached = 0;
  for (final (score, weight) in weighed) {
    reached += weight;
    // A hair under, for sums that don't come out exact.
    if (reached >= target - 1e-9) return score.toDouble();
  }
  return weighed.last.$1.toDouble();
}

/// A cap on a combined score: with any score under [threshold], it's at
/// most [cap].
typedef CapBelow = ({num threshold, num cap});

/// How scores combine into one -- a trait's parts', a person's or
/// habit's traits', a circle's people's -- each item by its id.
class Aggregation {
  const Aggregation({
    this.statistic = 'mean',
    this.percentile,
    this.weights = const {},
    this.limit,
    this.limitBy,
    this.capBelow,
    this.missing,
  });

  /// The plain mean, of what has a score.
  static const mean = Aggregation();

  /// The lowest score.
  static const lowest = Aggregation(limit: 1, limitBy: 'worst');

  /// One of [scoringStatistics]' keys.
  final String statistic;

  /// For a percentile, which: 0 to 100.
  final num? percentile;

  /// Each item's weight, by id; 1 for one not here.
  final Map<String, num> weights;

  /// Only the [limit] best or worst scores ([limitBy]) count.
  final int? limit;
  final String? limitBy;
  final CapBelow? capBelow;

  /// The score of an item with nothing to rate it by; null leaves it out.
  final num? missing;

  /// Whether it's as without one: the plain mean.
  bool get isMean =>
      statistic == 'mean' &&
      weights.isEmpty &&
      limit == null &&
      capBelow == null &&
      missing == null;

  num weightOf(String id) => weights[id] ?? 1;

  /// [json], as far as it's well formed; null for none.
  static Aggregation? fromJson(Object? json) {
    if (json is! Map) return null;
    return Aggregation(
      statistic: json['statistic'] == 'percentile' ? 'percentile' : 'mean',
      percentile: _num(json['percentile']),
      weights: {
        if (json['weights'] case final Map weights)
          for (final MapEntry(:key, :value) in weights.entries)
            if (value is num) '$key': value,
      },
      limit: _num(json['limit'])?.round(),
      limitBy: switch (json['limit_by']) {
        final String by when aggregationLimitBy.containsKey(by) => by,
        _ => null,
      },
      capBelow: switch (json['cap_below']) {
        {'threshold': final num threshold, 'cap': final num cap} => (
          threshold: threshold,
          cap: cap,
        ),
        _ => null,
      },
      missing: _num(json['missing']),
    );
  }

  /// As the server keeps it.
  Map<String, Object?> toJson() => {
    if (statistic != 'mean') 'statistic': statistic,
    if (statistic == 'percentile') 'percentile': percentile ?? 50,
    if (weights.isNotEmpty) 'weights': weights,
    if (limit != null) ...{'limit': limit, 'limit_by': limitBy ?? 'worst'},
    if (capBelow case final cap?)
      'cap_below': {'threshold': cap.threshold, 'cap': cap.cap},
    'missing': ?missing,
  };

  /// [items], each an id and its score (null with nothing to rate it by),
  /// combined: those with nothing are left out, or count as [missing];
  /// then those weighing nothing are; then only the [limit] best or worst
  /// count; then the [statistic] of them, weighted; then, with any of
  /// them under [capBelow]'s threshold, it's at most its cap. Null if
  /// nothing's left to combine.
  int? combine(Iterable<(String id, int? score)> items) {
    final scored = [
      for (final (id, score) in items)
        if ((score ?? missing) case final s?)
          if (weightOf(id) > 0) (score: s, weight: weightOf(id)),
    ];
    if (scored.isEmpty) return null;
    var kept = scored;
    if (limit case final n?) {
      final worst = limitBy != 'best';
      kept = [...scored]
        ..sort(
          (a, b) =>
              worst ? a.score.compareTo(b.score) : b.score.compareTo(a.score),
        );
      kept = kept.take(n < 1 ? 1 : n).toList();
    }
    final value = weightedStatistic(
      [for (final s in kept) (s.score, s.weight)],
      statistic,
      percentile,
    );
    if (value == null) return null;
    var result = value;
    if (capBelow case final cap?
        when scored.any((s) => s.score < cap.threshold)) {
      result = result > cap.cap ? cap.cap.toDouble() : result;
    }
    return result.round();
  }

  /// How it combines, in a phrase: "mean", "25th percentile of the worst
  /// 2, at most 50 with any under 40".
  String describe() => [
    _statisticPhrase(statistic, percentile) +
        switch (limit) {
          final n? => ' of the ${limitBy == 'best' ? 'best' : 'worst'} $n',
          null => '',
        },
    if (weights.isNotEmpty) 'weighted',
    if (missing case final m?) '${_g(m)} for any not rated',
    if (capBelow case final cap?)
      'at most ${_g(cap.cap)} with any under ${_g(cap.threshold)}',
  ].join(', ');
}

/// How a judgment part's judgments combine into its score: each counting
/// once, or for its event's time ([weightBy]); their mean, or a
/// percentile; and only the best, worst or most recent [limit] events --
/// or hours, by time.
class JudgmentScoring {
  const JudgmentScoring({
    this.weightBy = 'event',
    this.statistic = 'mean',
    this.percentile,
    this.limit,
    this.limitBy,
  });

  /// The mean, each judgment counting once.
  static const mean = JudgmentScoring();

  /// One of [judgmentWeightBy]'s keys.
  final String weightBy;

  /// One of [scoringStatistics]' keys.
  final String statistic;
  final num? percentile;

  /// How many events count -- or, by time, hours.
  final num? limit;

  /// One of [judgmentLimitBy]'s keys.
  final String? limitBy;

  bool get byDuration => weightBy == 'duration';

  bool get isMean => !byDuration && statistic == 'mean' && limit == null;

  static JudgmentScoring? fromJson(Object? json) {
    if (json is! Map) return null;
    return JudgmentScoring(
      weightBy: json['weight_by'] == 'duration' ? 'duration' : 'event',
      statistic: json['statistic'] == 'percentile' ? 'percentile' : 'mean',
      percentile: _num(json['percentile']),
      limit: _num(json['limit']),
      limitBy: switch (json['limit_by']) {
        final String by when judgmentLimitBy.containsKey(by) => by,
        _ => null,
      },
    );
  }

  Map<String, Object?> toJson() => {
    if (byDuration) 'weight_by': 'duration',
    if (statistic != 'mean') 'statistic': statistic,
    if (statistic == 'percentile') 'percentile': percentile ?? 50,
    if (limit != null) ...{'limit': limit, 'limit_by': limitBy ?? 'recent'},
  };

  /// [judged] -- each a score from 0 to 100, its event's time in minutes,
  /// and when it started -- combined, as a score from 0 to 100; null if
  /// none counts (by time, none took any).
  double? combine(List<({double score, num minutes, DateTime at})> judged) {
    var kept = judged;
    if (limit case final n?) {
      kept = [...judged]
        ..sort(
          (a, b) => switch (limitBy) {
            'best' => b.score.compareTo(a.score),
            'worst' => a.score.compareTo(b.score),
            _ => b.at.compareTo(a.at),
          },
        );
      if (byDuration) {
        // Hours: the last one in cut short to fit.
        var left = n * 60;
        kept = [
          for (final j in kept)
            if (left > 0)
              () {
                final minutes = j.minutes < left ? j.minutes : left;
                left -= minutes;
                return (score: j.score, minutes: minutes, at: j.at);
              }(),
        ];
      } else {
        kept = kept.take(n.round() < 1 ? 1 : n.round()).toList();
      }
    }
    return weightedStatistic(
      [for (final j in kept) (j.score, byDuration ? j.minutes : 1)],
      statistic,
      percentile,
    );
  }

  /// Which judgments count, in a phrase: "the best 10h", "the most
  /// recent 5"; empty without a limit.
  String get _which => switch (limit) {
    final n? =>
      'the ${switch (limitBy) {
        'best' => 'best',
        'worst' => 'worst',
        _ => 'most recent',
      }} ${byDuration ? formatMinutes(n * 60) : _g(n)}',
    null => '',
  };

  /// How it combines judgments, in a phrase: "mean", "median of the best
  /// 10h, by time".
  String summary() => [
    _statisticPhrase(statistic, percentile),
    if (limit != null) ' of $_which',
    if (byDuration) ', by time',
  ].join();

  /// How it combines [count] judgments, in a phrase: "Mean of 4
  /// judgments", "25th percentile of the best 10h of 6 judgments, by
  /// time".
  String describe(int count) {
    final noun = '$count judgment${count == 1 ? '' : 's'}';
    final statistic = _statisticPhrase(this.statistic, percentile);
    return '${statistic[0].toUpperCase()}${statistic.substring(1)} of '
        '${limit == null ? '' : '$_which of '}$noun'
        '${byDuration ? ', by time' : ''}';
  }
}

/// The defaults, where nothing sets its own (see `get_scoring_defaults`).
class ScoringDefaults {
  const ScoringDefaults({this.traits, this.circles, this.habitLayers});

  /// How a person's or habit's traits combine, by trait id.
  final Aggregation? traits;

  /// How a circle's people combine, by person id.
  final Aggregation? circles;

  /// How the habits and people in each layer of the habit graph combine:
  /// habits by `habit:<id>`, people by id.
  final Aggregation? habitLayers;

  factory ScoringDefaults.fromJson(Object? json) => json is Map
      ? ScoringDefaults(
          traits: Aggregation.fromJson(json['traits']),
          circles: Aggregation.fromJson(json['circles']),
          habitLayers: Aggregation.fromJson(json['habit_layers']),
        )
      : const ScoringDefaults();

  Map<String, Object?> toJson() => {
    'traits': traits?.toJson(),
    'circles': circles?.toJson(),
    'habit_layers': habitLayers?.toJson(),
  };
}

String _statisticPhrase(String statistic, num? percentile) {
  if (statistic != 'percentile') return 'mean';
  final p = (percentile ?? 50).round();
  return switch (p) {
    0 => 'lowest',
    100 => 'highest',
    50 => 'median',
    _ => '${_ordinal(p)} percentile',
  };
}

String _ordinal(int n) {
  if (n % 100 >= 11 && n % 100 <= 13) return '${n}th';
  return '$n${switch (n % 10) {
    1 => 'st',
    2 => 'nd',
    3 => 'rd',
    _ => 'th',
  }}';
}

num? _num(Object? value) => value is num ? value : null;

String _g(num n) => n == n.roundToDouble() ? '${n.round()}' : '$n';

/// The first of [json]'s fields not among [fields], if any.
String? _extraField(Map json, Set<String> fields) {
  for (final key in json.keys) {
    if (!fields.contains(key)) return '$key';
  }
  return null;
}

bool _isScore(Object? v) => v is num && v >= 0 && v <= 100;

String? _statisticProblem(Map json) {
  final statistic = json['statistic'];
  if (statistic != null && !scoringStatistics.containsKey(statistic)) {
    return 'pick the mean or a percentile.';
  }
  final percentile = json['percentile'];
  if (statistic == 'percentile' && !_isScore(percentile)) {
    return 'the percentile must be from 0 to 100.';
  }
  if (statistic != 'percentile' && percentile != null) {
    return 'a percentile is only for the percentile statistic.';
  }
  return null;
}

String? _limitProblem(Map json, Map<String, String> by, {required bool whole}) {
  final limit = json['limit'];
  final limitBy = json['limit_by'];
  if (limit == null) {
    return limitBy == null ? null : 'which to keep is only for a limit.';
  }
  if (limit is! num || limit <= 0 || (whole && limit != limit.round())) {
    return whole
        ? 'the limit must be a whole number, 1 or more.'
        : 'the limit must be above 0.';
  }
  if (!by.containsKey(limitBy)) return 'say which to keep within the limit.';
  return null;
}

/// What's wrong with an aggregation as [json], in a sentence, or null if
/// it's fine: the checks the server's `aggregation_problems` makes. Its
/// weights are checked against [partIds] when given.
String? aggregationProblem(Object? json, {List<String>? partIds}) {
  if (json is! Map) return 'it must be an object.';
  const fields = {
    'statistic',
    'percentile',
    'weights',
    'limit',
    'limit_by',
    'cap_below',
    'missing',
  };
  if (_extraField(json, fields) case final extra?) {
    return "it has a field the app doesn't know: $extra.";
  }
  if (_statisticProblem(json) case final problem?) return problem;
  if (json['weights'] case final weights?) {
    if (weights is! Map) return 'its weights must be by id.';
    for (final MapEntry(:key, :value) in weights.entries) {
      if (value is! num || value < 0) return 'each weight must be 0 or more.';
      if (partIds != null && !partIds.contains(key)) {
        return "a weight names a part it doesn't have.";
      }
    }
  }
  if (_limitProblem(json, aggregationLimitBy, whole: true) case final p?) {
    return p;
  }
  if (json['cap_below'] case final cap?) {
    if (cap is! Map ||
        cap.length != 2 ||
        !_isScore(cap['threshold']) ||
        !_isScore(cap['cap'])) {
      return 'a cap needs a threshold and a cap, each from 0 to 100.';
    }
  }
  if (json['missing'] case final missing?) {
    if (missing != 'skip' && !_isScore(missing)) {
      return 'what isn\'t rated must be left out, or a score from 0 to 100.';
    }
  }
  return null;
}

/// What's wrong with a judgment part's scoring as [json], in a sentence,
/// or null if it's fine: the checks the server's
/// `judgment_scoring_problems` makes.
String? judgmentScoringProblem(Object? json) {
  if (json is! Map) return 'its scoring must be an object.';
  const fields = {'weight_by', 'statistic', 'percentile', 'limit', 'limit_by'};
  if (_extraField(json, fields) case final extra?) {
    return "its scoring has a field the app doesn't know: $extra.";
  }
  final weightBy = json['weight_by'];
  if (weightBy != null && !judgmentWeightBy.containsKey(weightBy)) {
    return 'pick whether each event counts once or for its time.';
  }
  if (_statisticProblem(json) case final problem?) return problem;
  return _limitProblem(json, judgmentLimitBy, whole: weightBy != 'duration');
}
