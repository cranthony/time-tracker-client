import 'package:flutter/material.dart';

import 'hotkeys.dart';
import '../models/trait.dart';
import '../models/trait_scores.dart' show defaultWindowDays;
import 'duration_field.dart';
import 'edit_page.dart';
import 'scoring_editor.dart';

/// Edits a trait's parts -- each one's kind, settings and whether it
/// reads events with someone or for them -- as cards, with "Add part"
/// below them. A judgment's card edits its rubric, its rating scale and
/// the facts Claude judges it from, each history with its lookback; a
/// spacing part's, its exceptions. Each part keeps its id, which its
/// judgments and weight are kept under; a new one has none until saved.
/// Calls [onChanged] with the parts as they stand after every edit,
/// whether or not they're valid yet; see [partProblem]. [actions] names
/// the actions and groups a part can count, by id; [exceptionActions]
/// (by default those) those a spacing part can set aside.
/// With [preview], each card ends with its part's score as it stands --
/// "[previewLabel]: 88 · 35h of 40h in the last 7 days" -- and, for a
/// part that fades instead of giving partial credit, what partial credit
/// would score.
class PartsEditor extends StatefulWidget {
  const PartsEditor({
    super.key,
    required this.parts,
    required this.onChanged,
    this.actions = const {},
    this.exceptionActions,
    this.preview,
    this.previewLabel = 'Yesterday',
  });

  final List<Part> parts;
  final ValueChanged<List<Part>> onChanged;
  final Map<String, String> actions;
  final Map<String, String>? exceptionActions;
  final PartsPreview? preview;
  final String previewLabel;

  @override
  State<PartsEditor> createState() => _PartsEditorState();
}

/// Scores [parts] as they're being edited, each by its index; null, or
/// null for one, without a score of it.
typedef PartsPreview = List<PartScore?>? Function(List<Part> parts);

/// What a new judgment starts with: a scale of 0 to 3, judged from the
/// event's actions and notes.
const Part newJudgment = {
  'kind': 'judgment',
  'ratings': {'0': '', '1': '', '2': '', '3': ''},
  'facts': ['action', 'general_notes'],
};

class _PartsEditorState extends State<PartsEditor> {
  late final List<_PartDraft> _drafts = [
    for (final part in widget.parts) _PartDraft.from(part),
  ];

  @override
  void dispose() {
    for (final draft in _drafts) {
      draft.dispose();
    }
    super.dispose();
  }

  void _changed() {
    setState(() {});
    widget.onChanged([for (final draft in _drafts) draft.part]);
  }

