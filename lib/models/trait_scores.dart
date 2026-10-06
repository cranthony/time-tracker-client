/// Scoring a person's traits for a day, from their events: each part
/// 0-100, each trait the weighted mean of its parts (leaving out any with
/// nothing to rate it by), over a trailing window that ends with the day.
/// A port of the server's utilities/trait_scores.py, worked out in the
/// app from the events it has.
///
/// **A person's events.** The user ([selfPersonId]) was at every event.
/// Anyone else's "with" events are those whose facts name them in
/// `with_ids`; their "for" events, those naming them in `for_ids` (done
/// for them while they weren't there). A part reads one or the other by
/// its `engagement_type`.
///
/// **Their cancellations** aren't read off the calendar: they're the ones
/// the server recorded for each person when the user cancelled an event
/// they were to be at, or for ([Person.cancelledEvents]).
///
/// | kind             | scores                                              |
/// | ---------------- | --------------------------------------------------- |
/// | `judgment`       | the mean of its judgments (rating / scale) on the   |
/// |                  | person's events in the last `window_days` (30)      |
/// | `continuity`     | 100 if the last event ended within                  |
/// |                  | `last_within_days` of the day's end and the next    |
/// |                  | starts within `next_within_days` after it; 50 for   |
/// |                  | one; 0 for neither                                  |
/// | `count`          | events over `interval_days` (30) against `target`:  |
/// |                  | 100 while it's met; short of it, in proportion --   |
/// |                  | or, with `zero_at_days`, falling from 100 when it   |
/// |                  | was last met to 0 by `zero_at_days`                 |
/// | `duration`       | the same with minutes, against `target_min`         |
/// | `follow_through` | a running score over `look_back_days` (30): from    |
/// |                  | 100, each day loses `penalty` (25) per event the    |
/// |                  | user cancelled and regains `recovery` (25) if one   |
/// |                  | was kept                                            |
///
/// `continuity`, `count`, `duration` and `follow_through` with an
/// `action` count only events of that action -- or, for an action group,
/// of any action in it.
library;

import 'dart:math' as math;

import 'event.dart';
import 'facts.dart';
import 'person.dart';
import 'trait.dart';

/// How far a judgment, count or duration looks back unless it says.
const defaultWindowDays = 30;

/// How far continuity looks either way unless it says.
const defaultWithinDays = 14;

/// What a follow-through part loses per cancellation, and wins back per
/// day kept, unless it says; and how far back it runs.
const followThroughPenalty = 25;
const followThroughRecovery = 25;
const followThroughLookBackDays = 30;

/// A name for each of [parts], unique within them: its kind, then
/// "kind#2", "kind#3" for later ones of the same kind. Judgments name
/// parts by these.
List<String> partKeys(List<Part> parts) {
  final seen = <String, int>{};
  return [
    for (final part in parts)
      () {
        final kind = switch (part['kind']) {
          final String kind => kind,
          _ => 'part',
        };
        final n = seen[kind] = (seen[kind] ?? 0) + 1;
        return n == 1 ? kind : '$kind#$n';
      }(),
  ];
}

/// The active traits that apply to [person] -- those their traits select,
/// by default all -- each with its parts for them (their own, if they
/// replace the trait's).
List<(Trait, List<Part>)> traitsFor(Person person, List<Trait> traits) => [
  for (final trait in traits)
    if (trait.status == 'active' &&
        trait.id != null &&
        person.traits.applies(trait.id!))
      (trait, person.traits.parts[trait.id] ?? trait.parts),
];

/// How many days before a day's end, and after it, [parts] read events.
({int back, int ahead}) reach(Iterable<Part> parts) {
  var back = defaultWindowDays, ahead = 0;
  int days(Object? n, int fallback) => n is num ? n.ceil() : fallback;
  for (final part in parts) {
    if (partProblem(part) != null) continue;
    final n = switch (part['kind']) {
      'judgment' => days(part['window_days'], defaultWindowDays),
      'continuity' => () {
        ahead = math.max(
          ahead,
          days(part['next_within_days'], defaultWithinDays),
        );
        return days(part['last_within_days'], defaultWithinDays);
      }(),
      'count' || 'duration' => math.max(
        days(part['interval_days'], defaultWindowDays),
        days(part['zero_at_days'], 0),
      ),
      'follow_through' => days(
        part['look_back_days'],
        followThroughLookBackDays,
      ),
      _ => 0,
    };
    back = math.max(back, n);
  }
  return (back: back, ahead: ahead);
}

