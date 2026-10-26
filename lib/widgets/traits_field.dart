import 'package:flutter/material.dart';

import '../models/person.dart';
import '../models/scoring.dart';
import '../models/trait.dart';
import '../models/trait_scores.dart' show partKeys;
import '../services/plan_memory.dart';
import 'parts_editor.dart';
import 'scoring_editor.dart';

/// How the traits combine into their score -- a person's, or a habit's
/// -- and, below it, which of [traits] apply: every active one, or those
/// picked, each with its own parts in place of the trait's, if it has
/// any, and how they combine. Starts from [value], and calls [onChanged]
/// with them after every change. A trait's tune button edits its own
/// parts on a page of its own titled [partsTitle], with
/// [partsExplanation] above them and [warnings] below; [actions] names
/// the actions and groups a part can
/// count. [own] is whose they are: "Their own", "Its own". With
/// [preview], a trait's own parts are scored as they're edited (see
/// [PartsEditor.preview]). Shows nothing without [traits].
class TraitsField extends StatefulWidget {
  const TraitsField({
    super.key,
    required this.traits,
    required this.value,
    required this.onChanged,
    required this.partsTitle,
    required this.partsExplanation,
    this.own = 'Their own',
    this.actions = const {},
    this.exceptionActions,
    this.warnings,
    this.preview,
  });

  final List<Trait> traits;
  final PersonTraits value;
  final ValueChanged<PersonTraits> onChanged;
  final String Function(Trait trait) partsTitle;
  final String Function(Trait trait) partsExplanation;
  final String own;
  final Map<String, String> actions;

  /// What a spacing part can set aside, by id; by default [actions].
  final Map<String, String>? exceptionActions;
  final List<String> Function(List<Part> parts)? warnings;
  final List<PartScore?>? Function(Trait trait, List<Part> parts)? preview;

  @override
  State<TraitsField> createState() => _TraitsFieldState();
}

class _TraitsFieldState extends State<TraitsField> {
  /// The traits picked; null for every active one.
  late List<String>? _select = switch (widget.value.select) {
    final ids? => [...ids],
    null => null,
  };

  /// Their own parts, by trait id, kept for a trait unpicked in case it's
  /// picked again.
  late final _parts = <String, List<Part>>{...widget.value.parts};

  /// How a trait's parts combine for them, by trait id.
  late final _partScoring = <String, Aggregation>{...widget.value.partScoring};

  /// How their traits combine.
  late Aggregation? _scoring = widget.value.scoring;

  void _changed(VoidCallback change) {
    setState(change);
    bool picked(String id) => _select?.contains(id) ?? true;
    widget.onChanged(
      PersonTraits(
        select: _select,
        except: widget.value.except,
        parts: {
          for (final MapEntry(:key, :value) in _parts.entries)
            if (picked(key)) key: value,
        },
        partScoring: {
          for (final MapEntry(:key, :value) in _partScoring.entries)
            if (picked(key)) key: value,
        },
        scoring: _scoring,
        // Edited beside their summaries, and kept here as they are.
        facts: widget.value.facts,
      ),
    );
  }

  /// [trait]'s parts for them -- their own, or the trait's -- that can be
  /// weighed, by id, each in a line.
  Map<String, String> _weighable(Trait trait) {
    final parts = _parts[trait.id] ?? trait.parts;
    final ids = partKeys(parts);
    return {
      for (final (i, part) in parts.indexed)
        // Their own new ones have no id till they're saved.
        if (_parts[trait.id] == null || part['id'] != null)
          ids[i]: describePart(part, widget.actions),
    };
  }

