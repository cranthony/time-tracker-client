import 'dart:convert';

import 'goal.dart';
import 'goal_activation.dart';
import 'goal_changes.dart';

/// Queues of goals: the backlog. A queue is goals each waiting
/// (`activate_when: {after: [{goal_closed: <the one ahead>}]}`) for the
/// one ahead of it to close, so each starts as the one ahead closes. It's
/// a tree: a goal two wait for is a fork, its branches starting together
/// when it closes. A goal waiting for several sits behind the one of them
/// expected to close last ([QueueNode.alsoWaitsFor] the others).

/// How a queue's front goal waits: what starts the queue.
enum QueueFront {
  /// It's being worked on: the next starts as it closes.
  active,

  /// Inactive, waiting for nothing: held till it's started by hand.
  onHold,

  /// Inactive, waiting for a time to come (or held while others are
  /// active).
  waiting,

  /// Inactive, waiting for a goal not in any queue shown: a sub-goal of a
  /// goal on hold, say ([GoalQueue.behind]).
  behind,

  /// Inactive, its triggers come: it starts on the next read.
  ready,
}

/// A goal in a queue, with those waiting for it next.
class QueueNode {
  QueueNode(this.goal, {this.alsoWaitsFor = const []});

  final Goal goal;

  /// The other open goals it waits for, besides the one it's behind.
  final List<String> alsoWaitsFor;

  /// Those waiting for it, each the start of a branch if there are
  /// several; in the order they'd start.
  final List<QueueNode> next = [];

  /// It, and every goal behind it, in order: down each branch in turn.
  Iterable<QueueNode> get all sync* {
    yield this;
    for (final n in next) {
      yield* n.all;
    }
  }
}

/// A queue: its [front] and what that waits for.
class GoalQueue {
  GoalQueue(this.front, this.kind, {this.behind});

  final QueueNode front;
  final QueueFront kind;

  /// For [QueueFront.behind], the goal it waits for.
  final Goal? behind;

  /// Every goal in it, front first.
  Iterable<QueueNode> get all => front.all;
}

/// Whether [goal] belongs in a queue at all: open, not made by a habit,
/// and not under an inactive goal -- that comes with its parent.
bool _queueable(Goal goal, GoalTree tree) =>
    goal.open &&
    goal.habitId == null &&
    !tree.ancestorsOf(goal.id).any((g) => g.inactive);

/// The goal [goal] is placed behind: of the open goals it waits for, the
/// one expected to close last (one with no deadline to go by counting as
/// last); null if it waits for none.
Goal? placedBehind(Goal goal, GoalTree tree, {required DateTime now}) {
  if (!goal.inactive) return null;
  Goal? best;
  DateTime? bestDue;
  var bestUnknown = false;
  for (final id in waitsFor(goal)) {
    final other = tree[id];
    if (other == null || other.closed) continue;
    final due = deadlineEnd(expectedDeadline(other, tree, now: now));
    if (best == null) {
      (best, bestDue, bestUnknown) = (other, due, due == null);
      continue;
    }
    if (bestUnknown) continue;
    if (due == null || (bestDue != null && due.isAfter(bestDue))) {
      (best, bestDue, bestUnknown) = (other, due, due == null);
    }
  }
  return best;
}