/// [person]'s score of each trait that applies to them, for the day from
/// [start] to [end], from [events] (none cancelled). [parentOf] gives an
/// action's group, to count the actions in a group a part names.
List<TraitScore> scorePerson(
  Person person,
  List<Trait> traits,
  DateTime start,
  DateTime end,
  List<Event> events, {
  String? Function(String id)? parentOf,
}) => [
  for (final (trait, parts) in traitsFor(person, traits))
    () {
      final keys = partKeys(parts);
      final scores = [
        for (var i = 0; i < parts.length; i++)
          _part(person, trait.id!, parts[i], keys[i], end, events, parentOf),
      ];
      return TraitScore(
        traitId: trait.id!,
        name: trait.name,
        score: _weightedMean([for (final p in scores) (p.score, p.weight)]),
        parts: scores,
      );
    }(),
];

/// The weighted mean of [scores] with a score; null if none has one.
int? _weightedMean(List<(int?, num)> scores) {
  final rated = [
    for (final (score, weight) in scores)
      if (score != null) (score, weight),
  ];
  final total = rated.fold<num>(0, (sum, s) => sum + s.$2);
  if (rated.isEmpty || total <= 0) return null;
  return (rated.fold<num>(0, (sum, s) => sum + s.$1 * s.$2) / total).round();
}

/// The events [personId] took part in by [engagement].
List<Event> _engaged(String personId, String engagement, List<Event> events) {
  if (engagement == 'with' && personId == selfPersonId) return events;
  return [
    for (final e in events)
      if (Facts.fromJson(e.properties['facts']) case final facts?)
        if ((engagement == 'with' ? facts.withIds : facts.forIds).contains(
          personId,
        ))
          e,
  ];
}

/// [events] of the action [actionId] -- or of any action in the group it
/// names -- or all of them without one.
List<Event> _ofAction(
  List<Event> events,
  String? actionId,
  String? Function(String id)? parentOf,
) => [
  for (final e in events)
    if (_isOf(e.actionIds, actionId, parentOf)) e,
];

/// Whether [actionIds] are of the action [actionId], or in the group it
/// names; any are, without one.
bool _isOf(
  List<String> actionIds,
  String? actionId,
  String? Function(String id)? parentOf,
) {
  if (actionId == null || actionId.isEmpty) return true;
  bool matches(String candidate) {
    final seen = <String>{};
    for (String? id = candidate; id != null && seen.add(id);) {
      if (id == actionId) return true;
      id = parentOf?.call(id);
    }
    return false;
  }

  return actionIds.any(matches);
}

num _num(Object? value, num fallback) => value is num ? value : fallback;

String _g(num n) => n == n.roundToDouble() ? '${n.round()}' : '$n';

