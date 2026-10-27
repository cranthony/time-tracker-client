import '../models/attendance.dart';

import 'package:flutter/material.dart';

import '../models/facts.dart';
import '../models/goal.dart';
import '../models/person.dart';
import '../models/plan_action.dart';
import '../models/scoring.dart';
import '../models/trait.dart';
import '../models/trait_scores.dart';
import '../services/events_repository.dart';
import '../services/goals_repository.dart';
import '../services/people_repository.dart';
import '../services/plan_memory.dart';
import '../services/traits_repository.dart';
import '../widgets/durations.dart';
import '../widgets/error_sheet.dart';
import '../widgets/fact_prompts_dialog.dart';
import '../widgets/goal_editor.dart' show deadlineLabel;
import '../widgets/health.dart';
import '../widgets/relationship_habits.dart';
import 'goal_screen.dart';
import 'person_history.dart';
import 'subject_sections.dart';
import 'trait_breakdown.dart';

/// A person -- Self included -- on one page: who they are (their context
/// and circles), and which traits apply to them and their own parts for
/// any. Once [memory] has scored everyone from the events (see
/// [PlanMemory.scores]), also their relationship health, their traits'
/// scores of the last day that's over, each with what it keeps about them
/// (its facts' summaries; tapping one shows them with what compaction
/// changed in each, then the parts, events and Claude's judgments behind
/// it), their history
/// (the actions done and locations of their events, with how often and
/// when), and a timeline of those events with what happened at each.
/// The open goals done with them or for them, each opening its page.
/// Always, the events the user cancelled that count against their
/// follow-through ([Person.cancelledEvents]). The page of all their events
/// can load every event whose facts name them over the last
/// [historyYears] years, asked of [events] (or else [memory]'s EventStore's
/// repository). Self's habits are on the Plan page's Habits pane. [onEdit]
/// edits them, returning them as saved.
class PersonScreen extends StatefulWidget {
  const PersonScreen({
    super.key,
    required this.person,
    this.traits,
    this.memory,
    this.circles = const [],
    this.personNames = const {},
    this.actionNames = const {},
    this.locationNames = const {},
    this.events,
    this.onEdit,
  });

  final Person person;
  final TraitsRepository? traits;

  /// Where everyone's scores are worked out, from the events.
  final PlanMemory? memory;
  final List<Circle> circles;

  /// Names people by id, for who events were with and for.
  final Map<String?, String> personNames;

  /// Names actions by id, for what was done at their events.
  final Map<String?, String> actionNames;

  /// Names locations by id, for where their events were.
  final Map<String?, String> locationNames;

  /// Where all their events, over the years, are asked for.
  final EventsRepository? events;

  final Future<Person?> Function()? onEdit;

  @override
  State<PersonScreen> createState() => _PersonScreenState();
}

class _PersonScreenState extends State<PersonScreen> with Rescored {
  late Person _person = widget.person;

  /// Every trait, by id, to name those that apply to them.
  Map<String, Trait> _traitList = const {};

  /// Everyone's scores, if they're worked out yet.
  TraitScores? get _scores => widget.memory?.scores;
  bool get _scored => widget.memory != null;

  @override
  PlanMemory? get memory => widget.memory;

  @override
  void initState() {
    super.initState();
    _loadTraitList();
  }

  /// The traits again, and the week either side of today's events.
  Future<void> _load() async {
    await Future.wait([
      _loadTraitList(),
      if (widget.memory?.eventStore case final store?)
        store.warm().catchError((Object _) {}),
    ]);
  }

  Future<void> _loadTraitList() async {
    try {
      final traits = await widget.traits?.traits(
        statuses: [...traitStatuses.keys],
      );
      if (!mounted || traits == null) return;
      setState(
        () => _traitList = {
          for (final t in traits)
            if (t.id != null) t.id!: t,
        },
      );
    } catch (_) {
      // Named by id, then.
    }
  }

  EventsRepository? get _events =>
      widget.events ?? widget.memory?.eventStore?.repository;

  /// The actions known, by id, to show an event's by name and color.
  Map<String, PlanAction> get _actions => {
    for (final a in widget.memory?.actions?.actions ?? const <PlanAction>[])
      ?a.id: a,
  };

