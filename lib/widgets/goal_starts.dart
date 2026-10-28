import 'package:flutter/material.dart';

import '../models/goal.dart';
import '../models/goal_activation.dart';
import 'duration_field.dart';
import 'durations.dart';
import 'goal_icon.dart';
import 'picker_sheet.dart';
import 'tree_picker.dart';

/// A time a goal waits for ([waitsUntil]) as the app shows it: "Mon, Nov
/// 2", or "Mon, Nov 2, 9:00 AM".
String startLabel(BuildContext context, String at) {
  final start = startOf(at);
  if (start == null) return at;
  final strings = MaterialLocalizations.of(context);
  return at.contains('T')
      ? '${strings.formatMediumDate(start)}, '
            '${strings.formatTimeOfDay(TimeOfDay.fromDateTime(start))}'
      : strings.formatMediumDate(start);
}

/// What [goal] waits for before it's activated, a line each, its goals
/// named from [tree]: "After “Draft the plan” closes", "From Mon, Nov 2",
/// "Then the next day", "Held while 3 other goals at P1 or higher are
/// active". Empty if it waits for nothing.
List<String> startsLines(BuildContext context, Goal goal, GoalTree tree) {
  final when = goal.activateWhen;
  if (when == null) return const [];
  String named(String id) =>
      tree[id] == null ? 'a goal deleted since' : '“${goalTitle(tree[id]!)}”';
  return [
    for (final t in when['after'] as List? ?? const [])
      switch (t) {
        {'goal_closed': final String id} => 'After ${named(id)} closes',
        {'at': final String at} => 'From ${startLabel(context, at)}',
        _ => 'After something unknown',
      },
    if (waitsNextDay(goal)) 'Then the next day',
    if (delayMinutes(goal) case final m? when m > 0)
      'Then ${formatMinutes(m)} later',
    for (final hold in when['hold_while'] as List? ?? const [])
      if (hold is Map)
        'Held while ${holdLabel(hold, tree.priorityOf(goal.id))}',
  ];
}

/// When [goal], waiting to be activated, starts, in a line for its tile,
/// its goals named from [tree]: "Starts Oct 30" (or "Starts Oct 30, 9:00
/// AM") if it's expected to ([expectedStart]); ready by [now], "Ready,
/// held while 3 other goals are active" or "Ready to start"; or else the
/// goals it still waits for, "Starts after “Draft the plan” closes, the
/// next day". "Waiting" if it waits for none.
String startsSummary(
  BuildContext context,
  Goal goal,
  GoalTree tree, {
  required DateTime now,
}) {
  final strings = MaterialLocalizations.of(context);
  if (expectedStart(goal, tree, now: now) case final at?) {
    final day = strings.formatShortMonthDay(at);
    return at.hour == 0 && at.minute == 0
        ? 'Starts $day'
        : 'Starts $day, '
              '${strings.formatTimeOfDay(TimeOfDay.fromDateTime(at))}';
  }
  if (readyAt(goal, tree) case final at? when !at.isAfter(now)) {
    return switch (holding(goal, tree)) {
      final hold? =>
        'Ready, held while ${holdLabel(hold, tree.priorityOf(goal.id))}',
      null => 'Ready to start',
    };
  }
  final open = [
    for (final id in waitsFor(goal))
      if (tree[id] == null)
        'a goal deleted since'
      else if (tree[id]!.closedAt == null)
        '“${goalTitle(tree[id]!)}”',
  ];
  if (open.isEmpty) return 'Waiting';
  final names = open.length == 1
      ? open.single
      : '${open.take(open.length - 1).join(', ')} and ${open.last}';
  final then = waitsNextDay(goal)
      ? ', the next day'
      : switch (delayMinutes(goal)) {
          final m? when m > 0 => ', then ${formatMinutes(m)} later',
          _ => '',
        };
  return 'Starts after $names close${open.length == 1 ? 's' : ''}$then';
}

