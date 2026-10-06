import 'package:flutter/widgets.dart';

import '../models/trait.dart';
import 'mcp_client.dart';
import 'response_cache.dart';

/// Traits, how each person (Self included) is rated by them, and each
/// person's history, through the Time Tracker MCP server's tools. The app talks to this
/// rather than to MCP directly, so screens can be exercised without a
/// server. See [TraitsScope] for how screens find it.
abstract class TraitsRepository {
  /// Whether people are scored in full: [explainTraits] with the events
  /// behind each part, and [personDigest]. The server gives only the daily
  /// scores ([traitHistory]) and how each part's was reached; the sample
  /// data has it all.
  bool get scored;

  /// The traits with any of [statuses] (by default active and off).
  Future<List<Trait>> traits({List<String>? statuses});

  /// What [traits] last returned for [statuses], kept from an earlier run
  /// of the app; null if there's nothing kept.
  Future<List<Trait>?> cachedTraits({List<String>? statuses});

  /// Creates [trait]; returns it as created, with its id.
  Future<Trait> createTrait(Trait trait);

  /// Saves [changes], keyed as `update_trait` takes them, to the trait
  /// [id]; a null definition clears it. Returns it as saved.
  Future<Trait> updateTrait(String id, Map<String, Object?> changes);

  /// Each trait's daily score from [start] to [end] (both inclusive; by
  /// default the last 30 days): only [traitIds]' and from [personIds]'
  /// ratings, if given.
  Future<List<TraitDay>> traitHistory({
    List<String>? traitIds,
    List<String>? personIds,
    DateTime? start,
    DateTime? end,
  });

  /// How [personId]'s traits rate [day] (by default the last day that's
  /// over), part by part, with the events behind each part.
  Future<TraitsRating> explainTraits(String personId, {DateTime? day});

  /// [personId]'s history over the last [windowDays], with their events.
  Future<PersonDigest> personDigest(String personId, {int windowDays = 180});
}

/// Reaches traits via the Time Tracker MCP server.
class McpTraitsRepository implements TraitsRepository {
  McpTraitsRepository(this._client, {this._cache});

  final McpClient _client;

  final ResponseCache? _cache;

  static String _cacheKey(List<String>? statuses) =>
      'traits:${(statuses ?? const ['default']).join(',')}';

  static List<Trait> _decode(Object? result) => [
    for (final t in result as List)
      Trait.fromJson((t as Map).cast<String, dynamic>()),
  ];

  @override
  Future<List<Trait>> traits({List<String>? statuses}) async {
    final result = await _client.callTool('get_traits', {
      'statuses': ?statuses,
    });
    await _cache?.write(_cacheKey(statuses), result);
    return _decode(result);
  }

  @override
  Future<List<Trait>?> cachedTraits({List<String>? statuses}) async {
    try {
      final result = await _cache?.read(_cacheKey(statuses));
      return result == null ? null : _decode(result);
    } catch (_) {
      return null; // From an older version of the app, perhaps.
    }
  }

  @override
  Future<Trait> createTrait(Trait trait) async {
    final result = await _client.callTool('create_trait', {
      'trait': {...trait.toJson()..remove('id')},
    });
    return Trait.fromJson((result as Map).cast<String, dynamic>());
  }

  @override
  Future<Trait> updateTrait(String id, Map<String, Object?> changes) async {
    final cleared = [
      for (final MapEntry(:key, :value) in changes.entries)
        if (value == null) key,
    ];
    final result = await _client.callTool('update_trait', {
      'trait': {
        'id': id,
        for (final MapEntry(:key, :value) in changes.entries) key: ?value,
      },
      if (cleared.isNotEmpty) 'clear_fields': cleared,
    });
    return Trait.fromJson((result as Map).cast<String, dynamic>());
  }

  @override
  bool get scored => false;

  /// The server's daily score rows: one per person per day, each with its
  /// traits' scores and their parts'. Days are rolled up only once
  /// they're over, so [end] is yesterday by default, and [start] 29 days
  /// before it.
  Future<List<Map<String, dynamic>>> _scoreRows({
    String? personId,
    DateTime? start,
    DateTime? end,
  }) async {
    final now = DateTime.now();
    final last = end ?? DateTime(now.year, now.month, now.day - 1);
    final first = start ?? DateTime(last.year, last.month, last.day - 29);
    final result = await _client.callTool('get_trait_scores', {
      'person_id': ?personId,
      'start': _date(first),
      'end': _date(last),
    });
    return [
      for (final row in result as List? ?? const [])
        if (row is Map) row.cast<String, dynamic>(),
    ];
  }

  static String _date(DateTime day) =>
      '${day.year.toString().padLeft(4, '0')}-'
      '${day.month.toString().padLeft(2, '0')}-'
      '${day.day.toString().padLeft(2, '0')}';

  @override
  Future<List<TraitDay>> traitHistory({
    List<String>? traitIds,
    List<String>? personIds,
    DateTime? start,
    DateTime? end,
  }) async {
    final rows = await _scoreRows(
      personId: personIds?.length == 1 ? personIds!.single : null,
      start: start,
      end: end,
    );
    return traitDays(rows, traitIds: traitIds, personIds: personIds);
  }