  /// Their events over the last [historyYears] years, from [events], as
  /// what builds their tiles.
  Future<List<Widget> Function(BuildContext)> _loadAllEvents(
    EventsRepository events,
  ) async {
    final id = _person.id;
    final history = await loadPersonHistory(events, id);
    final actions = _actions;
    return (context) =>
        personHistoryTiles(context, history, personId: id, actions: actions);
  }

  /// Edits their own prompts for [trait]'s [fact] -- or, with [reset],
  /// lets go of them, to use the trait's -- and saves them to [people].
  Future<void> _editFactPrompts(
    PeopleRepository people,
    Trait trait,
    TraitFact fact, {
    bool reset = false,
  }) async {
    final traitId = trait.id;
    if (traitId == null) return;
    final prompts = reset
        ? const FactPromptOverride()
        : await showFactPromptsDialog(
            context,
            trait: trait,
            fact: fact,
            current: _person.traits.factPrompts(traitId, fact.id),
            whose: _person.isSelf ? 'your' : 'their',
          );
    if (prompts == null || !mounted) return;
    final traits = _person.traits.withFactPrompts(traitId, fact.id, prompts);
    await runOrShowError(
      context,
      title: "Couldn't save the prompts",
      action: () async {
        final saved = await people.updatePerson(_person.id, {
          'traits': traits.isDefault ? null : traits.toJson(),
        });
        if (mounted) setState(() => _person = saved);
      },
    );
  }

  Future<void> _edit() async {
    final saved = await widget.onEdit!();
    if (saved == null || !mounted) return;
    setState(() => _person = saved);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final circles = [
      for (final c in widget.circles)
        if (_person.circleIds.contains(c.id)) c,
    ];
    final sections = SubjectSections(
      context,
      memory: widget.memory,
      scored: _scored,
      subjectId: _person.id,
      name: personName(_person),
      healthTitle: 'Relationship health',
      scale: HealthScale.relationship,
      traits: _person.traits,
      cancelled: _person.cancelledEvents,
      traitList: _traitList,
      whom: _person.isSelf ? 'you' : 'them',
      whose: _person.isSelf ? 'your' : 'their',
      withWhom: _person.isSelf ? null : 'with them',
      why: 'off, archived, or not theirs',
      noteOf: _person.id,
      person: _person,
      factLogs: switch (PeopleScope.of(context)) {
        final people? => (traitId) => people.factLogs(
          _person.id,
          traitId: traitId,
        ),
        null => null,
      },
      onFactPrompts: switch (PeopleScope.of(context)) {
        final people? => (trait, fact, {reset = false}) => _editFactPrompts(
          people,
          trait,
          fact,
          reset: reset,
        ),
        null => null,
      },
      actionNames: widget.actionNames,
      personNames: widget.personNames,
      locationNames: widget.locationNames,
      loadAllEvents: switch (_events) {
        final events? => () => _loadAllEvents(events),
        null => null,
      },
    );
    return Scaffold(
      appBar: AppBar(
        title: Text(personName(_person)),
        actions: [
          if (widget.onEdit != null) editButton(personName(_person), _edit),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.symmetric(vertical: 8),
          children: [
            ...sections.health(),
            if (_person.context case final context?)
              ListTile(
                dense: true,
                title: const Text('Context'),
                subtitle: Text(context),
              ),
            if (circles.isNotEmpty)
              ListTile(
                dense: true,
                title: const Text('Circles'),
                subtitle: Text(circles.map((c) => c.name).join(', ')),
              ),
            ..._goals(theme),
            ...sections.traitSection(),
            if (widget.memory case final memory?) ...[
              sectionHeading(theme, 'Habits'),
              sectionPadded(
                RelationshipHabits(memory: memory, person: _person),
              ),
            ],
            if (_scored) ...[
              sectionHeading(theme, 'History'),
              ..._history(theme),
            ],
            ...sections.events(),
            ...sections.cancelledSection(),
          ],
        ),
      ),
    );
  }

  /// The open goals done with them or for them, soonest due first --
  /// nothing, without any.
  List<Widget> _goals(ThemeData theme) {
    final them = _person.isSelf ? 'you' : 'them';
    return openGoalTiles(context, widget.memory, {
      _person.id,
    }, who: (_, isFor) => isFor ? 'For $them' : 'With $them');
  }

