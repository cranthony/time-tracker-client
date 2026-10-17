import 'package:flutter/material.dart';

import '../models/event.dart';
import '../models/goal.dart';
import '../models/goal_changes.dart';
import '../services/goals_repository.dart';
import '../services/plan_memory.dart';
import 'error_sheet.dart';
import 'goal_editor.dart';
import 'goal_icon.dart';

/// What the Goals pane and a goal's page do to goals: add, edit, change
/// their status, move and delete them -- each a change to one goal or
/// several ([GoalChange]s), checked against the server's rules before
/// it's saved ([planned]), saved in order through [repository], and shown
/// in [memory] at once.
class GoalActions {
  GoalActions({
    required this.context,
    required this.repository,
    required this.memory,
    this.now = DateTime.now,
  });

  final BuildContext context;
  final GoalsRepository repository;
  final PlanMemory memory;
  final DateTime Function() now;

  List<Goal> get goals => memory.goals ?? const [];
  GoalTree get tree => GoalTree(goals);

  /// The events kept on the device that are tagged with [goal].
  List<Event> taggedWith(Goal goal) {
    final store = memory.eventStore;
    final span = store?.span;
    if (store == null || span == null) return const [];
    final (first, last) = span;
    return [
      for (final e in store.between(first, last.add(const Duration(days: 1))))
        if (e.goals.any((s) => s.goalId == goal.id)) e,
    ];
  }

  /// Saves [changes], in order, unless they'd break a rule -- then says
  /// which, under [title], and saves nothing. True if they're saved.
  Future<bool> save(String title, List<GoalChange> changes) async {
    if (changes.isEmpty) return true;
    final problems = planned(goals, changes, now: now());
    if (problems.isNotEmpty) {
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(title),
          content: Text(problems.join('\n')),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      return false;
    }
    final several = changes.length > 1;
    // A goal made here gets its id as it's made: what names it after
    // that is given that one.
    final ids = <String, String>{};
    final made = <GoalChange>[];
    return runOrShowError(
      context,
      title: title,
      action: () async {
        for (final change in changes.skip(made.length)) {
          final done = switch (change) {
            GoalCreate(:final goal) => await () async {
              // Its id is the repository's to give.
              final created = await repository.createGoal(
                Goal.fromJson({...goal.toJson(), 'id': ''}),
              );
              ids[goal.id] = created.id;
              return GoalCreate(created);
            }(),
            GoalUpdate(:final id, :final changes) => await () async {
              final named = {
                for (final MapEntry(:key, :value) in changes.entries)
                  key: key == 'parent_id' ? ids[value] ?? value : value,
              };
              await repository.updateGoal(
                ids[id] ?? id,
                named,
                ordered: several,
              );
              return GoalUpdate(ids[id] ?? id, named);
            }(),
            GoalDelete(:final id) => await () async {
              await repository.deleteGoal(ids[id] ?? id, ordered: several);
              return GoalDelete(ids[id] ?? id);
            }(),
          };
          made.add(done);
        }
        memory.showGoals(applied(goals, made, now: now()));
        // Then as the server has them, best effort.
        memory.loadGoals(repository, again: true).ignore();
      },
    );
  }

  /// Adds a goal under [parent] (the top level, if null).
  Future<void> add({Goal? parent}) async {
    final fields = await showGoalEditor(
      context,
      parent: parent,
      goals: goals,
      now: now,
    );
    if (fields == null || !context.mounted) return;
    await save("Couldn't add the goal", [
      GoalCreate(Goal.fromJson({'id': '', ...fields})),
    ]);
  }

  /// Edits [goal].
  Future<void> edit(Goal goal) async {
    final changes = await showGoalEditor(
      context,
      goal: goal,
      goals: goals,
      now: now,
    );
    if (changes == null || changes.isEmpty || !context.mounted) return;
    await save("Couldn't save ${goalTitle(goal)}", [
      GoalUpdate(goal.id, changes),
    ]);
  }

