import 'package:flutter/material.dart';

import '../models/goal.dart';
import '../models/measure.dart';
import 'durations.dart';

/// The statuses of sub-goals a weighted rollup's weights leave out: not
/// yet taken up, or done with.
const _hiddenFromWeights = {'proposed', 'completed', 'archived', 'deleted'};

/// Edits a goal's measure: a kind picked from [measureKinds] (or none),
/// then that kind's fields. Calls [onChanged] with the measure as it
/// stands after every edit -- null for none -- whether or not it's valid
/// yet; see [measureProblem].
///
/// A time-spent, number-of-events, time-of-day or time-window measure looks
/// at the events of its own goal, or of a goal chosen from [goals]; with or
/// without their sub-goals. A weighted rollup weighs each of [goalId]'s
/// sub-goals, from [goals]. Any measure can be rated only on days with
/// events of its goal, or of another.
class MeasureEditor extends StatefulWidget {
  const MeasureEditor({
    super.key,
    required this.measure,
    required this.onChanged,
    this.goalId,
    this.goals,
  });

  final Measure? measure;
  final ValueChanged<Measure?> onChanged;

  /// The goal it measures; null for one not created yet, which has no
  /// sub-goals to weigh.
  final String? goalId;

  /// Every goal, to choose whose events are looked at; without it, only
  /// the measure's own goal can be.
  final Future<List<Goal>>? goals;

  @override
  State<MeasureEditor> createState() => _MeasureEditorState();
}

class _MeasureEditorState extends State<MeasureEditor> {
  String? _kind;
  final _target = TextEditingController();
  final _noun = TextEditingController();
  final _grace = TextEditingController();
  final _zeroAt = TextEditingController();
  final _prompt = TextEditingController();
  final _rubric = TextEditingController();
  final _interval = TextEditingController();
  final _zeroAtDays = TextEditingController();
  final _percentile = TextEditingController();
  String _timeTarget = '09:00';
  String _windowFrom = '12:00';
  String _windowTo = '13:00';
  String _edge = 'start';
  String _when = 'by';
  String _agg = 'mean';

  /// A weighted rollup's weight for each sub-goal, by id.
  final _weights = <String, TextEditingController>{};

  /// The goal's sub-goals, once [MeasureEditor.goals] has them: a weight
  /// for any other goal, one that's since moved, isn't kept.
  Set<String>? _subGoalIds;

  /// Whether it looks at another goal's events, as though it were that
  /// goal; and which, once picked.
  bool _otherGoal = false;
  String? _eventsOf;
  bool _subGoals = true;

  /// Whether it's rated only on days with events of its goal, or of
  /// another; which, once picked; and whether their sub-goals' count.
  bool _onlyIf = false;
  bool _onlyIfOtherGoal = false;
  String? _onlyIfEventsOf;
  bool _onlyIfSubGoals = true;