  List<Widget> _history(ThemeData theme) {
    final digest = _scores?.digest(_person.id);
    if (digest == null) return [sectionPadded(const LinearProgressIndicator())];
    String entries(List<DigestEntry> list) => list.isEmpty
        ? 'None recorded'
        : [
            for (final e in list)
              '${widget.actionNames[e.label] ?? widget.locationNames[e.label] ?? e.label} ×${e.count} '
                  '(${e.first == e.last ? e.first : '${e.first} – ${e.last}'})',
          ].join('\n');
    return [
      sectionPadded(
        Text(
          '${digest.eventsCounted} events in the last ${digest.windowDays} '
          'days.',
          style: theme.textTheme.bodySmall,
        ),
      ),
      ListTile(
        dense: true,
        title: const Text('Actions'),
        subtitle: Text(entries(digest.actions)),
      ),
      ListTile(
        dense: true,
        title: const Text('Locations'),
        subtitle: Text(entries(digest.locations)),
      ),
    ];
  }
}

/// The open goals done with or for any of [ids] -- named themself, or by
/// a plain circle they're in ([Attendance]) -- soonest due first, under a
/// heading -- nothing, without any: each saying [who] of them it's for
/// ([isFor]) or done with, when it's due, and whether it's inactive, and
/// opening its page.
List<Widget> openGoalTiles(
  BuildContext context,
  PlanMemory? memory,
  Set<String> ids, {
  required String Function(Goal goal, bool isFor) who,
}) {
  final attendance = Attendance(circles: memory?.people?.circles ?? const []);
  bool any(List<Named> named) =>
      ids.any((id) => attendance.includes(named, id));
  final goals = [
    for (final g in memory?.goals ?? const <Goal>[])
      if (g.open && (any(g.withWhom) || any(g.forWhom))) g,
  ]..sort(compareByDeadline);
  if (goals.isEmpty) return const [];
  final repository = GoalsScope.of(context);
  return [
    sectionHeading(Theme.of(context), 'Goals'),
    for (final g in goals)
      if (any(g.forWhom) case final isFor)
        ListTile(
          dense: true,
          leading: Icon(isFor ? Icons.card_giftcard : Icons.group_outlined),
          title: Text(goalTitle(g)),
          subtitle: Text(
            [
              who(g, isFor),
              if (g.deadline != null)
                'Due ${deadlineLabel(context, g.deadline)}',
              if (g.inactive) 'Inactive',
            ].join(' · '),
          ),
          onTap: repository == null || memory == null
              ? null
              : () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => GoalScreen(
                      goalId: g.id,
                      repository: repository,
                      memory: memory,
                    ),
                  ),
                ),
        ),
  ];
}

/// How the traits combine -- [traits.scoring], or else [defaults] --
/// then which apply: [traits.select], every active one by default, named
/// from [traitList], and [own] parts for any: a person's, or a habit's.
/// [actionNames] names the actions a part counts.
List<Widget> traitsApplied(
  ThemeData theme,
  PersonTraits traits, {
  required Map<String, Trait> traitList,
  required Map<String?, String> actionNames,
  Aggregation? defaults,
  String own = 'their own',
}) {
  String name(String id) => traitList[id]?.name ?? id;
  return [
    Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Text(switch (traits.scoring) {
        final scoring? => 'Combined: ${scoring.describe()}',
        null =>
          "Combined: ${(defaults ?? Aggregation.mean).describe()}, the "
              "defaults'",
      }, style: theme.textTheme.bodySmall),
    ),
    Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Text(switch (traits.select) {
        null => 'Every active trait',
        final ids when ids.isEmpty => 'None',
        final ids => ids.map(name).join(', '),
      }, style: theme.textTheme.bodyMedium),
    ),
    for (final MapEntry(:key, :value) in traits.parts.entries)
      ListTile(
        dense: true,
        title: Text('${name(key)}, $own'),
        subtitle: Text(
          [for (final part in value) describePart(part, actionNames)]
              .join('\n'),
        ),
      ),
  ];
}

/// The events the user [cancelled] that count against [whose]
/// follow-through ("your", "their", "its"), newest first: when each was
/// planned, what was to be done, whether it was for [whom] or [withWhom],
/// and when and how it was cancelled, with the traits (from [traitList])
/// it counted against.
List<Widget> cancelledTiles(
  BuildContext context,
  List<CancelledEvent> cancelled, {
  required String whose,
  required String whom,
  String? withWhom,
  required Map<String, Trait> traitList,
  required Map<String?, String> actionNames,
}) {
  final theme = Theme.of(context);
  if (cancelled.isEmpty) {
    return [
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        child: Text(
          'Nothing cancelled that counts against $whose follow-through.',
          style: TextStyle(color: theme.hintColor),
        ),
      ),
    ];
  }
  return [
    for (final c in cancelled)
      cancelledTile(
        context,
        c,
        whom: whom,
        withWhom: withWhom,
        traitList: traitList,
        actionNames: actionNames,
      ),
  ];
}

