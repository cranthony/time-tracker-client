import 'package:flutter/material.dart';

import '../models/habit_graph.dart';
import 'picker_sheet.dart';
import 'tree_picker.dart';

/// What a habit, or a person, can be built on: every habit and person in
/// [graph] -- a person by their habits, but for those on it themselves
/// as before people had habits -- but not [id] itself, nor anything
/// built on it, which would make a cycle. Habits first, then people,
/// each by name.
List<GraphNode> foundationChoices(HabitGraph graph, {String? id}) {
  final excluded = {?id, if (id != null) ...graph.builtOn(id)};
  return [
    for (final n in graph.nodes.values)
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
/// [selected], in a [pickNodes] sheet: habits and people, searched by
/// name and context. Returns the ids picked, in [choices]' order, or null
/// if it was called off.
Future<List<String>?> showFoundationsPicker(
  BuildContext context, {
  required String title,
  required List<GraphNode> choices,
  required List<String> selected,
}) async {
  final byId = {for (final c in choices) c.id: c};
  final picked = await pickNodes(
    context,
    title: title,
    nodes: [
      for (final c in choices)
        PickerNode(id: c.id, label: c.name, detail: c.person?.context),
    ],
    // Unknown ones can't be picked here; they're kept below.
    picked: [
      for (final id in selected)
        if (byId.containsKey(id)) id,
    ],
    searchHint: 'Search habits and people',
    empty: 'No habits or people.',
    marker: (node) => Icon(
      byId[node.id]?.isPerson ?? false ? Icons.person_outline : Icons.repeat,
      size: 20,
    ),
  );
  if (picked == null) return null;
  return [
    for (final c in choices)
      if (picked.contains(c.id)) c.id,
    for (final id in selected)
      if (!byId.containsKey(id)) id,
  ];
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
