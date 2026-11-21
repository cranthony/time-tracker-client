import 'package:flutter/material.dart';

import '../models/goal.dart';
import '../models/goal_queue.dart';
import 'goal_color.dart';
import 'goal_icon.dart';
import 'goal_starts.dart' show startsSummary;

/// Asks where in a queue ([goalQueues]) goal [goalId] -- or a new goal,
/// if null -- goes: each queue's goals in the order they'd start, each
/// with when, and an "Insert here" between them and at the end of each
/// branch. Not in front of a queue: that's starting it, done in the
/// backlog. Nor in or behind [goalId] itself. The slot picked; null if
/// it's called off.
Future<QueueSlot?> pickQueueSlot(
  BuildContext context, {
  required List<Goal> goals,
  String? goalId,
  DateTime Function() now = DateTime.now,
}) {
  final tree = GoalTree(goals);
  final queues = goalQueues(goals, now: now());
  return showDialog<QueueSlot>(
    context: context,
    builder: (context) {
      final theme = Theme.of(context);
      final small = theme.textTheme.bodySmall?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
      );
      final rows = <Widget>[];
      for (final q in queues) {
        final slots = [
          for (final s in slotsIn(q, id: goalId, branches: true))
            if (s.after != null) s,
        ];
        if (slots.isEmpty) continue;
        // The goal picked for and those behind it: it can't go there.
        final moving = {
          for (final n in q.all)
            if (n.goal.id == goalId)
              for (final m in n.all) m.goal.id,
        };
        void visit(QueueNode n, int depth) {
          final g = n.goal;
          rows.add(
            ListTile(
              dense: true,
              contentPadding: EdgeInsetsDirectional.only(
                start: 16.0 + 20 * depth,
                end: 16,
              ),
              leading: GoalIcon(size: 18, color: colorOfGoal(g, tree: tree)),
              title: Text(goalTitle(g)),
              subtitle: Text(
                g.active
                    ? 'Active'
                    : startsSummary(context, g, tree, now: now()),
                style: small,
              ),
            ),
          );
          for (final s in slots.where((s) => s.after == g.id)) {
            final branch =
                s.before == null &&
                n.next.any((m) => !moving.contains(m.goal.id));
            rows.add(
              Padding(
                padding: EdgeInsetsDirectional.only(
                  start: 16.0 + 20 * (depth + (branch ? 1 : 0)),
                  end: 16,
                ),
                child: Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: TextButton.icon(
                    icon: Icon(
                      branch
                          ? Icons.call_split
                          : Icons.subdirectory_arrow_right,
                      size: 18,
                    ),
                    label: Text(
                      branch
                          ? 'New branch: starts with the others after it'
                          : 'Insert here',
                    ),
                    onPressed: () => Navigator.of(context).pop(s),
                  ),
                ),
              ),
            );
          }
          for (final m in n.next) {
            if (moving.contains(m.goal.id)) continue;
            visit(m, n.next.length > 1 ? depth + 1 : depth);
          }
        }

        if (rows.isNotEmpty) rows.add(const Divider());
        visit(q.front, 0);
      }
      return AlertDialog(
        title: const Text('Where in a queue?'),
        contentPadding: const EdgeInsets.only(top: 12),
        content: SizedBox(
          width: 480,
          child: rows.isEmpty
              ? const Padding(
                  padding: EdgeInsets.all(24),
                  child: Text('No queues yet.'),
                )
              : ListView(shrinkWrap: true, children: rows),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
        ],
      );
    },
  );
}
