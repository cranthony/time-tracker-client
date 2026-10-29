import 'dart:convert';

import 'package:flutter/material.dart';

import '../models/facts.dart';
import '../models/goal.dart';
import '../models/goal_changes.dart';
import '../services/plan_memory.dart';
import 'color_picker.dart';
import 'duration_field.dart';
import 'edit_page.dart';
import 'event_description.dart';
import 'goal_color.dart';
import 'goal_fields.dart';
import 'goal_icon.dart';
import 'goal_starts.dart';
import 'text_editor.dart';
import 'picker_sheet.dart';
import 'tree_picker.dart';

/// Adds a goal (with no [goal]) under [parent] (the top level, if null),
/// or edits [goal], on a page of its own: its title, status, deadline (a
/// date, and a time if wanted -- or, for a sub-goal, its parent's, or
/// some days or weeks before it, following it), priority (its own, or
/// its parent's, inherited), expected time, whether
/// its parent needs it, its description and definition of done (plain
/// text, Markdown or HTML, in [showTextEditor]), the hints for telling
/// its events, and the people it's done with and for (picked as an event's are) -- laid out, and
/// its bar titled, as the goal's page has them ([GoalField],
/// [GoalBarTitle]). A new one
/// starts active, or inactive if chosen; an active one needs a deadline.
/// Its deadline can instead be measured from its start, or another goal's
/// deadline; and an inactive one can wait to be activated ("Starts":
/// [GoalStartsEditor]). A new one can start with [status], [activateWhen]
/// and [deadlineRule] -- the next goal in a chain, say.
/// Saving is off while the change breaks a rule (see [planned]) against
/// [goals], every goal there is, saying which -- a change of status
/// checked with what it takes ([editing]). A new one starts with [title]
/// and [deadline], [description] and [priority], and the people and
/// circles it's done with ([withWhom]) and for ([forWhom]), if they're
/// given -- from the New goal sheet, say.
/// Gives a new goal's fields, or an edit's changes (a null clearing a
/// field) -- null if nothing's saved.
Future<Map<String, Object?>?> showGoalEditor(
  BuildContext context, {
  Goal? goal,
  Goal? parent,
  required List<Goal> goals,
  String? title,
  String? deadline,
  String? description,
  TextFormat? descriptionFormat,
  int? priority,
  List<Named> withWhom = const [],
  List<Named> forWhom = const [],
  String? status,
  Map<String, Object?>? activateWhen,
  Map<String, Object?>? deadlineRule,
  DateTime Function() now = DateTime.now,
}) => Navigator.of(context).push<Map<String, Object?>>(
  MaterialPageRoute(
    fullscreenDialog: true,
    builder: (_) => GoalEditorPage(
      goal: goal,
      parent: parent ?? GoalTree(goals)[goal?.parentId],
      goals: goals,
      title: title,
      deadline: deadline,
      description: description,
      descriptionFormat: descriptionFormat,
      priority: priority,
      withWhom: withWhom,
      forWhom: forWhom,
      status: status,
      activateWhen: activateWhen,
      deadlineRule: deadlineRule,
      now: now,
    ),
  ),
);

class GoalEditorPage extends StatefulWidget {
  const GoalEditorPage({
    super.key,
    this.goal,
    this.parent,
    required this.goals,
    this.title,
    this.deadline,
    this.description,
    this.descriptionFormat,
    this.priority,
    this.withWhom = const [],
    this.forWhom = const [],
    this.status,
    this.activateWhen,
    this.deadlineRule,
    this.now = DateTime.now,
  });

  final Goal? goal;
  final Goal? parent;
  final List<Goal> goals;

  /// A new goal's, to begin with.
  final String? title;
  final String? deadline;
  final String? description;
  final TextFormat? descriptionFormat;
  final int? priority;

  /// A new goal's people and circles, to begin with: who it's done with,
  /// and for.
  final List<Named> withWhom;
  final List<Named> forWhom;

  /// A new goal's status, what it waits for, and what its deadline is
  /// measured from, to begin with.
  final String? status;
  final Map<String, Object?>? activateWhen;
  final Map<String, Object?>? deadlineRule;
  final DateTime Function() now;

