import 'package:flutter/material.dart';

import '../models/person.dart';
import '../models/trait.dart';

/// Edits [whose] own prompts for [trait]'s [fact], in a dialog: for its
/// summary prompt and its log prompt, whether to use the trait's, their
/// own in place of it ("Replace": the field starts as the trait's), or
/// the trait's with theirs after it ("Append": the trait's shown above
/// an empty field). Starts from [current]. Returns their prompts --
/// empty to use the trait's -- or null if it was called off.
Future<FactPromptOverride?> showFactPromptsDialog(
  BuildContext context, {
  required Trait trait,
  required TraitFact fact,
  FactPromptOverride? current,
  String whose = 'their',
}) => showDialog<FactPromptOverride>(
  context: context,
  builder: (_) => _FactPromptsDialog(
    trait: trait,
    fact: fact,
    current: current,
    whose: whose,
  ),
);

/// How one prompt goes for them.
enum _How { traits, replace, append }

/// One prompt being edited: how it goes, and their text.
class _PromptDraft {
  _PromptDraft(PromptOverride? given, this.traits)
    : how = switch (given) {
        null => _How.traits,
        PromptOverride(append: true) => _How.append,
        _ => _How.replace,
      },
      text = TextEditingController(text: given?.text);

  /// The trait's prompt, if it has one.
  final String? traits;
  _How how;
  final TextEditingController text;

  /// As their prompts keep it: null for the trait's, or an empty text.
  PromptOverride? get value => switch (how) {
    _How.traits => null,
    _ when text.text.trim().isEmpty => null,
    _How.replace => PromptOverride(text.text.trim()),
    _How.append => PromptOverride(text.text.trim(), append: true),
  };

  /// Picks [picked]: "Replace" starts from the trait's prompt; "Append"
  /// from nothing.
  void pick(_How picked) {
    if (picked == how) return;
    if (picked == _How.replace && text.text.trim().isEmpty) {
      text.text = traits ?? '';
    } else if (picked == _How.append && text.text.trim() == traits?.trim()) {
      text.clear();
    }
    how = picked;
  }
}

class _FactPromptsDialog extends StatefulWidget {
  const _FactPromptsDialog({
    required this.trait,
    required this.fact,
    required this.current,
    required this.whose,
  });

  final Trait trait;
  final TraitFact fact;
  final FactPromptOverride? current;
  final String whose;

  @override
  State<_FactPromptsDialog> createState() => _FactPromptsDialogState();
}

class _FactPromptsDialogState extends State<_FactPromptsDialog> {
  late final _summary = _PromptDraft(
    widget.current?.summaryPrompt,
    widget.fact.summaryPrompt,
  );
  late final _log = _PromptDraft(
    widget.current?.logPrompt,
    widget.fact.logPrompt,
  );

  @override
  void dispose() {
    _summary.text.dispose();
    _log.text.dispose();
    super.dispose();
  }

  Widget _prompt(ThemeData theme, String label, _PromptDraft draft) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(label, style: theme.textTheme.titleSmall),
      const SizedBox(height: 6),
      SegmentedButton<_How>(
        showSelectedIcon: false,
        segments: [
          ButtonSegment(
            value: _How.traits,
            label: Text("${widget.trait.name}'s"),
          ),
          const ButtonSegment(value: _How.replace, label: Text('Replace')),
          const ButtonSegment(value: _How.append, label: Text('Append')),
        ],
        selected: {draft.how},
        onSelectionChanged: (picked) =>
            setState(() => draft.pick(picked.single)),
      ),
      const SizedBox(height: 8),
      if (draft.how != _How.replace)
        Text(
          draft.traits ?? "${widget.trait.name} has none.",
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      if (draft.how != _How.traits)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: TextField(
            controller: draft.text,
            minLines: 2,
            maxLines: null,
            maxLength: 5000,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              labelText: draft.how == _How.append
                  ? 'Added for ${widget.whose == 'your' ? 'you' : 'them'}'
                  : '${widget.whose[0].toUpperCase()}${widget.whose.substring(1)} own',
              border: const OutlineInputBorder(),
              isDense: true,
            ),
            onChanged: (_) => setState(() {}),
          ),
        ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: Text('${widget.fact.name}: ${widget.whose} own prompts'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'How compaction keeps ${widget.whose} summary of it, in '
              "place of ${widget.trait.name}'s or added to it. The summary is "
              'rewritten to fit the next time an event is with or for '
              '${widget.whose == 'your' ? 'you' : 'them'}.',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            _prompt(theme, 'What the summary keeps', _summary),
            const SizedBox(height: 16),
            _prompt(theme, "What's logged when it changes", _log),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(
            FactPromptOverride(
              summaryPrompt: _summary.value,
              logPrompt: _log.value,
            ),
          ),
          child: const Text('Done'),
        ),
      ],
    );
  }
}