  /// Sets [goal]'s status to [status], with what that takes: activating
  /// its parents, deactivating its sub-goals, or deciding what becomes
  /// of those left open.
  Future<void> setStatus(Goal goal, String status) async {
    switch (status) {
      case 'active':
        await activate([goal]);
      case 'inactive':
        await deactivate(goal);
      case 'done' || 'obsolete':
        await close(goal, status);
    }
  }

  /// Activates [picked], and the inactive parents they're under, asking
  /// for each one's deadline that has none.
  Future<void> activate(List<Goal> picked) async {
    final tree = this.tree;
    final all = [...inactiveParents(tree, picked), ...picked];
    final deadlines = await _askDeadlines(all, tree);
    if (deadlines == null || !context.mounted) return;
    await save(
      picked.length == 1
          ? "Couldn't activate ${goalTitle(picked.single)}"
          : "Couldn't activate the goals",
      activating(tree, picked, deadlines: deadlines),
    );
  }

  /// Deactivates [goal] -- its active sub-goals too, if the user agrees.
  Future<void> deactivate(Goal goal) async {
    final tree = this.tree;
    final active = [
      for (final g in tree.descendantsOf(goal.id))
        if (g.active) g,
    ];
    if (active.isNotEmpty) {
      final ok = await _confirm(
        title: 'Deactivate ${goalTitle(goal)}?',
        text:
            'An inactive goal has no active sub-goals, so '
            '${_count(active.length, 'active sub-goal')} under it will be '
            'deactivated too. To keep one active, move it elsewhere first.',
        action: 'Deactivate them all',
      );
      if (!ok || !context.mounted) return;
    }
    await save(
      "Couldn't deactivate ${goalTitle(goal)}",
      deactivating(tree, goal),
    );
  }

  /// Marks [goal] [status] ("done" or "obsolete"), asking what becomes of
  /// each sub-goal left open: done, obsolete, or moved elsewhere. Done
  /// waits for its required sub-goals.
  Future<void> close(Goal goal, String status) async {
    final tree = this.tree;
    if (status == 'done') {
      final needed = requiredOpen(tree, goal);
      if (needed.isNotEmpty) {
        await _confirm(
          title: "${goalTitle(goal)} isn't done yet",
          text:
              'It needs ${needed.map((g) => '“${goalTitle(g)}”').join(', ')} '
              'done first (or marked obsolete).',
          action: null,
        );
        return;
      }
    }
    final open = [
      for (final c in tree.childrenOf(goal.id))
        if (c.open) c,
    ];
    var leftovers = const <String, Leftover>{};
    Goal? made;
    if (open.isNotEmpty) {
      final decided = await _decideLeftovers(goal, status, open, tree);
      if (decided == null || !context.mounted) return;
      (leftovers, made) = decided;
    }
    await save(
      "Couldn't mark ${goalTitle(goal)} $status",
      closing(tree, goal, status, leftovers: leftovers, made: made),
    );
  }

  /// Moves [goal] under another goal, or to the top level, or under a new
  /// top-level goal made for it -- changing what must change to fit.
  Future<void> move(Goal goal) async {
    final tree = this.tree;
    final picked = await _pickDestination(goal, tree);
    if (picked == null || !context.mounted) return;
    final (to, made) = picked;
    final fit = fitUnder(goal, made ?? tree[to]);
    if (fit.isNotEmpty) {
      final ok = await _confirm(
        title: 'Make it fit?',
        text: _fitText(fit),
        action: 'Move it',
      );
      if (!ok || !context.mounted) return;
    }
    await save(
      "Couldn't move ${goalTitle(goal)}",
      moving(tree, goal, made?.id ?? to, made: made),
    );
  }

