import '../widgets/circle_icon.dart';

import 'package:flutter/material.dart';

import '../models/goal.dart';
import '../models/habit.dart';
import '../models/person.dart';
import '../models/plan_action.dart';
import '../models/recurring_goal.dart';
import '../models/trait.dart';
import '../services/plan_memory.dart';
import '../widgets/habit_dialog.dart';
import '../widgets/health.dart';
import 'subject_sections.dart';

/// One of Self's habits on a page: the action or group whose events it's
/// about, in its color, its status, what it's for, what it's built on
/// ([Habit.foundations], named by [foundationNames]), which traits apply to
/// it and its own parts for any, and the events the user cancelled that
/// count against its follow-through ([Habit.cancelledEvents]). Once
/// [memory] has scored it from the events (see [PlanMemory.scores]),
/// also its health -- on track, needing attention or off track -- with
/// its last 8 days, each trait's score of the last day that's over, with
/// its trend (tapping one shows the parts, events and Claude's judgments
/// behind it), and its events. Its events and cancellations are in
/// brief -- how many, their time, the most recent and the oldest -- with
/// a button opening each lot on a page of its own. Claude judges its
/// events; past ones only when asked. Pulling down loads the events
/// again. [onEdit] edits it, returning it as saved.
///
/// A person's or circle's habit says whose it is, in place of its action,
/// and has their traits -- those it picks -- as they're scored for them.
/// Tapping the person opens their page, with [onOpenPerson]; the circle,
/// its page, with [onOpenCircle].
///
/// A recurring goal's habit says what its goal is, in place of its
/// action, and lists its goals, newest first: done, missed (and tried
/// again), or under way.
class HabitScreen extends StatefulWidget {
  const HabitScreen({
    super.key,
    required this.habit,
    this.actions = const [],
    this.traits = const {},
    this.memory,
    this.personNames = const {},
    this.locationNames = const {},
    this.foundationNames = const {},
    this.onEdit,
    this.onOpenPerson,
    this.onOpenCircle,
  });

  final Habit habit;

  /// Every action and group, to name and color its own.
  final List<PlanAction> actions;

  /// Every trait, by id, to name those that apply to it.
  final Map<String, Trait> traits;

  /// Where its scores are worked out, from the events.
  final PlanMemory? memory;

  /// Names people and locations by id, for who its events were with and
  /// where.
  final Map<String?, String> personNames;
  final Map<String?, String> locationNames;

  /// Names habits and people by id, for what it's built on.
  final Map<String, String> foundationNames;
  final Future<Habit?> Function(Habit habit)? onEdit;

  /// Opens a person's page: theirs, for a person's habit.
  final void Function(Person person)? onOpenPerson;

  /// Opens a circle's page: its, for a circle's habit.
  final void Function(Circle circle)? onOpenCircle;

  @override
  State<HabitScreen> createState() => _HabitScreenState();
}

class _HabitScreenState extends State<HabitScreen> with Rescored {
  late Habit _habit = widget.habit;

  @override
  PlanMemory? get memory => widget.memory;

  // As it's loaded again, after an edit, say.
  @override
  void onRescored() {
    if (memory?.habits?.where((h) => h.id == _habit.id).firstOrNull
        case final kept?) {
      _habit = kept;
    }
  }

  Map<String?, String> get _actionNames => {
    for (final a in widget.actions) a.id: actionName(a),
  };

  /// The week either side of today's events again, rescored as they
  /// come.
  Future<void> _load() async {
    await widget.memory?.eventStore?.warm().catchError((Object _) {});
  }

  Future<void> _edit() async {
    final saved = await widget.onEdit!(_habit);
    if (saved == null || !mounted) return;
    setState(() => _habit = saved);
  }

