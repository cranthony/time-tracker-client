/// What happened at an event, for its goals' traits, mirroring the Time
/// Tracker MCP server's `Facets` (its utilities/facets.py): who it was
/// with and who it was for (goal ids), its activity and place, three 0-3
/// judgments, what was new, and a line of evidence. Every field is
/// optional. Compaction writes them on past events; they can be edited
/// here, and are saved whole through `update_event`.
class Facets {
  const Facets({
    this.withGoalIds = const [],
    this.forGoalIds = const [],
    this.activity,
    this.place,
    this.creative,
    this.newness,
    this.effort,
    this.attention,
    this.why,
  });

  /// The goals of the people present.
  final List<String> withGoalIds;

  /// The goals of the people it was done for, while they weren't there
  /// (preparing a gift, say).
  final List<String> forGoalIds;

  /// What it was, a short label, e.g. "salsa social".
  final String? activity;

  /// Where, a short label.
  final String? place;

  /// 0-3: how much they made something together.
  final int? creative;

  /// What was new to them: one of [newKinds]' keys.
  final String? newness;

  /// 0-3: effort beyond showing up (prepared, cooked, hosted, traveled).
  final int? effort;

  /// 0-3: the quality of attention given.
  final int? attention;

  /// One line of evidence for the judgments.
  final String? why;

  bool get isEmpty =>
      withGoalIds.isEmpty &&
      forGoalIds.isEmpty &&
      activity == null &&
      place == null &&
      creative == null &&
      newness == null &&
      effort == null &&
      attention == null &&
      why == null;

  /// From a `PublicEvent`'s `facets`; null for none.
  static Facets? fromJson(Object? json) {
    if (json is! Map) return null;
    List<String> ids(Object? value) => [
      for (final id in value as List? ?? const []) '$id',
    ];
    String? text(Object? value) =>
        value is String && value.trim().isNotEmpty ? value : null;
    int? score(Object? value) => value is num ? value.round() : null;
    return Facets(
      withGoalIds: ids(json['with_goal_ids']),
      forGoalIds: ids(json['for_goal_ids']),
      activity: text(json['activity']),
      place: text(json['place']),
      creative: score(json['creative']),
      newness: text(json['new']),
      effort: score(json['effort']),
      attention: score(json['attention']),
      why: text(json['why']),
    );
  }

  /// As `update_event` takes them, leaving out what's unset.
  Map<String, Object?> toJson() => {
    if (withGoalIds.isNotEmpty) 'with_goal_ids': withGoalIds,
    if (forGoalIds.isNotEmpty) 'for_goal_ids': forGoalIds,
    'activity': ?activity,
    'place': ?place,
    'creative': ?creative,
    'new': ?newness,
    'effort': ?effort,
    'attention': ?attention,
    'why': ?why,
  };

  /// In a line, e.g. "With Sam · salsa social @ the hall · new place ·
  /// creative 2, effort 1, attention 3"; goals named from [goalNames].
  String describe([Map<String?, String> goalNames = const {}]) {
    String names(List<String> ids) =>
        ids.map((id) => goalNames[id] ?? id).join(', ');
    final what = [?activity, ?place].join(' @ ');
    final scores = [
      if (creative case final c?) 'creative $c',
      if (effort case final e?) 'effort $e',
      if (attention case final a?) 'attention $a',
    ].join(', ');
    return [
      if (withGoalIds.isNotEmpty) 'With ${names(withGoalIds)}',
      if (forGoalIds.isNotEmpty) 'For ${names(forGoalIds)}',
      if (what.isNotEmpty) what,
      if (newness case final n? when n != 'none') 'new $n',
      if (scores.isNotEmpty) scores,
    ].join(' · ');
  }

  @override
  bool operator ==(Object other) =>
      other is Facets &&
      _sameList(withGoalIds, other.withGoalIds) &&
      _sameList(forGoalIds, other.forGoalIds) &&
      activity == other.activity &&
      place == other.place &&
      creative == other.creative &&
      newness == other.newness &&
      effort == other.effort &&
      attention == other.attention &&
      why == other.why;

  @override
  int get hashCode => Object.hash(
    Object.hashAll(withGoalIds),
    Object.hashAll(forGoalIds),
    activity,
    place,
    creative,
    newness,
    effort,
    attention,
    why,
  );
}

bool _sameList(List<String> a, List<String> b) =>
    a.length == b.length &&
    [for (var i = 0; i < a.length; i++) a[i] == b[i]].every((same) => same);

/// What can be new to them at an event, as the server names it, and as
/// the app shows it.
const newKinds = {
  'none': 'Nothing new',
  'activity': 'New activity',
  'place': 'New place',
  'both': 'New activity and place',
};

/// The 0-3 judgments, as the server names them, and as the app shows them
/// with what they rate.
const facetScores = {
  'creative': ('Creative', 'Made something together'),
  'effort': ('Effort', 'Beyond showing up: prepared, cooked, hosted, traveled'),
  'attention': ('Attention', 'The quality of attention given'),
};
