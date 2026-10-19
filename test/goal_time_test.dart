import 'package:flutter_test/flutter_test.dart';
import 'package:time_tracker_client/models/event.dart';
import 'package:time_tracker_client/models/goal.dart';

/// Ship › Pane › Icon, and Learn on its own.
final _tree = GoalTree([
  const Goal(id: 'ship', title: 'Ship'),
  const Goal(id: 'pane', title: 'Pane', parentId: 'ship'),
  const Goal(id: 'icon', title: 'Icon', parentId: 'pane'),
  const Goal(id: 'learn', title: 'Learn'),
]);

const _hour = Duration(hours: 1);

Duration _m(int minutes) => Duration(minutes: minutes);

Event _event(List<Map<String, Object?>> goals, {int minutes = 60}) => Event(
  start: DateTime(2026, 10, 17, 9),
  end: DateTime(2026, 10, 17, 9).add(_m(minutes)),
  properties: {'goals': goals},
);

void main() {
  group('a goal share', () {
    test('takes fixed minutes first, then percents of the rest', () {
      final times = shareTimes(const [
        GoalShare('a', percent: 50),
        GoalShare('b', minutes: 20),
        GoalShare('c'),
        GoalShare('d', minutes: 10),
      ], _hour);

      // c, with neither, takes the 15 minutes the others leave.
      expect(times, {'b': _m(20), 'd': _m(10), 'a': _m(15), 'c': _m(15)});
    });

    test('with the rest too, takes the remaining time as well as its own', () {
      final times = shareTimes(const [
        GoalShare('a', minutes: 20, remaining: true),
        GoalShare('b', percent: 50),
        GoalShare('c'),
      ], _hour);

      // 20 fixed, 50% of the 40 left: 20 remaining, all of it to a and c.
      expect(times, {'a': _m(40), 'b': _m(20), 'c': _m(20)});
    });

    test('says it takes the rest in its label and to the server', () {
      const share = GoalShare('a', minutes: 20, remaining: true);
      expect(share.label, '20m + the rest');
      expect(share.toJson(), {
        'goal_id': 'a',
        'minutes': 20,
        'remaining': true,
      });
      expect(GoalShare.fromJson(share.toJson()), share);
      expect(const GoalShare('a', remaining: true), const GoalShare('a'));
    });

    test('is cut to fit an event shortened since', () {
      final times = shareTimes(const [
        GoalShare('a', minutes: 40),
        GoalShare('b', minutes: 40),
      ], _m(60));

      expect(times, {'a': _m(40), 'b': _m(20)});
    });

    test('is read from the event as the server lists it', () {
      final event = _event([
        {'goal_id': 'ship', 'minutes': 45, 'percent': null},
        {'goal_id': 'learn', 'minutes': null, 'percent': 30},
        {'goal_id': 'icon'},
      ]);

      expect(event.goals, const [
        GoalShare('ship', minutes: 45),
        GoalShare('learn', percent: 30),
        GoalShare('icon'),
      ]);
      expect(_event([]).goals, isEmpty);
    });

    test('is checked as the server checks it', () {
      expect(shareProblems(const [GoalShare('a', minutes: 60)], 60), isEmpty);
      expect(
        shareProblems(const [
          GoalShare('a', minutes: 40),
          GoalShare('b', minutes: 21),
        ], 60),
        [contains('more than the event')],
      );
      expect(
        shareProblems(const [
          GoalShare('a', percent: 70),
          GoalShare('b', percent: 31),
        ], 60),
        [contains('more than 100%')],
      );
    });
  });

  group('a parent goal', () {
    test("gets its own share and its sub-goals' together", () {
      final times = goalTimes(
        const [GoalShare('ship', minutes: 20), GoalShare('icon', minutes: 30)],
        _hour,
        _tree,
      );

      expect(times, {'ship': _m(50), 'pane': _m(30), 'icon': _m(30)});
    });

    test('never gets more than the event', () {
      final times = goalTimes(
        const [
          GoalShare('pane', percent: 80),
          GoalShare('icon', percent: 20),
          GoalShare('ship', minutes: 30),
        ],
        _hour,
        _tree,
      );

      // 30 fixed, then 80% and 20% of the 30 left: 24 + 6.
      expect(times['ship'], _hour);
      expect(times['pane'], _m(30));
      expect(times['icon'], _m(6));
    });

    test('gets the remaining time once when it or one under it takes it', () {
      final whole = goalTimes(
        const [GoalShare('ship', minutes: 20), GoalShare('icon')],
        _hour,
        _tree,
      );
      expect(whole, {'ship': _hour, 'pane': _m(40), 'icon': _m(40)});

      final both = goalTimes(
        const [GoalShare('ship'), GoalShare('pane')],
        _hour,
        _tree,
      );
      expect(both, {'ship': _hour, 'pane': _hour});
    });

    test("leaves out goals that aren't there any more", () {
      final times = goalTimes(
        const [GoalShare('gone'), GoalShare('learn', minutes: 10)],
        _hour,
        _tree,
      );

      expect(times, {'learn': _m(10)});
    });
  });

  test('time spent adds up every event, a parent never more than each', () {
    final spent = timeSpent([
      _event([
        {'goal_id': 'icon'},
        {'goal_id': 'pane'},
        {'goal_id': 'ship', 'minutes': 50},
      ]),
      _event([
        {'goal_id': 'learn', 'percent': 50},
      ], minutes: 30),
      _event([]),
    ], _tree);

    // Ship's 50 minutes and the 10 left, which Pane and Icon take.
    expect(spent, {
      'ship': _hour,
      'pane': _m(10),
      'icon': _m(10),
      'learn': _m(15),
    });
  });

  test('top-level fractions split an event no more than whole', () {
    final fractions = topLevelFractions(
      const [
        GoalShare('icon', minutes: 30, remaining: true),
        GoalShare('learn'),
      ],
      _hour,
      _tree,
    );

    // Ship's whole hour (its 30 and the 30 left) and Learn's 30 left:
    // scaled to two thirds and a third.
    expect(fractions['ship'], closeTo(2 / 3, 1e-9));
    expect(fractions['learn'], closeTo(1 / 3, 1e-9));
    expect(
      topLevelFractions(const [GoalShare('pane', minutes: 15)], _hour, _tree),
      {'ship': 0.25},
    );
  });

  group('a goal', () {
    test('falls due at the end of its day unless given a time', () {
      expect(deadlineEnd('2026-11-01'), DateTime(2026, 11, 2));
      expect(deadlineEnd('2026-11-01T17:00'), DateTime(2026, 11, 1, 17));
      expect(deadlineEnd('Friday'), isNull);
      expect(deadlineOf(DateTime(2026, 3, 4, 5, 6)), '2026-03-04');
      expect(
        deadlineOf(DateTime(2026, 3, 4, 5, 6), time: true),
        '2026-03-04T05:06',
      );
    });

    test('says when it started and closed from its history', () {
      final goal = Goal.fromJson({
        'id': 'g',
        'title': 'G',
        'status': 'done',
        'history': [
          {'status': 'inactive', 'at': '2026-10-01T09:00:00-04:00'},
          {'status': 'active', 'at': '2026-10-02T09:00:00-04:00'},
          {'status': 'done', 'at': '2026-10-09T09:00:00-04:00'},
        ],
        'path': ['Ship'],
      });

      expect(goal.startedAt, DateTime.parse('2026-10-02T09:00:00-04:00'));
      expect(goal.closedAt, DateTime.parse('2026-10-09T09:00:00-04:00'));
      expect(goal.path, ['Ship']);
      expect(goal.toJson()['history'], hasLength(3));
    });

    test('tree knows each goal\'s parents, children and depth', () {
      expect(_tree.topLevel.map((g) => g.id), ['ship', 'learn']);
      expect(_tree.pathOf('icon'), ['Ship', 'Pane']);
      expect(_tree.depthOf('icon'), 2);
      expect(_tree.descendantsOf('ship').map((g) => g.id), ['pane', 'icon']);
      expect(_tree.isWithin('icon', 'ship'), isTrue);
      expect(_tree.isWithin('learn', 'ship'), isFalse);
    });

    test('lists soonest due first, undated last', () {
      final listed = byPriority(const [
        Goal(id: 'c', title: 'C'),
        Goal(id: 'b', title: 'B', deadline: '2026-11-02'),
        Goal(id: 'a', title: 'A', deadline: '2026-11-01T17:00'),
      ]);
      expect(listed.map((g) => g.id), ['a', 'b', 'c']);
    });

    test('a goal takes its nearest priority up its tree, or P3', () {
      final tree = GoalTree(const [
        Goal(id: 'top', title: 'Top', priority: 1),
        Goal(id: 'mid', title: 'Mid', parentId: 'top'),
        Goal(id: 'leaf', title: 'Leaf', parentId: 'mid'),
        Goal(id: 'own', title: 'Own', parentId: 'mid', priority: 0),
        Goal(id: 'alone', title: 'Alone'),
      ]);
      expect(
        [
          for (final id in ['top', 'mid', 'leaf', 'own', 'alone'])
            tree.priorityOf(id),
        ],
        [1, 1, 1, 0, defaultGoalPriority],
      );
      expect(defaultGoalPriority, 3);
    });

    test('lists the highest priority first, then soonest due', () {
      const goals = [
        Goal(id: 'p3 soon', title: 'A', deadline: '2026-11-01'),
        Goal(id: 'p1 late', title: 'B', deadline: '2026-12-01', priority: 1),
        Goal(id: 'p0 none', title: 'C', priority: 0),
        Goal(id: 'p1 soon', title: 'D', deadline: '2026-11-01', priority: 1),
        Goal(id: 'under p0', title: 'E', parentId: 'p0 none'),
      ];
      final tree = GoalTree(goals);
      expect(byPriority(goals, tree).map((g) => g.id), [
        'p0 none',
        'under p0',
        'p1 soon',
        'p1 late',
        'p3 soon',
      ]);
      // Without its parent there, a goal is P3.
      expect(
        byPriority(goals.where((g) => g.id != 'p0 none')).last.id,
        'under p0',
      );
    });
  });

  group('the rules', () {
    Goal goal(
      String id, {
      String? parent,
      String status = 'active',
      String? deadline = '2026-12-01',
      int? minutes,
    }) => Goal.fromJson({
      'id': id,
      'title': id,
      'parent_id': parent,
      'status': status,
      'deadline': deadline,
      'expected_minutes': minutes,
      'history': [
        {'status': status, 'at': '2026-10-17T09:00:00'},
      ],
    });

    test('hold for goals as the server keeps them', () {
      expect(
        goalProblems([
          goal('top', minutes: 600),
          goal('sub', parent: 'top', deadline: '2026-11-01', minutes: 600),
          goal('later', parent: 'top', status: 'inactive', deadline: null),
        ]),
        isEmpty,
      );
    });

    test('say what breaks them', () {
      expect(goalProblems([goal('a', deadline: null)]), [
        contains('needs a deadline'),
      ]);
      expect(
        goalProblems([
          goal('top'),
          goal('sub', parent: 'top', deadline: '2026-12-02'),
        ]),
        [contains('due after')],
      );
      expect(
        goalProblems([
          goal('top', minutes: 60),
          goal('sub', parent: 'top', minutes: 61),
        ]),
        [contains('longer than')],
      );
      expect(
        goalProblems([goal('top', status: 'done'), goal('sub', parent: 'top')]),
        [contains('is active, but “top” is done')],
      );
      expect(
        goalProblems([
          goal('top', status: 'inactive', deadline: null),
          goal('sub', parent: 'top'),
        ]),
        [contains('is inactive')],
      );
      expect(
        goalProblems([goal('top', parent: 'sub'), goal('sub', parent: 'top')]),
        [contains('under itself'), contains('under itself')],
      );
    });
  });
}