  @override
  State<GoalEditorPage> createState() => _GoalEditorPageState();
}

class _GoalEditorPageState extends State<GoalEditorPage> {
  Goal? get _goal => widget.goal;

  late final _title = TextEditingController(
    text: _goal?.title ?? widget.title ?? '',
  );
  late final _hints = TextEditingController(
    text: _goal?.attributionHints ?? '',
  );
  late final _minutes = TextEditingController(
    text: _goal?.expectedMinutes?.toString() ?? '',
  );
  late String? _deadline = _goal?.deadline ?? widget.deadline;
  late final _offset = TextEditingController(
    text: _goal?.deadlineOffsetMinutes?.toString() ?? '',
  );

  /// How many times a chip has set [_offset].
  var _offsetPicks = 0;

  late final Map<String, Object?>? _rule =
      _goal?.deadlineRule ?? widget.deadlineRule;

  /// What its deadline is measured from.
  late _DeadlineFrom _from = switch (_rule) {
    {'after_start': _} => _DeadlineFrom.start,
    {'after_goal': _} => _DeadlineFrom.goal,
    _ when widget.parent != null && (_goal?.followsParent ?? false) =>
      _DeadlineFrom.parent,
    _ => _DeadlineFrom.date,
  };

  bool get _follows => _from == _DeadlineFrom.parent;

  /// How long after its start, or the other goal's deadline, it's due, in
  /// minutes; and how many times a chip has set it.
  late final _after = TextEditingController(
    text: switch (_rule?['after_start'] ?? _rule?['after_goal']) {
      {'days': final num d} => '${d.toInt() * Duration.minutesPerDay}',
      {'minutes': final num m} => '${m.toInt()}',
      _ => '${7 * Duration.minutesPerDay}',
    },
  );
  var _afterPicks = 0;

  /// The goal whose deadline it's measured from, after it.
  late String? _afterGoal = switch (_rule) {
    {'after_goal': {'id': final String id}} => id,
    _ => null,
  };

  /// What it waits for before it's activated.
  late Map<String, Object?>? _activateWhen =
      _goal?.activateWhen ?? widget.activateWhen;
  late String _status = _goal?.status ?? widget.status ?? 'active';
  late bool _required = _goal?.required ?? false;
  late int? _priority = _goal?.priority ?? widget.priority;
  late String? _color = _goal?.backgroundColor;
  late String? _description = _goal?.description ?? widget.description;
  late TextFormat? _descriptionFormat =
      _goal?.descriptionFormat ?? widget.descriptionFormat;
  late String? _definitionOfDone = _goal?.definitionOfDone;
  late TextFormat? _definitionOfDoneFormat = _goal?.definitionOfDoneFormat;
  late List<Named> _with = [...(_goal?.withWhom ?? widget.withWhom)];
  late List<Named> _for = [...(_goal?.forWhom ?? widget.forWhom)];

  @override
  void dispose() {
    _title.dispose();
    _hints.dispose();
    _minutes.dispose();
    _offset.dispose();
    _after.dispose();
    super.dispose();
  }

  String? _text(TextEditingController c) =>
      c.text.trim().isEmpty ? null : c.text.trim();

  int? get _expected => switch (num.tryParse(_minutes.text.trim())) {
    final m? when m > 0 => m.round(),
    _ => null,
  };

  /// How long before its parent's its deadline is, following it: none if
  /// it doesn't, or what's typed isn't a length of time.
  int? get _offsetMinutes => !_follows
      ? null
      : _offset.text.trim().isEmpty
      ? 0
      : switch (num.tryParse(_offset.text.trim())) {
          final m? when m >= 0 => m.round(),
          _ => null,
        };

  /// Its deadline: its own, or the one following its parent's -- none
  /// here when it's measured from its start or another goal's.
  String? get _shownDeadline => switch (_from) {
    _DeadlineFrom.parent =>
      deadlineBefore(widget.parent?.deadline, _offsetMinutes ?? 0) ?? _deadline,
    _DeadlineFrom.date => _deadline,
    _ => null,
  };