  /// Each part's preview: its score as it stands and, for one that fades,
  /// what partial credit would score. Null without [PartsEditor.preview].
  List<(PartScore, PartScore?)?>? get _previews {
    final preview = widget.preview;
    if (preview == null) return null;
    final parts = [for (final draft in _drafts) draft.part];
    final scores = preview(parts);
    if (scores == null) return null;
    return [
      for (final (i, part) in parts.indexed)
        switch (scores.elementAtOrNull(i)) {
          final score? when partProblem(part) == null => (
            score,
            part['zero_at_days'] != null && (score.score ?? 100) < 100
                ? preview([
                    ...parts.take(i),
                    {...part}..remove('zero_at_days'),
                    ...parts.skip(i + 1),
                  ])?.elementAtOrNull(i)
                : null,
          ),
          _ => null,
        },
    ];
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final previews = _previews;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final (i, draft) in _drafts.indexed)
          FieldHotkey(
            i < 9 ? '${i + 1}' : null,
            focusOnly: true,
            child: _card(theme, i, draft, previews?.elementAtOrNull(i)),
          ),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: FieldHotkey(
            'A',
            child: TextButton.icon(
              onPressed: () {
                _drafts.add(_PartDraft.from(newJudgment));
                _changed();
              },
              icon: const Icon(Icons.add),
              label: const Text('Add part'),
            ),
          ),
        ),
      ],
    );
  }

  Widget _card(
    ThemeData theme,
    int index,
    _PartDraft draft,
    (PartScore, PartScore?)? preview,
  ) {
    final kind = partKinds[draft.kind];
    return Card(
      margin: const EdgeInsets.only(top: 8),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 4, 4, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: DropdownButton<String>(
                    isExpanded: true,
                    value: kind == null ? null : draft.kind,
                    hint: Text(draft.kind),
                    items: [
                      for (final MapEntry(:key, :value) in partKinds.entries)
                        DropdownMenuItem(value: key, child: Text(value.label)),
                    ],
                    onChanged: (picked) {
                      draft.kind = picked ?? draft.kind;
                      _changed();
                    },
                  ),
                ),
                IconButton(
                  tooltip: 'Remove part ${index + 1}',
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () {
                    _drafts.removeAt(index).dispose();
                    _changed();
                  },
                ),
              ],
            ),
            if (kind != null) Text(kind.hint, style: theme.textTheme.bodySmall),
            Padding(
              padding: const EdgeInsets.only(top: 12, right: 8),
              child: SegmentedButton<String>(
                showSelectedIcon: false,
                segments: [
                  for (final MapEntry(:key, :value) in engagementTypes.entries)
                    ButtonSegment(value: key, label: Text(value)),
                ],
                selected: {draft.engagement},
                onSelectionChanged: (picked) {
                  draft.engagement = picked.single;
                  _changed();
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 4, right: 8),
              child: Text(
                draft.engagement == 'for'
                    ? "Reads the events done for them while they weren't "
                          'there.'
                    : 'Reads the events they were at with you.',
                style: theme.textTheme.bodySmall,
              ),
            ),
            for (final field in kind?.fields ?? const [])
              if (field.field == 'action')
                _actionPicker(draft, required: field.required)
              else if (field.field == 'zero_at_days')
                ..._fadeFields(theme, draft)
              else if (field.field == 'target_min')
                Padding(
                  padding: const EdgeInsets.only(top: 8, right: 8),
                  child: DurationField(
                    controller: draft.controller('target_min'),
                    label: 'Target',
                    onChanged: _changed,
                  ),
                )
              else
                _input(
                  draft.controller(field.field),
                  field.label + (field.required ? '' : ' (optional)'),
                  hint: field.hint,
                  number: !textFields.contains(field.field),
                  maxLines: field.field == 'rubric' ? 4 : 1,
                ),
            if (draft.kind == 'judgment') ...[
              ..._judgmentFields(theme, draft),
              ...judgmentScoringFields(theme, draft.scoring, _changed),
            ],
            if (draft.kind == 'spacing') ..._spacingFields(theme, draft),
            if (preview case (final score, final partial))
              _preview(theme, score, partial),
          ],
        ),
      ),
    );
  }

  /// The action or group a part counts: one of [PartsEditor.actions],
  /// or, unless it's [required], any.
  Widget _actionPicker(_PartDraft draft, {bool required = false}) {
    final current = draft.controller('action').text;
    final known = widget.actions.containsKey(current);
    return Padding(
      padding: const EdgeInsets.only(top: 8, right: 8),
      child: DropdownButtonFormField<String?>(
        initialValue: current.isEmpty ? null : current,
        isExpanded: true,
        decoration: InputDecoration(
          labelText: required
              ? 'Action or group'
              : 'Action or group (optional)',
          isDense: true,
          border: const OutlineInputBorder(),
        ),
        items: [
          if (!required)
            const DropdownMenuItem(value: null, child: Text('Any action')),
          for (final MapEntry(:key, :value) in widget.actions.entries)
            DropdownMenuItem(value: key, child: Text(value)),
          if (current.isNotEmpty && !known)
            DropdownMenuItem(value: current, child: Text(current)),
        ],
        onChanged: (picked) {
          draft.controller('action').text = picked ?? '';
          _changed();
        },
      ),
    );
  }

  /// Whether a count or duration part short of its target gets partial
  /// credit or, with none, fades from when it was last met -- and over
  /// how many days.
  List<Widget> _fadeFields(ThemeData theme, _PartDraft draft) => [
    Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Text(
        'When short of the target',
        style: theme.textTheme.labelLarge,
      ),
    ),
    Padding(
      padding: const EdgeInsets.only(top: 8, right: 8),
      child: SegmentedButton<bool>(
        showSelectedIcon: false,
        segments: const [
          ButtonSegment(value: false, label: Text('Partial credit')),
          ButtonSegment(value: true, label: Text('Fade when missed')),
        ],
        selected: {draft.fades},
        onSelectionChanged: (picked) {
          draft.fades = picked.single;
          if (draft.fades && draft.fade.text.trim().isEmpty) {
            // As long as it looks back, to start with.
            final interval = draft.controller('interval_days').text.trim();
            draft.fade.text = interval.isEmpty
                ? '$defaultWindowDays'
                : interval;
          }
          _changed();
        },
      ),
    ),
    if (draft.fades)
      _input(draft.fade, 'Fades to 0 over, in days', number: true),
    Padding(
      padding: const EdgeInsets.only(top: 4, right: 8),
      child: Text(
        draft.fades
            ? 'No partial credit: 100 while the target is met, then '
                  'falling to 0 over these days after the last time it was.'
            : 'Scores its share of the target: half of it scores 50.',
        style: theme.textTheme.bodySmall,
      ),
    ),
  ];

  /// A part's score as it stands, how it was reached, and what partial
  /// credit would score instead.
  Widget _preview(ThemeData theme, PartScore score, PartScore? partial) =>
      Padding(
        padding: const EdgeInsets.only(top: 12, right: 8),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.visibility_outlined,
                  size: 16,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: '${widget.previewLabel}: ${score.score ?? '–'}',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        TextSpan(text: ' · ${score.said}'),
                        if (partial?.score case final credit?)
                          TextSpan(text: '\nWith partial credit: $credit'),
                      ],
                    ),
                    style: theme.textTheme.bodySmall,
                  ),
                ),
              ],
            ),
          ),
        ),
      );

  /// A judgment's rating scale and facts.
  List<Widget> _judgmentFields(ThemeData theme, _PartDraft draft) => [
    Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Text('Ratings', style: theme.textTheme.labelLarge),
    ),
    for (final (i, rating) in draft.ratings.indexed)
      Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 64,
              child: TextField(
                controller: rating.score,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Score',
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
                onChanged: (_) => _changed(),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: rating.label,
                minLines: 1,
                maxLines: 3,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Means',
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
                onChanged: (_) => _changed(),
              ),
            ),
            IconButton(
              tooltip: 'Remove rating ${rating.score.text}',
              icon: const Icon(Icons.close),
              onPressed: () {
                draft.ratings.removeAt(i).dispose();
                _changed();
              },
            ),
          ],
        ),
      ),
    Align(
      alignment: AlignmentDirectional.centerStart,
      child: TextButton.icon(
        onPressed: () {
          final next = draft.ratings.isEmpty
              ? 0
              : (draft.ratings
                        .map((r) => int.tryParse(r.score.text) ?? 0)
                        .reduce((a, b) => a > b ? a : b) +
                    1);
          draft.ratings.add(_RatingDraft(next, ''));
          _changed();
        },
        icon: const Icon(Icons.add),
        label: const Text('Add rating'),
      ),
    ),
    Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Text('Judged from', style: theme.textTheme.labelLarge),
    ),
    Text(
      'What Claude is shown about each event, for one person or a named '
      'group of them.',
      style: theme.textTheme.bodySmall,
    ),
    for (final MapEntry(:key, :value) in judgmentFacts.entries)
      Row(
        children: [
          Expanded(
            child: CheckboxListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              title: Text(value.label),
              subtitle: Text(value.hint),
              value: draft.facts.containsKey(key),
              onChanged: (on) {
                if (on ?? false) {
                  draft.facts[key] = value.lookback
                      ? TextEditingController(text: '$defaultLookbackDays')
                      : null;
                } else {
                  draft.facts.remove(key)?.dispose();
                }
                _changed();
              },
            ),
          ),
          if (draft.facts[key] case final lookback?)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: SizedBox(
                width: 96,
                child: TextField(
                  controller: lookback,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Lookback',
                    suffixText: 'd',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (_) => _changed(),
                ),
              ),
            ),
        ],
      ),
  ];

  /// A spacing part's exceptions: each the actions whose events stop
  /// its clock, and the time left on it after one.
  List<Widget> _spacingFields(ThemeData theme, _PartDraft draft) {
    final actions = widget.exceptionActions ?? widget.actions;
    return [
      Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Text('Exceptions', style: theme.textTheme.labelLarge),
      ),
      Text(
        "Events that stop the clock -- you don't eat while you sleep -- and, "
        'if you like, the time it has left after one: an hour after waking, '
        'say.',
        style: theme.textTheme.bodySmall,
      ),
      for (final (i, exception) in draft.exceptions.indexed)
        Padding(
          padding: const EdgeInsets.only(top: 8, right: 8),
          child: DecoratedBox(
            decoration: BoxDecoration(
              border: Border.all(color: theme.dividerColor),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 4, 0, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          children: [
                            for (final id in exception.actions)
                              InputChip(
                                label: Text(actions[id] ?? id),
                                onDeleted: () {
                                  exception.actions.remove(id);
                                  _changed();
                                },
                              ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: 'Remove exception ${i + 1}',
                        icon: const Icon(Icons.close),
                        onPressed: () {
                          draft.exceptions.removeAt(i).dispose();
                          _changed();
                        },
                      ),
                    ],
                  ),
                  Padding(
                    padding: const EdgeInsets.only(top: 4, right: 8),
                    child: DropdownButtonFormField<String>(
                      key: ValueKey(exception.actions.join(',')),
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Add an action or group',
                        isDense: true,
                        border: OutlineInputBorder(),
                      ),
                      items: [
                        for (final MapEntry(:key, :value) in actions.entries)
                          if (!exception.actions.contains(key))
                            DropdownMenuItem(value: key, child: Text(value)),
                      ],
                      onChanged: (picked) {
                        if (picked == null) return;
                        exception.actions.add(picked);
                        _changed();
                      },
                    ),
                  ),
                  _input(
                    exception.reset,
                    'Hours left after it (optional)',
                    hint: 'unchanged',
                    number: true,
                  ),
                ],
              ),
            ),
          ),
        ),
      Align(
        alignment: AlignmentDirectional.centerStart,
        child: TextButton.icon(
          onPressed: () {
            draft.exceptions.add(_ExceptionDraft(const [], null));
            _changed();
          },
          icon: const Icon(Icons.add),
          label: const Text('Add exception'),
        ),
      ),
    ];
  }

  Widget _input(
    TextEditingController controller,
    String label, {
    String? hint,
    bool number = false,
    int maxLines = 1,
  }) => Padding(
    padding: const EdgeInsets.only(top: 8, right: 8),
    child: TextField(
      controller: controller,
      minLines: 1,
      maxLines: maxLines,
      keyboardType: number
          ? const TextInputType.numberWithOptions(decimal: true)
          : TextInputType.text,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        isDense: true,
        border: const OutlineInputBorder(),
        floatingLabelBehavior: FloatingLabelBehavior.always,
      ),
      onChanged: (_) => _changed(),
    ),
  );
}

