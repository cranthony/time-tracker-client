import 'package:flutter/material.dart';

import '../models/goal.dart';
import '../models/measure.dart';
import '../services/goals_repository.dart';
import '../services/mcp_client.dart';
import 'goal_history_screen.dart';
import '../widgets/app_menu.dart';
import '../widgets/color_picker.dart';
import '../widgets/goal_dialog.dart';
import '../widgets/health.dart';
import '../widgets/refreshing_bar.dart';
import '../widgets/status_message.dart';

/// The overall goal at the top -- its rating, and the time spent on goals
/// of the statuses shown in the last 24 hours and 7 days, each event once
/// -- then every other goal, as a tree: each one's color, name, status,
/// priority and
/// measure, the time spent on it (and its sub-goals) in the last 24 hours
/// and 7 days up to the last compaction, which is noted at the top, and
/// its last 8 days' ratings, with its sub-goals indented under it. A goal
/// with sub-goals starts collapsed, saying how many it has; tapping its
/// arrow or its flag expands it. Pressing and holding a goal starts
/// reordering: each goal can be dragged among its siblings, its sub-goals
/// going with it, until "Done". The filter at the top right picks which
/// statuses are shown: proposed, active and inactive goals to start with.
/// Only active goals take up a calendar label; the others keep their
/// history. Tapping a goal shows its details, all its properties, and lets
/// one change them, its status included; tapping its ratings shows its
/// history; its menu adds a sub-goal, or shows its history or details;
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

  /// The goals whose sub-goals are shown; every other goal is collapsed.
  final _expanded = <String>{};

  /// Whether goals are being dragged into a new order.
  bool _reordering = false;

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

  /// Moves the goal at [oldIndex] of [shown] to [newIndex] (as
  /// ReorderableListView.onReorderItem gives it) among its siblings, shows the new
  /// order at once, and saves it.
  Future<void> _reorder(List<Goal> shown, int oldIndex, int newIndex) async {
    final goals = _goals;
    if (goals == null) return;
    final moved = shown[oldIndex];
    final order = [...shown]
      ..removeAt(oldIndex)
      ..insert(newIndex, moved);
    final ids = [
      for (final goal in order)
        if (goal.parentId == moved.parentId) goal.id!,
    ];
    final before = [
      for (final goal in shown)
        if (goal.parentId == moved.parentId) goal.id!,
    ];
    if (ids.join(',') == before.join(',')) return;
    setState(() => _goals = _withSiblingOrder(goals, ids));
    final messenger = ScaffoldMessenger.of(context);
    try {
      final saved = await widget.repository.reorderGoals(ids);
      if (mounted) setState(() => _goals = saved);
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            "Couldn't save the new order. ${switch (e) {
              SignInRequiredException() => 'Sign in again, then try again.',
              McpException(:final message) => message,
              _ => '$e',
            }}",
          ),
        ),
      );
      await _load();
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
      confirmSave: (changes) => switch (changes['status']) {
        final String status when status != goal.status => _confirmStatus(
          goal,
          status,
        ),
        _ => Future.value(true),
      },
      goals: _allGoals,
    ),
    'Saved.',
  );

  void _history(Goal goal) => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) =>
          GoalHistoryScreen(goal: goal, repository: widget.repository),
    ),
  );

  Future<void> _add({String? parentId}) async {
    // So the new sub-goal can be seen.
    if (parentId != null) setState(() => _expanded.add(parentId));
    await _addGoal(parentId: parentId);
  }

  Future<void> _addGoal({String? parentId}) async => _saved(
    await showNewGoalDialog(
      context,
      create: widget.repository.createGoal,
      parentId: parentId,
      goals: _allGoals,
    ),
    'Added.',
  );

  /// Whether to move [goal] to [status]: freeing its label, or deleting it,
  /// is worth a second look.
  Future<bool> _confirmStatus(Goal goal, String status) async {
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
      return confirmed == true;
    }
    return true;
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
    final reordering = _reordering && ready;
    return PopScope(
      canPop: !reordering,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) setState(() => _reordering = false);
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(reordering ? 'Reorder goals' : 'Goals'),
          actions: reordering
              ? [
                  TextButton(
                    onPressed: () => setState(() => _reordering = false),
                    child: const Text('Done'),
                  ),
                ]
              : [
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
        floatingActionButton: ready && !reordering
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
    // The overall goal has a card of its own, above the tree.
    final overall = goals.overall;
    final all = [
      for (final goal in goals.goals)
        if (!goal.isOverall) goal,
    ];
    if (all.isEmpty) {
      return const FillViewport(
        child: StatusMessage(
          icon: Icons.flag_outlined,
          text: 'No goals yet.\nTap + to add one.',
        ),
      );
    }
    final byId = {for (final goal in all) goal.id: goal};
    final names = {for (final goal in goals.goals) goal.id: goalName(goal)};
    final withStatus = [
      for (final goal in all)
        if (_shown.contains(goal.status)) goal,
    ];
    // How many sub-goals each goal has, of those with the statuses shown.
    final subGoals = <String?, int>{};
    for (final goal in withStatus) {
      subGoals.update(goal.parentId, (n) => n + 1, ifAbsent: () => 1);
    }
    // A goal is hidden under any collapsed ancestor that's shown. One whose
    // parent's status is filtered out still shows, where it always has.
    bool underCollapsed(Goal goal) {
      for (
        var parent = byId[goal.parentId];
        parent != null;
        parent = byId[parent.parentId]
      ) {
        if (_shown.contains(parent.status) && !_expanded.contains(parent.id)) {
          return true;
        }
      }
      return false;
    }

    final shown = [
      for (final goal in withStatus)
        if (!underCollapsed(goal)) goal,
    ];
    if (_reordering) {
      return ReorderableListView.builder(
        buildDefaultDragHandles: false,
        padding: const EdgeInsets.only(bottom: 24),
        header: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: Text(
            'Drag a goal by its handle to move it among the goals it sits '
            'with; its sub-goals go with it.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
        itemCount: shown.length,
        onReorderItem: (from, to) => _reorder(shown, from, to),
        itemBuilder: (context, i) => Column(
          key: ValueKey(shown[i].id),
          mainAxisSize: MainAxisSize.min,
          children: [
            if (i > 0) const Divider(height: 1),
            _GoalTile(
              goal: shown[i],
              goalNames: names,
              subGoals: subGoals[shown[i].id] ?? 0,
              expanded: _expanded.contains(shown[i].id),
              dragIndex: i,
              onToggle: () => setState(() {
                if (!_expanded.remove(shown[i].id)) _expanded.add(shown[i].id!);
              }),
              onTap: null,
              onAddSubGoal: () {},
              onHistory: () {},
            ),
          ],
        ),
      );
    }
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
            runSpacing: 4,
            children: [
              Tooltip(
                message:
                    'Time spent is counted up to when notes were last '
                    'compacted into the calendar.',
                child: Text(switch (goals.asOf) {
                  final asOf? =>
                    'Last compacted ${formatTimestamp(context, asOf)}',
                  null => 'Notes not compacted yet',
                }, style: Theme.of(context).textTheme.bodySmall),
              ),
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
        _OverallCard(
          goal: overall,
          time: overall?.timeFor(_shown) ?? goals.timeFor(_shown),
          goalNames: names,
          onTap: overall == null ? null : () => _open(overall),
          onHistory: overall == null ? null : () => _history(overall),
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
            goalNames: names,
            shownStatuses: _shown,
            subGoals: subGoals[goal.id] ?? 0,
            expanded: _expanded.contains(goal.id),
            onToggle: () => setState(() {
              if (!_expanded.remove(goal.id)) _expanded.add(goal.id!);
            }),
            onTap: () => _open(goal),
            onLongPress: () => setState(() => _reordering = true),
            onAddSubGoal: () => _add(parentId: goal.id),
            onHistory: () => _history(goal),
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
/// an outline in the color it inherits, from its parent or its priority.
class GoalFlag extends StatelessWidget {
  const GoalFlag({super.key, required this.goal});

  final Goal goal;

  @override
  Widget build(BuildContext context) {
    if (parseColor(goal.backgroundColor) case final own?) {
      return Icon(Icons.flag, color: own);
    }
    return Icon(
      Icons.outlined_flag,
      color: parseColor(goal.effectiveColor) ?? Theme.of(context).hintColor,
    );
  }
}

/// Each status's icon.
const _statusIcons = {
  'proposed': Icons.lightbulb_outline,
  'active': Icons.flag,
  'inactive': Icons.pause_circle_outline,
  'completed': Icons.check_circle_outline,
  'archived': Icons.inventory_2_outlined,
  'deleted': Icons.delete_outline,
};

/// The width of the expand arrow before a goal's flag.
const _arrowWidth = 32.0;

class _GoalTile extends StatelessWidget {
  const _GoalTile({
    required this.goal,
    this.goalNames = const {},
    this.shownStatuses,
    required this.subGoals,
    required this.expanded,
    required this.onToggle,
    required this.onTap,
    this.onLongPress,
    this.dragIndex,
    required this.onAddSubGoal,
    required this.onHistory,
  });

  final Goal goal;

  /// Every goal's name, by id, to say whose events it's measured by.
  final Map<String?, String> goalNames;

  /// The statuses the Goals page shows: its time is through goals with
  /// these. Null for all its time.
  final Set<String>? shownStatuses;

  /// How many sub-goals it has (of those shown); none, and it has no arrow.
  final int subGoals;

  /// Whether its sub-goals are shown.
  final bool expanded;

  /// Shows or hides its sub-goals: its arrow and its flag do this.
  final VoidCallback onToggle;

  /// Shows its details: tapping it, or "Details" in its menu.
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  /// While reordering, its index in the list, for its drag handle; null
  /// otherwise, when it has its menu instead.
  final int? dragIndex;
  final VoidCallback onAddSubGoal;

  /// Shows its history: tapping its ratings, or "History" in its menu.
  final VoidCallback onHistory;

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
      if (goal.measure case final measure?)
        describeMeasure(measure, goalNames: goalNames),
      if (goal.staleDays case final stale? when stale > 0)
        '$stale day${stale == 1 ? '' : 's'} unrated',
      if (subGoals > 0 && !expanded)
        '$subGoals sub-goal${subGoals == 1 ? '' : 's'}',
    ].nonNulls.join(' · ');
    final rated =
        goal.active &&
        (goal.staleDays != null ||
            goal.health != null ||
            goal.healthTrend.isNotEmpty);
    // Through the sub-goals shown, if the server says; else all of it.
    final filtered = switch (shownStatuses) {
      final shown? => goal.timeFor(shown),
      null => null,
    };
    final time = switch (filtered ?? (goal.minutes24h, goal.minutes7d)) {
      (final int day, final int week) => describeTime(
        day,
        week,
        skipZero: true,
      ),
      _ => null,
    };
    final flag = Tooltip(
      message: goalStatuses[goal.status] ?? goal.status,
      child: goal.active
          ? GoalFlag(goal: goal)
          : Icon(
              _statusIcons[goal.status] ?? Icons.outlined_flag,
              color: theme.hintColor,
            ),
    );
    return ListTile(
      contentPadding: EdgeInsetsDirectional.only(
        start: 4.0 + 24.0 * goal.depth,
        end: 4,
      ),
      leading: subGoals > 0
          // The arrow and the flag together show or hide its sub-goals.
          ? Tooltip(
              message: '${expanded ? 'Collapse' : 'Expand'} ${goalName(goal)}',
              child: InkWell(
                borderRadius: BorderRadius.circular(20),
                onTap: onToggle,
                child: SizedBox(
                  height: 40,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: _arrowWidth,
                        child: Icon(
                          expanded ? Icons.expand_more : Icons.chevron_right,
                        ),
                      ),
                      flag,
                      const SizedBox(width: 4),
                    ],
                  ),
                ),
              ),
            )
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Lines up with the arrows' flags.
                const SizedBox(width: _arrowWidth),
                flag,
                const SizedBox(width: 4),
              ],
            ),
      title: Text(goalName(goal), style: faded),
      subtitle: details.isEmpty && time == null
          ? null
          : Text(
              [?time, if (details.isNotEmpty) details].join('\n'),
              style: faded,
            ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (rated)
            Tooltip(
              message: 'History of ${goalName(goal)}',
              child: InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: dragIndex == null ? onHistory : null,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 8,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (goal.healthTrend.isNotEmpty) ...[
                        TrendSparkline(trend: goal.healthTrend),
                        const SizedBox(width: 8),
                      ],
                      HealthDot(rating: goal.health),
                    ],
                  ),
                ),
              ),
            ),
          if (dragIndex case final index?)
            ReorderableDragStartListener(
              index: index,
              child: Tooltip(
                message: 'Drag to move ${goalName(goal)}',
                child: const Padding(
                  padding: EdgeInsets.all(12),
                  child: Icon(Icons.drag_handle),
                ),
              ),
            )
          else
            PopupMenuButton<String>(
              tooltip: 'More for ${goalName(goal)}',
              onSelected: (choice) => switch (choice) {
                'sub' => onAddSubGoal(),
                'history' => onHistory(),
                _ => onTap?.call(),
              },
              itemBuilder: (context) => const [
                PopupMenuItem(value: 'sub', child: Text('Add sub-goal')),
                PopupMenuItem(value: 'history', child: Text('History')),
                PopupMenuItem(value: 'details', child: Text('Details')),
              ],
            ),
        ],
      ),
      onTap: onTap,
      onLongPress: onLongPress,
    );
  }
}

