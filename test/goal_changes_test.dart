import 'package:flutter_test/flutter_test.dart';
import 'package:time_tracker_client/models/goal.dart';
import 'package:time_tracker_client/models/goal_changes.dart';

final _now = DateTime(2026, 10, 17, 9);

Goal _goal(
  String id, {
  String? parent,
  String status = 'active',
  String? deadline = '2026-12-01',
  int? minutes,
  bool required = false,
}) => Goal.fromJson({
  'id': id,
  'title': id,
  'parent_id': parent,
  'status': status,
  'deadline': deadline,
  'expected_minutes': minutes,
  'required': required,
  'history': [
    {'status': status, 'at': '2026-10-01T09:00:00'},
  ],
});

/// Each change as "verb id {changes}", to compare.
List<String> _described(List<GoalChange> changes) => [
  for (final c in changes)
    switch (c) {
      GoalCreate(:final goal) => 'create ${goal.id}',
      GoalUpdate(:final id, :final changes) => 'update $id $changes',
      GoalDelete(:final id) => 'delete $id',
      GoalBatch(:final changes) => 'batch ${_described(changes)}',
    },
];

void main() {
  final goals = [
    _goal('top', minutes: 600),
    _goal('a', parent: 'top', deadline: '2026-11-01', required: true),
    _goal('a1', parent: 'a', deadline: '2026-10-25'),
    _goal('b', parent: 'top', status: 'inactive', deadline: null),
    _goal('c', parent: 'top', deadline: '2026-11-20'),
  ];
  final tree = GoalTree(goals);

  test('closing a goal closes, then moves, its sub-goals first', () {
    final changes = closing(
      tree,
      tree['top']!,
      'done',
      leftovers: {
        'b': const CloseLeftover('obsolete'),
        'c': const MoveLeftover(to: 'inbox'),
      },
      made: _goal('inbox', deadline: '2026-12-31'),
    );

    expect(_described(changes), [
      'create inbox',
      'update c {parent_id: inbox}',
      'update a1 {status: done}',
      'update a {status: done}',
      'update b {status: obsolete}',
      'update top {status: done}',
    ]);
    expect(planned(goals, changes, now: _now), isEmpty);
    expect(requiredOpen(tree, tree['top']!).map((g) => g.id), ['a']);
  });

  test('closing a goal alone is refused while its sub-goals are open', () {
    final problems = planned(goals, [
      const GoalUpdate('top', {'status': 'done'}),
    ], now: _now);
    expect(problems, isNotEmpty);
  });

  test('activating a goal activates its inactive parents first', () {
    final deep = [
      _goal('p', status: 'inactive', deadline: null),
      _goal('q', parent: 'p', status: 'inactive', deadline: null),
      _goal('r', parent: 'q', status: 'inactive', deadline: null),
    ];
    final t = GoalTree(deep);

    final changes = activating(
      t,
      [t['r']!],
      deadlines: {'p': '2026-12-01', 'q': '2026-11-01', 'r': '2026-10-30'},
    );

    expect(_described(changes), [
      'update p {status: active, deadline: 2026-12-01}',
      'update q {status: active, deadline: 2026-11-01}',
      'update r {status: active, deadline: 2026-10-30}',
    ]);
    expect(planned(deep, changes, now: _now), isEmpty);
    expect(inactiveParents(t, [t['r']!]).map((g) => g.id), ['p', 'q']);
    // Without deadlines, it's refused.
    expect(planned(deep, activating(t, [t['r']!]), now: _now), isNotEmpty);
  });

  test('deactivating a goal deactivates its active sub-goals first', () {
    final changes = deactivating(tree, tree['top']!);

    expect(_described(changes), [
      'update a1 {status: inactive}',
      'update c {status: inactive}',
      'update a {status: inactive}',
      'update top {status: inactive}',
    ]);
    expect(planned(goals, changes, now: _now), isEmpty);
  });

  test('moving a goal makes it fit under its new parent', () {
    final soon = _goal('soon', deadline: '2026-10-20', minutes: 60);
    final all = [...goals, soon];
    final t = GoalTree(all);

    final changes = moving(t, t['top']!, 'soon');

    expect(_described(changes), [
      'update top {parent_id: soon, deadline: 2026-10-20, expected_minutes: 60}',
    ]);
    // Its own sub-goals then don't fit it: refused, naming them.
    expect(planned(all, changes, now: _now), isNotEmpty);
    expect(fitUnder(t['a1']!, t['top']), isEmpty);
  });

  test('deleting a goal deletes its sub-goals, or moves them first', () {
    expect(_described(deleting(tree, tree['a']!)), ['delete a1', 'delete a']);
    final kept = deleting(tree, tree['a']!, keep: true, moveTo: 'top');
    expect(_described(kept), ['update a1 {parent_id: top}', 'delete a']);
    expect(planned(goals, kept, now: _now), isEmpty);
  });

  test('a status change is added to the history as the server adds it', () {
    final after = applied(goals, [
      const GoalUpdate('b', {'status': 'active', 'deadline': '2026-11-02'}),
    ], now: _now);

    final b = after.firstWhere((g) => g.id == 'b');
    expect(b.history.map((c) => c.status), ['inactive', 'active']);
    expect(b.startedAt!.isAtSameMomentAs(_now), isTrue);
  });

  test('quick deadlines are the end of today, and of the week', () {
    expect(endOfToday(DateTime(2026, 10, 17, 9)), '2026-10-17');
    // A Saturday: its week ends the next day.
    expect(endOfWeek(DateTime(2026, 10, 17, 9)), '2026-10-18');
    expect(endOfWeek(DateTime(2026, 10, 18, 9)), '2026-10-18');
  });
}
