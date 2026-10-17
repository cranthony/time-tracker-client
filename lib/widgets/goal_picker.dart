import 'package:flutter/material.dart';

import 'durations.dart';
import '../models/goal.dart';
import 'goal_icon.dart';
import 'picker_sheet.dart';
import 'tree_picker.dart';

/// Picks the goals an event is for in a [showPickerSheet]: a [TreePicker]
/// over the open goals (and any [picked] already that aren't), each under
/// its parent, the picked as chips. Tapping a chip sets how much of the
/// event that goal takes ([showGoalShareDialog]); each chip says it. What
/// the shares come to is checked against the event, [eventMinutes] long.
/// Gives the shares picked, in order; null if it's dismissed.
Future<List<GoalShare>?> showGoalsSheet(
  BuildContext context, {
  required List<Goal> goals,
  required List<GoalShare> picked,
  required int eventMinutes,
}) {
  var shares = [...picked];
  final tree = GoalTree(goals);
  final pickedIds = {for (final s in picked) s.goalId};
  final shown = [
    for (final g in goals)
      if (g.open || pickedIds.contains(g.id)) g,
  ];
  final nodes = [
    for (final g in byDeadline(shown))
      PickerNode(
        id: g.id,
        label: goalTitle(g),
        parentId: g.parentId,
        path: [...tree.pathOf(g.id), goalTitle(g)].join(' › '),
        detail: g.inactive
            ? 'Inactive'
            : (g.closed ? goalStatuses[g.status] : null),
        group: tree.childrenOf(g.id).isNotEmpty,
        faded: !g.active,
      ),
  ];
  return showPickerSheet(
    context,
    title: 'Goals',
    result: () => shares,
    body: (context, setState) {
      final problems = shareProblems(shares, eventMinutes);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (problems.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                problems.join(' '),
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          Expanded(
            child: TreePicker(
              nodes: nodes,
              picked: [for (final s in shares) s.goalId],
              groupsPickable: true,
              searchHint: 'Search goals',
              empty: 'No goals yet: add them on the Plan page.',
              marker: (node) => GoalIcon(
                size: 18,
                color: tree[node.id]?.active ?? false
                    ? null
                    : Theme.of(context).hintColor,
              ),
              chipDetail: (id) =>
                  shares.where((s) => s.goalId == id).firstOrNull?.label,
              onChipTap: (id) async {
                final share = shares.firstWhere((s) => s.goalId == id);
                final set = await showGoalShareDialog(
                  context,
                  goal: tree[id],
                  share: share,
                  eventMinutes: eventMinutes,
                );
                if (set == null) return;
                setState(() {
                  shares = [for (final s in shares) s.goalId == id ? set : s];
                });
              },
              onChanged: (ids) => setState(() {
                final by = {for (final s in shares) s.goalId: s};
                shares = [for (final id in ids) by[id] ?? GoalShare(id)];
              }),
            ),
          ),
        ],
      );
    },
  );
}

/// How much of an event, [eventMinutes] long, [goal] takes: the whole
/// event, a duration, or a percentage of what the durations leave. Gives
/// the share as set, or null if it's called off.
Future<GoalShare?> showGoalShareDialog(
  BuildContext context, {
  required Goal? goal,
  required GoalShare share,
  required int eventMinutes,
}) => showDialog<GoalShare>(
  context: context,
  builder: (context) => _ShareDialog(
    title: goal == null ? share.goalId : goalTitle(goal),
    share: share,
    eventMinutes: eventMinutes,
  ),
);

enum _Kind { whole, minutes, percent }

class _ShareDialog extends StatefulWidget {
  const _ShareDialog({
    required this.title,
    required this.share,
    required this.eventMinutes,
  });

  final String title;
  final GoalShare share;
  final int eventMinutes;

  @override
  State<_ShareDialog> createState() => _ShareDialogState();
}

class _ShareDialogState extends State<_ShareDialog> {
  late var _kind = widget.share.minutes != null
      ? _Kind.minutes
      : widget.share.percent != null
      ? _Kind.percent
      : _Kind.whole;
  late final _minutes = TextEditingController(
    text: '${widget.share.minutes ?? widget.eventMinutes}',
  );
  late final _percent = TextEditingController(
    text: '${widget.share.percent ?? 50}',
  );

  @override
  void dispose() {
    _minutes.dispose();
    _percent.dispose();
    super.dispose();
  }

  GoalShare? get _share => switch (_kind) {
    _Kind.whole => GoalShare(widget.share.goalId),
    _Kind.minutes => switch (int.tryParse(_minutes.text.trim())) {
      final m? when m > 0 && m <= widget.eventMinutes => GoalShare(
        widget.share.goalId,
        minutes: m,
      ),
      _ => null,
    },
    _Kind.percent => switch (int.tryParse(_percent.text.trim())) {
      final p? when p >= 1 && p <= 100 => GoalShare(
        widget.share.goalId,
        percent: p,
      ),
      _ => null,
    },
  };

  @override
  Widget build(BuildContext context) {
    final share = _share;
    return AlertDialog(
      title: Text(widget.title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'How much of this ${formatMinutes(widget.eventMinutes)} event is '
            'for it?',
          ),
          const SizedBox(height: 12),
          SegmentedButton<_Kind>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: _Kind.whole, label: Text('All of it')),
              ButtonSegment(value: _Kind.minutes, label: Text('Minutes')),
              ButtonSegment(value: _Kind.percent, label: Text('Percent')),
            ],
            selected: {_kind},
            onSelectionChanged: (picked) =>
                setState(() => _kind = picked.single),
          ),
          const SizedBox(height: 12),
          switch (_kind) {
            _Kind.whole => const Text(
              'It counts the whole event, whatever the other goals take.',
            ),
            _Kind.minutes => TextField(
              controller: _minutes,
              autofocus: true,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: 'Minutes',
                helperText: 'At most ${widget.eventMinutes}',
              ),
              onChanged: (_) => setState(() {}),
            ),
            _Kind.percent => TextField(
              controller: _percent,
              autofocus: true,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Percent',
                suffixText: '%',
                helperText: "Of what the goals given minutes don't take",
              ),
              onChanged: (_) => setState(() {}),
            ),
          },
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: share == null
              ? null
              : () => Navigator.of(context).pop(share),
          child: const Text('Set'),
        ),
      ],
    );
  }
}