  /// How long after what it's measured from it's due: days, if it's
  /// whole days, else minutes; null if what's typed isn't a length.
  Map<String, Object?>? get _afterOffset =>
      switch (num.tryParse(_after.text.trim())?.round()) {
        final m? when m >= 0 && m % Duration.minutesPerDay == 0 => {
          'days': m ~/ Duration.minutesPerDay,
        },
        final m? when m >= 0 => {'minutes': m},
        _ => null,
      };

  /// What its deadline is measured from, as the server takes it, when it's
  /// its start or another goal's; null otherwise.
  Map<String, Object?>? get _deadlineRule => switch (_from) {
    _DeadlineFrom.start => {'after_start': ?_afterOffset},
    _DeadlineFrom.goal => {
      'after_goal': {'id': _afterGoal, ...?_afterOffset},
    },
    _ => null,
  };

  /// What's set, keyed as the server takes it.
  Map<String, Object?> get _fields => {
    'title': _title.text.trim(),
    if (_deadlineRule == null) 'deadline': _shownDeadline,
    'deadline_offset_minutes': _offsetMinutes,
    'deadline_rule': _deadlineRule,
    'activate_when': _status == 'inactive' ? _activateWhen : null,
    'priority': _priority,
    'background_color': _color,
    'expected_minutes': _expected,
    'required': widget.parent == null ? null : _required,
    'description': _description,
    // A text cleared takes its format with it, on the server.
    'description_format': _description == null
        ? null
        : _descriptionFormat?.wire,
    'definition_of_done': _definitionOfDone,
    'definition_of_done_format': _definitionOfDone == null
        ? null
        : _definitionOfDoneFormat?.wire,
    'attribution_hints': _text(_hints),
  };

  /// The people and circles it's done with and for, keyed as the server
  /// takes them: null for none.
  Map<String, Object?> get _people => {
    'with_ids': _with.isEmpty ? null : namedToJson(_with),
    'for_ids': _for.isEmpty ? null : namedToJson(_for),
  };

  /// A new goal's fields, or what an edit changes.
  Map<String, Object?> get _changes {
    final goal = _goal;
    final fields = _fields;
    if (goal == null) {
      return {
        ...fields,
        ..._people,
        'parent_id': widget.parent?.id,
        'status': _status,
      }..removeWhere((_, v) => v == null);
    }
    bool same(List<Named> a, List<Named> b) =>
        a.length == b.length && a.every(b.contains);
    final before = {
      'title': goal.title,
      'deadline': goal.deadline,
      'deadline_offset_minutes': goal.deadlineOffsetMinutes,
      'deadline_rule': goal.deadlineRule,
      // Activated, what it waited for is cleared anyway.
      'activate_when': _status == 'inactive' ? goal.activateWhen : null,
      'priority': goal.priority,
      'background_color': goal.backgroundColor,
      'expected_minutes': goal.expectedMinutes,
      'required': goal.parentId == null ? null : goal.required,
      'description': goal.description,
      'description_format': goal.description == null
          ? null
          : goal.descriptionFormat?.wire,
      'definition_of_done': goal.definitionOfDone,
      'definition_of_done_format': goal.definitionOfDone == null
          ? null
          : goal.definitionOfDoneFormat?.wire,
      'attribution_hints': goal.attributionHints,
    };
    return {
      for (final MapEntry(:key, :value) in fields.entries)
        if (jsonEncode(value) != jsonEncode(before[key])) key: value,
      if (_status != goal.status) 'status': _status,
      if (!same(_with, goal.withWhom)) 'with_ids': _people['with_ids'],
      if (!same(_for, goal.forWhom)) 'for_ids': _people['for_ids'],
    };
  }

  /// Picks who it's done with and for, as an event's are picked.
  Future<void> _pickPeople() async {
    final picked = await showWhoWhereSheet(
      context,
      Facts.named(with_: _with, for_: _for),
      withCaption: 'Who you’ll do it with',
      forCaption: 'Who it’s for, who won’t be part of doing it',
    );
    if (picked == null || !mounted) return;
    setState(() {
      _with = picked.facts.withWhom;
      _for = picked.facts.forWhom;
    });
  }