PartScore _part(
  Person person,
  String traitId,
  Part part,
  String key,
  DateTime end,
  List<Event> events,
  String? Function(String id)? parentOf,
) {
  final kind = switch (part['kind']) {
    final String kind => kind,
    _ => '?',
  };
  if (partProblem(part) case final problem?) {
    return PartScore(
      key: key,
      kind: kind,
      weight: 0,
      said: 'Not scored: $problem',
    );
  }
  final weight = _num(part['weight'], 1);
  final rubric = part['rubric'] as String?;
  final engagement = part['engagement_type'] as String? ?? 'with';
  var engaged = _engaged(person.id, engagement, events);

  PartScore score(int? value, String said, List<Event> behind) => PartScore(
    key: key,
    kind: kind,
    weight: weight,
    score: value,
    said: said,
    rubric: rubric,
    eventIds: [for (final e in behind) ?e.id],
  );

  switch (kind) {
    case 'judgment':
      final days = _num(part['window_days'], defaultWindowDays);
      final from = end.subtract(Duration(minutes: (days * 24 * 60).round()));
      final judged = <Judgment>[];
      final behind = <Event>[];
      for (final e in engaged) {
        if (e.start.isBefore(from) || !e.start.isBefore(end)) continue;
        for (final j in judgmentsFromJson(
          e.properties['judgments'],
          eventId: e.id,
        )) {
          if (j.personId == person.id &&
              j.traitId == traitId &&
              j.part == key &&
              (j.scale ?? 0) > 0) {
            judged.add(j);
            behind.add(e);
          }
        }
      }
      if (judged.isEmpty) {
        return score(null, 'No judgments in the last ${_g(days)} days', []);
      }
      final mean =
          judged.map((j) => j.rating / j.scale!).reduce((a, b) => a + b) /
          judged.length;
      return PartScore(
        key: key,
        kind: kind,
        weight: weight,
        score: (100 * mean).round(),
        said:
            'Mean of ${judged.length} judgment(s) in the last ${_g(days)} '
            'days',
        rubric: rubric,
        eventIds: [for (final e in behind) ?e.id],
        judgments: judged,
      );
    case 'continuity':
      engaged = _ofAction(engaged, part['action'] as String?, parentOf);
      final lastDays = _num(part['last_within_days'], defaultWithinDays);
      final nextDays = _num(part['next_within_days'], defaultWithinDays);
      Event? last, next;
      for (final e in engaged) {
        if (e.start.isBefore(end)) {
          if (last == null || e.end.isAfter(last.end)) last = e;
        } else if (next == null || e.start.isBefore(next.start)) {
          next = e;
        }
      }
      final lastOk =
          last != null && _days(end.difference(last.end)) <= lastDays;
      final nextOk =
          next != null && _days(next.start.difference(end)) <= nextDays;
      final said = [
        last != null
            ? 'last ${_ago(end.difference(last.end))} ago'
            : 'none '
                  'before',
        next != null
            ? 'next in ${_ago(next.start.difference(end))}'
            : 'none '
                  'planned',
      ].join('; ');
      return score(
        (lastOk ? 50 : 0) + (nextOk ? 50 : 0),
        '${said[0].toUpperCase()}${said.substring(1)} (within '
        '${_g(lastDays)} and ${_g(nextDays)} days)',
        [?last, ?next],
      );
    case 'count' || 'duration':
      engaged = _ofAction(engaged, part['action'] as String?, parentOf);
      final (rating, said, behind) = _overInterval(part, kind, end, engaged);
      return score(rating, said, behind);
    default: // follow_through
      engaged = _ofAction(engaged, part['action'] as String?, parentOf);
      final dropped = [
        for (final c in person.cancelledEvents)
          if (c.engagement == engagement &&
              _isOf(c.actionIds, part['action'] as String?, parentOf))
            c,
      ];
      final (rating, said, behind) = _followThrough(
        part,
        end,
        engaged,
        dropped,
      );
      return score(rating, said, behind);
  }
}

/// A follow-through part's running score, how the day's was reached, and
/// the events kept that day: [kept] the person's events, [dropped] the
/// cancellations recorded for them.
(int, String, List<Event>) _followThrough(
  Part part,
  DateTime end,
  List<Event> kept,
  List<CancelledEvent> dropped,
) {
  final penalty = _num(part['penalty'], followThroughPenalty);
  final recovery = _num(part['recovery'], followThroughRecovery);
  final lookBack = _num(
    part['look_back_days'],
    followThroughLookBackDays,
  ).round();
  final start = DateTime(end.year, end.month, end.day - 1);
  num score = 100, before = 100;
  var lost = 0;
  var gained = <Event>[];
  for (var back = lookBack - 1; back >= 0; back--) {
    final dayStart = DateTime(start.year, start.month, start.day - back);
    final dayEnd = back == 0
        ? end
        : DateTime(dayStart.year, dayStart.month, dayStart.day + 1);
    bool within(DateTime t) => !t.isBefore(dayStart) && t.isBefore(dayEnd);
    before = score;
    lost = dropped.where((c) => within(c.start)).length;
    gained = [
      for (final e in kept)
        if (within(e.start)) e,
    ];
    score = (score - penalty * lost + (gained.isEmpty ? 0 : recovery)).clamp(
      0,
      100,
    );
  }
  final said = [
    if (lost > 0) '$lost cancelled (−${_g(penalty * lost)})',
    if (gained.isNotEmpty) '${gained.length} kept (+${_g(recovery)})',
  ].join(', ');
  return (
    score.round(),
    '${said.isEmpty ? 'Nothing cancelled or kept' : said} that day, from '
        '${before.round()}',
    gained,
  );
}

