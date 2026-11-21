import 'package:flutter_test/flutter_test.dart';
import 'package:time_tracker_client/models/goal.dart';
import 'package:time_tracker_client/models/goal_changes.dart';
import 'package:time_tracker_client/models/goal_queue.dart';

final _now = DateTime(2026, 11, 21, 12);

Goal _goal(
  String id, {
  String status = 'inactive',
  String deadline = '2026-12-31',
  String? parent,
  Object? after,
  bool held = false,
}) => Goal(
  id: id,
  title: id,
  status: status,
  deadline: deadline,
  parentId: parent,
  activateWhen: held || status != 'inactive'
      ? null
      : {
          'after': switch (after) {
            null => const [],
            final String one => [
              {'goal_closed': one},
            ],
            final List several => several,
            _ => throw ArgumentError(after),
          },
        },
  history: [StatusChange(status, DateTime(2026, 11, 1))],
);

/// Each goal's queue order, as "front > a > b" with branches in
/// brackets.
String _drawn(GoalQueue q) {
  String draw(QueueNode n) => switch (n.next) {
    [] => n.goal.id,
    [final one] => '${n.goal.id} > ${draw(one)}',
    final several => '${n.goal.id} > [${several.map(draw).join(' | ')}]',
  };
  return '${q.kind.name}: ${draw(q.front)}';
}

List<String> _queues(List<Goal> goals) => [
  for (final q in goalQueues(goals, now: _now)) _drawn(q),
];

/// [goals] with [changes] made.
List<Goal> _made(List<Goal> goals, List<GoalChange> changes) =>
    applied(goals, changes, now: _now);

void main() {
  final work = _goal('work', status: 'active', deadline: '2026-11-25');
  final a = _goal('a', after: 'work', deadline: '2026-11-28');
  final b = _goal('b', after: 'a');
  final c = _goal('c', after: 'b');
  final queue = [work, a, b, c];

  test('a queue runs from its active front through what waits for each', () {
    expect(_queues(queue), ['active: work > a > b > c']);
  });

  test('an active goal with nothing queued behind it is no queue', () {
    final alone = _goal('alone', status: 'active');
    expect(_queues([...queue, alone]), ['active: work > a > b > c']);
  });

  test('fronts on hold, waiting for a time, and forks', () {
    final held = _goal('held', held: true);
    final later = _goal(
      'later',
      after: [
        {'at': '2026-12-05'},
      ],
    );
    final forked = _goal('side', after: 'a', deadline: '2026-12-01');
    expect(_queues([...queue, held, later, forked]), [
      'active: work > a > [side | b > c]',
      'waiting: later',
      'onHold: held',
    ]);
  });

  test('one waiting for two is behind the one expected to close last', () {
    final other = _goal('other', status: 'active', deadline: '2026-12-20');
    final both = _goal(
      'both',
      after: [
        {'goal_closed': 'a'},
        {'goal_closed': 'other'},
      ],
    );
    final queues = goalQueues([...queue, other, both], now: _now);
    expect(queues.map(_drawn), [
      'active: work > a > b > c',
      'active: other > both',
    ]);
    expect(queues[1].front.next.single.alsoWaitsFor, ['a']);
  });

  test('leaving closes the queue up behind it', () {
    expect(
      _queues(
        _made(queue, leavingQueue(queue, 'b'))..removeWhere((g) => g.id == 'b'),
      ),
      ['active: work > a > c'],
    );
  });

  test('deleting one splices what waited for it, as the server does', () {
    expect(_queues(_made(queue, [const GoalDelete('a')])), [
      'active: work > b > c',
    ]);
    // One held: what waited for it is held too.
    final held = _goal('held', held: true);
    final next = _goal('next', after: 'held');
    final after = _made([held, next], [const GoalDelete('held')]);
    expect(after.single.activateWhen, isNull);
    expect(after.single.inactive, isTrue);
  });

  test('moving one later, earlier, or to the front', () {
    expect(
      _queues(
        _made(
          queue,
          movingInQueue(queue, 'a', const QueueSlot(after: 'b', before: 'c')),
        ),
      ),
      ['active: work > b > a > c'],
    );
    expect(
      _queues(
        _made(
          queue,
          movingInQueue(
            queue,
            'c',
            const QueueSlot(after: 'work', before: 'a'),
          ),
        ),
      ),
      ['active: work > c > a > b'],
    );
    // In front of the active goal: it starts, and that one waits for it.
    final changes = movingInQueue(queue, 'b', const QueueSlot.front('work'));
    final moved = _made(queue, changes);
    expect(_queues(moved), ['active: b > work > a > c']);
    expect(changes.length, 3);
  });

  test('moving the active front back starts the one behind it', () {
    final moved = _made(
      queue,
      movingInQueue(queue, 'work', const QueueSlot(after: 'a', before: 'b')),
    );
    expect(_queues(moved), ['active: a > work > b > c']);
  });

  test('a held queue put behind another goal is a branch of its tree', () {
    final held = _goal('held', held: true);
    final next = _goal('next', after: 'held');
    final goals = [...queue, held, next];
    final moved = _made(
      goals,
      movingBranch(goals, 'held', const QueueSlot(after: 'a')),
    );
    expect(_queues(moved), ['active: work > a > [b > c | held > next]']);
    // Moved alone, it leaves the rest of its queue held.
    expect(
      _queues(
        _made(goals, movingInQueue(goals, 'held', const QueueSlot(after: 'a'))),
      ),
      ['active: work > a > [b > c | held]', 'onHold: next'],
    );
  });

  test('slots leave out those in or behind the goal moved', () {
    final q = goalQueues(queue, now: _now).single;
    String name(QueueSlot s) => '${s.after}/${s.before}';
    expect(slotsIn(q, id: 'b').map(name), ['null/work', 'work/a', 'a/null']);
    expect(slotsIn(q).map(name), [
      'null/work',
      'work/a',
      'a/b',
      'b/c',
      'c/null',
    ]);
  });

  test('a goal put ahead of another in a queue: that one waits for it, '
      "and where it's put is never sent", () {
    final when = {
      'after': [
        {'goal_closed': 'a'},
      ],
      aheadOfKey: 'b',
    };
    final (cleaned, more) = queuedAhead(queue, 'new', when);
    expect(cleaned, {
      'after': [
        {'goal_closed': 'a'},
      ],
    });
    final made = _made([...queue, _goal('new', after: 'a')], more);
    expect(_queues(made), ['active: work > a > new > b > c']);
    expect(goalWire({'activate_when': when})['activate_when'], cleaned);
  });
}
