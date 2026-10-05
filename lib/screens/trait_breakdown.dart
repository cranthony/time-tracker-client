import 'package:flutter/material.dart';

import '../models/facets.dart';
import '../models/trait.dart';
import '../services/mcp_client.dart';
import '../services/traits_repository.dart';

/// Shows [trait]'s daily scores, [days], newest first, each the mean
/// across the people rated by it; tapping a person's score shows the parts
/// and events behind it ([showTraitParts]).
Future<void> showTraitHistory(
  BuildContext context, {
  required Trait trait,
  required List<TraitDay> days,
  required TraitsRepository repository,
  Map<String?, String> personNames = const {},
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  builder: (context) => DraggableScrollableSheet(
    expand: false,
    initialChildSize: 0.6,
    builder: (context, controller) => ListView(
      controller: controller,
      children: [
        ListTile(
          title: Text(
            trait.name,
            style: Theme.of(context).textTheme.titleLarge,
          ),
          subtitle: trait.definition == null ? null : Text(trait.definition!),
        ),
        for (final day in days.reversed)
          ExpansionTile(
            title: Text(day.day),
            trailing: Text('${day.score}'),
            children: [
              for (final MapEntry(key: personId, value: score)
                  in day.people.entries)
                ListTile(
                  dense: true,
                  title: Text(personNames[personId] ?? personId),
                  trailing: Text('$score'),
                  onTap: () async {
                    try {
                      final rating = await repository.explainTraits(
                        personId,
                        day: DateTime.parse(day.day),
                      );
                      final score = rating.traits
                          .where((t) => t.traitId == trait.id)
                          .firstOrNull;
                      if (score != null && context.mounted) {
                        await showTraitParts(
                          context,
                          score,
                          title:
                              '${personNames[personId] ?? personId} · ${day.day}',
                        );
                      }
                    } catch (e) {
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(switch (e) {
                            McpException(:final message) => message,
                            _ => '$e',
                          }),
                        ),
                      );
                    }
                  },
                ),
            ],
          ),
      ],
    ),
  ),
);

/// Shows how [score] was reached: each of its parts' score, weight and how
/// it was reached, and the events behind it -- named from [events] (by id,
/// each as the server sent it, with its facets) where they're there, each
/// with Claude's rating of it for a facet. Each part is titled from
/// [labels], in order, where it has one.
Future<void> showTraitParts(
  BuildContext context,
  TraitScore score, {
  String? title,
  Map<String, Map<String, dynamic>> events = const {},
  Map<String?, String> personNames = const {},
  List<String> labels = const [],
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  builder: (context) {
    final theme = Theme.of(context);
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      builder: (context, controller) => ListView(
        controller: controller,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: [
          Text(
            '${score.name}: ${score.score ?? '–'}',
            style: theme.textTheme.titleLarge,
          ),
          if (title != null) Text(title, style: theme.textTheme.bodySmall),
          const SizedBox(height: 8),
          for (final (i, part) in score.parts.indexed)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            i < labels.length
                                ? labels[i]
                                : partKinds[part.kind]?.label ?? part.key,
                            style: theme.textTheme.titleSmall,
                          ),
                        ),
                        Text(
                          part.score == null ? '–' : '${part.score}',
                          style: theme.textTheme.titleMedium,
                        ),
                      ],
                    ),
                    if (part.weight != 1)
                      Text(
                        'Weight ${part.weight}',
                        style: theme.textTheme.bodySmall,
                      ),
                    Text(part.said),
                    if (part.rubric case final rubric?)
                      Text(
                        rubric,
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    for (final id in part.eventIds)
                      _event(
                        theme,
                        id,
                        events[id],
                        personNames,
                        part.judgments
                            .where((j) => j.eventId == id)
                            .firstOrNull,
                      ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 16),
        ],
      ),
    );
  },
);

Widget _event(
  ThemeData theme,
  String id,
  Map<String, dynamic>? event,
  Map<String?, String> personNames,
  FacetJudgment? judgment,
) {
  final rated = switch (judgment) {
    FacetJudgment(:final rating, :final why) =>
      '\n   Rated $rating${why == null ? '' : ': $why'}',
    null => '',
  };
  if (event == null) {
    return Text('• Event $id$rated', style: theme.textTheme.bodySmall);
  }
  final start = DateTime.tryParse('${event['start']}')?.toLocal();
  final facets = Facets.fromJson(event['facets']);
  final described = facets?.describe(personNames) ?? '';
  return Padding(
    padding: const EdgeInsets.only(top: 4),
    child: Text(
      '• ${start == null ? '' : '${start.year}-${_two(start.month)}-${_two(start.day)} '}'
      '${event['summary'] ?? '(no title)'}'
      '${described.isEmpty ? '' : ' — $described'}$rated',
      style: theme.textTheme.bodySmall,
    ),
  );
}

String _two(int n) => n.toString().padLeft(2, '0');
