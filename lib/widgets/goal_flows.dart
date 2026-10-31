import 'package:flutter/material.dart';

import 'day_picker.dart';
import 'durations.dart';
import '../models/event.dart';
import '../models/goal.dart';
import '../models/goal_activation.dart';
import '../models/goal_changes.dart';
import '../services/goal_drafts.dart';
import '../services/goals_repository.dart';
import '../services/plan_memory.dart';
import 'error_sheet.dart';
import 'goal_editor.dart';
import 'goal_fields.dart' show deadlineAt, pickDeadline;
import 'goal_icon.dart';
import 'goal_sheet.dart';
import 'goal_starts.dart';
import 'hotkeys.dart';

/// Asks which day to try a goal again by -- tomorrow to start with, no
/// earlier than [today], at the time of day the goal's [deadline] has, if
/// it has one -- and gives the deadline: that day, at the time picked on
/// it, if one is. Null if dismissed.
Future<String?> pickRetryDeadline(
  BuildContext context, {
  required DateTime today,
  String? deadline,
}) async {
  final start = DateTime(today.year, today.month, today.day);
  final due = deadlineEnd(deadline);
  final picked = await showDayTimePicker(
    context,
    initialDate: DateTime(start.year, start.month, start.day + 1),
    initialTime: due != null && deadlineHasTime(deadline)
        ? TimeOfDay.fromDateTime(due)
        : null,
    firstDate: start,
    lastDate: DateTime(start.year + 10),
    helpText: 'Try again by',
  );
  return picked == null ? null : deadlineAt(picked);
}

/// Adds a goal in a New goal sheet, saved through [repository] and shown
/// in [memory], starting with [title] and due on [day], if given -- or,
/// from its More, the full New goal page. Its Under picker adds a goal
/// for it to go under the same way, in a sheet over it, kept as no
/// draft. Returns it as saved; null if it was called off.
Future<Goal?> addGoalInSheet(
  BuildContext context, {
  required GoalsRepository repository,
  required PlanMemory memory,
  GoalDrafts? drafts,
  String? title,
  DateTime? day,
  VoidCallback? onFieldFocused,
}) async {
  GoalActions actions() =>
      GoalActions(context: context, repository: repository, memory: memory);
  Goal? added;
  final result = await showAddGoalSheet(
    context,
    keep: (fields) async => added = await actions().create(fields),
    goals: memory.goals ?? const [],
    drafts: drafts,
    title: title,
    day: day,
    addParent: (title, day) => addGoalFor(
      context,
      repository: repository,
      memory: memory,
      title: title,
      day: day,
    ),
    onFieldFocused: onFieldFocused,
  );
  if (result is! MoreGoal || !context.mounted) return added;
  final goalActions = actions();
  return goalActions.add(
    parent: goalActions.tree[result.parentId],
    title: result.title,
    deadline: result.deadline,
    description: result.description,
    descriptionFormat: result.descriptionFormat,
    priority: result.priority,
    withWhom: result.withWhom,
    forWhom: result.forWhom,
  );
}

