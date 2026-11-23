import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/goal.dart';
import '../models/goal_activation.dart';
import '../models/goal_changes.dart';
import '../models/goal_queue.dart';
import 'goal_color.dart';
import 'goal_starts.dart' show holdLabel, startDayLabel;

/// The backlog: [goals]' queues ([goalQueues]), each under a line saying
/// what starts it, its goals in the order they'd start. Each branch has a
/// rail down its left in its first goal's color, and a fork names the
/// branches starting together. Each goal, as [tile] builds it, is held
/// and dragged to move it: alone, the queue closing up behind it
/// ([movingInQueue]); or, a queue's front or a branch's first, with
/// everything behind it ([movingBranch]) -- put behind a goal of another
/// queue, a whole queue waits for it. [onMove] is given the changes.
/// A queue waiting to start says when it's expected to, if what it waits
/// for closes by its deadline. Tapping a queue's first line folds it to
/// that line, and the queues folded are kept on the device. With
/// [allOpen], every open goal is in a queue ([goalQueues]); with
/// [matches], only the queues with a goal it matches are shown.
class GoalBacklog extends StatefulWidget {
  const GoalBacklog({
    super.key,
    required this.goals,
    required this.tile,
    required this.onMove,
    this.allOpen = false,
    this.matches,
    this.noMatches,
    this.now,
    this.footer,
    this.padding,
  });

  final List<Goal> goals;
  final Widget Function(Goal goal) tile;
  final ValueChanged<List<GoalChange>> onMove;

  /// Whether every open goal is in a queue, not just those queued.
  final bool allOpen;

  /// Which goals a search matches; null for all.
  final bool Function(Goal goal)? matches;

  /// Shown when [matches] leaves no queue.
  final Widget? noMatches;

  /// The clock; the real one by default.
  final DateTime Function()? now;

  /// After the queues, in the same list.
  final Widget? footer;

  /// Around the list.
  final EdgeInsets? padding;

  @override
  State<GoalBacklog> createState() => _GoalBacklogState();
}

sealed class _Row {
  const _Row();
}

/// A queue's first line: what starts it.
class _Header extends _Row {
  const _Header(this.queue);
  final GoalQueue queue;
}

/// A goal in a queue, under [parent] (null at the front), with the rails
/// of the branches it's in, outermost first.
class _GoalRow extends _Row {
  const _GoalRow(this.node, this.queue, this.parent, this.rails);
  final QueueNode node;
  final GoalQueue queue;
  final QueueNode? parent;
  final List<Color> rails;
}

/// After [node], the branches that start together as it closes.
class _Fork extends _Row {
  const _Fork(this.node, this.rails);
  final QueueNode node;
  final List<Color> rails;
}

class _GoalBacklogState extends State<GoalBacklog> {
  DateTime get _now => (widget.now ?? DateTime.now)();

  /// The fronts of the queues folded to their first line.
  final _collapsed = <String>{};

  @override
  void initState() {
    super.initState();
    _loadCollapsed();
  }

  /// The queues folded last time. Best effort: without them, all are
  /// open.
  Future<void> _loadCollapsed() async {
    try {
      final kept = await SharedPreferencesAsync().getStringList(_collapsedKey);
      if (!mounted || kept == null) return;
      setState(() => _collapsed.addAll(kept));
    } catch (_) {
      // Nowhere they're kept: all open.
    }
  }

  /// Folds or opens the queue whose front is [front], keeping which are
  /// folded -- of the queues there are now.
  void _toggle(String front, List<GoalQueue> queues) {
    setState(() {
      if (!_collapsed.remove(front)) _collapsed.add(front);
      final fronts = {for (final q in queues) q.front.goal.id};
      _collapsed.removeWhere((id) => !fronts.contains(id));
    });
    try {
      SharedPreferencesAsync()
          .setStringList(_collapsedKey, [..._collapsed])
          .catchError((_) {});
    } catch (_) {
      // Nowhere to keep it: it lasts until the app closes.
    }
  }

