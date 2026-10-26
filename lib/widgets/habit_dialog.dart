import 'package:flutter/material.dart';

import 'hotkeys.dart';
import '../models/habit.dart';
import '../models/habit_graph.dart';
import '../models/person.dart';
import '../models/plan_action.dart';
import '../models/recurring_goal.dart';
import '../models/trait.dart';
import '../models/trait_scores.dart';
import 'actions_picker.dart';
import 'color_picker.dart';
import 'edit_page.dart';
import 'error_sheet.dart';
import 'foundations_field.dart';
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
  late String? _actionId = widget.habit?.actionId;
  late String _status = widget.habit?.status ?? 'active';

  /// Whether it's a recurring goal's habit: picked for a new one, fixed
  /// for one there is.
  late bool _isGoal = widget.habit?.isGoal ?? false;
  late String _period = widget.habit?.recurringGoal?.period ?? 'week';
  late final _goalTitle = TextEditingController(
    text: widget.habit?.recurringGoal?.title,
  );
  late final _definitionOfDone = TextEditingController(
    text: widget.habit?.recurringGoal?.definitionOfDone,
  );
  late final _attributionHints = TextEditingController(
    text: widget.habit?.recurringGoal?.attributionHints,
  );
  late final _ratePeriods = TextEditingController(
    text:
        '${widget.habit?.recurringGoal?.ratedPeriods ?? defaultRatePeriods(_period)}',
  );

  /// Whether its goal rate's span is its own, not its period's default,
  /// which it follows as the period's changed till it's typed.
  late bool _ownRate = widget.habit?.recurringGoal?.ratePeriods != null;
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
    _goalTitle.dispose();
    _definitionOfDone.dispose();
    _attributionHints.dispose();
    _ratePeriods.dispose();
    super.dispose();
  }

  static String? _text(TextEditingController c) =>
      c.text.trim().isEmpty ? null : c.text.trim();

  int? get _rateValue => int.tryParse(_ratePeriods.text.trim());

  /// Its recurring goal as it's being edited: what the server takes,
  /// kept as it was where this doesn't edit it.
  RecurringGoal get _recurring {
    final was = widget.habit?.recurringGoal ?? const RecurringGoal();
    return RecurringGoal(
      period: _period,
      title: _text(_goalTitle),
      priority: was.priority,
      expectedMinutes: was.expectedMinutes,
      description: was.description,
      definitionOfDone: _text(_definitionOfDone),
      attributionHints: _text(_attributionHints),
      withIds: was.withIds,
      forIds: was.forIds,
      ratePeriods: _ownRate ? _rateValue : null,
    );
  }

  /// Picks [period], its goal rate's span following it unless it's
  /// been given one.
  void _pickPeriod(String period) => setState(() {
    _period = period;
    if (!_ownRate) _ratePeriods.text = '${defaultRatePeriods(period)}';
  });

  /// Switches a new habit between an action's and a recurring goal's: a
  /// goal's is scored by its goal rate alone till it's given traits.
  void _pickGoal(bool goal) => setState(() {
    _isGoal = goal;
    _traits = goal ? const PersonTraits(select: []) : _actionTraits;
  });

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
    if (_isGoal)
      'recurring_goal': _recurring.toJson()
    else
      'action_id': _actionId,
    'note': _noteText,
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
        ? (_rateValue == null || _rateValue! < 1
              ? 'Give how many periods its goal rate counts: 1 or more.'
              : null)
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
            child: TextField(
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

  /// The goal made for each period, for a recurring goal's habit.
  List<Widget> _goalFields(ThemeData theme) => [
    Padding(
      padding: const EdgeInsets.only(top: 16, bottom: 4),
      child: Text('A goal each', style: theme.textTheme.titleSmall),
    ),
    FieldHotkey(
      'P',
      onPressed: () => _pickPeriod(nextOf(goalPeriods.keys.toList(), _period)),
      child: SegmentedButton<String>(
        showSelectedIcon: false,
        segments: [
          for (final MapEntry(:key, :value) in goalPeriods.entries)
            ButtonSegment(value: key, label: Text(value.$1)),
        ],
        selected: {_period},
        onSelectionChanged: (picked) => _pickPeriod(picked.single),
      ),
    ),
    Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Text(
        'A goal is made as each ${goalPeriods[_period]!.$1.toLowerCase()} '
        '${_period == 'week' ? 'starts, on Sunday' : 'starts'}, once the one '
        'before is done; one missed is tried again through the next. Its '
        'events are those tagged with its goals.',
        style: theme.textTheme.bodySmall,
      ),
    ),
    Padding(
      padding: const EdgeInsets.only(top: 16),
      child: TextField(
        controller: _goalTitle,
        textCapitalization: TextCapitalization.sentences,
        decoration: InputDecoration(
          labelText: "Goals' title (optional)",
          hintText: _name.text.trim().isEmpty
              ? "The habit's name"
              : _name.text.trim(),
          border: const OutlineInputBorder(),
          isDense: true,
          floatingLabelBehavior: FloatingLabelBehavior.always,
        ),
      ),
    ),
    Padding(
      padding: const EdgeInsets.only(top: 16),
      child: TextField(
        controller: _definitionOfDone,
        minLines: 2,
        maxLines: null,
        textCapitalization: TextCapitalization.sentences,
        decoration: const InputDecoration(
          labelText: 'Done when (optional)',
          hintText: 'e.g. I talked with Mom for at least 20 minutes',
          helperText: 'Compaction marks each goal done or missed by this.',
          border: OutlineInputBorder(),
          floatingLabelBehavior: FloatingLabelBehavior.always,
        ),
      ),
    ),
    Padding(
      padding: const EdgeInsets.only(top: 16),
      child: TextField(
        controller: _attributionHints,
        minLines: 2,
        maxLines: null,
        textCapitalization: TextCapitalization.sentences,
        decoration: const InputDecoration(
          labelText: 'Its events (optional)',
          hintText: 'e.g. Calls or visits with Mom',
          helperText: 'Which events compaction tags with its goals.',
          border: OutlineInputBorder(),
          floatingLabelBehavior: FloatingLabelBehavior.always,
        ),
      ),
    ),
    Padding(
      padding: const EdgeInsets.only(top: 16),
      child: TextField(
        controller: _ratePeriods,
        keyboardType: TextInputType.number,
        decoration: InputDecoration(
          labelText: 'Goal rate counts the last',
          suffixText: goalPeriods[_period]!.$2,
          helperText: "It's scored by how many of them had its goal done.",
          border: const OutlineInputBorder(),
          isDense: true,
        ),
        onChanged: (_) => setState(() => _ownRate = true),
      ),
    ),
  ];

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