  String? get _problem {
    if (_title.text.trim().isEmpty) return 'Give it a title.';
    if (_follows && _offsetMinutes == null) {
      return "Say how long before its parent's it's due.";
    }
    if (_deadlineRule != null && _afterOffset == null) {
      return "Say how long after it it's due.";
    }
    if (_from == _DeadlineFrom.goal && _afterGoal == null) {
      return 'Pick the goal its deadline comes after.';
    }
    final goal = _goal;
    final tree = GoalTree(widget.goals);
    if (goal != null && _status == 'done' && goal.status != 'done') {
      final needed = requiredOpen(tree, goal);
      if (needed.isNotEmpty) {
        return 'It needs '
            '${needed.map((g) => '“${goalTitle(g)}”').join(', ')} done first '
            '(or marked missed or obsolete).';
      }
    }
    final changes = goal == null
        ? [
            GoalCreate(Goal.fromJson({'id': '\u0000new', ..._changes})),
          ]
        : [
            GoalBatch(
              editing(
                tree,
                goal,
                {..._changes}..remove('status'),
                status: _status,
                // Asked for as it's activated: any will do here.
                deadlines: {
                  for (final p in inactiveParents(tree, [goal]))
                    if (p.deadline == null) p.id: ?_shownDeadline,
                },
              ),
            ),
          ];
    final problems = planned(widget.goals, changes, now: widget.now());
    return problems.isEmpty ? null : problems.join(' ');
  }

  Future<void> _pickDate() async {
    final now = widget.now();
    final at = deadlineEnd(_deadline);
    final day = at == null
        ? null
        : deadlineHasTime(_deadline)
        ? at
        : at.subtract(const Duration(days: 1));
    final picked = await showDatePicker(
      context: context,
      initialDate: day ?? now,
      firstDate: DateTime(now.year - 5),
      lastDate: DateTime(now.year + 20),
    );
    if (picked == null || !mounted) return;
    setState(() {
      if (deadlineHasTime(_deadline) && day != null) {
        _deadline = deadlineOf(
          DateTime(picked.year, picked.month, picked.day, day.hour, day.minute),
          time: true,
        );
      } else {
        _deadline = deadlineOf(picked);
      }
    });
  }

  Future<void> _pickTime() async {
    final at = deadlineEnd(_deadline);
    if (at == null) return;
    final day = deadlineHasTime(_deadline)
        ? at
        : at.subtract(const Duration(days: 1));
    final picked = await showTimePicker(
      context: context,
      initialTime: deadlineHasTime(_deadline)
          ? TimeOfDay.fromDateTime(at)
          : const TimeOfDay(hour: 17, minute: 0),
    );
    if (picked == null || !mounted) return;
    setState(
      () => _deadline = deadlineOf(
        DateTime(day.year, day.month, day.day, picked.hour, picked.minute),
        time: true,
      ),
    );
  }

