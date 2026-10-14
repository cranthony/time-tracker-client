import 'package:flutter/material.dart';

import '../models/scoring.dart';
import '../models/trait.dart';
import '../models/trait_scores.dart' show partKeys;
import 'edit_page.dart';
import 'error_sheet.dart';
import 'parts_editor.dart';
import 'scoring_editor.dart';

/// Creates a trait (with no [trait]) or edits one, on a page of its own
/// ([EditPage]) -- its name, definition, status, parts and how they
/// combine -- checking it as the server does ([traitProblem]),
/// then saving it with [save], which gets it whole. Returns what [save]
/// returned, or null if it was called off. [actions] names the actions
/// a cadence part can count, by id. With [preview], its parts are scored
/// as they're edited, for Self (see [PartsEditor.preview]).
Future<Trait?> showTraitEditor(
  BuildContext context, {
  Trait? trait,
  required Future<Trait> Function(Trait trait) save,
  Map<String, String> actions = const {},
  PartsPreview? preview,
}) => showEditPage<Trait>(
  context,
  _TraitEditor(trait: trait, save: save, actions: actions, preview: preview),
);

class _TraitEditor extends StatefulWidget {
  const _TraitEditor({
    required this.trait,
    required this.save,
    required this.actions,
    required this.preview,
  });

  final Trait? trait;
  final Future<Trait> Function(Trait trait) save;
  final Map<String, String> actions;
  final PartsPreview? preview;

  @override
  State<_TraitEditor> createState() => _TraitEditorState();
}

class _TraitEditorState extends State<_TraitEditor> {
  late final _name = TextEditingController(text: widget.trait?.name);
  late final _definition = TextEditingController(
    text: widget.trait?.definition,
  );
  late String _status = widget.trait?.status ?? 'active';

  late List<Part> _parts = [...?widget.trait?.parts];
  late Aggregation? _scoring = widget.trait?.scoring;

  /// Its parts that can be weighed, by id, each in a line: those saved,
  /// a new one having no id till then.
  Map<String, String> get _weighable => {
    for (final part in _parts)
      if (part['id'] case final String id)
        id: describePart(part, widget.actions),
  };

  /// [_scoring], without the weights of parts let go.
  Aggregation? get _kept {
    final scoring = _scoring;
    if (scoring == null) return null;
    final ids = partKeys(_parts);
    final json = scoring.toJson()..remove('weights');
    final weights = {
      for (final MapEntry(:key, :value) in scoring.weights.entries)
        if (ids.contains(key)) key: value,
    };
    if (weights.isNotEmpty) json['weights'] = weights;
    final kept = Aggregation.fromJson(json)!;
    return kept.isMean ? null : kept;
  }

  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    _definition.dispose();
    super.dispose();
  }

  Trait get _trait => Trait(
    id: widget.trait?.id,
    name: _name.text.trim(),
    status: _status,
    definition: _definition.text.trim().isEmpty
        ? null
        : _definition.text.trim(),
    parts: _parts,
    scoring: _kept,
  );

  Future<void> _save() async {
    final navigator = Navigator.of(context);
    setState(() => _saving = true);
    try {
      navigator.pop(await widget.save(_trait));
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
    final problem = traitProblem(_trait);
    return EditPage(
      title: widget.trait == null ? 'New trait' : 'Edit ${widget.trait!.name}',
      problem: problem,
      saving: _saving,
      onSave: _save,
      children: [
        TextField(
          controller: _name,
          maxLength: 50,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
            labelText: 'Name',
            border: OutlineInputBorder(),
            isDense: true,
          ),
          onChanged: (_) => setState(() {}),
        ),
        TextField(
          controller: _definition,
          minLines: 3,
          maxLines: null,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(
            labelText: 'Definition',
            hintText: 'What it means, in a sentence or two',
            border: OutlineInputBorder(),
            isDense: true,
          ),
        ),
        const SizedBox(height: 12),
        SegmentedButton<String>(
          showSelectedIcon: false,
          segments: [
            for (final MapEntry(:key, :value) in traitStatuses.entries)
              ButtonSegment(value: key, label: Text(value)),
          ],
          selected: {_status},
          onSelectionChanged: (picked) =>
              setState(() => _status = picked.single),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(switch (_status) {
            'off' => "Kept, but not rated for now.",
            'archived' => 'Retired: not rated. Its history is kept.',
            _ => 'Rated for everyone, Self included.',
          }, style: theme.textTheme.bodySmall),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 16, bottom: 4),
          child: Text('Parts', style: theme.textTheme.titleSmall),
        ),
        Text(
          "Its score for a person combines its parts', each scored over "
          'the events with or for them, leaving out a part with nothing to '
          'score it by.',
          style: theme.textTheme.bodySmall,
        ),
        PartsEditor(
          parts: _parts,
          actions: widget.actions,
          preview: widget.preview,
          previewLabel: 'Yesterday, for you',
          onChanged: (parts) => setState(() => _parts = parts),
        ),
        AggregationTile(
          title: 'How its parts combine',
          label: 'How its parts combine',
          explanation:
              "Into its score for a person, unless their own say. A new "
              'part can be weighed once the trait is saved.',
          value: _kept,
          items: _weighable,
          checkWeights: true,
          noun: 'parts',
          fallback: 'Mean',
          onChanged: (scoring) => setState(() => _scoring = scoring),
        ),
      ],
    );
  }
}
