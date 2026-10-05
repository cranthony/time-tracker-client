import 'facets.dart';

/// A trait goals can be rated by -- Thoughtful, Reliable, Creative,
/// Adventurous, Generous to start with -- mirroring the Time Tracker MCP
/// server's `Trait` (its utilities/traits.py). Its score of a goal's day is
/// the weighted mean of its [parts]' scores, each computed over the goal's
/// events and their facets, or (a judgment) made in the reflection.
class Trait {
  const Trait({
    this.id,
    required this.name,
    this.status = 'active',
    this.definition,
    this.parts = const [],
    this.problems = const [],
  });

  /// Made from its first name when it's created; it never changes.
  final String? id;
  final String name;

  /// One of [traitStatuses]' keys.
  final String status;
  final String? definition;
  final List<Part> parts;

  /// What's wrong with it, as the server says, for one edited by hand:
  /// its bad parts aren't rated.
  final List<String> problems;

  factory Trait.fromJson(Map<String, dynamic> json) => Trait(
    id: json['id'] as String?,
    name: json['name'] as String? ?? '',
    status: json['status'] as String? ?? 'active',
    definition: json['definition'] as String?,
    parts: [
      for (final part in json['parts'] as List? ?? const [])
        if (part is Map) Map<String, Object?>.unmodifiable(part.cast()),
    ],
    problems: [for (final p in json['problems'] as List? ?? const []) '$p'],
  );

  /// As `create_trait` and `update_trait` take it.
  Map<String, Object?> toJson() => {
    'id': ?id,
    'name': name,
    'status': status,
    'definition': ?definition,
    'parts': parts,
  };
}

/// One part of a trait: `{"kind": ..., "weight": 1, ...}`, the fields its
/// kind takes ([partKinds]).
typedef Part = Map<String, Object?>;

/// The statuses a trait can have, as the server names them, and as the app
/// shows them.
const traitStatuses = {
  'active': 'Active',
  'off': 'Off',
  'archived': 'Archived',
};

/// A part kind's name, what it rates, and its fields: (field, label,
/// whether it's required, its default as shown).
typedef PartKind = ({
  String label,
  String hint,
  List<({String field, String label, bool required, String? hint})> fields,
});

const _window = (
  field: 'window_days',
  label: 'Window, in days',
  required: false,
  hint: "the measure's",
);
const _target = (field: 'target', label: 'Target', required: false, hint: '1');

/// The kinds of part, as the server names them (its utilities/traits.py's
/// PART_KINDS), each with the fields the app edits.
const partKinds = <String, PartKind>{
  'prep': (
    label: 'Preparation',
    hint: 'Events done for them while they weren\'t there, in the window.',
    fields: [_target, _window],
  ),
  'prep_regularity': (
    label: 'Regular preparation',
    hint: 'The share of recent weeks with something done for them.',
    fields: [(field: 'weeks', label: 'Weeks', required: false, hint: '4')],
  ),
  'continuity': (
    label: 'Continuity',
    hint:
        'The last event with them was recent, and the next is planned soon: '
        '100 for both, 50 for one, 0 for neither.',
    fields: [
      (
        field: 'last_within_days',
        label: 'Last within, days',
        required: false,
        hint: '14',
      ),
      (
        field: 'next_within_days',
        label: 'Next within, days',
        required: false,
        hint: '14',
      ),
    ],
  ),
  'together_creative': (
    label: 'Made something together',
    hint: 'Events with them that were creative enough, in the window.',
    fields: [
      _target,
      (
        field: 'min_creative',
        label: 'At least creative',
        required: false,
        hint: '2',
      ),
      _window,
    ],
  ),
  'novelty': (
    label: 'Something new',
    hint: 'Events with them where something was new, in the window.',
    fields: [_target, _window],
  ),
  'effort_paid': (
    label: 'Effort paid',
    hint: 'Minutes × (1 + effort) of events with and for them, in the window.',
    fields: [
      (
        field: 'target',
        label: 'Target, effort-minutes',
        required: true,
        hint: null,
      ),
      _window,
    ],
  ),
  'attention': (
    label: 'Attention',
    hint: 'The mean attention (0-3) of events with them, in the window.',
    fields: [_window],
  ),
  'judgment': (
    label: 'Judgment',
    hint: 'Judged against a rubric in the reflection.',
    fields: [(field: 'rubric', label: 'Rubric', required: true, hint: null)],
  ),
  'count': (
    label: 'Number of events',
    hint: "How many of the goal's events, against a target.",
    fields: [
      (field: 'target', label: 'Target', required: true, hint: null),
      (
        field: 'interval_days',
        label: 'Over, in days',
        required: false,
        hint: 'the window',
      ),
      (
        field: 'zero_at_days',
        label: 'Zero at, in days',
        required: false,
        hint: null,
      ),
      (field: 'noun', label: "What's counted", required: false, hint: 'events'),
    ],
  ),
  'duration': (
    label: 'Time spent',
    hint: "Minutes of the goal's events, against a target.",
    fields: [
      (
        field: 'target_min',
        label: 'Target, minutes',
        required: true,
        hint: null,
      ),
      (
        field: 'interval_days',
        label: 'Over, in days',
        required: false,
        hint: 'the window',
      ),
      (
        field: 'zero_at_days',
        label: 'Zero at, in days',
        required: false,
        hint: null,
      ),
    ],
  ),
  'follow_through': (
    label: 'Follow-through',
    hint: "The goal's cancelled events cost points; kept ones win them back.",
    fields: [
      (
        field: 'penalty',
        label: 'Lost per cancellation',
        required: false,
        hint: '25',
      ),
      (
        field: 'recovery',
        label: 'Won back per day kept',
        required: false,
        hint: '25',
      ),
      (
        field: 'look_back_days',
        label: 'Over, in days',
        required: false,
        hint: '30',
      ),
    ],
  ),
};

