import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:time_tracker_client/models/goal.dart';
import 'package:time_tracker_client/screens/goals_screen.dart';
import 'package:time_tracker_client/services/goals_repository.dart';
import 'package:time_tracker_client/services/mcp_client.dart';
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

  /// The status filter's chip for [status].
  Finder chip(String status) => find.widgetWithText(FilterChip, status);

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

      expect(shownNames(tester), [
        'Cooking',
        'Tofu tikka',
        'Hosting',
        'Idea',
        'Old habit',
      ]);
      expect(find.text('Priority 1 · Weekly'), findsOneWidget);
      expect(find.text('Fixed time'), findsOneWidget);
      expect(find.text('Proposed'), findsWidgets);
      expect(find.text('3 of 200 labels in use'), findsOneWidget);
      // The sub-goal is indented under its parent.
      final indent = tester
          .widgetList<ListTile>(find.byType(ListTile))
          .map((t) => (t.contentPadding as EdgeInsetsDirectional).start)
          .toList();
      expect(indent[1], greaterThan(indent[0]));
    },
  );

  testWidgets('the filter picks which statuses are shown', (tester) async {
    await tester.pumpWidget(app(tree()));
    await tester.pumpAndSettle();
    for (final status in ['Proposed', 'Active', 'Inactive']) {
      expect(tester.widget<FilterChip>(chip(status)).selected, isTrue);
    }
    expect(tester.widget<FilterChip>(chip('Deleted')).selected, isFalse);

    await tester.tap(chip('Inactive'));
    await tester.tap(chip('Completed'));
    await tester.tap(chip('Deleted'));
    await tester.pumpAndSettle();
    expect(shownNames(tester), contains('Done thing'));
    expect(shownNames(tester), contains('Oops'));
    expect(shownNames(tester), isNot(contains('Old habit')));

    for (final status in ['Proposed', 'Active', 'Completed', 'Deleted']) {
      await tester.tap(chip(status));
    }
    await tester.pumpAndSettle();
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
    expect(shownNames(tester), [
      'Cooking',
      'Tofu tikka',
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