double _days(Duration d) => d.inMicroseconds / Duration.microsecondsPerDay;

/// A count or duration part's score, how it was reached, and the events
/// behind it.
(int, String, List<Event>) _overInterval(
  Part part,
  String kind,
  DateTime end,
  List<Event> events,
) {
  final intervalDays = _num(part['interval_days'], defaultWindowDays);
  final interval = Duration(minutes: (intervalDays * 24 * 60).round());
  final num target;
  final double Function(DateTime at) value;
  final String said;
  if (kind == 'duration') {
    target = part['target_min'] as num;
    value = (at) => _minutesIn(events, at.subtract(interval), at);
    said = '${value(end).round()} of ${_g(target)} minutes';
  } else {
    target = _num(part['target'], 1);
    value = (at) => events
        .where(
          (e) => e.start.isBefore(at) && e.end.isAfter(at.subtract(interval)),
        )
        .length
        .toDouble();
    said =
        '${value(end).round()} of ${_g(target)} '
        '${part['noun'] as String? ?? 'events'}';
  }
  final amount = value(end).round();
  final behind = [
    for (final e in events)
      if (e.start.isBefore(end) && e.end.isAfter(end.subtract(interval))) e,
  ];
  final within = 'the last ${_g(intervalDays)} days';
  final zeroAtDays = part['zero_at_days'];
  if (zeroAtDays is! num || amount >= target) {
    return (_capped(amount, target), '$said in $within', behind);
  }
  final met = _lastMet(
    events,
    value,
    end,
    interval,
    Duration(minutes: (zeroAtDays * 24 * 60).round()),
    target,
    continuous: kind == 'duration',
  );
  if (met == null) {
    return (
      0,
      '$said in $within; not met in the last ${_g(zeroAtDays)} days',
      behind,
    );
  }
  final grace = zeroAtDays - intervalDays;
  final lapsed = end.difference(met);
  final rating = (100 * (1 - _days(lapsed) / grace)).round().clamp(0, 100);
  return (
    rating,
    '$said in $within; met until ${_ago(lapsed)} ago, 0 after '
        '${_g(zeroAtDays)} days',
    behind,
  );
}

/// The latest time, from `end - horizon` to [end], at which the window of
/// [interval] before it met [target] -- `value(t)` being the window
/// ending at `t`'s value -- or null if there's none. The value changes
/// only where an event's start or end enters or leaves the window:
/// between those, linearly if [continuous] (minutes), else not at all (a
/// count).
DateTime? _lastMet(
  List<Event> events,
  double Function(DateTime at) value,
  DateTime end,
  Duration interval,
  Duration horizon,
  num target, {
  required bool continuous,
}) {
  final first = end.subtract(horizon);
  final points = <DateTime>{end, first};
  for (final e in events) {
    for (final edge in [
      e.start,
      e.end,
      e.start.add(interval),
      e.end.add(interval),
    ]) {
      if (edge.isAfter(first) && edge.isBefore(end)) points.add(edge);
    }
  }
  final ordered = points.toList()..sort((a, b) => b.compareTo(a));
  if (value(end) >= target) return end;
  for (var i = 0; i + 1 < ordered.length; i++) {
    final high = ordered[i], low = ordered[i + 1];
    if (continuous) {
      final atLow = value(low);
      if (atLow >= target) {
        final atHigh = value(high);
        final share = (atLow - target) / (atLow - atHigh);
        return low.add(high.difference(low) * share);
      }
    } else if (value(low.add(high.difference(low) ~/ 2)) >= target) {
      return high;
    } else if (value(low) >= target) {
      return low;
    }
  }
  return null;
}