  @override
  void initState() {
    super.initState();
    final m = widget.measure ?? const {};
    _kind = measureKinds.containsKey(m['kind']) ? m['kind'] as String : null;
    String text(Object? value) => switch (value) {
      final num n => '${n == n.roundToDouble() ? n.round() : n}',
      final String s => s,
      _ => '',
    };
    // From before events_of, the first of the goals it counted.
    _eventsOf = switch ((m['events_of'], m['goal_ids'])) {
      (final String id, _) || (_, [final String id, ...]) => id,
      _ => null,
    };
    _otherGoal = _eventsOf != null;
    if (m['include_sub_goals'] == false) _subGoals = false;
    if (m['only_if'] case final Map onlyIf) {
      _onlyIf = true;
      if (onlyIf['events_of'] case final String id) _onlyIfEventsOf = id;
      _onlyIfOtherGoal = onlyIf.containsKey('events_of');
      _onlyIfSubGoals = onlyIf['include_sub_goals'] != false;
    }
    _interval.text = text(m['interval_days']);
    _zeroAtDays.text = text(m['zero_at_days']);
    switch (_kind) {
      case 'duration':
        if (m['target_min'] case final num minutes) {
          _target.text = formatMinutes(minutes);
        }
      case 'count':
        _target.text = text(m['target']);
        _noun.text = text(m['noun']);
      case 'time_constraint':
        if (m['target'] case final String target) _timeTarget = target;
        if (m['edge'] == 'end') _edge = 'end';
        if (m['when'] == 'after') _when = 'after';
        _grace.text = text(m['grace_min']);
        _zeroAt.text = text(m['zero_at_min']);
      case 'time_window':
        if (m['from'] case final String from) _windowFrom = from;
        if (m['to'] case final String to) _windowTo = to;
        _grace.text = text(m['grace_min']);
        _zeroAt.text = text(m['zero_at_min']);
      case 'subjective':
        _prompt.text = text(m['prompt']);
      case 'llm':
        _rubric.text = text(m['rubric']);
      case 'rollup':
        _agg = switch (m['agg']) {
          'weighted' => 'weighted',
          'percentile' => 'percentile',
          'min' => 'percentile', // From before percentiles: the lowest.
          _ => 'mean',
        };
        _percentile.text = m['agg'] == 'min' ? '0' : text(m['percentile']);
        if (m['weights'] case final Map weights) {
          for (final MapEntry(:key, :value) in weights.entries) {
            _weights[key as String] = TextEditingController(text: text(value));
          }
        }
    }
  }

