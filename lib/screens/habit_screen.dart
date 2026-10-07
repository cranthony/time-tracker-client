import 'package:flutter/material.dart';

import '../models/habit.dart';
import '../models/plan_action.dart';
import '../models/trait.dart';
import '../widgets/habit_dialog.dart';
import 'person_screen.dart';

/// One of Self's habits on a page: the action or group whose events it's
/// about, in its color, its status, what it's for, which traits apply to
/// it and its own parts for any, and the events the user cancelled that
/// count against its follow-through ([Habit.cancelledEvents]). Claude
/// judges its events; past ones only when asked. [onEdit] edits it,
/// returning it as saved.
class HabitScreen extends StatefulWidget {
  const HabitScreen({
    super.key,
    required this.habit,
    this.actions = const [],
    this.traits = const {},
    this.onEdit,
  });

  final Habit habit;

  /// Every action and group, to name and color its own.
  final List<PlanAction> actions;

  /// Every trait, by id, to name those that apply to it.
  final Map<String, Trait> traits;
  final Future<Habit?> Function(Habit habit)? onEdit;

  @override
  State<HabitScreen> createState() => _HabitScreenState();
}

class _HabitScreenState extends State<HabitScreen> {
  late Habit _habit = widget.habit;

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
          _padded(
            Text(
              'Claude judges its events as they happen. To judge past ones, '
              'ask Claude to judge past events for this habit.',
              style: theme.textTheme.bodySmall,
            ),
          ),
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
