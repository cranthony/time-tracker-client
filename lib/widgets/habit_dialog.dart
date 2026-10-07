import 'package:flutter/material.dart';

import '../models/habit.dart';
import '../models/person.dart';
import '../models/plan_action.dart';
import '../models/trait.dart';
import 'actions_picker.dart';
import 'color_picker.dart';
import 'error_sheet.dart';
import 'traits_field.dart';

/// Adds a habit (with no [habit]) or edits one: its name, the action or
/// group of [actions] whose events it's about, a note on what it's for,
/// which of [traits] apply to it -- every active one, or those picked --
/// with its own parts for any, and its status. A part of its own that
/// counts an action outside it, or reads events done for someone, is
/// warned of. Saves with [save], which gets the fields as `create_habit`
/// or `update_habit` takes them (null to clear one), and returns what it
/// returned, or null if it was called off.
Future<Habit?> showHabitDialog(
  BuildContext context, {
  Habit? habit,
  List<PlanAction> actions = const [],
  List<Trait> traits = const [],
  required Future<Habit> Function(Map<String, Object?> fields) save,
}) => showDialog<Habit>(
  context: context,
  builder: (_) =>
      _HabitDialog(habit: habit, actions: actions, traits: traits, save: save),
);

/// A dot in [action]'s color, or a gap as wide, if it has none.
Widget actionDot(PlanAction? action, {double size = 12}) =>
    switch (parseColor(action?.backgroundColor ?? action?.effectiveColor)) {
      final c? => ColorDot(color: c, size: size),
      null => SizedBox(width: size),
    };

class _HabitDialog extends StatefulWidget {
  const _HabitDialog({
    required this.habit,
    required this.actions,
    required this.traits,
    required this.save,
  });

  final Habit? habit;
  final List<PlanAction> actions;
  final List<Trait> traits;
  final Future<Habit> Function(Map<String, Object?> fields) save;

  @override
  State<_HabitDialog> createState() => _HabitDialogState();
}

class _HabitDialogState extends State<_HabitDialog> {
  late final _name = TextEditingController(text: widget.habit?.name);
  late final _note = TextEditingController(text: widget.habit?.note);
  late String? _actionId = widget.habit?.actionId;
  late String _status = widget.habit?.status ?? 'active';
  late PersonTraits _traits = widget.habit?.traits ?? const PersonTraits();
  bool _saving = false;

  late final Map<String, PlanAction> _byId = {
    for (final a in widget.actions) ?a.id: a,
  };

  @override
  void dispose() {
    _name.dispose();
    _note.dispose();
    super.dispose();
  }

  String? get _noteText => _note.text.trim().isEmpty ? null : _note.text.trim();

  String _actionName(String id) => switch (_byId[id]) {
    final a? => a.path ?? actionName(a),
    null => id,
  };

  /// The actions and groups a part of its own can count, by path: its
  /// action, or those under its group.
  Map<String, String> get _inScope => {
    for (final a in widget.actions)
      if (a.id case final id?
          when a.status != 'deleted' &&
              _actionId != null &&
              inScope(_actionId!, id, (id) => _byId[id]?.parentId))
        id: a.path ?? actionName(a),
  };

  Map<String, Object?> get _fields => {
    'name': _name.text.trim(),
    'action_id': _actionId,
    'note': _noteText,
    'traits': _traits.isDefault ? null : _traits.toJson(),
    if (widget.habit != null) 'status': _status,
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
    final problem = _name.text.trim().isEmpty
        ? 'Give it a name.'
        : _actionId == null
        ? 'Pick the action or group it is about.'
        : null;
    final name = _name.text.trim().isEmpty ? 'it' : _name.text.trim();
    return AlertDialog(
      title: Text(switch (widget.habit) {
        null => 'New habit',
        final h => 'Edit ${habitName(h)}',
      }),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _name,
                autofocus: widget.habit == null,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Name',
                  hintText: 'e.g. Practice guitar mindfully',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                onChanged: (_) => setState(() {}),
              ),
              Padding(
                padding: const EdgeInsets.only(top: 16, bottom: 4),
                child: Text(
                  'Action or group',
                  style: theme.textTheme.titleSmall,
                ),
              ),
              ActionField(
                actions: widget.actions,
                value: _actionId,
                title: 'What is it about?',
                hint: 'Pick an action or group',
                exclude: {
                  // Nothing deleted, nor put away, unless it's there
                  // already.
                  for (final a in widget.actions)
                    if (const {'archived', 'deleted'}.contains(a.status) &&
                        a.id != _actionId)
                      ?a.id,
                },
                marker: actionDot,
                onChanged: (id) => setState(() => _actionId = id),
              ),
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  'Its events are yours with this action, or with any '
                  'action under this group.',
                  style: theme.textTheme.bodySmall,
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(top: 16),
                child: TextField(
                  controller: _note,
                  minLines: 2,
                  maxLines: 6,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                    labelText: 'Note (optional)',
                    hintText:
                        'What it is for, and what doing it well looks '
                        'like',
                    helperText: 'Claude judges its events with this in mind.',
                    helperMaxLines: 2,
                    border: OutlineInputBorder(),
                    floatingLabelBehavior: FloatingLabelBehavior.always,
                  ),
                ),
              ),
              TraitsField(
                // Again for another action, so its warnings are new.
                key: ValueKey(_actionId),
                traits: widget.traits,
                value: _traits,
                own: 'Its own',
                actions: _inScope,
                partsTitle: (trait) => '${trait.name} for $name',
                partsExplanation: (trait) =>
                    "Its own parts for ${trait.name}, in place of the "
                    "trait's: a rubric for this habit alone, say. Counts, "
                    'time spent and the like count only its events, and '
                    "you're at every one.",
                warnings: _actionId == null
                    ? null
                    : (parts) => habitPartWarnings(
                        parts,
                        _actionId!,
                        (id) => _byId[id]?.parentId,
                        {for (final id in _byId.keys) id: _actionName(id)},
                      ),
                onChanged: (traits) => setState(() => _traits = traits),
              ),
              ..._warnings(theme),
              if (widget.habit != null) ...[
                const SizedBox(height: 16),
                SegmentedButton<String>(
                  showSelectedIcon: false,
                  segments: [
                    for (final MapEntry(:key, :value) in habitStatuses.entries)
                      ButtonSegment(value: key, label: Text(value)),
                  ],
                  selected: {_status},
                  onSelectionChanged: (picked) =>
                      setState(() => _status = picked.single),
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(switch (_status) {
                    'archived' => 'Set aside: kept, out of the way.',
                    'deleted' => "Shouldn't have existed.",
                    _ => "One you're working on.",
                  }, style: theme.textTheme.bodySmall),
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

  /// What's amiss with its own parts, as they stand: those that count
  /// nothing here, or read events done for someone.
  List<Widget> _warnings(ThemeData theme) {
    final scope = _actionId;
    if (scope == null) return const [];
    final traitNames = {for (final t in widget.traits) t.id: t.name};
    return [
      for (final MapEntry(:key, :value) in _traits.parts.entries)
        for (final warning in habitPartWarnings(
          value,
          scope,
          (id) => _byId[id]?.parentId,
          {for (final id in _byId.keys) id: _actionName(id)},
        ))
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              '${traitNames[key] ?? key}: $warning',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.tertiary,
              ),
            ),
          ),
    ];
  }
}
