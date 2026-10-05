import 'person.dart';

/// What compaction established about an event, kept in its private
/// properties, mirroring the Time Tracker MCP server's `Facts` (its
/// utilities/facts.py): where it was, who was there with the user, who it
/// was done for while they weren't there, and a subjective note on each
/// person who was there ("self" for the user). Every field is optional.
/// What was done at it isn't here: that's its actions, which set its
/// label. They're saved whole through `update_event`.
class Facts {
  const Facts({
    this.locationId,
    this.withIds = const [],
    this.forIds = const [],
    this.notes = const {},
  });

  /// Where it was: a location's id.
  final String? locationId;

  /// The people there with the user: never [selfPersonId], who's at every
  /// event.
  final List<String> withIds;

  /// The people it was done for, who weren't there: never also in
  /// [withIds].
  final List<String> forIds;

  /// A subjective note on each person who was there, by person id:
  /// [selfPersonId] for the user, or one of [withIds].
  final Map<String, String> notes;

  bool get isEmpty =>
      locationId == null && withIds.isEmpty && forIds.isEmpty && notes.isEmpty;

  /// Everyone it involves, with them or for them, each once.
  List<String> get personIds => {...withIds, ...forIds}.toList();

  /// From a `PublicEvent`'s `facts`; null for none.
  static Facts? fromJson(Object? json) {
    if (json is! Map) return null;
    List<String> ids(Object? value) => [
      for (final id in value as List? ?? const []) '$id',
    ];
    String? text(Object? value) =>
        value is String && value.trim().isNotEmpty ? value : null;
    return Facts(
      locationId: text(json['location_id']),
      withIds: ids(json['with_ids']),
      forIds: ids(json['for_ids']),
      notes: {
        for (final MapEntry(:key, :value)
            in (json['notes'] as Map? ?? const {}).entries)
          '$key': ?text(value),
      },
    );
  }

  /// As `update_event` takes them, leaving out what's unset.
  Map<String, Object?> toJson() => {
    'location_id': ?locationId,
    if (withIds.isNotEmpty) 'with_ids': withIds,
    if (forIds.isNotEmpty) 'for_ids': forIds,
    if (notes.isNotEmpty) 'notes': notes,
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

  /// In a line, e.g. "With Sam · For Priya · @ Home"; people named from
  /// [personNames], and the location from [locationNames].
  String describe([
    Map<String?, String> personNames = const {},
    Map<String?, String> locationNames = const {},
  ]) {
    String names(List<String> ids) =>
        ids.map((id) => personNames[id] ?? id).join(', ');
    return [
      if (withIds.isNotEmpty) 'With ${names(withIds)}',
      if (forIds.isNotEmpty) 'For ${names(forIds)}',
      if (locationId case final where?) '@ ${locationNames[where] ?? where}',
    ].join(' · ');
  }

  @override
  bool operator ==(Object other) =>
      other is Facts &&
      locationId == other.locationId &&
      _sameList(withIds, other.withIds) &&
      _sameList(forIds, other.forIds) &&
      notes.length == other.notes.length &&
      notes.entries.every((e) => other.notes[e.key] == e.value);

  @override
  int get hashCode => Object.hash(
    locationId,
    Object.hashAll(withIds),
    Object.hashAll(forIds),
    Object.hashAllUnordered(notes.entries.map((e) => (e.key, e.value))),
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

bool _sameList(List<String> a, List<String> b) =>
    a.length == b.length &&
    [for (var i = 0; i < a.length; i++) a[i] == b[i]].every((same) => same);