/// One of a judgment's ratings as it's being edited.
class _RatingDraft {
  _RatingDraft(int score, String label)
    : score = TextEditingController(text: '$score'),
      label = TextEditingController(text: label);

  final TextEditingController score;
  final TextEditingController label;

  void dispose() {
    score.dispose();
    label.dispose();
  }
}

/// One of a spacing part's exceptions as it's being edited.
class _ExceptionDraft {
  _ExceptionDraft(List<String> actions, num? resetHours)
    : actions = [...actions],
      reset = TextEditingController(text: resetHours?.toString() ?? '');

  final List<String> actions;
  final TextEditingController reset;

  SpacingException get exception =>
      (actions: actions, resetHours: num.tryParse(reset.text.trim()));

  void dispose() => reset.dispose();
}

/// A part as it's being edited: its kind, its engagement type, and a
/// field for each of its settings, kept across changes of kind; and a
/// judgment's ratings and facts (each history's lookback in a field).
class _PartDraft {
  _PartDraft.from(Part part)
    : kind = '${part['kind']}',
      id = part['id'] as String?,
      _scoring = part['scoring'],
      judgmentKept = {
        for (final key in const ['window_days']) key: ?part[key],
      } {
    for (final MapEntry(:key, :value) in part.entries) {
      if (value == null || value is List || value is Map) continue;
      if (const {'kind', 'engagement_type', 'id', 'weight'}.contains(key)) {
        continue;
      }
      if (key == 'zero_at_days') continue;
      controller(key).text = '$value';
    }
    fades = part['zero_at_days'] != null;
    fade.text = switch (fadeDays(part)) {
      final days? => days == days.roundToDouble() ? '${days.round()}' : '$days',
      null => '${part['zero_at_days'] ?? ''}',
    };
    engagement = part['engagement_type'] as String? ?? 'with';
    // Ready, should it become a judgment.
    final judgment = part['kind'] == 'judgment' ? part : newJudgment;
    ratings.addAll([
      for (final r in judgmentRatings(judgment)) _RatingDraft(r.score, r.label),
    ]);
    for (final MapEntry(:key, :value) in judgmentFactsOf(judgment).entries) {
      facts[key] = value == null ? null : TextEditingController(text: '$value');
    }
    exceptions.addAll([
      for (final e in spacingExceptions(part))
        _ExceptionDraft(e.actions, e.resetHours),
    ]);
  }

