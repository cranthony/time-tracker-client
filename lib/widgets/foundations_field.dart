import 'package:flutter/material.dart';

import '../models/habit_graph.dart';
import '../models/person.dart';
import 'plan_pane.dart';

/// What a habit, or a person, can be built on: every habit and person in
/// [graph], and everyone else of [people] not deleted -- but not [id]
/// itself, nor anything built on it, which would make a cycle. Habits
/// first, then people, each by name.
List<GraphNode> foundationChoices(
  HabitGraph graph,
  List<Person> people, {
  String? id,
}) {
  final excluded = {?id, if (id != null) ...graph.builtOn(id)};
  final nodes = {
    ...graph.nodes,
    for (final p in people)
      if (p.status != 'deleted' && !graph.nodes.containsKey(p.id))
        p.id: GraphNode.person(p),
  };
  return [
    for (final n in nodes.values)
      if (!excluded.contains(n.id)) n,
  ]..sort(
    (a, b) => switch ((a.isPerson, b.isPerson)) {
      (false, true) => -1,
      (true, false) => 1,
      _ => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
    },
  );
}

/// Picks what something is built on, from [choices], starting with
/// [selected]; returns the ids picked, in [choices]' order, or null if
/// it was called off.
Future<List<String>?> showFoundationsPicker(
  BuildContext context, {
  required String title,
  required List<GraphNode> choices,
  required List<String> selected,
}) => showDialog<List<String>>(
  context: context,
  builder: (_) =>
      _FoundationsPicker(title: title, choices: choices, selected: selected),
);

class _FoundationsPicker extends StatefulWidget {
  const _FoundationsPicker({
    required this.title,
    required this.choices,
    required this.selected,
  });

  final String title;
  final List<GraphNode> choices;
  final List<String> selected;

  @override
  State<_FoundationsPicker> createState() => _FoundationsPickerState();
}

class _FoundationsPickerState extends State<_FoundationsPicker> {
  late final _picked = {...widget.selected};
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final shown = [
      for (final c in widget.choices)
        if (matchesSearch(_query, [c.name, c.person?.context])) c,
    ];
    return AlertDialog(
      title: Text(widget.title),
      contentPadding: const EdgeInsets.fromLTRB(8, 12, 8, 0),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                decoration: const InputDecoration(
                  hintText: 'Search habits and people',
                  prefixIcon: Icon(Icons.search),
                  isDense: true,
                ),
                onChanged: (query) => setState(() => _query = query),
              ),
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final c in shown)
                    CheckboxListTile(
                      dense: true,
                      secondary: Icon(
                        c.isPerson ? Icons.person_outline : Icons.repeat,
                      ),
                      title: Text(c.name),
                      subtitle: switch (c.person?.context) {
                        final context? => Text(context),
                        null => null,
                      },
                      value: _picked.contains(c.id),
                      onChanged: (on) => setState(
                        () => on ?? false
                            ? _picked.add(c.id)
                            : _picked.remove(c.id),
                      ),
                    ),
                  if (shown.isEmpty) NoMatches(query: _query),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop([
            for (final c in widget.choices)
              if (_picked.contains(c.id)) c.id,
            // Kept, though they can't be picked here: unknown ones.
            for (final id in widget.selected)
              if (!widget.choices.any((c) => c.id == id)) id,
          ]),
          child: const Text('Done'),
        ),
      ],
    );
  }
}

/// What something is built on, as chips by name, with a button to pick
/// them ([showFoundationsPicker]) from [choices].
class FoundationsField extends StatelessWidget {
  const FoundationsField({
    super.key,
    required this.value,
    required this.choices,
    required this.names,
    required this.onChanged,
    this.title = 'Built on',
  });

  final List<String> value;
  final List<GraphNode> choices;

  /// Names what [value] has, by id.
  final Map<String, String> names;
  final ValueChanged<List<String>> onChanged;
  final String title;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: Text(title, style: theme.textTheme.titleSmall)),
            TextButton.icon(
              onPressed: () async {
                final picked = await showFoundationsPicker(
                  context,
                  title: title,
                  choices: choices,
                  selected: value,
                );
                if (picked != null) onChanged(picked);
              },
              icon: const Icon(Icons.edit_outlined),
              label: const Text('Pick'),
            ),
          ],
        ),
        if (value.isEmpty)
          Text(
            'Nothing: it sits at the bottom of the habit graph.',
            style: theme.textTheme.bodySmall,
          )
        else
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final id in value)
                InputChip(
                  label: Text(names[id] ?? id),
                  onDeleted: () => onChanged([...value]..remove(id)),
                ),
            ],
          ),
      ],
    );
  }
}