/// [goals] with the siblings [ids] (sharing a parent) put in that order
/// among the places they hold, and the list rebuilt parents first, each
/// goal's sub-goals after it, as the server lists them.
GoalList _withSiblingOrder(GoalList goals, List<String> ids) {
  final byId = {for (final goal in goals.goals) goal.id: goal};
  final children = <String?, List<Goal>>{};
  for (final goal in goals.goals) {
    final parent = byId.containsKey(goal.parentId) ? goal.parentId : null;
    children.putIfAbsent(parent, () => []).add(goal);
  }
  final siblings = children[byId[ids.first]?.parentId] ?? [];
  final places = [
    for (final (i, goal) in siblings.indexed)
      if (ids.contains(goal.id)) i,
  ];
  for (var i = 0; i < places.length && i < ids.length; i++) {
    siblings[places[i]] = byId[ids[i]]!;
  }
  final ordered = <Goal>[];
  void visit(Goal goal) {
    ordered.add(goal);
    children[goal.id]?.forEach(visit);
  }

  children[null]?.forEach(visit);
  return GoalList(
    goals: ordered,
    labelSlotsUsed: goals.labelSlotsUsed,
    labelSlotsTotal: goals.labelSlotsTotal,
    asOf: goals.asOf,
    minutesByStatuses: goals.minutesByStatuses,
  );
}

