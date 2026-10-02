import 'package:flutter/material.dart';

import '../models/goal.dart';
import '../services/goals_repository.dart';
import '../services/mcp_client.dart';
import '../widgets/app_menu.dart';
import '../widgets/color_picker.dart';
import '../widgets/goal_dialog.dart';
import '../widgets/refreshing_bar.dart';
import '../widgets/status_message.dart';

/// Every goal, as a tree: each one's color, name, status, priority and
/// cadence, with its sub-goals indented under it. The filter at the top
/// right picks which statuses are shown: proposed, active and inactive
/// goals to start with. Only active goals take up a calendar label; the others keep
/// their history. Tapping a goal shows all its properties and lets one
/// change them; its menu adds a sub-goal or moves it to another status;
/// "+" adds a top-level goal.
class GoalsScreen extends StatefulWidget {
  const GoalsScreen({
    super.key,
    required this.repository,
    required this.serverLabel,
    this.onSignIn,
    this.onSignOut,
    this.version,
  });

  final GoalsRepository repository;

  /// Which server this build talks to, for the About dialog.
  final String serverLabel;

  /// Runs the interactive sign-in; null when the backend needs none.
  final Future<void> Function()? onSignIn;
  final Future<void> Function()? onSignOut;

  /// The app's version, for the About dialog; null until it's known.
  final String? version;

  @override
  State<GoalsScreen> createState() => _GoalsScreenState();
}

class _GoalsScreenState extends State<GoalsScreen> {
  GoalList? _goals;

  /// [_goals] are the ones kept from last time; the server hasn't answered
  /// since.
  bool _stale = false;
  Object? _error;
  bool _needsSignIn = false;
  bool _signingIn = false;

  /// The statuses shown.
  final _shown = {...defaultGoalStatuses};

  @override
  void initState() {
    super.initState();
    _showCached();
    _load();
  }

  /// Shows the goals kept from last time, unless the server answered
  /// first.
  Future<void> _showCached() async {
    final goals = await widget.repository.cachedGoals();
    if (!mounted || goals == null) return;
    if (_goals != null || _needsSignIn || _error != null) return;
    setState(() {
      _goals = goals;
      _stale = true;
    });
  }

