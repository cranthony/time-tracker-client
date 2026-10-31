import 'goal.dart';

/// What an inactive goal waits for before it's activated
/// ([Goal.activateWhen]), as the server keeps it -- `{after: [{goal_closed:
/// id} | {at: date or date and time}], delay: "next_day" | {minutes},
/// hold_while: [{active_at_least, priority?: {at_or_above | exactly: a
/// priority or "own"}}]}` -- and how the server goes by it, mirrored so the
/// app shows what it will do before it's read back.

/// The ids of the goals [goal] waits to close.
List<String> waitsFor(Goal goal) => [
  for (final t in goal.activateWhen?['after'] as List? ?? const [])
    if (t case {'goal_closed': final String id}) id,
];

/// The times [goal] waits for: dates ("2026-11-02", from its start) or
/// dates and times.
List<String> waitsUntil(Goal goal) => [
  for (final t in goal.activateWhen?['after'] as List? ?? const [])
    if (t case {'at': final String at}) at,
];

/// Whether [goal] waits until the day after the last of what it waits for.
bool waitsNextDay(Goal goal) => goal.activateWhen?['delay'] == 'next_day';

/// How many minutes [goal] waits after the last of what it waits for, if
/// it's given in minutes.
int? delayMinutes(Goal goal) => switch (goal.activateWhen?['delay']) {
  {'minutes': final num m} => m.toInt(),
  _ => null,
};

/// The goals in [goals] still waiting for goal [id] to close.
List<Goal> waitingOn(Iterable<Goal> goals, String id) => [
  for (final g in goals)
    if (g.inactive && waitsFor(g).contains(id)) g,
];

/// When a time [at] that a goal waits for comes: a date's at its start.
DateTime? startOf(String at) {
  final text = at.trim();
  if (RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(text)) {
    final end = deadlineEnd(text);
    return end == null ? null : DateTime(end.year, end.month, end.day - 1);
  }
  return deadlineEnd(text);
}

DateTime _delayed(DateTime at, Object? delay) => switch (delay) {
  'next_day' => DateTime(at.year, at.month, at.day + 1),
  {'minutes': final num m} => at.add(Duration(minutes: m.toInt())),
  _ => at,
};

/// When [goal] is ready to be activated: the last of what it waits for,
/// then its delay -- or, waiting for nothing, from its last change. Null
/// while a goal it waits for is open (or isn't a goal).
DateTime? readyAt(Goal goal, GoalTree tree) {
  final when = goal.activateWhen;
  if (when == null) return null;
  DateTime? last;
  for (final t in when['after'] as List? ?? const []) {
    final DateTime came;
    switch (t) {
      case {'goal_closed': final String id}:
        final closed = tree[id]?.closedAt;
        if (closed == null) return null;
        came = closed;
      case {'at': final String at}:
        final start = startOf(at);
        if (start == null) return null;
        came = start;
      default:
        continue;
    }
    if (last == null || came.isAfter(last)) last = came;
  }
  final since = last ?? goal.history.lastOrNull?.at;
  return since == null ? null : _delayed(since, when['delay']);
}

/// When [goal], waiting, is expected to be activated: the server's word
/// ([Goal.expectedStart]) if it gave it, or else when what it waits for
/// is expected to come -- each goal it waits for by the deadline it's
/// due by (or is expected to have) -- then its delay. Null if something
/// it waits for has no deadline to go by, or it's ready by [now] already
/// (so it's held back).
DateTime? expectedStart(
  Goal goal,
  GoalTree tree, {
  required DateTime now,
  int depth = 0,
}) {
  if (goal.expectedStart case final at? when depth == 0) return startOf(at);
  final when = goal.activateWhen;
  if (!goal.inactive || when == null || depth > tree.byId.length) return null;
  DateTime? last;
  // A goal expected to close by its deadline closes within its day, not
  // at the midnight after: the day after is the one after that.
  var byDeadline = false;
  for (final t in when['after'] as List? ?? const []) {
    final DateTime comes;
    switch (t) {
      case {'goal_closed': final String id}:
        final other = tree[id];
        if (other == null) return null;
        if (other.closedAt case final closed?) {
          comes = closed;
        } else {
          final due = deadlineEnd(
            expectedDeadline(other, tree, now: now, depth: depth + 1),
          );
          if (due == null) return null;
          comes = due;
          if (last == null || !comes.isBefore(last)) byDeadline = true;
        }
      case {'at': final String at}:
        final start = startOf(at);
        if (start == null) return null;
        comes = start;
        if (last == null || comes.isAfter(last)) byDeadline = false;
      default:
        continue;
    }
    if (last == null || comes.isAfter(last)) last = comes;
  }
  final from = last ?? now;
  final at = when['delay'] == 'next_day' && byDeadline
      ? _delayed(from.subtract(const Duration(minutes: 1)), 'next_day')
      : _delayed(from, when['delay']);
  return at.isAfter(now) ? at : null;
}

