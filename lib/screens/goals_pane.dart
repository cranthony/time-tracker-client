import 'package:flutter/material.dart';

import '../models/goal.dart';
import '../services/goals_repository.dart';
import '../services/plan_memory.dart';
import '../widgets/goal_backlog.dart';
import '../widgets/goal_flows.dart';
import '../widgets/goal_reorder_list.dart';
import '../widgets/goal_tile.dart';
import '../widgets/hotkeys.dart';
import '../widgets/plan_pane.dart';
import '../widgets/plan_summaries.dart';
import 'goal_screen.dart';

/// The Plan page's Goals pane -- what the user aims for. First, every
/// open goal in its queue ([GoalBacklog]): the goals queued to start one
/// after another, dragged to reorder them, and each other open goal a
/// queue of its own; a search shows the queues with a goal that matches.
/// The tree button shows every goal by status instead, as a tree, each
/// indented under those it's under, soonest due first among those beside
/// it. Either way each goal has when it's due and the time spent toward
/// it (by the events kept on the device). Tapping one opens its page
/// ([GoalScreen]); its button edits it. By status, the inactive and
/// active ones are shown by default, and the filter shows others; a
/// search shows those that match, at any depth, the goals one's under
/// above it, whatever their status. "+" adds a top-level goal, on its
/// full page; the round
/// "+" in the corner, given [onQuickAdd], the quick New goal sheet the
/// home screen widget opens. Above it all, with a
/// [summary] to measure, the time in its window by top-level goal. It
/// shows what [memory] has, while it loads afresh.
class GoalsPane extends StatefulWidget {
  const GoalsPane({
    super.key,
    required this.repository,
    required this.memory,
    this.summary,
    this.onQuickAdd,
  });

  final GoalsRepository repository;
  final PlanMemory memory;

  /// What the summary measures, and how it's shown; null for none.
  final SummaryView? summary;

  /// Opens the quick New goal sheet; null for no button for it.
  final VoidCallback? onQuickAdd;

  @override
  State<GoalsPane> createState() => GoalsPaneState();
}

class GoalsPaneState extends State<GoalsPane> {
  var _statuses = const {'inactive', 'active'};
  var _query = '';

  /// Whether the goals are shown by status, as a tree, in place of the
  /// queues.
  var _byStatus = false;

  /// Whether they've been asked for, this visit, and couldn't be had.
  bool _failed = false;

  List<Goal>? get _goals => widget.memory.goals;

  GoalActions get _actions => GoalActions(
    context: context,
    repository: widget.repository,
    memory: widget.memory,
  );

  @override
  void initState() {
    super.initState();
    widget.memory.addListener(_changed);
    _settle(widget.memory.loadGoals(widget.repository));
  }

  @override
  void dispose() {
    widget.memory.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  Future<void> reload() =>
      _settle(widget.memory.loadGoals(widget.repository, again: true));

  Future<void> _settle(Future<void> loading) async {
    await loading;
    if (mounted) setState(() => _failed = _goals == null);
  }

  void _open(Goal goal) => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => GoalScreen(
        goalId: goal.id,
        repository: widget.repository,
        memory: widget.memory,
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final goals = _goals;
    final view = widget.summary;
    final tree = GoalTree(goals ?? const []);
    final spent = keptGoalTime(widget.memory, tree);
    bool matches(Goal g) => matchesSearch(_query, [
      g.title,
      g.description,
      g.definitionOfDone,
      g.attributionHints,
    ]);
    final shown = tree.outline(
      (g) => _statuses.contains(g.status) && matches(g),
    );
    return PlanPane(
      searchHint: 'Search goals',
      onSearch: (query) => setState(() => _query = query),
      summary: view == null || goals == null
          ? null
          : PlanSummary(
              view: view,
              titles: const ['By goal'],
              pages: (events) => [goalTime(events, view.window, goals)],
            ),
      actions: [
        IconButton(
          tooltip: _byStatus ? 'Show the queues' : 'Show the goal tree',
          icon: Icon(
            _byStatus ? Icons.low_priority : Icons.account_tree_outlined,
          ),
          onPressed: () => setState(() => _byStatus = !_byStatus),
        ),
        if (_byStatus)
          GoalStatusFilter(
            statuses: _statuses,
            onChanged: (picked) => setState(() => _statuses = picked),
          ),
        NewHotkey(
          child: IconButton(
            tooltip: 'New goal',
            icon: const Icon(Icons.add),
            onPressed: goals == null ? null : () => _actions.add(),
          ),
        ),
      ],
      child: _withQuickAdd(
        RefreshIndicator(
          onRefresh: reload,
          child: switch ((goals, _failed)) {
            (null, true) => ListView(
              children: [_message("Couldn't load the goals.", retry: true)],
            ),
            (null, false) => ListView(
              children: const [LinearProgressIndicator()],
            ),
            _ when tree.byId.isEmpty => ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                _message(
                  'No goals yet. Tap + to add one: an outcome you can mark '
                  'done -- shipping a project, say -- with a deadline, and '
                  'goals under it for its pieces.',
                ),
              ],
            ),
            _ when !_byStatus => GoalBacklog(
              goals: goals!,
              allOpen: true,
              matches: _query.trim().isEmpty ? null : matches,
              noMatches: NoMatches(query: _query),
              padding: widget.onQuickAdd == null
                  ? null
                  : const EdgeInsets.only(bottom: 88),
              onMove: _actions.requeue,
              tile: (goal) => GoalTile(
                goal: goal,
                depth: 0,
                spent: spent[goal.id],
                subGoals: tree.childrenOf(goal.id).length,
                priority: tree.priorityOf(goal.id),
                tree: tree,
                onTap: () => _open(goal),
                onEdit: () => _actions.edit(goal),
              ),
            ),
            _ => GoalReorderList(
              goals: shown,
              // Room for the last to be scrolled clear of the round "+".
              padding: widget.onQuickAdd == null
                  ? null
                  : const EdgeInsets.only(bottom: 88),
              tree: tree,
              onMove: _actions.reorder,
              tile: (goal) => GoalTile(
                goal: goal,
                depth: tree.depthOf(goal.id),
                spent: spent[goal.id],
                subGoals: tree.childrenOf(goal.id).length,
                priority: tree.priorityOf(goal.id),
                tree: tree,
                onTap: () => _open(goal),
                onEdit: () => _actions.edit(goal),
              ),
              footer: shown.isNotEmpty
                  ? null
                  : _query.trim().isEmpty
                  ? _message('No goals with the statuses shown.')
                  : NoMatches(query: _query),
            ),
          },
        ),
      ),
    );
  }

  /// [list], with the round "+" for the quick New goal sheet over its
  /// lower right, as the Notes page has for a note.
  Widget _withQuickAdd(Widget list) {
    final onQuickAdd = widget.onQuickAdd;
    if (onQuickAdd == null) return list;
    return Stack(
      children: [
        Positioned.fill(child: list),
        PositionedDirectional(
          end: 16,
          bottom: 16,
          child: HotkeyHint(
            Hotkey.newGoal,
            child: FloatingActionButton(
              heroTag: null,
              onPressed: onQuickAdd,
              tooltip: 'Add goal',
              child: const Icon(Icons.add),
            ),
          ),
        ),
      ],
    );
  }

  Widget _message(String text, {bool retry = false}) => Padding(
    padding: const EdgeInsets.all(16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(text),
        if (retry)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: OutlinedButton(
              onPressed: reload,
              child: const Text('Try again'),
            ),
          ),
      ],
    ),
  );
}