  Future<void> _load() async {
    try {
      final goals = await widget.repository.goals();
      if (!mounted) return;
      setState(() {
        _goals = goals;
        _stale = false;
        _error = null;
        _needsSignIn = false;
      });
    } on SignInRequiredException {
      if (!mounted) return;
      setState(() {
        _goals = null;
        _stale = false;
        _needsSignIn = true;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e);
    }
  }

  /// Every goal, for the dialogs' goal pickers.
  Future<List<Goal>> _allGoals() async =>
      (await widget.repository.goals()).goals;

  void _saved(GoalList? goals, String message) {
    if (goals == null || !mounted) return;
    setState(() {
      _goals = goals;
      _stale = false;
      _error = null;
    });
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _open(Goal goal) async => _saved(
    await showGoalDialog(
      context,
      goal,
      save: widget.repository.updateGoal,
      goals: _allGoals,
    ),
    'Saved.',
  );

  Future<void> _add({String? parentId}) async => _saved(
    await showNewGoalDialog(
      context,
      create: widget.repository.createGoal,
      parentId: parentId,
      goals: _allGoals,
    ),
    'Added.',
  );

  Future<void> _setStatus(Goal goal, String status) async {
    final name = goalName(goal);
    // Freeing a label, or deleting, is worth a second look.
    final (String, String, String)? check = switch (status) {
      'deleted' => (
        'Delete $name?',
        "Its history is kept, and events that have it keep it, but no event "
            "can be given it again. It's hidden unless you show deleted goals.",
        'Delete',
      ),
      _ when goal.active => (
        'Move $name to ${goalStatuses[status]?.toLowerCase()}?',
        "It stops taking up one of the calendar's event labels, and its "
            "events lose its color until it's active again. Its history is "
            'kept.',
        goalStatuses[status] ?? status,
      ),
      _ => null,
    };
    if (check case (final question, final explanation, final confirm)) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(question),
          content: Text(explanation),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Keep it'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(confirm),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
    }
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      _saved(
        await widget.repository.updateGoal(goal, {'status': status}),
        'Now ${goalStatuses[status]?.toLowerCase() ?? status}.',
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(switch (e) {
            SignInRequiredException() =>
              'You were signed out. Sign in again, then try again.',
            McpException(:final message) => message,
            _ => '$e',
          }),
        ),
      );
    }
  }

  Future<void> _signIn() async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _signingIn = true);
    try {
      await widget.onSignIn!();
      await _load();
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Sign-in failed: $e')));
    } finally {
      if (mounted) setState(() => _signingIn = false);
    }
  }

  Future<void> _signOut() async {
    await widget.onSignOut!();
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final ready = _goals != null && !_needsSignIn;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Goals'),
        actions: [
          if (ready)
            _StatusFilter(
              shown: _shown,
              onChanged: (status, on) => setState(
                () => on ? _shown.add(status) : _shown.remove(status),
              ),
            ),
          AppMenu(
            serverLabel: widget.serverLabel,
            version: widget.version,
            onSignOut: widget.onSignOut == null || _needsSignIn
                ? null
                : _signOut,
          ),
        ],
      ),
      floatingActionButton: ready
          ? FloatingActionButton(
              onPressed: _add,
              tooltip: 'Add goal',
              child: const Icon(Icons.add),
            )
          : null,
      body: RefreshingBar(
        refreshing: _stale && _error == null && !_needsSignIn,
        child: RefreshIndicator(onRefresh: _load, child: _buildBody(context)),
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    final goals = _goals;
    if (_needsSignIn) {
      return FillViewport(
        child: StatusMessage(
          icon: Icons.lock_outline,
          text: 'Sign in to see your goals.',
          action: widget.onSignIn == null
              ? null
              : FilledButton(
                  onPressed: _signingIn ? null : _signIn,
                  child: Text(_signingIn ? 'Waiting for browser…' : 'Sign in'),
                ),
        ),
      );
    }
    if (_error != null && (goals == null || goals.goals.isEmpty)) {
      return FillViewport(
        child: StatusMessage(
          icon: Icons.cloud_off,
          text: 'Could not load goals.\n$_error',
        ),
      );
    }
    if (goals == null) return const Center(child: CircularProgressIndicator());
    if (goals.goals.isEmpty) {
      return const FillViewport(
        child: StatusMessage(
          icon: Icons.flag_outlined,
          text: 'No goals yet.\nTap + to add one.',
        ),
      );
    }
    final shown = [
      for (final goal in goals.goals)
        if (_shown.contains(goal.status)) goal,
    ];
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.only(bottom: 88), // Clear of the "+".
      children: [
        // The last goals loaded, or kept from last time, are still shown.
        if (_error != null)
          StatusMessage(
            icon: Icons.cloud_off,
            text: 'Could not load goals. These may be out of date.\n$_error',
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: Row(
            children: [
              Tooltip(
                message:
                    'Each active goal takes one of the calendar\'s event '
                    'labels, as do its own default colors.',
                child: Text(
                  '${goals.labelSlotsUsed} of ${goals.labelSlotsTotal} labels '
                  'in use',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ],
          ),
        ),
        if (shown.isEmpty)
          const StatusMessage(
            icon: Icons.flag_outlined,
            text: 'No goals with these statuses.',
          ),
        for (final (i, goal) in shown.indexed) ...[
          if (i > 0) const Divider(height: 1),
          _GoalTile(
            goal: goal,
            onTap: () => _open(goal),
            onAddSubGoal: () => _add(parentId: goal.id),
            onSetStatus: (status) => _setStatus(goal, status),
          ),
        ],
      ],
    );
  }
}

/// The app bar's filter: a drop-down of every status, each with a check
/// box, which stays open while they're ticked. A dot on its icon says
/// it's showing something other than [defaultGoalStatuses].
class _StatusFilter extends StatelessWidget {
  const _StatusFilter({required this.shown, required this.onChanged});

  final Set<String> shown;
  final void Function(String status, bool on) onChanged;

