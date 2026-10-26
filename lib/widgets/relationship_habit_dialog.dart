import 'package:flutter/material.dart';

import 'hotkeys.dart';
import '../models/habit.dart';
import '../models/habit_graph.dart';
import '../models/person.dart';
import '../models/trait.dart';
import 'edit_page.dart';
import 'error_sheet.dart';
import 'foundations_field.dart';

/// The most traits left out that a person's or circle's habit keeps as
/// those left out -- so traits added later are on it -- rather than as
/// those picked.
const maxExcepted = 2;

/// Which of [all] (trait ids) a person's or circle's habit is on, with
/// [picked] picked: every one; all but a few ([maxExcepted]), as those
/// left out; or else those picked.
PersonTraits relationshipSelection(Set<String> picked, List<String> all) {
  final left = [
    for (final id in all)
      if (!picked.contains(id)) id,
  ];
  if (left.isEmpty) return const PersonTraits();
  if (left.length <= maxExcepted) return PersonTraits(except: left);
  return PersonTraits(
    select: [
      for (final id in all)
        if (picked.contains(id)) id,
    ],
  );
}

/// Adds a person's or circle's habit (with no [habit]) or edits one, on a
/// page of its own ([EditPage]): which of [traits] -- theirs -- it's on,
/// its name, what it's built on (picked from [foundationChoices], named
/// by [foundationNames]) and, editing one, its status. [whose] names
/// them, and [targetField] -- `person_id` or `circle_id` -- with
/// [targetId] says who they are. Its name is theirs and its traits' until
/// it's given another, and back to that whenever its traits change.
/// Saves with [save], as `create_habit` or `update_habit` takes the
/// fields (null to clear one), returning what it returned, or null if it
/// was called off.
Future<Habit?> showRelationshipHabitEditor(
  BuildContext context, {
  Habit? habit,
  required String whose,
  required String targetField,
  required String targetId,
  required List<Trait> traits,
  List<GraphNode>? foundationChoices,
  Map<String, String> foundationNames = const {},
  required Future<Habit> Function(Map<String, Object?> fields) save,
}) => showEditPage<Habit>(
  context,
  _RelationshipHabitEditor(
    habit: habit,
    whose: whose,
    targetField: targetField,
    targetId: targetId,
    traits: traits,
    foundationChoices: foundationChoices,
    foundationNames: foundationNames,
    save: save,
  ),
);

class _RelationshipHabitEditor extends StatefulWidget {
  const _RelationshipHabitEditor({
    required this.habit,
    required this.whose,
    required this.targetField,
    required this.targetId,
    required this.traits,
    required this.foundationChoices,
    required this.foundationNames,
    required this.save,
  });

  final Habit? habit;
  final String whose;
  final String targetField;
  final String targetId;
  final List<Trait> traits;
  final List<GraphNode>? foundationChoices;
  final Map<String, String> foundationNames;
  final Future<Habit> Function(Map<String, Object?> fields) save;

  @override
  State<_RelationshipHabitEditor> createState() =>
      _RelationshipHabitEditorState();
}

class _RelationshipHabitEditorState extends State<_RelationshipHabitEditor> {
  late final List<String> _all = [
    for (final t in widget.traits)
      if (t.id != null) t.id!,
  ];

  late final Map<String, String> _traitNames = {
    for (final t in widget.traits)
      if (t.id != null) t.id!: t.name,
  };

  late Set<String> _picked = {
    for (final id in _all)
      if (widget.habit?.traits.applies(id) ?? true) id,
  };

  PersonTraits get _selection => relationshipSelection(_picked, _all);

  String get _defaultName =>
      relationshipHabitName(widget.whose, _selection, _traitNames);

  late final _name = TextEditingController(
    text: widget.habit?.name ?? _defaultName,
  );
  late String _status = widget.habit?.status ?? 'active';
  late List<String> _foundations = widget.habit?.foundations ?? const [];
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  /// Picks [id], or unpicks it, naming it by its traits again.
  void _toggle(String id, bool on) => setState(() {
    _picked = on ? {..._picked, id} : ({..._picked}..remove(id));
    _name.text = _defaultName;
  });

  Map<String, Object?> get _fields {
    final selection = _selection;
    return {
      // Its default, if it's that: it has none of its own.
      'name': _name.text.trim(),
      if (widget.habit == null) widget.targetField: widget.targetId,
      'traits': selection.isDefault ? null : selection.toJson(),
      // Only when changed, so a server without them is never asked.
      if (_foundations.join(',') !=
          (widget.habit?.foundations ?? const []).join(','))
        'foundations': _foundations.isEmpty ? null : _foundations,
      if (widget.habit != null) 'status': _status,
    };
  }

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
    final problem = _name.text.trim().isEmpty
        ? 'Give it a name.'
        : _picked.isEmpty && _all.isNotEmpty
        ? 'Pick a trait it is on.'
        : null;
    return EditPage(
      title: switch (widget.habit) {
        null => 'New habit for ${widget.whose}',
        final h => 'Edit ${habitName(h)}',
      },
      problem: problem,
      saving: _saving,
      onSave: _save,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Text('Traits', style: theme.textTheme.titleSmall),
        ),
        FieldHotkey(
          'T',
          focusOnly: true,
          child: Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final t in widget.traits)
                if (t.id case final id?)
                  FilterChip(
                    label: Text(t.name),
                    selected: _picked.contains(id),
                    onSelected: (on) => _toggle(id, on),
                  ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            "Scored as ${widget.whose}'s are, by these alone. With all but "
            '$maxExcepted or fewer picked, traits added later are on it '
            'too.',
            style: theme.textTheme.bodySmall,
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 16),
          child: FieldHotkey(
            'N',
            child: TextField(
              controller: _name,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Name',
                helperText:
                    'Named for them and its traits, until you change it; '
                    'changing its traits names it so again.',
                helperMaxLines: 2,
                border: OutlineInputBorder(),
                isDense: true,
              ),
              onChanged: (_) => setState(() {}),
            ),
          ),
        ),
        if (widget.foundationChoices case final choices?)
          Padding(
            padding: const EdgeInsets.only(top: 16),
            child: FieldHotkey(
              'B',
              child: FoundationsField(
                value: _foundations,
                choices: choices,
                names: widget.foundationNames,
                onChanged: (picked) => setState(() => _foundations = picked),
              ),
            ),
          ),
        if (widget.habit != null) ...[
          const SizedBox(height: 16),
          FieldHotkey(
            'S',
            onPressed: () => setState(
              () => _status = nextOf(habitStatuses.keys.toList(), _status),
            ),
            child: SegmentedButton<String>(
              showSelectedIcon: false,
              segments: [
                for (final MapEntry(:key, :value) in habitStatuses.entries)
                  ButtonSegment(value: key, label: Text(value)),
              ],
              selected: {_status},
              onSelectionChanged: (picked) =>
                  setState(() => _status = picked.single),
            ),
          ),
        ],
      ],
    );
  }
}
