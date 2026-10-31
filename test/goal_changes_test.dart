import 'package:flutter_test/flutter_test.dart';
import 'package:time_tracker_client/models/goal.dart';
import 'package:time_tracker_client/models/goal_changes.dart';
import 'package:time_tracker_client/models/note.dart';

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

  test('a missed goal is closed, and a missed required sub-goal does not '
      'hold up its parent', () {
    final missed = [
      _goal('top'),
      _goal(
        'a',
        parent: 'top',
        status: 'missed',
        deadline: null,
        required: true,
      ),
      _goal('b', parent: 'top', deadline: '2026-11-01'),
    ];
    final t = GoalTree(missed);
    expect(t['a']!.closed, isTrue);
    expect(t['a']!.closedAt, DateTime(2026, 10, 1, 9));
    expect(requiredOpen(t, t['top']!), isEmpty);

    final changes = closing(
      t,
      t['top']!,
      'done',
      leftovers: {'b': const CloseLeftover('missed')},
    );
    expect(_described(changes), [
      'update b {status: missed}',
      'update top {status: done}',
    ]);
    expect(planned(missed, changes, now: _now), isEmpty);
  });

  test('closing a goal alone is refused while its sub-goals are open', () {
    final problems = planned(goals, [
      const GoalUpdate('top', {'status': 'done'}),
    ], now: _now);
    expect(problems, isNotEmpty);
  });

  test('activating a goal leaves its inactive parents inactive', () {
    final deep = [
      _goal('p', status: 'inactive'),
      _goal('q', parent: 'p', status: 'inactive'),
      _goal('r', parent: 'q', status: 'inactive', deadline: null),
    ];
    final t = GoalTree(deep);

    final changes = activating(t, [t['r']!], deadlines: {'r': '2026-10-30'});

    expect(_described(changes), [
      'update r {status: active, deadline: 2026-10-30}',
    ]);
    expect(planned(deep, changes, now: _now), isEmpty);
    // Without a deadline, it's refused.
    expect(planned(deep, activating(t, [t['r']!]), now: _now), isNotEmpty);
  });

  test('a goal activated from an event still to come waits for it', () {
    final waiting = _goal('w', status: 'inactive');
    final changes = waitingFor([
      waiting,
      _goal('a'),
    ], DateTime(2026, 11, 1, 10));

    expect(_described(changes), [
      'update w {activate_when: {after: [{at: 2026-11-01T10:00}]}}',
    ]);
    expect(planned([waiting], changes, now: _now), isEmpty);
  });

  test('an activation is backdated, but never past its last change or '
      'after now', () {
    final goal = _goal('g', status: 'inactive');
    final earlier = DateTime(2026, 10, 15, 8);
    expect(backdatedTo(goal, earlier, now: _now), earlier);
    expect(
      backdatedTo(goal, DateTime(2026, 9, 1), now: _now),
      DateTime.parse('2026-10-01T09:00:00'),
    );
    expect(backdatedTo(goal, DateTime(2026, 11, 1, 10), now: _now), _now);
  });

  test('deactivating a goal leaves its active sub-goals active', () {
    final changes = deactivating(tree, tree['top']!);

    expect(_described(changes), ['update top {status: inactive}']);
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

  test('a status change records the deadline the goal has then', () {
    final after = applied(goals, [
      const GoalUpdate('b', {'status': 'active', 'deadline': '2026-11-02'}),
      const GoalUpdate('c', {'status': 'done'}),
    ], now: _now);

    final b = after.firstWhere((g) => g.id == 'b');
    expect(b.history.last.deadline, '2026-11-02');
    final c = after.firstWhere((g) => g.id == 'c');
    expect(c.history.last.deadline, '2026-11-20');
    expect(c.history.first.deadline, isNull);
    expect(c.history.last.toJson(), {
      'status': 'done',
      'at': localIsoTimestamp(_now),
      'deadline': '2026-11-20',
    });
    expect(c.history.first.toJson().containsKey('deadline'), isFalse);
  });

  test('a goal missed and tried again keeps the deadline it missed, and '
      'its status', () {
    final changes = retrying(tree['c']!, '2026-11-27', now: _now);
    expect(planned(goals, changes, now: _now), isEmpty);

    final c = applied(goals, changes, now: _now).firstWhere((g) => g.id == 'c');
    expect(c.status, 'active');
    expect(c.deadline, '2026-11-27');
    expect(c.history.map((h) => h.status), ['active', 'missed', 'active']);
    expect(c.history.map((h) => h.deadline), [
      null,
      '2026-11-20',
      '2026-11-27',
    ]);
    expect(c.history[1].at.isAtSameMomentAs(_now), isTrue);
    expect(c.misses.map((h) => h.deadline), ['2026-11-20']);
    expect(c.open, isTrue);
    expect(c.closedAt, isNull);

    // An inactive goal stays inactive.
    final b = applied(
      goals,
      retrying(
        _goal('b', status: 'inactive', deadline: '2026-10-10'),
        '2026-10-24',
        now: _now,
      ),
      now: _now,
    ).firstWhere((g) => g.id == 'b');
    expect(b.status, 'inactive');
    expect(b.history.map((h) => h.status), ['inactive', 'missed', 'inactive']);
  });

  test('quick deadlines are the end of today, and of the week', () {
    expect(endOfToday(DateTime(2026, 10, 17, 9)), '2026-10-17');
    // A Saturday: its week ends the next day.
    expect(endOfWeek(DateTime(2026, 10, 17, 9)), '2026-10-18');
    expect(endOfWeek(DateTime(2026, 10, 18, 9)), '2026-10-18');
  });

  test("a deadline before its parent's is a date while it's whole days", () {
    expect(deadlineBefore('2026-11-20', 0), '2026-11-20');
    expect(deadlineBefore('2026-11-20', 7 * 24 * 60), '2026-11-13');
    expect(deadlineBefore('2026-11-01', 60), '2026-11-01T23:00');
    expect(deadlineBefore('2026-11-20T17:00', 24 * 60), '2026-11-19T17:00');
    expect(deadlineBefore(null, 0), isNull);
  });

  test("a tied sub-goal follows its parent's deadline at any depth, until "
      'given one of its own or moved to the top', () {
    final tied = [
      _goal('top', deadline: '2026-11-20'),
      Goal.fromJson({
        ..._goal('mid', parent: 'top').toJson(),
        'deadline_offset_minutes': 24 * 60,
      }),
      Goal.fromJson({
        ..._goal('low', parent: 'mid').toJson(),
        'deadline_offset_minutes': 0,
      }),
    ];
    Map<String, (String?, int?)> deadlines(List<Goal> goals) => {
      for (final g in goals) g.id: (g.deadline, g.deadlineOffsetMinutes),
    };

    var after = applied(tied, [
      const GoalUpdate('top', {'deadline': '2026-11-10'}),
    ], now: _now);
    expect(deadlines(after), {
      'top': ('2026-11-10', null),
      'mid': ('2026-11-09', 24 * 60),
      'low': ('2026-11-09', 0),
    });

    after = applied(after, [
      const GoalUpdate('mid', {'deadline': '2026-11-01'}),
      const GoalUpdate('low', {'parent_id': null}),
      const GoalUpdate('top', {'deadline': '2026-11-05'}),
    ], now: _now);
    expect(deadlines(after), {
      'top': ('2026-11-05', null),
      'mid': ('2026-11-01', null),
      'low': ('2026-11-01', null),
    });
  });

  test("a goal's edit comes with what its new status takes", () {
    expect(
      _described(editing(tree, tree['b']!, {'title': 'B!'}, status: 'active')),
      ["update b {title: B!, status: active}"],
    );
    expect(
      _described(editing(tree, tree['a']!, {'title': 'A!'}, status: 'done')),
      ['update a1 {status: done}', 'update a {title: A!, status: done}'],
    );
    expect(_described(editing(tree, tree['a']!, {'title': 'A!'})), [
      'update a {title: A!}',
    ]);
  });

  test('a close keeps the note left with it on the history entry it adds, '
      'beside the goal on the wire', () {
    final changes = closing(tree, tree['a']!, 'done', note: 'Shipped');
    expect(_described(changes), [
      'update a1 {status: done}',
      'update a {status: done, status_note: Shipped}',
    ]);
    expect(goalWire({'status': 'done', 'status_note': 'Shipped'}), {
      'status': 'done',
    });

    final after = applied(goals, changes, now: _now);
    final a = after.firstWhere((g) => g.id == 'a');
    expect(a.history.last.note, 'Shipped');
    expect(a.history.last.toJson()['note'], 'Shipped');
    expect(a.toJson().containsKey('status_note'), isFalse);
    // A sub-goal closed with it gets no note, and its entry says none.
    final a1 = after.firstWhere((g) => g.id == 'a1');
    expect(a1.history.last.note, isNull);
    expect(a1.history.last.toJson().containsKey('note'), isFalse);
    // Without one, neither does the goal's own.
    final plain = applied(
      goals,
      closing(tree, tree['a']!, 'done'),
      now: _now,
    ).firstWhere((g) => g.id == 'a');
    expect(plain.history.last.toJson().containsKey('note'), isFalse);
  });
}
