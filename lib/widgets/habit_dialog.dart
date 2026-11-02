import 'goal_editor.dart' show FormattedField;

import 'package:flutter/material.dart';

import 'hotkeys.dart';
import '../models/habit.dart';
import '../models/habit_graph.dart';
import '../models/person.dart';
import '../models/plan_action.dart';
import '../models/goal.dart' show defaultGoalPriority;
import '../models/recurring_goal.dart';
import '../models/sub_goal_template.dart';
import '../models/text_format.dart';
import '../models/trait.dart';
import '../models/trait_scores.dart';
import 'actions_picker.dart';
import 'color_picker.dart';
import 'edit_page.dart';
import 'error_sheet.dart';
import 'foundations_field.dart';
import 'recurring_goal_editor.dart';
import 'sub_goal_editor.dart';
import 'text_editor.dart';
import 'traits_field.dart';

/// Adds a habit (with no [habit]) or edits one, on a page of its own
/// ([EditPage]): its name, the action or
/// group of [actions] whose events it's about -- or, for a recurring
/// goal's habit, the goal made for each day, week or month, picked in
/// place of an action for a new one -- a note on what it's for,
/// which of [traits] apply to it -- every active one, or those picked --
/// with its own parts for any, and its status. A part of its own that
/// counts an action outside it, or reads events done for someone, is
/// warned of. Saves with [save], which gets the fields as `create_habit`
/// or `update_habit` takes them (null to clear one), and returns what it
/// returned, or null if it was called off. With [foundationChoices],
/// what it's built on is picked from them; [foundationNames] names its
/// foundations by id. With [scoreParts], its own parts are scored as
/// they're edited, for the action picked.
Future<Habit?> showHabitEditor(
  BuildContext context, {
  Habit? habit,
  List<PlanAction> actions = const [],
  List<Trait> traits = const [],
  List<GraphNode>? foundationChoices,
  Map<String, String> foundationNames = const {},
  PartsScorer? scoreParts,
  required Future<Habit> Function(Map<String, Object?> fields) save,
}) => showEditPage<Habit>(
  context,
  _HabitEditor(
    habit: habit,
    actions: actions,
    traits: traits,
    foundationChoices: foundationChoices,
    foundationNames: foundationNames,
    scoreParts: scoreParts,
    save: save,
  ),
);

/// A dot in [action]'s color, or a gap as wide, if it has none.
Widget actionDot(PlanAction? action, {double size = 12}) =>
    switch (parseColor(action?.backgroundColor ?? action?.effectiveColor)) {
      final c? => ColorDot(color: c, size: size),
      null => SizedBox(width: size),
    };

class _HabitEditor extends StatefulWidget {
  const _HabitEditor({
    required this.habit,
    required this.actions,
    required this.traits,
    required this.foundationChoices,
    required this.foundationNames,
    required this.scoreParts,
    required this.save,
  });

  final Habit? habit;
  final List<PlanAction> actions;
  final List<Trait> traits;
  final List<GraphNode>? foundationChoices;
  final Map<String, String> foundationNames;
  final PartsScorer? scoreParts;
  final Future<Habit> Function(Map<String, Object?> fields) save;

  @override
  State<_HabitEditor> createState() => _HabitEditorState();
}

class _HabitEditorState extends State<_HabitEditor> {
  late final _name = TextEditingController(text: widget.habit?.name);
  late final _note = TextEditingController(text: widget.habit?.note);
  late TextFormat? _noteFormat = widget.habit?.noteFormat;
  late String? _actionId = widget.habit?.actionId;
  late String _status = widget.habit?.status ?? 'active';

  /// Whether it's a recurring goal's habit: picked for a new one, fixed
  /// for one there is.
  late bool _isGoal = widget.habit?.isGoal ?? false;

  /// Its goal made for each period, but for its chain, as it's been
  /// edited ([showRecurringGoalEditor]).
  late RecurringGoal _goal =
      widget.habit?.recurringGoal ?? const RecurringGoal();

  /// Whether its goal's been set up: one there is, or one saved.
  late bool _goalSet = widget.habit?.recurringGoal != null;

  /// The chain of sub-goals made under each of its goals.
  late List<Map<String, Object?>> _subGoals = [..._goal.subGoals];
  late PersonTraits _traits = widget.habit?.traits ?? const PersonTraits();
  late final PersonTraits _actionTraits = _traits;
  late List<String> _foundations = widget.habit?.foundations ?? const [];
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

  static String? _text(TextEditingController c) =>
      c.text.trim().isEmpty ? null : c.text.trim();

  String get _goalsTitle => _goal.title ?? _text(_name) ?? 'its goal';

  /// Adds a sub-goal to its chain (with no [index]), or edits the one at
  /// [index], removing it if that's asked.
  Future<void> _editSubGoal([int? index]) async {
    final edited = await showSubGoalEditor(
      context,
      sub: index == null ? null : _subGoals[index],
      siblings: [
        for (final (i, s) in _subGoals.indexed)
          if (i != index) s,
      ],
      goalTitle: _goalsTitle,
      goalPriority: _goal.priority ?? defaultGoalPriority,
    );
    if (edited == null || !mounted) return;
    setState(() {
      _subGoals = switch ((index, edited.sub)) {
        (null, final sub?) => [..._subGoals, sub],
        (final i?, final sub?) => [
          for (final (j, s) in _subGoals.indexed) j == i ? sub : s,
        ],
        (final i?, null) => withoutSubGoal(_subGoals, i),
        (null, null) => _subGoals,
      };
    });
  }