  Future<void> _editPartScoring(Trait trait) async {
    final picked = await showAggregationEditor(
      context,
      title: '${trait.name}: how its parts combine',
      explanation:
          "For them alone, in place of the trait's. A part of their own "
          'can be weighed once it is saved.',
      value: _partScoring[trait.id],
      items: _weighable(trait),
      noun: 'parts',
      fallback: switch (trait.scoring) {
        final scoring? => "The trait's: ${scoring.describe()}",
        null => "The trait's: mean",
      },
      fallbackValue: trait.scoring ?? Aggregation.mean,
    );
    if (picked == null) return;
    _changed(() {
      if (picked.scoring case final scoring?) {
        _partScoring[trait.id!] = scoring;
      } else {
        _partScoring.remove(trait.id);
      }
    });
  }

  Future<void> _editParts(Trait trait) async {
    final edited = await showPartsEditor(
      context,
      title: widget.partsTitle(trait),
      explanation: widget.partsExplanation(trait),
      parts: _parts[trait.id] ?? trait.parts,
      actions: widget.actions,
      exceptionActions: widget.exceptionActions,
      warnings: widget.warnings,
      preview: switch (widget.preview) {
        final preview? => (parts) => preview(trait, parts),
        null => null,
      },
      facts: trait.facts,
    );
    if (edited != null) _changed(() => _parts[trait.id!] = edited);
  }

  @override
  Widget build(BuildContext context) {
    if (widget.traits.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final all = _select == null;
    final shown = [
      for (final t in widget.traits)
        if (t.id != null &&
            (t.status == 'active' || (_select?.contains(t.id) ?? false)))
          t,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 16),
          child: Text('Traits', style: theme.textTheme.titleSmall),
        ),
        AggregationTile(
          title: 'How the traits combine',
          label: 'How the traits combine',
          explanation: 'Into the score of their day.',
          value: _scoring,
          items: {for (final t in shown) t.id!: t.name},
          noun: 'traits',
          fallback: switch (PlanMemoryScope.of(context)
              ?.scoringDefaults
              .traits) {
            final scoring? => "The defaults': ${scoring.describe()}",
            null => 'Mean',
          },
          fallbackValue:
              PlanMemoryScope.of(context)?.scoringDefaults.traits ??
              Aggregation.mean,
          onChanged: (scoring) => _changed(() => _scoring = scoring),
        ),
        SwitchListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          title: const Text('Every active trait'),
          subtitle: const Text('Including any added later.'),
          value: all,
          onChanged: (on) => _changed(
            () => _select = on ? null : [for (final t in shown) t.id!],
          ),
        ),
        for (final trait in shown)
          if (all || _select!.contains(trait.id))
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: all
                  ? null
                  : Checkbox(
                      value: true,
                      onChanged: (_) =>
                          _changed(() => _select!.remove(trait.id)),
                    ),
              title: Text(trait.name),
              subtitle: Text(
                [
                  switch (_parts[trait.id]) {
                    final own? =>
                      '${widget.own}: '
                          '${own.map((p) => describePart(p, widget.actions)).join('; ')}',
                    null => "The trait's parts",
                  },
                  if (_partScoring[trait.id] case final scoring?)
                    'combined: ${scoring.describe()}',
                ].join('; '),
              ),
              trailing: Wrap(
                children: [
                  IconButton(
                    tooltip: 'How ${trait.name} parts combine',
                    icon: const Icon(Icons.functions),
                    onPressed: () => _editPartScoring(trait),
                  ),
                  if (_parts.containsKey(trait.id))
                    IconButton(
                      tooltip: "Use ${trait.name}'s parts",
                      icon: const Icon(Icons.undo),
                      onPressed: () => _changed(() => _parts.remove(trait.id)),
                    ),
                  IconButton(
                    tooltip: '${widget.own} ${trait.name} parts',
                    icon: const Icon(Icons.tune),
                    onPressed: () => _editParts(trait),
                  ),
                ],
              ),
            )
          else
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Checkbox(
                value: false,
                onChanged: (_) => _changed(() => _select!.add(trait.id!)),
              ),
              title: Text(trait.name, style: TextStyle(color: theme.hintColor)),
            ),
      ],
    );
  }
}