/// One event the user cancelled, [c]: when it was planned, what was to
/// be done, whether it was for [whom] or [withWhom], and when and how it
/// was cancelled, with the traits (from [traitList]) it counted against.
Widget cancelledTile(
  BuildContext context,
  CancelledEvent c, {
  required String whom,
  String? withWhom,
  required Map<String, Trait> traitList,
  required Map<String?, String> actionNames,
}) {
  final theme = Theme.of(context);
  final localizations = MaterialLocalizations.of(context);
  String at(DateTime t) =>
      '${localizations.formatMediumDate(t)}, '
      '${localizations.formatTimeOfDay(TimeOfDay.fromDateTime(t))}';
  return ListTile(
    dense: true,
    leading: Icon(Icons.event_busy, color: theme.colorScheme.error),
    title: Text(c.summary ?? '(no title)'),
    subtitle: Text(
      [
        [
          'Planned for ${at(c.start)}',
          if (c.engagement == 'for') 'for $whom' else ?withWhom,
        ].join(', '),
        if (c.actionIds.isNotEmpty)
          [for (final id in c.actionIds) actionNames[id] ?? id].join(', '),
        [
          switch (c.cancelledAt) {
            final day? => 'Cancelled ${localizations.formatMediumDate(day)}',
            null => 'Cancelled',
          },
          if (c.byCompaction)
            "— it didn't happen"
          else if (c.source == 'delete_event')
            '— deleted',
        ].join(' '),
        if (c.traitIds.isNotEmpty)
          'Counts against '
              '${c.traitIds.map((id) => traitList[id]?.name ?? id).join(', ')}',
      ].join('\n'),
    ),
  );
}

/// The events the user [cancelled] that count against [whose]
/// follow-through, in brief: how many, the time they'd have taken, and
/// the most recent and the oldest (as [cancelledTile]s), with [onAll] --
/// "All cancelled events" -- to see the lot.
List<Widget> cancelledSummary(
  BuildContext context,
  List<CancelledEvent> cancelled, {
  required String whose,
  required String whom,
  String? withWhom,
  required Map<String, Trait> traitList,
  required Map<String?, String> actionNames,
  required VoidCallback onAll,
}) {
  if (cancelled.isEmpty) {
    return cancelledTiles(
      context,
      cancelled,
      whose: whose,
      whom: whom,
      traitList: traitList,
      actionNames: actionNames,
    );
  }
  final byStart = [...cancelled]..sort((a, b) => a.start.compareTo(b.start));
  final time = byStart.fold(
    Duration.zero,
    (sum, c) => c.end.isAfter(c.start) ? sum + c.end.difference(c.start) : sum,
  );
  Widget tile(CancelledEvent c) => cancelledTile(
    context,
    c,
    whom: whom,
    withWhom: withWhom,
    traitList: traitList,
    actionNames: actionNames,
  );
  return _summary(
    context,
    count: byStart.length,
    line: '${byStart.length} cancelled · ${formatDuration(time)} planned',
    latest: tile(byStart.last),
    oldest: tile(byStart.first),
    allLabel: 'All cancelled events',
    allIcon: Icons.event_busy_outlined,
    onAll: onAll,
  );
}

/// [line] -- how many there were, and their time -- then the [latest]
/// and the [oldest] of them, or just one if there's [count] one, and a
/// button, [allLabel], to see them all.
List<Widget> _summary(
  BuildContext context, {
  required int count,
  required String line,
  required Widget latest,
  required Widget oldest,
  required String allLabel,
  required IconData allIcon,
  required VoidCallback onAll,
}) {
  final theme = Theme.of(context);
  Widget label(String text) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
    child: Text(
      text,
      style: theme.textTheme.labelMedium?.copyWith(color: theme.hintColor),
    ),
  );
  return [
    Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Text(line, style: theme.textTheme.bodyMedium),
    ),
    if (count == 1) ...[
      label('The only one'),
      latest,
    ] else ...[
      label('Most recent'),
      latest,
      label('Oldest'),
      oldest,
    ],
    Align(
      alignment: AlignmentDirectional.centerStart,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: TextButton.icon(
          onPressed: onAll,
          icon: Icon(allIcon),
          label: Text(allLabel),
        ),
      ),
    ),
  ];
}