  /// Edits [text], written in [format], in [showTextEditor], setting it
  /// (null for nothing) and its format with [set] once it's saved.
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
      () => set(edited.text.isEmpty ? null : edited.text, edited.format),
    );
  }

  /// Picks the goal its deadline comes after: any other goal but one
  /// whose deadline comes, through others, after its own.
  Future<void> _pickAfterGoal() async {
    final tree = GoalTree(widget.goals);
    final self = _goal?.id;
    bool afterSelf(Goal g) {
      final seen = <String>{};
      for (Goal? at = g; at != null;) {
        if (at.id == self) return true;
        if (!seen.add(at.id)) return false;
        at = switch (at.deadlineRule) {
          {'after_goal': {'id': final String id}} => tree[id],
          _ when at.followsParent => tree[at.parentId],
          _ => null,
        };
      }
      return false;
    }

    final pickable = [
      for (final g in byPriority(widget.goals, tree))
        if (g.open && !afterSelf(g)) g,
    ];
    final picked = await pickNode(
      context,
      title: 'Due after',
      nodes: [
        for (final g in pickable)
          PickerNode(
            id: g.id,
            label: goalTitle(g),
            parentId: pickable.any((p) => p.id == g.parentId)
                ? g.parentId
                : null,
            path: [...tree.pathOf(g.id), goalTitle(g)].join(' › '),
            group: pickable.any((c) => c.parentId == g.id),
          ),
      ],
      value: _afterGoal,
      groupsPickable: true,
      marker: (_) => const GoalIcon(size: 18),
      searchHint: 'Search goals',
    );
    if (picked?.id case final id? when mounted) {
      setState(() => _afterGoal = id);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final goal = _goal;
    final parent = widget.parent;
    final tree = GoalTree(widget.goals);
    final problem = _problem;
    final now = widget.now();
    final deadline = _shownDeadline;
    final people = goalPeopleLabel(
      _with,
      _for,
      goalPeopleNames(PlanMemoryScope.of(context)),
    );
    final title = goal == null
        ? (parent == null ? 'New goal' : 'New sub-goal')
        : 'Edit goal';
    return EditPage(
      title: title,
      heading: GoalBarTitle(
        title: title,
        path: parent == null
            ? const []
            : [...tree.pathOf(parent.id), goalTitle(parent)],
      ),
      problem: problem,
      changed: () => _changes.isNotEmpty,
      onSave: () => Navigator.of(context).pop(_changes),
      // In the order the goal's page has them, under the same labels.
      children: [
        TextField(
          controller: _title,
          autofocus: goal == null,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(
            labelText: 'Title',
            hintText: 'An outcome you can mark done',
          ),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 8),
        GoalField(
          label: 'Status',
          child: goal == null
              ? SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'active', label: Text('Active')),
                    ButtonSegment(value: 'inactive', label: Text('Inactive')),
                  ],
                  selected: {_status},
                  onSelectionChanged: (picked) =>
                      setState(() => _status = picked.single),
                )
              : DropdownButtonFormField<String>(
                  initialValue: _status,
                  items: [
                    for (final MapEntry(:key, :value) in goalStatuses.entries)
                      DropdownMenuItem(value: key, child: Text(value)),
                  ],
                  onChanged: (picked) {
                    if (picked != null) setState(() => _status = picked);
                  },
                ),
        ),
        GoalField(
          label: 'Deadline',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  for (final from in _DeadlineFrom.values)
                    if (from != _DeadlineFrom.parent || parent != null)
                      ChoiceChip(
                        label: Text(from.label),
                        selected: _from == from,
                        onSelected: (_) => setState(() {
                          // Untied, it keeps the deadline it had.
                          if (from == _DeadlineFrom.date) {
                            _deadline = _shownDeadline ?? _deadline;
                          }
                          _from = from;
                        }),
                      ),
                ],
              ),
              const SizedBox(height: 8),
              if (_follows && parent != null)
                Text(
                  parent.deadline == null
                      ? '“${goalTitle(parent)}” has no deadline yet'
                      : '${deadlineLabel(context, deadline)} · '
                            '${followsLabel(goalTitle(parent), _offsetMinutes ?? 0)}',
                ),
              if (_from == _DeadlineFrom.goal)
                OutlinedButton.icon(
                  icon: const GoalIcon(size: 18),
                  label: Text(switch (tree[_afterGoal]) {
                    final g? => 'After “${goalTitle(g)}” is due',
                    null => 'Pick the goal',
                  }),
                  onPressed: _pickAfterGoal,
                ),
              if (_from == _DeadlineFrom.start ||
                  _from == _DeadlineFrom.goal) ...[
                Wrap(
                  spacing: 8,
                  children: [
                    for (final (label, minutes) in const [
                      ('Same day', 0),
                      ('1 day after', Duration.minutesPerDay),
                      ('1 week after', 7 * Duration.minutesPerDay),
                    ])
                      ChoiceChip(
                        label: Text(label),
                        selected: _after.text.trim() == '$minutes',
                        onSelected: (_) => setState(() {
                          _after.text = '$minutes';
                          _afterPicks++;
                        }),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                DurationField(
                  // Shown anew when a chip sets it.
                  key: ValueKey(('after', _afterPicks)),
                  controller: _after,
                  label: _from == _DeadlineFrom.start
                      ? 'How long after it starts'
                      : "How long after that goal's",
                  units: DurationUnits.weeksDays,
                  onChanged: () => setState(() {}),
                ),
              ],
              if (_follows) ...[
                Wrap(
                  spacing: 8,
                  children: [
                    for (final (label, minutes) in const [
                      ("Same as parent's", 0),
                      ('1 day before', Duration.minutesPerDay),
                      ('1 week before', 7 * Duration.minutesPerDay),
                    ])
                      ChoiceChip(
                        label: Text(label),
                        selected: _offsetMinutes == minutes,
                        onSelected: (_) => setState(() {
                          _offset.text = '$minutes';
                          _offsetPicks++;
                        }),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                DurationField(
                  // Shown anew when a chip sets it.
                  key: ValueKey(_offsetPicks),
                  controller: _offset,
                  label: "How long before its parent's",
                  units: DurationUnits.weeksDays,
                  onChanged: () => setState(() {}),
                ),
              ] else if (_from == _DeadlineFrom.date) ...[
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    OutlinedButton.icon(
                      icon: const Icon(Icons.event),
                      label: Text(
                        _deadline == null
                            ? 'Pick a date'
                            : deadlineLabel(context, _deadline),
                      ),
                      onPressed: _pickDate,
                    ),
                    if (_deadline != null)
                      TextButton.icon(
                        icon: const Icon(Icons.schedule),
                        label: Text(
                          deadlineHasTime(_deadline)
                              ? 'Change time'
                              : 'Add a time',
                        ),
                        onPressed: _pickTime,
                      ),
                    if (deadlineHasTime(_deadline))
                      TextButton(
                        onPressed: () => setState(
                          () => _deadline = _deadline!.split('T').first,
                        ),
                        child: const Text('End of day'),
                      ),
                    if (_deadline != null && _status != 'active')
                      IconButton(
                        tooltip: 'No deadline',
                        icon: const Icon(Icons.clear),
                        onPressed: () => setState(() => _deadline = null),
                      ),
                  ],
                ),
                Wrap(
                  spacing: 8,
                  children: [
                    ActionChip(
                      label: const Text('End of today'),
                      onPressed: () =>
                          setState(() => _deadline = endOfToday(now)),
                    ),
                    ActionChip(
                      label: const Text('End of this week'),
                      onPressed: () =>
                          setState(() => _deadline = endOfWeek(now)),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
        if (_status == 'inactive')
          GoalField(
            label: 'Starts',
            child: GoalStartsEditor(
              value: _activateWhen,
              goals: widget.goals,
              goalId: goal?.id,
              parentId: parent?.id,
              now: widget.now,
              onChanged: (value) => setState(() => _activateWhen = value),
            ),
          ),
        GoalField(
          label: 'Priority',
          child: Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              ChoiceChip(
                showCheckmark: false,
                label: Text(
                  parent == null
                      ? 'None (P$defaultGoalPriority)'
                      : 'Inherit (P${tree.priorityOf(parent.id)})',
                ),
                tooltip: inheritedPriorityLabel(tree, parent?.id),
                selected: _priority == null,
                onSelected: (_) => setState(() => _priority = null),
              ),
              for (final p in const [0, 1, 2, 3])
                ChoiceChip(
                  showCheckmark: false,
                  avatar: CircleAvatar(backgroundColor: priorityColor(p)),
                  label: Text('P$p'),
                  selected: _priority == p,
                  onSelected: (_) => setState(() => _priority = p),
                ),
            ],
          ),
        ),
        GoalField(
          label: 'Color',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_color == null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    inheritedColorLabel(
                      tree,
                      parent?.id,
                      _priority ??
                          (parent == null
                              ? defaultGoalPriority
                              : tree.priorityOf(parent.id)),
                    ),
                    style: theme.textTheme.bodySmall,
                  ),
                ),
              ColorPicker(
                color: parseColor(_color),
                onChanged: (color) => setState(
                  () => _color = color == null ? null : colorToHex(color),
                ),
              ),
            ],
          ),
        ),
        GoalField(
          label: 'Expected time',
          child: DurationField(
            controller: _minutes,
            label: 'How long it should take (optional)',
            onChanged: () => setState(() {}),
          ),
        ),
        if (parent != null)
          GoalField(
            label: 'Required',
            child: SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(requiredLabel(goalTitle(parent), _required)),
              value: _required,
              onChanged: (value) => setState(() => _required = value),
            ),
          ),
        GoalField(
          label: 'People',
          onTap: _pickPeople,
          child: people == null
              ? const GoalFieldEmpty('Add who it’s with or for')
              : Text(people),
        ),
        GoalField(
          label: 'Description',
          onTap: () => _editText(
            'Description',
            _description,
            _descriptionFormat,
            (text, format) {
              _description = text;
              _descriptionFormat = format;
            },
          ),
          child: _formatted(
            _description,
            _descriptionFormat,
            'Add description',
          ),
        ),
        GoalField(
          label: 'Definition of done',
          onTap: () => _editText(
            'Definition of done',
            _definitionOfDone,
            _definitionOfDoneFormat,
            (text, format) {
              _definitionOfDone = text;
              _definitionOfDoneFormat = format;
            },
          ),
          child: _formatted(
            _definitionOfDone,
            _definitionOfDoneFormat,
            'Add definition of done',
          ),
        ),
        GoalField(
          label: 'Attribution hints',
          child: TextField(
            controller: _hints,
            minLines: 2,
            maxLines: 6,
            decoration: InputDecoration(
              hintText: 'How Claude can tell which events are for it',
              hintStyle: TextStyle(color: theme.hintColor),
            ),
            onChanged: (_) => setState(() {}),
          ),
        ),
      ],
    );
  }

  /// A field's [text], written in [format], as it reads, or [empty]
  /// while there's none.
  static Widget _formatted(String? text, TextFormat? format, String empty) =>
      text == null
      ? GoalFieldEmpty(empty)
      : EventDescription(text, format: format, maxLines: 4, expandable: false);
}