double _minutesIn(List<Event> events, DateTime start, DateTime end) =>
    events.fold(0.0, (sum, e) {
      final from = e.start.isAfter(start) ? e.start : start;
      final to = e.end.isBefore(end) ? e.end : end;
      return sum + math.max(0, to.difference(from).inSeconds / 60);
    });

int _capped(num value, num target) =>
    target > 0 ? math.min(100, (100 * value / target).round()) : 100;

String _ago(Duration gap) {
  final days = _days(gap);
  if (days >= 1) {
    return '${days.round()} day${days.round() != 1 ? 's' : ''}';
  }
  final hours = gap.inSeconds / 3600;
  return '${hours.round()} hour${hours.round() != 1 ? 's' : ''}';
}

/// Every person's traits scored for each of the last [days] days that are
/// over, from the events the app has: each person's rating of a day (the
/// mean of their traits' scores), each trait's (the mean of everyone's
/// scores of it), and each person's history -- what was done at their
/// events and where. Worked out once, from what was loaded; work it out
/// again when that changes.
class TraitScores {
  TraitScores._(
    this.days,
    this.history,
    this.windowDays,
    this._ratings,
    this._eventsOf,
    this._events,
  );

  /// Scores [people] (Self among them) by [traits] for the [days] days
  /// before [today]'s, from [events]. [parentOf] gives an action's group.
  /// [windowDays] is how far back [events] go, for [digest] to say.
  factory TraitScores.compute({
    required List<Trait> traits,
    required List<Person> people,
    required List<Event> events,
    required DateTime today,
    String? Function(String id)? parentOf,
    int days = 7,
    int windowDays = defaultWindowDays,
  }) {
    final midnight = DateTime(today.year, today.month, today.day);
    final starts = [
      for (var back = days; back >= 1; back--)
        DateTime(midnight.year, midnight.month, midnight.day - back),
    ];
    final keys = [for (final d in starts) _dayKey(d)];
    final kept = [
      for (final e in events)
        if (!e.isCancelled) e,
    ];
    final ratings = <String, List<TraitsRating>>{};
    final eventsOf = <String, List<Event>>{};
    for (final person in people) {
      if (!person.active) continue;
      ratings[person.id] = [
        for (var i = 0; i < starts.length; i++)
          _rate(person, traits, starts[i], keys[i], kept, parentOf),
      ];
      eventsOf[person.id] = [
        for (final e in kept)
          if (e.start.isBefore(today) && _involves(person.id, e)) e,
      ];
    }
    final history = <TraitDay>[];
    for (final trait in traits) {
      if (trait.status != 'active' || trait.id == null) continue;
      for (var i = 0; i < keys.length; i++) {
        final scores = <String, int>{};
        for (final MapEntry(key: id, value: rated) in ratings.entries) {
          final score = rated[i].traits
              .where((t) => t.traitId == trait.id)
              .firstOrNull
              ?.score;
          if (score != null) scores[id] = score;
        }
        if (scores.isEmpty) continue;
        history.add(
          TraitDay(
            traitId: trait.id!,
            name: trait.name,
            day: keys[i],
            score: _mean(scores.values.toList())!,
            people: scores,
          ),
        );
      }
    }
    return TraitScores._(keys, history, windowDays, ratings, eventsOf, kept);
  }

  static TraitsRating _rate(
    Person person,
    List<Trait> traits,
    DateTime start,
    String day,
    List<Event> events,
    String? Function(String id)? parentOf,
  ) {
    final end = DateTime(start.year, start.month, start.day + 1);
    final scores = scorePerson(
      person,
      traits,
      start,
      end,
      events,
      parentOf: parentOf,
    );
    return TraitsRating(
      rating: _mean([for (final s in scores) s.score]),
      traits: scores,
      leftOut: [
        for (final t in traits)
          if (t.status != 'active' || !person.traits.applies(t.id ?? ''))
            t.name,
      ],
      day: day,
    );
  }

