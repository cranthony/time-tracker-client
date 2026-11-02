import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:time_tracker_client/models/goal.dart';
import 'package:time_tracker_client/models/habit.dart';
import 'package:time_tracker_client/models/sub_goal_template.dart';
import 'package:time_tracker_client/screens/habit_screen.dart';
import 'package:time_tracker_client/services/plan_memory.dart';
import 'package:time_tracker_client/widgets/habit_dialog.dart';

/// A dinner's chain: shopping a week ahead, cooking once it's done.
const _shop = <String, Object?>{
  'key': 'shop',
  'title': 'Buy groceries',
  'required': true,
  'deadline': {'days': 2},
  'activate_when': {
    'after': [
      {
        'before_parent': {'days': 7},
      },
    ],
  },
};
const _cook = <String, Object?>{
  'key': 'cook',
  'title': 'Make the sauce',
  'expected_minutes': 180,
  'deadline': {'days': 1},
  'description': 'In the big pot',
  'activate_when': {
    'after': [
      {'goal_closed': 'shop'},
      {
        'before_parent': {'days': 3},
      },
    ],
    'delay': 'next_day',
  },
};
const _finish = <String, Object?>{
  'key': 'finish',
  'title': 'Finish',
  'required': true,
  'expected_minutes': 30,
  'priority': 1,
  'activate_when': {
    'after': [
      {
        'before_parent': {'minutes': 120},
      },
    ],
  },
  // A field the app doesn't know is kept.
  'unknown': 'kept',
};

Habit _dinner() => Habit.fromJson({
  'id': 'h1',
  'name': 'Cook dinner',
  'recurring_goal': {
    'period': 'quarter',
    'title': 'Cook dinner',
    'priority': 2,
    'expected_minutes': 300,
    // Out of order, as a template can be.
    'sub_goals': [_finish, _shop, _cook],
  },
  'traits': {'select': <String>[]},
  'status': 'active',
});

