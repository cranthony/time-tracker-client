/// Scoring a subject's traits for a day -- a person's, or one of Self's
/// habits' -- from their events, in the app, from the events it has:
/// each part 0-100, over a trailing window that ends with the day; each
/// trait its parts' scores combined as its scoring says (by default their
/// mean, leaving out any with nothing to rate it by); and the subject's
/// rating of the day, their traits' scores combined as theirs, or the
/// defaults', say (see models/scoring.dart).
///
/// **A person's events.** The user ([selfPersonId]) was at every event.
/// Anyone else's "with" events are those whose facts name them in
/// `with_ids`; their "for" events, those naming them in `for_ids` (done
/// for them while they weren't there). A part reads one or the other by
/// its `engagement_type`.
///
/// **A habit's events** are Self's with its action, or with any action
/// under its group, worked out from the action tree as it is now -- or,
/// for a recurring goal's habit, those tagged with its goals. Its
/// judgments are those under `habit:<id>`. A recurring goal's habit is
/// scored by its [goalRate] too, as a trait of its own ([goalRateId]),
/// beside any traits it's given. The user is at every one, so
/// its parts that read events done for someone are left out; a trait
/// with no others isn't scored for it.
///
/// **A person's or circle's habit** is scored as they are -- their events,
/// judgments, parts and cancellations -- by the traits it picks of theirs
/// alone; a circle's, each of its people so, combined as the circle's
/// scoring says.
///
/// **Their cancellations** aren't read off the calendar: they're the ones
/// the server recorded for each person, or habit, when the user cancelled
/// an event they were to be at, or for ([Person.cancelledEvents],
/// [Habit.cancelledEvents]).
///
/// | kind             | scores                                              |
/// | ---------------- | --------------------------------------------------- |
/// | `judgment`       | its judgments (rating / scale) on the person's      |
/// |                  | events in the last `window_days` (30), combined as  |
/// |                  | its `scoring` says: by default, their mean          |
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
/// | `spacing`        | the share of the day's time, outside its            |
/// |                  | exceptions' events, that its clock hadn't run out:  |
/// |                  | each event of its `action` winds it back to         |
/// |                  | `max_gap_hours`; an exception's events stop it, and |
/// |                  | after one, it has `reset_hours` left (if given)     |
///
/// `continuity`, `count`, `duration` and `follow_through` with an
/// `action` count only events of that action -- or, for an action group,
/// of any action in it.
library;

import 'dart:math' as math;

import 'event.dart';
import 'facts.dart';
import 'goal.dart';
import 'habit.dart';
import 'person.dart';
import 'recurring_goal.dart';
import 'scoring.dart';
import 'trait.dart';
import '../widgets/durations.dart' show formatMinutes;

/// How far a judgment, count or duration looks back unless it says.
const defaultWindowDays = 30;

/// How far continuity looks either way unless it says.
const defaultWithinDays = 14;

/// How far before a day a spacing part looks, for its clock as the day
/// starts.
const spacingLeadDays = 2;

/// The most consecutive healthy days counted; more are "more than" it.
const maxConsistencyDays = 30;

/// The rating from which a day counts as healthy: on track, for a habit;
/// healthy, for a relationship.
const healthyRating = 70;

/// What a follow-through part loses per cancellation, and wins back per
/// day kept, unless it says; and how far back it runs.
const followThroughPenalty = 25;
const followThroughRecovery = 25;
const followThroughLookBackDays = 30;

/// Each of [parts]' id, what its judgments and weight are kept under, as
/// the server's `part_keys`: its own "id", or for one without -- as every
/// part was before parts had ids -- the name it had then: its kind for
/// the first of its kind, then "kind#2", "kind#3", passing over any
/// another part has as its id.
List<String> partKeys(List<Part> parts) {
  final taken = {
    for (final part in parts)
      if (part['id'] case final String id when id.isNotEmpty) id,
  };
  final seen = <String, int>{};
  return [
    for (final part in parts)
      () {
        final kind = switch (part['kind']) {
          final String kind => kind,
          _ => 'part',
        };
        var n = seen[kind] = (seen[kind] ?? 0) + 1;
        if (part['id'] case final String id when id.isNotEmpty) return id;
        while (true) {
          final key = n == 1 ? kind : '$kind#$n';
          if (taken.add(key)) return key;
          n++;
        }
      }(),
  ];
}

