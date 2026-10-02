import 'package:flutter/material.dart';

import '../models/goal.dart';
import '../models/measure.dart';
import 'durations.dart';

/// Edits a goal's measure: a kind picked from [measureKinds] (or none),
/// then that kind's fields. Calls [onChanged] with the measure as it
/// stands after every edit -- null for none -- whether or not it's valid
/// yet; see [measureProblem]. [cadence] words the targets ("per week").
///
/// A time-spent or number-of-events measure looks at the events of its own
/// goal, or of goals chosen from [goals]; with or without their sub-goals.
class MeasureEditor extends StatefulWidget {
  const MeasureEditor({
    super.key,
    required this.measure,
    required this.cadence,
    required this.onChanged,
    this.goals,
  });

  final Measure? measure;
  final String? cadence;
  final ValueChanged<Measure?> onChanged;

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
  String _wakeTarget = '07:00';
  String _agg = 'min';

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
        if (m['agg'] == 'mean') _agg = 'mean';
    }
  }

  @override
  void dispose() {
    for (final c in [_target, _noun, _grace, _zeroAt, _prompt, _rubric]) {
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
      'subjective' => {'kind': 'subjective', 'prompt': ?text(_prompt)},
      'llm' => {'kind': 'llm', 'rubric': text(_rubric)},
      'rollup' => {'kind': 'rollup', 'agg': _agg},
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
                  if (goal.id case final id?)
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
    final per = perPeriod(widget.cadence);
    final kind = _kind;
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
            _field(_target, 'Target', hint: 'e.g. 10h or 1h 30m', suffix: per),
            ..._whoseEvents(theme),
          ],
          'count' => [
            _field(_target, 'Target', number: true, suffix: per),
            _field(_noun, "What's counted", hint: 'e.g. dinners'),
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
          ],
          'llm' => [_field(_rubric, 'Rubric', maxLines: 5)],
          'rollup' => [
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: SegmentedButton<String>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(value: 'min', label: Text('Lowest')),
                  ButtonSegment(value: 'mean', label: Text('Average')),
                ],
                selected: {_agg},
                onSelectionChanged: (picked) {
                  setState(() => _agg = picked.single);
                  _changed();
                },
              ),
            ),
          ],
          _ => const <Widget>[],
        },
      ],
    );
  }
}