void main() {
  group('a chain', () {
    test('reads and writes its offsets as the server has them', () {
      expect(offsetMinutes({'days': 2}), 2880);
      expect(offsetMinutes({'minutes': 150}), 150);
      expect(offsetMinutes(null), 0);
      expect(offsetOf(2880), {'days': 2});
      expect(offsetOf(150), {'minutes': 150});
      expect(offsetOf(0), {'minutes': 0});
    });

    test('is in the order its sub-goals come due, then start', () {
      expect(
        [
          for (final s in chainOrder([_finish, _cook, _shop])) s['key'],
        ],
        ['shop', 'cook', 'finish'],
      );
    });

    test('keys a new sub-goal from its title, unlike the others', () {
      expect(newSubGoalKey('Buy groceries!', []), 'buy-groceries');
      expect(newSubGoalKey('Shop', ['shop', 'shop-2']), 'shop-3');
      expect(newSubGoalKey('…', []), 'step');
      expect(newSubGoalKey('a' * 60, []).length, lessThanOrEqualTo(40));
    });

    test('removing one stops the others waiting for it', () {
      final left = withoutSubGoal([_shop, _cook, _finish], 0);
      expect([for (final s in left) s['key']], ['cook', 'finish']);
      expect(left.first['activate_when'], {
        'after': [
          {
            'before_parent': {'days': 3},
          },
        ],
        'delay': 'next_day',
      });
      // One left waiting for nothing waits no longer.
      final alone = withoutSubGoal([
        _shop,
        {
          'key': 'b',
          'title': 'B',
          'activate_when': {
            'after': [
              {'goal_closed': 'shop'},
            ],
            'delay': 'next_day',
          },
        },
      ], 0);
      expect(alone.single.containsKey('activate_when'), isFalse);
    });

    test("says what's wrong with it before the server would", () {
      expect(chainProblems([_shop, _cook, _finish], goalMinutes: 300), isEmpty);
      expect(chainProblems([_cook]), [
        '“Make the sauce” waits for a sub-goal there isn’t.',
      ]);
      expect(chainProblems([_cook, _shop], goalMinutes: 60), [
        '“Make the sauce” is expected to take longer than its goal.',
      ]);
      expect(
        chainProblems([
          {
            'key': 'a',
            'title': 'A',
            'activate_when': {
              'after': [
                {'goal_closed': 'b'},
              ],
            },
          },
          {
            'key': 'b',
            'title': 'B',
            'activate_when': {
              'after': [
                {'goal_closed': 'a'},
              ],
            },
          },
        ]),
        ['“A”, “B” wait for each other, so none would start.'],
      );
    });
  });

  testWidgets("a habit's page shows its chain, and its goals' progress", (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1000, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    Goal goal(String id, String status, {String? parentId}) => Goal.fromJson({
      'id': id,
      'title': id,
      'habit_id': 'h1',
      'parent_id': ?parentId,
      'status': status,
      'deadline': {'at': '2026-12-31'},
      'due': '2026-12-31',
    });
    final memory = PlanMemory()
      ..goals = [
        goal('h1_2026-10-01', 'active'),
        goal('h1_2026-10-01_shop', 'done', parentId: 'h1_2026-10-01'),
        goal('h1_2026-10-01_cook', 'inactive', parentId: 'h1_2026-10-01'),
        goal('h1_2026-10-01_finish', 'inactive', parentId: 'h1_2026-10-01'),
      ];
    await tester.pumpWidget(
      MaterialApp(
        home: HabitScreen(habit: _dinner(), memory: memory),
      ),
    );

    expect(find.text('Its chain of sub-goals'), findsOneWidget);
    expect(
      find.text(
        'Due 2 days before its goal · Starts a week before its goal is due',
      ),
      findsOneWidget,
    );
    expect(
      find.text(
        '3h · Optional · Due 1 day before its goal · Starts after “Buy '
        'groceries” closes, 3 days before its goal is due, then the next '
        'day',
      ),
      findsOneWidget,
    );
    expect(
      find.text('30m · Due with its goal · Starts 2h before its goal is due'),
      findsOneWidget,
    );
    // Its sub-goals are under its goals, not among them.
    expect(find.textContaining('1 of 3 sub-goals done'), findsOneWidget);
    expect(find.text('h1_2026-10-01_shop'), findsNothing);

    await tester.tap(find.text('Make the sauce'));
    // Its health keeps spinning, with no events loaded.
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.textContaining('In the big pot'), findsOneWidget);
    expect(find.text('P2, its goal\'s'), findsOneWidget);
  });

  testWidgets("a habit's chain is edited: changed, added to, removed from", (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1000, 4000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    Map<String, Object?>? saved;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => showHabitEditor(
              context,
              habit: _dinner(),
              save: (fields) async {
                saved = fields;
                return _dinner();
              },
            ),
            child: const Text('Open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    // Its goals' priority and expected time are set on its goal's page.
    await tester.tap(find.text('A goal each quarter: Cook dinner'));
    await tester.pumpAndSettle();
    expect(find.text('Edit recurring goal'), findsOneWidget);
    await tester.tap(find.widgetWithText(ChoiceChip, 'P0'));
    await tester.enterText(
      find.widgetWithText(TextField, "Goals' expected time (optional)"),
      '6h',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.textContaining('P0 · 6h'), findsOneWidget);

    // Shopping's due a day sooner.
    await tester.tap(find.text('Buy groceries'));
    await tester.pumpAndSettle();
    expect(find.text('Edit sub-goal'), findsOneWidget);
    await tester.tap(find.text('1 week before').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    // Finishing's removed: nothing waits for it.
    await tester.tap(find.text('Finish'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Remove from the chain'));
    await tester.pumpAndSettle();
    expect(find.text('Finish'), findsNothing);

    // Setting the table's added, after the sauce is done.
    await tester.tap(find.text('Add a sub-goal'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Title'), 'Set it');
    await tester.pumpAndSettle();
    expect(find.text('Its goals’ ids end in “_set-it”.'), findsOneWidget);
    await tester.tap(find.text('It waits'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('After another closes…'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Make the sauce').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Then a while later'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ChoiceChip, 'P3'));
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(
      find.text(
        'Optional · Due with its goal · Starts after “Make the sauce” '
        'closes, then 1h later',
      ),
      findsOneWidget,
    );

    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    final recurring = saved!['recurring_goal']! as Map<String, Object?>;
    expect(recurring['priority'], 0);
    expect(recurring['expected_minutes'], 360);
    expect(recurring['sub_goals'], [
      {
        ..._shop,
        'deadline': {'days': 7},
      },
      _cook,
      {
        'key': 'set-it',
        'title': 'Set it',
        'activate_when': {
          'after': [
            {'goal_closed': 'cook'},
          ],
          'delay': {'minutes': 60},
        },
        'priority': 3,
      },
    ]);
  });

  testWidgets('a sub-goal edited keeps what the app doesn’t edit', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1000, 4000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    Map<String, Object?>? saved;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => showHabitEditor(
              context,
              habit: _dinner(),
              save: (fields) async {
                saved = fields;
                return _dinner();
              },
            ),
            child: const Text('Open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Finish'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Title'), 'Serve');
    await tester.pumpAndSettle();
    expect(
      find.text('Its goals’ ids end in “_finish”, kept as it’s renamed.'),
      findsOneWidget,
    );
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    final subs =
        (saved!['recurring_goal']! as Map<String, Object?>)['sub_goals']!
            as List;
    expect(subs.first, {..._finish, 'title': 'Serve'});
  });
}
