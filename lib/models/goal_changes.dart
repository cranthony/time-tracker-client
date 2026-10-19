import 'goal.dart';

/// One goal's part of a change to several: made, changed or deleted.
/// A change to several goals is a list of these, in the order they're
/// saved -- each leaving the goals as the server's rules want them, so
/// none is refused (see [planned]).
sealed class GoalChange {
  const GoalChange();
}

/// A goal made: [goal], with an id of its own, its history to come.
class GoalCreate extends GoalChange {
  const GoalCreate(this.goal);
  final Goal goal;
}

/// Goal [id]'s [changes], keyed as `update_goal` takes them: a null
/// clears a field.
class GoalUpdate extends GoalChange {
  const GoalUpdate(this.id, this.changes);
  final String id;
  final Map<String, Object?> changes;
}

/// Goal [id] deleted.
class GoalDelete extends GoalChange {
  const GoalDelete(this.id);
  final String id;
}

/// Several [changes], made at once ([GoalsRepository.changeGoals]): to
/// [planned], one step, so only the goals after all of them are checked.
class GoalBatch extends GoalChange {
  const GoalBatch(this.changes);
  final List<GoalChange> changes;
}

/// [changes], each goal named by [ids] (a goal made here, by the id it
/// was given in place of its own) named so instead -- itself, and as a
/// parent.
List<GoalChange> renamed(List<GoalChange> changes, Map<String, String> ids) {
  String name(String id) => ids[id] ?? id;
  return [
    for (final c in changes)
      switch (c) {
        GoalCreate(:final goal) => GoalCreate(
          Goal.fromJson({
            ...goal.toJson(),
            'id': name(goal.id),
            'parent_id': ?switch (goal.parentId) {
              final p? => name(p),
              null => null,
            },
          }),
        ),
        GoalUpdate(:final id, :final changes) => GoalUpdate(name(id), {
          for (final MapEntry(:key, :value) in changes.entries)
            key: key == 'parent_id' && value is String ? name(value) : value,
        }),
        GoalDelete(:final id) => GoalDelete(name(id)),
        GoalBatch(changes: final several) => GoalBatch(renamed(several, ids)),
      },
  ];
}

/// [goals] once [changes] are made, in order, a status changed at [now]
/// added to the goal's history as the server adds it.
List<Goal> applied(
  List<Goal> goals,
  List<GoalChange> changes, {
  required DateTime now,
}) {
  final out = [...goals];
  for (final change in changes) {
    switch (change) {
      case GoalCreate(:final goal):
        out.add(
          goal.history.isEmpty
              ? Goal.fromJson({
                  ...goal.toJson(),
                  'history': [StatusChange(goal.status, now).toJson()],
                })
              : goal,
        );
        final followed = followingParents(out);
        out
          ..clear()
          ..addAll(followed);
      case GoalUpdate(:final id, :final changes):
        final i = out.indexWhere((g) => g.id == id);
        if (i < 0) continue;
        final before = out[i];
        final json = {...before.toJson(), ...changes}
          ..removeWhere((_, v) => v == null);
        // A deadline of its own unties it from its parent's.
        if (changes.containsKey('deadline') &&
            !changes.containsKey('deadline_offset_minutes')) {
          json.remove('deadline_offset_minutes');
        }
        if (!changes.containsKey('history') &&
            json['status'] != before.status) {
          json['history'] = [
            for (final c in before.history) c.toJson(),
            StatusChange(json['status'] as String, now).toJson(),
          ];
        }
        out[i] = Goal.fromJson(json);
        final followed = followingParents(out);
        out
          ..clear()
          ..addAll(followed);
      case GoalDelete(:final id):
        out.removeWhere((g) => g.id == id);
      case GoalBatch(changes: final several):
        final after = applied(out, several, now: now);
        out
          ..clear()
          ..addAll(after);
    }
  }
  return out;
}

/// What's wrong with [goals] after [changes] -- after each one, in turn,
/// since each is saved on its own -- that wasn't wrong before; empty if
/// they can be saved.
List<String> planned(
  List<Goal> goals,
  List<GoalChange> changes, {
  required DateTime now,
}) {
  final before = goalProblems(goals).toSet();
  var at = goals;
  final problems = <String>{};
  for (final change in changes) {
    at = applied(at, [change], now: now);
    problems.addAll(goalProblems(at).where((p) => !before.contains(p)));
  }
  return problems.toList();
}