  /// Its recurring goal as it's being edited: what the server takes,
  /// kept as it was where this doesn't edit it.
  RecurringGoal get _recurring => _goal.withSubGoals(_subGoals);

  /// Edits its goal on a page of its own.
  Future<void> _editGoal() async {
    final edited = await showRecurringGoalEditor(
      context,
      goal: _goalSet ? _recurring : null,
      habitName: _name.text,
    );
    if (edited == null || !mounted) return;
    setState(() {
      _goal = edited;
      _goalSet = true;
    });
  }

  /// Switches a new habit between an action's and a recurring goal's: a
  /// goal's is scored by its goal rate alone till it's given traits.
  /// Its goal's page opens as it's picked, to be set up.
  void _pickGoal(bool goal) {
    if (goal == _isGoal) return;
    setState(() {
      _isGoal = goal;
      _traits = goal ? const PersonTraits(select: []) : _actionTraits;
    });
    if (goal) _editGoal();
  }

  String? get _noteText => _note.text.trim().isEmpty ? null : _note.text.trim();

  void _setNote(String? text, TextFormat format) {
    _note.text = text ?? '';
    _noteFormat = format;
  }

  /// Edits [text], written in [format], on a page of its own
  /// ([showTextEditor]), setting it (null for nothing) and its format
  /// with [set] unless that's called off.
  Future<void> _editText(
    String title,
    String? text,
    TextFormat? format,
    void Function(String? text, TextFormat format) set,
  ) async {
    final edited = await showTextEditor(
      context,
      title: title,
      text: text,
      format: format,
    );
    if (edited == null || !mounted) return;
    setState(
      () => set(
        edited.text.trim().isEmpty ? null : edited.text.trim(),
        edited.format,
      ),
    );
  }