/// [parts], each with an id, as the server keeps them: its own; or, for
/// one without, the name it had before parts had ids ([partKeys]) -- or,
/// with [fresh], a new one, as the server makes for a part added: short
/// and random. For what stands in for the server, without one.
List<Part> withPartIds(List<Part> parts, {bool fresh = false}) {
  final keys = partKeys(parts);
  final taken = {...keys};
  const letters = 'abcdefghijklmnopqrstuvwxyz0123456789';
  final random = math.Random();
  return [
    for (final (i, part) in parts.indexed)
      if (part['id'] is String)
        part
      else
        {
          'id': fresh
              ? () {
                  String id;
                  do {
                    id = String.fromCharCodes([
                      for (var n = 0; n < 6; n++)
                        letters.codeUnitAt(random.nextInt(letters.length)),
                    ]);
                  } while (!taken.add(id));
                  return id;
                }()
              : keys[i],
          ...part,
        },
  ];
}

/// [traits] with an id for each of their own parts, as [withPartIds].
PersonTraits traitsWithPartIds(PersonTraits traits, {bool fresh = false}) =>
    PersonTraits(
      select: traits.select,
      except: traits.except,
      parts: {
        for (final MapEntry(:key, :value) in traits.parts.entries)
          key: withPartIds(value, fresh: fresh),
      },
      partScoring: traits.partScoring,
      scoring: traits.scoring,
      facts: traits.facts,
    );

/// How [trait]'s parts combine for [subject]: their own scoring for it,
/// or the trait's; the plain mean without either.
Aggregation partsAggregation(Subject subject, Trait trait) =>
    subject.traits.partScoring[trait.id] ?? trait.scoring ?? Aggregation.mean;

/// How [subject]'s traits combine into their rating: their own scoring,
/// or [defaults]'; the plain mean without either.
Aggregation traitsAggregation(Subject subject, ScoringDefaults defaults) =>
    subject.traits.scoring ?? defaults.traits ?? Aggregation.mean;

/// Who or what is scored: a person (Self among them), by their id, or
/// one of Self's habits, by `habit:<id>` -- which traits apply to them,
/// with their own parts for any, the cancellations recorded against
/// them, and, for a habit, the action or group whose events are its.
class Subject {
  const Subject({
    required this.id,
    this.of,
    this.traits = const PersonTraits(),
    this.cancelledEvents = const [],
    this.active = true,
    this.scope,
    this.recurring,
    this.goals = const [],
  });

  factory Subject.person(Person person) => Subject(
    id: person.id,
    traits: person.traits,
    cancelledEvents: person.cancelledEvents,
    active: person.active,
  );

  /// [habit], with [goals] -- the user's -- for a recurring goal's.
  factory Subject.habit(Habit habit, {List<Goal> goals = const []}) => Subject(
    id: habit.subject,
    traits: habit.traits,
    cancelledEvents: habit.cancelledEvents,
    active: habit.active,
    scope: habit.actionId,
    recurring: habit.recurringGoal,
    goals: habit.isGoal
        ? [
            for (final g in goals)
              if (g.habitId == habit.id) g,
          ]
        : const [],
  );

  /// Who it is: what its ratings are kept under.
  final String id;

  /// For a person's habit, the person, by id.
  final String? of;

  /// Whose events and judgments it's scored by: a person's habit's are
  /// theirs.
  String get who => of ?? id;

  /// [habit], [person]'s, scored as they are by the traits it picks of
  /// theirs: kept under [id] (by default the habit's).
  factory Subject.relationship(Habit habit, Person person, {String? id}) =>
      Subject(
        id: id ?? habit.subject,
        of: person.id,
        traits: person.traits.narrowedTo(habit.traits),
        cancelledEvents: person.cancelledEvents,
        active: habit.active && person.active,
      );
  final PersonTraits traits;
  final List<CancelledEvent> cancelledEvents;

  /// Whether they're scored.
  final bool active;

  /// For a habit, the action or group whose events are its; null for a
  /// person.
  final String? scope;

  bool get isHabit => scope != null;

  /// For a recurring goal's habit, its recurring goal, and its goals:
  /// its events are those tagged with them.
  final RecurringGoal? recurring;
  final List<Goal> goals;

  /// Whether [part] reads their events: a habit's are all "with".
  bool reads(Part part) => !isHabit || part['engagement_type'] != 'for';
}

/// The active traits that apply to [subject] -- those their traits
/// select, by default all -- each with its parts for them (their own, if
/// they replace the trait's).
List<(Trait, List<Part>)> traitsFor(Subject subject, List<Trait> traits) => [
  for (final trait in traits)
    if (trait.status == 'active' &&
        trait.id != null &&
        subject.traits.applies(trait.id!))
      (trait, subject.traits.parts[trait.id] ?? trait.parts),
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
      'spacing' => spacingLeadDays,
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
}) => scoreSubject(
  Subject.person(person),
  traits,
  start,
  end,
  events,
  parentOf: parentOf,
);

