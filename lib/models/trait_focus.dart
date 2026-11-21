import 'event.dart';
import 'facts.dart';
import 'scoring.dart';
import 'trait.dart';
import 'trait_scores.dart' show partKeys;

/// What [trait]'s judgments make of an event, or of a day's events: a
/// [score] out of 100, as the trait's scores are, and a [lean] from -1
/// (its parts' lowest ratings) through 0 (their neutral ones,
/// [judgmentNeutral]) to 1 (their highest), to color it by.
class TraitReading {
  const TraitReading({required this.score, required this.lean});

  final int score;
  final double lean;

  @override
  bool operator ==(Object other) =>
      other is TraitReading && score == other.score && lean == other.lean;

  @override
  int get hashCode => Object.hash(score, lean);
}

/// The rating of [part] -- a judgment part, rated on [scale] -- that says
/// nothing either way: its own "neutral" if it names one of its
/// ratings, or else halfway up [scale].
num judgmentNeutral(Part? part, int scale) => switch (part?['neutral']) {
  final num n when n >= 0 && n <= scale => n,
  _ => scale / 2,
};

/// How far [rating], on [scale], leans from [neutral]: -1 at 0, 0 at
/// [neutral], 1 at [scale].
double judgmentLean(int rating, int scale, num neutral) {
  if (rating < neutral) return neutral == 0 ? 0 : (rating - neutral) / neutral;
  if (rating > neutral) {
    return neutral == scale ? 0 : (rating - neutral) / (scale - neutral);
  }
  return 0;
}

/// [trait]'s judgments of [event], each part's for each person the event
/// was about (not a habit's): every person's mean across their parts,
/// then the mean across people. Null if it has none.
TraitReading? eventTraitReading(Trait trait, Event event) =>
    _eventParts(trait, event)?.reading;

/// [trait]'s rating of the [events] that start in [day], from midnight
/// to the next: each judgment part's of them combined as its scoring
/// says (by event or by their time, the mean or a percentile...), then
/// the parts as the trait's scoring says -- by default, their mean. Each
/// event counts as the mean of the people it was about. Null if none of
/// them was judged by it.
TraitReading? dayTraitReading(Trait trait, List<Event> events, DateTime day) {
  final start = DateTime(day.year, day.month, day.day);
  final end = DateTime(day.year, day.month, day.day + 1);
  final byPart = <String, List<({double score, double lean, Event event})>>{};
  for (final event in events) {
    if (event.isCancelled ||
        event.start.isBefore(start) ||
        !event.start.isBefore(end)) {
      continue;
    }
    final parts = _eventParts(trait, event);
    if (parts == null) continue;
    for (final MapEntry(key: part, value: (:score, :lean))
        in parts.byPart.entries) {
      (byPart[part] ??= []).add((score: score, lean: lean, event: event));
    }
  }
  if (byPart.isEmpty) return null;
  final defined = _partsByKey(trait);
  final scores = <(String, int?)>[];
  final leans = <(String, int?)>[];
  for (final MapEntry(key: key, value: judged) in byPart.entries) {
    final scoring =
        JudgmentScoring.fromJson(defined[key]?['scoring']) ??
        JudgmentScoring.mean;
    double? combine(
      double Function(({double score, double lean, Event event})) of,
    ) => scoring.combine([
      for (final j in judged)
        (
          score: of(j),
          minutes: j.event.end.difference(j.event.start).inSeconds / 60,
          at: j.event.start,
        ),
    ]);
    scores.add((key, combine((j) => j.score)?.round()));
    // On the scores' scale, so the trait's scoring combines it the same.
    leans.add((key, combine((j) => 50 + 50 * j.lean)?.round()));
  }
  final aggregation = trait.scoring ?? Aggregation.mean;
  final score = aggregation.combine(scores);
  final lean = aggregation.combine(leans);
  if (score == null || lean == null) return null;
  return TraitReading(score: score, lean: (lean - 50) / 50);
}

Map<String, Part> _partsByKey(Trait trait) => {
  for (final (i, key) in partKeys(trait.parts).indexed) key: trait.parts[i],
};

/// [trait]'s judgments of [event]: the mean of the people it was about,
/// part by part, and all together.
({TraitReading reading, Map<String, ({double score, double lean})> byPart})?
_eventParts(Trait trait, Event event) {
  final traitId = trait.id;
  if (traitId == null) return null;
  final parts = _partsByKey(trait);
  // Each person's judgments, part by part.
  final people = <String, Map<String, ({double score, double lean})>>{};
  for (final j in judgmentsFromJson(event.properties['judgments'])) {
    final scale = j.scale;
    if (j.traitId != traitId ||
        scale == null ||
        scale <= 0 ||
        j.personId.startsWith(_habitPrefix)) {
      continue;
    }
    final rating = j.rating.clamp(0, scale);
    // A person's own part is kept as "<part>@<person>".
    final part = parts[j.part] ?? parts[j.part.split('@').first];
    (people[j.personId] ??= {})[j.part] = (
      score: 100 * rating / scale,
      lean: judgmentLean(rating, scale, judgmentNeutral(part, scale)),
    );
  }
  if (people.isEmpty) return null;
  double mean(Iterable<double> values) =>
      values.reduce((a, b) => a + b) / values.length;
  final byPart = <String, ({double score, double lean})>{};
  for (final part in {for (final p in people.values) ...p.keys}) {
    final judged = [for (final p in people.values) ?p[part]];
    byPart[part.split('@').first] = (
      score: mean(judged.map((j) => j.score)),
      lean: mean(judged.map((j) => j.lean)),
    );
  }
  final perPerson = [
    for (final p in people.values)
      (
        score: mean(p.values.map((j) => j.score)),
        lean: mean(p.values.map((j) => j.lean)),
      ),
  ];
  return (
    reading: TraitReading(
      score: mean(perPerson.map((p) => p.score)).round(),
      lean: mean(perPerson.map((p) => p.lean)),
    ),
    byPart: byPart,
  );
}

const _habitPrefix = 'habit:';