/// The queues in [goals]: each inactive goal that can be queued, and each
/// active one with something queued behind it, in trees. Active ones
/// first, then the rest by priority and when they're expected to start.
List<GoalQueue> goalQueues(List<Goal> goals, {required DateTime now}) {
  final tree = GoalTree(goals);
  final shown = {
    for (final g in goals)
      if (_queueable(g, tree)) g.id: g,
  };
  final nodes = <String, QueueNode>{};
  final behind = <String, Goal?>{};
  for (final g in shown.values) {
    if (!g.inactive) continue;
    final ahead = placedBehind(g, tree, now: now);
    behind[g.id] = ahead;
    nodes[g.id] = QueueNode(
      g,
      alsoWaitsFor: [
        for (final id in waitsFor(g))
          if (id != ahead?.id && tree[id]?.open == true) id,
      ],
    );
  }
  QueueNode node(Goal g) => nodes[g.id] ??= QueueNode(g);
  final fronts = <QueueNode>[];
  for (final g in [...nodes.values.map((n) => n.goal)]) {
    final ahead = behind[g.id];
    if (ahead != null && shown.containsKey(ahead.id)) {
      node(ahead).next.add(nodes[g.id]!);
    } else {
      fronts.add(nodes[g.id]!);
    }
  }
  for (final g in shown.values) {
    if (g.active && nodes[g.id]?.next.isNotEmpty == true) {
      fronts.add(nodes[g.id]!);
    }
  }
  int byStart(QueueNode a, QueueNode b) {
    final byPriority = tree
        .priorityOf(a.goal.id)
        .compareTo(tree.priorityOf(b.goal.id));
    if (byPriority != 0) return byPriority;
    final sa = expectedStart(a.goal, tree, now: now);
    final sb = expectedStart(b.goal, tree, now: now);
    if (sa != null && sb != null && sa != sb) return sa.compareTo(sb);
    if ((sa == null) != (sb == null)) return sa == null ? 1 : -1;
    return compareByDeadline(a.goal, b.goal);
  }

  for (final n in nodes.values) {
    n.next.sort(byStart);
  }
  QueueFront kindOf(Goal g) {
    if (g.active) return QueueFront.active;
    final when = g.activateWhen;
    if (when == null) return QueueFront.onHold;
    if (behind[g.id] != null) return QueueFront.behind;
    final ready = readyAt(g, tree);
    if (ready != null && !ready.isAfter(now) && !isHeld(g, tree)) {
      return QueueFront.ready;
    }
    return QueueFront.waiting;
  }

  final queues = [
    for (final f in fronts)
      GoalQueue(f, kindOf(f.goal), behind: behind[f.goal.id]),
  ];
  queues.sort((a, b) {
    final activeFirst = (a.kind == QueueFront.active ? 0 : 1).compareTo(
      b.kind == QueueFront.active ? 0 : 1,
    );
    return activeFirst != 0 ? activeFirst : byStart(a.front, b.front);
  });
  return queues;
}

// -- Changing queues --------------------------------------------------------

/// Where a goal goes in a queue: behind [after] (null: at the front, in
/// place of [before]) and ahead of [before], one of those waiting for
/// [after] (null: at the end of a branch, or a new branch of its own).
class QueueSlot {
  const QueueSlot({this.after, this.before})
    : assert(after != null || before != null);

  /// In front of the queue whose front is [front]: it takes its place.
  const QueueSlot.front(String front) : this(before: front);

  final String? after;
  final String? before;
}

/// The goals' statuses and what they wait for, changed on a copy, then
/// given as the changes that make them so.
class _Work {
  _Work(List<Goal> goals)
    : _tree = GoalTree(goals),
      _status = {for (final g in goals) g.id: g.status},
      _when = {for (final g in goals) g.id: g.activateWhen};

  final GoalTree _tree;
  final Map<String, String> _status;
  final Map<String, Map<String, Object?>?> _when;

  List<Map> _after(String id) => [
    for (final t in _when[id]?['after'] as List? ?? const [])
      if (t is Map) t,
  ];

  void _setAfter(String id, List<Map> after) {
    _when[id] = {...?_when[id], 'after': after};
  }

  /// The goals waiting for [id] now.
  List<String> waitingFor(String id) => [
    for (final MapEntry(:key, :value) in _status.entries)
      if (value == 'inactive' && _after(key).any((t) => t['goal_closed'] == id))
        key,
  ];

  /// Takes [id] out of where it waits: what waited for it waits, in its
  /// place, for what it waited for -- held too, if it's held; started, if
  /// it's active and was all they waited for.
  void leave(String id, {bool start = true}) {
    final status = _status[id];
    final when = _when[id];
    for (final w in waitingFor(id)) {
      if (status == 'inactive' && when == null) {
        _when[w] = null;
        continue;
      }
      final mine = {w, for (final p in _tree.ancestorsOf(w)) p.id};
      final after = <Map>[];
      void add(Map t) {
        if (!after.any((a) => jsonEncode(a) == jsonEncode(t))) after.add(t);
      }

      for (final t in _after(w)) {
        if (t['goal_closed'] != id) {
          add(t);
          continue;
        }
        if (status != 'inactive') continue;
        for (final inherited in _after(id)) {
          if (inherited['before_parent'] != null) continue;
          if (mine.contains(inherited['goal_closed'])) continue;
          add(inherited);
        }
      }
      if (start && status == 'active' && after.isEmpty) {
        _status[w] = 'active';
        _when[w] = null;
      } else {
        _setAfter(w, after);
      }
    }
  }

