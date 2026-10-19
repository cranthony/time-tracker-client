import 'package:flutter/material.dart';

import '../models/goal.dart';
import '../services/goals_repository.dart';
import '../services/plan_memory.dart';
import '../widgets/goal_flows.dart';
import '../widgets/goal_reorder_list.dart';
import '../widgets/goal_tile.dart';
import '../widgets/hotkeys.dart';
import '../widgets/plan_pane.dart';
import '../widgets/plan_summaries.dart';
import 'goal_screen.dart';

/// The Plan page's Goals pane -- what the user aims for: their top-level
/// goals, soonest due first, each with when it's due and the time spent
/// toward it (by the events kept on the device). Tapping one opens its
/// page ([GoalScreen]), where what's under it is; its button edits it.
/// By default the inactive and active ones are shown, and the filter
/// shows others. "+" adds a top-level goal, on its full page; the round
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
    final shown = byPriority([
      for (final g in tree.topLevel)
        if (_statuses.contains(g.status) &&
            matchesSearch(_query, [
              g.title,
              g.description,
              g.definitionOfDone,
              g.attributionHints,
            ]))
          g,
    ], tree);
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
                spent: spent[goal.id],
                subGoals: tree.childrenOf(goal.id).length,
                priority: tree.priorityOf(goal.id),
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
