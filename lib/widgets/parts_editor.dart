import 'package:flutter/material.dart';

import '../models/trait.dart';

/// Edits a trait's parts -- each one's kind, settings and weight, and a
/// judgment's rubric -- as cards, with "Add part" below them. Calls
/// [onChanged] with the parts as they stand after every edit, whether or
/// not they're valid yet; see [partProblem].
class PartsEditor extends StatefulWidget {
  const PartsEditor({super.key, required this.parts, required this.onChanged});

  final List<Part> parts;
  final ValueChanged<List<Part>> onChanged;

  @override
  State<PartsEditor> createState() => _PartsEditorState();
}

class _PartsEditorState extends State<PartsEditor> {
  late final List<_PartDraft> _drafts = [
    for (final part in widget.parts) _PartDraft.from(part),
  ];

  @override
  void dispose() {
    for (final draft in _drafts) {
      draft.dispose();
    }
    super.dispose();
  }

  void _changed() {
    setState(() {});
    widget.onChanged([for (final draft in _drafts) draft.part]);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final (i, draft) in _drafts.indexed) _card(theme, i, draft),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: TextButton.icon(
            onPressed: () {
              _drafts.add(_PartDraft.from(const {'kind': 'prep'}));
              _changed();
            },
            icon: const Icon(Icons.add),
            label: const Text('Add part'),
          ),
        ),
      ],
    );
  }

  Widget _card(ThemeData theme, int index, _PartDraft draft) {
    final kind = partKinds[draft.kind];
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
                    value: kind == null ? null : draft.kind,
                    hint: Text(draft.kind),
                    items: [
                      for (final MapEntry(:key, :value) in partKinds.entries)
                        DropdownMenuItem(value: key, child: Text(value.label)),
                    ],
                    onChanged: (picked) {
                      draft.kind = picked ?? draft.kind;
                      _changed();
                    },
                  ),
                ),
                IconButton(
                  tooltip: 'Remove part ${index + 1}',
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () {
                    _drafts.removeAt(index).dispose();
                    _changed();
                  },
                ),
              ],
            ),
            if (kind != null) Text(kind.hint, style: theme.textTheme.bodySmall),
            _input(
              draft.controller('weight'),
              'Weight',
              hint: '1',
              number: true,
            ),
            for (final field in kind?.fields ?? const [])
              _input(
                draft.controller(field.field),
                field.label + (field.required ? '' : ' (optional)'),
                hint: field.hint,
                number: !textFields.contains(field.field),
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
      onChanged: (_) => _changed(),
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
      if (textFields.contains(field)) {
        // Activities are kept as facets keep them, so they match.
        return field == 'activity' ? activityLabel(text) : text;
      }
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

/// Edits [parts] in a dialog titled [title], with [explanation] above
/// them, refusing to save while they're empty or a part is wrong. Returns
/// the parts, or null if it was called off.
Future<List<Part>?> showPartsDialog(
  BuildContext context, {
  required String title,
  String? explanation,
  required List<Part> parts,
}) => showDialog<List<Part>>(
  context: context,
  builder: (_) =>
      _PartsDialog(title: title, explanation: explanation, parts: parts),
);

class _PartsDialog extends StatefulWidget {
  const _PartsDialog({
    required this.title,
    required this.explanation,
    required this.parts,
  });

  final String title;
  final String? explanation;
  final List<Part> parts;

  @override
  State<_PartsDialog> createState() => _PartsDialogState();
}

class _PartsDialogState extends State<_PartsDialog> {
  late List<Part> _parts = widget.parts;

  String? get _problem {
    if (_parts.isEmpty) return 'Give it at least one part.';
    for (final (i, part) in _parts.indexed) {
      if (partProblem(part) case final problem?) {
        return 'Part ${i + 1}: $problem';
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final problem = _problem;
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.explanation case final explanation?)
                Text(explanation, style: theme.textTheme.bodySmall),
              PartsEditor(
                parts: widget.parts,
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
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: problem == null
              ? () => Navigator.of(context).pop(_parts)
              : null,
          child: const Text('Done'),
        ),
      ],
    );
  }
}
