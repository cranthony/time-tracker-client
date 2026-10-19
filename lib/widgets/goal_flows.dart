import 'package:flutter/material.dart';

import 'durations.dart';
import '../models/event.dart';
import '../models/goal.dart';
import '../models/goal_changes.dart';
import '../services/goals_repository.dart';
import '../services/plan_memory.dart';
import 'error_sheet.dart';
import 'goal_editor.dart';
import 'goal_icon.dart';
import 'hotkeys.dart';

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
    // Several at once are checked as the server checks them: whole.
    final problems = changes.length > 1
        ? planned(goals, [GoalBatch(changes)], now: now())
        : planned(goals, changes, now: now());
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
    // One goal's change on its own, through the write queue; several at
    // once, checked whole.
    if (changes.length > 1) {
      return runOrShowError(
        context,
        title: title,
        action: () async {
          final ids = await repository.changeGoals(changes);
          _shown(renamed(changes, ids));
        },
      );
    }
    return runOrShowError(
      context,
      title: title,
      action: () async {
        final change = changes.single;
        switch (change) {
          case GoalCreate(:final goal):
            // Its id is the repository's to give.
            final created = await repository.createGoal(
              Goal.fromJson({...goal.toJson(), 'id': ''}),
            );
            _shown([GoalCreate(created)]);
          case GoalUpdate(:final id, changes: final fields):
            await repository.updateGoal(id, fields);
            _shown([change]);
          case GoalDelete(:final id):
            await repository.deleteGoal(id);
            _shown([change]);
          case GoalBatch(changes: final several):
            final ids = await repository.changeGoals(several);
            _shown(renamed(several, ids));
        }
      },
    );
  }

  /// Shows [made] in [memory] at once, then the goals as the server has
  /// them, best effort.
  void _shown(List<GoalChange> made) {
    memory.showGoals(applied(goals, made, now: now()));
    memory.loadGoals(repository, again: true).ignore();
  }

  /// Saves [sortOrders], by goal id, as a goal's dragged into place
  /// ([GoalReorderList]): shown at once, so it stays where it's dropped,
  /// and put back if they can't be saved.
  Future<void> reorder(Map<String, int> sortOrders) async {
    final changes = [
      for (final MapEntry(:key, :value) in sortOrders.entries)
        GoalUpdate(key, {'sort_order': value}),
    ];
    final before = goals;
    memory.showGoals(applied(before, changes, now: now()));
    if (!await save("Couldn't reorder the goals", changes)) {
      memory.showGoals(before);
    }
  }

  /// Adds a goal under [parent] (the top level, if null), starting with
  /// [title], [deadline], [description] and [definitionOfDone] if they're
  /// given. Whether it's saved.
  Future<bool> add({
    Goal? parent,
    String? title,
    String? deadline,
    String? description,
    String? definitionOfDone,
  }) async {
    final fields = await showGoalEditor(
      context,
      parent: parent,
      goals: goals,
      title: title,
      deadline: deadline,
      description: description,
      definitionOfDone: definitionOfDone,
      now: now,
    );
    if (fields == null || !context.mounted) return false;
    return save("Couldn't add the goal", [
      GoalCreate(Goal.fromJson({'id': '', ...fields})),
    ]);
  }

  /// Adds a goal made of [fields], from the New goal sheet: shown in
  /// [memory] at once. Throws if it can't be.
  Future<void> create(Map<String, Object?> fields) async {
    final created = await repository.createGoal(
      Goal.fromJson({'id': '', ...fields}),
    );
    _shown([GoalCreate(created)]);
  }

  /// Edits [goal] -- a change of its status made as [setStatus] makes it,
  /// with the rest of the edit.
  Future<void> edit(Goal goal) async {
    final changes = await showGoalEditor(
      context,
      goal: goal,
      goals: goals,
      now: now,
    );
    if (changes == null || changes.isEmpty || !context.mounted) return;
    final fields = {...changes};
    if (fields.remove('status') case final String status) {
      await setStatus(goal, status, also: fields);
      return;
    }
    await save("Couldn't save ${goalTitle(goal)}", [
      GoalUpdate(goal.id, fields),
    ]);
  }

  /// Sets [goal]'s status to [status], with what that takes: activating
  /// its parents, deactivating its sub-goals, or deciding what becomes
  /// of those left open -- and [also] changed in it too, if given.
  Future<void> setStatus(
    Goal goal,
    String status, {
    Map<String, Object?> also = const {},
  }) async {
    switch (status) {
      case 'active':
        await activate([goal], also: also);
      case 'inactive':
        await deactivate(goal, also: also);
      case 'done' || 'missed' || 'obsolete':
        await close(goal, status, also: also);
    }
  }

  /// Activates [picked], and the inactive parents they're under, asking
  /// for each one's deadline that has none -- from [at], if it's given (an
  /// event's start, say): then each is backdated to it, or to its last
  /// change, if that's later. With [also], the one picked has that
  /// changed in it too.
  Future<void> activate(
    List<Goal> picked, {
    DateTime? at,
    Map<String, Object?> also = const {},
  }) async {
    final tree = also.isEmpty
        ? this.tree
        : GoalTree(
            applied(goals, [GoalUpdate(picked.single.id, also)], now: now()),
          );
    picked = [for (final g in picked) tree[g.id] ?? g];
    final all = [...inactiveParents(tree, picked), ...picked];
    final deadlines = await _askDeadlines(all, tree);
    if (deadlines == null || !context.mounted) return;
    final changes = also.isEmpty
        ? activating(tree, picked, deadlines: deadlines)
        : editing(
            tree,
            picked.single,
            also,
            status: 'active',
            deadlines: deadlines,
          );
    await save(
      picked.length == 1
          ? "Couldn't activate ${goalTitle(picked.single)}"
          : "Couldn't activate the goals",
      at == null ? changes : [for (final c in changes) _backdated(c, at)],
    );
  }

  /// [change], a goal's activation, dated [at] -- or its last change, if
  /// that's later -- rather than now.
  GoalChange _backdated(GoalChange change, DateTime at) {
    if (change is! GoalUpdate) return change;
    final goal = tree[change.id];
    if (goal == null) return change;
    final last = goal.history.lastOrNull?.at;
    final when = last != null && last.isAfter(at) ? last : at;
    return GoalUpdate(change.id, {
      ...change.changes,
      'history': [
        for (final c in goal.history) c.toJson(),
        StatusChange('active', when).toJson(),
      ],
    });
  }

  /// Deactivates [goal] -- its active sub-goals too, if the user agrees --
  /// with [also] changed in it too.
  Future<void> deactivate(
    Goal goal, {
    Map<String, Object?> also = const {},
  }) async {
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
      editing(tree, goal, also, status: 'inactive'),
    );
  }

  /// Marks [goal] [status] ("done", "missed" or "obsolete"), asking what
  /// becomes of each sub-goal left open: done, missed, obsolete, or moved
  /// elsewhere. Done waits for its required sub-goals. With [also]
  /// changed in it too.
  Future<void> close(
    Goal goal,
    String status, {
    Map<String, Object?> also = const {},
  }) async {
    final tree = this.tree;
    if (status == 'done') {
      final needed = requiredOpen(tree, goal);
      if (needed.isNotEmpty) {
        await _confirm(
          title: "${goalTitle(goal)} isn't done yet",
          text:
              'It needs ${needed.map((g) => '“${goalTitle(g)}”').join(', ')} '
              'done first (or marked missed or obsolete).',
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
      editing(
        tree,
        goal,
        also,
        status: status,
        leftovers: leftovers,
        made: made,
      ),
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
      for (final g in byPriority(level, tree)) {
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
              child: HotkeyItems(
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
/// closed as [status]: done, missed, obsolete or moved -- picked where to with
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
                  ButtonSegment(value: 'missed', label: Text('Missed')),
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
