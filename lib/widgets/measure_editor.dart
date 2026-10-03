import 'package:flutter/material.dart';

import '../models/goal.dart';
import '../models/measure.dart';
import 'durations.dart';

/// Edits a goal's measure: a kind picked from [measureKinds] (or none),
/// then that kind's fields. Calls [onChanged] with the measure as it
/// stands after every edit -- null for none -- whether or not it's valid
/// yet; see [measureProblem].
///
/// A time-spent or number-of-events measure looks at the events of its own
/// goal, or of goals chosen from [goals]; with or without their sub-goals,
/// over the last few days. A weighted rollup weighs each of [goalId]'s
/// sub-goals, from [goals].
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
  String _wakeTarget = '07:00';
  String _agg = 'mean';

  /// A weighted rollup's weight for each sub-goal, by id.
  final _weights = <String, TextEditingController>{};

  /// The goal's sub-goals, once [MeasureEditor.goals] has them: a weight
  /// for any other goal, one that's since moved, isn't kept.
  Set<String>? _subGoalIds;

  /// The goals whose events are looked at, in the order chosen; null for
  /// the measure's own goal.
  List<String>? _goalIds;
  bool _subGoals = true;

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
    if (m['goal_ids'] case final List ids) _goalIds = [...ids.cast<String>()];
    if (m['include_sub_goals'] == false) _subGoals = false;
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
      case 'wake_time':
        if (m['target'] case final String target) _wakeTarget = target;
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
  Measure? get _measure {
    Object? number(TextEditingController c) {
      final t = c.text.trim();
      return t.isEmpty ? null : (num.tryParse(t) ?? t);
    }

    String? text(TextEditingController c) {
      final t = c.text.trim();
      return t.isEmpty ? null : t;
    }

    // Which goals' events: left out for the defaults.
    final events = {
      'interval_days': ?number(_interval),
      'zero_at_days': ?number(_zeroAtDays),
      'goal_ids': ?_goalIds,
      if (!_subGoals) 'include_sub_goals': false,
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
      'wake_time' => {
        'kind': 'wake_time',
        'target': _wakeTarget,
        'grace_min': ?number(_grace),
        'zero_at_min': ?number(_zeroAt),
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

  Future<void> _pickWakeTarget() async {
    final [hour, minute] = _wakeTarget.split(':').map(int.parse).toList();
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: hour, minute: minute),
    );
    if (picked == null) return;
    setState(() {
      _wakeTarget =
          '${picked.hour.toString().padLeft(2, '0')}:'
          '${picked.minute.toString().padLeft(2, '0')}';
    });
    _changed();
  }

  /// Whose events a time-spent or number-of-events measure looks at.
  List<Widget> _whoseEvents(ThemeData theme) {
    final chosen = _goalIds;
    return [
      Padding(
        padding: const EdgeInsets.only(top: 12, bottom: 4),
        child: Text('Events of', style: theme.textTheme.labelMedium),
      ),
      SegmentedButton<bool>(
        showSelectedIcon: false,
        segments: const [
          ButtonSegment(value: false, label: Text('This goal')),
          ButtonSegment(value: true, label: Text('Chosen goals')),
        ],
        selected: {chosen != null},
        onSelectionChanged: (picked) {
          setState(() => _goalIds = picked.single ? [] : null);
          _changed();
        },
      ),
      if (chosen != null)
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
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final goal in goals)
                  if (goal.id case final id? when !goal.isOverall)
                    CheckboxListTile(
                      dense: true,
                      contentPadding: EdgeInsetsDirectional.only(
                        start: 16.0 * goal.depth,
                      ),
                      controlAffinity: ListTileControlAffinity.leading,
                      value: chosen.contains(id),
                      title: Text(goalName(goal)),
                      onChanged: (on) {
                        setState(() {
                          chosen.remove(id);
                          if (on == true) chosen.add(id);
                        });
                        _changed();
                      },
                    ),
              ],
            );
          },
        ),
      SwitchListTile(
        dense: true,
        contentPadding: EdgeInsets.zero,
        title: const Text('Include their sub-goals'),
        value: _subGoals,
        onChanged: (on) {
          setState(() => _subGoals = on);
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
      _subGoalIds = {for (final goal in subGoals) goal.id!};
      if (subGoals.isEmpty) return const Text('It has no sub-goals yet.');
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final goal in subGoals)
            _field(
              _weights.putIfAbsent(goal.id!, TextEditingController.new),
              goalName(goal),
              hint: '0',
              number: true,
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
      textCapitalization: number
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
            _field(_noun, "What's counted", hint: 'e.g. visits'),
            ...lookBack,
            ..._whoseEvents(theme),
          ],
          'wake_time' => [
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: ActionChip(
                avatar: const Icon(Icons.alarm),
                label: Text('Up by $_wakeTarget'),
                onPressed: _pickWakeTarget,
              ),
            ),
            _field(_grace, 'Grace, in minutes', hint: '0', number: true),
            _field(
              _zeroAt,
              'Zero at, in minutes late',
              hint: '60',
              number: true,
            ),
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
      ],
    );
  }
}
