import 'package:flutter/material.dart';

import '../models/facts.dart';
import '../models/habit.dart';
import '../models/person.dart';
import '../models/plan_action.dart';
import '../models/trait.dart';
import '../models/trait_scores.dart';
import '../services/habits_repository.dart';
import '../services/plan_memory.dart';
import '../services/traits_repository.dart';
import '../widgets/durations.dart';
import '../widgets/focus_buttons.dart';
import '../widgets/habit_dialog.dart';
import '../widgets/health.dart';
import 'event_list_screen.dart';
import 'habit_screen.dart';
import 'trait_breakdown.dart';

/// A person -- Self included -- on one page: who they are (their context
/// and circles), which traits apply to them and their own parts for any,
/// and what matters to them. Once [memory] has scored everyone from the
/// events (see [PlanMemory.scores]), also their relationship health,
/// their traits' scores of the last day that's over (tapping one shows
/// the parts, events and Claude's judgments behind it), their history
/// (the actions done and locations of their events, with how often and
/// when), and a timeline of those events with what happened at each.
/// Always, the events the user cancelled that count against their
/// follow-through ([Person.cancelledEvents]). For Self, their [habits]
/// too, each in its action's color: tapping one opens its page
/// ([HabitScreen]), its star focuses on it in the People pane, and
/// "Habit" adds one. Habits are best effort: if
/// they can't be loaded, there's no section for them.
/// [onEdit] edits them, returning them as saved.
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
    this.habits,
    this.actions = const [],
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

  /// Self's habits, if they're offered.
  final HabitsRepository? habits;

  /// Every action and group, for a habit's.
  final List<PlanAction> actions;
  final Future<Person?> Function()? onEdit;

  @override
  State<PersonScreen> createState() => _PersonScreenState();
}

class _PersonScreenState extends State<PersonScreen> {
  late Person _person = widget.person;

  /// Every trait, by id, to name those that apply to them.
  Map<String, Trait> _traitList = const {};

  /// Everyone's scores, if they're worked out yet.
  TraitScores? get _scores => widget.memory?.scores;
  bool get _scored => widget.memory != null;

  /// Self's habits, loaded here when there's no [PersonScreen.memory] to
  /// keep them.
  List<Habit>? _ownHabits;

  /// Self's habits, but those deleted; null if they couldn't be loaded,
  /// or aren't theirs to have.
  List<Habit>? get _habits => !_person.isSelf || widget.habits == null
      ? null
      : switch (widget.memory?.habits ?? _ownHabits) {
          final habits? => [
            for (final h in habits)
              if (h.status != 'deleted') h,
          ],
          null => null,
        };

  @override
  void initState() {
    super.initState();
    widget.memory?.addListener(_rescored);
    _loadTraitList();
    _loadHabits();
  }

  @override
  void dispose() {
    widget.memory?.removeListener(_rescored);
    super.dispose();
  }

  /// Shows the scores again, as they're worked out again.
  void _rescored() {
    if (mounted) setState(() {});
  }

  /// The traits again, and the week either side of today's events.
  Future<void> _load() async {
    await Future.wait([
      _loadTraitList(),
      _loadHabits(again: true),
      if (widget.memory?.eventStore case final store?)
        store.warm().catchError((Object _) {}),
    ]);
  }

  /// Self's habits, if they're offered. Best effort.
  Future<void> _loadHabits({bool again = false}) async {
    final repository = widget.habits;
    if (!_person.isSelf || repository == null) return;
    if (widget.memory case final memory?) {
      await memory.loadHabits(repository, again: again);
      return;
    }
    try {
      final habits = await repository.habits();
      if (mounted) setState(() => _ownHabits = habits);
    } catch (_) {
      // No habits section, then.
    }
  }

