import 'package:flutter_test/flutter_test.dart';
import 'package:time_tracker_client/models/goal.dart';
import 'package:time_tracker_client/models/goal_activation.dart';

Goal _goal(
  String id, {
  String status = 'active',
  String? deadline = '2026-11-30',
  String? parent,
  int? priority,
  Map<String, Object?>? activateWhen,
  Map<String, Object?>? deadlineRule,
  DateTime? at,
}) => Goal(
  id: id,
  title: id,
  status: status,
  deadline: deadline,
  parentId: parent,
  priority: priority,
  activateWhen: activateWhen,
  deadlineRule: deadlineRule,
  history: [StatusChange(status, at ?? DateTime(2026, 10, 1))],
);

Goal _closed(Goal goal, DateTime at, [String status = 'done']) =>
    Goal.fromJson({
      ...goal.toJson(),
      'status': status,
      'history': [
        for (final c in goal.history) c.toJson(),
        StatusChange(status, at).toJson(),
      ],
    });

void main() {
  final now = DateTime(2026, 10, 20, 12);

  test('a goal waiting for another to close starts once it does, dated '
      'then, with what it waited for cleared', () {
    final draft = _goal('draft', deadline: '2026-10-25');
    final send = _goal(
      'send',
      status: 'inactive',
      deadline: null,
      deadlineRule: const {
        'after_start': {'days': 2},
      },
      activateWhen: const {
        'after': [
          {'goal_closed': 'draft'},
        ],
      },
    );
    final tree = GoalTree([draft, send]);
    expect(waitsFor(send), ['draft']);
    expect(waitingOn(tree.byId.values, 'draft').map((g) => g.id), ['send']);
    expect(readyAt(send, tree), isNull);
    // Expected when the draft is due: the midnight after its day.
    expect(expectedStart(send, tree, now: now), DateTime(2026, 10, 26));
    expect(expectedDeadline(send, tree, now: now), '2026-10-28');

    final done = DateTime(2026, 10, 19, 15);
    final (after, started) = startingWaiting([_closed(draft, done), send], now);
    expect(started, ['send']);
    final sent = after.last;
    expect((sent.status, sent.activateWhen), ('active', null));
    expect(sent.history.last.at.isAtSameMomentAs(done), isTrue);
    expect(sent.deadline, '2026-10-21');
    expect(sent.history.last.deadline, '2026-10-21');
  });

  test('the next day waits for the start of the day after; a day waits '
      'for its start', () {
    final draft = _closed(
      _goal('draft', deadline: '2026-10-25'),
      DateTime(2026, 10, 20, 9),
    );
    final tomorrow = _goal(
      'tomorrow',
      status: 'inactive',
      activateWhen: const {
        'after': [
          {'goal_closed': 'draft'},
        ],
        'delay': 'next_day',
      },
    );
    final monday = _goal(
      'monday',
      status: 'inactive',
      activateWhen: const {
        'after': [
          {'at': '2026-10-26'},
        ],
      },
    );
    final tree = GoalTree([draft, tomorrow, monday]);
    expect(readyAt(tomorrow, tree), DateTime(2026, 10, 21));
    expect(readyAt(monday, tree), DateTime(2026, 10, 26));
    expect(startingWaiting([draft, tomorrow, monday], now).$2, isEmpty);
    expect(
      startingWaiting([draft, tomorrow, monday], DateTime(2026, 10, 21, 8)).$2,
      ['tomorrow'],
    );

    // Expected the day after the one a goal it waits for is due.
    final open = _goal('open', deadline: '2026-10-25');
    final next = _goal(
      'next',
      status: 'inactive',
      activateWhen: const {
        'after': [
          {'goal_closed': 'open'},
        ],
        'delay': 'next_day',
      },
    );
    expect(
      expectedStart(next, GoalTree([open, next]), now: now),
      DateTime(2026, 10, 26),
    );
  });

  test('a hold keeps it waiting while enough others of its priority are '
      'active; the highest priority goes first', () {
    final busy = [
      _goal('a', priority: 1),
      _goal('b', priority: 0),
      _goal('low', priority: 3),
    ];
    const hold = {
      'hold_while': [
        {
          'active_at_least': 2,
          'priority': {'at_or_above': 'own'},
        },
      ],
    };
    final wait = _goal(
      'wait',
      status: 'inactive',
      priority: 1,
      activateWhen: hold,
    );
    final tree = GoalTree([...busy, wait]);
    expect(isHeld(wait, tree), isTrue);
    expect(startingWaiting([...busy, wait], now).$2, isEmpty);
    final freed = [_closed(busy[0], now), ...busy.skip(1), wait];
    expect(startingWaiting(freed, now).$2, ['wait']);

    // One place for two: the higher priority takes it.
    const one = {
      'hold_while': [
        {'active_at_least': 1},
      ],
    };
    final (_, started) = startingWaiting([
      _goal('minor', status: 'inactive', priority: 2, activateWhen: one),
      _goal('major', status: 'inactive', priority: 0, activateWhen: one),
    ], now);
    expect(started, ['major']);
  });

  test('a goal starting takes its inactive parents; one past its deadline '
      'keeps waiting', () {
    final parent = _goal('parent', status: 'inactive');
    final child = _goal(
      'child',
      status: 'inactive',
      parent: 'parent',
      deadline: '2026-11-01',
      activateWhen: const {
        'after': [
          {'at': '2026-10-19'},
        ],
      },
    );
    final (after, started) = startingWaiting([parent, child], now);
    expect(started.toSet(), {'child', 'parent'});
    expect(after.every((g) => g.active), isTrue);

    final late = _goal(
      'late',
      status: 'inactive',
      deadline: '2026-10-18',
      activateWhen: const {
        'after': [
          {'at': '2026-10-19'},
        ],
      },
    );
    expect(startingWaiting([late], now).$2, isEmpty);
  });
}
