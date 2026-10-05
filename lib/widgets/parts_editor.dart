import 'package:flutter/material.dart';

import '../models/trait.dart';

/// Edits a trait's parts -- each one's kind, settings and weight -- as
/// cards, with "Add part" below them. A facet's card edits its rubric,
/// its rating scale, whether it rates events with them or for them, and
/// the primitives Claude judges it from, each history with its lookback.
/// Calls [onChanged] with the parts as they stand after every edit,
/// whether or not they're valid yet; see [partProblem]. [actions] names
/// the actions a cadence can count, by id.
class PartsEditor extends StatefulWidget {
  const PartsEditor({
    super.key,
    required this.parts,
    required this.onChanged,
    this.actions = const {},
  });

  final List<Part> parts;
  final ValueChanged<List<Part>> onChanged;
  final Map<String, String> actions;

  @override
  State<PartsEditor> createState() => _PartsEditorState();
}

/// What a new facet starts with: a scale of 0 to 3, judged from the
/// event's actions and notes, with them.
const Part newFacet = {
  'kind': 'facet',
  'engagement': 'with',
  'ratings': [
    {'score': 0, 'label': ''},
    {'score': 1, 'label': ''},
    {'score': 2, 'label': ''},
    {'score': 3, 'label': ''},
  ],
  'primitives': [
    {'name': 'action'},
    {'name': 'general_notes'},
  ],
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final (i, draft) in _drafts.indexed) _card(theme, i, draft),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: TextButton.icon(
            onPressed: () {
              _drafts.add(_PartDraft.from(newFacet));
              _changed();
            },
            icon: const Icon(Icons.add),
            label: const Text('Add part'),
          ),
        ),
      ],
    );
  }

  Widget _card(ThemeData theme, int index, _PartDraft draft) {
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
            _input(
              draft.controller('weight'),
              'Weight',
              hint: '1',
              number: true,
            ),
            for (final field in kind?.fields ?? const [])
              if (field.field == 'action_id')
                _actionPicker(draft)
              else
                _input(
                  draft.controller(field.field),
                  field.label + (field.required ? '' : ' (optional)'),
                  hint: field.hint,
                  number: !textFields.contains(field.field),
                  maxLines: field.field == 'rubric' ? 4 : 1,
                ),
            if (draft.kind == 'facet') ..._facetFields(theme, draft),
          ],
        ),
      ),
    );
  }

  /// A cadence's action: any, or one of [PartsEditor.actions].
  Widget _actionPicker(_PartDraft draft) {
    final current = draft.controller('action_id').text;
    final known = widget.actions.containsKey(current);
    return Padding(
      padding: const EdgeInsets.only(top: 8, right: 8),
      child: DropdownButtonFormField<String?>(
        initialValue: current.isEmpty ? null : current,
        isExpanded: true,
        decoration: const InputDecoration(
          labelText: 'Action (optional)',
          isDense: true,
          border: OutlineInputBorder(),
        ),
        items: [
          const DropdownMenuItem(value: null, child: Text('Any action')),
          for (final MapEntry(:key, :value) in widget.actions.entries)
            DropdownMenuItem(value: key, child: Text(value)),
          if (current.isNotEmpty && !known)
            DropdownMenuItem(value: current, child: Text(current)),
        ],
        onChanged: (picked) {
          draft.controller('action_id').text = picked ?? '';
          _changed();
        },
      ),
    );
  }

  /// A facet's engagement, rating scale and primitives.
  List<Widget> _facetFields(ThemeData theme, _PartDraft draft) => [
    Padding(
      padding: const EdgeInsets.only(top: 12, right: 8),
      child: SegmentedButton<String>(
        showSelectedIcon: false,
        segments: [
          for (final MapEntry(:key, :value) in facetEngagements.entries)
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
            ? 'Rates the events done for them, whether or not they were '
                  'there; their person notes are on you.'
            : 'Rates the events they were at; their person notes are on '
                  'them.',
        style: theme.textTheme.bodySmall,
      ),
    ),
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
      'What Claude reads about each event, for one person or a named group '
      'of them.',
      style: theme.textTheme.bodySmall,
    ),
    for (final MapEntry(:key, :value) in facetPrimitives.entries)
      Row(
        children: [
          Expanded(
            child: CheckboxListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              title: Text(value.label),
              subtitle: Text(value.hint),
              value: draft.primitives.containsKey(key),
              onChanged: (on) {
                if (on ?? false) {
                  draft.primitives[key] = value.lookback
                      ? TextEditingController(text: '$defaultLookbackDays')
                      : null;
                } else {
                  draft.primitives.remove(key)?.dispose();
                }
                _changed();
              },
            ),
          ),
          if (draft.primitives[key] case final lookback?)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: SizedBox(
                width: 96,
                child: TextField(
                  controller: lookback,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: 'Lookback',
                    suffixText: 'd',
                    isDense: true,
                    border: const OutlineInputBorder(),
                    semanticCounterText: '${value.label} lookback, in days',
                  ),
                  onChanged: (_) => _changed(),
                ),
              ),
            ),
        ],
      ),
  ];

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

