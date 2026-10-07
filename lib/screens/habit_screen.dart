import 'package:flutter/material.dart';

import '../models/habit.dart';
import '../models/person.dart';
import '../models/plan_action.dart';
import '../models/trait.dart';
import '../models/trait_scores.dart';
import '../services/plan_memory.dart';
import '../services/focus_store.dart';
import '../widgets/habit_dialog.dart';
import '../widgets/health.dart';
import 'person_screen.dart';

/// One of Self's habits on a page: the action or group whose events it's
/// about, in its color, its status, what it's for, which traits apply to
/// it and its own parts for any, and the events the user cancelled that
/// count against its follow-through ([Habit.cancelledEvents]). Once
/// [memory] has scored it from the events (see [PlanMemory.scores]),
/// also its health -- on track, needing attention or off track -- with
/// its last 8 days, each trait's score of the last day that's over, with
/// its trend (tapping one shows the parts, events and Claude's judgments
/// behind it), and its events. Claude judges its events; past ones only
/// when asked. [onEdit] edits it, returning it as saved.
class HabitScreen extends StatefulWidget {
  const HabitScreen({
    super.key,
    required this.habit,
    this.actions = const [],
    this.traits = const {},
    this.memory,
    this.personNames = const {},
    this.locationNames = const {},
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
  final Future<Habit?> Function(Habit habit)? onEdit;

  @override
  State<HabitScreen> createState() => _HabitScreenState();
}

class _HabitScreenState extends State<HabitScreen> {
  late Habit _habit = widget.habit;

  /// Everyone's scores, its among them, if they're worked out yet.
  TraitScores? get _scores => widget.memory?.scores;
  bool get _scored => widget.memory != null && _habit.active;

  @override
  void initState() {
    super.initState();
    widget.memory?.addListener(_rescored);
  }

  @override
  void dispose() {
    widget.memory?.removeListener(_rescored);
    super.dispose();
  }

  /// Shows the scores again, as they're worked out again.
  void _rescored() {
    if (!mounted) return;
    setState(() {
      // As it's loaded again, after an edit, say.
      if (widget.memory?.habits?.where((h) => h.id == _habit.id).firstOrNull
          case final kept?) {
        _habit = kept;
      }
    });
  }

  Map<String?, String> get _actionNames => {
    for (final a in widget.actions) a.id: actionName(a),
  };

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
    return Scaffold(
      appBar: AppBar(
        title: Text(habitName(_habit)),
        actions: [
          if (widget.memory?.focus case final focus?)
            focusHabitButton(focus, _habit),
          if (widget.onEdit != null)
            IconButton(
              tooltip: 'Edit ${habitName(_habit)}',
              icon: const Icon(Icons.edit_outlined),
              onPressed: _edit,
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          if (_scored)
            ListTile(
              title: const Text('Health'),
              subtitle: Text(switch (_scores?.health(_habit.subject)) {
                final h? => healthBand(h),
                null => 'Not rated yet',
              }),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_scores?.healthTrend(_habit.subject) case final trend?
                      when trend.nonNulls.isNotEmpty) ...[
                    TrendSparkline(trend: trend),
                    const SizedBox(width: 8),
                  ],
                  HealthDot(rating: _scores?.health(_habit.subject)),
                ],
              ),
            ),
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
          _heading(theme, "What it's for"),
          _padded(switch (_habit.note) {
            final note? => Text(note),
            null => Text(
              'Nothing yet: a note helps Claude judge its events.',
              style: TextStyle(color: theme.hintColor),
            ),
          }),
          _heading(theme, 'Traits'),
          ...traitsApplied(
            theme,
            _habit.traits,
            traitList: widget.traits,
            actionNames: _actionNames,
            own: 'its own',
          ),
          if (_scored)
            ...traitScoreTiles(
              context,
              _scores,
              _habit.subject,
              whom: 'it',
              why:
                  "off, archived, not its, or only about what's done for "
                  'someone',
              trends: true,
              scale: HealthScale.action,
              personNames: widget.personNames,
              locationNames: widget.locationNames,
            ),
          _padded(
            Text(
              'Claude judges its events as they happen. To judge past ones, '
              'ask Claude to judge past events for this habit.',
              style: theme.textTheme.bodySmall,
            ),
          ),
          if (_scored) ...[
            _heading(theme, 'Events'),
            ...eventTiles(
              context,
              _scores?.digest(_habit.subject),
              noteOf: selfPersonId,
              actionNames: _actionNames,
              personNames: widget.personNames,
              locationNames: widget.locationNames,
            ),
          ],
          _heading(theme, 'Cancelled'),
          ...cancelledTiles(
            context,
            _habit.cancelledEvents,
            whose: 'its',
            whom: 'it',
            traitList: widget.traits,
            actionNames: _actionNames,
          ),
        ],
      ),
    );
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

/// A star that focuses on [habit], keeping it in the People pane, or
/// stops; off once [FocusStore.maxHabits] are.
Widget focusHabitButton(FocusStore focus, Habit habit) {
  final on = focus.isFocusHabit(habit.id);
  return IconButton(
    tooltip: on
        ? "Don't focus on ${habitName(habit)}"
        : focus.habitsFull
        ? 'Focus on ${habitName(habit)} '
              '(${FocusStore.maxHabits} already)'
        : 'Focus on ${habitName(habit)}',
    isSelected: on,
    icon: const Icon(Icons.star_border),
    selectedIcon: const Icon(Icons.star),
    onPressed: on || !focus.habitsFull
        ? () => focus.setFocusHabit(habit.id, !on)
        : null,
  );
}