// -- The changes the Goals pages make -------------------------------------

/// What a sub-goal left open, as its parent's closed, comes to: done,
/// missed, obsolete, or moved under another goal (or the top level, with no
/// [to]).
sealed class Leftover {
  const Leftover();
}

class CloseLeftover extends Leftover {
  const CloseLeftover(this.status);

  /// "done", "missed" or "obsolete".
  final String status;
}

class MoveLeftover extends Leftover {
  const MoveLeftover({this.to, this.fit = const {}});

  /// The goal it goes under; null for the top level.
  final String? to;

  /// What else of it changes, to fit under [to] (see [fitUnder]).
  final Map<String, Object?> fit;
}

/// What of [goal] has to change for it to fit under [parent]: an earlier
/// deadline, a shorter expected time, or -- under an inactive parent --
/// inactive itself. Empty if it fits as it is.
Map<String, Object?> fitUnder(Goal goal, Goal? parent) {
  if (parent == null || goal.closed) return const {};
  return {
    // One that follows its parent's deadline moves with it.
    if ((goal.due, parent.due) case (final due?, final parentDue?)
        when due.isAfter(parentDue) && !goal.followsParent)
      'deadline': parent.deadline,
    if ((goal.expectedMinutes, parent.expectedMinutes)
        case (final m?, final pm?) when m > pm)
      'expected_minutes': pm,
    if (goal.active && parent.inactive) 'status': 'inactive',
  };
}

/// [goal] and its open sub-goals, at any depth, set to [status], deepest
/// first: closing a goal closes what's left open under it.
List<GoalChange> closingAll(GoalTree tree, Goal goal, String status) => [
  for (final g in tree.descendantsOf(goal.id).reversed)
    if (g.open) GoalUpdate(g.id, {'status': status}),
  if (goal.status != status) GoalUpdate(goal.id, {'status': status}),
];

/// Closes [goal] as [status] ("done", "missed" or "obsolete"), with each of its
/// open sub-goals ending as [leftovers] says, by id -- and [made], a goal
/// made for some of them to move under, made first. In the order the
/// server takes them: what's made, then what's moved, then what's
/// closed, deepest first, [goal] last.
List<GoalChange> closing(
  GoalTree tree,
  Goal goal,
  String status, {
  Map<String, Leftover> leftovers = const {},
  Goal? made,
}) {
  final moves = <GoalChange>[];
  final closes = <GoalChange>[];
  for (final child in tree.childrenOf(goal.id)) {
    if (child.closed) continue;
    switch (leftovers[child.id] ?? CloseLeftover(status)) {
      case MoveLeftover(:final to, :final fit):
        moves.add(GoalUpdate(child.id, {'parent_id': to, ...fit}));
      case CloseLeftover(status: final s):
        closes.addAll(closingAll(tree, child, s));
    }
  }
  return [
    if (made != null) GoalCreate(made),
    ...moves,
    ...closes,
    GoalUpdate(goal.id, {'status': status}),
  ];
}

/// The open sub-goals [goal] needs done before it can be: its required
/// ones. One that was missed or made obsolete doesn't hold it up.
List<Goal> requiredOpen(GoalTree tree, Goal goal) => [
  for (final c in tree.childrenOf(goal.id))
    if (c.required && c.open) c,
];

/// Activates [goals], each with the deadline [deadlines] gives by id
/// (kept, if it gives none), and any inactive parents they're under,
/// outermost first -- so each is active under an active parent.
List<GoalChange> activating(
  GoalTree tree,
  Iterable<Goal> goals, {
  Map<String, String> deadlines = const {},
}) {
  final order = <String>[];
  for (final goal in goals) {
    for (final g in [...tree.ancestorsOf(goal.id), goal]) {
      if (!g.active && !order.contains(g.id)) order.add(g.id);
    }
  }
  // Outermost first.
  order.sort((a, b) => tree.depthOf(a).compareTo(tree.depthOf(b)));
  return [
    for (final id in order)
      GoalUpdate(id, {'status': 'active', 'deadline': ?deadlines[id]}),
  ];
}

