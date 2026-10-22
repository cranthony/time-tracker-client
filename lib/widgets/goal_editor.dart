import 'package:flutter/material.dart';

import '../models/facts.dart';
import '../models/goal.dart';
import '../models/goal_changes.dart';
import '../models/person.dart';
import '../services/plan_memory.dart';
import 'color_picker.dart' show priorityColor;
import 'duration_field.dart';
import 'edit_page.dart';
import 'event_description.dart';
import 'goal_fields.dart';
import 'html_editor.dart';
import 'picker_sheet.dart';

/// Adds a goal (with no [goal]) under [parent] (the top level, if null),
/// or edits [goal], on a page of its own: its title, status, deadline (a
/// date, and a time if wanted -- or, for a sub-goal, its parent's, or
/// some days or weeks before it, following it), priority (its own, or
/// its parent's, inherited), expected time, whether
/// its parent needs it, its description and definition of done (HTML, in
/// [showHtmlEditor]), the hints for telling its events, and the people
/// it's done with and for (picked as an event's are) -- laid out, and
/// its bar titled, as the goal's page has them ([GoalField],
/// [GoalBarTitle]). A new one
/// starts active, or inactive if chosen; an active one needs a deadline.
/// Saving is off while the change breaks a rule (see [planned]) against
/// [goals], every goal there is, saying which -- a change of status
/// checked with what it takes ([editing]). A new one starts with [title]
/// and [deadline], [description] and [definitionOfDone], and the people
/// it's done with ([withIds]) and for ([forIds]), if they're given --
/// from the New goal sheet, say.
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
  String? definitionOfDone,
  List<String> withIds = const [],
  List<String> forIds = const [],
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
      definitionOfDone: definitionOfDone,
      withIds: withIds,
      forIds: forIds,
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
    this.definitionOfDone,
    this.withIds = const [],
    this.forIds = const [],
    this.now = DateTime.now,
  });

  final Goal? goal;
  final Goal? parent;
  final List<Goal> goals;

  /// A new goal's, to begin with.
  final String? title;
  final String? deadline;
  final String? description;
  final String? definitionOfDone;

  /// A new goal's people, to begin with: who it's done with, and for.
  final List<String> withIds;
  final List<String> forIds;
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
  late bool _follows = widget.parent != null && (_goal?.followsParent ?? false);
  late String _status = _goal?.status ?? 'active';
  late bool _required = _goal?.required ?? false;
  late int? _priority = _goal?.priority;
  late String? _description = _goal?.description ?? widget.description;
  late String? _definitionOfDone =
      _goal?.definitionOfDone ?? widget.definitionOfDone;
  late List<String> _with = [...(_goal?.withIds ?? widget.withIds)];
  late List<String> _for = [...(_goal?.forIds ?? widget.forIds)];

  @override
  void dispose() {
    _title.dispose();
    _hints.dispose();
    _minutes.dispose();
    _offset.dispose();
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

  /// Its deadline: its own, or the one following its parent's.
  String? get _shownDeadline => _follows
      ? deadlineBefore(widget.parent?.deadline, _offsetMinutes ?? 0) ??
            _deadline
      : _deadline;

  /// What's set, keyed as the server takes it.
  Map<String, Object?> get _fields => {
    'title': _title.text.trim(),
    'deadline': _shownDeadline,
    'deadline_offset_minutes': _offsetMinutes,
    'priority': _priority,
    'expected_minutes': _expected,
    'required': widget.parent == null ? null : _required,
    'description': _description,
    'definition_of_done': _definitionOfDone,
    'attribution_hints': _text(_hints),
  };

  /// The people it's done with and for, keyed as the server takes them:
  /// null for none.
  Map<String, Object?> get _people => {
    'with_ids': _with.isEmpty ? null : [..._with],
    'for_ids': _for.isEmpty ? null : [..._for],
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
    bool same(List<String> a, List<String> b) =>
        a.length == b.length && a.every(b.contains);
    final before = {
      'title': goal.title,
      'deadline': goal.deadline,
      'deadline_offset_minutes': goal.deadlineOffsetMinutes,
      'priority': goal.priority,
      'expected_minutes': goal.expectedMinutes,
      'required': goal.parentId == null ? null : goal.required,
      'description': goal.description,
      'definition_of_done': goal.definitionOfDone,
      'attribution_hints': goal.attributionHints,
    };
    return {
      for (final MapEntry(:key, :value) in fields.entries)
        if (value != before[key]) key: value,
      if (_status != goal.status) 'status': _status,
      if (!same(_with, goal.withIds)) 'with_ids': _people['with_ids'],
      if (!same(_for, goal.forIds)) 'for_ids': _people['for_ids'],
    };
  }

  /// Picks who it's done with and for, as an event's are picked.
  Future<void> _pickPeople() async {
    final picked = await showWhoWhereSheet(
      context,
      Facts(withIds: _with, forIds: _for),
      withCaption: 'Who you’ll do it with',
      forCaption: 'Who it’s for, who won’t be part of doing it',
    );
    if (picked == null || !mounted) return;
    setState(() {
      _with = [...picked.facts.withIds];
      _for = [...picked.facts.forIds];
    });
  }

  String? get _problem {
    if (_title.text.trim().isEmpty) return 'Give it a title.';
    if (_follows && _offsetMinutes == null) {
      return "Say how long before its parent's it's due.";
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

  Future<void> _editHtml(
    String title,
    String? text,
    ValueChanged<String?> set,
  ) async {
    final edited = await showHtmlEditor(context, title: title, text: text);
    if (edited == null || !mounted) return;
    setState(() => set(edited.isEmpty ? null : edited));
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
              if (parent != null)
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text("Follow its parent's deadline"),
                  subtitle: Text(
                    parent.deadline == null
                        ? '“${goalTitle(parent)}” has no deadline yet'
                        : _follows
                        ? '${deadlineLabel(context, deadline)} · '
                              '${followsLabel(goalTitle(parent), _offsetMinutes ?? 0)}'
                        : '“${goalTitle(parent)}” is due '
                              '${deadlineLabel(context, parent.deadline)}',
                  ),
                  value: _follows,
                  onChanged: (value) => setState(() {
                    // Untied, it keeps the deadline it had.
                    if (!value) _deadline = _shownDeadline;
                    _follows = value;
                  }),
                ),
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
                  days: true,
                  onChanged: () => setState(() {}),
                ),
              ] else ...[
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
          onTap: () =>
              _editHtml('Description', _description, (v) => _description = v),
          child: _html(_description, 'Add description'),
        ),
        GoalField(
          label: 'Definition of done',
          onTap: () => _editHtml(
            'Definition of done',
            _definitionOfDone,
            (v) => _definitionOfDone = v,
          ),
          child: _html(_definitionOfDone, 'Add definition of done'),
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

  /// An HTML field's [text] as it reads, or [empty] while there's none.
  static Widget _html(String? text, String empty) => text == null
      ? GoalFieldEmpty(empty)
      : EventDescription(text, maxLines: 4, expandable: false);
}

/// Names people by id from [memory]: an id it doesn't know, as itself.
String Function(String id) goalPeopleNames(PlanMemory? memory) {
  final byId = {
    for (final p in memory?.people?.withSelf ?? const <Person>[])
      p.id: personName(p),
  };
  return (id) => byId[id] ?? id;
}

/// Who a goal is done with and for, named by [names]: "With Ana · For
/// Sam"; null if no one.
String? goalPeopleLabel(
  List<String> withIds,
  List<String> forIds,
  String Function(String id) names,
) {
  final parts = [
    if (withIds.isNotEmpty) 'With ${withIds.map(names).join(', ')}',
    if (forIds.isNotEmpty) 'For ${forIds.map(names).join(', ')}',
  ];
  return parts.isEmpty ? null : parts.join(' · ');
}

/// An HTML field, as it reads, tapped to edit: "Add [label]" while
/// there's nothing in it.
class HtmlField extends StatelessWidget {
  const HtmlField({
    super.key,
    required this.label,
    required this.text,
    required this.onTap,
  });

  final String label;
  final String? text;
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
                    EventDescription(text, maxLines: 4, expandable: false)
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
