import 'facets.dart';

/// A trait: how the user wants to be -- adventurous, thoughtful, present
/// -- each rated for each person (Self included) from its [parts]. None
/// is built in: every trait, and every part, is the user's to define.
/// Its score of a person's day is the weighted mean of its parts' scores.
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

/// A part kind's name, what it rates, and its plain fields: (field,
/// label, whether it's required, its default as shown). A facet's
/// ratings, engagement and primitives are edited apart from these.
typedef PartKind = ({
  String label,
  String hint,
  List<({String field, String label, bool required, String? hint})> fields,
});

const _window = (
  field: 'window_days',
  label: 'Window, in days',
  required: false,
  hint: '30',
);

/// The part fields that are text, not numbers.
const textFields = {'rubric', 'noun', 'action_id'};

/// The kinds of part, as the server names them, each with the fields the
/// app edits.
const partKinds = <String, PartKind>{
  'facet': (
    label: 'Facet',
    hint:
        'Claude rates each event with them against a rubric during '
        'reflection, on a scale you define; the part scores the mean '
        'rating over the window, as a share of the top rating.',
    fields: [
      (field: 'rubric', label: 'Rubric', required: true, hint: null),
      _window,
    ],
  ),
  'count': (
    label: 'Number of events',
    hint:
        'How many events with them there were, against a target: with an '
        'action, only events of that action -- a cadence, like a call every '
        'week.',
    fields: [
      (field: 'action_id', label: 'Action', required: false, hint: 'any'),
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
    hint:
        'Minutes of events with them, against a target: with an action, '
        'only events of that action.',
    fields: [
      (field: 'action_id', label: 'Action', required: false, hint: 'any'),
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
  'follow_through': (
    label: 'Follow-through',
    hint: 'Cancelled events with them cost points; kept ones win them back.',
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

/// How a facet is engaged: the events done with a person (they were
/// there), or for them (they may not have been).
const facetEngagements = {'with': 'With them', 'for': 'For them'};

/// What a facet primitive gives Claude to judge an event by: its label,
/// what it is, and whether it looks back over a number of days.
typedef FacetPrimitive = ({String label, String hint, bool lookback});

/// The primitives a facet can be judged from, as the server names them.
const facetPrimitives = <String, FacetPrimitive>{
  'action': (
    label: 'Action',
    hint: 'What was done at the event',
    lookback: false,
  ),
  'action_history': (
    label: 'Action history',
    hint: 'What was done at earlier events with them',
    lookback: true,
  ),
  'location': (label: 'Location', hint: 'Where the event was', lookback: false),
  'location_history': (
    label: 'Location history',
    hint: 'Where earlier events with them were',
    lookback: true,
  ),
  'general_notes': (
    label: 'General notes',
    hint: 'What was noted about the event',
    lookback: false,
  ),
  'person_notes': (
    label: 'Person notes',
    hint:
        "Notes on the person: on you for a \"for\" facet, on them for a "
        '"with" one',
    lookback: false,
  ),
};

/// How far a history primitive looks back unless it says.
const defaultLookbackDays = 90;

/// A facet's rating scale: each score, lowest first, and what it means.
typedef FacetRating = ({int score, String label});

/// [part]'s rating scale, lowest first, if it's a facet with one.
List<FacetRating> facetRatings(Part part) => [
  for (final r in part['ratings'] as List? ?? const [])
    if (r case {'score': final num score, 'label': final String label})
      (score: score.round(), label: label),
]..sort((a, b) => a.score.compareTo(b.score));

/// [part]'s primitives, as `{name: lookback days}`: null for one that
/// doesn't look back.
Map<String, int?> facetPrimitivesOf(Part part) => {
  for (final p in part['primitives'] as List? ?? const [])
    if (p case {'name': final String name})
      name: facetPrimitives[name]?.lookback ?? false
          ? ((p['lookback_days'] as num?)?.round() ?? defaultLookbackDays)
          : null,
};

/// [ratings] as a facet part keeps them.
List<Map<String, Object?>> facetRatingsJson(List<FacetRating> ratings) => [
  for (final r in ratings) {'score': r.score, 'label': r.label},
];

/// [primitives] as a facet part keeps them.
List<Map<String, Object?>> facetPrimitivesJson(Map<String, int?> primitives) =>
    [
      for (final MapEntry(:key, :value) in primitives.entries)
        {'name': key, 'lookback_days': ?value},
    ];

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
      case 'rubric' || 'noun' || 'action_id':
        if (value is! String || value.trim().isEmpty) {
          return '${field.label.toLowerCase()} must be some text.';
        }
      case 'look_back_days':
        if (value is! int || value < 1) {
          return '${field.label.toLowerCase()} must be a whole number, 1 or more.';
        }
      default:
        if (!positive(value)) {
          return '${field.label.toLowerCase()} must be above 0.';
        }
    }
  }
  if (part['kind'] == 'facet') {
    if (!facetEngagements.containsKey(part['engagement'])) {
      return 'pick whether it rates events with them or for them.';
    }
    final raw = part['ratings'] as List? ?? const [];
    if (raw.any((r) => r is! Map || r['score'] is! int)) {
      return 'each rating needs a whole-number score.';
    }
    final ratings = facetRatings(part);
    if (ratings.length < 2) return 'give it at least two ratings.';
    if (ratings.map((r) => r.score).toSet().length != ratings.length) {
      return 'each rating needs a score of its own.';
    }
    if (ratings.any((r) => r.label.trim().isEmpty)) {
      return 'say what each rating means.';
    }
    if (ratings.first.score < 0) return 'ratings start at 0 or more.';
    final primitives = facetPrimitivesOf(part);
    if (primitives.isEmpty) return 'pick at least one primitive.';
    if (primitives.keys.any((p) => !facetPrimitives.containsKey(p))) {
      return 'it has a primitive the app doesn\'t know.';
    }
    for (final p in part['primitives'] as List? ?? const []) {
      final days = p is Map ? p['lookback_days'] : null;
      if (days != null) {
        if (days is! int || days < 1) {
          return 'a lookback must be a whole number of days, 1 or more.';
        }
      }
    }
  }
  final zeroAt = part['zero_at_days'];
  if (zeroAt is num && zeroAt <= ((part['interval_days'] as num?) ?? 0)) {
    return '"zero at" must be more days than it looks back.';
  }
  return null;
}

/// [part] in a line: "Facet: Was this activity or place new? (0-3, with
/// them)", "Call every 7 days", "Continuity: last within 7 days, next
/// within 7". [actionNames] names the actions a cadence counts.
String describePart(Part part, [Map<String?, String> actionNames = const {}]) {
  String days(Object? n) => n == 1 ? 'day' : '$n days';
  final target = part['target'] ?? 1;
  final action = switch (part['action_id']) {
    final String id => (actionNames[id] ?? id).toLowerCase(),
    _ => null,
  };
  return switch (part['kind']) {
    'facet' => () {
      final ratings = facetRatings(part);
      final scale = ratings.isEmpty
          ? ''
          : '${ratings.first.score}-${ratings.last.score}, ';
      final engagement = part['engagement'] == 'for' ? 'for them' : 'with them';
      return 'Facet: ${part['rubric'] ?? ''} ($scale$engagement)';
    }(),
    'count' => [
      '${target == 1 ? '' : '$target × '}${action ?? 'any event with them'}',
      'every ${days(part['interval_days'] ?? 'window')}',
      if (part['zero_at_days'] case final zero?) '(0 at $zero days)',
    ].join(' '),
    'duration' =>
      '${part['target_min']} min of ${action ?? 'events'} '
          'every ${days(part['interval_days'] ?? 'window')}',
    'continuity' =>
      'Continuity: last within ${days(part['last_within_days'] ?? 14)}, '
          'next within ${days(part['next_within_days'] ?? 14)}',
    final kind => partKinds[kind]?.label ?? '$kind',
  };
}

/// One trait's score of one day: the mean of its scores across the people
/// rated by it.
class TraitDay {
  const TraitDay({
    required this.traitId,
    required this.name,
    required this.day,
    required this.score,
    this.people = const {},
  });

  final String traitId;
  final String name;

  /// e.g. "2026-10-01".
  final String day;
  final int score;

  /// Each person's score of it, by person id.
  final Map<String, int> people;

  factory TraitDay.fromJson(Map<String, dynamic> json) => TraitDay(
    traitId: json['trait_id'] as String,
    name: json['name'] as String? ?? json['trait_id'] as String,
    day: json['day'] as String,
    score: (json['score'] as num).round(),
    people: {
      for (final p in json['people'] as List? ?? const [])
        if (p is Map) '${p['person_id']}': (p['score'] as num).round(),
    },
  );
}

/// How a person's traits rate one day, part by part: the server's
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

  /// Traits that aren't rated for them: off, archived, or weighed 0.
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
    this.judgments = const [],
  });

  /// Its name within its trait: its kind, or "kind#2".
  final String key;
  final String kind;
  final num weight;

  /// Null when there's nothing to rate it by.
  final int? score;

  /// How it was reached, in a line.
  final String said;

  /// The events behind it.
  final List<String> eventIds;

  /// A facet's rubric.
  final String? rubric;

  /// A facet's ratings of each event behind it, as Claude judged them.
  final List<FacetJudgment> judgments;

  factory PartScore.fromJson(Map<String, dynamic> json) => PartScore(
    key: json['key'] as String,
    kind: json['kind'] as String,
    weight: json['weight'] as num? ?? 1,
    score: json['score'] is num ? (json['score'] as num).round() : null,
    said: json['said'] as String? ?? '',
    eventIds: [for (final id in json['event_ids'] as List? ?? const []) '$id'],
    rubric: json['rubric'] as String?,
    judgments: [
      for (final j in json['judgments'] as List? ?? const [])
        if (j is Map) ?FacetJudgment.fromJson(j.cast()),
    ],
  );
}

/// One action or location in a person's history digest.
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

/// A person's history: the actions done and locations of the events
/// with or for them, with how often and when, and the events themselves
/// -- the server's `get_person_digest`.
class PersonDigest {
  const PersonDigest({
    required this.personId,
    this.windowDays = 180,
    this.eventsCounted = 0,
    this.actions = const [],
    this.locations = const [],
    this.events = const [],
  });

  final String personId;
  final int windowDays;
  final int eventsCounted;
  final List<DigestEntry> actions;
  final List<DigestEntry> locations;

  /// Its events, oldest first, as the server sent them (each a
  /// `PublicEvent`, with `facets`).
  final List<Map<String, dynamic>> events;

  factory PersonDigest.fromJson(Map<String, dynamic> json) => PersonDigest(
    personId: json['person_id'] as String,
    windowDays: (json['window_days'] as num?)?.round() ?? 180,
    eventsCounted: (json['events_counted'] as num?)?.round() ?? 0,
    actions: [
      for (final e in json['actions'] as List? ?? const [])
        if (e is Map) DigestEntry.fromJson(e.cast()),
    ],
    locations: [
      for (final e in json['locations'] as List? ?? const [])
        if (e is Map) DigestEntry.fromJson(e.cast()),
    ],
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
