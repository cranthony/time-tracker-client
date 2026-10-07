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
import '../widgets/habit_dialog.dart';
import '../widgets/health.dart';
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
/// ([HabitScreen]), and "Habit" adds one. Habits are best effort: if
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
    final saved = await showHabitDialog(
      context,
      habit: habit,
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
          trailing: const Icon(Icons.chevron_right),
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

  List<Widget> _traits(BuildContext context) {
    final theme = Theme.of(context);
    final scores = _scores;
    if (scores == null) return [_padded(const LinearProgressIndicator())];
    final rating = scores.rating(_person.id);
    if (rating == null || rating.traits.isEmpty) {
      return [
        _padded(
          Text(
            'Not rated: no active trait applies to them.',
            style: TextStyle(color: theme.hintColor),
          ),
        ),
      ];
    }
    return [
      _padded(
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
                '${_partLabel(part)} ${part.score ?? '–'}',
            ].join(' · '),
          ),
          trailing: Text(
            score.score == null ? '–' : '${score.score}',
            style: theme.textTheme.titleMedium,
          ),
          onTap: () => showTraitParts(
            context,
            score,
            labels: [for (final part in score.parts) _partLabel(part)],
            title: rating.day,
            events: scores.eventsBehind(score),
            personNames: widget.personNames,
            locationNames: widget.locationNames,
          ),
        ),
      if (rating.leftOut.isNotEmpty)
        _padded(
          Text(
            'Not rated: ${rating.leftOut.join(', ')} (off, archived, or not '
            'theirs).',
            style: theme.textTheme.bodySmall,
          ),
        ),
    ];
  }

  /// A part's name: a judgment's rubric, else its kind's.
  static String _partLabel(PartScore part) =>
      part.rubric ?? partKinds[part.kind]?.label ?? part.key;

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

  List<Widget> _timeline(ThemeData theme) {
    final digest = _scores?.digest(_person.id);
    if (digest == null) return [_padded(const LinearProgressIndicator())];
    if (digest.events.isEmpty) {
      return [_padded(const Text('No events in this window.'))];
    }
    return [
      for (final event in digest.events.reversed)
        ListTile(
          dense: true,
          title: Text('${event['summary'] ?? '(no title)'}'),
          subtitle: Text(
            [
              _when(event),
              if ((event['action_ids'] as List?)?.isNotEmpty ?? false)
                [
                  for (final id in event['action_ids'] as List)
                    widget.actionNames['$id'] ?? '$id',
                ].join(', '),
              if (Facts.fromJson(event['facts']) case final facts?
                  when !facts.isEmpty) ...[
                facts.describe(widget.personNames, widget.locationNames),
                if (facts.notes[_person.id] case final note?) '“$note”',
              ],
            ].where((line) => line.isNotEmpty).join('\n'),
          ),
        ),
    ];
  }

  /// The events the user cancelled that count against their
  /// follow-through.
  List<Widget> _cancelled(ThemeData theme) => cancelledTiles(
    context,
    _person.cancelledEvents,
    whose: _person.isSelf ? 'your' : 'their',
    whom: _person.isSelf ? 'you' : 'them',
    withWhom: _person.isSelf ? null : 'with them',
    traitList: _traitList,
    actionNames: widget.actionNames,
  );

  String _when(Map<String, dynamic> event) {
    final start = DateTime.tryParse('${event['start']}')?.toLocal();
    if (start == null) return '';
    final localizations = MaterialLocalizations.of(context);
    return '${localizations.formatMediumDate(start)}, '
        '${localizations.formatTimeOfDay(TimeOfDay.fromDateTime(start))}';
  }

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
  final localizations = MaterialLocalizations.of(context);
  String at(DateTime t) =>
      '${localizations.formatMediumDate(t)}, '
      '${localizations.formatTimeOfDay(TimeOfDay.fromDateTime(t))}';
  return [
    for (final c in cancelled)
      ListTile(
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
                final day? =>
                  'Cancelled ${localizations.formatMediumDate(day)}',
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
      ),
  ];
}