  List<_Row> _rows(List<GoalQueue> queues, GoalTree tree) {
    final out = <_Row>[];
    void visit(QueueNode n, GoalQueue q, QueueNode? parent, List<Color> rails) {
      out.add(_GoalRow(n, q, parent, rails));
      switch (n.next) {
        case []:
          break;
        case [final one]:
          visit(one, q, n, rails);
        case final several:
          out.add(_Fork(n, rails));
          for (final m in several) {
            visit(m, q, n, [...rails, colorOfGoal(m.goal, tree: tree)]);
          }
      }
    }

    for (final q in queues) {
      out.add(_Header(q));
      if (_collapsed.contains(q.front.goal.id)) continue;
      visit(q.front, q, null, [colorOfGoal(q.front.goal, tree: tree)]);
    }
    return out;
  }

  /// [row]'s goal dropped at [to] among [rows] without it: behind the
  /// goal above, ahead of the one it leads to; in front of a queue, just
  /// under its first line.
  void _drop(List<_Row> rows, int from, int to) {
    final row = rows[from];
    if (row is! _GoalRow) return;
    final others = [...rows]..removeAt(from);
    final QueueSlot slot;
    if (to <= 0) {
      final first = others.whereType<_Header>().firstOrNull;
      if (first == null) return;
      slot = QueueSlot.front(first.queue.front.goal.id);
    } else {
      slot = switch (others[to - 1]) {
        _Header(:final queue) => QueueSlot.front(queue.front.goal.id),
        _Fork(:final node) => QueueSlot(
          after: node.goal.id,
          before: node.next.first.goal.id,
        ),
        _GoalRow(:final node) => QueueSlot(
          after: node.goal.id,
          before: node.next.firstOrNull?.goal.id,
        ),
      };
    }
    final id = row.node.goal.id;
    final branch = row.parent == null || (row.parent?.next.length ?? 0) > 1;
    if (branch) {
      // Not behind itself.
      final behind = {for (final n in row.node.all) n.goal.id};
      if (behind.contains(slot.after) ||
          (slot.after == null && behind.contains(slot.before))) {
        return;
      }
    }
    final changes = branch
        ? movingBranch(widget.goals, id, slot)
        : movingInQueue(widget.goals, id, slot);
    if (changes.isNotEmpty) widget.onMove(changes);
  }

  String _starts(BuildContext context, GoalQueue q, GoalTree tree) =>
      switch (q.kind) {
        QueueFront.active when q.front.next.isEmpty => 'Active',
        QueueFront.active => 'Active: the next starts as it closes',
        QueueFront.onHold => 'On hold: starts when you start it',
        QueueFront.waiting =>
          'Waiting to start${_expected(context, q.front.goal, tree)}',
        QueueFront.behind =>
          'After “${q.behind == null ? 'another goal' : goalTitle(q.behind!)}”'
              '${_expected(context, q.front.goal, tree)}',
        QueueFront.ready => 'Starting',
      };

  /// When [goal], at a queue's front, is expected to start, if what it
  /// waits for closes by its deadline: " · expected Dec 2". Or why
  /// there's no telling: what it waits for has no deadline, or it's
  /// ready but held back.
  String _expected(BuildContext context, Goal goal, GoalTree tree) {
    if (expectedStart(goal, tree, now: _now) case final at?) {
      return ' · expected ${startDayLabel(context, at)}';
    }
    if ((readyAt(goal, tree), holding(goal, tree))
        case (final ready?, final hold?) when !ready.isAfter(_now)) {
      return ' · ready, held while '
          '${holdLabel(hold, tree.priorityOf(goal.id))}';
    }
    for (final id in waitsFor(goal)) {
      final other = tree[id];
      if (other == null || other.closed) continue;
      if (deadlineEnd(expectedDeadline(other, tree, now: _now)) == null) {
        return ' · no expected start: “${goalTitle(other)}” has no deadline';
      }
    }
    return '';
  }

  /// How many goals [q] has, for its folded first line.
  static String _count(GoalQueue q) {
    final n = q.all.length;
    return n == 1 ? '1 goal' : '$n goals';
  }