  /// Each trait's daily scores from [rows] (as `get_trait_scores` gives
  /// them): each day's the mean of the people scored by it that day.
  @visibleForTesting
  static List<TraitDay> traitDays(
    List<Map<String, dynamic>> rows, {
    List<String>? traitIds,
    List<String>? personIds,
  }) {
    // Trait, then day, then each person's score.
    final scores = <String, Map<String, Map<String, int>>>{};
    for (final row in rows) {
      final day = row['day'], personId = row['person_id'];
      if (day is! String || personId is! String) continue;
      if (personIds != null && !personIds.contains(personId)) continue;
      final traits = row['scores'];
      if (traits is! Map) continue;
      for (final MapEntry(:key, :value) in traits.entries) {
        if (value is! num) continue;
        if (traitIds != null && !traitIds.contains(key)) continue;
        ((scores['$key'] ??= {})[day] ??= {})[personId] = value.round();
      }
    }
    return [
      for (final MapEntry(key: traitId, value: days) in scores.entries)
        for (final day in days.keys.toList()..sort())
          TraitDay(
            traitId: traitId,
            name: traitId,
            day: day,
            score:
                (days[day]!.values.reduce((a, b) => a + b) / days[day]!.length)
                    .round(),
            people: days[day]!,
          ),
    ];
  }

  @override
  Future<TraitsRating> explainTraits(String personId, {DateTime? day}) async {
    final rows = await _scoreRows(personId: personId, start: day, end: day);
    final row = rows.where((r) => r['person_id'] == personId).lastOrNull;
    if (row == null) return const TraitsRating();
    final scores = row['scores'] as Map? ?? const {};
    final parts = row['parts'] as Map? ?? const {};
    return TraitsRating(
      day: row['day'] as String?,
      traits: [
        for (final MapEntry(:key, :value) in scores.entries)
          TraitScore(
            traitId: '$key',
            name: '$key',
            score: value is num ? value.round() : null,
            parts: [
              for (final MapEntry(key: part, value: how)
                  in (parts[key] as Map? ?? const {}).entries)
                PartScore(
                  key: '$part',
                  kind: '$part'.split('#').first,
                  score: how is Map && how['score'] is num
                      ? (how['score'] as num).round()
                      : null,
                  said: how is Map ? how['said'] as String? ?? '' : '',
                ),
            ],
          ),
      ],
    );
  }

  @override
  Future<PersonDigest> personDigest(
    String personId, {
    int windowDays = 180,
  }) async => PersonDigest(personId: personId, windowDays: windowDays);
}

/// Keeps traits in memory. Used when no server is configured, and in
/// tests: it computes nothing, giving back what it was made with.
class InMemoryTraitsRepository implements TraitsRepository {
  InMemoryTraitsRepository({
    List<Trait> traits = const [],
    this.history = const [],
    this.ratings = const {},
    this.digests = const {},
  }) : _traits = [...traits];

  final List<Trait> _traits;
  final List<TraitDay> history;

  /// [explainTraits]' answer, by person id.
  final Map<String, TraitsRating> ratings;

  /// [personDigest]'s answer, by person id.
  final Map<String, PersonDigest> digests;

  @override
  Future<List<Trait>?> cachedTraits({List<String>? statuses}) async => null;

  @override
  bool get scored => true;

  @override
  Future<List<Trait>> traits({List<String>? statuses}) async => [
    for (final t in _traits)
      if ((statuses ?? const ['active', 'off']).contains(t.status)) t,
  ];

  @override
  Future<Trait> createTrait(Trait trait) async {
    if (traitProblem(trait) case final problem?) throw McpException(problem);
    final base = trait.name.toLowerCase().replaceAll(
      RegExp(r'[^a-z0-9]+'),
      '-',
    );
    var id = base;
    for (var n = 2; _traits.any((t) => t.id == id); n++) {
      id = '$base-$n';
    }
    final created = Trait.fromJson({...trait.toJson(), 'id': id});
    _traits.add(created);
    return created;
  }

  @override
  Future<Trait> updateTrait(String id, Map<String, Object?> changes) async {
    final i = _traits.indexWhere((t) => t.id == id);
    if (i < 0) throw McpException("'$id' isn't a trait");
    final updated = Trait.fromJson({..._traits[i].toJson(), ...changes});
    if (traitProblem(updated) case final problem?) throw McpException(problem);
    _traits[i] = updated;
    return updated;
  }

  @override
  Future<List<TraitDay>> traitHistory({
    List<String>? traitIds,
    List<String>? personIds,
    DateTime? start,
    DateTime? end,
  }) async => [
    for (final d in history)
      if (traitIds == null || traitIds.contains(d.traitId))
        if (personIds == null || d.people.keys.any(personIds.contains)) d,
  ];

  @override
  Future<TraitsRating> explainTraits(String personId, {DateTime? day}) async =>
      ratings[personId] ?? const TraitsRating();

  @override
  Future<PersonDigest> personDigest(
    String personId, {
    int windowDays = 180,
  }) async =>
      digests[personId] ??
      PersonDigest(personId: personId, windowDays: windowDays);
}

/// Provides a [TraitsRepository] to the screens and dialogs below it, so
/// it needn't be passed through each. Without one, what needs traits isn't
/// offered.
class TraitsScope extends InheritedWidget {
  const TraitsScope({
    super.key,
    required this.repository,
    required super.child,
  });

  final TraitsRepository repository;

  /// The nearest [TraitsScope]'s repository, or null if there's none.
  static TraitsRepository? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<TraitsScope>()?.repository;

  @override
  bool updateShouldNotify(TraitsScope oldWidget) =>
      repository != oldWidget.repository;
}
