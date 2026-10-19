import 'package:flutter/material.dart';

import '../models/goal.dart';
import '../services/goals_repository.dart';
import '../services/plan_memory.dart';
import '../widgets/app_menu.dart' show RefreshButton;
import '../widgets/event_description.dart';
import '../widgets/goal_editor.dart';
import '../widgets/goal_flows.dart';
import '../widgets/goal_tile.dart';
import '../widgets/hotkeys.dart';

/// A goal's page, the same for a goal at any depth: read only, with the
/// pencil in its bar to edit it. Its title has its path (its parents'
/// titles) under it, and lines to its left, one for each level deep it
/// is. Below: its status, with what can change it; when it's due, its
/// expected time against the time spent; when it started and closed;
/// its description, definition of done and attribution hints; the goals
/// directly under it (soonest due first, filtered by status), each opening
/// its own page, with "+" to add one; and its history, each change's time
/// tapped to change it, or deleted. Holding a sub-goal selects it: then
/// the inactive ones selected can be activated together, each given a
/// deadline at once.
class GoalScreen extends StatefulWidget {
  const GoalScreen({
    super.key,
    required this.goalId,
    required this.repository,
    required this.memory,
  });

  final String goalId;
  final GoalsRepository repository;
  final PlanMemory memory;

  @override
  State<GoalScreen> createState() => _GoalScreenState();
}

class _GoalScreenState extends State<GoalScreen> {
  var _statuses = const {'inactive', 'active'};
  final _selected = <String>{};

  /// The pull-to-refresh, which the refresh button pulls down.
  final _refresher = GlobalKey<RefreshIndicatorState>();

  GoalActions get _actions => GoalActions(
    context: context,
    repository: widget.repository,
    memory: widget.memory,
  );

  @override
  void initState() {
    super.initState();
    widget.memory.addListener(_changed);
  }

