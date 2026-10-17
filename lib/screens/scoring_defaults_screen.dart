import 'package:flutter/material.dart';

import '../widgets/hotkeys.dart';
import '../models/scoring.dart';
import '../models/trait.dart';
import '../services/plan_memory.dart';
import '../services/traits_repository.dart';
import '../widgets/edit_page.dart';
import '../widgets/error_sheet.dart';
import '../widgets/scoring_editor.dart';

/// Edits the scoring defaults -- how scores combine wherever nothing says
/// otherwise -- on a page of its own ([EditPage]): a person's or habit's
/// traits, a circle's people, and each layer of the habits pane. Saves
/// them with [repository], then loads [memory]'s traits again, for the
/// scores to be worked out with them.
Future<void> showScoringDefaults(
  BuildContext context, {
  required TraitsRepository repository,
  required PlanMemory memory,
}) => showEditPage<void>(
  context,
  _ScoringDefaultsPage(repository: repository, memory: memory),
);

class _ScoringDefaultsPage extends StatefulWidget {
  const _ScoringDefaultsPage({required this.repository, required this.memory});

  final TraitsRepository repository;
  final PlanMemory memory;

  @override
  State<_ScoringDefaultsPage> createState() => _ScoringDefaultsPageState();
}

class _ScoringDefaultsPageState extends State<_ScoringDefaultsPage> {
  late ScoringDefaults _defaults = widget.memory.scoringDefaults;
  bool _saving = false;

  Future<void> _save() async {
    final navigator = Navigator.of(context);
    setState(() => _saving = true);
    try {
      await widget.repository.setScoringDefaults(_defaults);
      await widget.memory.loadTraits(widget.repository, again: true);
      navigator.pop();
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      await showErrorSheet(
        context,
        title: "Couldn't save",
        error: e,
        onRetry: _save,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final traits = <String, String>{
      for (final t in widget.memory.traits ?? const <Trait>[])
        if (t.id != null && t.status == 'active') t.id!: t.name,
    };
    return EditPage(
      title: 'Scoring defaults',
      saving: _saving,
      onSave: _save,
      children: [
        Text(
          'How scores combine wherever nothing says otherwise. A trait '
          'says how its parts combine; a person, a habit or a circle can '
          'set its own in place of these.',
          style: theme.textTheme.bodySmall,
        ),
        FieldHotkey(
          'T',
          child: AggregationTile(
            title: 'Traits',
            label: "A person's or habit's traits",
            explanation: 'Into the score of their day.',
            value: _defaults.traits,
            items: traits,
            noun: 'traits',
            fallback: 'Mean',
            onChanged: (scoring) => setState(
              () => _defaults = ScoringDefaults(
                traits: scoring,
                circles: _defaults.circles,
                habitLayers: _defaults.habitLayers,
              ),
            ),
          ),
        ),
        FieldHotkey(
          'C',
          child: AggregationTile(
            title: 'Circles',
            label: "A circle's people",
            explanation: "Into the circle's health.",
            value: _defaults.circles,
            noun: 'people',
            fallback: 'Mean',
            onChanged: (scoring) => setState(
              () => _defaults = ScoringDefaults(
                traits: _defaults.traits,
                circles: scoring,
                habitLayers: _defaults.habitLayers,
              ),
            ),
          ),
        ),
        FieldHotkey(
          'H',
          child: AggregationTile(
            title: 'Habit layers',
            label: 'A layer of the habits pane',
            explanation: "Its habits' and people's ratings, into the layer's.",
            value: _defaults.habitLayers,
            noun: 'habits and people',
            fallback: 'Lowest',
            fallbackValue: Aggregation.lowest,
            onChanged: (scoring) => setState(
              () => _defaults = ScoringDefaults(
                traits: _defaults.traits,
                circles: _defaults.circles,
                habitLayers: scoring,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
