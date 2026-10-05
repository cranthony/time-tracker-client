import 'package:flutter/widgets.dart';

import '../models/note.dart';
import '../models/trait.dart';
import 'mcp_client.dart';

/// Traits, how each person (Self included) is rated by them, and each
/// person's history, through the Time Tracker MCP server's tools. The app talks to this
/// rather than to MCP directly, so screens can be exercised without a
/// server. See [TraitsScope] for how screens find it.
abstract class TraitsRepository {
  /// The traits with any of [statuses] (by default active and off).
  Future<List<Trait>> traits({List<String>? statuses});

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

String _day(DateTime day) => localIsoTimestamp(day).substring(0, 10);

/// Reaches traits via the Time Tracker MCP server.
class McpTraitsRepository implements TraitsRepository {
  McpTraitsRepository(this._client);

  final McpClient _client;

  @override
  Future<List<Trait>> traits({List<String>? statuses}) async {
    final result = await _client.callTool('get_traits', {
      'statuses': ?statuses,
    });
    return [
      for (final t in result as List)
        Trait.fromJson((t as Map).cast<String, dynamic>()),
    ];
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
  Future<List<TraitDay>> traitHistory({
    List<String>? traitIds,
    List<String>? personIds,
    DateTime? start,
    DateTime? end,
  }) async {
    final result = await _client.callTool('get_trait_history', {
      'trait_ids': ?traitIds,
      'person_ids': ?personIds,
      if (start != null) 'start': _day(start),
      if (end != null) 'end': _day(end),
    });
    return [
      for (final d in result as List)
        TraitDay.fromJson((d as Map).cast<String, dynamic>()),
    ];
  }

  @override
  Future<TraitsRating> explainTraits(String personId, {DateTime? day}) async {
    final result = await _client.callTool('explain_traits', {
      'person_id': personId,
      if (day != null) 'day': _day(day),
    });
    return TraitsRating.fromJson((result as Map).cast<String, dynamic>());
  }

  @override
  Future<PersonDigest> personDigest(
    String personId, {
    int windowDays = 180,
  }) async {
    final result = await _client.callTool('get_person_digest', {
      'person_id': personId,
      'window_days': windowDays,
      'include_events': true,
    });
    return PersonDigest.fromJson((result as Map).cast<String, dynamic>());
  }
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
