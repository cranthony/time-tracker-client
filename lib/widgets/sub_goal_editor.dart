import 'dart:convert';

import 'package:flutter/material.dart';

import '../models/facts.dart';
import '../models/goal.dart';
import '../models/sub_goal_template.dart';
import '../services/plan_memory.dart';
import 'color_picker.dart';
import 'duration_field.dart';
import 'durations.dart';
import 'edit_page.dart';
import 'goal_editor.dart' show FormattedField, goalPeopleLabel, goalPeopleNames;
import 'goal_fields.dart';
import 'goal_starts.dart';
import 'picker_sheet.dart';
import 'text_editor.dart';

/// When [sub], a habit's sub-goal template, is due: "Due with its goal",
/// "Due 2 days before its goal".
String subGoalDueLabel(Map sub) =>
    switch (offsetWords(sub['deadline'] as Map?)) {
      final words? => 'Due ${words.toLowerCase()} before its goal',
      null => 'Due with its goal',
    };

/// What [sub] waits for before it starts, a line each, its sibling
/// sub-goals named by key from [titles], its holds counted for priority
/// [priority]: "After “Buy groceries” closes", "3 days before its goal is
/// due", "Then the next day". Empty if it starts with its goal.
List<String> subGoalStartsLines(
  Map sub,
  Map<String, String> titles, {
  required int priority,
}) {
  final when = sub['activate_when'];
  if (when is! Map) return const [];
  return [
    for (final t in when['after'] as List? ?? const [])
      switch (t) {
        {'goal_closed': final String key} =>
          'After “${titles[key] ?? key}” closes',
        {'before_parent': final Map offset} => switch (offsetWords(offset)) {
          final w? => '$w before its goal is due',
          null => 'When its goal is due',
        },
        _ => 'After something unknown',
      },
    if (when['delay'] == 'next_day') 'Then the next day',
    if (when['delay'] case {'minutes': final num m} when m > 0)
      'Then ${formatMinutes(m)} later',
    for (final hold in when['hold_while'] as List? ?? const [])
      if (hold is Map) 'Held while ${holdLabel(hold, priority)}',
  ];
}

/// [sub] in a line: how long it's expected to take, whether its goal can
/// be done without it, when it's due, and when it starts -- "3h · Due 1
/// day before its goal · Starts after “Buy groceries” closes, 3 days
/// before its goal is due".
String subGoalSummary(
  Map sub,
  Map<String, String> titles, {
  required int priority,
}) {
  final starts = subGoalStartsLines(sub, titles, priority: priority);
  return [
    if ((sub['expected_minutes'] as num?) case final m? when m > 0)
      formatMinutes(m),
    if (sub['required'] != true) 'Optional',
    subGoalDueLabel(sub),
    if (starts.isEmpty)
      'Starts with its goal'
    else
      'Starts ${starts.map(_lowerFirst).join(', ')}',
  ].join(' · ');
}

String _lowerFirst(String s) =>
    s.isEmpty ? s : s[0].toLowerCase() + s.substring(1);

/// Adds a sub-goal to a habit's chain (with no [sub]) or edits [sub], on
/// a page of its own: its title, when it's due and when it starts --
/// each some time before its goal's deadline ([goalTitle]'s), or, for a
/// start, once others of [siblings] close, then the next day or a while
/// later, and held while other goals are active -- its priority (its
/// goal's, [goalPriority], inherited, or its own), expected time, whether
/// its goal needs it, whom it's done with and for, its description and
/// definition of done, and the hints for telling its events. A new one
/// is keyed from its title, unlike [siblings]. Returns the sub-goal as
/// saved -- fields it doesn't edit kept as they were -- `(sub: null)` if
/// it's removed, or null if it's called off.
Future<({Map<String, Object?>? sub})?> showSubGoalEditor(
  BuildContext context, {
  Map<String, Object?>? sub,
  required List<Map<String, Object?>> siblings,
  required String goalTitle,
  required int goalPriority,
}) => showEditPage(
  context,
  _SubGoalEditor(
    sub: sub,
    siblings: siblings,
    goalTitle: goalTitle,
    goalPriority: goalPriority,
  ),
);

/// When a sub-goal waits after what it waits for.
enum _Delay { none, nextDay, minutes }

class _SubGoalEditor extends StatefulWidget {
  const _SubGoalEditor({
    required this.sub,
    required this.siblings,
    required this.goalTitle,
    required this.goalPriority,
  });

  final Map<String, Object?>? sub;
  final List<Map<String, Object?>> siblings;
  final String goalTitle;
  final int goalPriority;

  @override
  State<_SubGoalEditor> createState() => _SubGoalEditorState();
}