/// [subject]'s score of each trait that applies to them, as
/// [scorePerson]'s: a habit's from its events, leaving out the parts it
/// doesn't read, and any trait left with none. Each is weighed as their
/// traits combine, [defaults]' unless they say.
List<TraitScore> scoreSubject(
  Subject subject,
  List<Trait> traits,
  DateTime start,
  DateTime end,
  List<Event> events, {
  String? Function(String id)? parentOf,
  ScoringDefaults defaults = const ScoringDefaults(),
}) => _scoreSubject(
  subject,
  traits,
  end,
  events,
  _Reading(parentOf),
  defaults: defaults,
);

/// [scoreSubject], with [reading] keeping what it works out from [events]
/// for the next day scored from them.
List<TraitScore> _scoreSubject(
  Subject subject,
  List<Trait> traits,
  DateTime end,
  List<Event> events,
  _Reading reading, {
  required ScoringDefaults defaults,
}) {
  final combined = traitsAggregation(subject, defaults);
  return [
    if (subject.recurring case final recurring?)
      _goalRateScore(subject, recurring, end, combined),
    for (final (trait, parts) in traitsFor(subject, traits))
      if (_read(subject, parts) case final read when read.isNotEmpty)
        () {
          final aggregation = partsAggregation(subject, trait);
          // Keyed among all its parts, as its judgments are.
          final keys = partKeys(parts);
          final scores = [
            for (final i in read)
              _part(
                subject,
                trait.id!,
                parts[i],
                keys[i],
                end,
                events,
                reading,
                weight: aggregation.weightOf(keys[i]),
              ),
          ];
          return TraitScore(
            traitId: trait.id!,
            name: trait.name,
            weight: combined.weightOf(trait.id!),
            score: aggregation.combine([
              for (final p in scores)
                // A part that's wrong isn't rated, whatever it says.
                if (!p.said.startsWith(_notScored)) (p.key, p.score),
            ]),
            parts: scores,
          );
        }(),
  ];
}

/// The id a recurring goal's habit's goal rate is scored under, as a
/// trait's would be.
const goalRateId = 'goal_rate';

/// [subject]'s goal rate as of the day ending at [end], as a trait's
/// score: one part, its own.
TraitScore _goalRateScore(
  Subject subject,
  RecurringGoal recurring,
  DateTime end,
  Aggregation combined,
) {
  final rate = goalRate(
    habitIdOf(subject.id) ?? subject.id,
    recurring,
    subject.goals,
    end,
  );
  return TraitScore(
    traitId: goalRateId,
    name: 'Goal rate',
    weight: combined.weightOf(goalRateId),
    score: rate.score,
    parts: [
      PartScore(
        key: goalRateId,
        kind: goalRateId,
        score: rate.score,
        said: rate.said,
      ),
    ],
  );
}

/// Scores [parts] -- the trait [traitId]'s for [subject], as they're
/// being edited, say -- for the day ending at [end], as [scoreSubject]
/// would, from [events] (none cancelled); null for each one [subject]
/// doesn't read.
List<PartScore?> scoreParts(
  Subject subject,
  String traitId,
  List<Part> parts,
  DateTime end,
  List<Event> events, {
  String? Function(String id)? parentOf,
}) {
  final keys = partKeys(parts);
  final reading = _Reading(parentOf);
  return [
    for (final (i, part) in parts.indexed)
      subject.reads(part)
          ? _part(subject, traitId, part, keys[i], end, events, reading)
          : null,
  ];
}

/// Scores parts as [scoreParts] does, for the last day that's over, from
/// the events the app has; null without them.
typedef PartsScorer = List<PartScore?>? Function(
  Subject subject,
  String traitId,
  List<Part> parts,
);

/// Which of [parts] [subject] reads, by index.
List<int> _read(Subject subject, List<Part> parts) => [
  for (var i = 0; i < parts.length; i++)
    if (subject.reads(parts[i])) i,
];

