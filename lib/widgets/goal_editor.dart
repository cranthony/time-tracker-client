import 'package:flutter/material.dart';

import '../models/goal.dart';
import '../models/goal_changes.dart';
import 'duration_field.dart';
import 'edit_page.dart';
import 'event_description.dart';
import 'html_editor.dart';

/// Adds a goal (with no [goal]) under [parent] (the top level, if null),
/// or edits [goal], on a page of its own: its title, deadline (a date,
/// and a time if wanted), expected time, whether its parent needs it, its
/// description and definition of done (HTML, in [showHtmlEditor]) and
/// the hints for telling its events. A new one starts active, or
/// inactive if chosen; an active one needs a deadline. Saving is off
/// while the change breaks a rule (see [planned]) against [goals], every
/// goal there is, saying which. Gives a new goal's fields, or an edit's
/// changes (a null clearing a field) -- null if nothing's saved.
Future<Map<String, Object?>?> showGoalEditor(
  BuildContext context, {
  Goal? goal,
  Goal? parent,
  required List<Goal> goals,
  DateTime Function() now = DateTime.now,
}) => Navigator.of(context).push<Map<String, Object?>>(
  MaterialPageRoute(
    fullscreenDialog: true,
    builder: (_) => GoalEditorPage(
      goal: goal,
      parent: parent ?? GoalTree(goals)[goal?.parentId],
      goals: goals,
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
    this.now = DateTime.now,
  });

  final Goal? goal;
  final Goal? parent;
  final List<Goal> goals;
  final DateTime Function() now;

  @override
  State<GoalEditorPage> createState() => _GoalEditorPageState();
}

class _GoalEditorPageState extends State<GoalEditorPage> {
  Goal? get _goal => widget.goal;

  late final _title = TextEditingController(text: _goal?.title ?? '');
  late final _hints = TextEditingController(
    text: _goal?.attributionHints ?? '',
  );
  late final _minutes = TextEditingController(
    text: _goal?.expectedMinutes?.toString() ?? '',
  );
  late String? _deadline = _goal?.deadline;
  late String _status = _goal?.status ?? 'active';
  late bool _required = _goal?.required ?? false;
  late String? _description = _goal?.description;
  late String? _definitionOfDone = _goal?.definitionOfDone;

  @override
  void dispose() {
    _title.dispose();
    _hints.dispose();
    _minutes.dispose();
    super.dispose();
  }

  String? _text(TextEditingController c) =>
      c.text.trim().isEmpty ? null : c.text.trim();

  int? get _expected => switch (num.tryParse(_minutes.text.trim())) {
    final m? when m > 0 => m.round(),
    _ => null,
  };

  /// What's set, keyed as the server takes it.
  Map<String, Object?> get _fields => {
    'title': _title.text.trim(),
    'deadline': _deadline,
    'expected_minutes': _expected,
    'required': widget.parent == null ? null : _required,
    'description': _description,
    'definition_of_done': _definitionOfDone,
    'attribution_hints': _text(_hints),
  };

  /// A new goal's fields, or what an edit changes.
  Map<String, Object?> get _changes {
    final goal = _goal;
    final fields = _fields;
    if (goal == null) {
      return {...fields, 'parent_id': widget.parent?.id, 'status': _status}
        ..removeWhere((_, v) => v == null);
    }
    final before = {
      'title': goal.title,
      'deadline': goal.deadline,
      'expected_minutes': goal.expectedMinutes,
      'required': goal.parentId == null ? null : goal.required,
      'description': goal.description,
      'definition_of_done': goal.definitionOfDone,
      'attribution_hints': goal.attributionHints,
    };
    return {
      for (final MapEntry(:key, :value) in fields.entries)
        if (value != before[key]) key: value,
    };
  }

  String? get _problem {
    if (_title.text.trim().isEmpty) return 'Give it a title.';
    final goal = _goal;
    final changes = goal == null
        ? [
            GoalCreate(Goal.fromJson({'id': '\u0000new', ..._changes})),
          ]
        : [GoalUpdate(goal.id, _changes)];
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
    final problem = _problem;
    final now = widget.now();
    final open = goal == null ? _status : goal.status;
    return EditPage(
      title: goal == null
          ? (parent == null ? 'New goal' : 'New sub-goal')
          : 'Edit goal',
      problem: problem,
      changed: () => _changes.isNotEmpty,
      onSave: () => Navigator.of(context).pop(_changes),
      children: [
        if (parent != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              'Under ${[...GoalTree(widget.goals).pathOf(parent.id), goalTitle(parent)].join(' › ')}',
              style: theme.textTheme.bodySmall,
            ),
          ),
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
        if (goal == null) ...[
          const SizedBox(height: 16),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'active', label: Text('Start active')),
              ButtonSegment(value: 'inactive', label: Text('Start inactive')),
            ],
            selected: {_status},
            onSelectionChanged: (picked) =>
                setState(() => _status = picked.single),
          ),
        ],
        const SizedBox(height: 16),
        Text('Deadline', style: theme.textTheme.labelLarge),
        const SizedBox(height: 4),
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
                  deadlineHasTime(_deadline) ? 'Change time' : 'Add a time',
                ),
                onPressed: _pickTime,
              ),
            if (deadlineHasTime(_deadline))
              TextButton(
                onPressed: () =>
                    setState(() => _deadline = _deadline!.split('T').first),
                child: const Text('End of day'),
              ),
            if (_deadline != null && open != 'active')
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
              onPressed: () => setState(() => _deadline = endOfToday(now)),
            ),
            ActionChip(
              label: const Text('End of this week'),
              onPressed: () => setState(() => _deadline = endOfWeek(now)),
            ),
            if (parent?.deadline case final parentDeadline?)
              ActionChip(
                label: const Text("Parent's"),
                onPressed: () => setState(() => _deadline = parentDeadline),
              ),
          ],
        ),
        const SizedBox(height: 16),
        DurationField(
          controller: _minutes,
          label: 'Expected time (optional)',
          onChanged: () => setState(() {}),
        ),
        if (parent != null)
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Required'),
            subtitle: Text('“${goalTitle(parent)}” needs it done to be done'),
            value: _required,
            onChanged: (value) => setState(() => _required = value),
          ),
        const SizedBox(height: 8),
        _HtmlField(
          label: 'Description',
          text: _description,
          onTap: () =>
              _editHtml('Description', _description, (v) => _description = v),
        ),
        _HtmlField(
          label: 'Definition of done',
          text: _definitionOfDone,
          onTap: () => _editHtml(
            'Definition of done',
            _definitionOfDone,
            (v) => _definitionOfDone = v,
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _hints,
          minLines: 2,
          maxLines: 6,
          decoration: const InputDecoration(
            labelText: 'Attribution hints',
            hintText: 'How Claude can tell which events are for it',
          ),
          onChanged: (_) => setState(() {}),
        ),
      ],
    );
  }
}

/// An HTML field, as it reads, tapped to edit.
class _HtmlField extends StatelessWidget {
  const _HtmlField({
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
