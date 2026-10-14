import 'dart:convert';

import 'package:flutter/material.dart';

import '../models/scoring.dart';
import 'duration_field.dart';
import 'edit_page.dart';

/// What [showAggregationEditor] was closed with: the aggregation picked,
/// or null to go back to what's used without one.
typedef AggregationPicked = ({Aggregation? scoring});

/// Edits an aggregation -- how [items]' scores combine -- on a page of
/// its own titled [title], with [explanation] above: the mean or a
/// percentile, each item's weight (by id, named as [items] has them),
/// only the best or worst few, a cap while any is low, and what an item
/// with nothing to rate it by counts as. [fallback] says what's used
/// without one ("The defaults': mean") -- [fallbackValue], which the page
/// starts from without [value] -- and "Reset to default" goes back to it,
/// as does saving it unchanged; closing the page calls it off.
/// [checkWeights] checks the weights name [items], as a trait's must its
/// parts. Returns what was picked, or null if it was called off.
Future<AggregationPicked?> showAggregationEditor(
  BuildContext context, {
  required String title,
  String? explanation,
  required Aggregation? value,
  Map<String, String> items = const {},
  required String noun,
  required String fallback,
  Aggregation fallbackValue = Aggregation.mean,
  bool checkWeights = false,
}) => showEditPage<AggregationPicked>(
  context,
  _AggregationPage(
    title: title,
    explanation: explanation,
    value: value,
    items: items,
    noun: noun,
    fallback: fallback,
    fallbackValue: fallbackValue,
    checkWeights: checkWeights,
  ),
);

/// A line saying how something's scores combine -- [value], or else
/// [fallback] -- with a button that edits it ([showAggregationEditor]),
/// calling [onChanged] with what's picked.
class AggregationTile extends StatelessWidget {
  const AggregationTile({
    super.key,
    required this.title,
    required this.value,
    required this.onChanged,
    required this.noun,
    required this.fallback,
    this.explanation,
    this.items = const {},
    this.checkWeights = false,
    this.label = 'How they combine',
    this.fallbackValue = Aggregation.mean,
  });

  final String title;
  final Aggregation? value;
  final ValueChanged<Aggregation?> onChanged;
  final String noun;
  final String fallback;
  final String? explanation;
  final Map<String, String> items;
  final bool checkWeights;
  final String label;

  /// What's used without [value], which its page starts from.
  final Aggregation fallbackValue;

  @override
  Widget build(BuildContext context) => ListTile(
    dense: true,
    contentPadding: EdgeInsets.zero,
    title: Text(label),
    subtitle: Text(switch (value) {
      final scoring? => _capitalized(scoring.describe()),
      null => fallback,
    }),
    trailing: IconButton(
      tooltip: 'Edit ${label.toLowerCase()}',
      icon: const Icon(Icons.functions),
      onPressed: () async {
        final picked = await showAggregationEditor(
          context,
          title: title,
          explanation: explanation,
          value: value,
          items: items,
          noun: noun,
          fallback: fallback,
          fallbackValue: fallbackValue,
          checkWeights: checkWeights,
        );
        if (picked != null) onChanged(picked.scoring);
      },
    ),
  );
}

bool _same(Aggregation a, Aggregation b) =>
    jsonEncode(a.toJson()) == jsonEncode(b.toJson());

String _capitalized(String s) =>
    s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';

class _AggregationPage extends StatefulWidget {
  const _AggregationPage({
    required this.title,
    required this.explanation,
    required this.value,
    required this.items,
    required this.noun,
    required this.fallback,
    required this.fallbackValue,
    required this.checkWeights,
  });

  final String title;
  final String? explanation;
  final Aggregation? value;
  final Map<String, String> items;
  final String noun;
  final String fallback;
  final Aggregation fallbackValue;
  final bool checkWeights;

  @override
  State<_AggregationPage> createState() => _AggregationPageState();
}

class _AggregationPageState extends State<_AggregationPage> {
  // What's in effect, without its own.
  late final _value = widget.value ?? widget.fallbackValue;
  late String _statistic = _value.statistic;
  late final _percentile = _field(_value.percentile ?? 50);
  late bool _limited = _value.limit != null;
  late final _limit = _field(_value.limit ?? 1);
  late String _limitBy = _value.limitBy ?? 'worst';
  late final _weights = {
    // Weights for what's gone are kept, as typed, for the check to say so.
    for (final id in {...widget.items.keys, ..._value.weights.keys})
      id: _field(_value.weights[id]),
  };
  late bool _capped = _value.capBelow != null;
  late final _threshold = _field(_value.capBelow?.threshold ?? 40);
  late final _cap = _field(_value.capBelow?.cap ?? 50);
  late bool _counted = _value.missing != null;
  late final _missing = _field(_value.missing ?? 0);

  static TextEditingController _field(num? n) => TextEditingController(
    text: n == null ? '' : (n == n.roundToDouble() ? '${n.round()}' : '$n'),
  );

