import 'package:flutter/material.dart';

import '../models/person.dart';
import '../models/trait.dart';
import '../services/focus_store.dart';
import 'edit_page.dart';
import 'error_sheet.dart';
import 'focus_buttons.dart';
import 'traits_field.dart';

/// Adds a person (with no [person]) or edits one, on a page of its own
/// ([EditPage]): their name, a context
/// that tells them apart from others of the same name, the [circles]
/// they're in, what matters to them, which of [traits] apply to them --
/// every active one, or those picked -- with their own parts for any, and
/// their status. Self is in no circle and always active. Saves with
/// [save], which gets the fields as `create_person` or `update_person`
/// takes them (null to clear one), and returns what it returned, or null
/// if it was called off. [actions] names the actions and groups a part
/// can count. With [focus], a star beside Save prioritizes someone
/// already there, at once.
Future<Person?> showPersonEditor(
  BuildContext context, {
  Person? person,
  List<Circle> circles = const [],
  List<Trait> traits = const [],
  Map<String, String> actions = const {},
  FocusStore? focus,
  required Future<Person> Function(Map<String, Object?> fields) save,
}) => showEditPage<Person>(
  context,
  _PersonEditor(
    person: person,
    circles: circles,
    traits: traits,
    actions: actions,
    focus: focus,
    save: save,
  ),
);

class _PersonEditor extends StatefulWidget {
  const _PersonEditor({
    required this.person,
    required this.circles,
    required this.traits,
    required this.actions,
    required this.focus,
    required this.save,
  });

  final Person? person;
  final List<Circle> circles;
  final List<Trait> traits;
  final Map<String, String> actions;
  final FocusStore? focus;
  final Future<Person> Function(Map<String, Object?> fields) save;

  @override
  State<_PersonEditor> createState() => _PersonEditorState();
}

class _PersonEditorState extends State<_PersonEditor> {
  late final _name = TextEditingController(text: widget.person?.name);
  late final _context = TextEditingController(text: widget.person?.context);
  late final _whatMatters = TextEditingController(
    text: widget.person?.whatMatters,
  );
  late final _circleIds = {...?widget.person?.circleIds};
  late String _status = widget.person?.status ?? 'active';

  /// Which traits apply to them, and their own parts for any.
  late PersonTraits _traits = widget.person?.traits ?? const PersonTraits();
  bool _saving = false;

  bool get _isSelf => widget.person?.isSelf ?? false;

  @override
  void dispose() {
    _name.dispose();
    _context.dispose();
    _whatMatters.dispose();
    super.dispose();
  }

  String? _text(TextEditingController c) =>
      c.text.trim().isEmpty ? null : c.text.trim();

  Map<String, Object?> get _fields => {
    'name': _name.text.trim(),
    'context': _text(_context),
    'what_matters': _text(_whatMatters),
    'traits': _traits.isDefault ? null : _traits.toJson(),
    if (!_isSelf) ...{
      'circles': [..._circleIds],
      'status': _status,
    },
  };

  Future<void> _save() async {
    final navigator = Navigator.of(context);
    setState(() => _saving = true);
    try {
      navigator.pop(await widget.save(_fields));
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
    final problem = _name.text.trim().isEmpty ? 'Give them a name.' : null;
    final person = widget.person;
    return EditPage(
      title: switch (person) {
        null => 'New person',
        final p when p.isSelf => 'Self',
        final p => 'Edit ${personName(p)}',
      },
      actions: [
        if ((widget.focus, person) case (final focus?, final person?)
            when !person.isSelf)
          prioritizeButton(focus, person),
      ],
      problem: problem,
      saving: _saving,
      onSave: _save,
      children: [
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
        if (!_isSelf)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: TextField(
              controller: _context,
              decoration: const InputDecoration(
                labelText: 'Context (optional)',
                hintText: 'e.g. met at salsa',
                helperText:
                    'What tells them apart from others of the same '
                    'name.',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
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
            controller: _whatMatters,
            minLines: 6,
            maxLines: null,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              labelText: _isSelf
                  ? 'What matters to you'
                  : 'What matters to them',
              hintText: '- 2026-10-05: starts a new job in November',
              helperText:
                  'One dated line each: facts, moments coming up, '
                  'preferences.',
              helperMaxLines: 2,
              border: const OutlineInputBorder(),
              floatingLabelBehavior: FloatingLabelBehavior.always,
            ),
          ),
        ),
        TraitsField(
          traits: widget.traits,
          value: _traits,
          actions: widget.actions,
          partsTitle: (trait) => '${trait.name} for ${_text(_name) ?? 'them'}',
          partsExplanation: (trait) =>
              "Their own parts for ${trait.name}, in place of the "
              "trait's: their own cadence, say.",
          onChanged: (traits) => _traits = traits,
        ),
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
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(switch (_status) {
              'archived' => 'Out of touch: kept, out of the way.',
              'deleted' => "Shouldn't have existed.",
              _ => 'Someone you spend time with.',
            }, style: theme.textTheme.bodySmall),
          ),
        ],
      ],
    );
  }
}