  @override
  Widget build(BuildContext context) {
    final changed =
        shown.length != defaultGoalStatuses.length ||
        !shown.containsAll(defaultGoalStatuses);
    return MenuAnchor(
      menuChildren: [
        for (final MapEntry(key: status, value: label) in goalStatuses.entries)
          CheckboxMenuButton(
            value: shown.contains(status),
            closeOnActivate: false,
            onChanged: (on) => onChanged(status, on ?? false),
            child: Text(label),
          ),
      ],
      builder: (context, controller, _) => IconButton(
        tooltip: 'Show goals that are…',
        icon: Badge(
          isLabelVisible: changed,
          child: const Icon(Icons.filter_list),
        ),
        onPressed: () =>
            controller.isOpen ? controller.close() : controller.open(),
      ),
    );
  }
}

/// An active goal's flag: solid in its own color if it has one; otherwise
/// a grey outline filled with the color it inherits, from its priority or
/// its parent.
class GoalFlag extends StatelessWidget {
  const GoalFlag({super.key, required this.goal});

  final Goal goal;

  @override
  Widget build(BuildContext context) {
    final hint = Theme.of(context).hintColor;
    if (parseColor(goal.backgroundColor) case final own?) {
      return Icon(Icons.flag, color: own);
    }
    return Stack(
      children: [
        if (parseColor(goal.effectiveColor) case final inherited?)
          Icon(Icons.flag, color: inherited),
        Icon(Icons.outlined_flag, color: hint),
      ],
    );
  }
}

/// What moving a goal to each status is called in its menu.
const _moveTo = {
  'proposed': 'Mark proposed',
  'active': 'Make active',
  'inactive': 'Make inactive',
  'completed': 'Mark completed',
  'archived': 'Archive',
  'deleted': 'Delete',
};

/// Each status's icon.
const _statusIcons = {
  'proposed': Icons.lightbulb_outline,
  'active': Icons.flag,
  'inactive': Icons.pause_circle_outline,
  'completed': Icons.check_circle_outline,
  'archived': Icons.inventory_2_outlined,
  'deleted': Icons.delete_outline,
};

class _GoalTile extends StatelessWidget {
  const _GoalTile({
    required this.goal,
    required this.onTap,
    required this.onAddSubGoal,
    required this.onSetStatus,
  });

  final Goal goal;
  final VoidCallback onTap;
  final VoidCallback onAddSubGoal;
  final ValueChanged<String> onSetStatus;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final priority = goal.priority;
    final faded = goal.active ? null : TextStyle(color: theme.hintColor);
    final details = [
      if (!goal.active) goalStatuses[goal.status] ?? goal.status,
      if (priority != null) 'Priority $priority',
      switch (goal.fixedTime) {
        true => 'Fixed time',
        false => 'Flexible time',
        null => null,
      },
      if (goal.cadence case final cadence?) cadences[cadence] ?? cadence,
    ].nonNulls.join(' · ');
    return ListTile(
      contentPadding: EdgeInsetsDirectional.only(
        start: 16.0 + 24.0 * goal.depth,
        end: 4,
      ),
      leading: Tooltip(
        message: goalStatuses[goal.status] ?? goal.status,
        child: goal.active
            ? GoalFlag(goal: goal)
            : Icon(
                _statusIcons[goal.status] ?? Icons.outlined_flag,
                color: theme.hintColor,
              ),
      ),
      title: Text(goalName(goal), style: faded),
      subtitle: details.isEmpty ? null : Text(details, style: faded),
      trailing: PopupMenuButton<String>(
        tooltip: 'More for ${goalName(goal)}',
        onSelected: (choice) =>
            choice == 'sub' ? onAddSubGoal() : onSetStatus(choice),
        itemBuilder: (context) => [
          const PopupMenuItem(value: 'sub', child: Text('Add sub-goal')),
          const PopupMenuDivider(),
          for (final MapEntry(key: status, value: label) in _moveTo.entries)
            if (status != goal.status)
              PopupMenuItem(value: status, child: Text(label)),
        ],
      ),
      onTap: onTap,
    );
  }
}