/// What's wrong with [trait], in a sentence, or null if it's fine: the
/// checks the server's `trait_problems` makes, so the editor can say so
/// before saving (the server refuses it anyway, saying why).
String? traitProblem(Trait trait) {
  if (trait.name.trim().isEmpty) return 'Give it a name.';
  if (trait.name.length > 50) return 'Its name can be at most 50 characters.';
  if (!traitStatuses.containsKey(trait.status)) return 'Pick a status.';
  if (trait.parts.isEmpty) return 'Give it at least one part.';
  for (final (i, part) in trait.parts.indexed) {
    if (partProblem(part) case final problem?) return 'Part ${i + 1}: $problem';
  }
  return null;
}

/// What's wrong with [part], in a sentence, or null if it's fine.
String? partProblem(Part part) {
  final kind = partKinds[part['kind']];
  if (kind == null) return 'pick a kind.';
  bool positive(Object? n) => n is num && n > 0;
  final weight = part['weight'];
  if (weight != null && (weight is! num || weight < 0)) {
    return 'the weight must be 0 or more.';
  }
  for (final field in kind.fields) {
    final value = part[field.field];
    if (value == null) {
      if (field.required) return '${field.label.toLowerCase()} is needed.';
      continue;
    }
    switch (field.field) {
      case 'rubric' || 'noun':
        if (value is! String || value.trim().isEmpty) {
          return '${field.label.toLowerCase()} must be some text.';
        }
      case 'weeks' || 'look_back_days':
        if (value is! int || value < 1) {
          return '${field.label.toLowerCase()} must be a whole number, 1 or more.';
        }
      case 'min_creative':
        if (value is! int || value < 1 || value > 3) {
          return 'at least creative must be 1, 2 or 3.';
        }
      default:
        if (!positive(value)) {
          return '${field.label.toLowerCase()} must be above 0.';
        }
    }
  }
  final zeroAt = part['zero_at_days'];
  if (zeroAt is num && zeroAt <= ((part['interval_days'] as num?) ?? 0)) {
    return '"zero at" must be more days than it looks back.';
  }
  return null;
}

/// One trait's score of one day: the mean of its scores across the goals
/// rated by it, mirroring the server's `TraitDay`.
class TraitDay {
  const TraitDay({
    required this.traitId,
    required this.name,
    required this.day,
    required this.score,
    this.goals = const {},
  });

  final String traitId;
  final String name;

  /// e.g. "2026-10-01".
  final String day;
  final int score;

  /// Each goal's score of it, by goal id.
  final Map<String, int> goals;

  factory TraitDay.fromJson(Map<String, dynamic> json) => TraitDay(
    traitId: json['trait_id'] as String,
    name: json['name'] as String? ?? json['trait_id'] as String,
    day: json['day'] as String,
    score: (json['score'] as num).round(),
    goals: {
      for (final g in json['goals'] as List? ?? const [])
        if (g is Map) '${g['goal_id']}': (g['score'] as num).round(),
    },
  );
}

/// How a goal's traits measure rates one day, part by part: the server's
/// `explain_traits`.
class TraitsRating {
  const TraitsRating({
    this.rating,
    this.explanation,
    this.traits = const [],
    this.leftOut = const [],
    this.day,
  });

  /// 0-100; null for a skip.
  final int? rating;
  final String? explanation;
  final List<TraitScore> traits;

  /// Traits its measure names that aren't rated: off, archived or unknown.
  final List<String> leftOut;
  final String? day;

  factory TraitsRating.fromJson(Map<String, dynamic> json) => TraitsRating(
    rating: json['rating'] is num ? (json['rating'] as num).round() : null,
    explanation: json['explanation'] as String?,
    traits: [
      for (final t in json['traits'] as List? ?? const [])
        if (t is Map) TraitScore.fromJson(t.cast()),
    ],
    leftOut: [for (final id in json['left_out'] as List? ?? const []) '$id'],
    day: json['day'] as String?,
  );
}

class TraitScore {
  const TraitScore({
    required this.traitId,
    required this.name,
    this.weight = 1,
    this.score,
    this.parts = const [],
  });

  final String traitId;
  final String name;
  final num weight;

  /// Null if no part had anything to rate it by.
  final int? score;
  final List<PartScore> parts;

