import 'package:flutter_test/flutter_test.dart';
import 'package:time_tracker_client/models/goal.dart';
import 'package:time_tracker_client/models/goal_order.dart';

Goal _goal(
  String id, {
  String? deadline = '2026-11-01',
  int? priority,
  int? order,
}) => Goal(
  id: id,
  title: id,
  deadline: deadline,
  priority: priority,
  sortOrder: order,
);

void main() {
  group('the order goals are listed in', () {
    test('priority, then the day due, then their own order, then the time '
        'due and title', () {
      final goals = [
        _goal('undated', deadline: null),
        _goal('later day', deadline: '2026-11-02'),
        _goal('9am', deadline: '2026-11-01T09:00'),
        _goal('end of day b'),
        _goal('end of day a'),
        _goal('second', deadline: '2026-11-01T17:00', order: 2000),
        _goal('first', deadline: '2026-11-01T18:00', order: 1000),
        _goal('p1', deadline: '2026-12-01', priority: 1),
      ];
      expect(byPriority(goals).map((g) => g.id), [
        'p1',
        'first',
        'second',
        '9am',
        'end of day a',
        'end of day b',
        'later day',
        'undated',
      ]);
    });

    test('goals list alike with the same priority, due the same day', () {
      final tree = GoalTree([
        _goal('a', deadline: '2026-11-01T09:00'),
        _goal('b'),
        _goal('c', priority: 1),
        _goal('d', deadline: '2026-11-02'),
      ]);
      expect(tree.listAlike(tree['a']!, tree['b']!), isTrue);
      expect(tree.listAlike(tree['a']!, tree['c']!), isFalse);
      expect(tree.listAlike(tree['a']!, tree['d']!), isFalse);
    });
  });

  group('moving a goal', () {
    final listed = byPriority([
      _goal('high', priority: 1),
      _goal('a', order: 1000),
      _goal('b', order: 2000),
      _goal('c'),
      _goal('d'),
      _goal('later', deadline: '2026-11-05'),
      _goal('undated', deadline: null),
    ]);
    final tree = GoalTree(listed);

    test('between two with an order, takes one between theirs', () {
      // b, between high and a: the others are high, a, c, d, later...
      final move = moveGoal(listed, tree, 'b', 1);
      expect(move.index, 1);
      expect(move.warning, isNull);
      expect(move.sortOrders, {'b': 0});
    });

    test('before the first, one before its order', () {
      expect(moveGoal(listed, tree, 'a', 1).sortOrders, isEmpty);
      expect(moveGoal(listed, tree, 'b', 1).sortOrders, {'b': 0});
    });

    test('after those with an order, one after the last', () {
      expect(moveGoal(listed, tree, 'a', 2).sortOrders, {'a': 3000});
    });

    test('among those with none, numbers those up to it afresh', () {
      expect(moveGoal(listed, tree, 'a', 4).sortOrders, {
        'b': 1000,
        'c': 2000,
        'd': 3000,
        'a': 4000,
      });
      expect(moveGoal(listed, tree, 'd', 1).sortOrders, {'d': 0});
    });

    test('above a higher-priority goal, kept below it, saying why', () {
      final move = moveGoal(listed, tree, 'c', 0);
      expect(move.index, 1);
      expect(move.warning, "It can't go above a higher-priority goal.");
      expect(move.sortOrders, {'c': 0});
    });

    test('below a goal due later, kept above it, saying why', () {
      final move = moveGoal(listed, tree, 'a', 6);
      expect(move.index, 4);
      expect(move.warning, "It can't go below a goal due later.");
      expect(
        moveGoal(listed, tree, 'later', 1).warning,
        "It can't go above a goal due sooner.",
      );
      expect(
        moveGoal(listed, tree, 'later', 6).warning,
        "It can't go below a goal with no deadline.",
      );
      expect(
        moveGoal(listed, tree, 'high', 3).warning,
        "It can't go below a lower-priority goal.",
      );
    });

    test('where it was, nothing is saved', () {
      final move = moveGoal(listed, tree, 'later', 0);
      expect(move.index, 5);
      expect(move.sortOrders, isEmpty);
    });

    test('between two whose orders are next to each other, numbers them '
        'afresh', () {
      final close = byPriority([
        _goal('x', order: 1),
        _goal('y', order: 2),
        _goal('z', order: 3),
      ]);
      expect(moveGoal(close, GoalTree(close), 'z', 1).sortOrders, {
        'x': 1000,
        'z': 2000,
        'y': 3000,
      });
    });
  });
}
