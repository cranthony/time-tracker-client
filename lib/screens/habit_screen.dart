import 'package:flutter/material.dart';

import '../models/habit.dart';
import '../models/person.dart';
import '../models/plan_action.dart';
import '../models/trait.dart';
import '../services/plan_memory.dart';
import '../widgets/focus_buttons.dart';
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final action = widget.actions
        .where((a) => a.id == _habit.actionId)
        .firstOrNull;
    final sections = SubjectSections(
      context,
      memory: widget.memory,
      scored: widget.memory != null && _habit.active,
      subjectId: _habit.subject,
      name: habitName(_habit),
      healthTitle: 'Health',
      scale: HealthScale.action,
      traits: _habit.traits,
      cancelled: _habit.cancelledEvents,
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
          if (widget.memory?.focus case final focus?)
            focusHabitButton(focus, _habit),
          if (widget.onEdit != null) editButton(habitName(_habit), _edit),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.symmetric(vertical: 8),
          children: [
            ...sections.health(),
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
            sectionHeading(theme, "What it's for"),
            sectionPadded(switch (_habit.note) {
              final note? => Text(note),
              null => Text(
                'Nothing yet: a note helps Claude judge its events.',
                style: TextStyle(color: theme.hintColor),
              ),
            }),
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
