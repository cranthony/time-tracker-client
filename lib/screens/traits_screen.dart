import 'package:flutter/material.dart';

import '../models/trait.dart';
import '../services/mcp_client.dart';
import '../services/traits_repository.dart';
import '../widgets/health.dart';
import '../widgets/trait_dialog.dart';
import 'trait_breakdown.dart';

/// The traits goals are rated by: each one's name, status, latest score
/// (the mean across the goals rated by it) and its last 8 days' scores,
/// and anything wrong with it. Tapping a trait edits it; tapping its score
/// shows the goals and parts behind it; its menu turns it on or off, or
/// archives it. "+" adds one. Archived traits are shown only when asked
/// for. [goalNames] names the goals behind a score.
class TraitsScreen extends StatefulWidget {
  const TraitsScreen({
    super.key,
    required this.repository,
    this.goalNames = const {},
  });

  final TraitsRepository repository;
  final Map<String?, String> goalNames;

  @override
  State<TraitsScreen> createState() => _TraitsScreenState();
}

class _TraitsScreenState extends State<TraitsScreen> {
  List<Trait>? _traits;
  Map<String, List<TraitDay>> _history = const {};
  Object? _error;
  bool _archived = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final traits = await widget.repository.traits(
        statuses: [...traitStatuses.keys],
      );
      final history = await widget.repository.traitHistory();
      if (!mounted) return;
      setState(() {
        _traits = traits;
        _history = {};
        for (final day in history) {
          (_history[day.traitId] ??= []).add(day);
        }
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _edit(Trait? trait) async {
    final repository = widget.repository;
    final saved = await showTraitDialog(
      context,
      trait: trait,
      save: (edited) => trait?.id == null
          ? repository.createTrait(edited)
          : repository.updateTrait(trait!.id!, {
              'name': edited.name,
              'status': edited.status,
              'definition': edited.definition,
              'parts': edited.parts,
            }),
    );
    if (saved != null) await _load();
  }

  Future<void> _setStatus(Trait trait, String status) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await widget.repository.updateTrait(trait.id!, {'status': status});
      await _load();
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(switch (e) {
            McpException(:final message) => "Couldn't save. $message",
            _ => "Couldn't save. $e",
          }),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final traits = [
      for (final trait in _traits ?? const <Trait>[])
        if (_archived || trait.status != 'archived') trait,
    ];
    return Scaffold(
      appBar: AppBar(
        title: const Text('Traits'),
        actions: [
          IconButton(
            tooltip: _archived
                ? 'Hide archived traits'
                : 'Show archived traits',
            icon: Icon(
              _archived ? Icons.inventory_2 : Icons.inventory_2_outlined,
            ),
            onPressed: () => setState(() => _archived = !_archived),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        tooltip: 'New trait',
        onPressed: _traits == null ? null : () => _edit(null),
        child: const Icon(Icons.add),
      ),
      body: switch ((_traits, _error)) {
        (null, final error?) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              "Couldn't load the traits. ${switch (error) {
                McpException(:final message) => message,
                _ => '$error',
              }}",
            ),
          ),
        ),
        (null, _) => const Center(child: CircularProgressIndicator()),
        _ => RefreshIndicator(
          onRefresh: _load,
          child: ListView(
            children: [
              for (final trait in traits) _tile(context, trait),
              if (traits.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Text('No traits yet.'),
                ),
            ],
          ),
        ),
      },
    );
  }

  Widget _tile(BuildContext context, Trait trait) {
    final theme = Theme.of(context);
    final days = _history[trait.id] ?? const <TraitDay>[];
    final latest = days.isEmpty ? null : days.last;
    final muted = trait.status != 'active';
    return ListTile(
      onTap: () => _edit(trait),
      title: Text(
        trait.name,
        style: muted ? TextStyle(color: theme.hintColor) : null,
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (trait.definition case final definition?) Text(definition),
          if (trait.status != 'active')
            Text(traitStatuses[trait.status] ?? trait.status),
          for (final problem in trait.problems)
            Text(problem, style: TextStyle(color: theme.colorScheme.error)),
        ],
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (latest != null)
            InkWell(
              onTap: () => showTraitHistory(
                context,
                trait: trait,
                days: days,
                repository: widget.repository,
                goalNames: widget.goalNames,
              ),
              // On one line, as the Goals page shows a goal's health:
              // a column would overflow a list tile's height.
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TrendSparkline(trend: _trend(days)),
                    const SizedBox(width: 6),
                    HealthDot(rating: latest.score),
                  ],
                ),
              ),
            ),
          PopupMenuButton<String>(
            tooltip: 'More for ${trait.name}',
            onSelected: (status) => _setStatus(trait, status),
            itemBuilder: (_) => [
              for (final MapEntry(:key, :value) in traitStatuses.entries)
                if (key != trait.status)
                  PopupMenuItem(
                    value: key,
                    child: Text(switch (key) {
                      'active' => 'Turn on',
                      'off' => 'Turn off',
                      _ => value == 'Archived' ? 'Archive' : value,
                    }),
                  ),
            ],
          ),
        ],
      ),
    );
  }

  /// The last 8 days' scores, oldest first, for a [TrendSparkline].
  static List<int?> _trend(List<TraitDay> days) => [
    for (final day in days.skip(days.length > 8 ? days.length - 8 : 0))
      day.score,
  ];
}
