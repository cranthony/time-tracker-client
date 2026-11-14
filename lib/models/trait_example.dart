/// A story of someone embodying a trait well -- the user, someone they
/// know, or anyone at all: when it happened, who did it, what they did,
/// and why it embodies the trait. Kept by the server
/// (`get_trait_examples`), each on one trait, and linked, if it was one,
/// to the event it happened at.
class TraitExample {
  const TraitExample({
    this.id,
    required this.traitId,
    required this.when,
    this.personId,
    this.who,
    required this.what,
    required this.why,
    this.eventId,
    this.version,
  });

  /// The server's; null until it's created.
  final String? id;
  final String traitId;

  /// The day it happened, `YYYY-MM-DD`.
  final String when;

  /// Who did it, if they're in People: a person, a community, or `self`.
  final String? personId;

  /// Who did it, in words, for someone not in People. It has this or
  /// [personId], or both.
  final String? who;

  /// What they did.
  final String what;

  /// Why it embodies the trait.
  final String why;

  /// The event it happened at, if it was one.
  final String? eventId;

  /// The server's version of it, to save a change only to what was read.
  final int? version;

  factory TraitExample.fromJson(Map<String, dynamic> json) => TraitExample(
    id: json['id'] as String?,
    traitId: json['trait_id'] as String? ?? '',
    when: json['when'] as String? ?? '',
    personId: _text(json['person_id']),
    who: _text(json['who']),
    what: json['what'] as String? ?? '',
    why: json['why'] as String? ?? '',
    eventId: _text(json['event_id']),
    version: (json['version'] as num?)?.toInt(),
  );

  /// As `create_trait_example` takes it.
  Map<String, Object?> toJson() => {
    'id': ?id,
    'trait_id': traitId,
    'when': when,
    'person_id': ?personId,
    'who': ?who,
    'what': what,
    'why': why,
    'event_id': ?eventId,
  };

  /// What changed from [before] to this, as `update_trait_example` takes
  /// it: a field cleared is null, for its `clear_fields`.
  Map<String, Object?> changesFrom(TraitExample before) => {
    if (traitId != before.traitId) 'trait_id': traitId,
    if (when != before.when) 'when': when,
    if (personId != before.personId) 'person_id': personId,
    if (who != before.who) 'who': who,
    if (what != before.what) 'what': what,
    if (why != before.why) 'why': why,
    if (eventId != before.eventId) 'event_id': eventId,
  };

  static String? _text(Object? value) => switch (value) {
    final String text when text.trim().isNotEmpty => text,
    _ => null,
  };
}

/// The fields of a trait example that can be cleared.
const clearableExampleFields = {'person_id', 'who', 'event_id'};

/// The longest a story's what and why can be, in characters.
const exampleTextMaxLength = 2000;

/// What's wrong with [example], as the server would refuse it, or null if
/// it's fine.
String? traitExampleProblem(TraitExample example) {
  if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(example.when)) {
    return 'Say when it happened.';
  }
  if (example.personId == null && (example.who?.trim().isEmpty ?? true)) {
    return 'Say who did it.';
  }
  if (example.what.trim().isEmpty) return 'Say what they did.';
  if (example.why.trim().isEmpty) return 'Say why it embodies the trait.';
  if (example.what.length > exampleTextMaxLength ||
      example.why.length > exampleTextMaxLength) {
    return 'What they did, and why, can each be at most '
        '$exampleTextMaxLength characters.';
  }
  return null;
}

/// [examples], newest first: by when they happened, latest first.
List<TraitExample> newestFirst(Iterable<TraitExample> examples) =>
    [...examples]..sort((a, b) => b.when.compareTo(a.when));