/// [goal]'s deadline, or, waiting for one -- measured from a start that
/// hasn't come -- the one it's expected to have.
String? expectedDeadline(
  Goal goal,
  GoalTree tree, {
  required DateTime now,
  int depth = 0,
}) {
  if (goal.deadline case final d?) return d;
  if (depth > tree.byId.length) return null;
  switch (goal.deadlineRule) {
    case {'after_start': final Map offset}:
      final start = expectedStart(goal, tree, now: now, depth: depth + 1);
      if (start == null) return null;
      return switch (offset) {
        {'days': final num d} => deadlineOf(
          DateTime(start.year, start.month, start.day + d.toInt()),
        ),
        {'minutes': final num m} => deadlineOf(
          start.add(Duration(minutes: m.toInt())),
          time: true,
        ),
        _ => null,
      };
    case {'after_goal': {'id': final String id} && final Map offset}:
      final other = tree[id];
      final base = other == null
          ? null
          : expectedDeadline(other, tree, now: now, depth: depth + 1);
      final end = deadlineEnd(base);
      if (base == null || end == null) return null;
      return switch (offset) {
        {'days': final num d} when !deadlineHasTime(base) => deadlineOf(
          DateTime(end.year, end.month, end.day - 1 + d.toInt()),
        ),
        {'days': final num d} => deadlineOf(
          end.add(Duration(days: d.toInt())),
          time: true,
        ),
        {'minutes': final num m} => deadlineOf(
          end.add(Duration(minutes: m.toInt())),
          time: true,
        ),
        _ => null,
      };
  }
  return null;
}

/// Whether [other] is [goal] or one of its parents or sub-goals, in
/// [tree]: what a hold of [goal]'s doesn't count.
bool _kin(Goal goal, Goal other, GoalTree tree) =>
    other.id == goal.id ||
    tree.ancestorsOf(goal.id).any((g) => g.id == other.id) ||
    tree.ancestorsOf(other.id).any((g) => g.id == goal.id);

/// Whether one of [goal]'s holds holds it back: at least that many other
/// goals of the priority it names are active, its parents and sub-goals
/// not counted.
bool isHeld(Goal goal, GoalTree tree) => holding(goal, tree) != null;

/// The first of [goal]'s holds that holds it back ([isHeld]); null if none
/// does.
Map? holding(Goal goal, GoalTree tree) {
  final holds = goal.activateWhen?['hold_while'] as List? ?? const [];
  final own = tree.priorityOf(goal.id);
  int level(Object? p) => p == 'own' ? own : (p as num).toInt();
  for (final hold in holds) {
    if (hold is! Map) continue;
    final least = (hold['active_at_least'] as num?)?.toInt() ?? 1;
    bool fits(Goal g) {
      final p = tree.priorityOf(g.id);
      return switch (hold['priority']) {
        {'at_or_above': final Object r} => p <= level(r),
        {'exactly': final Object r} => p == level(r),
        _ => true,
      };
    }

    final active = tree.byId.values.where(
      (g) => g.active && !_kin(goal, g, tree) && fits(g),
    );
    if (active.length >= least) return hold;
  }
  return null;
}

/// [goals] with each inactive goal whose activate_when is ready by [now],
/// and isn't held, activated -- just it: its inactive parents stay so --
/// as the server does: the highest priority first, then the soonest due, each
/// counted in the holds of the next, dated when it became ready (never
/// before its last change), what it waited for cleared. One that would
/// start past its own deadline keeps waiting. With the ids of those
/// activated.
(List<Goal>, List<String>) startingWaiting(List<Goal> goals, DateTime now) {
  var out = [...goals];
  final activated = <String>[];
  for (var round = 0; round < goals.length; round++) {
    final tree = GoalTree(out);
    final ready = <(Goal, DateTime)>[];
    for (final g in out) {
      if (!g.inactive || g.activateWhen == null) continue;
      final at = readyAt(g, tree);
      if (at == null || at.isAfter(now) || isHeld(g, tree)) continue;
      final last = g.history.lastOrNull?.at;
      var when = last != null && last.isAfter(at) ? last : at;
      if (when.isAfter(now)) when = now;
      final fits = switch (g.due) {
        final due? => due.isAfter(when),
        null => g.deadlineRule != null,
      };
      if (fits) ready.add((g, when));
    }
    if (ready.isEmpty) break;
    ready.sort((a, b) {
      final byPriority = tree
          .priorityOf(a.$1.id)
          .compareTo(tree.priorityOf(b.$1.id));
      return byPriority != 0 ? byPriority : compareByDeadline(a.$1, b.$1);
    });
    final (goal, startAt) = ready.first;
    final ids = {goal.id};
    out = followingParents([
      for (final g in out)
        if (!ids.contains(g.id))
          g
        else
          Goal.fromJson({
            ...g.toJson()..remove('activate_when'),
            'status': 'active',
            'history': [
              for (final c in g.history) c.toJson(),
              StatusChange('active', startAt, deadline: g.deadline).toJson(),
            ],
            'path': g.path,
          }),
    ]);
    activated.addAll(ids);
  }
  // Each activation's history entry carries the deadline it then has.
  if (activated.isNotEmpty) {
    out = [
      for (final g in out)
        if (activated.contains(g.id) && g.history.isNotEmpty)
          Goal.fromJson({
            ...g.toJson(),
            'history': [
              for (final c in g.history.take(g.history.length - 1)) c.toJson(),
              StatusChange(
                'active',
                g.history.last.at,
                deadline: g.deadline,
              ).toJson(),
            ],
            'path': g.path,
          })
        else
          g,
    ];
  }
  return (out, activated);
}