/// The events [subject] took part in by [engagement]: for a habit, those
/// in its scope.
List<Event> _engaged(
  Subject subject,
  String engagement,
  List<Event> events,
  _Reading reading,
) {
  final personId = subject.who;
  if (subject.recurring != null) {
    if (engagement != 'with') return const [];
    final habitId = habitIdOf(subject.id);
    return reading.engaged(
      events,
      ('goals', subject.id),
      () => [
        for (final e in events)
          if (e.goals.any((g) => habitOfGoalId(g.goalId) == habitId)) e,
      ],
    );
  }
  if (subject.scope case final scope?) {
    if (engagement != 'with' || scope.isEmpty) return const [];
    return _ofAction(events, scope, reading);
  }
  if (engagement == 'with' && personId == selfPersonId) return events;
  return reading.engaged(
    events,
    (engagement, personId),
    () => [
      for (final e in events)
        if (_facts(e) case final facts?)
          if ((engagement == 'with' ? facts.withIds : facts.forIds).contains(
            personId,
          ))
            e,
    ],
  );
}

/// [events] of the action [actionId] -- or of any action in the group it
/// names -- or all of them without one.
List<Event> _ofAction(List<Event> events, String? actionId, _Reading reading) {
  if (actionId == null || actionId.isEmpty) return events;
  return reading.ofAction(
    events,
    actionId,
    () => [
      for (final e in events)
        if (_isOf(_actionIds(e), actionId, reading)) e,
    ],
  );
}

/// Whether [actionIds] are of the action [actionId], or in the group it
/// names; any are, without one.
bool _isOf(List<String> actionIds, String? actionId, _Reading reading) {
  if (actionId == null || actionId.isEmpty) return true;
  return actionIds.any((id) => reading.lineage(id).contains(actionId));
}

/// What scoring works out from a list of events, kept for the next
/// subject, part and day scored from the same list -- which is never
/// changed while it's scored from: which events each person took part in,
/// which are of each action, and each action's groups by [parentOf].
class _Reading {
  _Reading(this.parentOf);

  /// An action's group, as [_isOf] reads it.
  final String? Function(String id)? parentOf;

  final _engaged = Expando<Map<(String, String), List<Event>>>();
  final _ofAction = Expando<Map<String, List<Event>>>();
  final _lineages = <String, Set<String>>{};
  final _days = <(int, int, int), DateTime>{};

  /// The midnight [days] days after [at]'s, as `DateTime(at.year,
  /// at.month, at.day + days)` -- slow to make, and made again for every
  /// subject, part and day, while it's the same few days.
  DateTime day(DateTime at, int days) =>
      _days[(at.year, at.month, at.day + days)] ??= DateTime(
        at.year,
        at.month,
        at.day + days,
      );

  /// Those of [events] [made] gives, for [key]: worked out once.
  List<Event> engaged(
    List<Event> events,
    (String, String) key,
    List<Event> Function() made,
  ) => (_engaged[events] ??= {})[key] ??= made();

  /// Those of [events] of [actionId], [made] gives: worked out once.
  List<Event> ofAction(
    List<Event> events,
    String actionId,
    List<Event> Function() made,
  ) => (_ofAction[events] ??= {})[actionId] ??= made();

  /// [id] and every group it's in.
  Set<String> lineage(String id) => _lineages[id] ??= () {
    final seen = <String>{};
    for (String? at = id; at != null && seen.add(at);) {
      at = parentOf?.call(at);
    }
    return seen;
  }();
}

/// What's read off each event, read once: an event is never changed, but
/// scoring reads it again for every subject, part and day.
final _factsRead = Expando<(Facts?,)>();
final _actionSharesRead = Expando<List<ActionShare>>();
final _actionIdsRead = Expando<List<String>>();
final _judgmentsRead = Expando<List<Judgment>>();

Facts? _facts(Event e) =>
    (_factsRead[e] ??= (Facts.fromJson(e.properties['facts']),)).$1;

List<ActionShare> _actionShares(Event e) =>
    _actionSharesRead[e] ??= e.actionShares;

List<String> _actionIds(Event e) =>
    _actionIdsRead[e] ??= [for (final a in _actionShares(e)) a.actionId];

List<Judgment> _judgments(Event e) => _judgmentsRead[e] ??= judgmentsFromJson(
  e.properties['judgments'],
  eventId: e.id,
);

num _num(Object? value, num fallback) => value is num ? value : fallback;

String _g(num n) => n == n.roundToDouble() ? '${n.round()}' : '$n';

const _notScored = 'Not scored: ';