  @override
  void dispose() {
    for (final c in [
      _percentile,
      _limit,
      _threshold,
      _cap,
      _missing,
      ..._weights.values,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  static Object? _number(TextEditingController c) {
    final text = c.text.trim();
    return num.tryParse(text) ?? text;
  }

  /// As the server keeps it; a number that doesn't parse is kept as
  /// typed, for [aggregationProblem] to say so.
  Map<String, Object?> get _json => {
    if (_statistic == 'percentile') ...{
      'statistic': 'percentile',
      'percentile': _number(_percentile),
    },
    if (_weights.entries.where((e) => e.value.text.trim().isNotEmpty)
        case final given when given.isNotEmpty)
      'weights': {for (final e in given) e.key: _number(e.value)},
    if (_limited) ...{'limit': _number(_limit), 'limit_by': _limitBy},
    if (_capped)
      'cap_below': {'threshold': _number(_threshold), 'cap': _number(_cap)},
    if (_counted) 'missing': _number(_missing),
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final json = _json;
    final problem = aggregationProblem(
      json,
      partIds: widget.checkWeights ? [...widget.items.keys] : null,
    );
    final scoring = Aggregation.fromJson(json)!;
    final noun = widget.noun;
    return EditPage(
      title: widget.title,
      saveLabel: 'Done',
      problem: problem == null ? null : _capitalized(problem),
      // Saved as the default is, it goes on following the default.
      onSave: () => Navigator.of(context).pop<AggregationPicked>((
        scoring: _same(scoring, widget.fallbackValue) ? null : scoring,
      )),
      actions: [
        TextButton(
          onPressed: () =>
              Navigator.of(context).pop<AggregationPicked>((scoring: null)),
          child: const Text('Reset to default'),
        ),
      ],
      children: [
        if (widget.explanation case final explanation?)
          Text(explanation, style: theme.textTheme.bodySmall),
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            'The default: ${widget.fallback.toLowerCase()}. "Reset to '
            'default" goes back to it; closing this page keeps what was '
            'there.',
            style: theme.textTheme.bodySmall,
          ),
        ),
        _heading(theme, 'Combined as'),
        _segments(scoringStatistics, _statistic, (v) => _statistic = v),
        if (_statistic == 'percentile') ...[
          _numberField(_percentile, 'Percentile, 0 to 100'),
          _hint(
            theme,
            'The lowest score with at least that share of the weight at or '
            'below it: 0 is the lowest, 50 the median, 100 the highest.',
          ),
        ],
        SwitchListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          title: Text('Only some $noun count'),
          value: _limited,
          onChanged: (on) => setState(() => _limited = on),
        ),
        if (_limited) ...[
          _segments(aggregationLimitBy, _limitBy, (v) => _limitBy = v),
          _numberField(_limit, 'How many'),
        ],
        if (_weights.isNotEmpty) ...[
          _heading(theme, 'Weights'),
          _hint(
            theme,
            'Each counts once unless you say: 2 counts twice, 0 leaves it '
            'out.',
          ),
          for (final MapEntry(key: id, value: field) in _weights.entries)
            _numberField(field, widget.items[id] ?? '$id (gone)', hint: '1'),
        ],
        SwitchListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          title: const Text('Capped while any is low'),
          value: _capped,
          onChanged: (on) => setState(() => _capped = on),
        ),
        if (_capped)
          Row(
            children: [
              Expanded(child: _numberField(_cap, 'At most')),
              const SizedBox(width: 8),
              Expanded(child: _numberField(_threshold, 'With any under')),
            ],
          ),
        SwitchListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          title: Text('Count $noun with nothing to rate them by'),
          subtitle: const Text('Otherwise, they are left out.'),
          value: _counted,
          onChanged: (on) => setState(() => _counted = on),
        ),
        if (_counted) _numberField(_missing, 'As a score of'),
        if (problem == null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(
              scoring.isMean ? 'The mean' : _capitalized(scoring.describe()),
              style: theme.textTheme.bodyMedium,
            ),
          ),
      ],
    );
  }

  Widget _heading(ThemeData theme, String text) => Padding(
    padding: const EdgeInsets.only(top: 16, bottom: 6),
    child: Text(text, style: theme.textTheme.labelLarge),
  );

  Widget _hint(ThemeData theme, String text) => Padding(
    padding: const EdgeInsets.only(top: 4),
    child: Text(text, style: theme.textTheme.bodySmall),
  );

  Widget _segments(
    Map<String, String> options,
    String selected,
    void Function(String) pick,
  ) => SegmentedButton<String>(
    showSelectedIcon: false,
    segments: [
      for (final MapEntry(:key, :value) in options.entries)
        ButtonSegment(value: key, label: Text(value)),
    ],
    selected: {selected},
    onSelectionChanged: (picked) => setState(() => pick(picked.single)),
  );

  Widget _numberField(TextEditingController c, String label, {String? hint}) =>
      numberField(c, label, hint: hint, onChanged: () => setState(() {}));
}

