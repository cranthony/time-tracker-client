import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:time_tracker_client/models/goal.dart';
import 'package:time_tracker_client/widgets/goal_starts.dart';
import 'package:time_tracker_client/widgets/goal_tile.dart';

Goal _goal(
  String id, {
  String status = 'active',
  String? deadline,
  Map<String, Object?>? activateWhen,
}) => Goal.fromJson({
  'id': id,
  'title': id,
  'status': status,
  'deadline': deadline,
  'activate_when': activateWhen,
  'history': [
    {'status': status, 'at': '2026-01-01T09:00:00'},
  ],
});

Goal _waiting(String id, Map<String, Object?> activateWhen) =>
    _goal(id, status: 'inactive', activateWhen: activateWhen);

void main() {
  Future<void> pump(WidgetTester tester, List<Goal> goals) async {
    final tree = GoalTree(goals);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListView(
            children: [
              for (final g in goals)
                if (g.inactive) GoalTile(goal: g, tree: tree),
            ],
          ),
        ),
      ),
    );
  }

  testWidgets("a waiting goal's tile says when it starts: by the deadline "
      'of the goal it waits for, then the next day', (tester) async {
    await pump(tester, [
      _goal('Draft', deadline: '2099-11-01'),
      _waiting('Ship', {
        'after': [
          {'goal_closed': 'Draft'},
        ],
        'delay': 'next_day',
      }),
      _waiting('Launch', {
        'after': [
          {'at': '2099-11-02T09:00'},
        ],
      }),
    ]);
    expect(find.text('Starts Mon, Nov 2'), findsOneWidget);
    expect(find.text('Starts Mon, Nov 2, 9:00 AM'), findsOneWidget);
  });

  testWidgets('a start is pictured by its day: today, tomorrow with its '
      'weekday and date, or else its weekday and date', (tester) async {
    late BuildContext context;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (c) {
            context = c;
            return const SizedBox();
          },
        ),
      ),
    );
    final now = DateTime(2026, 11, 24, 16);
    String label(DateTime at) => startDayLabel(context, at, now: now);
    expect(label(DateTime(2026, 11, 24, 18)), 'today, 6:00 PM');
    expect(label(DateTime(2026, 11, 25)), 'tomorrow (Wed, Nov 25)');
    expect(label(DateTime(2026, 11, 25, 9)), 'tomorrow (Wed, Nov 25), 9:00 AM');
    expect(label(DateTime(2026, 11, 27)), 'Fri, Nov 27');
    expect(label(DateTime(2026, 12, 1)), 'Tue, Dec 1');
  });

  testWidgets('with no deadline to go by, it says what it waits for', (
    tester,
  ) async {
    await pump(tester, [
      _goal('Draft'),
      _goal('Review'),
      _goal('Done', status: 'done'),
      _waiting('Ship', {
        'after': [
          {'goal_closed': 'Draft'},
        ],
        'delay': 'next_day',
      }),
      _waiting('Launch', {
        'after': [
          {'goal_closed': 'Draft'},
          {'goal_closed': 'Review'},
          {'goal_closed': 'Done'},
        ],
        'delay': {'minutes': 90},
      }),
    ]);
    expect(
      find.text('Starts after “Draft” closes, the next day'),
      findsOneWidget,
    );
    expect(
      find.text('Starts after “Draft” and “Review” close, then 1h 30m later'),
      findsOneWidget,
    );
  });

  testWidgets('ready, it says whether a hold holds it back', (tester) async {
    await pump(tester, [
      _goal('Draft'),
      _waiting('Ship', {
        'after': [
          {'at': '2020-01-01'},
        ],
        'hold_while': [
          {'active_at_least': 1},
        ],
      }),
      _waiting('Launch', {
        'after': [
          {'at': '2020-01-01'},
        ],
        'hold_while': [
          {'active_at_least': 5},
        ],
      }),
    ]);
    expect(
      find.text('Ready, held while 1 other goal is active'),
      findsOneWidget,
    );
    expect(find.text('Ready to start'), findsOneWidget);
  });
}