/// What a hold counts, for a goal of priority [own]: "3 other goals at P1
/// or higher are active".
String holdLabel(Map hold, int own) {
  final n = (hold['active_at_least'] as num?)?.toInt() ?? 1;
  String level(Object? p) => p == 'own' ? 'its priority (P$own)' : 'P$p';
  final which = switch (hold['priority']) {
    {'at_or_above': final Object r} => ' at ${level(r)} or higher',
    {'exactly': final Object r} => ' at exactly ${level(r)}',
    _ => '',
  };
  return '$n other goal${n == 1 ? '' : 's'}$which '
      '${n == 1 ? 'is' : 'are'} active';
}

/// The ways a hold can count goals by priority: its key here, what it's
/// called, and the server's `priority` for it (null for any).
const holdScopes = [
  ('any', 'of any priority', null),
  ('own-up', 'at its priority or higher', {'at_or_above': 'own'}),
  ('own', 'at exactly its priority', {'exactly': 'own'}),
  ('0-up', 'at P0', {'at_or_above': 0}),
  ('1-up', 'at P1 or higher', {'at_or_above': 1}),
  ('2-up', 'at P2 or higher', {'at_or_above': 2}),
];

/// Which of [holdScopes] a hold's [priority] is; "any" if none fits.
String holdScopeOf(Object? priority) {
  for (final (key, _, p) in holdScopes) {
    if (p == null && priority == null) return key;
    if (p != null && priority is Map && '$p' == '$priority') return key;
  }
  return 'any';
}

/// What a goal waits for before it's activated, edited: the goals it
/// waits to close and the days it waits for, as chips to remove, and
/// buttons to add one; whether it then waits for the next day; and a
/// hold, while enough other goals are active. [value] is
/// [Goal.activateWhen]'s, or null for none; [onChanged] gets it as
/// changed, null once it waits for nothing. [goalId] is the goal's own,
/// and [goals] every goal, to pick from: not itself, its parents, a goal
/// waiting for it, or one that's closed.
class GoalStartsEditor extends StatelessWidget {
  const GoalStartsEditor({
    super.key,
    required this.value,
    required this.goals,
    required this.onChanged,
    this.goalId,
    this.parentId,
    this.now = DateTime.now,
  });

  final Map<String, Object?>? value;
  final List<Goal> goals;
  final String? goalId;

  /// The goal it's under, for a new one; its own parent otherwise.
  final String? parentId;
  final ValueChanged<Map<String, Object?>?> onChanged;
  final DateTime Function() now;

  List<Map<String, Object?>> get _after => [
    for (final t in value?['after'] as List? ?? const [])
      (t as Map).cast<String, Object?>(),
  ];

  List<Map<String, Object?>> get _holds => [
    for (final h in value?['hold_while'] as List? ?? const [])
      (h as Map).cast<String, Object?>(),
  ];

  /// [value] with [after], [delay] and [holds] as given, or as they are.
  void _set({
    List<Map<String, Object?>>? after,
    Object? delay = _keep,
    List<Map<String, Object?>>? holds,
  }) {
    final kept = value?['delay'];
    final d = identical(delay, _keep) ? kept : delay;
    final next = <String, Object?>{
      if ((after ?? _after) case final a when a.isNotEmpty) 'after': a,
      'delay': ?d,
      if ((holds ?? _holds) case final h when h.isNotEmpty) 'hold_while': h,
    };
    onChanged(next.isEmpty ? null : next);
  }

  static const _keep = Object();

  /// The goals that can be waited for: open, not itself, not one of its
  /// parents (which can't close while it's open), and not one waiting,
  /// through others, for it.
  List<Goal> _pickable(GoalTree tree) {
    final self = goalId;
    final parents = {
      ?parentId,
      if (parentId != null) ...tree.ancestorsOf(parentId!).map((g) => g.id),
    };
    bool waitsOnSelf(Goal g, Set<String> seen) {
      if (self == null) return false;
      for (final id in waitsFor(g)) {
        if (id == self) return true;
        final next = tree[id];
        if (next != null && seen.add(id) && waitsOnSelf(next, seen)) {
          return true;
        }
      }
      return false;
    }

    return [
      for (final g in byPriority(goals, tree))
        if (g.open &&
            g.id != self &&
            !parents.contains(g.id) &&
            !waitsOnSelf(g, {}) &&
            !_after.any((t) => t['goal_closed'] == g.id))
          g,
    ];
  }

