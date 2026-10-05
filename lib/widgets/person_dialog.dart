import 'package:flutter/material.dart';

import '../models/person.dart';
import '../models/trait.dart';
import '../services/mcp_client.dart';
import 'color_picker.dart';

/// Adds a person (with no [person]) or edits one: their name, the
/// [circles] they're in, what matters to them, how much each of [traits]
/// counts toward their relationship health, and their status. Self keeps
/// their name, and is in no circle and never archived. Saves with [save],
/// which gets the fields as `create_person` or `update_person` takes them,
/// and returns what it returned, or null if it was called off.
Future<Person?> showPersonDialog(
  BuildContext context, {
  Person? person,
  List<Circle> circles = const [],
  List<Trait> traits = const [],
  required Future<Person> Function(Map<String, Object?> fields) save,
}) => showDialog<Person>(
  context: context,
  builder: (_) => _PersonDialog(
    person: person,
    circles: circles,
    traits: traits,
    save: save,
  ),
);

class _PersonDialog extends StatefulWidget {
  const _PersonDialog({
    required this.person,
    required this.circles,
    required this.traits,
    required this.save,
  });

  final Person? person;
  final List<Circle> circles;
  final List<Trait> traits;
  final Future<Person> Function(Map<String, Object?> fields) save;

  @override
  State<_PersonDialog> createState() => _PersonDialogState();
}

class _PersonDialogState extends State<_PersonDialog> {
  late final _name = TextEditingController(text: widget.person?.name);
  late final _notes = TextEditingController(text: widget.person?.notes);
  late final _circleIds = {...?widget.person?.circleIds};
  late String _status = widget.person?.status ?? 'active';
  late final _weights = {
    for (final trait in widget.traits)
      if (trait.id != null)
        trait.id!: TextEditingController(
          text: switch (widget.person?.traitWeights[trait.id]) {
            final w? => '${w == w.roundToDouble() ? w.round() : w}',
            null => '',
          },
        ),
  };
  bool _saving = false;
  String? _error;

  bool get _isSelf => widget.person?.isSelf ?? false;

  @override
  void dispose() {
    _name.dispose();
    _notes.dispose();
    for (final c in _weights.values) {
      c.dispose();
    }
    super.dispose();
  }

  String? get _problem {
    if (_name.text.trim().isEmpty) return 'Give them a name.';
    for (final MapEntry(:key, :value) in _weights.entries) {
      final text = value.text.trim();
      if (text.isEmpty) continue;
      final weight = num.tryParse(text);
      if (weight == null || weight < 0) {
        final name = widget.traits.firstWhere((t) => t.id == key).name;
        return "$name's weight must be a number, 0 or more.";
      }
    }
    return null;
  }

  Map<String, Object?> get _fields => {
    'name': _name.text.trim(),
    'notes': _notes.text.trim().isEmpty ? null : _notes.text.trim(),
    'trait_weights': {
      // Kept for traits not offered (off or archived).
      ...?widget.person?.traitWeights,
      for (final MapEntry(:key, :value) in _weights.entries)
        key: ?num.tryParse(value.text.trim()),
    }..removeWhere((key, _) => _weights[key]?.text.trim().isEmpty ?? false),
    if (!_isSelf) ...{
      'circle_ids': [..._circleIds],
      'status': _status,
    },
  };

