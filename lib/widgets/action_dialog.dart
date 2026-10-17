import 'package:flutter/material.dart';

import '../models/plan_action.dart';
import '../services/mcp_client.dart';
import 'hotkeys.dart';
import 'action_icon.dart';
import 'actions_picker.dart';
import 'color_picker.dart';
import 'error_sheet.dart';

/// The priorities offered as chips; "…" takes any other.
const _priorities = [0, 1, 2, 3];

/// Saves [changes] to [action], returning every action as they're to be
/// shown now.
typedef SaveAction = Future<ActionList> Function(
  PlanAction action,
  Map<String, Object?> changes,
);

/// Edits [action] -- an action or a group -- opening ready to edit, as
/// the Locations pane's dialogs do: its name, the group it's in, its
/// status (an action's), priority, color and note, each as
/// `update_action` and `update_action_group` take them. What it inherits
/// from a group, or for a color its priority, is said under each.
///
/// "Save" sends every change with [save], after [confirmSave], given the
/// changes, says to go ahead. Returns what [save] returned (every action,
/// as they're to be shown now), or null if nothing was saved. [actions]
/// are every action and group, for the group it's in and what it
/// inherits. [changes] opens it with those already made: ones that
/// couldn't be saved before.
Future<ActionList?> showActionDialog(
  BuildContext context,
  PlanAction action, {
  required List<PlanAction> actions,
  required SaveAction save,
  Future<bool> Function(Map<String, Object?> changes)? confirmSave,
  Map<String, Object?> changes = const {},
}) => showDialog<ActionList>(
  context: context,
  builder: (_) => _ActionDialog(
    action: action,
    isNew: false,
    actions: actions,
    changes: changes,
    confirmSave: confirmSave,
    save: (changes) => save(action, changes),
  ),
);

/// The dialog [showActionDialog] edits in, for a new action -- or with
/// [group], a group of them -- in group [parentId] if given, made with
/// [create] on "Save". Returns what [create] returned (every action, as
/// they're to be shown now), or null if nothing was made. [fields] opens
/// it with those already filled in: one that couldn't be made before.
Future<ActionList?> showNewActionDialog(
  BuildContext context, {
  required Future<ActionList> Function(Map<String, Object?> fields) create,
  required List<PlanAction> actions,
  String? parentId,
  bool group = false,
  Map<String, Object?> fields = const {},
}) {
  final isGroup = group || fields['kind'] == 'group';
  return showDialog<ActionList>(
    context: context,
    builder: (_) => _ActionDialog(
      action: PlanAction(
        parentId: parentId,
        properties: {if (isGroup) 'kind': 'group'},
      ),
      isNew: true,
      actions: actions,
      changes: {
        for (final MapEntry(:key, :value) in fields.entries)
          if (key != 'parent_id' && key != 'kind' && value != null) key: value,
      },
      save: (changes) => create({
        'parent_id': parentId,
        if (isGroup) 'kind': 'group',
        for (final MapEntry(:key, :value) in changes.entries) key: ?value,
      }),
    ),
  );
}

class _ActionDialog extends StatefulWidget {
  const _ActionDialog({
    required this.action,
    required this.isNew,
    required this.actions,
    required this.changes,
    required this.save,
    this.confirmSave,
  });

  final PlanAction action;
  final bool isNew;
  final List<PlanAction> actions;
  final Map<String, Object?> changes;
  final Future<ActionList> Function(Map<String, Object?> changes) save;
  final Future<bool> Function(Map<String, Object?> changes)? confirmSave;

  @override
  State<_ActionDialog> createState() => _ActionDialogState();
}

class _ActionDialogState extends State<_ActionDialog> {
  /// What's been changed, keyed as `update_action` takes it; null clears.
  late final _changes = <String, Object?>{...widget.changes};

  late final _name = TextEditingController(text: _value('name') as String?);
  late final _note = TextEditingController(text: _value('note') as String?);

  /// Whether "…" was picked, to type a priority not among [_priorities].
  late bool _otherPriority = switch (_priority) {
    final p? => !_priorities.contains(p),
    null => false,
  };
  late final _otherController = TextEditingController(
    text: _otherPriority ? '$_priority' : '',
  );

  bool _saving = false;

  PlanAction get _action => widget.action;

  /// As it was, keyed as `update_action` takes it.
  late final Map<String, Object?> _was = {
    'name': _action.name,
    'parent_id': _action.parentId,
    'status': _action.status,
    'priority': _action.priority,
    'background_color': _action.backgroundColor,
    'note': _action.properties['note'] as String?,
    'commute': _action.commute,
  };

  @override
  void dispose() {
    _name.dispose();
    _note.dispose();
    _otherController.dispose();
    super.dispose();
  }

  /// [key]'s value as it'll be saved: changed, or as it was.
  Object? _value(String key) =>
      _changes.containsKey(key) ? _changes[key] : _was[key];

  String? get _parentId => _value('parent_id') as String?;
  String get _status => _value('status') as String? ?? 'active';
  int? get _priority => _value('priority') as int?;
  String? get _color => _value('background_color') as String?;
  bool get _commute => _value('commute')! as bool;