  /// [child] with [rails] down its left, as tall as it is: drawn beside
  /// it rather than measured, as a tile's title, wrapped, is taller than
  /// its intrinsic height says.
  Widget _rails(List<Color> rails, Widget child) => Stack(
    children: [
      Padding(
        padding: EdgeInsetsDirectional.only(start: 8.0 + 12 * rails.length),
        child: child,
      ),
      for (final (i, c) in rails.indexed)
        PositionedDirectional(
          start: 8.0 + 12 * i,
          top: 0,
          bottom: 0,
          width: 3,
          child: ColoredBox(color: c),
        ),
    ],
  );

  Widget _row(
    BuildContext context,
    _Row row,
    GoalTree tree,
    List<GoalQueue> queues,
  ) {
    final theme = Theme.of(context);
    final small = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    return switch (row) {
      _Header(:final queue) => Padding(
        padding: const EdgeInsets.only(top: 8),
        child: InkWell(
          // Not a stop for J and K, which go from goal to goal.
          canRequestFocus: false,
          onTap: () => _toggle(queue.front.goal.id, queues),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 16, 4),
            child: Row(
              children: [
                Icon(
                  _collapsed.contains(queue.front.goal.id)
                      ? Icons.chevron_right
                      : Icons.expand_more,
                  size: 20,
                  semanticLabel: _collapsed.contains(queue.front.goal.id)
                      ? 'Show the queue'
                      : 'Fold the queue',
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    _starts(context, queue, tree),
                    style: theme.textTheme.labelLarge,
                  ),
                ),
                if (_collapsed.contains(queue.front.goal.id))
                  Text(_count(queue), style: small),
              ],
            ),
          ),
        ),
      ),
      _Fork(:final node, :final rails) => _rails(
        rails,
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            children: [
              Icon(Icons.call_split, size: 18, color: small?.color),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Then ${node.next.length} branches start together: '
                  '${node.next.map((m) => '“${goalTitle(m.goal)}”').join(', ')}',
                  style: small,
                ),
              ),
            ],
          ),
        ),
      ),
      _GoalRow(:final node, :final rails) => _rails(
        rails,
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            widget.tile(node.goal),
            if (node.alsoWaitsFor.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
                child: Text(
                  'Also waits for '
                  '${node.alsoWaitsFor.map((id) => '“${tree[id] == null ? id : goalTitle(tree[id]!)}”').join(', ')}',
                  style: small,
                ),
              ),
          ],
        ),
      ),
    };
  }

  @override
  Widget build(BuildContext context) {
    final tree = GoalTree(widget.goals);
    final matches = widget.matches;
    final queues = [
      for (final q in goalQueues(
        widget.goals,
        now: _now,
        allOpen: widget.allOpen,
      ))
        if (matches == null || q.all.any((n) => matches(n.goal))) q,
    ];
    final rows = _rows(queues, tree);
    return ReorderableListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      buildDefaultDragHandles: false,
      itemCount: rows.length,
      footer: rows.isEmpty && widget.noMatches != null && matches != null
          ? widget.noMatches
          : rows.isEmpty
          ? Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                widget.allOpen
                    ? 'No open goals.'
                    : 'Nothing queued. A goal made inactive, starting after '
                          'another closes, joins that goal’s queue.',
              ),
            )
          : widget.footer,
      padding: widget.padding,
      onReorderItem: (from, to) => _drop(rows, from, to),
      itemBuilder: (context, index) {
        final row = rows[index];
        final key = switch (row) {
          _Header(:final queue) => 'queue:${queue.front.goal.id}',
          _Fork(:final node) => 'fork:${node.goal.id}',
          _GoalRow(:final node) => node.goal.id,
        };
        final child = _row(context, row, tree, queues);
        return row is _GoalRow
            ? ReorderableDelayedDragStartListener(
                key: ValueKey(key),
                index: index,
                child: child,
              )
            : KeyedSubtree(key: ValueKey(key), child: child);
      },
    );
  }
}

/// Where the fronts of the queues folded are kept.
const _collapsedKey = 'goal_queues_collapsed';