/// Adds a goal from a picker, as [addGoalInSheet] does, named [title] as
/// it's typed there (nothing, if it's blank) and due on [day]: the goal
/// added, and every goal there is now; null if it was called off.
Future<GoalAdded?> addGoalFor(
  BuildContext context, {
  required GoalsRepository repository,
  required PlanMemory memory,
  required String title,
  DateTime? day,
}) async {
  final added = await addGoalInSheet(
    context,
    repository: repository,
    memory: memory,
    title: title.isEmpty ? null : title,
    day: day,
  );
  if (added == null) return null;
  return (added: added, goals: memory.goals ?? const []);
}

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
  /// which, under [title], and saves nothing. True if they're saved. A
  /// goal created on its own is given to [onCreated], as the server has it.
  Future<bool> save(
    String title,
    List<GoalChange> changes, {
    ValueChanged<Goal>? onCreated,
  }) async {
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
            onCreated?.call(created);
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

  /// Shows [made] in [memory] at once -- with each goal waiting for what
  /// it closed activated, as the server will, and a word that it is --
  /// then the goals as the server has them, best effort.
  void _shown(List<GoalChange> made) {
    final waited = {
      for (final g in goals)
        if (g.activateWhen != null && g.inactive) g.id,
    };
    final (shown, started) = startingWaiting(
      applied(goals, made, now: now()),
      now(),
    );
    memory.showGoals(shown);
    memory.loadGoals(repository, again: true).ignore();
    final names = [
      for (final id in started)
        if (waited.contains(id)) goalTitle(GoalTree(shown)[id]!),
    ];
    if (names.isEmpty || !context.mounted) return;
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(
        content: Text(
          names.length == 1
              ? '“${names.single}” is now active'
              : '${names.length} goals waiting on it are now active: '
                    '${names.map((n) => '“$n”').join(', ')}',
        ),
      ),
    );
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
  /// [title], [deadline], [description] (written in [descriptionFormat])
  /// and [priority], and the
  /// people and circles it's done with ([withWhom]) and for ([forWhom]),
  /// if they're given. Returns it as saved; null if it wasn't.
  Future<Goal?> add({
    Goal? parent,
    String? title,
    String? deadline,
    String? description,
    TextFormat? descriptionFormat,
    int? priority,
    List<Named> withWhom = const [],
    List<Named> forWhom = const [],
  }) async {
    final fields = await showGoalEditor(
      context,
      parent: parent,
      goals: goals,
      title: title,
      deadline: deadline,
      description: description,
      descriptionFormat: descriptionFormat,
      priority: priority,
      withWhom: withWhom,
      forWhom: forWhom,
      now: now,
    );
    if (fields == null || !context.mounted) return null;
    Goal? added;
    await save("Couldn't add the goal", [
      GoalCreate(Goal.fromJson({'id': '', ...fields})),
    ], onCreated: (goal) => added = goal);
    return added;
  }

  /// Adds the goal that comes after [goal]: under the same parent,
  /// inactive, waiting for [goal] to close, and due a week after it
  /// starts -- each changed as the editor's opened with it.
  Future<Goal?> addNext(Goal goal) async {
    final fields = await showGoalEditor(
      context,
      parent: tree[goal.parentId],
      goals: goals,
      status: 'inactive',
      activateWhen: {
        'after': [
          {'goal_closed': goal.id},
        ],
      },
      deadlineRule: const {
        'after_start': {'days': 7},
      },
      priority: goal.priority,
      now: now,
    );
    if (fields == null || !context.mounted) return null;
    Goal? added;
    await save("Couldn't add the next goal", [
      GoalCreate(Goal.fromJson({'id': '', ...fields})),
    ], onCreated: (g) => added = g);
    return added;
  }

  /// Adds a goal made of [fields], from the New goal sheet: shown in
  /// [memory] at once. Returns it as saved; throws if it can't be.
  Future<Goal> create(Map<String, Object?> fields) async {
    final created = await repository.createGoal(
      Goal.fromJson({'id': '', ...fields}),
    );
    _shown([GoalCreate(created)]);
    return created;
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

  /// Sets [goal]'s status to [status], with what that takes: asking for
  /// its deadline, or deciding what becomes
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

  /// Activates [picked] -- just them: the inactive parents they're under
  /// stay inactive -- asking for each one's deadline that has none -- from
  /// [at], if it's given (an event's start, say): then each is backdated
  /// to it, or to its last change, if that's later. An [at] still to come
  /// leaves them inactive, waiting for it ([waitingFor]). With [also], the
  /// one picked has that changed in it too.
  Future<void> activate(
    List<Goal> picked, {
    DateTime? at,
    Map<String, Object?> also = const {},
  }) async {
    if (at != null && at.isAfter(now()) && also.isEmpty) {
      await save(
        picked.length == 1
            ? "Couldn't set when ${goalTitle(picked.single)} starts"
            : "Couldn't set when the goals start",
        waitingFor(picked, at),
      );
      return;
    }
    final tree = also.isEmpty
        ? this.tree
        : GoalTree(
            applied(goals, [GoalUpdate(picked.single.id, also)], now: now()),
          );
    picked = [for (final g in picked) tree[g.id] ?? g];
    final deadlines = await _askDeadlines(picked, tree);
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
  /// that's later -- rather than now; never after now.
  GoalChange _backdated(GoalChange change, DateTime at) {
    if (change is! GoalUpdate) return change;
    final goal = tree[change.id];
    if (goal == null) return change;
    final when = backdatedTo(goal, at, now: now());
    return GoalUpdate(change.id, {
      ...change.changes,
      'history': [
        for (final c in goal.history) c.toJson(),
        StatusChange(
          'active',
          when,
          deadline: change.changes['deadline'] as String? ?? goal.deadline,
        ).toJson(),
      ],
    });
  }

  /// Marks [goal] missed and tries it again by a day picked -- at the
  /// time it was due, if it was due at one -- as one change, so its
  /// history keeps the deadline it missed and it stays open, as it was
  /// ([retrying]). Nothing for a goal with no deadline.
  Future<void> retry(Goal goal) async {
    if (goal.due == null || goal.closed) return;
    final deadline = await pickRetryDeadline(
      context,
      today: now(),
      deadline: goal.deadline,
    );
    if (deadline == null || !context.mounted) return;
    await save(
      "Couldn't try ${goalTitle(goal)} again",
      retrying(goal, deadline, now: now()),
    );
  }

  /// Deactivates [goal] -- just it: its active sub-goals stay active --
  /// with [also] changed in it too.
  Future<void> deactivate(
    Goal goal, {
    Map<String, Object?> also = const {},
  }) async {
    await save(
      "Couldn't deactivate ${goalTitle(goal)}",
      editing(tree, goal, also, status: 'inactive'),
    );
  }

  /// Deactivates [goal] until what's picked comes ([pickDeactivateUntil]):
  /// inactive, waiting for it before it's activated again.
  Future<void> deactivateUntil(Goal goal) async {
    final when = await pickDeactivateUntil(
      context,
      goal: goal,
      goals: goals,
      now: now,
    );
    if (when == null || !context.mounted) return;
    await deactivate(goal, also: {'activate_when': when});
  }

  /// Marks [goal] [status] ("done", "missed" or "obsolete"), asking for a
  /// note to keep with the change (why, say) and what becomes of each
  /// sub-goal left open: done, missed, obsolete, or moved elsewhere. Done
  /// waits for its required sub-goals. With [also] changed in it too.
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
    String? note;
    if (open.isNotEmpty) {
      final decided = await _decideLeftovers(goal, status, open, tree);
      if (decided == null || !context.mounted) return;
      (leftovers, made, note) = decided;
    } else {
      final asked = await _askNote(goal, status);
      if (asked == null || !context.mounted) return;
      note = asked.note;
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
        note: note,
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
    final day = await showDayPicker(
      context,
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
            (i == index
                    ? StatusChange(
                        c.status,
                        when,
                        deadline: c.deadline,
                        note: c.note,
                      )
                    : c)
                .toJson(),
        ],
      }),
    ]);
  }

  /// Changes the note on [goal]'s history entry [index]: adds one, or,
  /// left blank, takes it off.
  Future<void> annotate(Goal goal, int index) async {
    final entry = goal.history[index];
    final asked = await showDialog<({String? note})>(
      context: context,
      builder: (context) => _NoteDialog(
        title:
            'Note on “${goalTitle(goal)}” '
            '${goalStatuses[entry.status]?.toLowerCase() ?? entry.status}',
        action: 'Save',
        initial: entry.note,
      ),
    );
    if (asked == null || !context.mounted) return;
    await save("Couldn't change the note", [
      GoalUpdate(goal.id, {
        'history': [
          for (final (i, c) in goal.history.indexed)
            (i == index
                    ? StatusChange(
                        c.status,
                        c.at,
                        deadline: c.deadline,
                        note: asked.note,
                      )
                    : c)
                .toJson(),
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
        if (g.deadline == null && g.deadlineRule == null) g,
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
  /// Asks for a note to keep with marking [goal] [status] -- why, say.
  /// Gives it (none, left blank), or null if it's called off.
  Future<({String? note})?> _askNote(Goal goal, String status) =>
      showDialog<({String? note})>(
        context: context,
        builder: (context) => _NoteDialog(
          title: 'Mark ${goalTitle(goal)} $status',
          action: 'Mark $status',
        ),
      );

  Future<(Map<String, Leftover>, Goal?, String?)?> _decideLeftovers(
    Goal goal,
    String status,
    List<Goal> open,
    GoalTree tree,
  ) => showDialog<(Map<String, Leftover>, Goal?, String?)>(
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
    final picked = await pickDeadline(
      context,
      deadline: _picked[goal.id],
      initialDate: now,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 20),
    );
    if (picked != null && mounted) {
      setState(() => _picked[goal.id] = picked);
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
/// [pick] -- and a note to keep with the change. Gives them by id, with
/// any new top-level goal made for them, and the note (null for none).
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
  final _note = TextEditingController();

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  /// The goal made for sub-goals to move under, while any still does.
  Goal? get _madeUsed =>
      _chosen.values.whereType<MoveLeftover>().any(
        (m) => m.to != null && m.to == _made?.id,
      )
      ? _made
      : null;

  void _submit() =>
      Navigator.of(context).pop((_chosen, _madeUsed, _statusNote(_note)));

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
            const SizedBox(height: 16),
            _StatusNoteField(controller: _note, onSubmitted: _submit),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: Text('Mark ${widget.status}')),
      ],
    );
  }
}

/// A note to keep with a goal's status change -- why it's done, say --
/// asked for under [title], [action] going on with it (none, left
/// blank) and Cancel calling it off: gives `(note: ...)`, or null.
/// [initial] is the note as it is, to change.
class _NoteDialog extends StatefulWidget {
  const _NoteDialog({required this.title, required this.action, this.initial});

  final String title;
  final String action;
  final String? initial;

  @override
  State<_NoteDialog> createState() => _NoteDialogState();
}

class _NoteDialogState extends State<_NoteDialog> {
  late final _note = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  void _submit() => Navigator.of(context).pop((note: _statusNote(_note)));

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: SizedBox(
      width: 440,
      child: _StatusNoteField(controller: _note, onSubmitted: _submit),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Cancel'),
      ),
      FilledButton(onPressed: _submit, child: Text(widget.action)),
    ],
  );
}

/// The field for a note on a goal's status change, focused as it's
/// shown: optional, and Enter in it calls [onSubmitted].
class _StatusNoteField extends StatelessWidget {
  const _StatusNoteField({required this.controller, required this.onSubmitted});

  final TextEditingController controller;
  final VoidCallback onSubmitted;

  @override
  Widget build(BuildContext context) => TextField(
    controller: controller,
    autofocus: true,
    decoration: const InputDecoration(
      labelText: 'Note',
      border: OutlineInputBorder(),
    ),
    textInputAction: TextInputAction.done,
    onSubmitted: (_) => onSubmitted(),
  );
}

/// What [note] holds, trimmed; null for nothing.
String? _statusNote(TextEditingController note) => switch (note.text.trim()) {
  '' => null,
  final text => text,
};