  /// Its goals, newest first, each with its period and how it went.
  List<Widget> _goals(BuildContext context) {
    final theme = Theme.of(context);
    final goals = [
      for (final g in widget.memory?.goals ?? const <Goal>[])
        if (g.habitId == _habit.id) g,
    ]..sort((a, b) => b.id.compareTo(a.id));
    final locale = MaterialLocalizations.of(context);
    return [
      sectionHeading(theme, 'Its goals'),
      if (goals.isEmpty)
        sectionPadded(
          Text(
            'None yet: the first is made as its period starts.',
            style: TextStyle(color: theme.hintColor),
          ),
        ),
      for (final g in goals)
        ListTile(
          dense: true,
          leading: Icon(switch (g.status) {
            'done' => Icons.check_circle_outline,
            'missed' => Icons.cancel_outlined,
            'obsolete' => Icons.remove_circle_outline,
            _ => g.misses.isEmpty ? Icons.radio_button_unchecked : Icons.replay,
          }, size: 20),
          title: Text(switch (DateTime.tryParse(g.id.split('_').last)) {
            final start? => 'From ${locale.formatMediumDate(start)}',
            null => goalTitle(g),
          }),
          subtitle: Text(
            [
              goalStatuses[g.status] ?? g.status,
              if (g.misses.isNotEmpty && g.open) 'tried again',
              if (g.due case final due? when g.open)
                'due ${locale.formatMediumDate(due.subtract(const Duration(minutes: 1)))}',
            ].join(' · '),
          ),
        ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final action = widget.actions
        .where((a) => a.id == _habit.actionId)
        .firstOrNull;
    final people = widget.memory?.people;
    final person = people?.withSelf
        .where((p) => p.id == _habit.personId)
        .firstOrNull;
    final circle = people?.circles
        .where((c) => c.id == _habit.circleId)
        .firstOrNull;
    final relationship = _habit.isRelationship;
    final open = switch ((person, circle)) {
      (final p?, _) => switch (widget.onOpenPerson) {
        final onOpen? => () => onOpen(p),
        null => null,
      },
      (_, final c?) => switch (widget.onOpenCircle) {
        final onOpen? => () => onOpen(c),
        null => null,
      },
      _ => null,
    };
    final sections = SubjectSections(
      context,
      memory: widget.memory,
      scored: widget.memory != null && _habit.active,
      subjectId: _habit.subject,
      name: habitName(_habit),
      healthTitle: 'Health',
      scale: HealthScale.action,
      traits: switch (person) {
        final p? => p.traits.narrowedTo(_habit.traits),
        null => _habit.traits,
      },
      cancelled: person?.cancelledEvents ?? _habit.cancelledEvents,
      traitList: widget.traits,
      whom: 'it',
      whose: 'its',
      own: 'its own',
      why: "off, archived, not its, or only about what's done for someone",
      trends: true,
      noteOf: selfPersonId,
      actionNames: _actionNames,
      personNames: widget.personNames,
      locationNames: widget.locationNames,
    );
    return Scaffold(
      appBar: AppBar(
        title: Text(habitName(_habit)),
        actions: [
          if (widget.onEdit != null) editButton(habitName(_habit), _edit),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.symmetric(vertical: 8),
          children: [
            ...sections.health(),
            if (relationship)
              ListTile(
                leading: Icon(
                  _habit.personId != null ? Icons.person : circleIconOf(circle),
                ),
                title: Text(switch ((person, circle)) {
                  (final p?, _) => personName(p),
                  (_, final c?) => circleName(c),
                  _ => _habit.personId ?? _habit.circleId ?? '',
                }),
                subtitle: Text(
                  [
                    if (_habit.personId != null)
                      'Their traits, as they are scored for them'
                    else if (circle?.isCommunity ?? false)
                      'Its own traits, as they are scored for it'
                    else
                      "Its people's traits, combined as the circle's are",
                    if (!_habit.active)
                      habitStatuses[_habit.status] ?? _habit.status,
                  ].join(' · '),
                ),
                trailing: open == null ? null : const Icon(Icons.chevron_right),
                onTap: open,
              )
            else if (_habit.recurringGoal case final goal?)
              ListTile(
                leading: const Icon(Icons.repeat),
                title: Text(
                  '${goalEachLabel(goal)}: ${goal.title ?? habitName(_habit)}',
                ),
                subtitle: Text(
                  [
                    goal.definitionOfDone ?? 'Done when its goal is',
                    'goal rate over the last ${goal.ratedPeriods} '
                        '${goalPeriods[goal.period]?.$2 ?? 'periods'}',
                    if (!_habit.active)
                      habitStatuses[_habit.status] ?? _habit.status,
                  ].join(' · '),
                ),
              )
            else
              ListTile(
                leading: actionDot(action, size: 16),
                title: Text(
                  action?.path ??
                      _habit.actionPath ??
                      (action == null ? _habit.actionId : actionName(action)),
                ),
                subtitle: Text(
                  [
                    if (action?.isGroup ?? false)
                      'Your events with any action in it'
                    else
                      'Your events with it',
                    if (!_habit.active)
                      habitStatuses[_habit.status] ?? _habit.status,
                  ].join(' · '),
                ),
              ),
            if (!relationship) sectionHeading(theme, "What it's for"),
            if (!relationship)
              sectionPadded(switch (_habit.note) {
                final note? => Text(note),
                null => Text(
                  'Nothing yet: a note helps Claude judge its events.',
                  style: TextStyle(color: theme.hintColor),
                ),
              }),
            if (_habit.isGoal) ..._goals(context),
            sectionHeading(theme, 'Built on'),
            sectionPadded(switch (_habit.foundations) {
              [] => Text(
                'Nothing: it sits at the bottom of the habit graph.',
                style: TextStyle(color: theme.hintColor),
              ),
              final foundations => Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final id in foundations)
                    Chip(label: Text(widget.foundationNames[id] ?? id)),
                ],
              ),
            }),
            ...sections.traitSection(),
            if (!relationship)
              sectionPadded(
                Text(
                  'Claude judges its events as they happen. To judge past ones, '
                  'ask Claude to judge past events for this habit.',
                  style: theme.textTheme.bodySmall,
                ),
              ),
            ...sections.events(),
            ...sections.cancelledSection(),
          ],
        ),
      ),
    );
  }
}