  String kind;
  late String engagement;

  /// The server's id for it; null for a new one.
  final String? id;

  /// A judgment's settings this doesn't edit -- how far back it looks --
  /// kept as they were.
  final Map<String, Object?> judgmentKept;

  /// How a judgment's judgments combine.
  late final scoring = JudgmentScoringDraft(_scoring);
  final Object? _scoring;

  /// Whether a count or duration part fades, short of its target, rather
  /// than giving partial credit; and over how many days after its
  /// interval (kept as its `zero_at_days`).
  var fades = false;
  final fade = TextEditingController();
  final ratings = <_RatingDraft>[];

  /// A spacing part's exceptions.
  final exceptions = <_ExceptionDraft>[];

  /// The facts picked, each history with its lookback's field.
  final facts = <String, TextEditingController?>{};
  final _controllers = <String, TextEditingController>{};

  TextEditingController controller(String field) =>
      _controllers.putIfAbsent(field, TextEditingController.new);

  /// The part as its fields have it: its id, and only its kind's fields;
  /// a number that doesn't parse is kept as typed, for [partProblem].
  /// With "with", the default, its engagement type is left out.
  Part get part {
    final fields = {
      for (final f in partKinds[kind]?.fields ?? const []) f.field,
    };
    Object? value(String field) {
      final text = _controllers[field]?.text.trim() ?? '';
      if (text.isEmpty) return null;
      if (textFields.contains(field)) return text;
      return num.tryParse(text) ?? text;
    }

    final scores = [for (final r in ratings) r.score.text.trim()];
    return {
      'id': ?id,
      'kind': kind,
      if (engagement != 'with') 'engagement_type': engagement,
      for (final field in fields) field: ?value(field),
      if (fades && fields.contains('zero_at_days')) 'zero_at_days': _zeroAt,
      if (kind == 'spacing' && exceptions.isNotEmpty)
        'exceptions': [
          for (final e in exceptions)
            {
              'actions': e.actions,
              // One that doesn't parse is kept as typed, for partProblem.
              if (e.reset.text.trim() case final text when text.isNotEmpty)
                'reset_hours': num.tryParse(text) ?? text,
            },
        ],
      if (kind == 'judgment') ...{
        ...judgmentKept,
        'scoring': ?scoring.json,
        // Two sharing a score can't be a map: partProblem says so.
        'ratings': scores.toSet().length == scores.length
            ? {
                for (final r in ratings)
                  r.score.text.trim(): r.label.text.trim(),
              }
            : [for (final r in ratings) r.label.text.trim()],
        'facts': [
          for (final MapEntry(:key, :value) in facts.entries)
            if (value == null)
              key
            else
              {
                'fact': key,
                'lookback_days':
                    int.tryParse(value.text.trim()) ?? value.text.trim(),
              },
        ],
      },
    };
  }

