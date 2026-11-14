import 'package:flutter/material.dart';

import '../models/person.dart';
import '../models/proposal.dart';
import '../models/proposed_stories.dart';
import '../models/trait.dart';
import 'trait_icon.dart';

/// Shows the stories of traits done well that the proposal [current]
/// gives adds once it's confirmed -- each by its trait's icon and name,
/// when, who did it, what they did, why it's the trait, and the event of
/// the proposal it's at. Each can be changed ([onEdit]) or dropped
/// ([onDrop]), and the sheet shows the proposal as it then is.
Future<void> showProposedStoriesSheet(
  BuildContext context, {
  required Proposal Function() current,
  List<Trait> traits = const [],
  PeopleList? people,
  Future<void> Function(ProposedStory story)? onEdit,
  Future<void> Function(ProposedStory story)? onDrop,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  builder: (context) => _StoriesSheet(
    current: current,
    traits: traits,
    people: people,
    onEdit: onEdit,
    onDrop: onDrop,
  ),
);

class _StoriesSheet extends StatefulWidget {
  const _StoriesSheet({
    required this.current,
    required this.traits,
    required this.people,
    required this.onEdit,
    required this.onDrop,
  });

  final Proposal Function() current;
  final List<Trait> traits;
  final PeopleList? people;
  final Future<void> Function(ProposedStory story)? onEdit;
  final Future<void> Function(ProposedStory story)? onDrop;

  @override
  State<_StoriesSheet> createState() => _StoriesSheetState();
}

class _StoriesSheetState extends State<_StoriesSheet> {
  Future<void> _then(
    Future<void> Function(ProposedStory)? act,
    ProposedStory s,
  ) async {
    await act?.call(s);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final proposal = widget.current();
    final traits = {for (final t in widget.traits) t.id: t};
    final stories = proposal.traitExamples;
    final dropped = proposal.settledTraitExamples
        .where((s) => s.use == StoryEditUse.drop)
        .length;
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      builder: (context, controller) => ListView(
        controller: controller,
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        children: [
          Text('Stories it adds', style: theme.textTheme.titleMedium),
          Text(
            'Stories of traits done well, from the notes: made once '
            "it's confirmed, each on its trait's page and at its event. "
            'Change one, or drop it.',
            style: muted,
          ),
          if (stories.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text('None now.', style: muted),
            ),
          for (final story in stories)
            _StoryCard(
              story: story,
              trait: traits[story.example.traitId],
              who: proposedStoryWho(story, widget.people),
              event: switch (proposal.event(story.example.eventId)) {
                final e? => e.summary ?? '(no summary)',
                null => story.example.eventId,
              },
              onEdit: widget.onEdit == null
                  ? null
                  : () => _then(widget.onEdit, story),
              onDrop: widget.onDrop == null
                  ? null
                  : () => _then(widget.onDrop, story),
            ),
          if (dropped > 0)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                '$dropped dropped: not made when it\'s confirmed.',
                style: muted,
              ),
            ),
        ],
      ),
    );
  }
}

/// Who did [story], as it's shown: the person or community it names, by
/// the server's name for them (or [people]'s), and the words it gives.
String proposedStoryWho(ProposedStory story, PeopleList? people) {
  final example = story.example;
  final named = switch (example.personId) {
    null => null,
    selfPersonId => story.personName ?? 'Me',
    final id => story.personName ?? people?.names[id] ?? id,
  };
  return switch ((named, example.who)) {
    (final named?, final who?) => '$named ($who)',
    (final named?, null) => named,
    (null, final who?) => who,
    _ => '',
  };
}

class _StoryCard extends StatelessWidget {
  const _StoryCard({
    required this.story,
    required this.trait,
    required this.who,
    required this.event,
    required this.onEdit,
    required this.onDrop,
  });

  final ProposedStory story;
  final Trait? trait;
  final String who;

  /// The event it's at, named; null for none.
  final String? event;
  final VoidCallback? onEdit;
  final VoidCallback? onDrop;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final example = story.example;
    final name = trait?.name ?? story.traitName ?? example.traitId;
    final day = DateTime.tryParse(example.when);
    return Card.outlined(
      margin: const EdgeInsets.only(top: 12),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 4, 4, 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    switch (trait) {
                      final trait? => traitTitle(
                        trait,
                        style: theme.textTheme.titleSmall,
                      ),
                      null => Text(name, style: theme.textTheme.titleSmall),
                    },
                    const SizedBox(height: 2),
                    Text(
                      [
                        day == null
                            ? example.when
                            : MaterialLocalizations.of(context)
                                  .formatMediumDate(day),
                        who,
                        if (story.decidedBy == DecidedBy.user) 'yours',
                      ].join(' · '),
                      style: muted,
                    ),
                    const SizedBox(height: 4),
                    Text(example.what, style: theme.textTheme.bodyMedium),
                    const SizedBox(height: 4),
                    Text(
                      'Why: ${example.why}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                    if (event case final event?)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Row(
                          children: [
                            Icon(
                              Icons.event,
                              size: 16,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                            const SizedBox(width: 6),
                            Expanded(child: Text('At $event', style: muted)),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
            if (onEdit != null || onDrop != null)
              PopupMenuButton<VoidCallback>(
                tooltip: 'More for this story',
                onSelected: (action) => action(),
                itemBuilder: (_) => [
                  if (onEdit case final edit?)
                    PopupMenuItem(value: edit, child: const Text('Change')),
                  if (onDrop case final drop?)
                    PopupMenuItem(value: drop, child: const Text('Drop')),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
