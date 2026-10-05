import 'package:flutter/material.dart';

import '../models/facets.dart';
import '../models/goal.dart';
import 'color_picker.dart';
import 'goals_picker.dart';

/// Edits an event's [facets] -- who it was with and for, its activity and
/// place, the three 0-3 judgments, what was new, and the evidence -- and
/// returns them: empty to remove them, or null if it was called off.
/// [loadGoals] lists the goals to pick who it was with or for; [goals]
/// names those already picked.
Future<Facets?> showFacetsDialog(
  BuildContext context,
  Facets? facets, {
  Map<String, Goal> goals = const {},
  Future<List<Goal>> Function()? loadGoals,
}) => showDialog<Facets>(
  context: context,
  builder: (_) => _FacetsDialog(
    facets: facets ?? const Facets(),
    goals: goals,
    loadGoals: loadGoals,
  ),
);

class _FacetsDialog extends StatefulWidget {
  const _FacetsDialog({
    required this.facets,
    required this.goals,
    required this.loadGoals,
  });

  final Facets facets;
  final Map<String, Goal> goals;
  final Future<List<Goal>> Function()? loadGoals;

  @override
  State<_FacetsDialog> createState() => _FacetsDialogState();
}

/// Who an event's people are, in [_FacetsDialog]: with them, or for them.
enum _Who { withThem, forThem }

class _FacetsDialogState extends State<_FacetsDialog> {
  late var _with = [...widget.facets.withGoalIds];
  late var _for = [...widget.facets.forGoalIds];
  late final _activity = TextEditingController(text: widget.facets.activity);
  late final _place = TextEditingController(text: widget.facets.place);
  late final _why = TextEditingController(text: widget.facets.why);
  late final _scores = {
    'creative': widget.facets.creative,
    'effort': widget.facets.effort,
    'attention': widget.facets.attention,
  };
  late String? _new = widget.facets.newness;

  /// Whose goals are being picked, if any.
  _Who? _picking;
  late final Future<List<Goal>>? _goalList = widget.loadGoals?.call();

  @override
  void dispose() {
    _activity.dispose();
    _place.dispose();
    _why.dispose();
    super.dispose();
  }

  String? _text(TextEditingController c) =>
      c.text.trim().isEmpty ? null : c.text.trim();

  Facets get _facets => Facets(
    withGoalIds: _with,
    forGoalIds: _for,
    // Lower-case, as the server keeps them, so they group.
    activity: _text(_activity)?.toLowerCase(),
    place: _text(_place)?.toLowerCase(),
    creative: _scores['creative'],
    newness: _new,
    effort: _scores['effort'],
    attention: _scores['attention'],
    why: _text(_why),
  );

  String _name(String id) => switch (widget.goals[id]) {
    final goal? => goalName(goal),
    null => id,
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: const Text('What happened'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _people(context, _Who.withThem, 'With', _with),
              _people(
                context,
                _Who.forThem,
                'For, while they weren\'t there',
                _for,
              ),
              _field(_activity, 'Activity', 'e.g. salsa social'),
              _field(_place, 'Place', 'e.g. the hall'),
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: DropdownButtonFormField<String?>(
                  initialValue: _new,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'New to them',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  items: [
                    const DropdownMenuItem(
                      value: null,
                      child: Text('Not said'),
                    ),
                    for (final MapEntry(:key, :value) in newKinds.entries)
                      DropdownMenuItem(value: key, child: Text(value)),
                  ],
                  onChanged: (picked) => setState(() => _new = picked),
                ),
              ),
              for (final MapEntry(key: key, value: (label, hint))
                  in facetScores.entries)
                _score(theme, key, label, hint),
              _field(_why, 'Why', 'One line of evidence', maxLines: 2),
            ],
          ),
        ),
      ),
      actions: [
        if (!widget.facets.isEmpty)
          TextButton(
            onPressed: () => Navigator.of(context).pop(const Facets()),
            child: const Text('Remove all'),
          ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_facets),
          child: const Text('Done'),
        ),
      ],
    );
  }

  /// The goals of the people it was with, or for, as chips; opened to pick
  /// them.
  Widget _people(
    BuildContext context,
    _Who who,
    String label,
    List<String> ids,
  ) {
    final theme = Theme.of(context);
    final picking = _picking == who;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(label, style: theme.textTheme.labelLarge)),
              if (widget.loadGoals != null)
                TextButton(
                  onPressed: () =>
                      setState(() => _picking = picking ? null : who),
                  child: Text(picking ? 'Done' : 'Change'),
                ),
            ],
          ),
          if (!picking)
            ids.isEmpty
                ? Text('No one', style: TextStyle(color: theme.hintColor))
                : Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final id in ids) Chip(label: Text(_name(id))),
                    ],
                  ),
          if (picking)
            FutureBuilder(
              future: _goalList,
              builder: (context, snapshot) => switch (snapshot.data) {
                final goals? => GoalsPicker(
                  goals: goals,
                  picked: ids,
                  autofocus: true,
                  maxListHeight: 240,
                  marker: (goal) => switch (parseColor(
                    goal.effectiveColor ?? goal.backgroundColor,
                  )) {
                    final c? => ColorDot(color: c, size: 12),
                    null => const SizedBox(width: 12),
                  },
                  onChanged: (picked) => setState(() {
                    if (who == _Who.withThem) {
                      _with = picked;
                    } else {
                      _for = picked;
                    }
                  }),
                ),
                null when snapshot.hasError => const Text(
                  "Couldn't load the goals.",
                ),
                null => const LinearProgressIndicator(),
              },
            ),
        ],
      ),
    );
  }

  /// A 0-3 judgment, or not said.
  Widget _score(ThemeData theme, String key, String label, String hint) =>
      Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: theme.textTheme.labelLarge),
            Text(hint, style: theme.textTheme.bodySmall),
            const SizedBox(height: 4),
            SegmentedButton<int?>(
              showSelectedIcon: false,
              segments: [
                const ButtonSegment(value: null, label: Text('–')),
                for (var n = 0; n <= 3; n++)
                  ButtonSegment(value: n, label: Text('$n')),
              ],
              selected: {_scores[key]},
              onSelectionChanged: (picked) =>
                  setState(() => _scores[key] = picked.single),
            ),
          ],
        ),
      );

  Widget _field(
    TextEditingController controller,
    String label,
    String hint, {
    int maxLines = 1,
  }) => Padding(
    padding: const EdgeInsets.only(top: 12),
    child: TextField(
      controller: controller,
      maxLines: maxLines,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        isDense: true,
        border: const OutlineInputBorder(),
        floatingLabelBehavior: FloatingLabelBehavior.always,
      ),
    ),
  );
}