  /// Sets [key] to [value], dropping the change if that's how it was.
  void _set(String key, Object? value) => setState(() {
    if (value == _was[key]) {
      _changes.remove(key);
    } else {
      _changes[key] = value;
    }
  });

  /// [text] trimmed, or null if that leaves nothing.
  static String? _trimmed(String text) =>
      text.trim().isEmpty ? null : text.trim();

  /// The listed action with [id], if it's listed.
  PlanAction? _byId(String? id) =>
      id == null ? null : widget.actions.where((g) => g.id == id).firstOrNull;

  /// The groups it's in, nearest first, as far as they're listed: in the
  /// group picked, if it's been moved.
  List<PlanAction> get _ancestors {
    final chain = <PlanAction>[];
    var parent = _byId(_parentId);
    while (parent != null && !chain.contains(parent)) {
      chain.add(parent);
      parent = _byId(parent.parentId);
    }
    return chain;
  }

  /// What it inherits for priority: its group's, if that's listed;
  /// otherwise what the server said, if it hasn't moved.
  int? get _inheritedPriority => switch (_byId(_parentId)) {
    final parent? => parent.effectivePriority,
    null when _parentId == _action.parentId && _action.inheritsPriority =>
      _action.effectivePriority,
    null => null,
  };

  /// The nearest group it's in with a priority of its own.
  PlanAction? get _priorityFrom =>
      _ancestors.where((g) => g.priority != null).firstOrNull;

  /// The nearest group it's in with a color of its own.
  PlanAction? get _colorFrom => _ancestors
      .where((g) => parseColor(g.backgroundColor) != null)
      .firstOrNull;

  /// The color its label is shown in, as it'll be saved.
  Color get _shownColor =>
      parseColor(_color) ??
      parseColor(_colorFrom?.backgroundColor) ??
      (_changes.isEmpty ? parseColor(_action.effectiveColor) : null) ??
      priorityColor(_priority ?? _inheritedPriority);

