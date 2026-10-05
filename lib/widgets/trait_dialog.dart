import 'package:flutter/material.dart';

import '../models/trait.dart';
import '../services/mcp_client.dart';

/// Creates a trait (with no [trait]) or edits one -- its name, definition,
/// status and parts -- checking it as the server does ([traitProblem]),
/// then saving it with [save], which gets it whole. Returns what [save]
/// returned, or null if it was called off.
Future<Trait?> showTraitDialog(
  BuildContext context, {
  Trait? trait,
  required Future<Trait> Function(Trait trait) save,
}) => showDialog<Trait>(
  context: context,
  builder: (_) => _TraitDialog(trait: trait, save: save),
);

class _TraitDialog extends StatefulWidget {
  const _TraitDialog({required this.trait, required this.save});

  final Trait? trait;
  final Future<Trait> Function(Trait trait) save;

  @override
  State<_TraitDialog> createState() => _TraitDialogState();
}

class _TraitDialogState extends State<_TraitDialog> {
  late final _name = TextEditingController(text: widget.trait?.name);
  late final _definition = TextEditingController(
    text: widget.trait?.definition,
  );
  late String _status = widget.trait?.status ?? 'active';

  /// Each part's kind, and its fields as typed, by field name.
  late final List<_PartDraft> _parts = [
    for (final part in widget.trait?.parts ?? const <Part>[])
      _PartDraft.from(part),
  ];

  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _definition.dispose();
    for (final part in _parts) {
      part.dispose();
    }
    super.dispose();
  }

  Trait get _trait => Trait(
    id: widget.trait?.id,
    name: _name.text.trim(),
    status: _status,
    definition: _definition.text.trim().isEmpty
        ? null
        : _definition.text.trim(),
    parts: [for (final part in _parts) part.part],
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
                  _ => 'Rated, for every goal whose traits measure picks it.',
                }, style: theme.textTheme.bodySmall),
              ),
              Padding(
                padding: const EdgeInsets.only(top: 16, bottom: 4),
                child: Text('Parts', style: theme.textTheme.titleSmall),
              ),
              Text(
                "Its score is the weighted mean of its parts', each scored "
                "over the events of the goal using it, leaving out a part "
                'with nothing to score it by.',
                style: theme.textTheme.bodySmall,
              ),
              for (final (i, part) in _parts.indexed) _partCard(theme, i, part),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: TextButton.icon(
                  onPressed: () => setState(
                    () => _parts.add(_PartDraft.from(const {'kind': 'prep'})),
                  ),
                  icon: const Icon(Icons.add),
                  label: const Text('Add part'),
                ),
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

  Widget _partCard(ThemeData theme, int index, _PartDraft part) {
    final kind = partKinds[part.kind];
    return Card(
      margin: const EdgeInsets.only(top: 8),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 4, 4, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: DropdownButton<String>(
                    isExpanded: true,
                    value: kind == null ? null : part.kind,
                    hint: Text(part.kind),
                    items: [
                      for (final MapEntry(:key, :value) in partKinds.entries)
                        DropdownMenuItem(value: key, child: Text(value.label)),
                    ],
                    onChanged: (picked) =>
                        setState(() => part.kind = picked ?? part.kind),
                  ),
                ),
                IconButton(
                  tooltip: 'Remove part ${index + 1}',
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () => setState(() {
                    _parts.removeAt(index).dispose();
                  }),
                ),
              ],
            ),
            if (kind != null) Text(kind.hint, style: theme.textTheme.bodySmall),
            _input(
              part.controller('weight'),
              'Weight',
              hint: '1',
              number: true,
            ),
            for (final field in kind?.fields ?? const [])
              _input(
                part.controller(field.field),
                field.label + (field.required ? '' : ' (optional)'),
                hint: field.hint,
                number: field.field != 'rubric' && field.field != 'noun',
                maxLines: field.field == 'rubric' ? 4 : 1,
              ),
          ],
        ),
      ),
    );
  }

  Widget _input(
    TextEditingController controller,
    String label, {
    String? hint,
    bool number = false,
    int maxLines = 1,
  }) => Padding(
    padding: const EdgeInsets.only(top: 8, right: 8),
    child: TextField(
      controller: controller,
      minLines: 1,
      maxLines: maxLines,
      keyboardType: number
          ? const TextInputType.numberWithOptions(decimal: true)
          : TextInputType.text,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        isDense: true,
        border: const OutlineInputBorder(),
        floatingLabelBehavior: FloatingLabelBehavior.always,
      ),
      onChanged: (_) => setState(() {}),
    ),
  );
}

/// A part as it's being edited: its kind, and a field for each of its
/// settings, kept across changes of kind.
class _PartDraft {
  _PartDraft.from(Part part) : kind = '${part['kind']}' {
    for (final MapEntry(:key, :value) in part.entries) {
      if (key != 'kind' && value != null) controller(key).text = '$value';
    }
  }

  String kind;
  final _controllers = <String, TextEditingController>{};

  TextEditingController controller(String field) =>
      _controllers.putIfAbsent(field, TextEditingController.new);

  /// The part as its fields have it: only its kind's, and the weight; a
  /// number that doesn't parse is kept as typed, for [partProblem].
  Part get part {
    final fields = {
      'weight',
      for (final f in partKinds[kind]?.fields ?? const []) f.field,
    };
    Object? value(String field) {
      final text = _controllers[field]?.text.trim() ?? '';
      if (text.isEmpty) return null;
      if (field == 'rubric' || field == 'noun') return text;
      return num.tryParse(text) ?? text;
    }

    return {'kind': kind, for (final field in fields) field: ?value(field)};
  }

  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
  }
}
