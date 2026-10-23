import 'package:flutter_test/flutter_test.dart';
import 'package:time_tracker_client/models/goal.dart';

void main() {
  test("a goal as the server lists it: its due, and what it's measured "
      'from', () {
    final fixed = Goal.fromJson({
      'id': 'a',
      'title': 'A',
      'deadline': {'at': '2026-11-01'},
      'due': '2026-11-01',
    });
    expect(
      (fixed.deadline, fixed.deadlineOffsetMinutes, fixed.deadlineRule),
      ('2026-11-01', null, null),
    );

    final tied = Goal.fromJson({
      'id': 'b',
      'title': 'B',
      'deadline': {
        'before_parent': {'days': 2},
      },
      'due': '2026-10-30',
    });
    expect((tied.deadline, tied.deadlineOffsetMinutes), ('2026-10-30', 2880));
    expect(tied.followsParent, isTrue);

    final waiting = Goal.fromJson({
      'id': 'c',
      'title': 'C',
      'status': 'inactive',
      'deadline': {
        'after_start': {'days': 3},
      },
      'due': null,
      'activate_when': {
        'after': [
          {'goal_closed': 'a'},
        ],
        'delay': 'next_day',
      },
      'expected_start': '2026-11-02',
    });
    expect(waiting.deadline, isNull);
    expect(waiting.deadlineRule, {
      'after_start': {'days': 3},
    });
    expect(waiting.activateWhen?['delay'], 'next_day');
    expect(waiting.expectedStart, '2026-11-02');

    // Kept here, and read back, as the app keeps it.
    expect(Goal.fromJson(waiting.toJson()).toJson(), waiting.toJson());
    expect(Goal.fromJson(tied.toJson()).deadlineOffsetMinutes, 2880);
  });

  test("a change kept here, a date waiting to be written over the server's "
      'deadline, reads as that date', () {
    final shown = Goal.fromJson({
      'id': 'b',
      'title': 'B',
      'due': '2026-10-30',
      // The change waiting to be written, over the listed goal.
      'deadline': '2026-11-05',
    });
    expect(
      (shown.deadline, shown.deadlineOffsetMinutes, shown.deadlineRule),
      ('2026-11-05', null, null),
    );
  });

  test('goalWire: a deadline as the server takes it, and nothing it works '
      'out', () {
    expect(goalWire({'deadline': '2026-11-01'}), {
      'deadline': {'at': '2026-11-01'},
    });
    expect(
      goalWire({'deadline': '2026-11-01', 'deadline_offset_minutes': 1440}),
      {
        'deadline': {
          'before_parent': {'days': 1},
        },
      },
    );
    expect(goalWire({'deadline_offset_minutes': 90}), {
      'deadline': {
        'before_parent': {'minutes': 90},
      },
    });
    expect(
      goalWire({
        'deadline': null,
        'deadline_rule': {
          'after_start': {'days': 2},
        },
      }),
      {
        'deadline': {
          'after_start': {'days': 2},
        },
      },
    );
    expect(goalWire({'deadline': null}), {'deadline': null});
    expect(
      goalWire({'deadline': '2026-11-01', 'deadline_offset_minutes': null}),
      {
        'deadline': {'at': '2026-11-01'},
      },
    );
    final whole = Goal(
      id: 'w',
      title: 'W',
      status: 'inactive',
      deadlineRule: const {
        'after_goal': {'id': 'a', 'days': 1},
      },
      expectedStart: '2026-11-02',
      path: const ['Top'],
    ).toJson();
    expect(goalWire(whole), {
      'id': 'w',
      'title': 'W',
      'deadline': {
        'after_goal': {'id': 'a', 'days': 1},
      },
      'status': 'inactive',
    });
  });

  test('followingParents works out a deadline from a start, once started, '
      "and one after another goal's", () {
    final goals = followingParents([
      Goal(
        id: 'first',
        title: 'First',
        deadline: '2026-10-20T17:00',
        history: [StatusChange('active', DateTime(2026, 10, 1))],
      ),
      Goal(
        id: 'after',
        title: 'After',
        deadlineRule: const {
          'after_goal': {'id': 'first', 'days': 2},
        },
        history: [StatusChange('active', DateTime(2026, 10, 1))],
      ),
      Goal(
        id: 'started',
        title: 'Started',
        deadlineRule: const {
          'after_start': {'days': 3},
        },
        history: [StatusChange('active', DateTime(2026, 10, 18, 9))],
      ),
      Goal(
        id: 'waiting',
        title: 'Waiting',
        status: 'inactive',
        deadlineRule: const {
          'after_start': {'minutes': 90},
        },
        history: [StatusChange('inactive', DateTime(2026, 10, 18, 9))],
      ),
    ]);
    expect(goals.map((g) => g.deadline), [
      '2026-10-20T17:00',
      '2026-10-22T17:00',
      '2026-10-21',
      null,
    ]);
  });

  test('an active goal may be under an inactive one, but an open goal '
      'needs a deadline it can work out', () {
    final parent = Goal(
      id: 'p',
      title: 'Parent',
      status: 'inactive',
      deadline: '2026-12-01',
      history: [StatusChange('inactive', DateTime(2026, 10, 1))],
    );
    final child = Goal(
      id: 'c',
      title: 'Child',
      parentId: 'p',
      deadline: '2026-11-01',
      history: [StatusChange('active', DateTime(2026, 10, 1))],
    );
    expect(goalProblems([parent, child]), isEmpty);
    final someday = Goal(
      id: 's',
      title: 'Someday',
      status: 'inactive',
      history: [StatusChange('inactive', DateTime(2026, 10, 1))],
    );
    expect(goalProblems([someday]), [
      '“Someday” needs a deadline, to have when it starts.',
    ]);
  });
}