  /// A field of free text, written in [format], [label] over it as it
  /// reads, tapped to edit, with [helper] beneath.
  Widget _formattedField(
    ThemeData theme,
    String label,
    String? text,
    TextFormat? format,
    String helper,
    void Function(String? text, TextFormat format) set,
  ) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      FormattedField(
        label: label,
        text: text,
        format: format,
        onTap: () => _editText(label, text, format, set),
      ),
      Text(helper, style: theme.textTheme.bodySmall),
    ],
  );

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
    if (_isGoal)
      'recurring_goal': _recurring.toJson()
    else
      'action_id': _actionId,
    'note': _noteText,
    // Only when changed, so a server without it is never asked.
    if ((_noteText == null ? null : _noteFormat) != widget.habit?.noteFormat)
      'note_format': _noteText == null ? null : _noteFormat?.wire,
    'traits': _traits.isDefault ? null : _traits.toJson(),
    // Only when changed, so a server without them is never asked.
    if (_foundations.join(',') !=
        (widget.habit?.foundations ?? const []).join(','))
      'foundations': _foundations.isEmpty ? null : _foundations,
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
        : _isGoal
        ? chainProblems(
            _subGoals,
            goalMinutes: _goal.expectedMinutes,
          ).firstOrNull
        : _actionId == null
        ? 'Pick the action or group it is about.'
        : null;
    final name = _name.text.trim().isEmpty ? 'it' : _name.text.trim();
    return EditPage(
      title: switch (widget.habit) {
        null => 'New habit',
        final h => 'Edit ${habitName(h)}',
      },
      problem: problem,
      saving: _saving,
      onSave: _save,
      children: [
        FieldHotkey(
          'N',
          child: TextField(
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
        ),
        if (widget.habit == null)
          Padding(
            padding: const EdgeInsets.only(top: 16),
            child: FieldHotkey(
              'K',
              onPressed: () => _pickGoal(!_isGoal),
              child: SegmentedButton<bool>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(value: false, label: Text('An action')),
                  ButtonSegment(value: true, label: Text('A recurring goal')),
                ],
                selected: {_isGoal},
                onSelectionChanged: (picked) => _pickGoal(picked.single),
              ),
            ),
          ),
        if (_isGoal) ..._goalFields(theme) else ..._actionFields(theme),
        Padding(
          padding: const EdgeInsets.only(top: 16),
          child: FieldHotkey(
            'O',
            onPressed: _isGoal
                ? () => _editText('Note', _noteText, _noteFormat, _setNote)
                : null,
            child: _isGoal
                ? _formattedField(
                    theme,
                    'Note',
                    _noteText,
                    _noteFormat,
                    'What it is for. Claude judges its events with this in '
                        'mind.',
                    _setNote,
                  )
                : TextField(
                    controller: _note,
                    minLines: 4,
                    maxLines: null,
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
        FieldHotkey(
          'T',
          focusOnly: true,
          child: TraitsField(
            // Again for another action, so its warnings are new.
            key: ValueKey(_actionId),
            traits: widget.traits,
            value: _traits,
            own: 'Its own',
            actions: _inScope,
            // Sleep, say, needn't be in its scope to be set aside.
            exceptionActions: {
              for (final a in widget.actions)
                if (a.id case final id? when a.status != 'deleted')
                  id: a.path ?? actionName(a),
            },
            partsTitle: (trait) => '${trait.name} for $name',
            partsExplanation: (trait) =>
                "Its own parts for ${trait.name}, in place of the "
                "trait's: a rubric for this habit alone, say. Counts, "
                'time spent and the like count only its events, and '
                "you're at every one.",
            warnings: _actionId == null || _isGoal
                ? null
                : (parts) => habitPartWarnings(
                    parts,
                    _actionId!,
                    (id) => _byId[id]?.parentId,
                    {for (final id in _byId.keys) id: _actionName(id)},
                  ),
            preview: switch ((widget.scoreParts, _isGoal ? null : _actionId)) {
              (final score?, final actionId?) => (trait, parts) => score(
                Subject(
                  id: widget.habit?.subject ?? 'habit:',
                  cancelledEvents: widget.habit?.cancelledEvents ?? const [],
                  scope: actionId,
                ),
                trait.id!,
                parts,
              ),
              _ => null,
            },
            onChanged: (traits) => setState(() => _traits = traits),
          ),
        ),
        ..._warnings(theme),
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
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(switch (_status) {
              'archived' => 'Set aside: kept, out of the way.',
              'deleted' => "Shouldn't have existed.",
              _ => "One you're working on.",
            }, style: theme.textTheme.bodySmall),
          ),
        ],
      ],
    );
  }

  /// The action or group it's about, for an action's habit.
  List<Widget> _actionFields(ThemeData theme) => [
    Padding(
      padding: const EdgeInsets.only(top: 16, bottom: 4),
      child: Text('Action or group', style: theme.textTheme.titleSmall),
    ),
    FieldHotkey(
      'A',
      child: ActionField(
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
    ),
    Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Text(
        'Its events are yours with this action, or with any '
        'action under this group.',
        style: theme.textTheme.bodySmall,
      ),
    ),
  ];

  /// The goal made for each period, for a recurring goal's habit: a
  /// tile opening its page.
  List<Widget> _goalFields(ThemeData theme) => [
    Padding(
      padding: const EdgeInsets.only(top: 16, bottom: 4),
      child: Text('Its goal', style: theme.textTheme.titleSmall),
    ),
    FieldHotkey(
      'G',
      onPressed: _editGoal,
      child: ListTile(
        contentPadding: EdgeInsets.zero,
        leading: const Icon(Icons.repeat),
        title: Text(
          recurringGoalTitle(
            _goal,
            _name.text.trim().isEmpty ? 'its name' : _name.text.trim(),
          ),
        ),
        subtitle: Text(recurringGoalSummary(_goal)),
        trailing: const Icon(Icons.edit_outlined, size: 18),
        onTap: _editGoal,
      ),
    ),
    Text(recurringGoalMade(_goal), style: theme.textTheme.bodySmall),
    ..._chainFields(theme),
  ];

  /// The chain of sub-goals made under each of its goals, in the order
  /// they come due, each opening its editor, and a button adding one.
  List<Widget> _chainFields(ThemeData theme) {
    final titles = {for (final s in _subGoals) ?subGoalKey(s): subGoalTitle(s)};
    final priority = _goal.priority ?? defaultGoalPriority;
    return [
      Padding(
        padding: const EdgeInsets.only(top: 24, bottom: 4),
        child: Text(
          'Its chain of sub-goals',
          style: theme.textTheme.titleSmall,
        ),
      ),
      Text(
        _subGoals.isEmpty
            ? 'None: each goal is made alone. Sub-goals are made under each '
                  'one, timed from its deadline, so moving it moves them.'
            : 'Made under each goal, timed from its deadline, so moving it '
                  'moves them. A change goes with the goals to come.',
        style: theme.textTheme.bodySmall,
      ),
      for (final sub in chainOrder(_subGoals))
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.subdirectory_arrow_right),
          title: Text(subGoalTitle(sub)),
          subtitle: Text(
            subGoalSummary(
              sub,
              titles,
              priority: (sub['priority'] as num?)?.toInt() ?? priority,
            ),
          ),
          trailing: const Icon(Icons.edit_outlined, size: 18),
          onTap: () =>
              _editSubGoal(_subGoals.indexWhere((s) => identical(s, sub))),
        ),
      Align(
        alignment: AlignmentDirectional.centerStart,
        child: TextButton.icon(
          icon: const Icon(Icons.add),
          label: const Text('Add a sub-goal'),
          onPressed: _editSubGoal,
        ),
      ),
    ];
  }

  /// What's amiss with its own parts, as they stand: those that count
  /// nothing here, or read events done for someone.
  List<Widget> _warnings(ThemeData theme) {
    final scope = _actionId;
    if (scope == null || _isGoal) return const [];
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