  Future<void> _pickGoal(BuildContext context) async {
    final tree = GoalTree(goals);
    final pickable = _pickable(tree);
    final picked = await pickNode(
      context,
      title: 'After it closes',
      nodes: [
        for (final g in pickable)
          PickerNode(
            id: g.id,
            label: goalTitle(g),
            parentId: pickable.any((p) => p.id == g.parentId)
                ? g.parentId
                : null,
            path: [...tree.pathOf(g.id), goalTitle(g)].join(' › '),
            group: pickable.any((c) => c.parentId == g.id),
          ),
      ],
      groupsPickable: true,
      marker: (_) => const GoalIcon(size: 18),
      searchHint: 'Search goals',
    );
    final id = picked?.id;
    if (id == null) return;
    _set(
      after: [
        ..._after,
        {'goal_closed': id},
      ],
    );
  }

  Future<void> _pickDay(BuildContext context) async {
    final today = now();
    final picked = await showDatePicker(
      context: context,
      initialDate: today.add(const Duration(days: 1)),
      firstDate: DateTime(today.year - 1),
      lastDate: DateTime(today.year + 20),
    );
    if (picked == null) return;
    _set(
      after: [
        ..._after,
        {'at': deadlineOf(picked)},
      ],
    );
  }

  /// Adds a time [now] plus a while picked, in days and hours
  /// ([pickWhile]): "For a while…".
  Future<void> _pickWhile(BuildContext context) async {
    final at = await pickWhile(context, now: now);
    if (at == null) return;
    _set(
      after: [
        ..._after,
        {'at': deadlineOf(at, time: true)},
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tree = GoalTree(goals);
    final after = _after;
    final hold = _holds.firstOrNull;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (after.isEmpty && hold == null)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(
              'Only when you activate it',
              style: TextStyle(color: theme.hintColor),
            ),
          ),
        if (after.isNotEmpty)
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final (i, t) in after.indexed)
                InputChip(
                  avatar: Icon(
                    t['goal_closed'] != null
                        ? Icons.flag_outlined
                        : Icons.event,
                    size: 18,
                  ),
                  label: Text(switch (t) {
                    {'goal_closed': final String id} =>
                      'After “${tree[id] == null ? id : goalTitle(tree[id]!)}” closes',
                    {'at': final String at} =>
                      'From ${startLabel(context, at)}',
                    _ => '?',
                  }),
                  onDeleted: () => _set(
                    after: [
                      for (final (j, u) in after.indexed)
                        if (j != i) u,
                    ],
                  ),
                ),
            ],
          ),
        Wrap(
          spacing: 8,
          children: [
            ActionChip(
              avatar: const Icon(Icons.flag_outlined, size: 18),
              label: const Text('After a goal closes…'),
              onPressed: () => _pickGoal(context),
            ),
            ActionChip(
              avatar: const Icon(Icons.event, size: 18),
              label: const Text('From a day…'),
              onPressed: () => _pickDay(context),
            ),
            ActionChip(
              avatar: const Icon(Icons.hourglass_empty, size: 18),
              label: const Text('For a while…'),
              onPressed: () => _pickWhile(context),
            ),
          ],
        ),
        if (after.isNotEmpty)
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Then wait until the next day'),
            value: value?['delay'] == 'next_day',
            onChanged: (on) => _set(delay: on ? 'next_day' : null),
          ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Hold it while other goals are active'),
          subtitle: hold == null
              ? null
              : Text(
                  'Held while '
                  '${holdLabel(hold, goalId == null ? defaultGoalPriority : tree.priorityOf(goalId!))}',
                ),
          value: hold != null,
          onChanged: (on) => _set(
            holds: on
                ? [
                    {
                      'active_at_least': 3,
                      'priority': {'at_or_above': 'own'},
                    },
                  ]
                : const [],
          ),
        ),
        if (hold != null)
          Wrap(
            spacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              const Text('At least'),
              DropdownButton<int>(
                value: (hold['active_at_least'] as num?)?.toInt() ?? 1,
                items: [
                  for (var n = 1; n <= 10; n++)
                    DropdownMenuItem(value: n, child: Text('$n')),
                ],
                onChanged: (n) => _set(
                  holds: [
                    {...hold, 'active_at_least': ?n},
                  ],
                ),
              ),
              const Text('active,'),
              DropdownButton<String>(
                value: holdScopeOf(hold['priority']),
                items: [
                  for (final (key, label, _) in holdScopes)
                    DropdownMenuItem(value: key, child: Text(label)),
                ],
                onChanged: (key) {
                  final scope = holdScopes.firstWhere((s) => s.$1 == key).$3;
                  _set(
                    holds: [
                      {
                        'active_at_least': hold['active_at_least'] ?? 1,
                        'priority': ?scope,
                      },
                    ],
                  );
                },
              ),
            ],
          ),
      ],
    );
  }
}