  /// Deletes [goal], after a warning -- and another if events are tagged
  /// with it -- and its sub-goals with it, or moved first.
  Future<void> delete(Goal goal) async {
    final tree = this.tree;
    final children = tree.childrenOf(goal.id);
    final under = tree.descendantsOf(goal.id);
    var keep = false;
    final choice = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete ${goalTitle(goal)}?'),
        content: Text(
          [
            "This can't be undone.",
            if (under.isNotEmpty)
              'It has ${_count(under.length, 'sub-goal')}: delete them too, '
                  'or move ${children.length == 1 ? 'it' : 'its '
                            '${children.length} direct sub-goals'} '
                  'to where it is now.',
          ].join('\n\n'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          if (under.isNotEmpty)
            TextButton(
              onPressed: () => Navigator.of(context).pop('keep'),
              child: const Text('Move them, delete it'),
            ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop('delete'),
            child: Text(under.isEmpty ? 'Delete' : 'Delete them all'),
          ),
        ],
      ),
    );
    if (choice == null || !context.mounted) return;
    keep = choice == 'keep';
    final gone = [goal, if (!keep) ...under];
    final tagged = {for (final g in gone) ...taggedWith(g)};
    if (tagged.isNotEmpty) {
      final ok = await _confirm(
        title: 'Events are tagged with it',
        text:
            '${_count(tagged.length, 'event')} on this device '
            '${tagged.length == 1 ? 'is' : 'are'} tagged with '
            '${gone.length == 1 ? 'it' : 'these goals'}. They will stop '
            "showing ${gone.length == 1 ? 'it' : 'them'}, and this can't be "
            'undone.',
        action: 'Delete anyway',
      );
      if (!ok || !context.mounted) return;
    }
    await save(
      "Couldn't delete ${goalTitle(goal)}",
      deleting(tree, goal, keep: keep, moveTo: goal.parentId),
    );
  }

  /// Changes [goal]'s history entry [index]'s time, picked.
  Future<void> retime(Goal goal, int index) async {
    final entry = goal.history[index];
    final at = entry.at.toLocal();
    final day = await showDatePicker(
      context: context,
      initialDate: at,
      firstDate: DateTime(at.year - 10),
      lastDate: DateTime(at.year + 10),
    );
    if (day == null || !context.mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(at),
    );
    if (time == null || !context.mounted) return;
    final when = DateTime(day.year, day.month, day.day, time.hour, time.minute);
    await save("Couldn't change the history", [
      GoalUpdate(goal.id, {
        'history': [
          for (final (i, c) in goal.history.indexed)
            (i == index ? StatusChange(c.status, when) : c).toJson(),
        ],
      }),
    ]);
  }

  /// Deletes [goal]'s history entry [index] -- the last one, its status
  /// going back to the one before.
  Future<void> forget(Goal goal, int index) async {
    if (goal.history.length < 2) return;
    final history = [...goal.history]..removeAt(index);
    await save("Couldn't change the history", [
      GoalUpdate(goal.id, {
        'history': [for (final c in history) c.toJson()],
        if (history.last.status != goal.status) 'status': history.last.status,
      }),
    ]);
  }

  // -- Asking ----------------------------------------------------------------

  Future<bool> _confirm({
    required String title,
    required String text,
    required String? action,
  }) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(title),
          content: Text(text),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(action == null ? 'OK' : 'Cancel'),
            ),
            if (action != null)
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: Text(action),
              ),
          ],
        ),
      ) ??
      false;

  /// Each of [goals]' deadlines, asked for those with none: by id, or
  /// null if it's called off. Each can be the end of today, of this week,
  /// a date, or its parent's.
  Future<Map<String, String>?> _askDeadlines(List<Goal> goals, GoalTree tree) {
    final missing = [
      for (final g in goals)
        if (g.deadline == null) g,
    ];
    if (missing.isEmpty) return Future.value(const {});
    return showDialog<Map<String, String>>(
      context: context,
      builder: (context) =>
          _DeadlinesDialog(goals: missing, tree: tree, now: now()),
    );
  }

  /// What becomes of each of [open], [goal]'s sub-goals left open as it's
  /// closed as [status]: by id, with a new top-level goal for some to move
  /// under, if one's made -- or null if it's called off.
  Future<(Map<String, Leftover>, Goal?)?> _decideLeftovers(
    Goal goal,
    String status,
    List<Goal> open,
    GoalTree tree,
  ) => showDialog<(Map<String, Leftover>, Goal?)>(
    context: context,
    builder: (context) => _LeftoversDialog(
      goal: goal,
      status: status,
      open: open,
      tree: tree,
      pick: (child) => _pickDestination(child, tree, exclude: goal),
    ),
  );

  /// Where [goal] can go: under any open goal not under it (nor
  /// [exclude], nor under that), the top level, or a new top-level goal.
  /// Gives (the goal it goes under, a goal made for it) -- both null for
  /// the top level -- or null if it's called off.
  Future<(String?, Goal?)?> _pickDestination(
    Goal goal,
    GoalTree tree, {
    Goal? exclude,
  }) async {
    final choices = [
      for (final g in _inTreeOrder(tree))
        if (g.open &&
            !tree.isWithin(g.id, goal.id) &&
            (exclude == null || !tree.isWithin(g.id, exclude.id)))
          g,
    ];
    final picked = await showDialog<Object>(
      context: context,
      builder: (context) =>
          _DestinationDialog(goal: goal, choices: choices, tree: tree),
    );
    if (!context.mounted) return null;
    return switch (picked) {
      _Top() => (null, null),
      _New() => await _newTopLevel(goal),
      final Goal g => (g.id, null),
      _ => null,
    };
  }

  /// A new top-level goal for [goal] to move under: its title and
  /// deadline asked for -- inactive, with no deadline, if none's given.
  Future<(String?, Goal?)?> _newTopLevel(Goal goal) async {
    final fields = await showGoalEditor(context, goals: goals, now: now);
    if (fields == null) return null;
    final made = Goal.fromJson({
      ...fields,
      'id': '\u0000made${now().microsecondsSinceEpoch}',
    });
    return (made.id, made);
  }

  /// Every goal, each followed by those under it, soonest due first.
  static List<Goal> _inTreeOrder(GoalTree tree) {
    final out = <Goal>[];
    void walk(List<Goal> level) {
      for (final g in byDeadline(level)) {
        out.add(g);
        walk(tree.childrenOf(g.id));
      }
    }

    walk(tree.topLevel);
    return out;
  }
}

