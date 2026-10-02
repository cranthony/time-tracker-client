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
    const Goal(id: 'old', name: 'Old habit', active: false),
  ]);

  List<String?> shownNames(WidgetTester tester) => tester
      .widgetList<ListTile>(find.byType(ListTile))
      .map((t) => (t.title as Text).data)
      .toList();

  test('Goal.fromJson keeps every property the server sent', () {
    final goal = Goal.fromJson({
      'id': 'g1',
      'parent_id': 'g0',
      'name': 'Tofu tikka',
      'active': false,
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
    test('lists every goal, inactive ones too', () async {
      final client = _FakeClient();
      final goals = await McpGoalsRepository(client).goals();
      expect(client.calls.single.$1, 'get_goals');
      expect(client.calls.single.$2, {'include_inactive': true});
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

  testWidgets('lists active goals as a tree, with the label count', (
    tester,
  ) async {
    await tester.pumpWidget(app(tree()));
    await tester.pumpAndSettle();

    expect(shownNames(tester), ['Cooking', 'Tofu tikka', 'Hosting']);
    expect(find.text('Priority 1 · Weekly'), findsOneWidget);
    expect(find.text('Fixed time'), findsOneWidget);
    expect(find.text('3 of 200 labels'), findsOneWidget);
    // The sub-goal is indented under its parent.
    final indent = tester
        .widgetList<ListTile>(find.byType(ListTile))
        .map((t) => (t.contentPadding as EdgeInsetsDirectional).start)
        .toList();
    expect(indent[1], greaterThan(indent[0]));
  });

  testWidgets('the filter shows inactive goals', (tester) async {
    await tester.pumpWidget(app(tree()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Inactive'));
    await tester.pumpAndSettle();
    expect(shownNames(tester), ['Old habit']);
    expect(find.text('Inactive').last, findsOneWidget);

    await tester.tap(find.text('All'));
    await tester.pumpAndSettle();
    expect(shownNames(tester), hasLength(4));
  });

  testWidgets('deactivating asks first, then moves the goal to Inactive', (
    tester,
  ) async {
    final repo = tree();
    await tester.pumpWidget(app(repo));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('More for Hosting'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Deactivate'));
    await tester.pumpAndSettle();
    expect(find.text('Deactivate Hosting?'), findsOneWidget);
    await tester.tap(find.text('Keep active'));
    await tester.pumpAndSettle();
    expect(shownNames(tester), contains('Hosting'));

    await tester.tap(find.byTooltip('More for Hosting'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Deactivate'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Deactivate').last);
    await tester.pumpAndSettle();
    expect(shownNames(tester), isNot(contains('Hosting')));
    expect(find.text('Deactivated.'), findsOneWidget);
    expect(
      (await repo.goals()).goals.firstWhere((g) => g.id == 'host').active,
      isFalse,
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