  /// Its `zero_at_days`: its interval and [fade]'s days; one that doesn't
  /// parse is kept as typed, for [partProblem].
  Object get _zeroAt {
    final text = fade.text.trim();
    final days = num.tryParse(text);
    if (days == null) return text;
    final interval = num.tryParse(controller('interval_days').text.trim());
    return (interval ?? defaultWindowDays) + days;
  }

  void dispose() {
    scoring.dispose();
    fade.dispose();
    for (final c in _controllers.values) {
      c.dispose();
    }
    for (final r in ratings) {
      r.dispose();
    }
    for (final c in facts.values) {
      c?.dispose();
    }
    for (final e in exceptions) {
      e.dispose();
    }
  }
}

/// Edits [parts] on a page of its own ([EditPage]) titled [title], with
/// [explanation] above them, refusing to be done while they're empty or
/// a part is wrong. Below them, [warnings] says what's amiss with them
/// that doesn't stop them being saved; with [preview], each part's
/// score shows as it's edited (see [PartsEditor.preview]). Returns the
/// parts, or null if it was called off.
Future<List<Part>?> showPartsEditor(
  BuildContext context, {
  required String title,
  String? explanation,
  required List<Part> parts,
  Map<String, String> actions = const {},
  Map<String, String>? exceptionActions,
  List<String> Function(List<Part> parts)? warnings,
  PartsPreview? preview,
}) => showEditPage<List<Part>>(
  context,
  _PartsPage(
    title: title,
    explanation: explanation,
    parts: parts,
    actions: actions,
    exceptionActions: exceptionActions,
    warnings: warnings,
    preview: preview,
  ),
);