String _count(int n, String noun) => '$n $noun${n == 1 ? '' : 's'}';

/// What [fit] changes, said.
String _fitText(Map<String, Object?> fit) => [
  'To fit under its new parent:',
  if (fit['deadline'] case final String d) '• its deadline becomes $d',
  if (fit['expected_minutes'] case final int m)
    '• its expected time becomes ${formatMinutes(m)}',
  if (fit['status'] == 'inactive')
    '• it, and its active sub-goals, become inactive',
].join('\n');

/// Picks [_DestinationDialog]'s top level.
class _Top {
  const _Top();
}

/// Picks [_DestinationDialog]'s new top-level goal.
class _New {
  const _New();
}

/// Where a goal can go, as a list: the top level, a new top-level goal,
/// then [choices], indented by depth, searchable.
class _DestinationDialog extends StatefulWidget {
  const _DestinationDialog({
    required this.goal,
    required this.choices,
    required this.tree,
  });

  final Goal goal;
  final List<Goal> choices;
  final GoalTree tree;

  @override
  State<_DestinationDialog> createState() => _DestinationDialogState();
}

class _DestinationDialogState extends State<_DestinationDialog> {
  var _query = '';

  @override
  Widget build(BuildContext context) {
    final query = _query.trim().toLowerCase();
    final shown = [
      for (final g in widget.choices)
        if (query.isEmpty || g.title.toLowerCase().contains(query)) g,
    ];
    return AlertDialog(
      title: Text('Move ${goalTitle(widget.goal)}'),
      contentPadding: const EdgeInsets.fromLTRB(0, 16, 0, 0),
      content: SizedBox(
        width: 400,
        height: 420,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                autofocus: true,
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  hintText: 'Search goals',
                  isDense: true,
                ),
                onChanged: (text) => setState(() => _query = text),
              ),
            ),
            Expanded(
              child: ListView(
                children: [
                  if (widget.goal.parentId != null)
                    ListTile(
                      leading: const Icon(Icons.vertical_align_top),
                      title: const Text('To the top level'),
                      onTap: () => Navigator.of(context).pop(const _Top()),
                    ),
                  ListTile(
                    leading: const Icon(Icons.add),
                    title: const Text('Under a new top-level goal…'),
                    onTap: () => Navigator.of(context).pop(const _New()),
                  ),
                  const Divider(),
                  for (final g in shown)
                    ListTile(
                      enabled: g.id != widget.goal.parentId,
                      contentPadding: EdgeInsetsDirectional.only(
                        start: 16.0 + 16 * widget.tree.depthOf(g.id),
                        end: 16,
                      ),
                      leading: const GoalIcon(size: 20),
                      title: Text(goalTitle(g)),
                      subtitle: g.deadline == null
                          ? null
                          : Text('Due ${deadlineLabel(context, g.deadline)}'),
                      onTap: () => Navigator.of(context).pop(g),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
      ],
    );
  }
}

/// Each of [goals]' deadline, picked: the end of today, of this week, a
/// date, or its parent's (one picked here, or the one it has). Saving is
/// off till each has one.
class _DeadlinesDialog extends StatefulWidget {
  const _DeadlinesDialog({
    required this.goals,
    required this.tree,
    required this.now,
  });