/// Adds a circle (with no [circle]) or edits one: its name and note.
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
      builder: (_) => _NamedDialog(
        noun: 'circle',
        name: circle?.name,
        detail: circle?.note,
        detailField: 'note',
        detailLabel: 'Note (optional)',
        detailHint: 'Who they are to you',
        nameHint: 'e.g. Family',
        deleteExplanation: 'Everyone in it stays; they just leave the circle.',
        save: save,
        delete: delete,
      ),
    ) ??
    false;

/// Adds a location (with no [location]) or edits one: its name and a hint
/// for recognizing it. Saves with [save], returning what it returned, or
/// null if it was called off. "Delete", asked first, calls [delete]: then
/// [location] is returned.
Future<Location?> showLocationDialog(
  BuildContext context, {
  Location? location,
  required Future<Location> Function(Map<String, Object?> fields) save,
  Future<void> Function()? delete,
}) async {
  Location? saved;
  final done = await showDialog<bool>(
    context: context,
    builder: (_) => _NamedDialog(
      noun: 'location',
      name: location?.name,
      detail: location?.hint,
      detailField: 'hint',
      detailLabel: 'Hint (optional)',
      detailHint: "Other names, an address: \"the apartment; 'my place'\"",
      nameHint: 'e.g. Home',
      deleteExplanation:
          "Events there keep its id, but won't say where they were.",
      save: (fields) async => saved = await save(fields),
      delete: delete,
    ),
  );
  return done == true ? saved ?? location : null;
}

/// A name, and one more line of text, to save or delete.
class _NamedDialog extends StatefulWidget {
  const _NamedDialog({
    required this.noun,
    required this.name,
    required this.detail,
    required this.detailField,
    required this.detailLabel,
    required this.detailHint,
    required this.nameHint,
    required this.deleteExplanation,
    required this.save,
    required this.delete,
  });

  final String noun;
  final String? name;
  final String? detail;
  final String detailField;
  final String detailLabel;
  final String detailHint;
  final String nameHint;
  final String deleteExplanation;
  final Future<void> Function(Map<String, Object?> fields) save;
  final Future<void> Function()? delete;

  @override
  State<_NamedDialog> createState() => _NamedDialogState();
}

class _NamedDialogState extends State<_NamedDialog> {
  late final _name = TextEditingController(text: widget.name);
  late final _detail = TextEditingController(text: widget.detail);

  @override
  void dispose() {
    _name.dispose();
    _detail.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    final navigator = Navigator.of(context);
    try {
      await action();
      navigator.pop(true);
    } catch (e) {
      if (mounted) {
        await showErrorSheet(
          context,
          title: "Couldn't save",
          error: e,
          onRetry: () => _run(action),
        );
      }
    }
  }

  Future<void> _delete() async {
    final name = widget.name ?? 'this ${widget.noun}';
    final sure = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete $name?'),
        content: Text(widget.deleteExplanation),
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
    final named = _name.text.trim().isNotEmpty;
    return AlertDialog(
      title: Text(
        widget.name == null ? 'New ${widget.noun}' : 'Edit ${widget.noun}',
      ),
      content: SizedBox(
        width: 420,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _name,
              autofocus: widget.name == null,
              maxLength: 50,
              textCapitalization: TextCapitalization.words,
              decoration: InputDecoration(
                labelText: 'Name',
                hintText: widget.nameHint,
                border: const OutlineInputBorder(),
                isDense: true,
              ),
              onChanged: (_) => setState(() {}),
            ),
            TextField(
              controller: _detail,
              minLines: 1,
              maxLines: 3,
              decoration: InputDecoration(
                labelText: widget.detailLabel,
                hintText: widget.detailHint,
                border: const OutlineInputBorder(),
                isDense: true,
              ),
            ),
          ],
        ),
      ),
      actions: [
        if (widget.name != null && widget.delete != null)
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
                    widget.detailField: _detail.text.trim().isEmpty
                        ? null
                        : _detail.text.trim(),
                  }),
                )
              : null,
          child: const Text('Save'),
        ),
      ],
    );
  }
}
