import 'person.dart';
import 'share.dart';

/// What compaction established about an event, kept in its private
/// properties, mirroring the Time Tracker MCP server's `Facts` (its
/// facts.rs): where it was, who was there with the user, who it
/// was done for while they weren't there, and a subjective note on each
/// person who was there ("self" for the user) -- and whether it's a
/// [commute]. Every field is optional.
/// What was done at it isn't here: that's its actions, which set its
/// label. They're saved whole through `update_event`.
///
/// A person or place can take a share of the event ([PersonShare],
/// [LocationShare]): the ids are in [withIds], [forIds] and
/// [locationIds] all the same, and those with a share have it in
/// [withSplits], [forSplits] or [locationSplits].
class Facts {
  const Facts({
    this.locationIds = const [],
    this.withIds = const [],
    this.forIds = const [],
    this.notes = const {},
    this.commute = false,
    this.locationSplits = const {},
    this.withSplits = const {},
    this.forSplits = const {},
  });

  /// The shares of those in [locationIds], [withIds] and [forIds] that
  /// have one -- minutes or a percent -- by id.
  final Map<String, LocationShare> locationSplits;
  final Map<String, PersonShare> withSplits;
  final Map<String, PersonShare> forSplits;

  /// The places it was, and how much of it each takes.
  List<LocationShare> get locationShares => [
    for (final id in locationIds) locationSplits[id] ?? LocationShare(id),
  ];

  /// The people with the user, and how much of it each takes.
  List<PersonShare> get withShares => [
    for (final id in withIds) withSplits[id] ?? PersonShare(id),
  ];

  /// The people it was for, and how much of it each takes.
  List<PersonShare> get forShares => [
    for (final id in forIds) forSplits[id] ?? PersonShare(id),
  ];

  /// These, with what's given changed: each place and person kept keeps
  /// the share it had.
  Facts copyWith({
    List<String>? locationIds,
    List<String>? withIds,
    List<String>? forIds,
    Map<String, String>? notes,
    bool? commute,
    Map<String, LocationShare>? locationSplits,
    Map<String, PersonShare>? withSplits,
    Map<String, PersonShare>? forSplits,
  }) {
    Map<String, S> kept<S>(Map<String, S> splits, List<String> ids) => {
      for (final MapEntry(:key, :value) in splits.entries)
        if (ids.contains(key)) key: value,
    };
    final (where, with_, for_) = (
      locationIds ?? this.locationIds,
      withIds ?? this.withIds,
      forIds ?? this.forIds,
    );
    return Facts(
      locationIds: where,
      withIds: with_,
      forIds: for_,
      notes: notes ?? this.notes,
      commute: commute ?? this.commute,
      locationSplits: kept(locationSplits ?? this.locationSplits, where),
      withSplits: kept(withSplits ?? this.withSplits, with_),
      forSplits: kept(forSplits ?? this.forSplits, for_),
    );
  }

  /// [splits] with [share] set: kept if it has minutes or a percent, left
  /// out if it has neither.
  static Map<String, S> withSplit<S extends Share>(
    Map<String, S> splits,
    S share,
  ) => {
    for (final MapEntry(:key, :value) in splits.entries)
      if (key != share.id) key: value,
    if (!share.whole) share.id: share,
  };

  /// Where it was: the ids of the locations it was at, usually one;
  /// several when it moved between them.
  final List<String> locationIds;

  /// The people there with the user: never [selfPersonId], who's at every
  /// event.
  final List<String> withIds;

  /// The people it was done for, who weren't there: never also in
  /// [withIds].
  final List<String> forIds;

  /// A subjective note on each person who was there, by person id:
  /// [selfPersonId] for the user, or one of [withIds].
  final Map<String, String> notes;

  /// Whether it's a commute: getting from one place to another, by its
  /// action ("Drive"). Marked so, rather than known by its action, so a
  /// walk for its own sake is never taken for one.
  final bool commute;

  bool get isEmpty =>
      locationIds.isEmpty &&
      withIds.isEmpty &&
      forIds.isEmpty &&
      notes.isEmpty &&
      !commute;

  /// These, but a commute or not as [commute] says.
  Facts withCommute(bool commute) => copyWith(commute: commute);

  /// Everyone it involves, with them or for them, each once.
  List<String> get personIds => {...withIds, ...forIds}.toList();

  /// From a `PublicEvent`'s `facts`; null for none.
  static Facts? fromJson(Object? json) {
    if (json is! Map) return null;
    final where = sharesFromJson(
      json['location_ids'],
      'location_id',
      LocationShare.new,
    );
    final with_ = sharesFromJson(
      json['with_ids'],
      'person_id',
      PersonShare.new,
    );
    final for_ = sharesFromJson(json['for_ids'], 'person_id', PersonShare.new);
    Map<String, S> splits<S extends Share>(List<S> shares) => {
      for (final s in shares)
        if (!s.whole) s.id: s,
    };
    String? text(Object? value) =>
        value is String && value.trim().isNotEmpty ? value : null;
    return Facts(
      locationIds: [for (final s in where) s.id],
      withIds: [for (final s in with_) s.id],
      forIds: [for (final s in for_) s.id],
      locationSplits: splits(where),
      withSplits: splits(with_),
      forSplits: splits(for_),
      notes: {
        for (final MapEntry(:key, :value)
            in (json['notes'] as Map? ?? const {}).entries)
          '$key': ?text(value),
      },
      commute: json['commute'] == true,
    );
  }