  /// The days scored, oldest first ("2026-10-05").
  final List<String> days;

  /// Each active trait's score of each day, oldest first: the mean of
  /// everyone scored by it that day. A day no one was scored is left out.
  final List<TraitDay> history;

  /// How far back the events go, in days.
  final int windowDays;

  final Map<String, List<TraitsRating>> _ratings;
  final Map<String, List<Event>> _eventsOf;
  final List<Event> _events;

  late final Map<String, Event> _byId = {
    for (final e in _events)
      if (e.id != null) e.id!: e,
  };

  /// The events behind [score]'s parts, by id, as the server sent them.
  Map<String, Map<String, dynamic>> eventsBehind(TraitScore score) => {
    for (final part in score.parts)
      for (final id in part.eventIds)
        if (_byId[id] case final e?) id: e.toJson().cast<String, dynamic>(),
  };

  /// [personId]'s rating of [day] (by default the last), trait by trait
  /// and part by part; null for anyone not scored.
  TraitsRating? rating(String personId, [String? day]) {
    final all = _ratings[personId];
    if (all == null || all.isEmpty) return null;
    return day == null ? all.last : all.where((r) => r.day == day).firstOrNull;
  }

  /// [personId]'s relationship health: their rating of the last day.
  int? health(String personId) => rating(personId)?.rating;

  /// [personId]'s rating of each day, oldest first.
  List<int?> healthTrend(String personId) => [
    for (final r in _ratings[personId] ?? const <TraitsRating>[]) r.rating,
  ];

  /// The mean health of [personIds], as a circle's: of those rated.
  int? groupHealth(Iterable<String> personIds) =>
      _mean([for (final id in personIds) health(id)]);

  /// [groupHealth] of each day, oldest first.
  List<int?> groupTrend(Iterable<String> personIds) => [
    for (var i = 0; i < days.length; i++)
      _mean([
        for (final id in personIds)
          if (_ratings[id] case final r? when r.length > i) r[i].rating,
      ]),
  ];

  static int? _mean(List<int?> values) {
    final rated = values.nonNulls.toList();
    return rated.isEmpty
        ? null
        : (rated.reduce((a, b) => a + b) / rated.length).round();
  }

  /// [personId]'s history: the actions done and locations of their past
  /// events, with how often and when, and the events, as the server sent
  /// them.
  PersonDigest digest(String personId) {
    final events = _eventsOf[personId] ?? const <Event>[];
    List<DigestEntry> entries(Iterable<(String, DateTime)> seen) {
      final byLabel = <String, List<DateTime>>{};
      for (final (label, at) in seen) {
        (byLabel[label] ??= []).add(at);
      }
      return [
        for (final MapEntry(key: label, value: at) in byLabel.entries)
          DigestEntry(
            label: label,
            count: at.length,
            first: _dayKey(at.reduce((a, b) => a.isBefore(b) ? a : b)),
            last: _dayKey(at.reduce((a, b) => a.isAfter(b) ? a : b)),
          ),
      ]..sort((a, b) => b.count.compareTo(a.count));
    }

    return PersonDigest(
      personId: personId,
      windowDays: windowDays,
      eventsCounted: events.length,
      actions: entries([
        for (final e in events)
          for (final id in e.actionIds) (id, e.start),
      ]),
      locations: entries([
        for (final e in events)
          if (Facts.fromJson(e.properties['facts'])?.locationId
              case final where?)
            (where, e.start),
      ]),
      events: [for (final e in events) e.toJson().cast<String, dynamic>()],
    );
  }

  /// Whether [e] was with or for [personId]: for Self, whether it says
  /// anything of who or where.
  static bool _involves(String personId, Event e) {
    final facts = Facts.fromJson(e.properties['facts']);
    if (facts == null) return false;
    if (personId == selfPersonId) return !facts.isEmpty;
    return facts.withIds.contains(personId) || facts.forIds.contains(personId);
  }
}

String _dayKey(DateTime day) =>
    '${day.year.toString().padLeft(4, '0')}-'
    '${day.month.toString().padLeft(2, '0')}-'
    '${day.day.toString().padLeft(2, '0')}';