class _SubGoalEditorState extends State<_SubGoalEditor> {
  Map<String, Object?> get _was => widget.sub ?? const {};

  late final _title = TextEditingController(
    text: _was['title'] as String? ?? '',
  );
  late final _due = TextEditingController(text: '${dueBeforeMinutes(_was)}');
  var _duePicks = 0;

  Map get _when => _was['activate_when'] as Map? ?? const {};

  /// Whether it waits to start, not starting with its goal.
  late bool _waits = _was['activate_when'] is Map;

  /// Whether it waits for a time before its goal's deadline, and how long
  /// before.
  late bool _waitsForTime = beforeParent(_was) != null;
  late final _startsBefore = TextEditingController(
    text: '${startsBeforeMinutes(_was) ?? 7 * Duration.minutesPerDay}',
  );
  var _startsPicks = 0;

  /// The other sub-goals it waits to close, by key.
  late List<String> _afterKeys = waitsForKeys(_was);

  late _Delay _delay = switch (_when['delay']) {
    'next_day' => _Delay.nextDay,
    {'minutes': _} => _Delay.minutes,
    _ => _Delay.none,
  };
  late final _delayMinutes = TextEditingController(
    text: switch (_when['delay']) {
      {'minutes': final num m} => '${m.round()}',
      _ => '60',
    },
  );
  late Map<String, Object?>? _hold = switch (_when['hold_while']) {
    [final Map h, ...] => h.cast<String, Object?>(),
    _ => null,
  };

  late int? _priority = (_was['priority'] as num?)?.toInt();
  late final _minutes = TextEditingController(
    text: (_was['expected_minutes'] as num?)?.round().toString() ?? '',
  );
  late bool _required = _was['required'] == true;
  late List<Named> _with = Named.listFromJson(_was['with_ids']);
  late List<Named> _for = Named.listFromJson(_was['for_ids']);
  late String? _description = _was['description'] as String?;
  late TextFormat? _descriptionFormat = TextFormat.fromJson(
    _was['description_format'],
  );
  late String? _definitionOfDone = _was['definition_of_done'] as String?;
  late TextFormat? _definitionOfDoneFormat = TextFormat.fromJson(
    _was['definition_of_done_format'],
  );
  late final _hints = TextEditingController(
    text: _was['attribution_hints'] as String? ?? '',
  );

  @override
  void dispose() {
    _title.dispose();
    _due.dispose();
    _startsBefore.dispose();
    _delayMinutes.dispose();
    _minutes.dispose();
    _hints.dispose();
    super.dispose();
  }

  static int? _minutesIn(TextEditingController c) =>
      switch (num.tryParse(c.text.trim())) {
        final m? when m >= 0 => m.round(),
        _ => null,
      };

  String? _text(TextEditingController c) =>
      c.text.trim().isEmpty ? null : c.text.trim();

  /// Its key: as it was, or, for a new one, from its title.
  String get _key =>
      subGoalKey(_was) ??
      newSubGoalKey(_title.text, [
        for (final s in widget.siblings) ?subGoalKey(s),
      ]);

  /// The others, by key, with their titles.
  Map<String, String> get _titles => {
    for (final s in widget.siblings) ?subGoalKey(s): subGoalTitle(s),
  };

  /// What it waits for, as the server takes it; null if it starts with
  /// its goal.
  Map<String, Object?>? get _activateWhen {
    if (!_waits) return null;
    // A field the app doesn't know is kept, as are triggers it doesn't.
    final rest = {
      for (final MapEntry(:key, :value) in _when.entries)
        if (!const {'after', 'delay', 'hold_while'}.contains(key))
          key as String: value,
    };
    final after = [
      for (final t in _when['after'] as List? ?? const [])
        if (t is Map &&
            !t.containsKey('goal_closed') &&
            !t.containsKey('before_parent'))
          t,
      if (_waitsForTime)
        {'before_parent': offsetOf(_minutesIn(_startsBefore) ?? 0)},
      for (final key in _afterKeys) {'goal_closed': key},
    ];
    return {
      ...rest,
      if (after.isNotEmpty) 'after': after,
      if (after.isNotEmpty)
        'delay': ?switch (_delay) {
          _Delay.nextDay => 'next_day',
          _Delay.minutes => {'minutes': _minutesIn(_delayMinutes) ?? 0},
          _Delay.none => null,
        },
      if (_hold case final hold?) 'hold_while': [hold],
    };
  }