/// The overall goal, above the rest: its rating and last 8 days, and the
/// time spent on the goals of the statuses shown. Tapping it shows its
/// details; tapping its ratings, its history. Without [goal] (from an
/// older server), just the time.
class _OverallCard extends StatelessWidget {
  const _OverallCard({
    required this.goal,
    required this.time,
    required this.goalNames,
    required this.onTap,
    required this.onHistory,
  });

  final Goal? goal;

  /// Minutes on the goals shown in the last 24 hours and 7 days.
  final (int, int)? time;
  final Map<String?, String> goalNames;
  final VoidCallback? onTap;
  final VoidCallback? onHistory;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final goal = this.goal;
    if (goal == null && time == null) return const SizedBox.shrink();
    final details = [
      if (time case (final day, final week))
        '${describeTime(day, week)!} on the goals shown',
      [
        if (goal?.measure case final measure?)
          describeMeasure(measure, goalNames: goalNames)
        else if (goal != null)
          "Average of the top-level goals'",
        if (goal?.staleDays case final stale? when stale > 0)
          '$stale day${stale == 1 ? '' : 's'} unrated',
      ].join(' · '),
    ].where((line) => line.isNotEmpty).join('\n');
    return Card(
      margin: const EdgeInsets.fromLTRB(12, 4, 12, 8),
      color: theme.colorScheme.surfaceContainerHigh,
      child: ListTile(
        leading: Icon(Icons.all_inclusive, color: theme.colorScheme.primary),
        title: Text(goal == null ? 'All goals' : goalName(goal)),
        subtitle: Text(details),
        onTap: onTap,
        trailing: goal == null
            ? null
            : Tooltip(
                message: 'History of ${goalName(goal)}',
                child: InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: onHistory,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 8,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (goal.healthTrend.isNotEmpty) ...[
                          TrendSparkline(trend: goal.healthTrend),
                          const SizedBox(width: 8),
                        ],
                        HealthDot(rating: goal.health),
                      ],
                    ),
                  ),
                ),
              ),
      ),
    );
  }
}

