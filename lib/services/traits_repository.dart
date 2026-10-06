import 'package:flutter/widgets.dart';

import '../models/trait.dart';
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
}

/// Keeps traits in memory. Used when no server is configured, and in
/// tests.
class InMemoryTraitsRepository implements TraitsRepository {
  InMemoryTraitsRepository({List<Trait> traits = const []})
    : _traits = [...traits];

  final List<Trait> _traits;

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
