import '../widgets/durations.dart' show formatMinutes;
import 'facts.dart';

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
/// label, whether it's required, its default as shown). A judgment's
/// ratings and facts, and every part's engagement type, are edited apart
/// from these.
typedef PartKind = ({
  String label,
  String hint,
  List<({String field, String label, bool required, String? hint})> fields,
});

/// The action (or action group) a part counts, if it names one.
const _action = (
  field: 'action',
  label: 'Action',
  required: false,
  hint: 'any',
);

/// The part fields that are text, not numbers.
const textFields = {'rubric', 'noun', 'action'};

/// The kinds of part, as the server names them (its utilities/traits.py's
/// PART_KINDS), each with the fields the app edits.
const partKinds = <String, PartKind>{
  'judgment': (
    label: 'Judgment',
    hint:
        'Claude rates each event against a rubric, on a scale you define, '
        'from the facts it names; the part scores the mean rating as a '
        'share of the top one.',
    fields: [(field: 'rubric', label: 'Rubric', required: true, hint: null)],
  ),
  'count': (
    label: 'Number of events',
    hint:
        'How many events there were, against a target: with an action, '
        'only events of it -- a cadence, like a call every week.',
    fields: [
      _action,
      (field: 'target', label: 'Target', required: true, hint: null),
      (
        field: 'interval_days',
        label: 'Over, in days',
        required: false,
        hint: '30',
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
    hint: 'Time spent at events, against a target: with an action, only its.',
    fields: [
      _action,
      (
        field: 'target_min',
        // Kept in minutes; shown, and entered, in hours and minutes.
        label: 'Target time',
        required: true,
        hint: null,
      ),
      (
        field: 'interval_days',
        label: 'Over, in days',
        required: false,
        hint: '30',
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
        'The last event was recent, and the next is planned soon: 100 for '
        'both, 50 for one, 0 for neither.',
    fields: [
      _action,
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
    hint: 'Cancelled events cost points; kept ones win them back.',
    fields: [
      _action,
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

/// A part's `engagement_type`, as the server names them, and as the app
/// shows them: the events a person was at with the user (the default), or
/// those the user did for them while they weren't there.
const engagementTypes = {'with': 'With them', 'for': 'For them'};

/// What a judgment fact shows Claude about an event: its label, what it
/// is, and whether it looks back over a number of days.
typedef JudgmentFact = ({String label, String hint, bool lookback});

/// The facts a judgment can be made from, as the server names them (its
/// utilities/traits.py's FACTS).
const judgmentFacts = <String, JudgmentFact>{
  'action': (
    label: 'Action',
    hint: 'What was done at the event',
    lookback: false,
  ),
  'action_history': (
    label: 'Action history',
    hint: "What's been done with them before",
    lookback: true,
  ),
  'location': (label: 'Location', hint: 'Where the event was', lookback: false),
  'location_history': (
    label: 'Location history',
    hint: "Where you've been with them before",
    lookback: true,
  ),
  'general_notes': (
    label: 'General notes',
    hint: "The event's own notes",
    lookback: false,
  ),
  'person_notes': (
    label: 'Person notes',
    hint:
        'The notes on the person: yours for a "for" part, theirs for a '
        '"with" one',
    lookback: false,
  ),
  'what_matters': (
    label: 'What matters',
    hint: "What's important to them, as their page says",
    lookback: false,
  ),
};

/// How far a history fact looks back unless it says.
const defaultLookbackDays = 30;

/// A judgment's rating scale: each rating, lowest first, and what it
/// means.
typedef JudgmentRating = ({int score, String label});

/// [part]'s rating scale, lowest first: its `ratings`, {"0": "...", ...}.
List<JudgmentRating> judgmentRatings(Part part) => [
  if (part['ratings'] case final Map ratings)
    for (final MapEntry(:key, :value) in ratings.entries)
      if (value is String && int.tryParse('$key') != null)
        (score: int.parse('$key'), label: value),
]..sort((a, b) => a.score.compareTo(b.score));

/// [part]'s facts, as `{name: lookback days}`: null for one that doesn't
/// look back.
Map<String, int?> judgmentFactsOf(Part part) {
  final facts = <String, int?>{};
  for (final fact in part['facts'] as List? ?? const []) {
    final name = _factName(fact);
    if (name == null) continue;
    facts[name] = judgmentFacts[name]?.lookback ?? false
        ? switch (fact) {
            {'lookback_days': final num days} => days.round(),
            _ => defaultLookbackDays,
          }
        : null;
  }
  return facts;
}

/// A fact's name: it's given as one, or as {"fact": name, ...}.
String? _factName(Object? fact) => switch (fact) {
  final String name => name,
  {'fact': final String name} => name,
  _ => null,
};

/// [ratings] as a judgment keeps them.
Map<String, String> judgmentRatingsJson(List<JudgmentRating> ratings) => {
  for (final r in ratings) '${r.score}': r.label,
};

/// [facts] as a judgment keeps them: a name, or with its lookback.
List<Object> judgmentFactsJson(Map<String, int?> facts) => [
  for (final MapEntry(:key, :value) in facts.entries)
    value == null ? key : {'fact': key, 'lookback_days': value},
];

/// What's wrong with [trait], in a sentence, or null if it's fine: the
/// checks the server's `trait_problems` makes, so the editor can say so
/// before saving (the server refuses it anyway, saying why).
String? traitProblem(Trait trait) {
  if (trait.name.trim().isEmpty) return 'Give it a name.';
  if (trait.name.length > 50) return 'Its name can be at most 50 characters.';
  if (!traitStatuses.containsKey(trait.status)) return 'Pick a status.';
  if (trait.parts.isEmpty) return 'Give it at least one part.';
  return partsProblem(trait.parts);
}

/// What's wrong with the first bad part of [parts], or null if they're
/// fine.
String? partsProblem(List<Part> parts) {
  for (final (i, part) in parts.indexed) {
    if (partProblem(part) case final problem?) return 'Part ${i + 1}: $problem';
  }
  return null;
}

/// What's wrong with [part], in a sentence, or null if it's fine: the
/// checks the server's `part_problems` makes.
String? partProblem(Part part) {
  final kind = partKinds[part['kind']];
  if (kind == null) return 'pick a kind.';
  bool positive(Object? n) => n is num && n > 0;
  final weight = part['weight'];
  if (weight != null && (weight is! num || weight < 0)) {
    return 'the weight must be 0 or more.';
  }
  final engagement = part['engagement_type'];
  if (engagement != null && !engagementTypes.containsKey(engagement)) {
    return 'pick whether it reads events with them or for them.';
  }
  for (final field in kind.fields) {
    final value = part[field.field];
    if (value == null) {
      if (field.required) return '${field.label.toLowerCase()} is needed.';
      continue;
    }
    switch (field.field) {
      case 'rubric' || 'noun' || 'action':
        if (value is! String || value.trim().isEmpty) {
          return '${field.label.toLowerCase()} must be some text.';
        }
      case 'penalty' || 'recovery':
        if (value is! num || value < 0 || value > 100) {
          return '${field.label.toLowerCase()} must be from 0 to 100.';
        }
      default:
        if (!positive(value)) {
          return '${field.label.toLowerCase()} must be above 0.';
        }
    }
  }
  if (part['kind'] == 'judgment') {
    // The editor sends its ratings as a list when two share a score.
    final raw = part['ratings'];
    if (raw is List) return 'each rating needs a score of its own.';
    if (raw is! Map || raw.keys.any((k) => int.tryParse('$k') == null)) {
      return 'each rating needs a whole-number score, from 0.';
    }
    final ratings = judgmentRatings(part);
    if (ratings.any((r) => r.score < 0)) {
      return 'each rating needs a whole-number score, from 0.';
    }
    if (ratings.length < 2) return 'give it at least two ratings.';
    if (ratings.any((r) => r.label.trim().isEmpty)) {
      return 'say what each rating means.';
    }
    final facts = part['facts'] as List? ?? const [];
    if (facts.isEmpty) return 'pick at least one fact to judge by.';
    final names = judgmentFactsOf(part);
    if (names.keys.any((f) => !judgmentFacts.containsKey(f))) {
      return "it has a fact the app doesn't know.";
    }
    for (final fact in facts) {
      final days = fact is Map ? fact['lookback_days'] : null;
      if (days != null && (days is! int || days < 1)) {
        return 'a lookback must be a whole number of days, 1 or more.';
      }
    }
  }
  final zeroAt = part['zero_at_days'];
  if (zeroAt is num && zeroAt <= ((part['interval_days'] as num?) ?? 30)) {
    return '"zero at" must be more days than it looks back.';
  }
  return null;
}

/// [part] in a line: "Judgment: Was this activity or place new? (0-3,
/// with them)", "Call every 7 days", "Continuity: last within 7 days,
/// next within 7". [actionNames] names the action a part counts.
String describePart(Part part, [Map<String?, String> actionNames = const {}]) {
  String days(Object? n) => n == 1 ? 'day' : '$n days';
  final target = part['target'] ?? 1;
  final action = switch (part['action']) {
    final String id => (actionNames[id] ?? id).toLowerCase(),
    _ => null,
  };
  final engagement = part['engagement_type'] == 'for'
      ? 'for them'
      : 'with them';
  return switch (part['kind']) {
    'judgment' => () {
      final ratings = judgmentRatings(part);
      final scale = ratings.isEmpty
          ? ''
          : '${ratings.first.score}-${ratings.last.score}, ';
      return 'Judgment: ${part['rubric'] ?? ''} ($scale$engagement)';
    }(),
    'count' => [
      '${target == 1 ? '' : '$target × '}${action ?? 'any event'}',
      'every ${days(part['interval_days'] ?? 30)}',
      if (part['zero_at_days'] case final zero?) '(0 at $zero days)',
    ].join(' '),
    'duration' =>
      '${switch (part['target_min']) {
            final num minutes => formatMinutes(minutes),
            final other => '$other',
          }} of ${action ?? 'events'} '
          'every ${days(part['interval_days'] ?? 30)}',
    'continuity' =>
      'Continuity${action == null ? '' : ' of $action'}: last within '
          '${days(part['last_within_days'] ?? 14)}, next within '
          '${days(part['next_within_days'] ?? 14)}',
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
}

/// How a person's traits rate one day, part by part (see
/// models/trait_scores.dart).
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

  /// A judgment's rubric.
  final String? rubric;

  /// A judgment's ratings of each event behind it, as Claude made them.
  final List<Judgment> judgments;
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
}

/// A person's history: the actions done and locations of the events
/// with or for them, with how often and when, and the events themselves
/// -- worked out from the events (see models/trait_scores.dart).
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
  /// `PublicEvent`, with its `facts` and `judgments`).
  final List<Map<String, dynamic>> events;
}
