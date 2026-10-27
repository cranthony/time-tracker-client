import 'package:flutter/material.dart';

import '../models/named.dart';
import '../models/people_times.dart';
import '../models/person.dart';
import '../models/plan_action.dart';
import '../models/scoring.dart';
import '../models/trait.dart';
import '../models/trait_scores.dart';
import '../services/events_repository.dart';
import '../services/people_repository.dart';
import '../services/plan_memory.dart';
import '../services/traits_repository.dart';
import '../widgets/error_sheet.dart';
import '../widgets/fact_prompts_dialog.dart';
import '../widgets/health.dart';
import '../widgets/person_tile.dart';
import '../widgets/relationship_habits.dart';
import 'person_history.dart';
import 'person_screen.dart';
import 'subject_sections.dart';

/// A circle on one page. A plain circle's is its people's, combined: its
/// relationship health -- theirs, combined as it says -- and its trend,
/// its note, and with [times], the time with any of its people in the
/// summary's 24 hours and 7 days and the last (or next) event with any
/// of them. Then its habits, the open goals done with or for it or any
/// of its people, and its people, each with their health, opening their
/// page with [onOpenPerson]. A community's is as a person's: its own
/// relationship health, its traits' scores of the last day that's over,
/// each with what it keeps about it (its facts' summaries, with what
/// compaction changed in each), its history and the timeline of the
/// events naming it, and the events the user cancelled that count
/// against its follow-through ([Circle.cancelledEvents]) -- its people a
/// roster. [traits] names the traits that apply to it; [events] (or else
/// [memory]'s EventStore's repository) can load every event naming it
/// over the last [historyYears] years. It's shown as [memory] has it, as
/// it changes; [onEdit] edits it, and once it's deleted, the page closes.
class CircleScreen extends StatefulWidget {
  const CircleScreen({
    super.key,
    required this.circle,
    required this.memory,
    this.times,
    this.durations = true,
    this.traits,
    this.personNames = const {},
    this.actionNames = const {},
    this.locationNames = const {},
    this.events,
    this.onOpenPerson,
    this.onEdit,
  });

  final Circle circle;
  final PlanMemory memory;
  final PeopleTimes? times;
  final bool durations;

  /// Where the traits are, to name those that apply to a community.
  final TraitsRepository? traits;

  /// Names people and circles by id, for who a community's events were
  /// with and for.
  final Map<String?, String> personNames;

  /// Names actions by id, for what was done at a community's events.
  final Map<String?, String> actionNames;

  /// Names locations by id, for where a community's events were.
  final Map<String?, String> locationNames;

  /// Where all a community's events, over the years, are asked for.
  final EventsRepository? events;

  final void Function(Person person)? onOpenPerson;
  final Future<void> Function(Circle circle)? onEdit;

  @override
  State<CircleScreen> createState() => _CircleScreenState();
}

class _CircleScreenState extends State<CircleScreen> with Rescored {
  @override
  PlanMemory get memory => widget.memory;

  /// Every trait, by id, to name those that apply to a community.
  Map<String, Trait> _traitList = const {};

  /// It, as the app has it now; null once it's deleted.
  Circle? get _circle {
    final people = memory.people;
    if (people == null) return widget.circle;
    return people.circles.where((c) => c.id == widget.circle.id).firstOrNull;
  }

  TraitScores? get _scores => memory.scores;

  @override
  void initState() {
    super.initState();
    _loadTraitList();
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
      widget.events ?? memory.eventStore?.repository;

  /// The actions known, by id, to show an event's by name and color.
  Map<String, PlanAction> get _actions => {
    for (final a in memory.actions?.actions ?? const <PlanAction>[]) ?a.id: a,
  };

  /// The events naming community [id] over the last [historyYears]
  /// years, from [events], as what builds their tiles.
  Future<List<Widget> Function(BuildContext)> _loadAllEvents(
    EventsRepository events,
    String id,
  ) async {
    final history = await loadPersonHistory(events, id);
    final actions = _actions;
    return (context) =>
        personHistoryTiles(context, history, personId: id, actions: actions);
  }

  /// Edits community [circle]'s own prompts for [trait]'s [fact] -- or,
  /// with [reset], lets go of them, to use the trait's -- and saves them
  /// to [people].
  Future<void> _editFactPrompts(
    PeopleRepository people,
    Circle circle,
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
            current: circle.traits.factPrompts(traitId, fact.id),
            whose: 'its',
          );
    if (prompts == null || !mounted) return;
    final traits = circle.traits.withFactPrompts(traitId, fact.id, prompts);
    await runOrShowError(
      context,
      title: "Couldn't save the prompts",
      action: () async {
        await people.updateCircle(circle.id, {
          'traits': traits.isDefault ? null : traits.toJson(),
        });
        await memory.loadPeople(people, again: true);
        if (mounted) setState(() {});
      },
    );
  }

  Future<void> _edit(Circle circle) async {
    await widget.onEdit!(circle);
    if (!mounted) return;
    if (_circle == null) {
      Navigator.of(context).pop();
      return;
    }
    setState(() {});
  }

