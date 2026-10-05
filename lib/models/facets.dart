/// What happened at an event, kept in its private properties: who it was
/// with and who it was for (person ids), where it was, notes on it and on
/// each person, and Claude's ratings of it against the traits' facets.
/// Every field is optional. What was done at it isn't here: that's its
/// actions, which are its calendar labels. Compaction gathers these on
/// past events; they can be edited here, and are saved whole through
/// `update_event`.
class Facets {
  const Facets({
    this.withPersonIds = const [],
    this.forPersonIds = const [],
    this.location,
    this.notes,
    this.personNotes = const {},
    this.judgments = const [],
  });

  /// The people who were there.
  final List<String> withPersonIds;

  /// The people it was done for, whether or not they were there (a gift,
  /// say, or Self's own practice).
  final List<String> forPersonIds;

  /// Where, a short label, e.g. "the hall".
  final String? location;

  /// What was noted about it in general.
  final String? notes;

  /// Subjective notes on each person there, by person id.
  final Map<String, String> personNotes;

  /// Claude's ratings of it against the traits' facets, for each person;
  /// made in the reflection, never by hand.
  final List<FacetJudgment> judgments;

  bool get isEmpty =>
      withPersonIds.isEmpty &&
      forPersonIds.isEmpty &&
      location == null &&
      notes == null &&
      personNotes.isEmpty &&
      judgments.isEmpty;

  /// Everyone it involves, with them or for them, each once.
  List<String> get personIds => {...withPersonIds, ...forPersonIds}.toList();

  /// From a `PublicEvent`'s `facets`; null for none.
  static Facets? fromJson(Object? json) {
    if (json is! Map) return null;
    List<String> ids(Object? value) => [
      for (final id in value as List? ?? const []) '$id',
    ];
    String? text(Object? value) =>
        value is String && value.trim().isNotEmpty ? value : null;
    return Facets(
      withPersonIds: ids(json['with_person_ids']),
      forPersonIds: ids(json['for_person_ids']),
      location: text(json['location']),
      notes: text(json['notes']),
      personNotes: {
        for (final MapEntry(:key, :value)
            in (json['person_notes'] as Map? ?? const {}).entries)
          '$key': ?text(value),
      },
      judgments: [
        for (final j in json['judgments'] as List? ?? const [])
          if (j is Map) ?FacetJudgment.fromJson(j.cast()),
      ],
    );
  }

  /// As `update_event` takes them, leaving out what's unset.
  Map<String, Object?> toJson() => {
    if (withPersonIds.isNotEmpty) 'with_person_ids': withPersonIds,
    if (forPersonIds.isNotEmpty) 'for_person_ids': forPersonIds,
    'location': ?location,
    'notes': ?notes,
    if (personNotes.isNotEmpty) 'person_notes': personNotes,
    if (judgments.isNotEmpty)
      'judgments': [for (final j in judgments) j.toJson()],
  };

  /// [this] with who, where and the notes replaced: Claude's judgments
  /// are kept, but only for the people still there.
  Facets edited({
    required List<String> withPersonIds,
    required List<String> forPersonIds,
    String? location,
    String? notes,
    Map<String, String> personNotes = const {},
  }) {
    final everyone = {...withPersonIds, ...forPersonIds};
    return Facets(
      withPersonIds: withPersonIds,
      forPersonIds: forPersonIds,
      location: location,
      notes: notes,
      personNotes: {
        for (final MapEntry(:key, :value) in personNotes.entries)
          if (everyone.contains(key)) key: value,
      },
      judgments: [
        for (final j in judgments)
          if (j.personId == null || everyone.contains(j.personId)) j,
      ],
    );
  }

  /// In a line, e.g. "With Sam · For Self · @ the hall"; people named
  /// from [personNames].
  String describe([Map<String?, String> personNames = const {}]) {
    String names(List<String> ids) =>
        ids.map((id) => personNames[id] ?? id).join(', ');
    return [
      if (withPersonIds.isNotEmpty) 'With ${names(withPersonIds)}',
      if (forPersonIds.isNotEmpty) 'For ${names(forPersonIds)}',
      if (location case final where?) '@ $where',
    ].join(' · ');
  }

  @override
  bool operator ==(Object other) =>
      other is Facets &&
      _sameList(withPersonIds, other.withPersonIds) &&
      _sameList(forPersonIds, other.forPersonIds) &&
      location == other.location &&
      notes == other.notes &&
      _sameMap(personNotes, other.personNotes) &&
      _sameList(judgments, other.judgments);

  @override
  int get hashCode => Object.hash(
    Object.hashAll(withPersonIds),
    Object.hashAll(forPersonIds),
    location,
    notes,
    Object.hashAllUnordered(personNotes.entries.map((e) => (e.key, e.value))),
    Object.hashAll(judgments),
  );
}

/// Claude's rating of one event against one trait's facet, for one person
/// (or a named group of them).
class FacetJudgment {
  const FacetJudgment({
    this.eventId,
    this.traitId,
    this.part,
    this.personId,
    required this.rating,
    this.why,
  });

  /// The event judged; in an event's own facets, left out.
  final String? eventId;
  final String? traitId;

  /// The facet's key within its trait: "facet", or "facet#2".
  final String? part;

  /// Who it was judged for: a person or a circle.
  final String? personId;
  final int rating;

  /// Claude's reason, in a line.
  final String? why;

  static FacetJudgment? fromJson(Map<String, dynamic> json) {
    final rating = json['rating'];
    if (rating is! num) return null;
    return FacetJudgment(
      eventId: json['event_id'] as String?,
      traitId: json['trait_id'] as String?,
      part: json['part'] as String?,
      personId: json['person_id'] as String?,
      rating: rating.round(),
      why: json['why'] as String?,
    );
  }

  Map<String, Object?> toJson() => {
    'event_id': ?eventId,
    'trait_id': ?traitId,
    'part': ?part,
    'person_id': ?personId,
    'rating': rating,
    'why': ?why,
  };

  @override
  bool operator ==(Object other) =>
      other is FacetJudgment &&
      eventId == other.eventId &&
      traitId == other.traitId &&
      part == other.part &&
      personId == other.personId &&
      rating == other.rating &&
      why == other.why;

  @override
  int get hashCode =>
      Object.hash(eventId, traitId, part, personId, rating, why);
}

bool _sameList<T>(List<T> a, List<T> b) =>
    a.length == b.length &&
    [for (var i = 0; i < a.length; i++) a[i] == b[i]].every((same) => same);

bool _sameMap(Map<String, String> a, Map<String, String> b) =>
    a.length == b.length && a.entries.every((e) => b[e.key] == e.value);
