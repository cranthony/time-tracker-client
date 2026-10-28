import 'package:flutter/widgets.dart';

import '../models/scoring.dart';
import '../models/trait.dart';
import '../models/trait_scores.dart' show withPartIds;
import '../outbox/write_queue.dart';
import 'mcp_client.dart';
import 'response_cache.dart';

/// Traits, through the Time Tracker MCP server's tools. How each person
/// is rated by them is worked out in the app, from their events (see
/// models/trait_scores.dart). The app talks to this
/// rather than to MCP directly, so screens can be exercised without a
/// server. See [TraitsScope] for how screens find it.
abstract class TraitsRepository {
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

  /// How scores combine where nothing says otherwise. A server without
  /// them has none: everything combines by the plain mean.
  Future<ScoringDefaults> scoringDefaults();

  /// What [scoringDefaults] last returned, kept from an earlier run of
  /// the app; null if there's nothing kept.
  Future<ScoringDefaults?> cachedScoringDefaults();

  /// Saves [defaults] whole: a level without one goes back to the plain
  /// mean (a habit layer's, to its lowest). Returns them as saved.
  Future<ScoringDefaults> setScoringDefaults(ScoringDefaults defaults);
}

/// Reaches traits via the Time Tracker MCP server.
class McpTraitsRepository implements TraitsRepository {
  /// With [writes], traits and the scoring defaults are written through
  /// it: queued, kept on the device and sent once -- and what's read is
  /// shown with them made.
  McpTraitsRepository(this._client, {this._cache, this._writes});

  final WriteQueue? _writes;

  /// [result], `get_traits`', with the writes waiting made to it.
  Object? _shown(Object? result) =>
      _writes?.shown(WriteKind.trait, [
        for (final t in result as List) (t as Map).cast<String, Object?>(),
      ]) ??
      result;

  /// [result], `get_scoring_defaults`', with the writes waiting made to it.
  Object? _shownDefaults(Object? result) {
    final writes = _writes;
    if (writes == null || result is! Map) return result;
    final shown = writes.shown(WriteKind.scoringDefaults, [
      {...result.cast<String, Object?>(), 'id': WriteKind.one},
    ]);
    return {...shown.single}..remove('id');
  }

  final McpClient _client;

  final ResponseCache? _cache;

  static String _cacheKey(List<String>? statuses) =>
      'traits:${(statuses ?? const ['default']).join(',')}';

  static const _defaultsKey = 'scoring_defaults';

  static List<Trait> _decode(Object? result) => [
    for (final t in result as List)
      Trait.fromJson((t as Map).cast<String, dynamic>()),
  ];

  @override
  Future<List<Trait>> traits({List<String>? statuses}) async {
    // The traits' writes saved before this are let go of once it's in
    // and they're made to it.
    final fetched = _writes?.fetchingKinds(const [WriteKind.trait]);
    final result = await _client.callTool('get_traits', {
      'statuses': ?statuses,
    });
    await _cache?.write(_cacheKey(statuses), result);
    final traits = _decode(_shown(result));
    fetched?.call();
    return traits;
  }

  @override
  Future<List<Trait>?> cachedTraits({List<String>? statuses}) async {
    try {
      final result = await _cache?.read(_cacheKey(statuses));
      return result == null ? null : _decode(_shown(result));
    } catch (_) {
      return null; // From an older version of the app, perhaps.
    }
  }

  @override
  Future<ScoringDefaults> scoringDefaults() async {
    final fetched = _writes?.fetchingKinds(const [WriteKind.scoringDefaults]);
    final Object? result;
    try {
      result = await _client.callTool('get_scoring_defaults');
    } on McpException {
      return const ScoringDefaults(); // A server from before them.
    }
    await _cache?.write(_defaultsKey, result);
    final defaults = ScoringDefaults.fromJson(_shownDefaults(result));
    fetched?.call();
    return defaults;
  }

  @override
  Future<ScoringDefaults> setScoringDefaults(ScoringDefaults defaults) async {
    if (_writes case final writes?) {
      final shown = writes.update(
        WriteKind.scoringDefaults,
        WriteKind.one,
        defaults.toJson(),
      );
      return ScoringDefaults.fromJson({...shown}..remove('id'));
    }
    final json = defaults.toJson();
    final result = await _client.callTool('set_scoring_defaults', {
      'defaults': {
        for (final MapEntry(:key, :value) in json.entries) key: ?value,
      },
      'clear_fields': [
        for (final MapEntry(:key, :value) in json.entries)
          if (value == null) key,
      ],
    });
    await _cache?.write(_defaultsKey, result);
    return ScoringDefaults.fromJson(result);
  }

  @override
  Future<ScoringDefaults?> cachedScoringDefaults() async {
    try {
      final result = await _cache?.read(_defaultsKey);
      return result == null
          ? null
          : ScoringDefaults.fromJson(_shownDefaults(result));
    } catch (_) {
      return null;
    }
  }

  @override
  Future<Trait> createTrait(Trait trait) async => switch (_writes) {
    final writes? => Trait.fromJson(
      writes.created(WriteKind.trait, trait.toJson()).cast(),
    ),
    null => await _createTrait(trait),
  };

  Future<Trait> _createTrait(Trait trait) async {
    final result = await _client.callTool('create_trait', {
      'trait': {...trait.toJson()..remove('id')},
    });
    return Trait.fromJson((result as Map).cast<String, dynamic>());
  }

  @override
  Future<Trait> updateTrait(String id, Map<String, Object?> changes) async =>
      switch (_writes) {
        final writes? => Trait.fromJson(
          writes.update(WriteKind.trait, id, changes).cast(),
        ),
        null => await _updateTrait(id, changes),
      };

  Future<Trait> _updateTrait(String id, Map<String, Object?> changes) async {
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
}

/// Keeps traits in memory. Used when no server is configured, and in
/// tests.
class InMemoryTraitsRepository implements TraitsRepository {
  InMemoryTraitsRepository({
    List<Trait> traits = const [],
    this.defaults = const ScoringDefaults(),
  }) : _traits = [for (final t in traits) _withIds(t)];

  final List<Trait> _traits;
  ScoringDefaults defaults;

  /// [trait] with an id for each part, as the server keeps them: a new
  /// one's made, with [fresh].
  static Trait _withIds(Trait trait, {bool fresh = false}) => Trait.fromJson({
    ...trait.toJson(),
    'parts': withPartIds(trait.parts, fresh: fresh),
  });

  @override
  Future<ScoringDefaults> scoringDefaults() async => defaults;

  @override
  Future<ScoringDefaults?> cachedScoringDefaults() async => null;

  @override
  Future<ScoringDefaults> setScoringDefaults(ScoringDefaults defaults) async {
    for (final level in defaults.toJson().values) {
      if (level == null) continue;
      if (aggregationProblem(level) case final problem?) {
        throw McpException(problem);
      }
    }
    return this.defaults = defaults;
  }

  @override
  Future<List<Trait>?> cachedTraits({List<String>? statuses}) async => null;

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
    final created = _withIds(
      Trait.fromJson({...trait.toJson(), 'id': id}),
      fresh: true,
    );
    _traits.add(created);
    return created;
  }

  @override
  Future<Trait> updateTrait(String id, Map<String, Object?> changes) async {
    final i = _traits.indexWhere((t) => t.id == id);
    if (i < 0) throw McpException("'$id' isn't a trait");
    final updated = _withIds(
      Trait.fromJson({..._traits[i].toJson(), ...changes}),
      fresh: true,
    );
    if (traitProblem(updated) case final problem?) throw McpException(problem);
    _traits[i] = updated;
    return updated;
  }
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