  /// Puts [id] -- out of any queue ([leave]) -- in [slot].
  void join(String id, QueueSlot slot) {
    final after = slot.after;
    final before = slot.before;
    if (after == null) {
      // In front: it takes the front's place, and the front waits for it.
      final front = before!;
      _status[id] = _status[front]!;
      _when[id] = _when[front] == null ? null : {..._when[front]!};
      _status[front] = 'inactive';
      _when[front] = {
        'after': [
          {'goal_closed': id},
        ],
      };
      return;
    }
    _status[id] = 'inactive';
    _when[id] = {
      ...?_when[id],
      'after': [
        {'goal_closed': after},
      ],
    };
    if (before != null) {
      _setAfter(before, [
        for (final t in _after(before))
          t['goal_closed'] == after ? {'goal_closed': id} : t,
      ]);
    }
  }

  /// The changes that make the goals so.
  List<GoalChange> changes() => [
    for (final g in _tree.byId.values)
      if (_status[g.id] != g.status ||
          jsonEncode(_when[g.id]) != jsonEncode(g.activateWhen))
        GoalUpdate(g.id, {
          if (_status[g.id] != g.status) 'status': _status[g.id],
          if (_status[g.id] != 'active' &&
              jsonEncode(_when[g.id]) != jsonEncode(g.activateWhen))
            'activate_when': _when[g.id],
        }),
  ];
}

/// The changes that take goal [id] out of its queue, the queue closing
/// up behind it: what waited for it waits for what it waited for (held,
/// if it was held; started, if it was active and all they waited for).
/// For a goal closed or deleted while it waits; it's left as it is.
/// Without [start], what waited only for an active one is left to start
/// as the server starts it, its delay first (as on a delete).
List<GoalChange> leavingQueue(
  List<Goal> goals,
  String id, {
  bool start = true,
}) => (_Work(goals)..leave(id, start: start)).changes();

/// The changes that move goal [id] -- queued, active, or neither -- to
/// [slot], the queue it leaves closing up behind it. In front of a
/// queue, it takes the front's place (started, if that was active) and
/// the front waits for it.
List<GoalChange> movingInQueue(List<Goal> goals, String id, QueueSlot slot) {
  if (slot.after == id || slot.before == id) return const [];
  final work = _Work(goals)..leave(id);
  // Leaving, what waited for it waits for what it waited for: a slot
  // ahead of one of those is now ahead of it there.
  work.join(id, slot);
  return work.changes();
}

/// The changes that move goal [id] to [slot] with every goal behind it
/// -- a whole queue, put behind another goal, say -- where it was left
/// as a gap: nothing else waited for it there but those coming with it.
List<GoalChange> movingBranch(List<Goal> goals, String id, QueueSlot slot) {
  if (slot.after == id || slot.before == id) return const [];
  return (_Work(goals)..join(id, slot)).changes();
}

/// The slots [id] can go in, in [queue]: in front, behind each goal ahead
/// of each that waits for it, and at the end of each branch -- and, with
/// [branches], a new branch behind each goal others wait for -- leaving
/// out those in it or behind it.
List<QueueSlot> slotsIn(GoalQueue queue, {String? id, bool branches = false}) {
  final out = <QueueSlot>[];
  final skip = <String>{
    if (id != null)
      for (final n in queue.all)
        if (n.goal.id == id)
          for (final m in n.all) m.goal.id,
  };
  if (!skip.contains(queue.front.goal.id)) {
    out.add(QueueSlot.front(queue.front.goal.id));
  }
  void walk(QueueNode n) {
    if (skip.contains(n.goal.id)) return;
    for (final m in n.next) {
      if (!skip.contains(m.goal.id)) {
        out.add(QueueSlot(after: n.goal.id, before: m.goal.id));
      }
    }
    if (branches || n.next.every((m) => skip.contains(m.goal.id))) {
      out.add(QueueSlot(after: n.goal.id));
    }
    for (final m in n.next) {
      walk(m);
    }
  }

  walk(queue.front);
  return out;
}
