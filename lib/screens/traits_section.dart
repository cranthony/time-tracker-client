import 'package:flutter/material.dart';

import '../models/person.dart';
import '../models/trait.dart';
import '../models/trait_scores.dart';
import '../widgets/status_message.dart';
import '../services/plan_memory.dart';
import '../services/traits_repository.dart';
import '../widgets/error_sheet.dart';
import '../widgets/health.dart';
import '../widgets/trait_dialog.dart';
import 'trait_breakdown.dart';
import 'trait_screen.dart';

/// The Traits pane's traits, under Self -- how the user wants to be:
/// each trait's name, definition, status, latest score (the mean across
/// the people rated by it) and its last 8 days' scores, and anything
/// wrong with it. Tapping a trait opens its page, to read
/// ([TraitScreen]), whose pencil edits it, parts and all; tapping its
/// score shows the people and parts behind it; its menu turns it on or
/// off, or archives it. "Trait" adds one. Archived traits are shown only
/// when asked for. It shows what [memory] has, while it loads afresh.
/// [personNames] names the people behind a score; [actions] the actions
/// a part can count.
class TraitsSection extends StatefulWidget {
  const TraitsSection({
    super.key,
    required this.repository,
    required this.memory,
    this.personNames = const {},
    this.actions = const {},
  });

  final TraitsRepository repository;
  final PlanMemory memory;
  final Map<String?, String> personNames;
  final Map<String, String> actions;

  @override
  State<TraitsSection> createState() => TraitsSectionState();
}

class TraitsSectionState extends State<TraitsSection> {
  Object? _error;
  bool _archived = false;

  List<Trait>? get _traits => widget.memory.traits;

  /// Each trait's scores, by its id, oldest first: worked out from the
  /// events.
  Map<String, List<TraitDay>> get _history {
    final history = <String, List<TraitDay>>{};
    for (final day in widget.memory.scores?.history ?? const <TraitDay>[]) {
      (history[day.traitId] ??= []).add(day);
    }
    return history;
  }

  /// How a person's traits rated a day, part by part, from the events.
  TraitsRating? _rating(String personId, String day) =>
      widget.memory.scores?.rating(personId, day);

  @override
  void initState() {
    super.initState();
    widget.memory.addListener(_rescored);
    _settle(widget.memory.loadTraits(widget.repository));
  }

  @override
  void dispose() {
    widget.memory.removeListener(_rescored);
    super.dispose();
  }

  /// Shows the scores again, as they're worked out again.
  void _rescored() {
    if (mounted) setState(() {});
  }

  /// Loads the traits afresh, and the events around today they're scored
  /// from.
  Future<void> reload() => Future.wait([
    _settle(widget.memory.loadTraits(widget.repository, again: true)),
    ?widget.memory.eventStore?.warm().catchError((Object _) {}),
  ]);

  /// Shows what [loading] loads, once it has, or why it couldn't.
  Future<void> _settle(Future<void> loading) async {
    try {
      await loading;
      if (mounted) setState(() => _error = null);
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _open(Trait trait) => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => TraitScreen(
        trait: trait,
        rating: _rating,
        events: widget.memory.scores?.eventsBehind,
        days: _history[trait.id] ?? const [],
        people: widget.memory.people,
        actionNames: widget.actions,
        onEdit: _edit,
      ),
    ),
  );

  /// Creates a trait (with no [trait]) or edits one; returns it as
  /// saved, or null if nothing was.
  Future<Trait?> _edit(Trait? trait) async {
    final repository = widget.repository;
    final saved = await showTraitEditor(
      context,
      trait: trait,
      actions: widget.actions,
      preview: (parts) => widget.memory.scoreDraftParts(
        Subject.person(
          widget.memory.people?.withSelf.firstWhere((p) => p.isSelf) ??
              defaultSelf,
        ),
        trait?.id ?? '',
        parts,
      ),
      save: (edited) => trait?.id == null
          ? repository.createTrait(edited)
          : repository.updateTrait(trait!.id!, {
              'name': edited.name,
              'status': edited.status,
              'definition': edited.definition,
              'parts': edited.parts,
              'scoring': edited.scoring?.toJson(),
              'facts': [for (final fact in edited.facts) fact.toJson()],
            }),
    );
    if (saved != null) await reload();
    return saved;
  }

  Future<void> _setStatus(Trait trait, String status) async {
    await runOrShowError(
      context,
      title: "Couldn't save ${trait.name}",
      action: () async {
        await widget.repository.updateTrait(trait.id!, {'status': status});
        await reload();
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    // Once a build, not once a trait.
    final history = _history;
    final theme = Theme.of(context);
    final traits = [
      for (final trait in _traits ?? const <Trait>[])
        if (_archived || trait.status != 'archived') trait,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: switch ((_traits, _error)) {
        (null, final error?) => [
          LoadError(what: 'the traits', error: error, onRetry: reload),
        ],
        (null, _) => const [LinearProgressIndicator()],
        _ => [
          for (final trait in traits)
            _tile(context, trait, history[trait.id] ?? const []),
          if (traits.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
              child: Text(
                'No traits yet: how you want to be.',
                style: theme.textTheme.bodySmall,
              ),
            ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Wrap(
              children: [
                TextButton.icon(
                  onPressed: () => _edit(null),
                  icon: const Icon(Icons.add),
                  label: const Text('Trait'),
                ),
                TextButton.icon(
                  onPressed: () => setState(() => _archived = !_archived),
                  icon: Icon(
                    _archived ? Icons.inventory_2 : Icons.inventory_2_outlined,
                  ),
                  label: Text(
                    _archived ? 'Hide archived traits' : 'Show archived traits',
                  ),
                ),
              ],
            ),
          ),
        ],
      },
    );
  }

  Widget _tile(BuildContext context, Trait trait, List<TraitDay> days) {
    final theme = Theme.of(context);
    final latest = days.isEmpty ? null : days.last;
    final muted = trait.status != 'active';
    final judgments = trait.parts.where((p) => p['kind'] == 'judgment').length;
    final others = trait.parts.length - judgments;
    return ListTile(
      onTap: () => _open(trait),
      title: Text(
        trait.name,
        style: muted ? TextStyle(color: theme.hintColor) : null,
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (trait.definition case final definition?) Text(definition),
          Text(
            [
              if (judgments > 0)
                '$judgments judgment${judgments == 1 ? '' : 's'}',
              if (others > 0) '$others other part${others == 1 ? '' : 's'}',
              if (trait.status != 'active')
                traitStatuses[trait.status] ?? trait.status,
            ].join(' · '),
            style: theme.textTheme.bodySmall,
          ),
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
                rating: _rating,
                events: widget.memory.scores?.eventsBehind,
                personNames: widget.personNames,
              ),
              // On one line: a column would overflow a list tile's height.
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