/// [subjectId]'s scores of the last day from [scores] -- a person's, or a
/// habit's: its rating, then each trait's score and its parts', with the
/// trait's trend over the days scored if [trends], tapping one showing
/// how it was reached ([showTraitParts]); and the traits not rated.
/// [whom] says who they are, "them" or "it"; [why], why a trait
/// isn't rated for them.
List<Widget> traitScoreTiles(
  BuildContext context,
  TraitScores? scores,
  String subjectId, {
  required String whom,
  required String why,
  bool trends = false,
  HealthScale scale = HealthScale.relationship,
  Map<String?, String> personNames = const {},
  Map<String?, String> locationNames = const {},
  Person? person,
  Map<String, Trait> traitList = const {},
  Future<List<FactLog>> Function(String traitId)? factLogs,
  Future<void> Function(Trait trait, TraitFact fact, {bool reset})?
  onFactPrompts,
}) {
  final theme = Theme.of(context);
  // A person's summary of each of a trait's facts, null for none yet.
  List<(TraitFact, String?)> factsOf(String traitId) => [
    if (person != null)
      for (final fact in traitList[traitId]?.facts ?? const <TraitFact>[])
        (fact, person.summary(traitId, fact.id)),
  ];
  Widget padded(Widget child) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
    child: child,
  );
  if (scores == null) return [padded(const LinearProgressIndicator())];
  final rating = scores.rating(subjectId);
  if (rating == null || rating.traits.isEmpty) {
    return [
      padded(
        Text(
          'Not rated: no active trait applies to $whom.',
          style: TextStyle(color: theme.hintColor),
        ),
      ),
    ];
  }
  String label(PartScore part) =>
      part.rubric ?? partKinds[part.kind]?.label ?? part.key;
  List<int?> trend(String traitId) => [
    for (final day in scores.days)
      scores
          .rating(subjectId, day)
          ?.traits
          .where((t) => t.traitId == traitId)
          .firstOrNull
          ?.score,
  ];
  return [
    padded(
      Text(
        '${rating.rating ?? 'Skipped'}'
        '${rating.day == null ? '' : ' · ${rating.day}'}',
        style: theme.textTheme.headlineSmall,
      ),
    ),
    for (final score in rating.traits) ...[
      ListTile(
        title: Text(
          score.weight == 1 ? score.name : '${score.name} ×${score.weight}',
        ),
        subtitle: Text(
          [
            for (final part in score.parts)
              '${label(part)} ${part.score ?? '–'}',
          ].join(' · '),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (trends)
              if (trend(score.traitId) case final days
                  when days.nonNulls.length > 1) ...[
                TrendSparkline(trend: days, scale: scale),
                const SizedBox(width: 8),
              ],
            Text(
              score.score == null ? '–' : '${score.score}',
              style: theme.textTheme.titleMedium,
            ),
          ],
        ),
        onTap: () => showTraitParts(
          context,
          score,
          labels: [for (final part in score.parts) label(part)],
          title: rating.day,
          events: scores.eventsBehind(score),
          personNames: personNames,
          locationNames: locationNames,
          facts: factsOf(score.traitId),
          factLogs: switch (factLogs) {
            final logs? => () => logs(score.traitId),
            null => null,
          },
        ),
      ),
      // Under it, what it keeps about them, and by whose prompts.
      for (final (fact, summary) in factsOf(score.traitId))
        Padding(
          padding: EdgeInsets.fromLTRB(
            32,
            0,
            onFactPrompts == null ? 16 : 4,
            8,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      person?.traits.factPrompts(score.traitId, fact.id) == null
                          ? fact.name
                          : '${fact.name} · ${whom == 'you' ? 'your' : 'their'} own prompts',
                      style: theme.textTheme.labelLarge,
                    ),
                    Text(
                      summary ?? 'Nothing yet.',
                      style: summary == null
                          ? theme.textTheme.bodySmall?.copyWith(
                              color: theme.hintColor,
                            )
                          : theme.textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              if ((onFactPrompts, traitList[score.traitId]) case (
                final edit?,
                final trait?,
              )) ...[
                IconButton(
                  tooltip: whom == 'you'
                      ? 'Your own prompts'
                      : 'Their own prompts',
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.tune),
                  onPressed: () => edit(trait, fact),
                ),
                if (person?.traits.factPrompts(score.traitId, fact.id) != null)
                  IconButton(
                    tooltip: "Use ${trait.name}'s prompts",
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.undo),
                    onPressed: () => edit(trait, fact, reset: true),
                  ),
              ],
            ],
          ),
        ),
    ],
    if (rating.leftOut.isNotEmpty)
      padded(
        Text(
          'Not rated: ${rating.leftOut.join(', ')} ($why).',
          style: theme.textTheme.bodySmall,
        ),
      ),
  ];
}