  Future<void> _save() async {
    final navigator = Navigator.of(context);
    final changes = Map.of(_changes);
    if (widget.confirmSave case final confirm?
        when !widget.isNew && !await confirm(changes)) {
      return;
    }
    setState(() => _saving = true);
    try {
      final saved = await widget.save(changes);
      navigator.pop(saved);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      await showErrorSheet(
        context,
        title: "Couldn't save",
        error: e,
        message: e is SignInRequiredException
            ? 'You were signed out. Sign in again from the Plan page, then '
                  'try again.'
            : null,
        onRetry: _save,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final noun = _action.isGroup ? 'group' : 'action';
    final named = _name.text.trim().isNotEmpty;
    final changed = widget.isNew || _changes.isNotEmpty;
    // As it'll look: its icon in the color it'll be.
    final preview = PlanAction(
      status: _status,
      backgroundColor: _color,
      effectiveColor: colorToHex(_shownColor),
      properties: _action.properties,
    );
    return SaveOrDiscard(
      changed: () => _changes.isNotEmpty || (widget.isNew && named),
      onSave: _saving || !named || !changed ? null : _save,
      escLeavesFields: true,
      onDiscard: () {
        if (!_saving) Navigator.of(context).pop();
      },
      child: AlertDialog(
        title: Row(
          children: [
            ActionIcon(preview, size: 28),
            const SizedBox(width: 12),
            Expanded(child: Text('${widget.isNew ? 'New' : 'Edit'} $noun')),
          ],
        ),
        content: SizedBox(
          width: 440,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 4),
                FieldHotkey(
                  'N',
                  child: TextField(
                    controller: _name,
                    autofocus: widget.isNew,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: InputDecoration(
                      labelText: 'Name',
                      hintText: _action.isGroup
                          ? 'e.g. Cooking'
                          : 'e.g. Make tofu',
                      border: const OutlineInputBorder(),
                      isDense: true,
                    ),
                    onChanged: (typed) => _set('name', _trimmed(typed)),
                  ),
                ),
                _Section(
                  label: 'Group',
                  letter: 'G',
                  child: ActionField(
                    actions: widget.actions,
                    value: _parentId,
                    title: 'Pick its group',
                    noneLabel: 'None (top-level)',
                    exclude: {
                      // Not under itself, nor under an action -- only groups
                      // hold anything -- or one put away, unless it's there
                      // already.
                      if (_action.id case final id?)
                        ...actionAndSubActions(widget.actions, id),
                      for (final action in widget.actions)
                        if ((!action.isGroup ||
                                const {
                                  'archived',
                                  'deleted',
                                }.contains(action.status)) &&
                            action.id != _parentId)
                          ?action.id,
                    },
                    marker: (action) => ActionIcon(action, size: 18),
                    onChanged: (id) => _set('parent_id', id),
                  ),
                ),
                if (!_action.isGroup && !widget.isNew)
                  _Section(
                    label: 'Status',
                    letter: 'S',
                    onLetter: () => _set(
                      'status',
                      nextOf(actionStatuses.keys.toList(), _status),
                    ),
                    hint: _status == 'active' || _status == 'proposed'
                        ? "It holds one of the calendar's event labels."
                        : "It doesn't hold an event label; its history is kept.",
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        for (final MapEntry(key: status, value: label)
                            in actionStatuses.entries)
                          ChoiceChip(
                            showCheckmark: false,
                            label: Text(label),
                            selected: _status == status,
                            onSelected: (_) => _set('status', status),
                          ),
                      ],
                    ),
                  ),
                _Section(
                  label: 'Priority',
                  letter: 'P',
                  onLetter: () {
                    _otherPriority = false;
                    _otherController.clear();
                    _set(
                      'priority',
                      nextOf<int?>([null, ..._priorities], _priority),
                    );
                  },
                  hint: switch ((_priority, _inheritedPriority)) {
                    (_?, _) =>
                      '0 is the most important. Its events, and the actions in '
                          'it with no priority of their own, take this one.',
                    (null, final p?) =>
                      'Inherited: P$p, from '
                          '${_priorityFrom == null ? 'its group' : actionName(_priorityFrom!)}.',
                    (null, null) => 'No priority here or in its groups.',
                  },
                  child: _priorityChips(),
                ),
                _Section(
                  label: 'Color',
                  letter: 'C',
                  hint: switch ((parseColor(_color), _colorFrom)) {
                    (_?, _) => null,
                    (null, final from?) =>
                      "With no color, it takes ${actionName(from)}'s.",
                    (null, null) =>
                      "With no color, it takes its priority's "
                          '(P${_priority ?? _inheritedPriority ?? defaultPriority}).',
                  },
                  child: ColorPicker(
                    color: parseColor(_color),
                    onChanged: (color) => _set(
                      'background_color',
                      color == null ? null : colorToHex(color),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                FieldHotkey(
                  'O',
                  child: TextField(
                    controller: _note,
                    minLines: 2,
                    maxLines: 6,
                    decoration: InputDecoration(
                      labelText: 'Note (optional)',
                      hintText: _action.isGroup
                          ? 'What it covers'
                          : 'What counts as it',
                      border: const OutlineInputBorder(),
                      isDense: true,
                    ),
                    onChanged: (typed) => _set('note', _trimmed(typed)),
                  ),
                ),
                if (!_action.isGroup)
                  FieldHotkey(
                    'M',
                    child: SwitchListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                      secondary: const Icon(Icons.directions_walk),
                      title: const Text('A way to commute'),
                      subtitle: const Text(
                        'Events with a commute are pushed with the events they '
                        'lead to or from.',
                      ),
                      value: _commute,
                      onChanged: (on) => _set('commute', on),
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
          HotkeyHint(
            Hotkey.save,
            child: FilledButton(
              onPressed: _saving || !named || !changed ? null : _save,
              child: const Text('Save'),
            ),
          ),
        ],
      ),
    );
  }

  /// No priority of its own (so it inherits one), one of [_priorities], or
  /// "…" for another, typed.
  Widget _priorityChips() {
    final own = _priority;
    final inherited = _inheritedPriority;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            ChoiceChip(
              showCheckmark: false,
              label: Text(inherited == null ? 'None' : 'Inherit (P$inherited)'),
              selected: own == null && !_otherPriority,
              onSelected: (_) {
                _otherPriority = false;
                _otherController.clear();
                _set('priority', null);
              },
            ),
            for (final p in _priorities)
              ChoiceChip(
                showCheckmark: false,
                avatar: CircleAvatar(backgroundColor: priorityColor(p)),
                label: Text('P$p'),
                selected: own == p && !_otherPriority,
                onSelected: (_) {
                  _otherPriority = false;
                  _otherController.clear();
                  _set('priority', p);
                },
              ),
            ChoiceChip(
              showCheckmark: false,
              label: const Text('…'),
              tooltip: 'Another priority',
              selected: _otherPriority,
              onSelected: (_) => setState(() => _otherPriority = true),
            ),
          ],
        ),
        if (_otherPriority)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: TextField(
              controller: _otherController,
              autofocus: _otherController.text.isEmpty,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Priority',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              onChanged: (typed) {
                if (int.tryParse(typed.trim()) case final p?) {
                  _set('priority', p);
                }
              },
            ),
          ),
      ],
    );
  }
}

/// One of the dialog's fields: [label] over [child], and [hint], if
/// there's one, under it; [letter] goes to it ([FieldHotkey]), or does
/// [onLetter].
class _Section extends StatelessWidget {
  const _Section({
    required this.label,
    required this.letter,
    required this.child,
    this.hint,
    this.onLetter,
  });

  final String label;
  final String letter;
  final VoidCallback? onLetter;
  final Widget child;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(label, style: theme.textTheme.labelLarge),
          const SizedBox(height: 6),
          FieldHotkey(letter, onPressed: onLetter, child: child),
          if (hint case final hint?)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(hint, style: muted),
            ),
        ],
      ),
    );
  }
}