  @override
  void dispose() {
    widget.memory.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  /// Every goal again, from the server.
  Future<void> _reload() =>
      widget.memory.loadGoals(widget.repository, again: true);

  void _open(Goal goal) => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => GoalScreen(
        goalId: goal.id,
        repository: widget.repository,
        memory: widget.memory,
      ),
    ),
  );

  void _toggle(Goal goal) => setState(() {
    if (!_selected.remove(goal.id)) _selected.add(goal.id);
  });

  Future<void> _activateSelected(GoalTree tree) async {
    final picked = [
      for (final id in _selected)
        if (tree[id] case final g? when g.inactive) g,
    ];
    if (picked.isEmpty) return;
    await _actions.activate(picked);
    if (mounted) setState(_selected.clear);
  }

  Future<void> _menu(String action, Goal goal) async {
    final actions = _actions;
    switch (action) {
      case 'move':
        await actions.move(goal);
      case 'delete':
        await actions.delete(goal);
        if (mounted &&
            widget.memory.goals?.any((g) => g.id == goal.id) != true) {
          Navigator.of(context).pop();
        }
      default:
        await actions.setStatus(goal, action);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tree = GoalTree(widget.memory.goals ?? const []);
    final goal = tree[widget.goalId];
    if (goal == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: Text('This goal is gone.')),
      );
    }
    final spent = keptGoalTime(widget.memory, tree);
    final children = tree.childrenOf(goal.id);
    final shown = byPriority([
      for (final c in children)
        if (_statuses.contains(c.status)) c,
    ], tree);
    final selecting = _selected.isNotEmpty;
    final path = tree.pathOf(goal.id);
    return Scaffold(
      appBar: AppBar(
        leading: selecting
            ? IconButton(
                tooltip: 'Stop selecting',
                icon: const Icon(Icons.close),
                onPressed: () => setState(_selected.clear),
              )
            : null,
        titleSpacing: selecting ? null : 0,
        title: selecting
            ? Text('${_selected.length} selected')
            : Row(
                children: [
                  DepthBars(depth: tree.depthOf(goal.id), height: 36),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(goalTitle(goal), overflow: TextOverflow.ellipsis),
                        if (path.isNotEmpty)
                          Text(
                            path.join(' › '),
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall,
                          ),
                      ],
                    ),
                  ),
                ],
              ),
        actions: selecting
            ? [
                TextButton.icon(
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('Activate'),
                  onPressed: _selected.any((id) => tree[id]?.inactive ?? false)
                      ? () => _activateSelected(tree)
                      : null,
                ),
              ]
            : [
                RefreshButton(
                  onRefresh: () async => _refresher.currentState?.show(),
                ),
                EditHotkey(
                  child: IconButton(
                    tooltip: 'Edit',
                    icon: const Icon(Icons.edit_outlined),
                    onPressed: () => _actions.edit(goal),
                  ),
                ),
                PopupMenuButton<String>(
                  onSelected: (action) => _menu(action, goal),
                  itemBuilder: (context) => [
                    for (final (status, label) in _statusMoves(goal))
                      PopupMenuItem(value: status, child: Text(label)),
                    const PopupMenuDivider(),
                    const PopupMenuItem(value: 'move', child: Text('Move…')),
                    const PopupMenuItem(
                      value: 'delete',
                      child: Text('Delete…'),
                    ),
                  ],
                ),
              ],
      ),
      body: RefreshIndicator(
        key: _refresher,
        onRefresh: _reload,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.only(bottom: 24),
          children: [
            _statusRow(context, goal),
            _facts(context, goal, spent[goal.id]),
            if (goal.description case final text?)
              _section(
                context,
                'Description',
                EventDescription(text, maxLines: null, selectable: true),
              ),
            if (goal.definitionOfDone case final text?)
              _section(
                context,
                'Definition of done',
                EventDescription(text, maxLines: null, selectable: true),
              ),
            if (goal.attributionHints case final text?)
              _section(context, 'Attribution hints', SelectableText(text)),
            const Divider(height: 24),
            Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(16, 0, 4, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Sub-goals',
                      style: theme.textTheme.titleMedium,
                    ),
                  ),
                  GoalStatusFilter(
                    statuses: _statuses,
                    onChanged: (picked) => setState(() => _statuses = picked),
                  ),
                  NewHotkey(
                    child: IconButton(
                      tooltip: 'New sub-goal',
                      icon: const Icon(Icons.add),
                      onPressed: goal.closed
                          ? null
                          : () => _actions.add(parent: goal),
                    ),
                  ),
                ],
              ),
            ),
            if (children.isEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                child: Text(
                  goal.closed
                      ? 'Nothing under it.'
                      : 'Nothing under it yet. Tap + to add a piece of it.',
                  style: TextStyle(color: theme.hintColor),
                ),
              )
            else if (shown.isEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                child: Text(
                  'None with the statuses shown.',
                  style: TextStyle(color: theme.hintColor),
                ),
              ),
            // What J and K go down and up: not the buttons over them, nor
            // the history under them.
            HotkeyItems(
              child: Column(
                children: [
                  for (final child in shown)
                    GoalTile(
                      goal: child,
                      spent: spent[child.id],
                      subGoals: tree.childrenOf(child.id).length,
                      priority: tree.priorityOf(child.id),
                      selecting: selecting,
                      selected: _selected.contains(child.id),
                      onTap: selecting
                          ? () => _toggle(child)
                          : () => _open(child),
                      onLongPress: () => _toggle(child),
                      onEdit: () => _actions.edit(child),
                    ),
                ],
              ),
            ),
            const Divider(height: 24),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text('History', style: theme.textTheme.titleMedium),
            ),
            for (final (i, change) in goal.history.indexed.toList().reversed)
              ListTile(
                dense: true,
                leading: const Icon(Icons.history, size: 20),
                title: Text(goalStatuses[change.status] ?? change.status),
                subtitle: Text(_when(context, change.at)),
                onTap: () => _actions.retime(goal, i),
                trailing: goal.history.length < 2
                    ? null
                    : IconButton(
                        tooltip: 'Delete this change',
                        icon: const Icon(Icons.delete_outline, size: 20),
                        onPressed: () => _actions.forget(goal, i),
                      ),
              ),
          ],
        ),
      ),
    );
  }

  /// What [goal]'s status can change to, with what each's called.
  static List<(String, String)> _statusMoves(Goal goal) =>
      switch (goal.status) {
        'active' => const [
          ('done', 'Mark done'),
          ('missed', 'Mark missed'),
          ('obsolete', 'Mark obsolete'),
          ('inactive', 'Deactivate'),
        ],
        'inactive' => const [
          ('active', 'Activate'),
          ('obsolete', 'Mark obsolete'),
          ('missed', 'Mark missed'),
        ],
        _ => const [('active', 'Reopen'), ('inactive', 'Reopen as inactive')],
      };

  Widget _statusRow(BuildContext context, Goal goal) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
    child: Wrap(
      spacing: 8,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Chip(
          avatar: Icon(
            Icons.flag_outlined,
            size: 16,
            color: goalColor(context, goal),
          ),
          label: Text(goalStatuses[goal.status] ?? goal.status),
        ),
        for (final (status, label) in _statusMoves(goal).take(2))
          OutlinedButton(
            onPressed: () => _actions.setStatus(goal, status),
            child: Text(label),
          ),
      ],
    ),
  );

  Widget _facts(BuildContext context, Goal goal, Duration? spent) {
    final theme = Theme.of(context);
    final rows = [
      if (goal.deadline != null) ('Due', deadlineLabel(context, goal.deadline)),
      if (spentLabel(goal, spent) case final s?) ('Time', s),
      if (goal.startedAt case final at?) ('Started', _when(context, at)),
      if (goal.closedAt case final at?)
        (goalStatuses[goal.status] ?? goal.status, _when(context, at)),
      if (goal.parentId != null)
        ('Parent', goal.required ? 'Needs it done' : "Doesn't need it done"),
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final (label, value) in rows)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 88,
                    child: Text(label, style: theme.textTheme.labelLarge),
                  ),
                  Expanded(child: Text(value)),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _section(BuildContext context, String title, Widget body) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 4),
        body,
      ],
    ),
  );

  static String _when(BuildContext context, DateTime at) {
    final strings = MaterialLocalizations.of(context);
    final local = at.toLocal();
    return '${strings.formatMediumDate(local)}, '
        '${strings.formatTimeOfDay(TimeOfDay.fromDateTime(local))}';
  }
}
