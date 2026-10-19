import 'package:flutter/material.dart';

import 'hotkeys.dart';
import '../models/scoring.dart';
import '../models/trait.dart';
import '../models/trait_scores.dart' show partKeys;
import 'edit_page.dart';
import 'error_sheet.dart';
import 'parts_editor.dart';
import 'scoring_editor.dart';

/// Creates a trait (with no [trait]) or edits one, on a page of its own
/// ([EditPage]) -- its name, definition, status, facts, parts and how
/// they combine -- checking it as the server does ([traitProblem]),
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

  /// What it keeps about each person, for its judgments.
  late List<TraitFact> _facts = [...?widget.trait?.facts];
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
    facts: _facts,
  );

  /// Adds a fact (with no [index]) or edits the one at [index].
  Future<void> _editFact([int? index]) async {
    final fact = index == null ? null : _facts[index];
    final edited = await showFactDialog(
      context,
      fact: fact,
      taken: {for (final f in _facts) f.id},
    );
    if (edited == null || !mounted) return;
    setState(() {
      _facts = [..._facts];
      if (index == null) {
        _facts.add(edited);
      } else {
        _facts[index] = edited;
      }
    });
  }

  /// Lets go of the fact at [index] -- people's summaries of it are kept,
  /// unused -- and takes it out of the parts judged from it.
  void _removeFact(int index) {
    final name = _facts[index].judgmentName;
    setState(() {
      _facts = [..._facts]..removeAt(index);
      _parts = [
        for (final part in _parts)
          if (part['facts'] case final List facts)
            {
              ...part,
              'facts': [
                for (final f in facts)
                  if (f != name && !(f is Map && f['fact'] == name)) f,
              ],
            }
          else
            part,
      ];
      _partsVersion++;
    });
  }

  /// Bumped when the parts change from outside the editor, to rebuild it.
  int _partsVersion = 0;

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
        FieldHotkey(
          'N',
          child: TextField(
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
        ),
        FieldHotkey(
          'D',
          child: TextField(
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
        ),
        const SizedBox(height: 12),
        FieldHotkey(
          'S',
          onPressed: () => setState(
            () => _status = nextOf(traitStatuses.keys.toList(), _status),
          ),
          child: SegmentedButton<String>(
            showSelectedIcon: false,
            segments: [
              for (final MapEntry(:key, :value) in traitStatuses.entries)
                ButtonSegment(value: key, label: Text(value)),
            ],
            selected: {_status},
            onSelectionChanged: (picked) =>
                setState(() => _status = picked.single),
          ),
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
          child: Text('Facts', style: theme.textTheme.titleSmall),
        ),
        Text(
          'What it keeps about each person it applies to, for its '
          "judgments to read: each person's summary of each, which "
          'compaction rewrites as notes show something new, logging what '
          'changed on the event.',
          style: theme.textTheme.bodySmall,
        ),
        for (final (i, fact) in _facts.indexed)
          Card.outlined(
            margin: const EdgeInsets.only(top: 8),
            child: ListTile(
              title: Text(fact.name),
              subtitle: Text(
                fact.summaryPrompt,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
              onTap: () => _editFact(i),
              trailing: IconButton(
                tooltip: 'Remove ${fact.name}',
                icon: const Icon(Icons.close),
                onPressed: () => _removeFact(i),
              ),
            ),
          ),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: FieldHotkey(
            'F',
            child: TextButton.icon(
              onPressed: _editFact,
              icon: const Icon(Icons.add),
              label: const Text('Add fact'),
            ),
          ),
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
        FieldHotkey(
          'P',
          focusOnly: true,
          child: PartsEditor(
            key: ValueKey(_partsVersion),
            parts: _parts,
            facts: _facts,
            actions: widget.actions,
            preview: widget.preview,
            previewLabel: 'Yesterday, for you',
            onChanged: (parts) => setState(() => _parts = parts),
          ),
        ),
        FieldHotkey(
          'C',
          child: AggregationTile(
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
        ),
      ],
    );
  }
}

/// Adds a trait fact (with no [fact]) or edits one, in a dialog: its
/// name, what its summary of a person keeps, and what's worth logging
/// when that changes. A new one's id is made from its name, none of
/// [taken], and never changes. Returns it, or null if it was called off.
Future<TraitFact?> showFactDialog(
  BuildContext context, {
  TraitFact? fact,
  Set<String> taken = const {},
}) => showDialog<TraitFact>(
  context: context,
  builder: (_) => _FactDialog(fact: fact, taken: taken),
);

class _FactDialog extends StatefulWidget {
  const _FactDialog({required this.fact, required this.taken});

  final TraitFact? fact;
  final Set<String> taken;

  @override
  State<_FactDialog> createState() => _FactDialogState();
}

class _FactDialogState extends State<_FactDialog> {
  late final _name = TextEditingController(text: widget.fact?.name);
  late final _summary = TextEditingController(text: widget.fact?.summaryPrompt);
  late final _log = TextEditingController(text: widget.fact?.logPrompt);

  @override
  void dispose() {
    _name.dispose();
    _summary.dispose();
    _log.dispose();
    super.dispose();
  }

  bool get _ready =>
      _name.text.trim().isNotEmpty && _summary.text.trim().isNotEmpty;

  void _done() {
    final name = _name.text.trim();
    Navigator.of(context).pop(
      TraitFact(
        id: widget.fact?.id ?? newFactId(name, widget.taken),
        name: name,
        summaryPrompt: _summary.text.trim(),
        logPrompt: _log.text.trim().isEmpty ? null : _log.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.fact == null ? 'New fact' : 'Edit ${widget.fact!.name}'),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _name,
            autofocus: widget.fact == null,
            maxLength: 50,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Name',
              hintText: 'e.g. What matters',
              border: OutlineInputBorder(),
              isDense: true,
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _summary,
            minLines: 3,
            maxLines: null,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'What its summary keeps',
              hintText:
                  "What's important to them: the people, interests and "
                  'plans they care about. A list, kept current.',
              helperText: 'What Claude is told, to keep each summary.',
              helperMaxLines: 2,
              border: OutlineInputBorder(),
              floatingLabelBehavior: FloatingLabelBehavior.always,
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _log,
            minLines: 2,
            maxLines: null,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: "What's logged when it changes (optional)",
              hintText: 'What changed, and what in the event showed it.',
              border: OutlineInputBorder(),
              floatingLabelBehavior: FloatingLabelBehavior.always,
            ),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: _ready ? _done : null,
        child: Text(widget.fact == null ? 'Add' : 'Done'),
      ),
    ],
  );
}
