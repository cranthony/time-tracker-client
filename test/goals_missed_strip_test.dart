import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:time_tracker_client/models/goal.dart';
import 'package:time_tracker_client/widgets/goals_due_strip.dart';

/// A goal, with the misses in its [history] -- each `(at, deadline)` --
/// before its latest status.
Goal _goal(
  String id,
  String title,
  String? deadline, {
  String status = 'active',
  List<(String, String?)> missed = const [],
}) => Goal.fromJson({
  'id': id,
  'title': title,
  'status': status,
  'deadline': ?deadline,
  'history': [
    {'status': 'active', 'at': '2026-10-01T09:00:00', 'deadline': '2026-10-18'},
    for (final (at, was) in missed)
      {'status': 'missed', 'at': at, 'deadline': ?was},
    {'status': status, 'at': '2026-10-19T09:00:00', 'deadline': ?deadline},
  ],
});

void main() {
  final day = DateTime(2026, 10, 18);

  test('missedOn: the goals with a miss whose deadline fell on the day, '
      'whatever became of them since', () {
    final goals = [
      _goal(
        'retried',
        'Retried',
        '2026-10-25',
        missed: [('2026-10-19T09:00:00', '2026-10-18')],
      ),
      _goal(
        'timed',
        'Timed',
        '2026-10-25T09:00',
        status: 'inactive',
        missed: [('2026-10-19T09:00:00', '2026-10-18T09:00')],
      ),
      _goal(
        'stayed',
        'Stayed missed',
        '2026-10-18',
        status: 'missed',
        missed: [('2026-10-19T09:00:00', '2026-10-18')],
      ),
      _goal(
        'done since',
        'Done since',
        '2026-10-20',
        status: 'done',
        missed: [('2026-10-19T09:00:00', '2026-10-18')],
      ),
      _goal(
        'twice',
        'Twice',
        '2026-11-01',
        missed: [
          ('2026-10-10T09:00:00', '2026-10-09'),
          ('2026-10-19T09:00:00', ' 2026-10-18 '),
        ],
      ),
      _goal(
        'other day',
        'Other day',
        '2026-10-25',
        missed: [('2026-10-20T09:00:00', '2026-10-19')],
      ),
      _goal(
        'unknown',
        'Deadline unknown',
        '2026-10-25',
        missed: [('2026-10-19T09:00:00', null)],
      ),
      _goal('due', 'Just due', '2026-10-18'),
    ];
    // Open ones first, then done, then missed; within a status, by title.
    expect(missedOn(goals, day).map((g) => g.id), [
      'retried',
      'twice',
      'timed',
      'done since',
      'stayed',
    ]);
    expect(missedOn(goals, DateTime(2026, 10, 19)).map((g) => g.id), [
      'other day',
    ]);
    expect(missedOn(goals, DateTime(2026, 10, 9)).map((g) => g.id), ['twice']);
    expect(missedOn(goals, DateTime(2026, 10, 17)), isEmpty);
    // The status given by a missed entry's being the last one: still
    // missed from that day.
    expect(
      missedOn([
        Goal.fromJson({
          'id': 'closed',
          'title': 'Closed',
          'status': 'missed',
          'deadline': '2026-10-18',
          'history': [
            {
              'status': 'missed',
              'at': '2026-10-19T09:00:00',
              'deadline': '2026-10-18',
            },
          ],
        }),
      ], day).map((g) => g.id),
      ['closed'],
    );
  });

  group('ghost pills', () {
    final retried = _goal(
      'retried',
      'Retried',
      '2026-10-25',
      missed: [('2026-10-19T09:00:00', '2026-10-18')],
    );
    final timed = _goal(
      'timed',
      'Timed',
      '2026-10-25T09:00',
      status: 'inactive',
      missed: [('2026-10-19T09:00:00', '2026-10-18T09:00')],
    );
    final stayed = _goal(
      'stayed',
      'Stayed',
      '2026-10-18',
      status: 'missed',
      missed: [('2026-10-19T09:00:00', '2026-10-18')],
    );
    final doneSince = _goal(
      'done',
      'Done since',
      '2026-10-20',
      status: 'done',
      missed: [('2026-10-19T09:00:00', '2026-10-18')],
    );
    final due = _goal('due', 'Due today', '2026-10-18');

    Future<void> show(
      WidgetTester tester, {
      required List<Goal> goals,
      required bool collapsed,
      ValueChanged<Goal>? onTap,
    }) => tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: GoalsDueStrip(
            goals: goalsDueOn(goals, day),
            missed: missedOn(goals, day),
            overdue: overdueGoalsOn(goals, day),
            day: day,
            today: day,
            spent: const {'retried': Duration(hours: 1)},
            collapsed: collapsed,
            onCollapsed: (_) {},
            onTap: onTap,
          ),
        ),
      ),
    );

    testWidgets("a greyed, struck-through pill after the day's for each "
        'goal missed from it, saying so and by when it is tried again; '
        'tapping one opens it', (tester) async {
      Goal? tapped;
      await show(
        tester,
        goals: [stayed, retried, timed, doneSince, due],
        collapsed: false,
        onTap: (g) => tapped = g,
      );
      expect(
        find.textContaining('Retried  ·  missed  ·  tried again by Oct 25'),
        findsOneWidget,
      );
      expect(
        find.textContaining(
          'Timed  ·  missed  ·  tried again by Oct 25, 9:00 AM',
        ),
        findsOneWidget,
      );
      // One still missed, due that day, is among the day's own instead.
      expect(find.textContaining('Stayed'), findsOneWidget);
      expect(find.textContaining('Stayed  ·'), findsNothing);
      expect(find.textContaining('Done since  ·  missed'), findsOneWidget);
      expect(find.textContaining('tried again'), findsNWidgets(2));
      // Not what's left of its time, nor its day's status.
      expect(find.textContaining('left'), findsNothing);
      expect(find.textContaining('done'), findsNothing);
      // Marked and greyed as a closed pill is: an x, struck through.
      expect(find.byIcon(Icons.close), findsNWidgets(4));
      expect(find.byIcon(Icons.check), findsNothing);
      final colors = Theme.of(tester.element(find.byType(GoalsDueStrip)))
          .colorScheme;
      final ghost = tester.widget<Text>(find.textContaining('Retried  ·'));
      expect(ghost.style?.color, colors.onSurfaceVariant);
      final spans = <TextSpan>[];
      ghost.textSpan!.visitChildren((s) {
        if (s is TextSpan) spans.add(s);
        return true;
      });
      expect(
        spans.firstWhere((s) => s.text == 'Retried').style?.decoration,
        TextDecoration.lineThrough,
      );
      expect(
        tester.widget<Text>(find.textContaining('Due today')).style?.color,
        colors.onSecondaryContainer,
      );
      // After the day's own, before the overdue group (none here).
      expect(find.text('Overdue'), findsNothing);
      final dueLeft = tester.getTopLeft(find.textContaining('Due today'));
      final ghostLeft = tester.getTopLeft(find.textContaining('Retried  ·'));
      expect(
        ghostLeft.dy > dueLeft.dy ||
            (ghostLeft.dy == dueLeft.dy && ghostLeft.dx > dueLeft.dx),
        isTrue,
      );
      await tester.tap(find.textContaining('Retried  ·'));
      expect(tapped?.id, 'retried');

      // Collapsed: counted and named.
      await show(
        tester,
        goals: [stayed, retried, timed, doneSince, due],
        collapsed: true,
      );
      expect(
        find.textContaining(
          '2 goals due (1 open), 3 missed · '
          'Due today, Stayed, Retried, Timed, Done since',
        ),
        findsOneWidget,
      );
      await show(tester, goals: [retried], collapsed: true);
      expect(find.textContaining('1 goal missed · Retried'), findsOneWidget);
    });

    testWidgets('shown on a past day too, and with nothing due; a goal '
        'missed and tried again by the same day is shown once, as due', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: GoalsDueStrip(
              goals: const [],
              missed: [retried],
              overdue: [retried],
              day: day,
              today: DateTime(2026, 10, 26),
              collapsed: false,
              onCollapsed: (_) {},
            ),
          ),
        ),
      );
      expect(find.textContaining('Retried  ·  missed'), findsOneWidget);
      expect(find.text('Overdue'), findsNothing);

      final sameDay = _goal(
        'same',
        'Same day',
        '2026-10-18T22:00',
        missed: [('2026-10-18T09:00:00', '2026-10-18T09:00')],
      );
      await show(tester, goals: [sameDay], collapsed: false);
      expect(find.textContaining('Same day'), findsOneWidget);
      expect(find.textContaining('missed'), findsNothing);
      expect(find.textContaining('10:00 PM'), findsOneWidget);
    });
  });

  group("an overdue pill's menu", () {
    final late = _goal('late', 'Late report', '2026-10-17');
    final due = _goal('due', 'Due today', '2026-10-18');

    Future<void> show(
      WidgetTester tester, {
      void Function(Goal, OverdueGoalAction)? onAction,
      ValueChanged<Goal>? onTap,
    }) => tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: GoalsDueStrip(
            goals: [due],
            overdue: [late],
            day: day,
            today: day,
            collapsed: false,
            onCollapsed: (_) {},
            onTap: onTap,
            onOverdueAction: onAction,
          ),
        ),
      ),
    );

    const labels = ['Mark done', 'Mark missed', 'Missed, try again…'];

    testWidgets('a long-press offers done, missed, and missed-try-again; '
        'a tap still opens the goal', (tester) async {
      final picked = <(String, OverdueGoalAction)>[];
      Goal? tapped;
      await show(
        tester,
        onAction: (g, a) => picked.add((g.id, a)),
        onTap: (g) => tapped = g,
      );
      await tester.longPress(find.textContaining('Late report'));
      await tester.pumpAndSettle();
      for (final label in labels) {
        expect(find.text(label), findsOneWidget);
      }
      await tester.tap(find.text('Mark done'));
      await tester.pumpAndSettle();
      expect(picked, [('late', OverdueGoalAction.done)]);
      expect(find.text('Mark done'), findsNothing);
      expect(tapped, isNull);

      await tester.longPress(find.textContaining('Late report'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Mark missed'));
      await tester.pumpAndSettle();
      expect(picked.last, ('late', OverdueGoalAction.missed));

      // Dismissed, nothing's done.
      await tester.longPress(find.textContaining('Late report'));
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(5, 5));
      await tester.pumpAndSettle();
      expect(picked, hasLength(2));
      expect(find.text('Mark done'), findsNothing);

      await tester.tap(find.textContaining('Late report'));
      await tester.pumpAndSettle();
      expect(tapped?.id, 'late');
      expect(find.text('Mark done'), findsNothing);
    });

    testWidgets('a right-click offers them too', (tester) async {
      final picked = <(String, OverdueGoalAction)>[];
      await show(tester, onAction: (g, a) => picked.add((g.id, a)));
      await tester.tap(
        find.textContaining('Late report'),
        buttons: kSecondaryButton,
      );
      await tester.pumpAndSettle();
      for (final label in labels) {
        expect(find.text(label), findsOneWidget);
      }
      await tester.tap(find.text('Missed, try again…'));
      await tester.pumpAndSettle();
      expect(picked, [('late', OverdueGoalAction.retry)]);
    });

    testWidgets("the day's own pills have no menu, nor does an overdue one "
        'with no actions given', (tester) async {
      await show(tester, onAction: (_, _) {});
      await tester.longPress(find.textContaining('Due today'));
      await tester.pumpAndSettle();
      expect(find.text('Mark done'), findsNothing);
      await tester.tap(
        find.textContaining('Due today'),
        buttons: kSecondaryButton,
      );
      await tester.pumpAndSettle();
      expect(find.text('Mark done'), findsNothing);

      await show(tester);
      await tester.longPress(find.textContaining('Late report'));
      await tester.pumpAndSettle();
      expect(find.text('Mark done'), findsNothing);
      await tester.tap(
        find.textContaining('Late report'),
        buttons: kSecondaryButton,
      );
      await tester.pumpAndSettle();
      expect(find.text('Mark done'), findsNothing);
    });
  });
}