PartScore _part(
  Subject subject,
  String traitId,
  Part part,
  String key,
  DateTime end,
  List<Event> events,
  _Reading reading, {
  num weight = 1,
}) {
  final kind = switch (part['kind']) {
    final String kind => kind,
    _ => '?',
  };
  if (partProblem(part) case final problem?) {
    return PartScore(
      key: key,
      kind: kind,
      weight: 0,
      said: '$_notScored$problem',
    );
  }
  final rubric = part['rubric'] as String?;
  final engagement = part['engagement_type'] as String? ?? 'with';
  var engaged = _engaged(subject, engagement, events, reading);

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
        for (final j in _judgments(e)) {
          if (j.personId == subject.who &&
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
      final scoring =
          JudgmentScoring.fromJson(part['scoring']) ?? JudgmentScoring.mean;
      final value = scoring.combine([
        for (final (i, j) in judged.indexed)
          (
            score: 100 * j.rating / j.scale!,
            minutes: behind[i].end.difference(behind[i].start).inSeconds / 60,
            at: behind[i].start,
          ),
      ]);
      return PartScore(
        key: key,
        kind: kind,
        weight: weight,
        score: value?.round(),
        said:
            '${scoring.describe(judged.length)}${scoring.byDuration ? ',' : ''} '
            'in the last ${_g(days)} '
            'days',
        rubric: rubric,
        eventIds: [for (final e in behind) ?e.id],
        judgments: judged,
      );
    case 'continuity':
      engaged = _ofAction(engaged, part['action'] as String?, reading);
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
      final action = part['action'] as String?;
      engaged = _ofAction(engaged, action, reading);
      final (rating, said, behind) = _overInterval(
        part,
        kind,
        end,
        engaged,
        (e) =>
            _actionShare(e, action, reading) *
            _personShare(e, subject, engagement),
      );
      return score(rating, said, behind);
    case 'spacing':
      // The user was at every event of Self's, and a habit's, but its
      // exceptions -- sleep, say -- needn't be in a habit's scope.
      final theirs = subject.isHabit || subject.who == selfPersonId
          ? events
          : engaged;
      final (rating, said, behind) = _spacing(part, end, theirs, reading);
      return score(rating, said, behind);
    default: // follow_through
      engaged = _ofAction(engaged, part['action'] as String?, reading);
      final dropped = [
        for (final c in subject.cancelledEvents)
          if (c.engagement == engagement &&
              _isOf(c.actionIds, part['action'] as String?, reading))
            c,
      ];
      final (rating, said, behind) = _followThrough(
        part,
        end,
        engaged,
        dropped,
        reading,
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
  _Reading reading,
) {
  final penalty = _num(part['penalty'], followThroughPenalty);
  final recovery = _num(part['recovery'], followThroughRecovery);
  final lookBack = _num(
    part['look_back_days'],
    followThroughLookBackDays,
  ).round();
  // Only those of the days run through, not every day's search of all.
  final first = reading.day(end, -lookBack);
  kept = [
    for (final e in kept)
      if (!e.start.isBefore(first) && e.start.isBefore(end)) e,
  ];
  num score = 100, before = 100;
  var lost = 0;
  var gained = <Event>[];
  for (var back = lookBack - 1; back >= 0; back--) {
    final dayStart = reading.day(end, -1 - back);
    final dayEnd = back == 0 ? end : reading.day(end, -back);
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

/// A spacing part's score of the day ending at [end], how it was reached,
/// and the events of its action that day. Its clock is followed from
/// [spacingLeadDays] before the day, starting full.
(int?, String, List<Event>) _spacing(
  Part part,
  DateTime end,
  List<Event> events,
  _Reading reading,
) {
  final gap = Duration(minutes: ((part['max_gap_hours'] as num) * 60).round());
  final dayStart = reading.day(end, -1);
  final from = reading.day(end, -1 - spacingLeadDays);
  final resets = [
    for (final e in _ofAction(events, part['action'] as String?, reading))
      if (e.start.isBefore(end) && !e.start.isBefore(from)) e,
  ];
  final exceptions = [
    for (final x in spacingExceptions(part))
      for (final e in events)
        if (x.actions.any((a) => _isOf(_actionIds(e), a, reading)) &&
            e.end.isAfter(from) &&
            e.start.isBefore(end))
          (event: e, reset: x.resetHours),
  ];
  bool aside(DateTime t) => exceptions.any(
    (x) => !t.isBefore(x.event.start) && t.isBefore(x.event.end),
  );
  // Where anything changes: each reset, and each exception's start and
  // end, with the day's own edges.
  final points = <DateTime>{from, dayStart, end};
  for (final e in resets) {
    points.add(e.start);
  }
  for (final x in exceptions) {
    if (x.event.start.isAfter(from)) points.add(x.event.start);
    if (x.event.end.isBefore(end)) points.add(x.event.end);
  }
  final ordered = points.toList()..sort();
  var left = gap;
  var counted = Duration.zero, overdue = Duration.zero;
  for (var i = 0; i + 1 < ordered.length; i++) {
    final at = ordered[i], next = ordered[i + 1];
    // An exception ending here sets the clock; a reset here winds it back
    // after that.
    for (final x in exceptions) {
      if (x.event.end == at && x.reset != null) {
        left = Duration(minutes: (x.reset! * 60).round());
      }
    }
    if (resets.any((e) => e.start == at)) left = gap;
    final span = next.difference(at);
    if (aside(at.add(span ~/ 2))) continue;
    if (!at.isBefore(dayStart)) {
      counted += span;
      final late = span - (left.isNegative ? Duration.zero : left);
      if (late > Duration.zero) overdue += late;
    }
    left -= span;
  }
  final behind = [
    for (final e in resets)
      if (!e.start.isBefore(dayStart)) e,
  ];
  if (counted == Duration.zero) {
    return (null, 'All of the day was set aside', behind);
  }
  final share = 1 - overdue.inSeconds / counted.inSeconds;
  return (
    (100 * share).round(),
    overdue == Duration.zero
        ? 'Never over ${_g(gap.inMinutes / 60)} hours apart, in '
              '${formatMinutes(counted.inMinutes)}'
        : '${formatMinutes(overdue.inMinutes)} overdue of '
              '${formatMinutes(counted.inMinutes)}',
    behind,
  );
}

/// A count or duration part's score, how it was reached, and the events
/// behind it. A duration counts [shareOf] each event: the part of it
/// that's the part's action's.
(int, String, List<Event>) _overInterval(
  Part part,
  String kind,
  DateTime end,
  List<Event> events,
  double Function(Event) shareOf,
) {
  final intervalDays = _num(part['interval_days'], defaultWindowDays);
  final interval = Duration(minutes: (intervalDays * 24 * 60).round());
  // Only those any window it measures -- back to when it was last met,
  // with zero_at_days -- takes in: each measure searches them all.
  final reach = switch (part['zero_at_days']) {
    final num days => Duration(minutes: (days * 24 * 60).round()),
    _ => Duration.zero,
  };
  final earliest = end.subtract(interval + reach);
  events = [
    for (final e in events)
      if (e.start.isBefore(end) && e.end.isAfter(earliest)) e,
  ];
  final num target;
  final double Function(DateTime at) value;
  final String said;
  if (kind == 'duration') {
    target = part['target_min'] as num;
    value = (at) => _minutesIn(events, at.subtract(interval), at, shareOf);
    said = '${formatMinutes(value(end))} of ${formatMinutes(target)}';
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

/// The minutes of [events] between [start] and [end], each event's
/// [shareOf] it.
double _minutesIn(
  List<Event> events,
  DateTime start,
  DateTime end,
  double Function(Event) shareOf,
) => events.fold(0.0, (sum, e) {
  final from = e.start.isAfter(start) ? e.start : start;
  final to = e.end.isBefore(end) ? e.end : end;
  return sum + math.max(0, to.difference(from).inSeconds / 60) * shareOf(e);
});

/// The part of [event] that's [subject]'s, by [engagement], as its
/// people's shares say ([Event.withFractions], [Event.forFractions]):
/// all of it for the user, or a habit.
double _personShare(Event event, Subject subject, String engagement) {
  if (subject.scope != null || subject.who == selfPersonId) return 1;
  final facts = _facts(event);
  final fractions = shareFractions(
    (engagement == 'with' ? facts?.withShares : facts?.forShares) ?? const [],
    event.end.difference(event.start),
  );
  return fractions[subject.who] ?? 1;
}

/// The part of [event] that's of the action [actionId] -- or of any in
/// the group it names -- as its actions' shares say
/// ([Event.actionFractions], as the summaries count it); all of it
/// without one.
double _actionShare(Event event, String? actionId, _Reading reading) {
  if (actionId == null || actionId.isEmpty) return 1;
  // As Event.actionFractions has them, from its shares read once.
  return shareFractions(
        _actionShares(event),
        event.end.difference(event.start),
        split: RemainingSplit.even,
      ).entries
      .where((part) => _isOf([part.key], actionId, reading))
      .fold(0.0, (sum, part) => sum + part.value);
}

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
/// events and where. Self's habits are scored as people are, by
/// `habit:<id>`, but not counted in a trait's score of a day. Worked out once, from what was loaded; work it out
/// again when that changes.
class TraitScores {
  TraitScores._(
    this.days,
    this.history,
    this.windowDays,
    this.defaults,
    this._ratings,
    this._eventsOf,
    this._events,
    this._consistency,
  );

  /// Scores [people] (Self among them), and Self's [habits], by [traits]
  /// for the [days] days before [today]'s, from [events]: a circle's
  /// habit by [circles]' people. [parentOf]
  /// gives an action's group, as it is now: a habit's events are worked
  /// out from it. [windowDays] is how far back [events] go, for [digest]
  /// to say. Each one's consistency is counted back from the last of
  /// those days, rating days before them only while it holds, as far as
  /// [maxConsistencyDays] and one more. Scores combine as each says, or
  /// else as [defaults] do.
  factory TraitScores.compute({
    required List<Trait> traits,
    required List<Person> people,
    List<Habit> habits = const [],
    List<Circle> circles = const [],
    List<Goal> goals = const [],
    required List<Event> events,
    required DateTime today,
    String? Function(String id)? parentOf,
    int days = 7,
    int windowDays = defaultWindowDays,
    ScoringDefaults defaults = const ScoringDefaults(),
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
    // What's worked out from them once, for every subject and day.
    final reading = _Reading(parentOf);
    final ratings = <String, List<TraitsRating>>{};
    final consistency = <String, int>{};
    final eventsOf = <String, List<Event>>{};
    final byId = {for (final p in people) p.id: p};
    final circlesById = {for (final c in circles) c.id: c};
    // What each is rated by, for a day: one subject, or for a circle's
    // habit, each of its people's.
    final scored = <(Subject, List<Subject>, Aggregation?)>[];
    for (final person in people) {
      scored.add((Subject.person(person), const [], null));
    }
    for (final habit in habits) {
      if (habit.personId case final id?) {
        if (byId[id] case final person?) {
          scored.add((Subject.relationship(habit, person), const [], null));
        }
      } else if (habit.circleId case final id?) {
        final circle = circlesById[id];
        if (circle == null) continue;
        scored.add((
          Subject(id: habit.subject, active: habit.active),
          [
            for (final m in circle.memberIds)
              if (byId[m] case final person? when person.active)
                Subject.relationship(
                  habit,
                  person,
                  id: '${habit.subject}@${person.id}',
                ),
          ],
          circle.scoring ?? defaults.circles ?? Aggregation.mean,
        ));
      } else {
        scored.add((Subject.habit(habit, goals: goals), const [], null));
      }
    }
    TraitsRating rate(
      (Subject, List<Subject>, Aggregation?) of,
      DateTime start,
      String day,
    ) => switch (of) {
      (final subject, [], _) => _rate(
        subject,
        traits,
        start,
        day,
        kept,
        reading,
        defaults,
      ),
      (_, final members, final scoring) => _combined(
        [
          for (final m in members)
            (m.who, _rate(m, traits, start, day, kept, reading, defaults)),
        ],
        scoring!,
        day,
      ),
    };
    for (final of in scored) {
      final (subject, members, _) = of;
      if (!subject.active) continue;
      ratings[subject.id] = [
        for (var i = 0; i < starts.length; i++) rate(of, starts[i], keys[i]),
      ];
      bool healthy(int? rating) => rating != null && rating >= healthyRating;
      var streak = 0;
      for (final r in ratings[subject.id]!.reversed) {
        if (!healthy(r.rating)) break;
        streak++;
      }
      // Healthy every day shown: back further, while it holds.
      for (
        var back = days + 1;
        streak == back - 1 && back <= maxConsistencyDays + 1;
        back++
      ) {
        final start = reading.day(midnight, -back);
        final rated = rate(of, start, _dayKey(start));
        if (healthy(rated.rating)) streak++;
      }
      consistency[subject.id] = math.min(streak, maxConsistencyDays + 1);
      final whose = {for (final m in members) m.who};
      final involved = subject.isHabit
          ? _engaged(subject, 'with', kept, reading)
          : [
              for (final e in kept)
                if (members.isEmpty
                    ? _involves(subject.who, e)
                    : whose.any((who) => _involves(who, e)))
                  e,
            ];
      eventsOf[subject.id] = [
        for (final e in involved)
          if (e.start.isBefore(today)) e,
      ];
    }
    final history = <TraitDay>[];
    for (final trait in traits) {
      if (trait.status != 'active' || trait.id == null) continue;
      for (var i = 0; i < keys.length; i++) {
        final scores = <String, int>{};
        for (final MapEntry(key: id, value: rated) in ratings.entries) {
          if (habitIdOf(id) != null) continue;
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
    return TraitScores._(
      keys,
      history,
      windowDays,
      defaults,
      ratings,
      eventsOf,
      kept,
      consistency,
    );
  }

  /// A circle's habit's rating of [day]: its people's [rated] combined
  /// by [scoring], and each trait's score, theirs combined so.
  static TraitsRating _combined(
    List<(String, TraitsRating)> rated,
    Aggregation scoring,
    String day,
  ) {
    final names = <String, String>{};
    final byTrait = <String, List<(String, int?)>>{};
    for (final (who, r) in rated) {
      for (final t in r.traits) {
        names[t.traitId] = t.name;
        (byTrait[t.traitId] ??= []).add((who, t.score));
      }
    }
    return TraitsRating(
      rating: scoring.combine([for (final (who, r) in rated) (who, r.rating)]),
      traits: [
        for (final MapEntry(key: id, value: scores) in byTrait.entries)
          TraitScore(
            traitId: id,
            name: names[id]!,
            score: scoring.combine(scores),
          ),
      ],
      day: day,
    );
  }

  static TraitsRating _rate(
    Subject subject,
    List<Trait> traits,
    DateTime start,
    String day,
    List<Event> events,
    _Reading reading,
    ScoringDefaults defaults,
  ) {
    final end = reading.day(start, 1);
    final scores = _scoreSubject(
      subject,
      traits,
      end,
      events,
      reading,
      defaults: defaults,
    );
    final combined = traitsAggregation(subject, defaults);
    return TraitsRating(
      rating: combined.combine([for (final s in scores) (s.traitId, s.score)]),
      traits: scores,
      leftOut: [
        for (final t in traits)
          if (t.status != 'active' ||
              !subject.traits.applies(t.id ?? '') ||
              combined.weightOf(t.id ?? '') == 0 ||
              // A habit's, with no part it reads.
              (subject.isHabit &&
                  t.id != null &&
                  !scores.any((s) => s.traitId == t.id)))
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

  /// How scores combine where nothing says otherwise.
  final ScoringDefaults defaults;

  final Map<String, List<TraitsRating>> _ratings;
  final Map<String, List<Event>> _eventsOf;
  final List<Event> _events;
  final Map<String, int> _consistency;

  /// How many days in a row, back from the last day scored, [subjectId]
  /// has been healthy: up to [maxConsistencyDays], or one more for more
  /// than that; 0 for none, or for anyone not scored.
  int consistency(String subjectId) => _consistency[subjectId] ?? 0;

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

  /// The health of [personIds], as a circle's: their healths combined as
  /// [scoring] -- the circle's own -- says, or else the defaults' circles;
  /// by default, the mean of those rated.
  int? groupHealth(Iterable<String> personIds, {Aggregation? scoring}) =>
      _circles(scoring).combine([for (final id in personIds) (id, health(id))]);

  /// [groupHealth] of each day, oldest first.
  List<int?> groupTrend(Iterable<String> personIds, {Aggregation? scoring}) =>
      _trend(personIds, _circles(scoring));

  Aggregation _circles(Aggregation? scoring) =>
      scoring ?? defaults.circles ?? Aggregation.mean;

  /// The rating of each day, oldest first, of a layer of the habit graph
  /// of [subjectIds] (habits by `habit:<id>`, people by id): theirs
  /// combined as the defaults' habit layers say, by default the lowest.
  List<int?> layerTrend(Iterable<String> subjectIds) =>
      _trend(subjectIds, defaults.habitLayers ?? Aggregation.lowest);

  List<int?> _trend(Iterable<String> ids, Aggregation aggregation) => [
    for (var i = 0; i < days.length; i++)
      aggregation.combine([
        for (final id in ids) (id, _ratings[id]?.elementAtOrNull(i)?.rating),
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
          for (final where
              in Facts.fromJson(e.properties['facts'])?.locationIds ??
                  const <String>[])
            (where, e.start),
      ]),
      events: [for (final e in events) e.toJson().cast<String, dynamic>()],
    );
  }

  /// Whether [e] was with or for [personId]: for Self, whether it says
  /// anything of who or where.
  static bool _involves(String personId, Event e) {
    final facts = _facts(e);
    if (facts == null) return false;
    if (personId == selfPersonId) return !facts.isEmpty;
    return facts.withIds.contains(personId) || facts.forIds.contains(personId);
  }
}

String _dayKey(DateTime day) =>
    '${day.year.toString().padLeft(4, '0')}-'
    '${day.month.toString().padLeft(2, '0')}-'
    '${day.day.toString().padLeft(2, '0')}';