/// [time], in local time, as "Fri, Oct 2, 9:05 PM".
String formatTimestamp(BuildContext context, DateTime time) {
  final strings = MaterialLocalizations.of(context);
  final local = time.toLocal();
  return '${strings.formatShortDate(local)}, '
      '${strings.formatTimeOfDay(TimeOfDay.fromDateTime(local))}';
}

/// [day] and [week] minutes as "9h in 24h (37.5%) · 10h in 7d (6%)", each
/// with its share of the time in its window when that's more than 1/24 (an
/// hour a day). With [skipZero], a window with no time is left out, and
/// null is given if both are.
String? describeTime(int day, int week, {bool skipZero = false}) {
  String? part(int minutes, String window, int windowMinutes) {
    if (skipZero && minutes == 0) return null;
    final text = '${formatMinutes(minutes)} in $window';
    if (minutes * 24 <= windowMinutes) return text;
    final percent = (minutes * 100 / windowMinutes).toStringAsFixed(1);
    final tidy = percent.endsWith('.0')
        ? percent.substring(0, percent.length - 2)
        : percent;
    return '$text ($tidy%)';
  }

  final parts = [
    part(day, '24h', 24 * 60),
    part(week, '7d', 7 * 24 * 60),
  ].nonNulls;
  return parts.isEmpty ? null : parts.join(' · ');
}
