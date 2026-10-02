import 'package:flutter/material.dart';

import '../models/goal.dart';
import '../services/goals_repository.dart';
import '../services/mcp_client.dart';
import '../widgets/app_menu.dart';
import '../widgets/color_picker.dart';
import '../widgets/goal_dialog.dart';
import '../widgets/refreshing_bar.dart';
import '../widgets/status_message.dart';

/// Which goals the Goals page lists.
enum GoalFilter { active, inactive, all }

/// Every goal, as a tree: each one's color, name, priority and cadence,
/// with its sub-goals indented under it. Active goals are shown first; the
/// filter at the top shows inactive ones, which keep their history but no
/// longer take up a calendar label. Tapping a goal shows all its
/// properties and lets one change them; its menu adds a sub-goal or
/// (de)activates it; "+" adds a top-level goal.
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
  var _filter = GoalFilter.active;

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

  Future<void> _setActive(Goal goal, bool active) async {
    if (!active) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('Deactivate ${goalName(goal)}?'),
          content: const Text(
            "It stops taking up one of the calendar's event labels, and its "
            "events lose its color until it's active again. Its history is "
            'kept.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Keep active'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Deactivate'),
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
        await widget.repository.updateGoal(goal, {'active': active}),
        active ? 'Activated.' : 'Deactivated.',
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
        if (switch (_filter) {
          GoalFilter.active => goal.active,
          GoalFilter.inactive => !goal.active,
          GoalFilter.all => true,
        })
          goal,
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
          child: Wrap(
            spacing: 16,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SegmentedButton<GoalFilter>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(
                    value: GoalFilter.active,
                    label: Text('Active'),
                  ),
                  ButtonSegment(
                    value: GoalFilter.inactive,
                    label: Text('Inactive'),
                  ),
                  ButtonSegment(value: GoalFilter.all, label: Text('All')),
                ],
                selected: {_filter},
                onSelectionChanged: (picked) =>
                    setState(() => _filter = picked.single),
              ),
              Tooltip(
                message:
                    'Each active goal takes one of the calendar\'s event '
                    'labels, as do its own default colors.',
                child: Text(
                  '${goals.labelSlotsUsed} of ${goals.labelSlotsTotal} labels',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ],
          ),
        ),
        if (shown.isEmpty)
          StatusMessage(
            icon: Icons.flag_outlined,
            text: switch (_filter) {
              GoalFilter.inactive => 'No inactive goals.',
              _ => 'No active goals.',
            },
          ),
        for (final (i, goal) in shown.indexed) ...[
          if (i > 0) const Divider(height: 1),
          _GoalTile(
            goal: goal,
            onTap: () => _open(goal),
            onAddSubGoal: () => _add(parentId: goal.id),
            onSetActive: (active) => _setActive(goal, active),
          ),
        ],
      ],
    );
  }
}

class _GoalTile extends StatelessWidget {
  const _GoalTile({
    required this.goal,
    required this.onTap,
    required this.onAddSubGoal,
    required this.onSetActive,
  });

  final Goal goal;
  final VoidCallback onTap;
  final VoidCallback onAddSubGoal;
  final ValueChanged<bool> onSetActive;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = parseColor(goal.backgroundColor);
    final priority = goal.priority;
    final faded = goal.active ? null : TextStyle(color: theme.hintColor);
    final details = [
      if (!goal.active) 'Inactive',
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
      leading: Icon(
        goal.active ? Icons.flag : Icons.outlined_flag,
        color: goal.active ? (color ?? theme.hintColor) : theme.hintColor,
      ),
      title: Text(goalName(goal), style: faded),
      subtitle: details.isEmpty ? null : Text(details, style: faded),
      trailing: PopupMenuButton<String>(
        tooltip: 'More for ${goalName(goal)}',
        onSelected: (choice) => switch (choice) {
          'sub' => onAddSubGoal(),
          'activate' => onSetActive(true),
          _ => onSetActive(false),
        },
        itemBuilder: (context) => [
          const PopupMenuItem(value: 'sub', child: Text('Add sub-goal')),
          if (goal.active)
            const PopupMenuItem(value: 'deactivate', child: Text('Deactivate'))
          else
            const PopupMenuItem(value: 'activate', child: Text('Activate')),
        ],
      ),
      onTap: onTap,
    );
  }
}