class _PartsPage extends StatefulWidget {
  const _PartsPage({
    required this.title,
    required this.explanation,
    required this.parts,
    required this.actions,
    required this.exceptionActions,
    required this.warnings,
    required this.preview,
  });

  final String title;
  final String? explanation;
  final List<Part> parts;
  final Map<String, String> actions;
  final Map<String, String>? exceptionActions;
  final List<String> Function(List<Part> parts)? warnings;
  final PartsPreview? preview;

  @override
  State<_PartsPage> createState() => _PartsPageState();
}

class _PartsPageState extends State<_PartsPage> {
  late List<Part> _parts = widget.parts;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return EditPage(
      title: widget.title,
      saveLabel: 'Done',
      problem: _parts.isEmpty
          ? 'Give it at least one part.'
          : partsProblem(_parts),
      onSave: () => Navigator.of(context).pop(_parts),
      children: [
        if (widget.explanation case final explanation?)
          Text(explanation, style: theme.textTheme.bodySmall),
        PartsEditor(
          parts: widget.parts,
          actions: widget.actions,
          exceptionActions: widget.exceptionActions,
          preview: widget.preview,
          onChanged: (parts) => setState(() => _parts = parts),
        ),
        for (final warning in widget.warnings?.call(_parts) ?? const [])
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              warning,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.tertiary,
              ),
            ),
          ),
      ],
    );
  }
}