/// The inactive parents [goals] are under, which activating them
/// activates too: outermost first.
List<Goal> inactiveParents(GoalTree tree, Iterable<Goal> goals) {
  final out = <String, Goal>{};
  for (final goal in goals) {
    for (final g in tree.ancestorsOf(goal.id)) {
      if (!g.active && !g.closed) out[g.id] = g;
    }
  }
  return out.values.toList()
    ..sort((a, b) => tree.depthOf(a.id).compareTo(tree.depthOf(b.id)));
}

/// Deactivates [goal] and its active sub-goals, deepest first.
List<GoalChange> deactivating(GoalTree tree, Goal goal) => [
  for (final g in tree.descendantsOf(goal.id).reversed)
    if (g.active) GoalUpdate(g.id, {'status': 'inactive'}),
  GoalUpdate(goal.id, {'status': 'inactive'}),
];

/// Moves [goal] under [to] (the top level, if null), changing what has to
/// change for it to fit ([fitUnder]) -- and, under an inactive parent, its
/// active sub-goals deactivated first.
List<GoalChange> moving(GoalTree tree, Goal goal, String? to, {Goal? made}) {
  final parent = made ?? tree[to];
  final fit = fitUnder(goal, parent);
  return [
    if (made != null) GoalCreate(made),
    if (fit['status'] == 'inactive')
      for (final g in tree.descendantsOf(goal.id).reversed)
        if (g.active) GoalUpdate(g.id, {'status': 'inactive'}),
    GoalUpdate(goal.id, {'parent_id': to, ...fit}),
  ];
}

/// Deletes [goal]: with its sub-goals, deepest first -- or, with
/// [moveTo] given (null for the top level), its sub-goals moved there
/// first. [keep] says whether the sub-goals are kept (moved) at all.
List<GoalChange> deleting(
  GoalTree tree,
  Goal goal, {
  bool keep = false,
  String? moveTo,
}) {
  final children = tree.childrenOf(goal.id);
  return [
    if (keep)
      for (final c in children) ...moving(tree, c, moveTo)
    else
      for (final g in tree.descendantsOf(goal.id).reversed) GoalDelete(g.id),
    GoalDelete(goal.id),
  ];
}

/// [changes] with [fields] changed in goal [id] too: in its own update,
/// if there's one, or else first.
List<GoalChange> withFields(
  List<GoalChange> changes,
  String id,
  Map<String, Object?> fields,
) {
  if (fields.isEmpty) return changes;
  final i = changes.indexWhere((c) => c is GoalUpdate && c.id == id);
  if (i < 0) return [GoalUpdate(id, fields), ...changes];
  return [
    for (final (j, c) in changes.indexed)
      if (j == i)
        GoalUpdate(id, {...fields, ...(c as GoalUpdate).changes})
      else
        c,
  ];
}

/// [goal] edited: [fields] changed, and its status set to [status], with
/// what that takes ([activating], [deactivating] or [closing]) -- each
/// inactive parent given the deadline [deadlines] says, and each open
/// sub-goal ending as [leftovers] says (closed as it is, by default).
List<GoalChange> editing(
  GoalTree tree,
  Goal goal,
  Map<String, Object?> fields, {
  String? status,
  Map<String, String> deadlines = const {},
  Map<String, Leftover> leftovers = const {},
  Goal? made,
}) => withFields(
  switch (status) {
    null => const [],
    final s when s == goal.status => const [],
    'active' => activating(tree, [goal], deadlines: deadlines),
    'inactive' => deactivating(tree, goal),
    final s => closing(tree, goal, s, leftovers: leftovers, made: made),
  },
  goal.id,
  fields,
);

/// The end of [now]'s day, as a deadline: "End of today".
String endOfToday(DateTime now) => deadlineOf(now);

/// The end of [now]'s week -- its Sunday -- as a deadline: "End of this
/// week".
String endOfWeek(DateTime now) =>
    deadlineOf(DateTime(now.year, now.month, now.day + (7 - now.weekday)));