/// Asks for a while, in days and hours ([DurationField]), and returns
/// when it's over from [now]: the same time of day that many days on,
/// then those hours. Null if it's cancelled.
Future<DateTime?> pickWhile(
  BuildContext context, {
  DateTime Function() now = DateTime.now,
}) => showDialog<DateTime>(
  context: context,
  builder: (context) => _WhileDialog(now: now()),
);

class _WhileDialog extends StatefulWidget {
  const _WhileDialog({required this.now});

  final DateTime now;

  @override
  State<_WhileDialog> createState() => _WhileDialogState();
}

class _WhileDialogState extends State<_WhileDialog> {
  final _minutes = TextEditingController(text: '${Duration.minutesPerDay}');

  @override
  void dispose() {
    _minutes.dispose();
    super.dispose();
  }

  /// When the while typed is over, if it's one: null if it isn't, or is
  /// none at all.
  DateTime? get _until {
    final minutes = int.tryParse(_minutes.text.trim());
    if (minutes == null || minutes <= 0) return null;
    final n = widget.now;
    return DateTime(
      n.year,
      n.month,
      n.day + minutes ~/ Duration.minutesPerDay,
      n.hour,
      n.minute + minutes % Duration.minutesPerDay,
    );
  }

  @override
  Widget build(BuildContext context) {
    final until = _until;
    return AlertDialog(
      title: const Text('For how long'),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DurationField(
              controller: _minutes,
              label: 'For',
              days: true,
              onChanged: () => setState(() {}),
            ),
            if (until != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'Until ${startLabel(context, deadlineOf(until, time: true))}',
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
        FilledButton(
          onPressed: until == null
              ? null
              : () => Navigator.of(context).pop(until),
          child: const Text('OK'),
        ),
      ],
    );
  }
}

/// Asks what [goal] waits for before it's activated again, as it's
/// deactivated ("Deactivate until"): the Starts editor ([GoalStartsEditor])
/// in a dialog, with [goals] to pick from. Returns its activate_when; null
/// if it's cancelled.
Future<Map<String, Object?>?> pickDeactivateUntil(
  BuildContext context, {
  required Goal goal,
  required List<Goal> goals,
  DateTime Function() now = DateTime.now,
}) => showDialog<Map<String, Object?>>(
  context: context,
  builder: (context) =>
      _DeactivateUntilDialog(goal: goal, goals: goals, now: now),
);

class _DeactivateUntilDialog extends StatefulWidget {
  const _DeactivateUntilDialog({
    required this.goal,
    required this.goals,
    required this.now,
  });

  final Goal goal;
  final List<Goal> goals;
  final DateTime Function() now;

  @override
  State<_DeactivateUntilDialog> createState() => _DeactivateUntilDialogState();
}

class _DeactivateUntilDialogState extends State<_DeactivateUntilDialog> {
  Map<String, Object?>? _value;

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text('Deactivate ${goalTitle(widget.goal)} until'),
    content: SizedBox(
      width: 480,
      child: SingleChildScrollView(
        child: GoalStartsEditor(
          value: _value,
          goals: widget.goals,
          goalId: widget.goal.id,
          parentId: widget.goal.parentId,
          now: widget.now,
          onChanged: (value) => setState(() => _value = value),
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: _value == null
            ? null
            : () => Navigator.of(context).pop(_value),
        child: const Text('Deactivate'),
      ),
    ],
  );
}