/// The events in [digest], latest first: each one's title, when, what
/// was done, and who and where, with its note on [noteOf].
List<Widget> eventTiles(
  BuildContext context,
  PersonDigest? digest, {
  String? noteOf,
  Map<String?, String> actionNames = const {},
  Map<String?, String> personNames = const {},
  Map<String?, String> locationNames = const {},
}) {
  Widget padded(Widget child) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
    child: child,
  );
  if (digest == null) return [padded(const LinearProgressIndicator())];
  if (digest.events.isEmpty) {
    return [padded(const Text('No events in this window.'))];
  }
  return [
    for (final event in digest.events.reversed)
      eventTile(
        context,
        event,
        noteOf: noteOf,
        actionNames: actionNames,
        personNames: personNames,
        locationNames: locationNames,
      ),
  ];
}

/// The events in [digest] in brief: how many in its window and their
/// time, and the most recent and the oldest (as [eventTile]s), with
/// [onAll] -- "All events" -- to see the lot ([eventTiles]).
List<Widget> eventsSummary(
  BuildContext context,
  PersonDigest? digest, {
  String? noteOf,
  Map<String?, String> actionNames = const {},
  Map<String?, String> personNames = const {},
  Map<String?, String> locationNames = const {},
  required VoidCallback onAll,
}) {
  if (digest == null || digest.events.isEmpty) {
    return eventTiles(context, digest);
  }
  final events = digest.events;
  final time = events.fold(Duration.zero, (sum, e) {
    final start = DateTime.tryParse('${e['start']}');
    final end = DateTime.tryParse('${e['end']}');
    if (start == null || end == null || !end.isAfter(start)) return sum;
    return sum + end.difference(start);
  });
  Widget tile(Map<String, dynamic> event) => eventTile(
    context,
    event,
    noteOf: noteOf,
    actionNames: actionNames,
    personNames: personNames,
    locationNames: locationNames,
  );
  return _summary(
    context,
    count: events.length,
    line:
        '${events.length} ${events.length == 1 ? 'event' : 'events'} in '
        'the last ${digest.windowDays} days · ${formatDuration(time)}',
    latest: tile(events.last),
    oldest: tile(events.first),
    allLabel: 'All events',
    allIcon: Icons.event_note_outlined,
    onAll: onAll,
  );
}

/// One event, as the server sent it: its title, when, what was done,
/// and who and where, with its note on [noteOf].
Widget eventTile(
  BuildContext context,
  Map<String, dynamic> event, {
  String? noteOf,
  Map<String?, String> actionNames = const {},
  Map<String?, String> personNames = const {},
  Map<String?, String> locationNames = const {},
}) {
  final localizations = MaterialLocalizations.of(context);
  String when(Map<String, dynamic> event) {
    final start = DateTime.tryParse('${event['start']}')?.toLocal();
    if (start == null) return '';
    return '${localizations.formatMediumDate(start)}, '
        '${localizations.formatTimeOfDay(TimeOfDay.fromDateTime(start))}';
  }

  return ListTile(
    dense: true,
    title: Text('${event['summary'] ?? '(no title)'}'),
    subtitle: Text(
      [
        when(event),
        if ((event['action_ids'] as List?)?.isNotEmpty ?? false)
          [
            for (final share
                in (event['action_ids'] as List)
                    .map(ActionShare.fromJson)
                    .nonNulls)
              actionNames[share.actionId] ?? share.actionId,
          ].join(', '),
        if (Facts.fromJson(event['facts']) case final facts?
            when !facts.isEmpty) ...[
          facts.describe(personNames, locationNames),
          if (facts.notes[noteOf] case final note?) '“$note”',
        ],
      ].where((line) => line.isNotEmpty).join('\n'),
    ),
  );
}
