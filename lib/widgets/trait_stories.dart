import 'package:flutter/material.dart';

import '../models/person.dart';
import '../models/text_format.dart';
import '../models/trait.dart';
import '../models/trait_example.dart';
import 'error_sheet.dart';
import 'event_description.dart';
import 'trait_example_dialog.dart';

/// Where a trait's stories come from and go, for [TraitStoriesSection].
class TraitStories {
  const TraitStories({
    required this.load,
    required this.save,
    required this.delete,
    this.people,
    this.eventsOn,
    this.openEvent,
  });

  /// The trait [traitId]'s stories.
  final Future<List<TraitExample>> Function(String traitId) load;

  /// Saves [example]: a new one, or [before] edited. Returns it as saved.
  final Future<TraitExample> Function(
    TraitExample example,
    TraitExample? before,
  )
  save;
  final Future<void> Function(TraitExample example) delete;

  /// Everyone, to pick and name who did it; null if they aren't known.
  final PeopleList? people;

  /// The events on a day, for the event a story happened at.
  final Future<List<StoryEvent>> Function(DateTime day)? eventsOn;

  /// Opens the event a story happened at.
  final Future<void> Function(TraitExample example)? openEvent;
}

/// Who did [example], as it's shown: the person or community in
/// [people] it names, and the words it gives, either or both.
String storyWho(TraitExample example, PeopleList? people) {
  final named = switch (example.personId) {
    null => null,
    selfPersonId => people == null ? 'Me' : personName(people.self),
    final id => people?.names[id] ?? id,
  };
  return switch ((named, example.who)) {
    (final named?, final who?) => '$named ($who)',
    (final named?, null) => named,
    (null, final who?) => who,
    _ => '',
  };
}

/// A story's [text] -- what was done, or why it's the trait -- as plain
/// text on a line, for a summary: its Markdown's marks dropped.
String storyPlainText(String text) =>
    descriptionText(text, format: TextFormat.markdown).replaceAll('\n', ' ');

/// What [example] says was done, then why it's the trait, each in the
/// Markdown it's written in: bold, italics, lists, links.
class StoryText extends StatelessWidget {
  const StoryText(this.example, {super.key});

  final TraitExample example;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      EventDescription(example.what, format: TextFormat.markdown),
      const SizedBox(height: 4),
      EventDescription('*Why:* ${example.why}', format: TextFormat.markdown),
    ],
  );
}

/// [trait]'s stories -- examples of someone embodying it well -- newest
/// first: when, who, what they did, why it's the trait, and the event it
/// happened at, if it was one. Each is edited or deleted from its menu;
/// "Story" adds one.
class TraitStoriesSection extends StatefulWidget {
  const TraitStoriesSection({
    super.key,
    required this.trait,
    required this.stories,
  });

  final Trait trait;
  final TraitStories stories;

  @override
  State<TraitStoriesSection> createState() => _TraitStoriesSectionState();
}

class _TraitStoriesSectionState extends State<TraitStoriesSection> {
  List<TraitExample>? _examples;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final examples = await widget.stories.load(widget.trait.id ?? '');
      if (mounted) {
        setState(() {
          _examples = newestFirst(examples);
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _edit(TraitExample? example) async {
    final saved = await showTraitExampleDialog(
      context,
      trait: widget.trait,
      example: example,
      people: widget.stories.people,
      eventsOn: widget.stories.eventsOn,
      save: (edited) => widget.stories.save(edited, example),
    );
    if (saved != null) await _load();
  }

  Future<void> _delete(TraitExample example) async {
    final sure = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete this story?'),
        content: Text(
          '${storyWho(example, widget.stories.people)}, ${example.when}: '
          '${storyPlainText(example.what)}'
          "\n\nThis can't be undone.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Keep'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (sure != true || !mounted) return;
    await runOrShowError(
      context,
      title: "Couldn't delete the story",
      action: () => widget.stories.delete(example),
    );
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final examples = _examples;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 20, bottom: 6),
          child: Row(
            children: [
              Expanded(
                child: Text('Stories', style: theme.textTheme.titleMedium),
              ),
              TextButton.icon(
                onPressed: () => _edit(null),
                icon: const Icon(Icons.add),
                label: const Text('Story'),
              ),
            ],
          ),
        ),
        if (examples == null && _error != null)
          Text(
            "Couldn't load its stories.",
            style: TextStyle(color: theme.colorScheme.error),
          )
        else if (examples == null)
          const LinearProgressIndicator()
        else if (examples.isEmpty)
          Text(
            'None yet: stories of you or someone else being '
            '${widget.trait.name.toLowerCase()} at their best -- what it '
            'looks like, done well.',
            style: muted,
          ),
        for (final example in examples ?? const <TraitExample>[])
          Card.outlined(
            margin: const EdgeInsets.only(bottom: 8),
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
                          Text(
                            '${_date(context, example.when)} · '
                            '${storyWho(example, widget.stories.people)}',
                            style: muted,
                          ),
                          const SizedBox(height: 4),
                          StoryText(example),
                          if (example.eventId != null &&
                              widget.stories.openEvent != null)
                            Align(
                              alignment: Alignment.centerLeft,
                              child: TextButton.icon(
                                style: TextButton.styleFrom(
                                  padding: EdgeInsets.zero,
                                  visualDensity: VisualDensity.compact,
                                ),
                                onPressed: () =>
                                    widget.stories.openEvent!(example),
                                icon: const Icon(Icons.event, size: 18),
                                label: const Text('The event'),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  PopupMenuButton<bool>(
                    tooltip: 'More for this story',
                    onSelected: (edit) =>
                        edit ? _edit(example) : _delete(example),
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: true, child: Text('Edit')),
                      PopupMenuItem(value: false, child: Text('Delete')),
                    ],
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  static String _date(BuildContext context, String when) =>
      switch (DateTime.tryParse(when)) {
        final day? => MaterialLocalizations.of(context).formatMediumDate(day),
        null => when,
      };
}