  final List<Goal> goals;
  final GoalTree tree;
  final DateTime now;

  @override
  State<_DeadlinesDialog> createState() => _DeadlinesDialogState();
}

class _DeadlinesDialogState extends State<_DeadlinesDialog> {
  final _picked = <String, String>{};

  String? _parents(Goal goal) =>
      _picked[goal.parentId] ?? widget.tree[goal.parentId]?.deadline;

  Future<void> _date(Goal goal) async {
    final now = widget.now;
    final picked = await showDatePicker(
      context: context,
      initialDate: now,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 20),
    );
    if (picked != null && mounted) {
      setState(() => _picked[goal.id] = deadlineOf(picked));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ready = widget.goals.every((g) => _picked.containsKey(g.id));
    return AlertDialog(
      title: Text(
        widget.goals.length == 1 ? 'When is it due?' : 'When are they due?',
      ),
      content: SizedBox(
        width: 420,
        child: ListView(
          shrinkWrap: true,
          children: [
            Text(
              'An active goal needs a deadline.',
              style: theme.textTheme.bodySmall,
            ),
            for (final goal in widget.goals) ...[
              const SizedBox(height: 12),
              Text(goalTitle(goal), style: theme.textTheme.titleSmall),
              Text(
                _picked[goal.id] == null
                    ? 'No deadline yet'
                    : 'Due ${deadlineLabel(context, _picked[goal.id])}',
                style: TextStyle(
                  color: _picked[goal.id] == null
                      ? theme.colorScheme.error
                      : theme.colorScheme.onSurfaceVariant,
                ),
              ),
              Wrap(
                spacing: 6,
                children: [
                  ChoiceChip(
                    label: const Text('End of today'),
                    selected: _picked[goal.id] == endOfToday(widget.now),
                    onSelected: (_) => setState(
                      () => _picked[goal.id] = endOfToday(widget.now),
                    ),
                  ),
                  ChoiceChip(
                    label: const Text('End of this week'),
                    selected: _picked[goal.id] == endOfWeek(widget.now),
                    onSelected: (_) => setState(
                      () => _picked[goal.id] = endOfWeek(widget.now),
                    ),
                  ),
                  ActionChip(
                    avatar: const Icon(Icons.event, size: 16),
                    label: const Text('A date…'),
                    onPressed: () => _date(goal),
                  ),
                  if (_parents(goal) case final parents?)
                    ChoiceChip(
                      label: const Text("Parent's"),
                      selected: _picked[goal.id] == parents,
                      onSelected: (_) =>
                          setState(() => _picked[goal.id] = parents),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: ready ? () => Navigator.of(context).pop(_picked) : null,
          child: const Text('Activate'),
        ),
      ],
    );
  }
}

/// What becomes of each of [open], [goal]'s sub-goals left open, as it's
/// closed as [status]: done, obsolete or moved -- picked where to with
/// [pick]. Gives them by id, with any new top-level goal made for them.
class _LeftoversDialog extends StatefulWidget {
  const _LeftoversDialog({
    required this.goal,
    required this.status,
    required this.open,
    required this.tree,
    required this.pick,
  });

  final Goal goal;
  final String status;
  final List<Goal> open;
  final GoalTree tree;
  final Future<(String?, Goal?)?> Function(Goal child) pick;

  @override
  State<_LeftoversDialog> createState() => _LeftoversDialogState();
}

class _LeftoversDialogState extends State<_LeftoversDialog> {
  late final _chosen = <String, Leftover>{
    for (final c in widget.open) c.id: CloseLeftover(widget.status),
  };
  Goal? _made;

  Future<void> _move(Goal child) async {
    final picked = await widget.pick(child);
    if (picked == null || !mounted) return;
    var (to, made) = picked;
    // One new goal for all that move under one.
    if (made != null) {
      _made ??= made;
      to = _made!.id;
    }
    setState(
      () => _chosen[child.id] = MoveLeftover(
        to: to,
        fit: fitUnder(child, to == _made?.id ? _made : widget.tree[to]),
      ),
    );
  }

  String _where(MoveLeftover move) => switch (move.to) {
    null => 'Moves to the top level',
    final id when id == _made?.id => 'Moves under “${goalTitle(_made!)}” (new)',
    final id => 'Moves under “${goalTitle(widget.tree[id]!)}”',
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final moving = _chosen.values.whereType<MoveLeftover>();
    final made = moving.any((m) => m.to != null && m.to == _made?.id)
        ? _made
        : null;
    return AlertDialog(
      title: Text('Mark ${goalTitle(widget.goal)} ${widget.status}'),
      content: SizedBox(
        width: 440,
        child: ListView(
          shrinkWrap: true,
          children: [
            Text(
              'What becomes of what\'s still open under it?',
              style: theme.textTheme.bodyMedium,
            ),
            for (final child in widget.open) ...[
              const SizedBox(height: 12),
              Text(goalTitle(child), style: theme.textTheme.titleSmall),
              if (widget.tree.descendantsOf(child.id).any((g) => g.open))
                Text(
                  'Closing it closes what\'s open under it too.',
                  style: theme.textTheme.bodySmall,
                ),
              const SizedBox(height: 4),
              SegmentedButton<String>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(value: 'done', label: Text('Done')),
                  ButtonSegment(value: 'obsolete', label: Text('Obsolete')),
                  ButtonSegment(value: 'move', label: Text('Move…')),
                ],
                selected: {
                  switch (_chosen[child.id]) {
                    CloseLeftover(:final status) => status,
                    _ => 'move',
                  },
                },
                onSelectionChanged: (picked) {
                  final value = picked.single;
                  if (value == 'move') {
                    _move(child);
                  } else {
                    setState(() => _chosen[child.id] = CloseLeftover(value));
                  }
                },
              ),
              if (_chosen[child.id] case final MoveLeftover move) ...[
                Text(_where(move), style: theme.textTheme.bodySmall),
                if (move.fit.isNotEmpty)
                  Text(_fitText(move.fit), style: theme.textTheme.bodySmall),
              ],
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop((_chosen, made)),
          child: Text('Mark ${widget.status}'),
        ),
      ],
    );
  }
}