  @override
  void dispose() {
    for (final c in [
      _target,
      _noun,
      _grace,
      _zeroAt,
      _prompt,
      _rubric,
      _interval,
      _zeroAtDays,
      _percentile,
      ..._weights.values,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  /// The measure as the fields have it; a field that's empty is left out,
  /// and one that doesn't parse is kept as typed, for [measureProblem] to
  /// refuse.
  Measure? get _measure => switch (_kindMeasure) {
    final measure? when _onlyIf => {
      ...measure,
      'only_if': {
        // Another goal not picked yet is empty, for measureProblem.
        if (_onlyIfOtherGoal) 'events_of': _onlyIfEventsOf ?? '',
        if (!_onlyIfSubGoals) 'include_sub_goals': false,
      },
    },
    final measure => measure,
  };

  /// The measure as its kind's fields have it, without `only_if`.
  Measure? get _kindMeasure {
    Object? number(TextEditingController c) {
      final t = c.text.trim();
      return t.isEmpty ? null : (num.tryParse(t) ?? t);
    }

    String? text(TextEditingController c) {
      final t = c.text.trim();
      return t.isEmpty ? null : t;
    }

    // Whose events: left out for the defaults. Another goal not picked
    // yet is empty, for measureProblem to ask for.
    final source = {
      if (_otherGoal) 'events_of': _eventsOf ?? '',
      if (!_subGoals) 'include_sub_goals': false,
    };
    final events = {
      'interval_days': ?number(_interval),
      'zero_at_days': ?number(_zeroAtDays),
      ...source,
    };
    return switch (_kind) {
      null => null,
      'duration' => {
        'kind': 'duration',
        'target_min': switch (_target.text.trim()) {
          '' => null,
          final t => parseDuration(t)?.inMinutes ?? t,
        },
        ...events,
      },
      'count' => {
        'kind': 'count',
        'target': number(_target),
        'noun': ?text(_noun),
        ...events,
      },
      'time_constraint' => {
        'kind': 'time_constraint',
        'edge': _edge,
        'target': _timeTarget,
        if (_when != 'by') 'when': _when,
        'grace_min': ?number(_grace),
        'zero_at_min': ?number(_zeroAt),
        ...source,
      },
      'time_window' => {
        'kind': 'time_window',
        'from': _windowFrom,
        'to': _windowTo,
        'grace_min': ?number(_grace),
        'zero_at_min': ?number(_zeroAt),
        ...source,
      },
      'subjective' => {
        'kind': 'subjective',
        'prompt': text(_prompt),
        'interval_days': ?number(_interval),
      },
      'llm' => {'kind': 'llm', 'rubric': text(_rubric)},
      'rollup' => {
        'kind': 'rollup',
        'agg': _agg,
        if (_agg == 'weighted')
          'weights': {
            for (final MapEntry(:key, :value) in _weights.entries)
              if (_subGoalIds?.contains(key) ?? true) key: ?number(value),
          },
        if (_agg == 'percentile') 'percentile': number(_percentile),
      },
      final kind => {'kind': kind},
    };
  }

  void _changed() => widget.onChanged(_measure);

  /// Asks for a time of day, starting from [current] ("HH:MM"), and gives
  /// [set] the one picked.
  Future<void> _pickTime(String current, ValueChanged<String> set) async {
    final [hour, minute] = current.split(':').map(int.parse).toList();
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: hour, minute: minute),
    );
    if (picked == null) return;
    setState(() {
      set(
        '${picked.hour.toString().padLeft(2, '0')}:'
        '${picked.minute.toString().padLeft(2, '0')}',
      );
    });
    _changed();
  }

  /// A chip showing [time], which picks another with [_pickTime].
  Widget _timeChip(String time, ValueChanged<String> set, {String? label}) =>
      ActionChip(
        avatar: const Icon(Icons.schedule),
        label: Text(label == null ? time : '$label $time'),
        onPressed: () => _pickTime(time, set),
      );

  /// Whose events a time-spent, number-of-events, time-of-day or
  /// time-window measure looks at: its own goal's, or another's, as though
  /// it were that goal.
  List<Widget> _whoseEvents(ThemeData theme) => [
    Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 4),
      child: Text('Events of', style: theme.textTheme.labelMedium),
    ),
    ..._goalChoice(
      otherGoal: _otherGoal,
      setOtherGoal: (other) => _otherGoal = other,
      eventsOf: _eventsOf,
      setEventsOf: (id) => _eventsOf = id,
      subGoals: _subGoals,
      setSubGoals: (on) => _subGoals = on,
    ),
  ];

  /// Whether it's rated only on days with events of its goal, or another's:
  /// on the rest, it's skipped, and a question isn't asked.
  List<Widget> _onlyIfDays(ThemeData theme) => [
    SwitchListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      title: const Text('Only rate days with events'),
      subtitle: const Text('Other days are skipped, without asking.'),
      value: _onlyIf,
      onChanged: (on) {
        setState(() => _onlyIf = on);
        _changed();
      },
    ),
    if (_onlyIf)
      ..._goalChoice(
        otherGoal: _onlyIfOtherGoal,
        setOtherGoal: (other) => _onlyIfOtherGoal = other,
        eventsOf: _onlyIfEventsOf,
        setEventsOf: (id) => _onlyIfEventsOf = id,
        subGoals: _onlyIfSubGoals,
        setSubGoals: (on) => _onlyIfSubGoals = on,
      ),
  ];

  /// This goal or another, picked from [MeasureEditor.goals], and whether
  /// its sub-goals' events count.
  List<Widget> _goalChoice({
    required bool otherGoal,
    required ValueChanged<bool> setOtherGoal,
    required String? eventsOf,
    required ValueChanged<String?> setEventsOf,
    required bool subGoals,
    required ValueChanged<bool> setSubGoals,
  }) {
    return [
      SegmentedButton<bool>(
        showSelectedIcon: false,
        segments: const [
          ButtonSegment(value: false, label: Text('This goal')),
          ButtonSegment(value: true, label: Text('Another goal')),
        ],
        selected: {otherGoal},
        onSelectionChanged: (picked) {
          setState(() => setOtherGoal(picked.single));
          _changed();
        },
      ),
      if (otherGoal)
        FutureBuilder(
          future: widget.goals,
          builder: (context, snapshot) {
            final goals = snapshot.data;
            if (widget.goals == null) {
              return const Text('No goals to choose from.');
            }
            if (goals == null) {
              return snapshot.hasError
                  ? const Text("Couldn't load the goals.")
                  : const LinearProgressIndicator();
            }
            final choices = [
              for (final goal in goals)
                if (goal.id != null &&
                    !goal.isOverall &&
                    goal.id != widget.goalId)
                  goal,
            ];
            return DropdownButton<String?>(
              isExpanded: true,
              hint: const Text('Pick a goal'),
              value: choices.any((g) => g.id == eventsOf) ? eventsOf : null,
              items: [
                for (final goal in choices)
                  DropdownMenuItem(
                    value: goal.id,
                    child: Padding(
                      padding: EdgeInsetsDirectional.only(
                        start: 16.0 * goal.depth,
                      ),
                      child: Text(goalName(goal)),
                    ),
                  ),
              ],
              onChanged: (picked) {
                setState(() => setEventsOf(picked));
                _changed();
              },
            );
          },
        ),
      SwitchListTile(
        dense: true,
        contentPadding: EdgeInsets.zero,
        title: const Text("Include its sub-goals' events"),
        value: subGoals,
        onChanged: (on) {
          setState(() => setSubGoals(on));
          _changed();
        },
      ),
    ];
  }

  /// A weighted rollup's weight for each of the goal's sub-goals: one it
  /// isn't given counts for nothing.
  Widget _weightFields(ThemeData theme) => FutureBuilder(
    future: widget.goals,
    builder: (context, snapshot) {
      final goals = snapshot.data;
      if (widget.goals == null || widget.goalId == null) {
        return const Text('No sub-goals to weigh yet.');
      }
      if (goals == null) {
        return snapshot.hasError
            ? const Text("Couldn't load the sub-goals.")
            : const LinearProgressIndicator();
      }
      // The overall goal's sub-goals are the top-level goals.
      final overall = widget.goalId == overallGoalId;
      final subGoals = [
        for (final goal in goals)
          if (goal.id != null &&
              !goal.isOverall &&
              (overall
                  ? goal.parentId == null
                  : goal.parentId == widget.goalId))
            goal,
      ];
      // Every sub-goal keeps its weight, but only active and inactive ones
      // are shown; an inactive one (which isn't rated) is greyed.
      _subGoalIds = {for (final goal in subGoals) goal.id!};
      final shown = [
        for (final goal in subGoals)
          if (!_hiddenFromWeights.contains(goal.status)) goal,
      ];
      if (shown.isEmpty) return const Text('It has no sub-goals yet.');
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final goal in shown)
            _field(
              _weights.putIfAbsent(goal.id!, TextEditingController.new),
              goalName(goal),
              hint: '0',
              number: true,
              muted: goal.active
                  ? null
                  : '${goalStatuses[goal.status] ?? goal.status}: '
                        "not rated, so it doesn't count",
            ),
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              'A sub-goal with no weight, or one added later, counts for '
              'nothing.',
              style: theme.textTheme.bodySmall,
            ),
          ),
        ],
      );
    },
  );

  Widget _field(
    TextEditingController controller,
    String label, {
    String? hint,
    String? suffix,
    bool number = false,
    int maxLines = 1,
    String? muted,
    bool capitalize = true,
  }) => Padding(
    padding: const EdgeInsets.only(top: 12),
    child: TextField(
      controller: controller,
      keyboardType: number
          ? const TextInputType.numberWithOptions(decimal: true)
          : maxLines > 1
          ? TextInputType.multiline
          : TextInputType.text,
      minLines: 1,
      maxLines: maxLines,
      textCapitalization: number || !capitalize
          ? TextCapitalization.none
          : TextCapitalization.sentences,
      decoration: InputDecoration(
        isDense: true,
        border: const OutlineInputBorder(),
        labelText: label,
        // So the hint, often the default, shows while it's empty.
        floatingLabelBehavior: FloatingLabelBehavior.always,
        hintText: hint,
        suffixText: suffix,
        // Greyed, with why, for a field that doesn't count for now.
        labelStyle: muted == null
            ? null
            : TextStyle(color: Theme.of(context).hintColor),
        floatingLabelStyle: muted == null
            ? null
            : TextStyle(color: Theme.of(context).hintColor),
        helperText: muted,
      ),
      onChanged: (_) => _changed(),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final kind = _kind;
    final lookBack = [
      _field(
        _interval,
        'Over the last',
        hint: '1',
        suffix: 'days',
        number: true,
      ),
      _field(
        _zeroAtDays,
        'Zero at, in days',
        hint: 'none: rated by how much',
        number: true,
      ),
      Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Text(
          'Short of the target, it falls to 0 by "zero at" days since it was '
          "last met; without one, it's rated by how much was done.",
          style: theme.textTheme.bodySmall,
        ),
      ),
    ];
    final minutesOff = [
      _field(_grace, 'Grace, in minutes', hint: '0', number: true),
      _field(_zeroAt, 'Zero at, in minutes off', hint: '60', number: true),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        DropdownButton<String?>(
          isExpanded: true,
          value: kind,
          items: [
            const DropdownMenuItem(value: null, child: Text('(none)')),
            for (final MapEntry(:key, :value) in measureKinds.entries)
              DropdownMenuItem(value: key, child: Text(value)),
          ],
          onChanged: (picked) {
            setState(() => _kind = picked);
            _changed();
          },
        ),
        if (measureKindHints[kind] case final hint?)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              hint,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ...switch (kind) {
          'duration' => [
            _field(_target, 'Target', hint: 'e.g. 10h or 1h 30m'),
            ...lookBack,
            ..._whoseEvents(theme),
          ],
          'count' => [
            _field(_target, 'Target', number: true),
            _field(
              _noun,
              "What's counted (display only)",
              hint: 'e.g. visits',
              // Read mid-sentence ("2 of 3 visits"), so lower-case.
              capitalize: false,
            ),
            ...lookBack,
            ..._whoseEvents(theme),
          ],
          'time_constraint' => [
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: SegmentedButton<String>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(value: 'start', label: Text('First starts')),
                  ButtonSegment(value: 'end', label: Text('Last ends')),
                ],
                selected: {_edge},
                onSelectionChanged: (picked) {
                  setState(() => _edge = picked.single);
                  _changed();
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: SegmentedButton<String>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(value: 'by', label: Text('By')),
                  ButtonSegment(value: 'after', label: Text('Not before')),
                ],
                selected: {_when},
                onSelectionChanged: (picked) {
                  setState(() => _when = picked.single);
                  _changed();
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: _timeChip(_timeTarget, (t) => _timeTarget = t),
            ),
            ...minutesOff,
            ..._whoseEvents(theme),
          ],
          'time_window' => [
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _timeChip(_windowFrom, (t) => _windowFrom = t, label: 'From'),
                  _timeChip(_windowTo, (t) => _windowTo = t, label: 'to'),
                ],
              ),
            ),
            ...minutesOff,
            ..._whoseEvents(theme),
          ],
          'subjective' => [
            _field(_prompt, 'Question', hint: 'e.g. How did it turn out?'),
            _field(
              _interval,
              'Ask every',
              hint: '1',
              suffix: 'days',
              number: true,
            ),
          ],
          'llm' => [_field(_rubric, 'Rubric', maxLines: 5)],
          'rollup' => [
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: SegmentedButton<String>(
                showSelectedIcon: false,
                segments: [
                  for (final MapEntry(:key, :value) in rollupAggregates.entries)
                    ButtonSegment(value: key, label: Text(value)),
                ],
                selected: {_agg},
                onSelectionChanged: (picked) {
                  setState(() => _agg = picked.single);
                  _changed();
                },
              ),
            ),
            if (_agg == 'percentile')
              _field(
                _percentile,
                'Percentile',
                hint: '0 is the lowest, 50 the median, 100 the highest',
                number: true,
              ),
            if (_agg == 'weighted') _weightFields(theme),
          ],
          _ => const <Widget>[],
        },
        if (kind != null) ..._onlyIfDays(theme),
      ],
    );
  }
}
