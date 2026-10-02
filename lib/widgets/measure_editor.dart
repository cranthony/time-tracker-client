import 'package:flutter/material.dart';

import '../models/measure.dart';
import 'durations.dart';

/// Edits a goal's measure: a kind picked from [measureKinds] (or none),
/// then that kind's fields. Calls [onChanged] with the measure as it
/// stands after every edit -- null for none -- whether or not it's valid
/// yet; see [measureProblem]. [cadence] words the targets ("per week").
class MeasureEditor extends StatefulWidget {
  const MeasureEditor({
    super.key,
    required this.measure,
    required this.cadence,
    required this.onChanged,
  });

  final Measure? measure;
  final String? cadence;
  final ValueChanged<Measure?> onChanged;

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

    return switch (_kind) {
      null => null,
      'duration' => {
        'kind': 'duration',
        'target_min': switch (_target.text.trim()) {
          '' => null,
          final t => parseDuration(t)?.inMinutes ?? t,
        },
      },
      'count' => {
        'kind': 'count',
        'target': number(_target),
        'noun': ?text(_noun),
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
          ],
          'count' => [
            _field(_target, 'Target', number: true, suffix: per),
            _field(_noun, "What's counted", hint: 'e.g. dinners'),
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
