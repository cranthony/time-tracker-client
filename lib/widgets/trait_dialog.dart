import 'package:flutter/material.dart';

import '../models/trait.dart';
import '../services/mcp_client.dart';
import 'parts_editor.dart';

/// Creates a trait (with no [trait]) or edits one -- its name, definition,
/// status and parts -- checking it as the server does ([traitProblem]),
/// then saving it with [save], which gets it whole. Returns what [save]
/// returned, or null if it was called off. [actions] names the actions
/// a cadence part can count, by id.
Future<Trait?> showTraitDialog(
  BuildContext context, {
  Trait? trait,
  required Future<Trait> Function(Trait trait) save,
  Map<String, String> actions = const {},
}) => showDialog<Trait>(
  context: context,
  builder: (_) => _TraitDialog(trait: trait, save: save, actions: actions),
);

class _TraitDialog extends StatefulWidget {
  const _TraitDialog({
    required this.trait,
    required this.save,
    required this.actions,
  });

  final Trait? trait;
  final Future<Trait> Function(Trait trait) save;
  final Map<String, String> actions;

  @override
  State<_TraitDialog> createState() => _TraitDialogState();
}

class _TraitDialogState extends State<_TraitDialog> {
  late final _name = TextEditingController(text: widget.trait?.name);
  late final _definition = TextEditingController(
    text: widget.trait?.definition,
  );
  late String _status = widget.trait?.status ?? 'active';

  late List<Part> _parts = [...?widget.trait?.parts];

  bool _saving = false;
  String? _error;

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
  );

  Future<void> _save() async {
    final navigator = Navigator.of(context);
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      navigator.pop(await widget.save(_trait));
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = switch (e) {
          McpException(:final message) => message,
          _ => '$e',
        };
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final problem = traitProblem(_trait);
    return AlertDialog(
      title: Text(widget.trait == null ? 'New trait' : 'Edit trait'),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_error case final error?)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: SelectableText(
                    "Couldn't save. $error",
                    style: TextStyle(color: theme.colorScheme.error),
                  ),
                ),
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
                minLines: 1,
                maxLines: 4,
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
                "Its score for a person is the weighted mean of its parts', "
                'each scored over the events with or for them, leaving out '
                'a part with nothing to score it by.',
                style: theme.textTheme.bodySmall,
              ),
              PartsEditor(
                parts: _parts,
                actions: widget.actions,
                onChanged: (parts) => setState(() => _parts = parts),
              ),
              if (problem != null)
                Text(problem, style: TextStyle(color: theme.colorScheme.error)),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _saving || problem != null ? null : _save,
          child: _saving
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Save'),
        ),
      ],
    );
  }
}
