import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:time_tracker_client/models/assessment.dart';
import 'package:time_tracker_client/models/goal.dart';
import 'package:time_tracker_client/screens/goal_history_screen.dart';
import 'package:time_tracker_client/screens/goals_screen.dart';
import 'package:time_tracker_client/services/goals_repository.dart';
import 'package:time_tracker_client/services/mcp_client.dart';
import 'package:time_tracker_client/widgets/health.dart';
import 'package:time_tracker_client/widgets/properties_dialog.dart';

void main() {
  Widget app(GoalsRepository repo) => MaterialApp(
    home: GoalsScreen(repository: repo, serverLabel: 'offline demo'),
  );

  InMemoryGoalsRepository tree() => InMemoryGoalsRepository([
    const Goal(id: 'cook', name: 'Cooking', priority: 1, cadence: 'weekly'),
    const Goal(id: 'tofu', name: 'Tofu tikka', parentId: 'cook'),
    const Goal(id: 'host', name: 'Hosting', fixedTime: true),
    const Goal(id: 'idea', name: 'Idea', status: 'proposed'),
    const Goal(id: 'old', name: 'Old habit', status: 'inactive'),
    const Goal(id: 'done', name: 'Done thing', status: 'completed'),
    const Goal(id: 'shelf', name: 'Shelved', status: 'archived'),
    const Goal(id: 'oops', name: 'Oops', status: 'deleted'),
  ]);

  /// The status filter's check box for [status], in its drop-down.
  Finder option(String status) =>
      find.widgetWithText(CheckboxMenuButton, status);

  bool ticked(WidgetTester tester, String status) =>
      tester.widget<CheckboxMenuButton>(option(status)).value == true;

  List<String?> shownNames(WidgetTester tester) => tester
      .widgetList<ListTile>(find.byType(ListTile))
      .map((t) => (t.title as Text).data)
      .toList();

  test('Goal.fromJson reads a server from before statuses', () {
    expect(Goal.fromJson({'id': 'g', 'active': false}).status, 'inactive');
    expect(Goal.fromJson({'id': 'g', 'active': true}).status, 'active');
    expect(Goal.fromJson({'id': 'g', 'status': 'archived'}).active, isFalse);
  });

  test('Goal.fromJson keeps every property the server sent', () {
    final goal = Goal.fromJson({
      'id': 'g1',
      'parent_id': 'g0',
      'name': 'Tofu tikka',
      'status': 'completed',
      'background_color': '#7bd148',
      'priority': 2,
      'fixed_time': true,
      'cadence': 'weekly',
      'path': 'Cooking › Tofu tikka',
      'new_thing': 'x',
    });
    expect(goal.parentId, 'g0');
    expect(goal.active, isFalse);
    expect(goal.cadence, 'weekly');
    expect(goal.depth, 1);
    expect(goal.properties['new_thing'], 'x');
  });

  group('McpGoalsRepository', () {
    test('lists goals of every status', () async {
      final client = _FakeClient();
      final goals = await McpGoalsRepository(client).goals();
      expect(client.calls.single.$1, 'get_goals');
      expect(client.calls.single.$2, {
        'statuses': [
          'proposed',
          'active',
          'inactive',
          'completed',
          'archived',
          'deleted',
        ],
      });
      expect(goals.goals.single.name, 'Cooking');
      expect(goals.labelSlotsUsed, 12);
    });

    test('updateGoal names cleared fields, then lists again', () async {
      final client = _FakeClient();
      await McpGoalsRepository(client).updateGoal(const Goal(id: 'g1'), {
        'cadence': null,
        'name': 'Vegetarian cooking',
      });
      expect(client.calls.first.$1, 'update_goal');
      expect(client.calls.first.$2, {
        'goal': {'id': 'g1', 'name': 'Vegetarian cooking'},
        'clear_fields': ['cadence'],
      });
      expect(client.calls.last.$1, 'get_goals');
    });

    test('createGoal leaves out what was never set', () async {
      final client = _FakeClient();
      await McpGoalsRepository(client)
          .createGoal({'name': 'Cooking', 'parent_id': null});
      expect(client.calls.first.$1, 'create_goal');
      expect(client.calls.first.$2, {
        'goal': {'name': 'Cooking'},
      });
    });
  });

  testWidgets(
    'lists proposed, active and inactive goals as a tree, with the label count',
    (tester) async {
      await tester.pumpWidget(app(tree()));
      await tester.pumpAndSettle();

      // Sub-goals start collapsed: their parent says how many it has.
      expect(shownNames(tester), ['Cooking', 'Hosting', 'Idea', 'Old habit']);
      expect(find.text('Priority 1 · Weekly · 1 sub-goal'), findsOneWidget);
      expect(find.text('Fixed time'), findsOneWidget);
      expect(find.text('Proposed'), findsWidgets);
      expect(find.text('3 of 200 labels in use'), findsOneWidget);
      // Only a goal with sub-goals can be expanded.
      expect(find.byTooltip('Expand Hosting'), findsNothing);

      await tester.tap(find.byTooltip('Expand Cooking'));
      await tester.pumpAndSettle();
      expect(shownNames(tester), [
        'Cooking',
        'Tofu tikka',
        'Hosting',
        'Idea',
        'Old habit',
      ]);
      expect(find.text('Priority 1 · Weekly'), findsOneWidget);
      // The sub-goal is indented under its parent.
      final indent = tester
          .widgetList<ListTile>(find.byType(ListTile))
          .map((t) => (t.contentPadding as EdgeInsetsDirectional).start)
          .toList();
      expect(indent[1], greaterThan(indent[0]));

      await tester.tap(find.byTooltip('Collapse Cooking'));
      await tester.pumpAndSettle();
      expect(shownNames(tester), ['Cooking', 'Hosting', 'Idea', 'Old habit']);
    },
  );

  testWidgets('the filter at the top right picks which statuses are shown', (
    tester,
  ) async {
    await tester.pumpWidget(app(tree()));
    await tester.pumpAndSettle();
    Badge badge() => tester.widget<Badge>(
      find.descendant(
        of: find.byTooltip('Show goals that are…'),
        matching: find.byType(Badge),
      ),
    );
    expect(badge().isLabelVisible, isFalse);

    await tester.tap(find.byTooltip('Show goals that are…'));
    await tester.pumpAndSettle();
    for (final status in ['Proposed', 'Active', 'Inactive']) {
      expect(ticked(tester, status), isTrue);
    }
    expect(ticked(tester, 'Deleted'), isFalse);

    // It stays open while several are ticked.
    await tester.tap(option('Inactive'));
    await tester.pumpAndSettle();
    await tester.tap(option('Completed'));
    await tester.pumpAndSettle();
    await tester.tap(option('Deleted'));
    await tester.pumpAndSettle();
    expect(ticked(tester, 'Inactive'), isFalse);
    expect(ticked(tester, 'Deleted'), isTrue);
    expect(shownNames(tester), contains('Done thing'));
    expect(shownNames(tester), contains('Oops'));
    expect(shownNames(tester), isNot(contains('Old habit')));
    expect(badge().isLabelVisible, isTrue);

    for (final status in ['Proposed', 'Active', 'Completed', 'Deleted']) {
      await tester.tap(option(status));
      await tester.pumpAndSettle();
    }
    expect(find.text('No goals with these statuses.'), findsOneWidget);
  });

  testWidgets('moving an active goal to another status asks first', (
    tester,
  ) async {
    final repo = tree();
    await tester.pumpWidget(app(repo));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('More for Hosting'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Mark completed'));
    await tester.pumpAndSettle();
    expect(find.text('Move Hosting to completed?'), findsOneWidget);
    await tester.tap(find.text('Keep it'));
    await tester.pumpAndSettle();
    expect(
      (await repo.goals()).goals.firstWhere((g) => g.id == 'host').status,
      'active',
    );

    await tester.tap(find.byTooltip('More for Hosting'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Mark completed'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Completed'));
    await tester.pumpAndSettle();
    expect(find.text('Now completed.'), findsOneWidget);
    // Completed goals aren't shown until asked for.
    expect(shownNames(tester), isNot(contains('Hosting')));
    expect(
      (await repo.goals()).goals.firstWhere((g) => g.id == 'host').status,
      'completed',
    );
  });

  testWidgets('a proposed goal is made active without a check', (tester) async {
    final repo = tree();
    await tester.pumpWidget(app(repo));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('More for Idea'));
    await tester.pumpAndSettle();
    // Its own status isn't offered.
    expect(find.text('Mark proposed'), findsNothing);
    await tester.tap(find.text('Make active'));
    await tester.pumpAndSettle();

    expect(find.text('Now active.'), findsOneWidget);
    expect(
      (await repo.goals()).goals.firstWhere((g) => g.id == 'idea').status,
      'active',
    );
  });

  testWidgets('deleting asks first, then hides the goal', (tester) async {
    final repo = tree();
    await tester.pumpWidget(app(repo));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('More for Old habit'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(find.text('Delete Old habit?'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, 'Delete'));
    await tester.pumpAndSettle();

    expect(shownNames(tester), isNot(contains('Old habit')));
    expect(
      (await repo.goals()).goals.firstWhere((g) => g.id == 'old').status,
      'deleted',
    );
  });

  testWidgets('adds a sub-goal under the goal whose menu it came from', (
    tester,
  ) async {
    final repo = tree();
    await tester.pumpWidget(app(repo));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('More for Hosting'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add sub-goal'));
    await tester.pumpAndSettle();
    expect(find.text('New sub-goal'), findsOneWidget);
    // Its parent, by name.
    expect(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text('Hosting'),
      ),
      findsOneWidget,
    );

    // Saving with no name is refused.
    await tester.tap(find.text('(none)').first);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Weekly dinners');
    await tester.tap(find.byTooltip('Keep edit'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save 1 change'));
    await tester.pumpAndSettle();

    expect(find.text('Added.'), findsOneWidget);
    final added = (await repo.goals()).goals.firstWhere(
      (g) => g.name == 'Weekly dinners',
    );
    expect(added.parentId, 'host');
    // Its parent is expanded, so it's in sight; Cooking stays collapsed.
    expect(shownNames(tester), [
      'Cooking',
      'Hosting',
      'Weekly dinners',
      'Idea',
      'Old habit',
    ]);
  });

  testWidgets('a new goal needs a name', (tester) async {
    await tester.pumpWidget(app(tree()));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Add goal'));
    await tester.pumpAndSettle();
    expect(find.text('New goal'), findsOneWidget);
    // Change something other than the name, then try to save.
    await tester.tap(find.text('(none)').at(2)); // priority
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '2');
    await tester.tap(find.byTooltip('Keep edit'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save 1 change'));
    await tester.pumpAndSettle();
    expect(find.textContaining('A goal needs a name.'), findsOneWidget);
  });

  testWidgets('a goal\'s cadence is picked from the cadences', (tester) async {
    final repo = tree();
    await tester.pumpWidget(app(repo));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Hosting'));
    await tester.pumpAndSettle();
    final dialog = find.byType(AlertDialog);
    final cadence = find.descendant(of: dialog, matching: find.text('cadence'));
    final row = find.ancestor(of: cadence, matching: find.byType(PropertyRow));
    await tester.ensureVisible(row);
    await tester.pumpAndSettle();
    await tester.tap(find.descendant(of: row, matching: find.text('(none)')));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(DropdownButton<String?>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Every 2 months').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Keep edit'));
    await tester.pumpAndSettle();
    expect(
      find.descendant(of: dialog, matching: find.text('Every 2 months')),
      findsOneWidget,
    );
    await tester.tap(find.text('Save 1 change'));
    await tester.pumpAndSettle();

    expect(
      (await repo.goals()).goals.firstWhere((g) => g.id == 'host').cadence,
      'every_2_months',
    );
  });

  /// Opens [goal]'s dialog, then its measure for editing.
  Future<Finder> openMeasure(WidgetTester tester, String goal) async {
    await tester.tap(find.text(goal));
    await tester.pumpAndSettle();
    final dialog = find.byType(AlertDialog);
    final label = find.descendant(of: dialog, matching: find.text('measure'));
    final row = find.ancestor(of: label, matching: find.byType(PropertyRow));
    await tester.ensureVisible(row);
    await tester.pumpAndSettle();
    await tester.tap(find.descendant(of: row, matching: find.text('(none)')));
    await tester.pumpAndSettle();
    return dialog;
  }

  /// Picks [kind] in the open measure's drop-down.
  Future<void> pickKind(WidgetTester tester, String kind) async {
    await tester.tap(find.byType(DropdownButton<String?>));
    await tester.pumpAndSettle();
    await tester.tap(find.text(kind).last);
    await tester.pumpAndSettle();
  }

  testWidgets("a goal's measure is edited as its kind's fields", (
    tester,
  ) async {
    final repo = tree();
    await tester.pumpWidget(app(repo));
    await tester.pumpAndSettle();

    final dialog = await openMeasure(tester, 'Cooking');
    await pickKind(tester, 'Time spent');
    await tester.enterText(find.widgetWithText(TextField, 'Target'), '10h');
    expect(find.text('per week'), findsOneWidget); // Cooking is weekly.
    await tester.tap(find.byTooltip('Keep edit'));
    await tester.pumpAndSettle();
    expect(
      find.descendant(of: dialog, matching: find.text('10h per week')),
      findsOneWidget,
    );
    await tester.tap(find.text('Save 1 change'));
    await tester.pumpAndSettle();

    final cooking = (await repo.goals()).goals.firstWhere(
      (g) => g.id == 'cook',
    );
    expect(cooking.measure, {'kind': 'duration', 'target_min': 600});
    // The Goals page says what it's measured by, in place of its cadence.
    expect(find.text('Priority 1 · 10h per week · 1 sub-goal'), findsOneWidget);
  });

  testWidgets("a measure missing what its kind needs isn't kept", (
    tester,
  ) async {
    await tester.pumpWidget(app(tree()));
    await tester.pumpAndSettle();

    await openMeasure(tester, 'Hosting');
    await pickKind(tester, 'Number of events');
    await tester.tap(find.byTooltip('Keep edit'));
    await tester.pumpAndSettle();

    expect(find.text('Enter a target above 0.'), findsOneWidget);
    expect(find.text('Save 1 change'), findsNothing);
  });

  testWidgets(
    'an active goal shows its own color, or outlines the one it inherits',
    (tester) async {
      await tester.pumpWidget(
        app(
          InMemoryGoalsRepository([
            Goal.fromJson({
              'id': 'own',
              'name': 'Own',
              'background_color': '#123456',
              'effective_color': '#123456',
            }),
            Goal.fromJson({
              'id': 'kid',
              'name': 'Kid',
              'parent_id': 'own',
              'effective_color': '#123456',
            }),
          ]),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Expand Own'));
      await tester.pumpAndSettle();

      List<Icon> iconsOf(String name) => tester
          .widgetList<Icon>(
            find.descendant(
              of: find.ancestor(
                of: find.text(name),
                matching: find.byType(ListTile),
              ),
              matching: find.descendant(
                of: find.byType(GoalFlag),
                matching: find.byType(Icon),
              ),
            ),
          )
          .toList();

      final own = iconsOf('Own');
      expect(own.map((i) => (i.icon, i.color)), [
        (Icons.flag, const Color(0xFF123456)),
      ]);
      expect(iconsOf('Kid').map((i) => (i.icon, i.color)), [
        (Icons.outlined_flag, const Color(0xFF123456)),
      ]);
    },
  );

  test('Goal.fromJson reads its health, trend and stale periods', () {
    final goal = Goal.fromJson({
      'id': 'g',
      'health': 85,
      'health_period': 'week-2026-09-20',
      'health_trend': '-,40,85',
      'stale_periods': 2,
    });
    expect(goal.health, 85);
    expect(goal.healthTrend, [null, 40, 85]);
    expect(goal.stalePeriods, 2);
    expect(Goal.fromJson({'id': 'g'}).healthTrend, isEmpty);
  });

  test("McpGoalsRepository reads a goal's history", () async {
    final client = _HistoryClient();
    final history = await McpGoalsRepository(client)
        .history(const Goal(id: 'g1'));
    expect(client.arguments, {
      'goal_ids': ['g1'],
    });
    expect(history.map((a) => (a.period, a.rating, a.confirmed)), [
      ('week-2026-09-13', 60, true),
      ('week-2026-09-20', null, false),
    ]);
  });

  testWidgets("an assessed goal shows its health, trend and what's overdue", (
    tester,
  ) async {
    await tester.pumpWidget(
      app(
        InMemoryGoalsRepository([
          const Goal(
            id: 'cook',
            name: 'Cooking',
            cadence: 'weekly',
            health: 85,
            healthTrend: [null, 40, 85],
            stalePeriods: 2,
          ),
          const Goal(id: 'idea', name: 'Idea', status: 'proposed'),
        ]),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(HealthDot), findsOneWidget); // not for the proposed one
    expect(find.text('85'), findsOneWidget);
    expect(find.byType(TrendSparkline), findsOneWidget);
    expect(find.text('Weekly · 2 weeks unassessed'), findsOneWidget);
  });

  testWidgets("a goal's history lists its assessments under a chart", (
    tester,
  ) async {
    await tester.pumpWidget(
      app(
        InMemoryGoalsRepository(
          [
            const Goal(
              id: 'cook',
              name: 'Cooking',
              cadence: 'weekly',
              health: 60,
            ),
          ],
          {
            'cook': [
              const Assessment(
                goalId: 'cook',
                period: 'week-2026-09-13',
                rating: 60,
                explanation: '3h of 5h target → 60',
              ),
              const Assessment(
                goalId: 'cook',
                period: 'week-2026-09-20',
                rating: 90,
                status: 'proposed',
                method: 'metric',
              ),
            ],
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('More for Cooking'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('History'));
    await tester.pumpAndSettle();

    expect(find.byType(HealthHistoryChart), findsOneWidget);
    final periods = tester
        .widgetList<ListTile>(find.byType(ListTile))
        .map((t) => (t.title as Text).data)
        .toList();
    expect(periods, ['week-2026-09-20 · proposed · metric', 'week-2026-09-13']);
    expect(find.text('3h of 5h target → 60'), findsOneWidget);
  });

  testWidgets('a goal with no assessments says how it gets some', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: GoalHistoryScreen(
          goal: const Goal(id: 'g', name: 'G', cadence: 'daily'),
          repository: InMemoryGoalsRepository(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.text(
        'No assessments yet.\nRatings are confirmed in a daily reflection.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('says when there are no goals yet', (tester) async {
    await tester.pumpWidget(app(InMemoryGoalsRepository()));
    await tester.pumpAndSettle();
    expect(find.text('No goals yet.\nTap + to add one.'), findsOneWidget);
  });
}

/// Records each tool call, and answers every one with a single goal.
class _FakeClient extends McpClient {
  _FakeClient() : super(endpoint: Uri.parse('http://test'));

  final calls = <(String, Map<String, Object?>)>[];

  @override
  Future<Object?> callTool(
    String name, [
    Map<String, Object?> arguments = const {},
  ]) async {
    calls.add((name, arguments));
    return {
      'goals': [
        {'id': 'g1', 'name': 'Cooking', 'active': true, 'path': 'Cooking'},
      ],
      'label_slots_used': 12,
      'label_slots_total': 200,
    };
  }
}

/// Answers get_goal_history with two assessments.
class _HistoryClient extends McpClient {
  _HistoryClient() : super(endpoint: Uri.parse('http://test'));

  Map<String, Object?>? arguments;

  @override
  Future<Object?> callTool(
    String name, [
    Map<String, Object?> arguments = const {},
  ]) async {
    this.arguments = arguments;
    return [
      {
        'goal_id': 'g1',
        'cadence': 'weekly',
        'period': 'week-2026-09-13',
        'rating': 60,
        'method': 'subjective',
        'status': 'confirmed',
      },
      {
        'goal_id': 'g1',
        'cadence': 'weekly',
        'period': 'week-2026-09-20',
        'rating': 'skip',
        'method': 'subjective',
        'status': 'proposed',
      },
    ];
  }
}
