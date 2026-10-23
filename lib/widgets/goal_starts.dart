import 'package:flutter/material.dart';

import '../models/goal.dart';
import '../models/goal_activation.dart';
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
