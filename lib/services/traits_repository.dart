import 'package:flutter/widgets.dart';

import '../models/note.dart';
import '../models/trait.dart';
import 'mcp_client.dart';

/// Traits, what goals rated by them are made of, and goals' descriptions,
/// through the Time Tracker MCP server's tools. The app talks to this
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
  /// default the last 30 days): only [traitIds]' and from [goalIds]'
  /// ratings, if given.
  Future<List<TraitDay>> traitHistory({
    List<String>? traitIds,
    List<String>? goalIds,
    DateTime? start,
    DateTime? end,
  });

  /// How [goalId]'s traits measure rates [day] (by default the last day
  /// that's over), part by part, with the events behind each part.
  Future<TraitsRating> explainTraits(String goalId, {DateTime? day});

  /// [goalId]'s history over the last [windowDays], with its events.
  Future<GoalDigest> goalDigest(String goalId, {int windowDays = 180});

  /// [goalId]'s description (Markdown); empty if it has none.
  Future<String> description(String goalId);

  /// Replaces [goalId]'s description whole.
  Future<void> setDescription(String goalId, String description);
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
    List<String>? goalIds,
    DateTime? start,
    DateTime? end,
  }) async {
    final result = await _client.callTool('get_trait_history', {
      'trait_ids': ?traitIds,
      'goal_ids': ?goalIds,
      if (start != null) 'start': _day(start),
      if (end != null) 'end': _day(end),
    });
    return [
      for (final d in result as List)
        TraitDay.fromJson((d as Map).cast<String, dynamic>()),
    ];
  }

  @override
  Future<TraitsRating> explainTraits(String goalId, {DateTime? day}) async {
    final result = await _client.callTool('explain_traits', {
      'goal_id': goalId,
      if (day != null) 'day': _day(day),
    });
    return TraitsRating.fromJson((result as Map).cast<String, dynamic>());
  }

  @override
  Future<GoalDigest> goalDigest(String goalId, {int windowDays = 180}) async {
    final result = await _client.callTool('get_goal_digest', {
      'goal_id': goalId,
      'window_days': windowDays,
      'include_events': true,
    });
    return GoalDigest.fromJson((result as Map).cast<String, dynamic>());
  }

  @override
  Future<String> description(String goalId) async =>
      '${await _client.callTool('get_goal_description', {'goal_id': goalId}) ?? ''}';

  @override
  Future<void> setDescription(String goalId, String description) =>
      _client.callTool('set_goal_description', {
        'goal_id': goalId,
        'description': description,
      });
}

/// Keeps traits in memory. Used when no server is configured, and in
/// tests: it computes nothing, giving back what it was made with.
class InMemoryTraitsRepository implements TraitsRepository {
  InMemoryTraitsRepository({
    List<Trait> traits = const [],
    this.history = const [],
    this.ratings = const {},
    this.digests = const {},
    Map<String, String> descriptions = const {},
  }) : _traits = [...traits],
       _descriptions = {...descriptions};

  final List<Trait> _traits;
  final List<TraitDay> history;

  /// [explainTraits]' answer, by goal id.
  final Map<String, TraitsRating> ratings;

  /// [goalDigest]'s answer, by goal id.
  final Map<String, GoalDigest> digests;
  final Map<String, String> _descriptions;

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
    List<String>? goalIds,
    DateTime? start,
    DateTime? end,
  }) async => [
    for (final d in history)
      if (traitIds == null || traitIds.contains(d.traitId))
        if (goalIds == null || d.goals.keys.any(goalIds.contains)) d,
  ];

  @override
  Future<TraitsRating> explainTraits(String goalId, {DateTime? day}) async =>
      ratings[goalId] ?? (throw McpException("It isn't measured by traits"));

  @override
  Future<GoalDigest> goalDigest(String goalId, {int windowDays = 180}) async =>
      digests[goalId] ?? GoalDigest(goalId: goalId, windowDays: windowDays);

  @override
  Future<String> description(String goalId) async =>
      _descriptions[goalId] ?? '';

  @override
  Future<void> setDescription(String goalId, String description) async =>
      _descriptions[goalId] = description;
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