/// Names people and circles by id from [memory]: an id it doesn't know,
/// as itself.
String Function(String id) goalPeopleNames(PlanMemory? memory) {
  final byId = memory?.people?.names ?? const <String, String>{};
  return (id) => byId[id] ?? id;
}

/// Who a goal is done with and for, named by [names]: "With Ana, Family
/// (except Sam) · For Sam"; null if no one.
String? goalPeopleLabel(
  List<Named> withWhom,
  List<Named> forWhom,
  String Function(String id) names,
) {
  final parts = [
    if (withWhom.isNotEmpty) 'With ${namedList(withWhom, names)}',
    if (forWhom.isNotEmpty) 'For ${namedList(forWhom, names)}',
  ];
  return parts.isEmpty ? null : parts.join(' · ');
}

/// A field of free text, written in [format], as it reads, tapped to
/// edit: "Add [label]" while there's nothing in it.
class FormattedField extends StatelessWidget {
  const FormattedField({
    super.key,
    required this.label,
    required this.text,
    this.format,
    required this.onTap,
  });

  final String label;
  final String? text;
  final TextFormat? format;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: theme.textTheme.labelLarge),
                  const SizedBox(height: 4),
                  if (text case final text?)
                    EventDescription(
                      text,
                      format: format,
                      maxLines: 4,
                      expandable: false,
                    )
                  else
                    Text(
                      'Add ${label.toLowerCase()}',
                      style: TextStyle(color: theme.hintColor),
                    ),
                ],
              ),
            ),
            const Icon(Icons.edit_outlined, size: 18),
          ],
        ),
      ),
    );
  }
}

/// [deadline] as the app shows it: "Sat, Nov 1", or "Sat, Nov 1, 5:00 PM".
String deadlineLabel(BuildContext context, String? deadline) {
  final at = deadlineEnd(deadline);
  if (at == null) return deadline ?? '';
  final strings = MaterialLocalizations.of(context);
  if (!deadlineHasTime(deadline)) {
    return strings.formatMediumDate(at.subtract(const Duration(days: 1)));
  }
  return '${strings.formatMediumDate(at)}, '
      '${strings.formatTimeOfDay(TimeOfDay.fromDateTime(at))}';
}

/// What a goal's deadline in the editor is measured from: a date given,
/// its parent's (before it), its start, or another goal's (after them).
enum _DeadlineFrom {
  date('A date'),
  parent("Before its parent's"),
  start('After it starts'),
  goal("After another goal's");

  const _DeadlineFrom(this.label);

  final String label;
}
