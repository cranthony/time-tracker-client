import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:time_tracker_client/models/assessment.dart';
import 'package:time_tracker_client/models/goal.dart';
import 'package:time_tracker_client/models/measure.dart';
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
    const Goal(id: 'cook', name: 'Cooking', priority: 1),
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

  /// Opens [name]'s details from its menu; tapping it shows its measure.
  Future<void> openDetails(WidgetTester tester, String name) async {
    await tester.tap(find.byTooltip('More for $name'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Details'));
    await tester.pumpAndSettle();
  }

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
      'path': 'Cooking › Tofu tikka',
      'new_thing': 'x',
    });
    expect(goal.parentId, 'g0');
    expect(goal.active, isFalse);
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

    test('updateGoal names cleared fields', () async {
      final client = _FakeClient();
      await McpGoalsRepository(client).updateGoal(const Goal(id: 'g1'), {
        'measure': null,
        'name': 'Vegetarian cooking',
      });
      expect(client.calls.first.$1, 'update_goal');
      expect(client.calls.first.$2, {
        'goal': {'id': 'g1', 'name': 'Vegetarian cooking'},
        'clear_fields': ['measure'],
      });
      // Listing them again is left until every change is saved.
      expect(client.calls, hasLength(1));
    });

    test('createGoal leaves out what was never set, and finds its id in '
        'the answer', () async {
      final client = _FakeClient();
      final id = await McpGoalsRepository(client)
          .createGoal({'name': 'Cooking', 'parent_id': null});
      expect(client.calls.single.$1, 'create_goal');
      expect(client.calls.single.$2, {
        'goal': {'name': 'Cooking'},
      });
      expect(id, 'g1');
      // Not one of the same name under another goal.
      expect(
        await McpGoalsRepository(client)
            .createGoal({'name': 'Cooking', 'parent_id': 'g0'}),
        isNull,
      );
    });
  });

  testWidgets(
    'lists proposed, active and inactive goals as a tree, with the label count',
    (tester) async {
      await tester.pumpWidget(app(tree()));
      await tester.pumpAndSettle();

      // Sub-goals start collapsed: their parent says how many it has.
      expect(shownNames(tester), ['Cooking', 'Hosting', 'Idea', 'Old habit']);
      expect(find.text('1 sub-goal'), findsOneWidget);
      // Priorities and fixed time are only under "Event properties".
      expect(find.textContaining('Priority'), findsNothing);
      expect(find.text('Fixed time'), findsNothing);
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
      expect(find.text('1 sub-goal'), findsNothing);
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

  /// Opens [name]'s details, and picks [status] for its status.
  Future<void> pickStatus(
    WidgetTester tester,
    String name,
    String status,
  ) async {
    await openDetails(tester, name);
    final dialog = find.byType(AlertDialog);
    final label = find.descendant(of: dialog, matching: find.text('status'));
    final row = find.ancestor(of: label, matching: find.byType(PropertyRow));
    await tester.tap(
      find.descendant(of: row, matching: find.byType(InkWell)).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byType(DropdownButton<String?>));
    await tester.pumpAndSettle();
    await tester.tap(find.text(status).last);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Keep edit'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save 1 change'));
    await tester.pumpAndSettle();
  }

  testWidgets("a goal's status is changed in its details, asking first to "
      'move an active one', (tester) async {
    final repo = tree();
    await tester.pumpWidget(app(repo));
    await tester.pumpAndSettle();

    await pickStatus(tester, 'Hosting', 'Completed');
    expect(find.text('Move Hosting to completed?'), findsOneWidget);
    await tester.tap(find.text('Keep it'));
    await tester.pumpAndSettle();
    // Still open, with the change kept, to save or revert.
    expect(find.text('Save 1 change'), findsOneWidget);
    expect(
      (await repo.goals()).goals.firstWhere((g) => g.id == 'host').status,
      'active',
    );

    await tester.tap(find.text('Save 1 change'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Completed'));
    await tester.pumpAndSettle();
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

    await pickStatus(tester, 'Idea', 'Active');

    expect(
      (await repo.goals()).goals.firstWhere((g) => g.id == 'idea').status,
      'active',
    );
  });

  testWidgets('deleting asks first, then hides the goal', (tester) async {
    final repo = tree();
    await tester.pumpWidget(app(repo));
    await tester.pumpAndSettle();

    await pickStatus(tester, 'Old habit', 'Deleted');
    expect(find.text('Delete Old habit?'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, 'Delete'));
    await tester.pumpAndSettle();

    expect(shownNames(tester), isNot(contains('Old habit')));
    expect(
      (await repo.goals()).goals.firstWhere((g) => g.id == 'old').status,
      'deleted',
    );
  });

  testWidgets("a goal's menu adds a sub-goal, or shows its history or "
      'details', (tester) async {
    await tester.pumpWidget(app(tree()));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('More for Hosting'));
    await tester.pumpAndSettle();
    final items = tester
        .widgetList<PopupMenuItem<String>>(find.byType(PopupMenuItem<String>))
        .map((i) => (i.child as Text).data)
        .toList();
    expect(items, ['Add sub-goal', 'Measure', 'History', 'Details']);

    await tester.tap(find.text('Details'));
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text('Hosting'),
      ),
      findsWidgets,
    );
  });

  testWidgets("tapping a goal's flag shows or hides its sub-goals", (
    tester,
  ) async {
    await tester.pumpWidget(app(tree()));
    await tester.pumpAndSettle();

    Finder flagOf(String name) => find.descendant(
      of: find.ancestor(of: find.text(name), matching: find.byType(ListTile)),
      matching: find.byType(GoalFlag),
    );
    await tester.tap(flagOf('Cooking'));
    await tester.pumpAndSettle();
    expect(shownNames(tester), contains('Tofu tikka'));
    await tester.tap(flagOf('Cooking'));
    await tester.pumpAndSettle();
    expect(shownNames(tester), isNot(contains('Tofu tikka')));
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

  /// Lets a second go by, a frame at a time: what pumpAndSettle does,
  /// for when a goal being saved keeps it from settling.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  /// In the dialog open, sets the goal's name to [name].
  Future<void> rename(WidgetTester tester, String name) async {
    final label = find.descendant(
      of: find.byType(AlertDialog),
      matching: find.text('name'),
    );
    final row = find.ancestor(of: label, matching: find.byType(PropertyRow));
    await tester.tap(
      find.descendant(of: row, matching: find.byType(InkWell)).first,
    );
    await settle(tester);
    await tester.enterText(find.byType(TextField), name);
    await tester.tap(find.byTooltip('Keep edit'));
    await settle(tester);
  }

  /// Adds a top-level goal named [name] from the "+" button.
  Future<void> addGoal(WidgetTester tester, String name) async {
    await tester.tap(find.byTooltip('Add goal'));
    await settle(tester);
    await tester.tap(find.text('(none)').first);
    await settle(tester);
    await tester.enterText(find.byType(TextField), name);
    await tester.tap(find.byTooltip('Keep edit'));
    await settle(tester);
    await tester.tap(find.text('Save 1 change'));
    await settle(tester);
  }

  testWidgets('saving closes the dialog at once, and saves in the '
      'background, in order', (tester) async {
    final repo = _GatedGoalsRepository(tree());
    await tester.pumpWidget(app(repo));
    await settle(tester);

    await addGoal(tester, 'Running');
    await settle(tester);
    // Closed, and shown already, saving.
    expect(find.byType(AlertDialog), findsNothing);
    expect(shownNames(tester), contains('Running'));
    expect(find.byTooltip('Saving…'), findsOneWidget);
    // Another can be added straight away.
    await addGoal(tester, 'Swimming');
    await settle(tester);
    expect(shownNames(tester), containsAllInOrder(['Running', 'Swimming']));
    expect(find.byTooltip('Saving…'), findsNWidgets(2));
    // Renaming a goal shows at once, too.
    await tester.tap(find.byTooltip('More for Hosting'));
    await settle(tester);
    await tester.tap(find.text('Details'));
    await settle(tester);
    await rename(tester, 'Parties');
    await tester.tap(find.text('Save 1 change'));
    await settle(tester);
    expect(find.byType(AlertDialog), findsNothing);
    expect(shownNames(tester), contains('Parties'));

    // Sent one at a time, in order.
    final fetched = repo.fetches;
    expect(repo.sent, ['create Running']);
    repo.answer();
    await tester.pump();
    expect(repo.sent, ['create Running', 'create Swimming']);
    // Running has its id, so it can be opened; Swimming is still saving.
    expect(find.byTooltip('Saving…'), findsOneWidget);
    expect(find.byTooltip('More for Running'), findsOneWidget);
    repo.answer();
    await tester.pump();
    expect(repo.sent, ['create Running', 'create Swimming', 'update host']);
    expect(find.byTooltip('Saving…'), findsNothing);
    // The goals are only fetched once every change is saved.
    expect(repo.fetches, fetched);
    repo.answer();
    await tester.pumpAndSettle();
    expect(repo.fetches, fetched + 1);
    expect(shownNames(tester), containsAll(['Running', 'Swimming', 'Parties']));
    expect(
      (await repo.goals()).goals.map((g) => g.name),
      containsAll(['Running', 'Swimming', 'Parties']),
    );
  });

  testWidgets('a new goal that fails to save stays, marked, to edit and '
      'save again', (tester) async {
    final repo = _GatedGoalsRepository(tree());
    await tester.pumpWidget(app(repo));
    await tester.pumpAndSettle();

    await addGoal(tester, 'Running');
    repo.fail(McpException('No room for it.'));
    await tester.pumpAndSettle();
    expect(find.text("Couldn't save Running. No room for it."), findsOneWidget);
    // Still there, with an error in place of its menu.
    expect(shownNames(tester), contains('Running'));
    expect(find.byTooltip('Not saved: No room for it.'), findsOneWidget);
    expect(find.byTooltip('More for Running'), findsNothing);

    // Tapping it opens what was entered, to change and save again.
    await tester.tap(find.text('Running'));
    await tester.pumpAndSettle();
    expect(find.text('Save 1 change'), findsOneWidget);
    await rename(tester, 'Jogging');
    await tester.tap(find.text('Save 1 change'));
    await settle(tester);
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.byTooltip('Saving…'), findsOneWidget);
    expect(repo.sent.last, 'create Jogging');

    repo.answer();
    await tester.pumpAndSettle();
    expect(shownNames(tester), contains('Jogging'));
    expect(shownNames(tester), isNot(contains('Running')));
    expect(find.byTooltip('Not saved: No room for it.'), findsNothing);
    expect(
      (await repo.goals()).goals.map((g) => g.name),
      containsAll(['Jogging']),
    );
  });

  testWidgets('a save that failed can be tried again as it was, or '
      'discarded', (tester) async {
    final repo = _GatedGoalsRepository(tree());
    await tester.pumpWidget(app(repo));
    await tester.pumpAndSettle();

    await addGoal(tester, 'Running');
    repo.fail(McpException('No room for it.'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Retry'));
    await settle(tester);
    expect(repo.sent, ['create Running', 'create Running']);
    expect(find.byTooltip('Saving…'), findsOneWidget);
    repo.fail(McpException('Still no room.'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Not saved: Still no room.'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Discard'));
    await tester.pumpAndSettle();
    expect(shownNames(tester), isNot(contains('Running')));
    expect(find.byTooltip('Not saved: Still no room.'), findsNothing);
  });

  testWidgets('a change that fails to save stays, to edit and save again', (
    tester,
  ) async {
    final repo = _GatedGoalsRepository(tree());
    await tester.pumpWidget(app(repo));
    await tester.pumpAndSettle();

    await openDetails(tester, 'Hosting');
    await rename(tester, 'Parties');
    await tester.tap(find.text('Save 1 change'));
    await settle(tester);
    repo.fail(McpException('Try later.'));
    await tester.pumpAndSettle();
    // Kept, though the goals were fetched again.
    expect(shownNames(tester), contains('Parties'));
    expect(find.byTooltip('Not saved: Try later.'), findsOneWidget);

    // Opens as the server has it, with the change to save again.
    await tester.tap(find.text('Parties'));
    await tester.pumpAndSettle();
    expect(find.text('Save 1 change'), findsOneWidget);
    await tester.tap(find.text('Save 1 change'));
    await settle(tester);
    expect(repo.sent, ['update host', 'update host']);
    repo.answer();
    await tester.pumpAndSettle();
    expect(find.byTooltip('Not saved: Try later.'), findsNothing);
    expect(
      (await repo.goals()).goals.firstWhere((g) => g.id == 'host').name,
      'Parties',
    );
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

  testWidgets('the time spent on each goal is shown, as of the last '
      'compaction, noted at the top', (tester) async {
    await tester.pumpWidget(
      app(
        InMemoryGoalsRepository(
          [
            const Goal(
              id: 'neighbor',
              name: 'Be a good neighbor',
              minutes24h: 90,
              minutes7d: 600,
            ),
            const Goal(id: 'idea', name: 'Idea', status: 'proposed'),
          ],
          const {},
          DateTime(2026, 10, 2, 21, 5),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Last compacted Oct 2, 2026, 9:05 PM'), findsOneWidget);
    expect(find.text('1h 30m in 24h · 10h in 7d'), findsOneWidget);
  });

  test('a time is said in hours and minutes, or as shares of each window', () {
    expect(describeTime(540, 0), '9h in 24h · 0m in 7d');
    expect(describeTime(0, 1680), '0m in 24h · 28h in 7d');
    // A goal's leaves out a window with no time, the Overall card's doesn't.
    expect(describeTime(540, 0, skipZero: true), '9h in 24h');
    expect(describeTime(0, 420, skipZero: true), '7h in 7d');
    expect(describeTime(0, 0, skipZero: true), isNull);
    expect(describeTime(0, 0), '0m in 24h · 0m in 7d');
    // Or just the shares, however small.
    expect(describeTime(540, 0, asPercent: true), '37.5% of 24h · 0% of 7d');
    expect(describeTime(60, 5, asPercent: true), '4.2% of 24h · <0.1% of 7d');
    expect(describeTime(0, 600, skipZero: true, asPercent: true), '6% of 7d');
  });

  group('what each goal shows under its name', () {
    InMemoryGoalsRepository goals() => InMemoryGoalsRepository(
      [
        const Goal(id: overallGoalId, name: 'Overall'),
        const Goal(
          id: 'app',
          name: 'Make an app',
          measure: {'kind': 'duration', 'target_min': 600, 'interval_days': 7},
          minutes24h: 540,
          minutes7d: 1680,
        ),
        const Goal(id: 'idea', name: 'Idea', minutes24h: 0, minutes7d: 600),
      ],
      const {},
      DateTime(2026, 10, 2, 21),
      const [
        StatusMinutes(statuses: {'active'}, minutes24h: 540, minutes7d: 2280),
      ],
    );

    Future<void> pick(WidgetTester tester, String label) async {
      await tester.tap(find.byTooltip('Show under each goal…'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.widgetWithText(RadioMenuButton<GoalSummary>, label),
      );
      await tester.pumpAndSettle();
    }

    setUp(
      () => SharedPreferencesAsyncPlatform.instance =
          InMemorySharedPreferencesAsync.empty(),
    );
    tearDown(
      () => SharedPreferencesAsyncPlatform.instance =
          InMemorySharedPreferencesAsync.empty(),
    );

    testWidgets('is its time spent to start with', (tester) async {
      await tester.pumpWidget(app(goals()));
      await tester.pumpAndSettle();

      // Its measure is only under "Measure".
      expect(find.text('9h in 24h · 28h in 7d'), findsOneWidget);
      expect(find.text('10h in 7d'), findsOneWidget);
      expect(find.textContaining('per 7 days'), findsNothing);
    });

    testWidgets('can be its measure, or its time as percentages', (
      tester,
    ) async {
      await tester.pumpWidget(app(goals()));
      await tester.pumpAndSettle();

      await pick(tester, 'Measure');
      // Its measure moves up, and isn't said twice; without one, nothing.
      expect(find.text('10h per 7 days'), findsOneWidget);
      // The Overall card's too: it's rated by the top-level goals'.
      expect(find.textContaining('in 24h'), findsNothing);
      expect(find.text("Average of the top-level goals'"), findsOneWidget);
      expect(
        find.descendant(
          of: find.widgetWithText(ListTile, 'Idea'),
          matching: find.textContaining('7d'),
        ),
        findsNothing,
      );

      await pick(tester, 'Time as a percentage');
      expect(find.text('37.5% of 24h · 16.7% of 7d'), findsOneWidget);
      expect(find.text('6% of 7d'), findsOneWidget);
      // The Overall card's too, without its measure.
      expect(
        find.text('37.5% of 24h · 22.6% of 7d on the goals shown'),
        findsOneWidget,
      );
      expect(find.text("Average of the top-level goals'"), findsNothing);
    });

    testWidgets('can be the priority and fixed time it gives its events', (
      tester,
    ) async {
      await tester.pumpWidget(app(tree()));
      await tester.pumpAndSettle();

      await pick(tester, 'Event properties');
      expect(find.text('Priority 1\n1 sub-goal'), findsOneWidget);
      expect(find.text('Fixed time'), findsOneWidget);
      // Neither its time nor its measure.
      expect(find.textContaining(' in 24h'), findsNothing);
      // A goal that gives neither shows nothing for them.
      expect(
        find.descendant(
          of: find.widgetWithText(ListTile, 'Idea'),
          matching: find.text('Proposed'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('is kept for next time', (tester) async {
      await tester.pumpWidget(app(goals()));
      await tester.pumpAndSettle();
      await pick(tester, 'Time as a percentage');

      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(app(goals()));
      await tester.pumpAndSettle();

      expect(find.text('6% of 7d'), findsOneWidget);
    });
  });

  group('the measure dialog', () {
    InMemoryGoalsRepository measured() => InMemoryGoalsRepository([
      const Goal(
        id: 'app',
        name: 'Make an app',
        measure: {'kind': 'duration', 'target_min': 600, 'interval_days': 7},
        health: 88,
        healthPeriod: '2026-09-30',
        healthTrend: [70, null, 88],
        staleDays: 2,
        minutes24h: 240,
        minutes7d: 1500,
      ),
      const Goal(id: 'cook', name: 'Cooking'),
      const Goal(id: 'old', name: 'Old habit', status: 'inactive'),
    ]);

    Finder inDialog(Finder finder) =>
        find.descendant(of: find.byType(AlertDialog).last, matching: finder);

    Measure? measureOf(GoalList goals, String id) =>
        goals.goals.firstWhere((g) => g.id == id).measure;

    testWidgets("opens on tapping a goal, with its settings and how it's "
        'doing', (tester) async {
      await tester.pumpWidget(app(measured()));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Make an app'));
      await tester.pumpAndSettle();
      expect(inDialog(find.text('Measure')), findsOneWidget);
      expect(inDialog(find.text('Time spent')), findsOneWidget);
      expect(inDialog(find.text('10h per 7 days')), findsOneWidget);
      expect(inDialog(find.text('Target')), findsOneWidget);
      expect(
        inDialog(find.text('This goal and its sub-goals')),
        findsOneWidget,
      );
      expect(
        inDialog(find.text('On track · last rated 2026-09-30')),
        findsOneWidget,
      );
      expect(inDialog(find.byType(TrendSparkline)), findsOneWidget);
      expect(inDialog(find.text('2 days unrated')), findsOneWidget);
      expect(
        inDialog(find.text('4h in 24h · 25h in 7d spent')),
        findsOneWidget,
      );
      expect(inDialog(find.text('Edit measure')), findsOneWidget);

      // "Details" swaps it for the goal's details.
      await tester.tap(inDialog(find.text('Details')));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(inDialog(find.text('parent_id')), findsOneWidget);
    });

    testWidgets("its goal's menu opens it too, and it opens the history", (
      tester,
    ) async {
      await tester.pumpWidget(app(measured()));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('More for Make an app'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Measure'));
      await tester.pumpAndSettle();
      expect(inDialog(find.text('10h per 7 days')), findsOneWidget);

      await tester.tap(inDialog(find.text('History')));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.byType(GoalHistoryScreen), findsOneWidget);
    });

    testWidgets("says how a goal without a measure is rated, and that an "
        "inactive one isn't", (tester) async {
      await tester.pumpWidget(app(measured()));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Old habit'));
      await tester.pumpAndSettle();
      expect(inDialog(find.text('No measure of its own')), findsOneWidget);
      expect(
        inDialog(
          find.text(
            "It's rated each day as the average of its sub-goals' ratings.",
          ),
        ),
        findsOneWidget,
      );
      expect(inDialog(find.text('Add a measure')), findsOneWidget);
      expect(
        inDialog(find.text('Only active goals are rated.')),
        findsOneWidget,
      );
    });

    testWidgets('edits the measure in its place, saying how it reads, then '
        'goes back to the goals', (tester) async {
      final repo = measured();
      await tester.pumpWidget(app(repo));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Make an app'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Edit measure'));
      await tester.pumpAndSettle();
      // In place of the measure dialog, not stacked over it.
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(inDialog(find.text('Reads as: 10h per 7 days')), findsOneWidget);
      // Nothing changed yet.
      final save = find.widgetWithText(FilledButton, 'Save');
      expect(tester.widget<FilledButton>(save).onPressed, isNull);

      await tester.enterText(find.widgetWithText(TextField, 'Target'), '12h');
      await tester.pumpAndSettle();
      expect(inDialog(find.text('Reads as: 12h per 7 days')), findsOneWidget);
      await tester.tap(save);
      await tester.pumpAndSettle();

      expect(measureOf(await repo.goals(), 'app'), {
        'kind': 'duration',
        'target_min': 720,
        'interval_days': 7,
      });
      // Back on the goals page.
      expect(find.byType(AlertDialog), findsNothing);
    });

    testWidgets("can't save a measure missing what it needs, and says why", (
      tester,
    ) async {
      await tester.pumpWidget(app(measured()));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Make an app'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Edit measure'));
      await tester.pumpAndSettle();
      await tester.enterText(find.widgetWithText(TextField, 'Target'), '');
      await tester.pumpAndSettle();

      expect(
        inDialog(find.text('Enter a target time, like 10h or 1h 30m.')),
        findsOneWidget,
      );
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, 'Save'))
            .onPressed,
        isNull,
      );
    });

    testWidgets('adds a measure to a goal without one', (tester) async {
      final repo = measured();
      await tester.pumpWidget(app(repo));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Cooking'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add a measure'));
      await tester.pumpAndSettle();
      expect(inDialog(find.text('Pick a kind of measure.')), findsOneWidget);
      // No measure to remove.
      expect(inDialog(find.text('Remove')), findsNothing);
      await tester.tap(find.byType(DropdownButton<String?>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Number of events').last);
      await tester.pumpAndSettle();
      await tester.enterText(find.widgetWithText(TextField, 'Target'), '3');
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();

      expect(measureOf(await repo.goals(), 'cook'), {
        'kind': 'count',
        'target': 3,
      });
      expect(find.byType(AlertDialog), findsNothing);
    });

    testWidgets('asks before removing the measure, saying its past ratings '
        'stay', (tester) async {
      final repo = measured();
      await tester.pumpWidget(app(repo));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Make an app'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Edit measure'));
      await tester.pumpAndSettle();
      await tester.tap(inDialog(find.text('Remove')));
      await tester.pumpAndSettle();
      expect(find.text('Remove the measure?'), findsOneWidget);
      expect(
        find.text(
          "Make an app will be rated by the average of its sub-goals' "
          'ratings instead. Its past ratings stay.',
        ),
        findsOneWidget,
      );

      await tester.tap(find.text('Keep it'));
      await tester.pumpAndSettle();
      expect(measureOf(await repo.goals(), 'app'), isNotNull);

      await tester.tap(inDialog(find.text('Remove')));
      await tester.pumpAndSettle();
      await tester.tap(inDialog(find.text('Remove')));
      await tester.pumpAndSettle();
      expect(measureOf(await repo.goals(), 'app'), isNull);
      expect(find.byType(AlertDialog), findsNothing);
    });

    testWidgets('asks before throwing away an edit', (tester) async {
      final repo = measured();
      await tester.pumpWidget(app(repo));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Make an app'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Edit measure'));
      await tester.pumpAndSettle();
      await tester.enterText(find.widgetWithText(TextField, 'Target'), '12h');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.text('Discard changes?'), findsOneWidget);

      await tester.tap(find.text('Discard'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(measureOf(await repo.goals(), 'app')?['target_min'], 600);
    });
  });

  testWidgets('says when notes were never compacted', (tester) async {
    await tester.pumpWidget(app(tree()));
    await tester.pumpAndSettle();

    expect(find.text('Notes not compacted yet'), findsOneWidget);
  });

  testWidgets('pressing and holding a goal reorders goals by dragging', (
    tester,
  ) async {
    final repo = tree();
    await tester.pumpWidget(app(repo));
    await tester.pumpAndSettle();

    await tester.longPress(find.text('Hosting'));
    await tester.pumpAndSettle();
    expect(find.text('Reorder goals'), findsOneWidget);
    expect(find.byTooltip('Add goal'), findsNothing);

    // Hosting, dragged above Cooking.
    final handle = find.byTooltip('Drag to move Hosting');
    final gesture = await tester.startGesture(tester.getCenter(handle));
    await tester.pump();
    for (var i = 0; i < 10; i++) {
      await gesture.moveBy(const Offset(0, -15));
      await tester.pump(const Duration(milliseconds: 50));
    }
    await gesture.up();
    await tester.pumpAndSettle();

    expect(shownNames(tester).take(2), ['Hosting', 'Cooking']);
    final saved = [for (final goal in (await repo.goals()).goals) goal.id];
    expect(saved.indexOf('host'), lessThan(saved.indexOf('cook')));

    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(find.text('Goals'), findsOneWidget);
    expect(find.byTooltip('More for Hosting'), findsOneWidget);
  });

  testWidgets(
    "a goal's parent is picked from the tree, and shown as its path",
    (tester) async {
      final repo = tree();
      await tester.pumpWidget(app(repo));
      await tester.pumpAndSettle();

      await openDetails(tester, 'Hosting');
      final dialog = find.byType(AlertDialog);
      final label = find.descendant(
        of: dialog,
        matching: find.text('parent_id'),
      );
      final row = find.ancestor(of: label, matching: find.byType(PropertyRow));
      await tester.tap(find.descendant(of: row, matching: find.text('(none)')));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(DropdownButton<String?>));
      await tester.pumpAndSettle();
      // Listed by name, not by path.
      expect(find.text('Cooking › Tofu tikka'), findsNothing);
      await tester.tap(find.text('Tofu tikka').last);
      await tester.pumpAndSettle();
      // Picked: its whole path.
      expect(find.text('Cooking › Tofu tikka'), findsOneWidget);
      await tester.tap(find.byTooltip('Keep edit'));
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: dialog,
          matching: find.text('Cooking › Tofu tikka'),
        ),
        findsOneWidget,
      );
    },
  );

  /// Opens [goal]'s details, then its measure for editing.
  Future<Finder> openMeasure(WidgetTester tester, String goal) async {
    await openDetails(tester, goal);
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
    // Tapped at once: settling scrolls back to the field being typed in.
    await tester.ensureVisible(find.byTooltip('Keep edit'));
    await tester.tap(find.byTooltip('Keep edit'));
    await tester.pumpAndSettle();
    expect(
      find.descendant(of: dialog, matching: find.text('10h per day')),
      findsOneWidget,
    );
    await tester.tap(find.text('Save 1 change'));
    await tester.pumpAndSettle();

    final cooking = (await repo.goals()).goals.firstWhere(
      (g) => g.id == 'cook',
    );
    expect(cooking.measure, {'kind': 'duration', 'target_min': 600});
    // The Goals page says what it's measured by only under "Measure".
    expect(find.text('10h per day'), findsNothing);
  });

  testWidgets("a measure missing what its kind needs isn't kept", (
    tester,
  ) async {
    await tester.pumpWidget(app(tree()));
    await tester.pumpAndSettle();

    await openMeasure(tester, 'Hosting');
    await pickKind(tester, 'Number of events');
    await tester.ensureVisible(find.byTooltip('Keep edit'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Keep edit'));
    await tester.pumpAndSettle();

    expect(find.text('Enter a target above 0.'), findsOneWidget);
    expect(find.text('Save 1 change'), findsNothing);
  });

  testWidgets("a measure can count another goal's events, without its "
      'sub-goals', (tester) async {
    final repo = tree();
    await tester.pumpWidget(app(repo));
    await tester.pumpAndSettle();

    await openMeasure(tester, 'Cooking');
    await pickKind(tester, 'Time spent');
    await tester.enterText(find.widgetWithText(TextField, 'Target'), '10h');
    await tester.ensureVisible(find.text('Another goal'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Another goal'));
    await tester.pumpAndSettle();
    final pick = find.text('Pick a goal');
    await tester.ensureVisible(pick);
    await tester.pumpAndSettle();
    await tester.tap(pick);
    await tester.pumpAndSettle();
    // Not the goal itself.
    expect(
      find.descendant(
        of: find.byType(DropdownMenuItem<String?>),
        matching: find.text('Cooking'),
      ),
      findsNothing,
    );
    await tester.tap(find.text('Hosting').last);
    await tester.pumpAndSettle();
    final subGoals = find.text("Include its sub-goals' events");
    await tester.ensureVisible(subGoals);
    await tester.tap(subGoals);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byTooltip('Keep edit'));
    await tester.tap(find.byTooltip('Keep edit'));
    await tester.pumpAndSettle();
    expect(
      find.text('10h per day, of Hosting (not sub-goals)'),
      findsOneWidget,
    );
    await tester.tap(find.text('Save 1 change'));
    await tester.pumpAndSettle();

    final cooking = (await repo.goals()).goals.firstWhere(
      (g) => g.id == 'cook',
    );
    expect(cooking.measure, {
      'kind': 'duration',
      'target_min': 600,
      'events_of': 'host',
      'include_sub_goals': false,
    });
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

  test('Goal.fromJson reads its health, trend, stale days and time', () {
    final goal = Goal.fromJson({
      'id': 'g',
      'health': 85,
      'health_period': '2026-09-30',
      'health_trend': '-,40,85',
      'stale_days': 2,
      'minutes_24h': 30,
      'minutes_7d': 300,
    });
    expect(goal.health, 85);
    expect(goal.healthTrend, [null, 40, 85]);
    expect(goal.staleDays, 2);
    expect((goal.minutes24h, goal.minutes7d), (30, 300));
    expect(Goal.fromJson({'id': 'g'}).healthTrend, isEmpty);
  });

  test('GoalList.fromJson reads when notes were last compacted', () {
    final goals = GoalList.fromJson({
      'goals': [],
      'as_of': '2026-10-02T21:05:00-04:00',
    });
    expect(goals.asOf, DateTime.utc(2026, 10, 3, 1, 5));
    expect(GoalList.fromJson({'goals': []}).asOf, isNull);
  });

  test("McpGoalsRepository reads a goal's history", () async {
    final client = _HistoryClient();
    final history = await McpGoalsRepository(client)
        .history(const Goal(id: 'g1'));
    expect(client.arguments, {
      'goal_ids': ['g1'],
    });
    expect(history.map((a) => (a.day, a.rating, a.confirmed)), [
      ('2026-09-29', 60, true),
      ('2026-09-30', null, false),
    ]);
  });

  testWidgets("a rated goal shows its health, trend and what's overdue", (
    tester,
  ) async {
    await tester.pumpWidget(
      app(
        InMemoryGoalsRepository([
          const Goal(
            id: 'cook',
            name: 'Cooking',
            measure: {'kind': 'subjective', 'prompt': 'How was it?'},
            health: 85,
            healthTrend: [null, 40, 85],
            staleDays: 2,
          ),
          const Goal(id: 'idea', name: 'Idea', status: 'proposed'),
        ]),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(HealthDot), findsOneWidget); // not for the proposed one
    expect(find.text('85'), findsOneWidget);
    expect(find.byType(TrendSparkline), findsOneWidget);
    expect(find.text('2 days unrated'), findsOneWidget);
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
              health: 60,
              healthTrend: [60],
              staleDays: 0,
            ),
          ],
          {
            'cook': [
              const Assessment(
                goalId: 'cook',
                day: '2026-09-29',
                rating: 60,
                explanation: '3h of 5h in the day → 60',
              ),
              const Assessment(
                goalId: 'cook',
                day: '2026-09-30',
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
    expect(periods, ['2026-09-30 · proposed · metric', '2026-09-29']);
    expect(find.text('3h of 5h in the day → 60'), findsOneWidget);

    // Its ratings, on the Goals page, open it too.
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.byType(TrendSparkline));
    await tester.pumpAndSettle();
    expect(find.byType(HealthHistoryChart), findsOneWidget);
  });

  testWidgets('a goal with no assessments says how it gets some', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: GoalHistoryScreen(
          goal: const Goal(id: 'g', name: 'G'),
          repository: InMemoryGoalsRepository(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.text(
        'No ratings yet.\nGoals are rated in the daily reflection: those '
        'with a measure, and those with sub-goals that are.',
      ),
      findsOneWidget,
    );
  });

  group('the overall goal', () {
    InMemoryGoalsRepository withOverall() => InMemoryGoalsRepository(
      [
        const Goal(
          id: overallGoalId,
          name: 'Overall',
          health: 72,
          healthTrend: [60, 72],
          staleDays: 0,
        ),
        const Goal(id: 'cook', name: 'Cooking'),
        const Goal(id: 'old', name: 'Old habit', status: 'inactive'),
      ],
      {
        overallGoalId: [
          const Assessment(
            goalId: overallGoalId,
            day: '2026-09-30',
            rating: 72,
          ),
        ],
      },
      DateTime(2026, 10, 2, 21),
      const [
        StatusMinutes(statuses: {'active'}, minutes24h: 60, minutes7d: 600),
        StatusMinutes(statuses: {'inactive'}, minutes24h: 30, minutes7d: 90),
        StatusMinutes(
          statuses: {'active', 'inactive'},
          minutes24h: 0,
          minutes7d: 45,
        ),
      ],
    );

    testWidgets("each goal's time counts only its sub-goals with the "
        'statuses shown', (tester) async {
      await tester.pumpWidget(
        app(
          InMemoryGoalsRepository(
            [
              const Goal(
                id: 'work',
                name: 'Work',
                minutes24h: 90,
                minutes7d: 690,
                minutesByStatuses: [
                  StatusMinutes(
                    statuses: {'active'},
                    minutes24h: 60,
                    minutes7d: 600,
                  ),
                  // Its inactive sub-goal's.
                  StatusMinutes(
                    statuses: {'inactive'},
                    minutes24h: 30,
                    minutes7d: 90,
                  ),
                ],
              ),
            ],
            const {},
            DateTime(2026, 10, 2, 21),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('1h 30m in 24h · 11h 30m in 7d'), findsOneWidget);

      await tester.tap(find.byTooltip('Show goals that are…'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(CheckboxMenuButton, 'Inactive'));
      await tester.pumpAndSettle();

      expect(find.text('1h in 24h · 10h in 7d'), findsOneWidget);
    });

    test('GoalList totals the time on goals of any of some statuses', () {
      final goals = GoalList.fromJson({
        'goals': [],
        'minutes_by_statuses': [
          {
            'statuses': ['active'],
            'minutes_24h': 60,
            'minutes_7d': 600,
          },
          {
            'statuses': ['active', 'inactive'],
            'minutes_24h': 10,
            'minutes_7d': 45,
          },
          {
            'statuses': ['inactive'],
            'minutes_24h': 30,
            'minutes_7d': 90,
          },
        ],
      });
      expect(goals.timeFor({'active'}), (70, 645));
      expect(goals.timeFor({'inactive'}), (40, 135));
      expect(goals.timeFor({'active', 'inactive'}), (100, 735));
      expect(goals.timeFor({'deleted'}), (0, 0));
      expect(GoalList.fromJson({'goals': []}).timeFor({'active'}), isNull);
    });

    testWidgets('sits above the tree with the time on the goals shown, '
        'which follows the filter', (tester) async {
      await tester.pumpWidget(app(withOverall()));
      await tester.pumpAndSettle();

      // Not in the tree itself.
      expect(shownNames(tester), ['Overall', 'Cooking', 'Old habit']);
      expect(find.byType(Card), findsOneWidget);
      expect(
        find.text('1h 30m in 24h · 12h 15m in 7d on the goals shown'),
        findsOneWidget,
      );

      await tester.tap(find.byTooltip('Show goals that are…'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(CheckboxMenuButton, 'Inactive'));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('1h in 24h · 10h 45m in 7d on the goals shown'),
        findsOneWidget,
      );
    });

    testWidgets('opens its details, without a status or parent, and its '
        'history from its ratings', (tester) async {
      await tester.pumpWidget(app(withOverall()));
      await tester.pumpAndSettle();

      // Tapping it shows its measure, which leads to its details.
      await tester.tap(find.text('Overall'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Details'));
      await tester.pumpAndSettle();
      final dialog = find.byType(AlertDialog);
      expect(
        find.descendant(of: dialog, matching: find.text('measure')),
        findsOneWidget,
      );
      for (final property in ['status', 'parent_id', 'background_color']) {
        final row = find.ancestor(
          of: find.descendant(of: dialog, matching: find.text(property)),
          matching: find.byType(PropertyRow),
        );
        // Shown, but not editable: no tap target.
        expect(
          find.descendant(of: row, matching: find.byType(InkWell)),
          findsNothing,
          reason: property,
        );
      }
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('History of Overall'));
      await tester.pumpAndSettle();
      expect(find.byType(HealthHistoryChart), findsOneWidget);
    });

    testWidgets("isn't offered as a goal's parent", (tester) async {
      await tester.pumpWidget(app(withOverall()));
      await tester.pumpAndSettle();

      await openDetails(tester, 'Cooking');
      final dialog = find.byType(AlertDialog);
      final row = find.ancestor(
        of: find.descendant(of: dialog, matching: find.text('parent_id')),
        matching: find.byType(PropertyRow),
      );
      await tester.tap(find.descendant(of: row, matching: find.text('(none)')));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(DropdownButton<String?>));
      await tester.pumpAndSettle();

      expect(find.text('Old habit'), findsWidgets);
      expect(
        find.descendant(
          of: find.byType(DropdownMenuItem<String?>),
          matching: find.text('Overall'),
        ),
        findsNothing,
      );
    });
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
        'day': '2026-09-29',
        'rating': 60,
        'method': 'subjective',
        'status': 'confirmed',
      },
      {
        'goal_id': 'g1',
        'day': '2026-09-30',
        'rating': 'skip',
        'method': 'subjective',
        'status': 'proposed',
      },
    ];
  }
}

/// Holds each save until the test answers it, or fails it.
class _GatedGoalsRepository implements GoalsRepository {
  _GatedGoalsRepository(this._inner);

  final InMemoryGoalsRepository _inner;

  /// What's been sent, oldest first: "create" and its name, or "update" and its id.
  final sent = <String>[];
  final _waiting = <Completer<void>>[];

  /// Lets the oldest save waiting through.
  void answer() => _waiting.removeAt(0).complete();

  /// Fails the oldest save waiting with [error].
  void fail(Object error) => _waiting.removeAt(0).completeError(error);

  Future<void> _gate(String what) {
    sent.add(what);
    final gate = Completer<void>();
    _waiting.add(gate);
    return gate.future;
  }

  /// How many times every goal has been fetched.
  var fetches = 0;

  @override
  Future<String?> createGoal(Map<String, Object?> fields) async {
    await _gate('create ${fields['name']}');
    return _inner.createGoal(fields);
  }

  @override
  Future<void> updateGoal(Goal goal, Map<String, Object?> changes) async {
    await _gate('update ${goal.id}');
    return _inner.updateGoal(goal, changes);
  }

  @override
  Future<GoalList> goals() {
    fetches++;
    return _inner.goals();
  }

  @override
  Future<GoalList?> cachedGoals() => _inner.cachedGoals();

  @override
  Future<GoalList> reorderGoals(List<String> ids) => _inner.reorderGoals(ids);

  @override
  Future<List<Assessment>> history(Goal goal) => _inner.history(goal);
}