  /// A community's sections, as a person's: its health, traits, events
  /// and cancellations; null for a plain circle.
  SubjectSections? _sections(BuildContext context, Circle circle) {
    if (!circle.isCommunity) return null;
    final people = PeopleScope.of(context);
    return SubjectSections(
      context,
      memory: memory,
      scored: true,
      subjectId: circle.id,
      name: circleName(circle),
      healthTitle: 'Relationship health',
      scale: HealthScale.relationship,
      traits: circle.traits,
      cancelled: circle.cancelledEvents,
      traitList: _traitList,
      whom: 'it',
      whose: 'its',
      withWhom: 'with it',
      own: 'its own',
      why: 'off, archived, or not its',
      noteOf: circle.id,
      judged: circle,
      factLogs: switch (people) {
        final people? => (traitId) => people.factLogs(
          circle.id,
          traitId: traitId,
        ),
        null => null,
      },
      onFactPrompts: switch (people) {
        final people? => (trait, fact, {reset = false}) => _editFactPrompts(
          people,
          circle,
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
        final events? => () => _loadAllEvents(events, circle.id),
        null => null,
      },
    );
  }

  /// A plain circle's health: its people's ([ids]), combined as it says.
  Widget _combinedHealth(Circle circle, List<String> ids) {
    final health = _scores?.groupHealth(ids, scoring: circle.scoring);
    final trend = _scores?.groupTrend(ids, scoring: circle.scoring);
    return ListTile(
      title: const Text('Relationship health'),
      subtitle: Text(
        [
          switch (health) {
            final h? => HealthScale.relationship.band(h),
            null => 'Not rated yet',
          },
          'Its people combined: '
              '${(circle.scoring ?? memory.scoringDefaults.circles ?? Aggregation.mean).describe()}',
        ].join('\n'),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (trend case final trend? when trend.nonNulls.isNotEmpty) ...[
            TrendSparkline(trend: trend, scale: HealthScale.relationship),
            const SizedBox(width: 8),
          ],
          HealthDot(rating: health, scale: HealthScale.relationship),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final circle = _circle ?? widget.circle;
    final members = memory.people?.inCircle(circle.id) ?? const <Person>[];
    final ids = [for (final p in members) p.id];
    final names = memory.people?.names ?? const <String, String>{};
    final sections = _sections(context, circle);
    final times = widget.times;
    final time = times == null
        ? null
        : [
            ?timeLine(
              times.window,
              times.circleDay(circle.id),
              times.circleWeek(circle.id),
              durations: widget.durations,
            ),
            nearestLine(context, times.window, times.circleNearest(circle.id)),
          ];
    final goals = openGoalTiles(
      context,
      memory,
      // A community's goals are its own; a plain circle's, its people's
      // too.
      sections != null ? {circle.id} : {circle.id, ...ids},
      who: (goal, isFor) =>
          '${isFor ? 'For' : 'With'} '
          '${namedList(isFor ? goal.forWhom : goal.withWhom, (id) => names[id] ?? id)}',
    );
    final habits = [
      sectionHeading(theme, 'Habits'),
      sectionPadded(RelationshipHabits(memory: memory, circle: circle)),
    ];
    return Scaffold(
      appBar: AppBar(
        title: Text(circleName(circle)),
        actions: [
          if (widget.onEdit != null)
            editButton(circleName(circle), () => _edit(circle)),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          if (sections != null)
            ...sections.health()
          else
            _combinedHealth(circle, ids),
          if (circle.note case final note?)
            ListTile(
              dense: true,
              title: const Text('Note'),
              subtitle: Text(note),
            ),
          if (time != null)
            ListTile(
              dense: true,
              title: const Text('Time together'),
              subtitle: Text(time.join('\n')),
            ),
          if (sections != null) ...[
            ...goals,
            ...sections.traitSection(),
            ...habits,
            sectionHeading(theme, 'History'),
            ...historyTiles(
              context,
              _scores,
              circle.id,
              actionNames: widget.actionNames,
              locationNames: widget.locationNames,
            ),
            ...sections.events(),
            ...sections.cancelledSection(),
          ] else ...[
            ...habits,
            ...goals,
          ],
          sectionHeading(
            theme,
            '${members.length} ${members.length == 1 ? 'person' : 'people'}',
          ),
          if (members.isEmpty)
            sectionPadded(
              Text(
                'No one in this ${circle.isCommunity ? 'community' : 'circle'} '
                'yet.',
                style: TextStyle(color: theme.hintColor),
              ),
            ),
          for (final person in members)
            PersonTile(
              person: person,
              health: _scores?.health(person.id),
              trend: _scores?.healthTrend(person.id) ?? const [],
              consistency: _scores?.consistency(person.id) ?? 0,
              times: times,
              durations: widget.durations,
              onTap: switch (widget.onOpenPerson) {
                final open? => () => open(person),
                null => null,
              },
            ),
        ],
      ),
    );
  }
}