  Future<void> _save() async {
    final navigator = Navigator.of(context);
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      navigator.pop(await widget.save(_fields));
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
    final problem = _problem;
    return AlertDialog(
      title: Text(switch (widget.person) {
        null => 'New person',
        final p when p.isSelf => 'Self',
        final p => 'Edit ${personName(p)}',
      }),
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
                autofocus: widget.person == null,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Name',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                onChanged: (_) => setState(() {}),
              ),
              if (!_isSelf) ...[
                Padding(
                  padding: const EdgeInsets.only(top: 16, bottom: 4),
                  child: Text('Circles', style: theme.textTheme.titleSmall),
                ),
                if (widget.circles.isEmpty)
                  Text(
                    'No circles yet: add one from the People section.',
                    style: theme.textTheme.bodySmall,
                  )
                else
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final circle in widget.circles)
                        FilterChip(
                          avatar: switch (parseColor(circle.color)) {
                            final c? => ColorDot(color: c, size: 12),
                            null => null,
                          },
                          label: Text(circle.name),
                          selected: _circleIds.contains(circle.id),
                          onSelected: (on) => setState(
                            () => on
                                ? _circleIds.add(circle.id)
                                : _circleIds.remove(circle.id),
                          ),
                        ),
                    ],
                  ),
              ],
              Padding(
                padding: const EdgeInsets.only(top: 16),
                child: TextField(
                  controller: _notes,
                  minLines: 3,
                  maxLines: 10,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: InputDecoration(
                    labelText: _isSelf
                        ? 'Notes on you'
                        : 'What matters to them',
                    hintText: '- 2026-10-05: starts a new job in November',
                    helperText:
                        'One dated line each: facts, moments coming up, '
                        'preferences.',
                    border: const OutlineInputBorder(),
                    floatingLabelBehavior: FloatingLabelBehavior.always,
                  ),
                ),
              ),
              if (widget.traits.isNotEmpty) ...[
                Padding(
                  padding: const EdgeInsets.only(top: 16, bottom: 4),
                  child: Text(
                    'Relationship health',
                    style: theme.textTheme.titleSmall,
                  ),
                ),
                Text(
                  "The weighted mean of their traits' scores. A trait with "
                  'no weight weighs 1; 0 leaves it out.',
                  style: theme.textTheme.bodySmall,
                ),
                for (final trait in widget.traits)
                  if (_weights[trait.id] case final controller?)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: TextField(
                        controller: controller,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: InputDecoration(
                          labelText: '${trait.name} weight',
                          hintText: '1',
                          isDense: true,
                          border: const OutlineInputBorder(),
                          floatingLabelBehavior: FloatingLabelBehavior.always,
                        ),
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
              ],
              if (!_isSelf && widget.person != null) ...[
                const SizedBox(height: 16),
                SegmentedButton<String>(
                  showSelectedIcon: false,
                  segments: [
                    for (final MapEntry(:key, :value) in personStatuses.entries)
                      ButtonSegment(value: key, label: Text(value)),
                  ],
                  selected: {_status},
                  onSelectionChanged: (picked) =>
                      setState(() => _status = picked.single),
                ),
              ],
              if (problem != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    problem,
                    style: TextStyle(color: theme.colorScheme.error),
                  ),
                ),
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
          child: const Text('Save'),
        ),
      ],
    );
  }
}

/// Adds a circle (with no [circle]) or edits one: its name and color.
/// Saves with [save]; "Delete", asked first, calls [delete]. Returns true
/// if anything was saved or deleted.
Future<bool> showCircleDialog(
  BuildContext context, {
  Circle? circle,
  required Future<void> Function(Map<String, Object?> fields) save,
  Future<void> Function()? delete,
}) async =>
    await showDialog<bool>(
      context: context,
      builder: (_) => _CircleDialog(circle: circle, save: save, delete: delete),
    ) ??
    false;

class _CircleDialog extends StatefulWidget {
  const _CircleDialog({
    required this.circle,
    required this.save,
    required this.delete,
  });

  final Circle? circle;
  final Future<void> Function(Map<String, Object?> fields) save;
  final Future<void> Function()? delete;

  @override
  State<_CircleDialog> createState() => _CircleDialogState();
}

class _CircleDialogState extends State<_CircleDialog> {
  late final _name = TextEditingController(text: widget.circle?.name);
  late Color? _color = parseColor(widget.circle?.color);
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    final navigator = Navigator.of(context);
    try {
      await action();
      navigator.pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(
        () => _error = switch (e) {
          McpException(:final message) => message,
          _ => '$e',
        },
      );
    }
  }

  Future<void> _delete() async {
    final name = widget.circle?.name ?? 'this circle';
    final sure = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete $name?'),
        content: const Text(
          'Everyone in it stays; they just leave the circle.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Keep it'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (sure == true) await _run(widget.delete!);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final named = _name.text.trim().isNotEmpty;
    return AlertDialog(
      title: Text(widget.circle == null ? 'New circle' : 'Edit circle'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_error case final error?)
                Text(
                  "Couldn't save. $error",
                  style: TextStyle(color: theme.colorScheme.error),
                ),
              TextField(
                controller: _name,
                autofocus: widget.circle == null,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Name',
                  hintText: 'e.g. Family',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                onChanged: (_) => setState(() {}),
              ),
              Padding(
                padding: const EdgeInsets.only(top: 16, bottom: 4),
                child: Text('Color', style: theme.textTheme.titleSmall),
              ),
              ColorPicker(
                color: _color,
                onChanged: (color) => setState(() => _color = color),
              ),
            ],
          ),
        ),
      ),
      actions: [
        if (widget.circle != null && widget.delete != null)
          TextButton(onPressed: _delete, child: const Text('Delete')),
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: named
              ? () => _run(
                  () => widget.save({
                    'name': _name.text.trim(),
                    'color': switch (_color) {
                      final c? => colorToHex(c),
                      null => null,
                    },
                  }),
                )
              : null,
          child: const Text('Save'),
        ),
      ],
    );
  }
}