  factory TraitScore.fromJson(Map<String, dynamic> json) => TraitScore(
    traitId: json['trait_id'] as String,
    name: json['name'] as String? ?? json['trait_id'] as String,
    weight: json['weight'] as num? ?? 1,
    score: json['score'] is num ? (json['score'] as num).round() : null,
    parts: [
      for (final p in json['parts'] as List? ?? const [])
        if (p is Map) PartScore.fromJson(p.cast()),
    ],
  );
}

class PartScore {
  const PartScore({
    required this.key,
    required this.kind,
    this.weight = 1,
    this.score,
    this.said = '',
    this.eventIds = const [],
    this.rubric,
  });

  /// Its name within its trait: its kind, or "kind#2".
  final String key;
  final String kind;
  final num weight;

  /// Null when there's nothing to rate it by, or for a judgment not made.
  final int? score;

  /// How it was reached, in a line.
  final String said;

  /// The events behind it.
  final List<String> eventIds;
  final String? rubric;

  factory PartScore.fromJson(Map<String, dynamic> json) => PartScore(
    key: json['key'] as String,
    kind: json['kind'] as String,
    weight: json['weight'] as num? ?? 1,
    score: json['score'] is num ? (json['score'] as num).round() : null,
    said: json['said'] as String? ?? '',
    eventIds: [for (final id in json['event_ids'] as List? ?? const []) '$id'],
    rubric: json['rubric'] as String?,
  );
}

/// One activity or place in a goal's history digest.
class DigestEntry {
  const DigestEntry({
    required this.label,
    required this.count,
    required this.first,
    required this.last,
  });

  final String label;
  final int count;

  /// e.g. "2026-04-10".
  final String first;
  final String last;

  factory DigestEntry.fromJson(Map<String, dynamic> json) => DigestEntry(
    label: json['label'] as String,
    count: (json['count'] as num).round(),
    first: json['first'] as String,
    last: json['last'] as String,
  );
}

/// A goal's history: its events' activities and places, with how often
/// and when, what matters to them, and its events with their facets --
/// the server's `get_goal_digest`.
class GoalDigest {
  const GoalDigest({
    required this.goalId,
    this.windowDays = 180,
    this.eventsCounted = 0,
    this.withFacets = 0,
    this.activities = const [],
    this.places = const [],
    this.whatMatters,
    this.events = const [],
  });

  final String goalId;
  final int windowDays;
  final int eventsCounted;
  final int withFacets;
  final List<DigestEntry> activities;
  final List<DigestEntry> places;

  /// Its description's "What matters to them" section, if it has one.
  final String? whatMatters;

  /// Its events, oldest first, as the server sent them (each a
  /// `PublicEvent`, with `facets`).
  final List<Map<String, dynamic>> events;

  factory GoalDigest.fromJson(Map<String, dynamic> json) => GoalDigest(
    goalId: json['goal_id'] as String,
    windowDays: (json['window_days'] as num?)?.round() ?? 180,
    eventsCounted: (json['events_counted'] as num?)?.round() ?? 0,
    withFacets: (json['with_facets'] as num?)?.round() ?? 0,
    activities: [
      for (final e in json['activities'] as List? ?? const [])
        if (e is Map) DigestEntry.fromJson(e.cast()),
    ],
    places: [
      for (final e in json['places'] as List? ?? const [])
        if (e is Map) DigestEntry.fromJson(e.cast()),
    ],
    whatMatters: json['what_matters'] as String?,
    events: [
      for (final e in json['events'] as List? ?? const [])
        if (e is Map) e.cast<String, dynamic>(),
    ],
  );

  /// Facets of each of [events], by event id.
  Map<String, Facets> get facetsByEvent => {
    for (final e in events) '${e['id']}': ?Facets.fromJson(e['facets']),
  };
}

/// The heading of a person goal's section of what matters to them, in its
/// description.
const whatMattersHeading = 'What matters to them';

/// [description] with its "What matters to them" section's text replaced
/// by [section] -- added at the end, under a level-2 heading, if it had
/// none.
String withWhatMatters(String description, String section) {
  final lines = description.split('\n');
  final heading = RegExp(r'^(#{1,6})\s+(.*?)\s*#*\s*$');
  for (var i = 0; i < lines.length; i++) {
    final match = heading.firstMatch(lines[i]);
    if (match == null ||
        match.group(2)!.toLowerCase() != whatMattersHeading.toLowerCase()) {
      continue;
    }
    final level = match.group(1)!.length;
    var end = lines.length;
    for (var j = i + 1; j < lines.length; j++) {
      final other = heading.firstMatch(lines[j]);
      if (other != null && other.group(1)!.length <= level) {
        end = j;
        break;
      }
    }
    return [
      ...lines.sublist(0, i + 1),
      '',
      section.trim(),
      if (end < lines.length) '',
      ...lines.sublist(end),
    ].join('\n').trimRight();
  }
  final before = description.trimRight();
  return [
    if (before.isNotEmpty) ...[before, ''],
    '## $whatMattersHeading',
    '',
    section.trim(),
  ].join('\n');
}