  /// The sub-goal as it's saved: what it was, with what's edited here.
  Map<String, Object?> get _saved {
    final due = _minutesIn(_due) ?? 0;
    final fields = <String, Object?>{
      'key': _key,
      'title': _title.text.trim(),
      'deadline': due > 0 ? offsetOf(due) : null,
      'activate_when': _activateWhen,
      'priority': _priority,
      'expected_minutes': switch (_minutesIn(_minutes)) {
        final m? when m > 0 => m,
        _ => null,
      },
      'required': _required ? true : null,
      'with_ids': _with.isEmpty ? null : namedToJson(_with),
      'for_ids': _for.isEmpty ? null : namedToJson(_for),
      'description': _description,
      'description_format': _description == null
          ? null
          : _descriptionFormat?.wire,
      'definition_of_done': _definitionOfDone,
      'definition_of_done_format': _definitionOfDone == null
          ? null
          : _definitionOfDoneFormat?.wire,
      'attribution_hints': _text(_hints),
    };
    return {
      for (final MapEntry(:key, :value) in _was.entries)
        if (!fields.containsKey(key)) key: value,
      for (final MapEntry(:key, :value) in fields.entries) key: ?value,
    };
  }

  String? get _problem {
    if (_title.text.trim().isEmpty) return 'Give it a title.';
    if (_minutesIn(_due) == null) {
      return "Say how long before its goal's deadline it's due.";
    }
    if (_waits) {
      if (_waitsForTime && _minutesIn(_startsBefore) == null) {
        return "Say how long before its goal's deadline it starts.";
      }
      if (_delay == _Delay.minutes && _minutesIn(_delayMinutes) == null) {
        return 'Say how long after it waits.';
      }
      if (!_waitsForTime && _afterKeys.isEmpty && _hold == null) {
        return 'Say what it waits for, or let it start with its goal.';
      }
    }
    return null;
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
      () => set(
        edited.text.trim().isEmpty ? null : edited.text.trim(),
        edited.format,
      ),
    );
  }

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

  /// The others it can wait for: not one it waits for already, nor one
  /// waiting, through others, for it.
  List<Map<String, Object?>> get _pickable {
    final self = subGoalKey(_was);
    final byKey = {for (final s in widget.siblings) ?subGoalKey(s): s};
    bool waitsOnSelf(String key, Set<String> seen) {
      if (self == null) return false;
      for (final next in waitsForKeys(byKey[key] ?? const {})) {
        if (next == self) return true;
        if (seen.add(next) && waitsOnSelf(next, seen)) return true;
      }
      return false;
    }

    return [
      for (final s in chainOrder(widget.siblings))
        if (subGoalKey(s) case final key?
            when !_afterKeys.contains(key) && !waitsOnSelf(key, {}))
          s,
    ];
  }

  Future<void> _pickAfter() async {
    final key = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('After it closes'),
        children: [
          for (final s in _pickable)
            SimpleDialogOption(
              onPressed: () => Navigator.of(context).pop(subGoalKey(s)),
              child: Text(subGoalTitle(s)),
            ),
        ],
      ),
    );
    if (key == null || !mounted) return;
    setState(() => _afterKeys = [..._afterKeys, key]);
  }

  /// Chips setting [controller] to each of [choices], and a field for
  /// any other length, in [units], labeled [label]; [picks] keys it anew
  /// when a chip sets it.
  Widget _offsetField({
    required TextEditingController controller,
    required List<(String, int)> choices,
    required String label,
    required int picks,
    required VoidCallback picked,
  }) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Wrap(
        spacing: 8,
        runSpacing: 4,
        children: [
          for (final (text, minutes) in choices)
            ChoiceChip(
              label: Text(text),
              selected: _minutesIn(controller) == minutes,
              onSelected: (_) => setState(() {
                controller.text = '$minutes';
                picked();
              }),
            ),
        ],
      ),
      const SizedBox(height: 8),
      DurationField(
        key: ValueKey((label, picks)),
        controller: controller,
        label: label,
        units: DurationUnits.daysHours,
        onChanged: () => setState(() {}),
      ),
    ],
  );

  static const _day = Duration.minutesPerDay;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final goal = '“${widget.goalTitle}”';
    final priority = _priority ?? widget.goalPriority;
    final people = goalPeopleLabel(
      _with,
      _for,
      goalPeopleNames(PlanMemoryScope.of(context)),
    );
    final titles = _titles;
    return EditPage(
      title: widget.sub == null ? 'New sub-goal' : 'Edit sub-goal',
      problem: _problem,
      changed: () =>
          widget.sub == null || jsonEncode(_saved) != jsonEncode(widget.sub),
      onSave: () => Navigator.of(context).pop((sub: _saved)),
      actions: [
        if (widget.sub != null)
          IconButton(
            tooltip: 'Remove from the chain',
            icon: const Icon(Icons.delete_outline),
            onPressed: () => Navigator.of(context).pop((sub: null)),
          ),
      ],
      children: [
        TextField(
          controller: _title,
          autofocus: widget.sub == null,
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(
            labelText: 'Title',
            hintText: 'A step toward $goal',
            helperText: _title.text.trim().isEmpty
                ? null
                : 'Its goals’ ids end in “_$_key”'
                      '${widget.sub == null ? '' : ', kept as it’s renamed'}.',
          ),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 8),
        GoalField(
          label: 'Due',
          child: _offsetField(
            controller: _due,
            choices: const [
              ('With its goal', 0),
              ('1 day before', _day),
              ('1 week before', 7 * _day),
            ],
            label: "How long before its goal's deadline",
            picks: _duePicks,
            picked: () => _duePicks++,
          ),
        ),
        GoalField(
          label: 'Starts',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SegmentedButton<bool>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(value: false, label: Text('With its goal')),
                  ButtonSegment(value: true, label: Text('It waits')),
                ],
                selected: {_waits},
                onSelectionChanged: (picked) =>
                    setState(() => _waits = picked.single),
              ),
              if (_waits) ...[
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text("Until a time before its goal's deadline"),
                  value: _waitsForTime,
                  onChanged: (on) => setState(() => _waitsForTime = on),
                ),
                if (_waitsForTime)
                  _offsetField(
                    controller: _startsBefore,
                    choices: const [
                      ('1 day before', _day),
                      ('3 days before', 3 * _day),
                      ('1 week before', 7 * _day),
                    ],
                    label: "How long before its goal's deadline",
                    picks: _startsPicks,
                    picked: () => _startsPicks++,
                  ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    for (final key in _afterKeys)
                      InputChip(
                        avatar: const Icon(Icons.flag_outlined, size: 18),
                        label: Text('After “${titles[key] ?? key}” closes'),
                        onDeleted: () => setState(
                          () => _afterKeys = [
                            for (final k in _afterKeys)
                              if (k != key) k,
                          ],
                        ),
                      ),
                    if (_pickable.isNotEmpty)
                      ActionChip(
                        avatar: const Icon(Icons.flag_outlined, size: 18),
                        label: const Text('After another closes…'),
                        onPressed: _pickAfter,
                      ),
                  ],
                ),
                if (_waitsForTime || _afterKeys.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      for (final (delay, text) in const [
                        (_Delay.none, 'Then right away'),
                        (_Delay.nextDay, 'Then the next day'),
                        (_Delay.minutes, 'Then a while later'),
                      ])
                        ChoiceChip(
                          label: Text(text),
                          selected: _delay == delay,
                          onSelected: (_) => setState(() => _delay = delay),
                        ),
                    ],
                  ),
                  if (_delay == _Delay.minutes)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: DurationField(
                        controller: _delayMinutes,
                        label: 'How long later',
                        onChanged: () => setState(() {}),
                      ),
                    ),
                ],
                HoldWhileEditor(
                  hold: _hold,
                  priority: priority,
                  onChanged: (hold) => setState(() => _hold = hold),
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
                label: Text('Inherit (P${widget.goalPriority})'),
                tooltip: 'Its goal’s',
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
        GoalField(
          label: 'Required',
          child: SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(requiredLabel(widget.goalTitle, _required)),
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
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: FormattedField(
            label: 'Description',
            text: _description,
            format: _descriptionFormat,
            onTap: () => _editText(
              'Description',
              _description,
              _descriptionFormat,
              (text, format) {
                _description = text;
                _descriptionFormat = format;
              },
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 16),
          child: FormattedField(
            label: 'Definition of done',
            text: _definitionOfDone,
            format: _definitionOfDoneFormat,
            onTap: () => _editText(
              'Definition of done',
              _definitionOfDone,
              _definitionOfDoneFormat,
              (text, format) {
                _definitionOfDone = text;
                _definitionOfDoneFormat = format;
              },
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 16),
          child: TextField(
            controller: _hints,
            minLines: 2,
            maxLines: 6,
            decoration: const InputDecoration(
              labelText: 'Attribution hints (optional)',
              hintText: 'How Claude can tell which events are for it',
              border: OutlineInputBorder(),
              floatingLabelBehavior: FloatingLabelBehavior.always,
            ),
            onChanged: (_) => setState(() {}),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Text(
            'Made under each of the habit’s goals as it’s made; a change '
            'goes with those to come.',
            style: theme.textTheme.bodySmall,
          ),
        ),
      ],
    );
  }
}