  /// As `update_event` takes them, leaving out what's unset.
  Map<String, Object?> toJson() => {
    if (locationIds.isNotEmpty)
      'location_ids': [for (final s in locationShares) s.toJson()],
    if (withIds.isNotEmpty)
      'with_ids': [for (final s in withShares) s.toJson()],
    if (forIds.isNotEmpty) 'for_ids': [for (final s in forShares) s.toJson()],
    if (notes.isNotEmpty) 'notes': notes,
    if (commute) 'commute': true,
  };

  /// What's wrong with them, as the server checks it, or null if they're
  /// fine.
  String? get problem {
    if (withIds.contains(selfPersonId)) {
      return "You're at every event: you're never one of those with you.";
    }
    if (withIds.any(forIds.contains)) {
      return 'Someone can be there, or have it done for them while they '
          "weren't, but not both.";
    }
    final absent = notes.keys.where(
      (id) => id != selfPersonId && !withIds.contains(id),
    );
    if (absent.isNotEmpty) {
      return 'Notes are only for those who were there.';
    }
    return null;
  }

  /// In a line, e.g. "With Sam · For Priya · @ Home, Park"; people named
  /// from [personNames], and the locations from [locationNames].
  String describe([
    Map<String?, String> personNames = const {},
    Map<String?, String> locationNames = const {},
  ]) {
    String names(List<String> ids) =>
        ids.map((id) => personNames[id] ?? id).join(', ');
    return [
      if (withIds.isNotEmpty) 'With ${names(withIds)}',
      if (forIds.isNotEmpty) 'For ${names(forIds)}',
      if (locationIds.isNotEmpty)
        '@ ${locationIds.map((id) => locationNames[id] ?? id).join(', ')}',
    ].join(' · ');
  }

  @override
  bool operator ==(Object other) =>
      other is Facts &&
      _sameList(locationIds, other.locationIds) &&
      _sameList(withIds, other.withIds) &&
      _sameList(forIds, other.forIds) &&
      commute == other.commute &&
      _sameList(locationShares, other.locationShares) &&
      _sameList(withShares, other.withShares) &&
      _sameList(forShares, other.forShares) &&
      notes.length == other.notes.length &&
      notes.entries.every((e) => other.notes[e.key] == e.value);

  @override
  int get hashCode => Object.hash(
    Object.hashAll(locationIds),
    Object.hashAll(withIds),
    Object.hashAll(forIds),
    Object.hashAll([
      ...locationSplits.values,
      ...withSplits.values,
      ...forSplits.values,
    ]),
    Object.hashAllUnordered(notes.entries.map((e) => (e.key, e.value))),
    commute,
  );
}

/// The assistant's judgment of one event, for one person, against one
/// judgment part of a trait: a rating on its scale, and a line of
/// reasoning. The server keeps them on the event, as `judgments`:
/// {person id: {trait id: {part key: {rating, scale, reasoning}}}}.
class Judgment {
  const Judgment({
    this.eventId,
    required this.personId,
    required this.traitId,
    required this.part,
    required this.rating,
    this.scale,
    this.reasoning,
  });

  /// The event judged; left out in an event's own judgments.
  final String? eventId;
  final String personId;
  final String traitId;

  /// The part's key within its trait: "judgment", or "judgment#2".
  final String part;
  final int rating;

  /// The highest rating its part allowed when it was made.
  final int? scale;
  final String? reasoning;

  @override
  bool operator ==(Object other) =>
      other is Judgment &&
      eventId == other.eventId &&
      personId == other.personId &&
      traitId == other.traitId &&
      part == other.part &&
      rating == other.rating &&
      scale == other.scale &&
      reasoning == other.reasoning;

  @override
  int get hashCode =>
      Object.hash(eventId, personId, traitId, part, rating, scale, reasoning);
}

/// An event's `judgments`, flattened, for event [eventId] if given.
List<Judgment> judgmentsFromJson(Object? json, {String? eventId}) => [
  if (json is Map)
    for (final MapEntry(key: person, value: traits) in json.entries)
      if (traits is Map)
        for (final MapEntry(key: trait, value: parts) in traits.entries)
          if (parts is Map)
            for (final MapEntry(key: part, value: judged) in parts.entries)
              if (judged case {'rating': final num rating})
                Judgment(
                  eventId: eventId,
                  personId: '$person',
                  traitId: '$trait',
                  part: '$part',
                  rating: rating.round(),
                  scale: (judged['scale'] as num?)?.round(),
                  reasoning: judged['reasoning'] as String?,
                ),
];

/// [judgments] as an event keeps them.
Map<String, Object?> judgmentsToJson(Iterable<Judgment> judgments) {
  final json = <String, Map<String, Map<String, Object?>>>{};
  for (final j in judgments) {
    ((json[j.personId] ??= {})[j.traitId] ??= {})[j.part] = {
      'rating': j.rating,
      'scale': ?j.scale,
      'reasoning': ?j.reasoning,
    };
  }
  return json;
}

bool _sameList(List<Object> a, List<Object> b) =>
    a.length == b.length &&
    [for (var i = 0; i < a.length; i++) a[i] == b[i]].every((same) => same);