/// One of a facet's ratings as it's being edited.
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

/// A part as it's being edited: its kind, and a field for each of its
/// settings, kept across changes of kind; and a facet's engagement,
/// ratings and primitives (each history's lookback in a field).
class _PartDraft {
  _PartDraft.from(Part part) : kind = '${part['kind']}' {
    for (final MapEntry(:key, :value) in part.entries) {
      if (value == null || value is List || value is Map) continue;
      if (key == 'kind' || key == 'engagement') continue;
      controller(key).text = '$value';
    }
    engagement = part['engagement'] as String? ?? 'with';
    ratings.addAll([
      for (final r in facetRatings(part)) _RatingDraft(r.score, r.label),
    ]);
    for (final MapEntry(:key, :value) in facetPrimitivesOf(part).entries) {
      primitives[key] = value == null
          ? null
          : TextEditingController(text: '$value');
    }
    if (part['kind'] != 'facet' && ratings.isEmpty) {
      // Ready, should it become a facet.
      engagement = newFacet['engagement'] as String;
      ratings.addAll([
        for (final r in facetRatings(newFacet)) _RatingDraft(r.score, r.label),
      ]);
      for (final name in facetPrimitivesOf(newFacet).keys) {
        primitives[name] = null;
      }
    }
  }

  String kind;
  late String engagement;
  final ratings = <_RatingDraft>[];

  /// The primitives picked, each history with its lookback's field.
  final primitives = <String, TextEditingController?>{};
  final _controllers = <String, TextEditingController>{};

  TextEditingController controller(String field) =>
      _controllers.putIfAbsent(field, TextEditingController.new);

  /// The part as its fields have it: only its kind's, and the weight; a
  /// number that doesn't parse is kept as typed, for [partProblem].
  Part get part {
    final fields = {
      'weight',
      for (final f in partKinds[kind]?.fields ?? const []) f.field,
    };
    Object? value(String field) {
      final text = _controllers[field]?.text.trim() ?? '';
      if (text.isEmpty) return null;
      if (textFields.contains(field)) return text;
      return num.tryParse(text) ?? text;
    }

    return {
      'kind': kind,
      for (final field in fields) field: ?value(field),
      if (kind == 'facet') ...{
        'engagement': engagement,
        'ratings': [
          for (final r in ratings)
            {
              'score': int.tryParse(r.score.text.trim()) ?? r.score.text,
              'label': r.label.text.trim(),
            },
        ],
        'primitives': [
          for (final MapEntry(:key, :value) in primitives.entries)
            {
              'name': key,
              if (value != null)
                'lookback_days':
                    int.tryParse(value.text.trim()) ?? value.text.trim(),
            },
        ],
      },
    };
  }

  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    for (final r in ratings) {
      r.dispose();
    }
    for (final c in primitives.values) {
      c?.dispose();
    }
  }
}
