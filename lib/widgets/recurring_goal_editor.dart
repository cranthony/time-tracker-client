import 'dart:convert';

import 'package:flutter/material.dart';

import '../models/facts.dart';
import '../models/goal.dart' show defaultGoalPriority;
import '../models/named.dart';
import '../models/recurring_goal.dart';
import '../models/text_format.dart';
import '../services/plan_memory.dart';
import 'color_picker.dart';
import 'duration_field.dart';
import 'durations.dart';
import 'edit_page.dart';
import 'event_description.dart';
import 'goal_editor.dart' show FormattedField, goalPeopleLabel, goalPeopleNames;
import 'hotkeys.dart';
import 'picker_sheet.dart' show showWhoWhereSheet;
import 'text_editor.dart';

/// "A goal each week: Call Mom", for [goal], its habit named [habitName].
String recurringGoalTitle(RecurringGoal goal, String habitName) =>
    '${goalEachLabel(goal)}: ${goal.title ?? habitName}';

/// [goal] in a line: when its goals are done, their priority and
/// expected time, and its goal rate's span -- "We talked · P1 · 1h ·
/// goal rate over the last 6 weeks".
String recurringGoalSummary(RecurringGoal goal) => [
  switch (goal.definitionOfDone) {
    final done? => descriptionText(
      done,
      format: goal.definitionOfDoneFormat,
    ).replaceAll('\n', ' '),
    null => 'Done when its goal is',
  },
  if (goal.priority case final p?) 'P$p',
  if (goal.expectedMinutes case final m? when m > 0) formatMinutes(m),
  'goal rate over the last ${goal.ratedPeriods} '
      '${goalPeriods[goal.period]?.$2 ?? 'periods'}',
].join(' · ');

/// When each of [goal]'s goals is made: "A goal is made as each week
/// starts, on Sunday, once the one before is done; ...".
String recurringGoalMade(RecurringGoal goal) {
  final each = (goalPeriods[goal.period]?.$1 ?? 'period').toLowerCase();
  return 'A goal is made as each $each '
      '${goal.period == 'week' ? 'starts, on Sunday' : 'starts'}, once the '
      'one before is done; one missed is tried again through the next. Its '
      'events are those tagged with its goals.';
}

/// Edits the goal a habit makes for each period, [goal] (a new one's,
/// with none), on a page of its own: the period, its goals' title (the
/// habit's name, [habitName], with none), priority and expected time,
/// description and definition of done, the hints for telling its events,
/// whom its goals are done with and for, and how many periods its goal
/// rate counts. Its sub-goals, and what the app doesn't edit, are kept as
/// they were. Returns the goal as saved, or null if it's called off.
Future<RecurringGoal?> showRecurringGoalEditor(
  BuildContext context, {
  RecurringGoal? goal,
  required String habitName,
}) => showEditPage(
  context,
  _RecurringGoalEditor(goal: goal, habitName: habitName),
);

class _RecurringGoalEditor extends StatefulWidget {
  const _RecurringGoalEditor({required this.goal, required this.habitName});

  final RecurringGoal? goal;
  final String habitName;

  @override
  State<_RecurringGoalEditor> createState() => _RecurringGoalEditorState();
}

class _RecurringGoalEditorState extends State<_RecurringGoalEditor> {
  RecurringGoal get _was => widget.goal ?? const RecurringGoal();

  late String _period = _was.period;
  late final _title = TextEditingController(text: _was.title);
  late int? _priority = _was.priority;
  late final _minutes = TextEditingController(
    text: _was.expectedMinutes?.toString() ?? '',
  );

  /// Its goals' description and definition of done, and how each is
  /// written, as a goal's.
  late String? _description = _was.description;
  late TextFormat? _descriptionFormat = _was.descriptionFormat;
  late String? _definitionOfDone = _was.definitionOfDone;
  late TextFormat? _definitionOfDoneFormat = _was.definitionOfDoneFormat;
  late final _attributionHints = TextEditingController(
    text: _was.attributionHints,
  );

  /// Whom its goals are done with and for: people and circles, a plain
  /// circle with those of its people it leaves out.
  late List<Named> _with = [..._was.withWhom];
  late List<Named> _for = [..._was.forWhom];
  late final _ratePeriods = TextEditingController(text: '${_was.ratedPeriods}');

  /// Whether its goal rate's span is its own, not its period's default,
  /// which it follows as the period's changed till it's typed.
  late bool _ownRate = _was.ratePeriods != null;

  @override
  void dispose() {
    _title.dispose();
    _minutes.dispose();
    _attributionHints.dispose();
    _ratePeriods.dispose();
    super.dispose();
  }

