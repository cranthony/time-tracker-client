import 'package:flutter/material.dart';

import '../models/goal.dart';
import '../models/goal_changes.dart';
import '../models/goal_queue.dart';
import 'goal_color.dart';

/// The backlog: [goals]' queues ([goalQueues]), each under a line saying
/// what starts it, its goals in the order they'd start. Each branch has a
/// rail down its left in its first goal's color, and a fork names the
/// branches starting together. Each goal, as [tile] builds it, is held
/// and dragged to move it: alone, the queue closing up behind it
/// ([movingInQueue]); or, a queue's front or a branch's first, with
/// everything behind it ([movingBranch]) -- put behind a goal of another
/// queue, a whole queue waits for it. [onMove] is given the changes.
class GoalBacklog extends StatefulWidget {
  const GoalBacklog({
    super.key,
    required this.goals,
    required this.tile,
    required this.onMove,
    this.now,
    this.footer,
    this.padding,
  });

  final List<Goal> goals;
  final Widget Function(Goal goal) tile;
  final ValueChanged<List<GoalChange>> onMove;

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

  String _starts(GoalQueue q) => switch (q.kind) {
    QueueFront.active => 'Active: the next starts as it closes',
    QueueFront.onHold => 'On hold: starts when you start it',
    QueueFront.waiting => 'Waiting to start',
    QueueFront.behind =>
      'After “${q.behind == null ? 'another goal' : goalTitle(q.behind!)}”',
    QueueFront.ready => 'Starting',
  };

  Widget _rails(List<Color> rails, Widget child) => IntrinsicHeight(
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(width: 8),
        for (final c in rails)
          Padding(
            padding: const EdgeInsetsDirectional.only(end: 9),
            child: Container(width: 3, color: c),
          ),
        Expanded(child: child),
      ],
    ),
  );

  Widget _row(BuildContext context, _Row row, GoalTree tree) {
    final theme = Theme.of(context);
    final small = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    return switch (row) {
      _Header(:final queue) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
        child: Text(_starts(queue), style: theme.textTheme.labelLarge),
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
    final queues = goalQueues(widget.goals, now: _now);
    final rows = _rows(queues, tree);
    return ReorderableListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      buildDefaultDragHandles: false,
      itemCount: rows.length,
      footer: rows.isEmpty
          ? Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'Nothing queued. A goal made inactive, starting after '
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
        final child = _row(context, row, tree);
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