/// A field for a number, labelled [label].
Widget numberField(
  TextEditingController controller,
  String label, {
  String? hint,
  required VoidCallback onChanged,
}) => Padding(
  padding: const EdgeInsets.only(top: 8),
  child: TextField(
    controller: controller,
    keyboardType: const TextInputType.numberWithOptions(decimal: true),
    decoration: InputDecoration(
      labelText: label,
      hintText: hint,
      isDense: true,
      border: const OutlineInputBorder(),
      floatingLabelBehavior: FloatingLabelBehavior.always,
    ),
    onChanged: (_) => onChanged(),
  ),
);

/// A judgment part's scoring as it's being edited: whether each judgment
/// counts once or for its event's time, the mean or a percentile, and
/// only the best, worst or most recent few events -- or hours, by time.
class JudgmentScoringDraft {
  JudgmentScoringDraft(Object? json) {
    final value = JudgmentScoring.fromJson(json) ?? JudgmentScoring.mean;
    weightBy = value.weightBy;
    statistic = value.statistic;
    percentile.text = '${value.percentile ?? 50}';
    limited = value.limit != null;
    limitBy = value.limitBy ?? 'recent';
    final limit = value.limit ?? 1;
    // Hours are kept as minutes, for the duration field.
    count.text = '${limit.round()}';
    minutes.text = '${(limit * 60).round()}';
  }

  late String weightBy;
  late String statistic;
  final percentile = TextEditingController();
  late bool limited;
  late String limitBy;
  final count = TextEditingController();
  final minutes = TextEditingController();

  bool get byDuration => weightBy == 'duration';

  /// As the part keeps it, or null for the plain mean; a number that
  /// doesn't parse is kept as typed, for [judgmentScoringProblem].
  Map<String, Object?>? get json {
    Object? number(TextEditingController c) =>
        num.tryParse(c.text.trim()) ?? c.text.trim();
    final limit = byDuration
        ? switch (num.tryParse(minutes.text.trim())) {
            final m? => m / 60,
            null => minutes.text.trim(),
          }
        : number(count);
    final out = {
      if (byDuration) 'weight_by': 'duration',
      if (statistic == 'percentile') ...{
        'statistic': 'percentile',
        'percentile': number(percentile),
      },
      if (limited) ...{'limit': limit, 'limit_by': limitBy},
    };
    return out.isEmpty ? null : out;
  }

  void dispose() {
    percentile.dispose();
    count.dispose();
    minutes.dispose();
  }
}

/// The fields of a judgment part's scoring ([draft]), calling [onChanged]
/// after each change.
List<Widget> judgmentScoringFields(
  ThemeData theme,
  JudgmentScoringDraft draft,
  VoidCallback onChanged,
) {
  Widget segments(
    Map<String, String> options,
    String selected,
    void Function(String) pick,
  ) => Padding(
    padding: const EdgeInsets.only(top: 8, right: 8),
    child: SegmentedButton<String>(
      showSelectedIcon: false,
      segments: [
        for (final MapEntry(:key, :value) in options.entries)
          ButtonSegment(value: key, label: Text(value)),
      ],
      selected: {selected},
      onSelectionChanged: (picked) {
        pick(picked.single);
        onChanged();
      },
    ),
  );
  return [
    Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Text('Aggregate judgments by', style: theme.textTheme.labelLarge),
    ),
    segments(judgmentWeightBy, draft.weightBy, (v) => draft.weightBy = v),
    segments(scoringStatistics, draft.statistic, (v) => draft.statistic = v),
    if (draft.statistic == 'percentile')
      Padding(
        padding: const EdgeInsets.only(right: 8),
        child: numberField(
          draft.percentile,
          'Percentile, 0 to 100',
          onChanged: onChanged,
        ),
      ),
    SwitchListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      title: Text(
        draft.byDuration ? 'Only some of their time' : 'Only some events',
      ),
      value: draft.limited,
      onChanged: (on) {
        draft.limited = on;
        onChanged();
      },
    ),
    if (draft.limited) ...[
      segments(judgmentLimitBy, draft.limitBy, (v) => draft.limitBy = v),
      if (draft.byDuration)
        Padding(
          padding: const EdgeInsets.only(top: 8, right: 8),
          child: DurationField(
            // A field of its own for each, as it shows them differently.
            key: const ValueKey('limit-hours'),
            controller: draft.minutes,
            label: 'How long',
            onChanged: onChanged,
          ),
        )
      else
        Padding(
          padding: const EdgeInsets.only(right: 8),
          child: numberField(draft.count, 'How many', onChanged: onChanged),
        ),
    ],
    Padding(
      padding: const EdgeInsets.only(top: 4, right: 8),
      child: Text(switch (JudgmentScoring.fromJson(draft.json)) {
        final scoring? when judgmentScoringProblem(draft.json) == null =>
          'Scores the ${scoring.summary()} of its judgments, each a share '
              'of the top rating.',
        null =>
          'Scores the mean of its judgments, each a share of the top '
              'rating.',
        _ => '',
      }, style: theme.textTheme.bodySmall),
    ),
  ];
}