  static String? _text(TextEditingController c) =>
      c.text.trim().isEmpty ? null : c.text.trim();

  int? get _rateValue => int.tryParse(_ratePeriods.text.trim());

  int? get _expected => switch (num.tryParse(_minutes.text.trim())?.round()) {
    final m? when m > 0 => m,
    _ => null,
  };

  RecurringGoal get _saved => RecurringGoal(
    period: _period,
    title: _text(_title),
    priority: _priority,
    expectedMinutes: _expected,
    description: _description,
    descriptionFormat: _description == null ? null : _descriptionFormat,
    definitionOfDone: _definitionOfDone,
    definitionOfDoneFormat: _definitionOfDone == null
        ? null
        : _definitionOfDoneFormat,
    attributionHints: _text(_attributionHints),
    withWhom: _with,
    forWhom: _for,
    ratePeriods: _ownRate ? _rateValue : null,
    subGoals: _was.subGoals,
  );

  String? get _problem => _rateValue == null || _rateValue! < 1
      ? 'Give how many periods its goal rate counts: 1 or more.'
      : _minutes.text.trim().isNotEmpty && _expected == null
      ? 'Give its goals’ expected time as a length of time.'
      : null;

  /// Picks [period], its goal rate's span following it unless it's
  /// been given one.
  void _pickPeriod(String period) => setState(() {
    _period = period;
    if (!_ownRate) _ratePeriods.text = '${defaultRatePeriods(period)}';
  });

  /// Picks whom its goals are done with and for, as a goal's are.
  Future<void> _pickPeople() async {
    final picked = await showWhoWhereSheet(
      context,
      Facts.named(with_: _with, for_: _for),
      withCaption: 'Who you’ll do its goals with',
      forCaption: 'Who they’re for, who won’t be part of doing them',
    );
    if (picked == null || !mounted) return;
    setState(() {
      _with = picked.facts.withWhom;
      _for = picked.facts.forWhom;
    });
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return EditPage(
      title: widget.goal == null ? 'New recurring goal' : 'Edit recurring goal',
      problem: _problem,
      changed: () =>
          widget.goal == null ||
          jsonEncode(_saved.toJson()) != jsonEncode(widget.goal!.toJson()),
      onSave: () => Navigator.of(context).pop(_saved),
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Text('A goal each', style: theme.textTheme.titleSmall),
        ),
        FieldHotkey(
          'P',
          onPressed: () =>
              _pickPeriod(nextOf(goalPeriods.keys.toList(), _period)),
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
            recurringGoalMade(RecurringGoal(period: _period)),
            style: theme.textTheme.bodySmall,
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 16),
          child: TextField(
            controller: _title,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              labelText: "Goals' title (optional)",
              hintText: widget.habitName.trim().isEmpty
                  ? "The habit's name"
                  : widget.habitName.trim(),
              border: const OutlineInputBorder(),
              isDense: true,
              floatingLabelBehavior: FloatingLabelBehavior.always,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 16, bottom: 4),
          child: Text("Goals' priority", style: theme.textTheme.labelLarge),
        ),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            ChoiceChip(
              showCheckmark: false,
              label: const Text('None (P$defaultGoalPriority)'),
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
        Padding(
          padding: const EdgeInsets.only(top: 16),
          child: DurationField(
            controller: _minutes,
            label: "Goals' expected time (optional)",
            onChanged: () => setState(() {}),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 16),
          child: _formattedField(
            theme,
            'Description',
            _description,
            _descriptionFormat,
            'Each goal is made with it; changed, it goes with those to come.',
            (text, format) {
              _description = text;
              _descriptionFormat = format;
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 16),
          child: _formattedField(
            theme,
            'Definition of done',
            _definitionOfDone,
            _definitionOfDoneFormat,
            'Compaction marks each goal done or missed by this.',
            (text, format) {
              _definitionOfDone = text;
              _definitionOfDoneFormat = format;
            },
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
            onChanged: (_) => setState(() {}),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 16),
          child: InkWell(
            borderRadius: BorderRadius.circular(4),
            onTap: _pickPeople,
            child: InputDecorator(
              isEmpty: _with.isEmpty && _for.isEmpty,
              decoration: const InputDecoration(
                labelText: 'With and for (optional)',
                hintText: 'No one: a goal of your own',
                helperText: 'Whom each goal is done with, and for.',
                isDense: true,
                border: OutlineInputBorder(),
                suffixIcon: Icon(Icons.arrow_drop_down),
              ),
              child: Text(
                goalPeopleLabel(
                      _with,
                      _for,
                      goalPeopleNames(PlanMemoryScope.of(context)),
                    ) ??
                    '',
              ),
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
      ],
    );
  }
}