  /// Adds a habit (with no [habit]) or edits one; returns it as saved.
  Future<Habit?> _editHabit(Habit? habit) async {
    final repository = widget.habits!;
    final saved = await showHabitEditor(
      context,
      habit: habit,
      focus: widget.memory?.focus,
      actions: widget.actions,
      traits: [..._traitList.values],
      save: (fields) => habit == null
          ? repository.createHabit(
              Habit.fromJson({'id': '', 'action_id': '', ...fields}),
            )
          : repository.updateHabit(habit.id, fields),
    );
    if (saved != null) await _loadHabits(again: true);
    return saved;
  }

  void _openHabit(Habit habit) => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => HabitScreen(
        habit: habit,
        actions: widget.actions,
        traits: _traitList,
        memory: widget.memory,
        personNames: widget.personNames,
        locationNames: widget.locationNames,
        onEdit: _editHabit,
      ),
    ),
  );

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
    return Scaffold(
      appBar: AppBar(
        title: Text(personName(_person)),
        actions: [
          if (widget.memory?.focus case final focus? when !_person.isSelf)
            prioritizeButton(focus, _person),
          if (widget.onEdit != null)
            IconButton(
              tooltip: 'Edit ${personName(_person)}',
              icon: const Icon(Icons.edit_outlined),
              onPressed: _edit,
            ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.symmetric(vertical: 8),
          children: [
            if (_scored)
              ListTile(
                title: const Text('Relationship health'),
                subtitle: Text(switch (_scores?.health(_person.id)) {
                  final h? => relationshipBand(h),
                  null => 'Not rated yet',
                }),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_scores?.healthTrend(_person.id) case final trend?
                        when trend.nonNulls.isNotEmpty) ...[
                      TrendSparkline(
                        trend: trend,
                        scale: HealthScale.relationship,
                      ),
                      const SizedBox(width: 8),
                    ],
                    HealthDot(
                      rating: _scores?.health(_person.id),
                      scale: HealthScale.relationship,
                    ),
                  ],
                ),
              ),
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
            _heading(theme, 'Traits'),
            ..._applies(theme),
            if (_scored) ..._traits(context),
            if (_habits case final habits?) ...[
              _heading(theme, 'Habits'),
              ..._habitTiles(theme, habits),
            ],
            _heading(
              theme,
              _person.isSelf ? 'What matters to you' : 'What matters to them',
            ),
            _padded(switch (_person.whatMatters) {
              final text? when text.trim().isNotEmpty => Text(text),
              _ => Text(
                'Nothing yet. Compaction adds to it as notes reveal things.',
                style: TextStyle(color: theme.hintColor),
              ),
            }),
            if (_scored) ...[
              _heading(theme, 'History'),
              ..._history(theme),
              _heading(theme, 'Events'),
              ..._timeline(theme),
            ],
            _heading(theme, 'Cancelled'),
            ..._cancelled(theme),
          ],
        ),
      ),
    );
  }

  /// Which traits apply to them, and their own parts for any.
  List<Widget> _applies(ThemeData theme) => traitsApplied(
    theme,
    _person.traits,
    traitList: _traitList,
    actionNames: widget.actionNames,
  );

  /// Each of Self's habits, in its action's color, and a button to add
  /// one.
  List<Widget> _habitTiles(ThemeData theme, List<Habit> habits) {
    final byId = {for (final a in widget.actions) a.id: a};
    return [
      if (habits.isEmpty)
        _padded(
          Text(
            'None yet. A habit holds your events with one action, or any '
            'in a group, to traits of their own: practicing guitar '
            'mindfully, say.',
            style: TextStyle(color: theme.hintColor),
          ),
        ),
      for (final habit in habits)
        ListTile(
          leading: actionDot(byId[habit.actionId], size: 16),
          title: Text(
            habitName(habit),
            style: habit.active ? null : TextStyle(color: theme.hintColor),
          ),
          subtitle: Text(
            [
              byId[habit.actionId]?.path ??
                  habit.actionPath ??
                  switch (byId[habit.actionId]) {
                    final a? => actionName(a),
                    null => habit.actionId,
                  },
              if (!habit.active) habitStatuses[habit.status] ?? habit.status,
            ].join(' · '),
          ),
          trailing: switch (widget.memory?.focus) {
            final focus? => focusHabitButton(focus, habit),
            null => const Icon(Icons.chevron_right),
          },
          onTap: () => _openHabit(habit),
        ),
      Align(
        alignment: AlignmentDirectional.centerStart,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: TextButton.icon(
            onPressed: () => _editHabit(null),
            icon: const Icon(Icons.add),
            label: const Text('Habit'),
          ),
        ),
      ),
    ];
  }

  List<Widget> _traits(BuildContext context) => traitScoreTiles(
    context,
    _scores,
    _person.id,
    whom: 'them',
    why: 'off, archived, or not theirs',
    personNames: widget.personNames,
    locationNames: widget.locationNames,
  );

  List<Widget> _history(ThemeData theme) {
    final digest = _scores?.digest(_person.id);
    if (digest == null) return [_padded(const LinearProgressIndicator())];
    String entries(List<DigestEntry> list) => list.isEmpty
        ? 'None recorded'
        : [
            for (final e in list)
              '${widget.actionNames[e.label] ?? widget.locationNames[e.label] ?? e.label} ×${e.count} '
                  '(${e.first == e.last ? e.first : '${e.first} – ${e.last}'})',
          ].join('\n');
    return [
      _padded(
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

  /// Their events in brief -- how many, their time, the most recent and
  /// the oldest -- with "All events" opening the lot on a page of its
  /// own.
  List<Widget> _timeline(ThemeData theme) => eventsSummary(
    context,
    _scores?.digest(_person.id),
    noteOf: _person.id,
    actionNames: widget.actionNames,
    personNames: widget.personNames,
    locationNames: widget.locationNames,
    onAll: () => _openList(
      'Events',
      (context) => eventTiles(
        context,
        _scores?.digest(_person.id),
        noteOf: _person.id,
        actionNames: widget.actionNames,
        personNames: widget.personNames,
        locationNames: widget.locationNames,
      ),
    ),
  );

  /// The events the user cancelled that count against their
  /// follow-through, in brief as their events are, with "All cancelled
  /// events" opening the lot.
  List<Widget> _cancelled(ThemeData theme) => cancelledSummary(
    context,
    _person.cancelledEvents,
    whose: _person.isSelf ? 'your' : 'their',
    whom: _person.isSelf ? 'you' : 'them',
    withWhom: _person.isSelf ? null : 'with them',
    traitList: _traitList,
    actionNames: widget.actionNames,
    onAll: () => _openList(
      'Cancelled',
      (context) => cancelledTiles(
        context,
        _person.cancelledEvents,
        whose: _person.isSelf ? 'your' : 'their',
        whom: _person.isSelf ? 'you' : 'them',
        withWhom: _person.isSelf ? null : 'with them',
        traitList: _traitList,
        actionNames: widget.actionNames,
      ),
    ),
  );

  /// A page of [title] listing what [tiles] builds, built again as
  /// they're scored again.
  void _openList(String title, List<Widget> Function(BuildContext) tiles) =>
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => EventListScreen(
            title: '$title · ${personName(_person)}',
            listenable: widget.memory,
            tiles: tiles,
          ),
        ),
      );

  Widget _heading(ThemeData theme, String text) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 16, 8, 4),
    child: Text(text, style: theme.textTheme.titleMedium),
  );

  Widget _padded(Widget child) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
    child: child,
  );
}

/// Which traits apply -- [traits.select], every active one by default --
/// named from [traitList], and [own] parts for any: a person's, or a
/// habit's. [actionNames] names the actions a part counts.
List<Widget> traitsApplied(
  ThemeData theme,
  PersonTraits traits, {
  required Map<String, Trait> traitList,
  required Map<String?, String> actionNames,
  String own = 'their own',
}) {
  String name(String id) => traitList[id]?.name ?? id;
  return [
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
}) {
  final theme = Theme.of(context);
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
    for (final score in rating.traits)
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
        ),
      ),
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
            for (final id in event['action_ids'] as List)
              actionNames['$id'] ?? '$id',
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
