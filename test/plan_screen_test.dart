import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:time_tracker_client/outbox/pending_action_save.dart';
import 'package:time_tracker_client/outbox/outbox_store.dart';
import 'package:time_tracker_client/outbox/action_outbox.dart';
import 'package:time_tracker_client/models/event.dart';
import 'package:time_tracker_client/models/plan_action.dart';
import 'package:time_tracker_client/models/note.dart';
import 'package:time_tracker_client/models/person.dart';
import 'package:time_tracker_client/screens/plan_screen.dart';
import 'package:time_tracker_client/models/trait.dart';
import 'package:time_tracker_client/services/events_repository.dart';
import 'package:time_tracker_client/services/actions_repository.dart';
import 'package:time_tracker_client/services/notes_repository.dart';
import 'package:time_tracker_client/services/people_repository.dart';
import 'package:time_tracker_client/services/plan_memory.dart';
import 'package:time_tracker_client/services/traits_repository.dart';
import 'package:time_tracker_client/services/mcp_client.dart';
import 'package:time_tracker_client/widgets/actions_picker.dart';
import 'package:time_tracker_client/widgets/priority_chip.dart';
import 'package:time_tracker_client/widgets/properties_dialog.dart';

void main() {
  /// The Plan page over [repo], saving through [outbox], or an outbox of
  /// its own: its Actions pane, with no traits or people to show, and
  /// with [events], a summary of them, measured from [lastCompaction].
  Widget app(
    ActionsRepository repo, {
    ActionOutbox? outbox,
    Future<void> Function()? onSignIn,
    EventsRepository? events,
    DateTime? lastCompaction,
    PlanMemory? memory,
  }) => MaterialApp(
    home: PlanScreen(
      repository: repo,
      outbox:
          outbox ??
          (ActionOutbox(store: InMemoryOutboxStore(), repository: repo)
            ..start()),
      serverLabel: 'offline demo',
      onSignIn: onSignIn,
      eventsRepository: events,
      notesRepository: InMemoryNotesRepository(
        const [],
        CompactionStatus(lastCompaction: lastCompaction),
      ),
      memory: memory,
    ),
  );

  InMemoryActionsRepository tree() => InMemoryActionsRepository([
    const PlanAction(
      id: 'cook',
      name: 'Cooking',
      priority: 1,
      properties: {'kind': 'group'},
    ),
    const PlanAction(id: 'tofu', name: 'Tofu tikka', parentId: 'cook'),
    const PlanAction(id: 'host', name: 'Hosting'),
    const PlanAction(id: 'idea', name: 'Idea', status: 'proposed'),
    const PlanAction(id: 'old', name: 'Old habit', status: 'proposed'),
    const PlanAction(id: 'done', name: 'Done thing', status: 'archived'),
    const PlanAction(id: 'shelf', name: 'Shelved', status: 'archived'),
    const PlanAction(id: 'oops', name: 'Oops', status: 'deleted'),
  ]);

  /// The text field in the dialog open: not the Actions pane's search.
  final dialogField = find.descendant(
    of: find.byType(AlertDialog),
    matching: find.byType(TextField),
  );

  /// The status filter's check box for [status], in its drop-down.
  Finder option(String status) =>
      find.widgetWithText(CheckboxMenuButton, status);

  bool ticked(WidgetTester tester, String status) =>
      tester.widget<CheckboxMenuButton>(option(status)).value == true;

  /// An action's name, from its title: plain, or with a priority chip after
  /// it.
  String? nameIn(Text title) =>
      title.data ?? (title.textSpan as TextSpan?)?.text;

  List<String?> shownNames(WidgetTester tester) => tester
      .widgetList<ListTile>(find.byType(ListTile))
      .map((t) => nameIn(t.title as Text))
      .toList();

  /// The title of the action named [name].
  Finder titled(String name) =>
      find.byWidgetPredicate((w) => w is Text && nameIn(w) == name);

  /// Taps [name]'s group, showing or hiding what's in it.
  Future<void> toggle(WidgetTester tester, String name) async {
    await tester.tap(
      find.descendant(of: find.byType(ListTile), matching: titled(name)).first,
    );
    await tester.pumpAndSettle();
  }

  /// The bands down the left of [name]'s action.
  ActionBands bandsOf(WidgetTester tester, String name) =>
      tester.widget<ActionBands>(
        find.descendant(
          of: find
              .ancestor(
                of: find
                    .descendant(
                      of: find.byType(ListTile),
                      matching: titled(name),
                    )
                    .first,
                matching: find.byType(Stack),
              )
              .first,
          matching: find.byType(ActionBands),
        ),
      );

  /// Opens [name]'s details from its menu, through its Edit dialog.
  Future<void> openDetails(WidgetTester tester, String name) async {
    await tester.tap(find.byTooltip('More for $name'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Details'));
    await tester.pumpAndSettle();
  }

  test('PlanAction.fromJson reads a server from before statuses', () {
    expect(
      PlanAction.fromJson({'id': 'g', 'active': false}).status,
      'archived',
    );
    expect(PlanAction.fromJson({'id': 'g', 'active': true}).status, 'active');
    expect(
      PlanAction.fromJson({'id': 'g', 'status': 'archived'}).active,
      isFalse,
    );
  });

  test('PlanAction.fromJson keeps every property the server sent', () {
    final action = PlanAction.fromJson({
      'id': 'g1',
      'parent_id': 'g0',
      'name': 'Tofu tikka',
      'status': 'archived',
      'background_color': '#7bd148',
      'priority': 2,
      'path': 'Cooking › Tofu tikka',
      'new_thing': 'x',
    });
    expect(action.parentId, 'g0');
    expect(action.active, isFalse);
    expect(action.depth, 1);
    expect(action.properties['new_thing'], 'x');
  });

  testWidgets('a server error after sign-in is shown, not the sign-in '
      'prompt', (tester) async {
    final repo = _SignInActionsRepository(tree())
      ..failure = McpException('Tool get_actions failed: token revoked');
    await tester.pumpWidget(
      app(repo, onSignIn: () async => repo.signedIn = true),
    );
    await tester.pumpAndSettle();
    expect(find.text('Sign in to see your plan.'), findsOneWidget);

    await tester.tap(find.text('Sign in'));
    await tester.pumpAndSettle();
    expect(find.text('Sign in to see your plan.'), findsNothing);
    expect(find.textContaining('Could not load actions.'), findsOneWidget);
    expect(find.textContaining('token revoked'), findsOneWidget);
  });

  testWidgets(
    'lists proposed and active actions as a tree, with the label count',
    (tester) async {
      await tester.pumpWidget(app(tree()));
      await tester.pumpAndSettle();

      // Sub-actions start collapsed, their parent's band an arrow; how many
      // isn't said.
      expect(shownNames(tester), ['Cooking', 'Hosting', 'Idea', 'Old habit']);
      expect(bandsOf(tester, 'Cooking').shape, ActionBandShape.collapsed);
      expect(find.textContaining('sub-action'), findsNothing);
      // Its priority, after its name.
      expect(find.text('P1'), findsOneWidget);
      expect(find.text('Proposed by Claude: review it'), findsWidgets);
      // Groups hold none.
      expect(find.text('2 of 200 labels in use'), findsOneWidget);
      // Only an action with sub-actions can be expanded.
      expect(bandsOf(tester, 'Hosting').shape, ActionBandShape.plain);

      await toggle(tester, 'Cooking');
      expect(shownNames(tester), [
        'Cooking',
        'Tofu tikka',
        'Hosting',
        'Idea',
        'Old habit',
      ]);
      expect(bandsOf(tester, 'Cooking').shape, ActionBandShape.expanded);
      // The sub-action is indented under its parent, beside its band.
      expect(bandsOf(tester, 'Cooking').bands, hasLength(1));
      expect(bandsOf(tester, 'Tofu tikka').bands, hasLength(2));
      // Its inherited priority, too.
      expect(find.text('P1'), findsNWidgets(2));

      await toggle(tester, 'Cooking');
      expect(shownNames(tester), ['Cooking', 'Hosting', 'Idea', 'Old habit']);
    },
  );

  testWidgets("the filter in the Actions heading picks which statuses are "
      'shown', (tester) async {
    await tester.pumpWidget(app(tree()));
    await tester.pumpAndSettle();
    Badge badge() => tester.widget<Badge>(
      find.descendant(
        of: find.byTooltip('Show actions that are…'),
        matching: find.byType(Badge),
      ),
    );
    expect(badge().isLabelVisible, isFalse);

    await tester.tap(find.byTooltip('Show actions that are…'));
    await tester.pumpAndSettle();
    for (final status in ['Proposed', 'Active']) {
      expect(ticked(tester, status), isTrue);
    }
    expect(ticked(tester, 'Archived'), isFalse);
    expect(ticked(tester, 'Deleted'), isFalse);
    // Actions are never inactive or completed.
    expect(option('Inactive'), findsNothing);
    expect(option('Completed'), findsNothing);

    // It stays open while several are ticked.
    await tester.tap(option('Proposed'));
    await tester.pumpAndSettle();
    await tester.tap(option('Archived'));
    await tester.pumpAndSettle();
    await tester.tap(option('Deleted'));
    await tester.pumpAndSettle();
    expect(ticked(tester, 'Proposed'), isFalse);
    expect(ticked(tester, 'Deleted'), isTrue);
    expect(shownNames(tester), contains('Done thing'));
    expect(shownNames(tester), contains('Oops'));
    expect(shownNames(tester), isNot(contains('Old habit')));
    expect(badge().isLabelVisible, isTrue);

    for (final status in ['Active', 'Archived', 'Deleted']) {
      await tester.tap(option(status));
      await tester.pumpAndSettle();
    }
    expect(find.text('No actions with these statuses.'), findsOneWidget);
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

  testWidgets("an action's status is changed in its details, asking first "
      'to move an active one', (tester) async {
    final repo = tree();
    await tester.pumpWidget(app(repo));
    await tester.pumpAndSettle();

    await pickStatus(tester, 'Hosting', 'Archived');
    expect(find.text('Move Hosting to archived?'), findsOneWidget);
    await tester.tap(find.text('Keep it'));
    await tester.pumpAndSettle();
    // Still open, with the change kept, to save or revert.
    expect(find.text('Save 1 change'), findsOneWidget);
    expect(
      (await repo.actions()).actions.firstWhere((g) => g.id == 'host').status,
      'active',
    );

    await tester.tap(find.text('Save 1 change'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Archived'));
    await tester.pumpAndSettle();
    // Archived actions aren't shown until asked for.
    expect(shownNames(tester), isNot(contains('Hosting')));
    expect(
      (await repo.actions()).actions.firstWhere((g) => g.id == 'host').status,
      'archived',
    );
  });

  testWidgets('a proposed action is made active without a check', (
    tester,
  ) async {
    final repo = tree();
    await tester.pumpWidget(app(repo));
    await tester.pumpAndSettle();

    await pickStatus(tester, 'Idea', 'Active');

    expect(
      (await repo.actions()).actions.firstWhere((g) => g.id == 'idea').status,
      'active',
    );
  });

  testWidgets('deleting asks first, then hides the action', (tester) async {
    final repo = tree();
    await tester.pumpWidget(app(repo));
    await tester.pumpAndSettle();

    await pickStatus(tester, 'Old habit', 'Deleted');
    expect(find.text('Delete Old habit?'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, 'Delete'));
    await tester.pumpAndSettle();

    expect(shownNames(tester), isNot(contains('Old habit')));
    expect(
      (await repo.actions()).actions.firstWhere((g) => g.id == 'old').status,
      'deleted',
    );
  });

  testWidgets("a group's menu adds to it; an action's edits it; a proposed "
      "one's approves it", (tester) async {
    final repo = tree();
    await tester.pumpWidget(app(repo));
    await tester.pumpAndSettle();
    Future<List<String?>> menuOf(String name) async {
      await tester.tap(find.byTooltip('More for $name'));
      await tester.pumpAndSettle();
      return tester
          .widgetList<PopupMenuItem<String>>(find.byType(PopupMenuItem<String>))
          .map((i) => (i.child as Text).data)
          .toList();
    }

    expect(await menuOf('Cooking'), ['Add action', 'Add group', 'Edit']);
    await tester.tapAt(Offset.zero);
    await tester.pumpAndSettle();
    expect(await menuOf('Idea'), ['Approve', 'Edit']);
    await tester.tap(find.text('Approve'));
    await tester.pumpAndSettle();
    expect(
      (await repo.actions()).actions.firstWhere((g) => g.id == 'idea').status,
      'active',
    );
    expect(await menuOf('Hosting'), ['Edit']);

    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text('Hosting'),
      ),
      findsWidgets,
    );
  });

  testWidgets("tapping a group opens or closes it; tapping an action edits "
      'its priority and color, from which "Details" opens the rest', (
    tester,
  ) async {
    final repo = tree();
    await tester.pumpWidget(app(repo));
    await tester.pumpAndSettle();

    await toggle(tester, 'Cooking');
    expect(shownNames(tester), contains('Tofu tikka'));
    expect(find.byType(AlertDialog), findsNothing);
    await toggle(tester, 'Cooking');
    expect(shownNames(tester), isNot(contains('Tofu tikka')));

    await tester.tap(titled('Hosting'));
    await tester.pumpAndSettle();
    final dialog = find.byType(AlertDialog);
    expect(
      find.descendant(of: dialog, matching: find.byType(PriorityChip)),
      findsOneWidget,
    );
    expect(find.descendant(of: dialog, matching: find.text('Color')), findsOne);
    await tester.tap(
      find.descendant(of: dialog, matching: find.byType(PriorityChip)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ChoiceChip, 'P0'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(
      (await repo.actions()).actions.firstWhere((g) => g.id == 'host').priority,
      0,
    );

    // A group's menu edits it the same way; "Details" opens the rest.
    await tester.tap(find.byTooltip('More for Cooking'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Details'));
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text('parent_id'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('tapping a group opens it; swiping goes to the next pane', (
    tester,
  ) async {
    await tester.pumpWidget(
      TraitsScope(
        repository: InMemoryTraitsRepository(
          traits: const [
            Trait(
              id: 'kind',
              name: 'Kind',
              parts: [
                {'kind': 'follow_through'},
              ],
            ),
          ],
        ),
        child: app(tree()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.widgetWithText(Tab, 'Actions'), findsOneWidget);

    await toggle(tester, 'Cooking');
    expect(shownNames(tester), contains('Tofu tikka'));

    await tester.fling(titled('Cooking').first, const Offset(-300, 0), 1000);
    await tester.pumpAndSettle();
    expect(find.text('Kind'), findsOneWidget);
    // Still open, back on Actions.
    await tester.tap(find.widgetWithText(Tab, 'Actions'));
    await tester.pumpAndSettle();
    expect(shownNames(tester), contains('Tofu tikka'));
  });

  testWidgets('searching shows what matches, in its groups', (tester) async {
    await tester.pumpWidget(app(tree()));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'tofu');
    await tester.pumpAndSettle();
    expect(shownNames(tester), ['Cooking', 'Tofu tikka']);
    // Nothing reorders mid-search.
    await tester.longPress(titled('Tofu tikka'));
    await tester.pumpAndSettle();
    expect(find.text('Reorder actions'), findsNothing);
    // It's a tap, then: its details open.
    Navigator.of(tester.element(find.byType(AlertDialog))).pop();
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'nothing like it');
    await tester.pumpAndSettle();
    expect(find.text('Nothing matches “nothing like it”.'), findsOneWidget);

    await tester.tap(find.byTooltip('Clear the search'));
    await tester.pumpAndSettle();
    expect(shownNames(tester), ['Cooking', 'Hosting', 'Idea', 'Old habit']);
  });

  testWidgets('adds an action to the group whose menu it came from', (
    tester,
  ) async {
    final repo = tree();
    await tester.pumpWidget(app(repo));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('More for Cooking'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add action'));
    await tester.pumpAndSettle();
    expect(find.text('New action'), findsOneWidget);
    // Its group, by name.
    expect(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text('Cooking'),
      ),
      findsOneWidget,
    );

    // Saving with no name is refused.
    await tester.tap(find.text('(none)').first);
    await tester.pumpAndSettle();
    await tester.enterText(dialogField, 'Make curry');
    await tester.tap(find.byTooltip('Keep edit'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save 1 change'));
    await tester.pumpAndSettle();

    final added = (await repo.actions()).actions.firstWhere(
      (g) => g.name == 'Make curry',
    );
    expect(added.parentId, 'cook');
    expect(added.isGroup, isFalse);
    // Its group is expanded, so it's in sight.
    expect(shownNames(tester), [
      'Cooking',
      'Tofu tikka',
      'Make curry',
      'Hosting',
      'Idea',
      'Old habit',
    ]);
  });

  testWidgets('adds a group from the Actions heading', (tester) async {
    final repo = tree();
    await tester.pumpWidget(app(repo));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Add an action or group'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('New group'));
    await tester.pumpAndSettle();
    expect(find.text('New group'), findsOneWidget);
    await tester.tap(find.text('(none)').first);
    await tester.pumpAndSettle();
    await tester.enterText(dialogField, 'Music');
    await tester.tap(find.byTooltip('Keep edit'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save 1 change'));
    await tester.pumpAndSettle();

    final added = (await repo.actions()).actions.firstWhere(
      (g) => g.name == 'Music',
    );
    expect(added.isGroup, isTrue);
    expect(find.text('Empty group'), findsOneWidget);
  });

  /// Lets a second go by, a frame at a time: what pumpAndSettle does,
  /// for when an action being saved keeps it from settling.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  /// In the dialog open, sets the action's name to [name].
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
    await tester.enterText(dialogField, name);
    await tester.tap(find.byTooltip('Keep edit'));
    await settle(tester);
  }

  /// Adds a top-level action named [name] from the "+" in the Actions
  /// heading.
  Future<void> addAction(WidgetTester tester, String name) async {
    await tester.tap(find.byTooltip('Add an action or group'));
    await settle(tester);
    await tester.tap(find.text('New action'));
    await settle(tester);
    await tester.tap(find.text('(none)').first);
    await settle(tester);
    await tester.enterText(dialogField, name);
    await tester.tap(find.byTooltip('Keep edit'));
    await settle(tester);
    await tester.tap(find.text('Save 1 change'));
    await settle(tester);
  }

  testWidgets('saving closes the dialog at once, and saves in the '
      'background, in order', (tester) async {
    final repo = _GatedActionsRepository(tree());
    await tester.pumpWidget(app(repo));
    await settle(tester);

    await addAction(tester, 'Running');
    await settle(tester);
    // Closed, and shown already, saving.
    expect(find.byType(AlertDialog), findsNothing);
    expect(shownNames(tester), contains('Running'));
    expect(find.byTooltip('Saving…'), findsOneWidget);
    // Another can be added straight away.
    await addAction(tester, 'Swimming');
    await settle(tester);
    expect(shownNames(tester), containsAllInOrder(['Running', 'Swimming']));
    expect(find.byTooltip('Saving…'), findsNWidgets(2));
    // Renaming an action shows at once, too.
    await tester.tap(find.byTooltip('More for Hosting'));
    await settle(tester);
    await tester.tap(find.text('Edit'));
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
    // The actions are only fetched once every change is saved.
    expect(repo.fetches, fetched);
    repo.answer();
    await tester.pumpAndSettle();
    expect(repo.fetches, fetched + 1);
    expect(shownNames(tester), containsAll(['Running', 'Swimming', 'Parties']));
    expect(
      (await repo.actions()).actions.map((g) => g.name),
      containsAll(['Running', 'Swimming', 'Parties']),
    );
  });

  testWidgets('a new action that fails to save stays, marked, to edit and '
      'save again', (tester) async {
    final repo = _GatedActionsRepository(tree());
    await tester.pumpWidget(app(repo));
    await tester.pumpAndSettle();

    await addAction(tester, 'Running');
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
      (await repo.actions()).actions.map((g) => g.name),
      containsAll(['Jogging']),
    );
  });

  testWidgets('a save that failed can be tried again as it was, or '
      'discarded', (tester) async {
    final repo = _GatedActionsRepository(tree());
    await tester.pumpWidget(app(repo));
    await tester.pumpAndSettle();

    await addAction(tester, 'Running');
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

  testWidgets('an action that failed to save is still there when the app opens '
      'again', (tester) async {
    final store = InMemoryOutboxStore<PendingActionSave>();
    final repo = _GatedActionsRepository(tree());
    ActionOutbox outbox() =>
        ActionOutbox(store: store, repository: repo)..start();
    await tester.pumpWidget(app(repo, outbox: outbox()));
    await tester.pumpAndSettle();
    await addAction(tester, 'Running');
    repo.fail(McpException('No room for it.'));
    await tester.pumpAndSettle();

    // The app closes, and opens again.
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(app(repo, outbox: outbox()));
    await tester.pumpAndSettle();
    expect(shownNames(tester), contains('Running'));
    expect(find.byTooltip('Not saved: No room for it.'), findsOneWidget);
  });

  testWidgets('a new action saved by the background task stays shown until '
      'the actions are fetched with it', (tester) async {
    final store = InMemoryOutboxStore<PendingActionSave>();
    final server = tree();
    final repo = _GatedActionsRepository(server);
    // Not started: as when the app is in the background.
    final outbox = ActionOutbox(store: store, repository: repo);
    await tester.pumpWidget(app(repo, outbox: outbox));
    await tester.pumpAndSettle();
    await addAction(tester, 'Running');
    expect(repo.sent, isEmpty);
    expect(find.byTooltip('Saving…'), findsOneWidget);

    // The background task saves it, with its own outbox.
    await ActionOutbox(
      store: store,
      repository: server,
    ).flush(ignoreBackoff: true);
    repo.fetchGate = Completer();
    final fetched = repo.fetches;

    // The app hears of it only as gone from the outbox.
    await outbox.refresh();
    await tester.pump();
    expect(outbox.saves, isEmpty);
    expect(repo.fetches, fetched + 1);
    expect(shownNames(tester), contains('Running'));

    repo.fetchGate!.complete();
    await tester.pumpAndSettle();
    expect(shownNames(tester), contains('Running'));
    expect(find.byTooltip('Saving…'), findsNothing);
    expect(find.byTooltip('More for Running'), findsOneWidget);
  });

  testWidgets('a change that fails to save stays, to edit and save again', (
    tester,
  ) async {
    final repo = _GatedActionsRepository(tree());
    await tester.pumpWidget(app(repo));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('More for Hosting'));
    await settle(tester);
    await tester.tap(find.text('Edit'));
    await settle(tester);
    await tester.tap(find.text('Details'));
    await settle(tester);
    await rename(tester, 'Parties');
    await tester.tap(find.text('Save 1 change'));
    await settle(tester);
    repo.fail(McpException('Try later.'));
    await tester.pumpAndSettle();
    // Kept, though the actions were fetched again.
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
      (await repo.actions()).actions.firstWhere((g) => g.id == 'host').name,
      'Parties',
    );
  });

  testWidgets('a new action needs a name', (tester) async {
    await tester.pumpWidget(app(tree()));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Add an action or group'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('New action'));
    await tester.pumpAndSettle();
    expect(find.text('New action'), findsOneWidget);
    // Change something other than the name, then try to save.
    await tester.tap(find.text('(none)').at(2)); // priority
    await tester.pumpAndSettle();
    await tester.enterText(dialogField, '2');
    await tester.tap(find.byTooltip('Keep edit'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save 1 change'));
    await tester.pumpAndSettle();
    expect(find.textContaining('It needs a name.'), findsOneWidget);
  });

  test('a time is said in hours and minutes, or as shares of each window', () {
    expect(describeTime(540, 0), '9h in 24h · 0m in 7d');
    expect(describeTime(0, 1680), '0m in 24h · 28h in 7d');
    // An action's leaves out a window with no time.
    expect(describeTime(540, 0, skipZero: true), '9h in 24h');
    expect(describeTime(0, 420, skipZero: true), '7h in 7d');
    expect(describeTime(0, 0, skipZero: true), isNull);
    expect(describeTime(0, 0), '0m in 24h · 0m in 7d');
    // Or just the shares, however small.
    expect(describeTime(540, 0, asPercent: true), '37.5% of 24h · 0% of 7d');
    expect(describeTime(60, 5, asPercent: true), '4.2% of 24h · <0.1% of 7d');
    expect(describeTime(0, 600, skipZero: true, asPercent: true), '6% of 7d');
  });

  group('the summaries', () {
    // A Thursday evening, after a compaction at 9 PM.
    final compacted = DateTime(2026, 10, 1, 21);
    Event event(
      String id,
      DateTime start,
      Duration length, {
      List<String> actions = const [],
      int? priority,
    }) => Event.fromJson({
      'id': id,
      'summary': id,
      'start': localIsoTimestamp(start),
      'end': localIsoTimestamp(start.add(length)),
      'action_ids': actions,
      'effective_priority': ?priority,
    });
    InMemoryEventsRepository events() => InMemoryEventsRepository([
      // An hour of tofu on the day, two more in the week, and an hour
      // of hosting the next day.
      event(
        'tonight',
        DateTime(2026, 10, 1, 18),
        const Duration(hours: 1),
        actions: ['tofu'],
        priority: 1,
      ),
      event(
        'monday',
        DateTime(2026, 9, 28, 18),
        const Duration(hours: 2),
        actions: ['tofu'],
      ),
      event(
        'tomorrow',
        DateTime(2026, 10, 2, 12),
        const Duration(hours: 1),
        actions: ['host'],
      ),
    ]);

    setUp(
      () => SharedPreferencesAsyncPlatform.instance =
          InMemorySharedPreferencesAsync.empty(),
    );
    tearDown(
      () => SharedPreferencesAsyncPlatform.instance =
          InMemorySharedPreferencesAsync.empty(),
    );

    testWidgets("measure back from the last compaction, the shown actions' "
        "time in each, and each one's in its row", (tester) async {
      await tester.pumpWidget(
        app(tree(), events: events(), lastCompaction: compacted),
      );
      await tester.pumpAndSettle();

      expect(find.text('Last compaction'), findsOneWidget);
      expect(find.textContaining('As of'), findsOneWidget);
      // Cooking, collapsed, has its tofu's time.
      expect(find.text('Cooking'), findsWidgets);
      expect(find.text('1h in 24h · 3h in 7d'), findsOneWidget);
      // Hosting's is tomorrow: not in the window.
      expect(
        find.descendant(
          of: find.widgetWithText(ListTile, 'Hosting'),
          matching: find.textContaining('in 24h'),
        ),
        findsNothing,
      );
      await toggle(tester, 'Cooking');
      expect(find.text('1h in 24h · 3h in 7d'), findsNWidgets(2));
    });

    testWidgets('move a day at a time, look on rather than back, and come '
        'back to the last compaction', (tester) async {
      await tester.pumpWidget(
        app(tree(), events: events(), lastCompaction: compacted),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('A day later'));
      await tester.pumpAndSettle();
      expect(find.text('+1 day from last compaction'), findsOneWidget);
      // Hosting, tomorrow, is in the day now; tonight's tofu too.
      expect(find.text('1h in 24h · 1h in 7d'), findsOneWidget);

      await tester.tap(find.text('+1 day from last compaction'));
      await tester.pumpAndSettle();
      expect(find.text('Last compaction'), findsOneWidget);

      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
      expect(find.textContaining('From'), findsOneWidget);
      // Only hosting is after the compaction.
      expect(find.text('1h in +24h · 1h in +7d'), findsOneWidget);
      expect(find.textContaining('in 24h'), findsNothing);
    });

    testWidgets("split the window by priority, and turn to percentages, as "
        'the rows do, kept for next time', (tester) async {
      await tester.pumpWidget(
        app(tree(), events: events(), lastCompaction: compacted),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('By priority'));
      await tester.pumpAndSettle();
      expect(find.text('P1'), findsWidgets);

      await tester.tap(find.byTooltip('Show percentages'));
      await tester.pumpAndSettle();
      expect(find.text('4.2% of 24h · 1.8% of 7d'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(
        app(tree(), events: events(), lastCompaction: compacted),
      );
      await tester.pumpAndSettle();
      expect(find.text('4.2% of 24h · 1.8% of 7d'), findsOneWidget);
    });
  });

  testWidgets('comes back as it was, from what it kept, while it loads '
      'again', (tester) async {
    final memory = PlanMemory();
    await tester.pumpWidget(app(tree(), memory: memory));
    await tester.pumpAndSettle();
    expect(shownNames(tester), contains('Hosting'));

    // Back again, with a server that hasn't answered yet.
    final slow = _GatedActionsRepository(tree())..fetchGate = Completer();
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(app(slow, memory: memory));
    await tester.pump();
    expect(shownNames(tester), contains('Hosting'));
    expect(find.byType(LinearProgressIndicator), findsNothing);
    slow.fetchGate!.complete();
    await tester.pumpAndSettle();
  });

  testWidgets("loads every pane's people and locations on landing, once", (
    tester,
  ) async {
    final people = _CountingPeopleRepository();
    await tester.pumpWidget(
      PeopleScope(repository: people, child: app(tree())),
    );
    await tester.pumpAndSettle();
    // Before the People pane is ever shown.
    expect(people.calls, ['people', 'locations']);

    await tester.tap(find.widgetWithText(Tab, 'People'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(Tab, 'Locations'));
    await tester.pumpAndSettle();
    expect(people.calls, ['people', 'locations']);
    expect(find.text('Home'), findsOneWidget);
  });

  group("an action's priority", () {
    InMemoryActionsRepository withColors() => InMemoryActionsRepository([
      const PlanAction(
        id: 'cook',
        name: 'Cooking',
        priority: 1,
        properties: {'kind': 'group'},
      ),
      const PlanAction(id: 'tofu', name: 'Tofu tikka', parentId: 'cook'),
      const PlanAction(
        id: 'curry',
        name: 'Curry',
        parentId: 'cook',
        priority: 3,
        backgroundColor: '#123456',
      ),
    ]);

    PriorityChip chipOf(WidgetTester tester, String name) =>
        tester.widget<PriorityChip>(
          find.descendant(
            of: find.ancestor(
              of: titled(name),
              matching: find.byType(ListTile),
            ),
            matching: find.byType(PriorityChip),
          ),
        );

    testWidgets("each action's priority is a chip: filled if set on it, "
        'outlined if inherited', (tester) async {
      await tester.pumpWidget(app(withColors()));
      await tester.pumpAndSettle();
      await toggle(tester, 'Cooking');

      expect(chipOf(tester, 'Cooking').priority, 1);
      expect(chipOf(tester, 'Cooking').own, isTrue);
      expect(chipOf(tester, 'Curry').priority, 3);
      expect(chipOf(tester, 'Curry').own, isTrue);
      // Tofu tikka inherits its priority.
      expect(chipOf(tester, 'Tofu tikka').priority, 1);
      expect(chipOf(tester, 'Tofu tikka').own, isFalse);
    });
  });

  testWidgets('pressing and holding an action reorders actions by dragging', (
    tester,
  ) async {
    final repo = tree();
    await tester.pumpWidget(app(repo));
    await tester.pumpAndSettle();

    await tester.longPress(find.text('Hosting'));
    await tester.pumpAndSettle();
    expect(find.text('Reorder actions'), findsOneWidget);
    expect(find.byTooltip('Add an action or group'), findsNothing);

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
    final saved = [
      for (final action in (await repo.actions()).actions) action.id,
    ];
    expect(saved.indexOf('host'), lessThan(saved.indexOf('cook')));

    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(find.text('Plan'), findsOneWidget);
    expect(find.byTooltip('More for Hosting'), findsOneWidget);
  });

  testWidgets("an action's group is picked from the groups, and shown as "
      'its path', (tester) async {
    final repo = InMemoryActionsRepository([
      const PlanAction(
        id: 'cook',
        name: 'Cooking',
        properties: {'kind': 'group'},
      ),
      const PlanAction(
        id: 'indian',
        name: 'Indian',
        parentId: 'cook',
        properties: {'kind': 'group'},
      ),
      const PlanAction(id: 'tofu', name: 'Tofu tikka', parentId: 'indian'),
      const PlanAction(id: 'host', name: 'Hosting'),
    ]);
    await tester.pumpWidget(app(repo));
    await tester.pumpAndSettle();

    await openDetails(tester, 'Hosting');
    final dialog = find.byType(AlertDialog);
    final label = find.descendant(of: dialog, matching: find.text('parent_id'));
    final row = find.ancestor(of: label, matching: find.byType(PropertyRow));
    await tester.tap(find.descendant(of: row, matching: find.text('(none)')));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(ActionField));
    await tester.pumpAndSettle();
    final picker = find.byType(ActionsPicker);
    // Not itself, nor an action.
    expect(
      find.descendant(of: picker, matching: find.text('Hosting')),
      findsNothing,
    );
    expect(find.text('Tofu tikka'), findsNothing);
    // A group in a group, once its group's opened.
    expect(find.text('Indian'), findsNothing);
    await tester.tap(find.byTooltip('Show 1 inside'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Indian'));
    await tester.pumpAndSettle();
    expect(picker, findsNothing);
    // Picked: its whole path.
    expect(find.text('Cooking › Indian'), findsOneWidget);
    await tester.tap(find.byTooltip('Keep edit'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save 1 change'));
    await tester.pumpAndSettle();
    expect(
      (await repo.actions()).actions.firstWhere((g) => g.id == 'host').parentId,
      'indian',
    );
  });

  testWidgets("an action can't be put under itself or its sub-actions, and can "
      'be made top-level', (tester) async {
    final repo = tree();
    await tester.pumpWidget(app(repo));
    await tester.pumpAndSettle();

    await toggle(tester, 'Cooking');
    await openDetails(tester, 'Tofu tikka');
    final dialog = find.byType(AlertDialog);
    final row = find.ancestor(
      of: find.descendant(of: dialog, matching: find.text('parent_id')),
      matching: find.byType(PropertyRow),
    );
    await tester.tap(
      find.descendant(of: row, matching: find.byType(InkWell)).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byType(ActionField));
    await tester.pumpAndSettle();
    // Only a group: Cooking, its own.
    final picker = find.byType(ActionsPicker);
    for (final action in ['Shelved', 'Oops', 'Old habit', 'Hosting']) {
      expect(
        find.descendant(of: picker, matching: find.text(action)),
        findsNothing,
        reason: action,
      );
    }
    expect(
      find.descendant(of: picker, matching: find.text('Cooking')),
      findsOneWidget,
    );
    // Searched by path; not itself.
    await tester.enterText(
      find.descendant(of: find.byType(ActionsPicker), matching: dialogField),
      'cook',
    );
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byType(ActionsPicker),
        matching: find.text('Tofu tikka'),
      ),
      findsNothing,
    );
    await tester.tap(find.text('None (top-level)'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Keep edit'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save 1 change'));
    await tester.pumpAndSettle();
    expect(
      (await repo.actions()).actions.firstWhere((g) => g.id == 'tofu').parentId,
      isNull,
    );

    await openDetails(tester, 'Cooking');
    await tester.tap(
      find
          .descendant(
            of: find.ancestor(
              of: find.descendant(
                of: find.byType(AlertDialog),
                matching: find.text('parent_id'),
              ),
              matching: find.byType(PropertyRow),
            ),
            matching: find.byType(InkWell),
          )
          .first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byType(ActionField));
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byType(ActionsPicker),
        matching: find.text('Cooking'),
      ),
      findsNothing,
    );
  });

  testWidgets(
    "an action's band is its own color, or the one it inherits, dashed, beside "
    "its ancestors'",
    (tester) async {
      await tester.pumpWidget(
        app(
          InMemoryActionsRepository([
            PlanAction.fromJson({
              'id': 'own',
              'name': 'Own',
              'background_color': '#123456',
              'effective_color': '#123456',
            }),
            PlanAction.fromJson({
              'id': 'kid',
              'name': 'Kid',
              'parent_id': 'own',
              'effective_color': '#123456',
            }),
            PlanAction.fromJson({
              'id': 'idle',
              'name': 'Idle',
              'status': 'proposed',
              'background_color': '#abcdef',
            }),
          ]),
        ),
      );
      await tester.pumpAndSettle();
      await toggle(tester, 'Own');

      const own = ActionBand(color: Color(0xFF123456), dashed: false);
      expect(bandsOf(tester, 'Own').bands, [own]);
      expect(bandsOf(tester, 'Kid').bands, [
        own,
        const ActionBand(color: Color(0xFF123456), dashed: true),
      ]);
      // A proposed action's is grey, and dashed.
      final idle = bandsOf(tester, 'Idle').bands.single;
      expect(idle.dashed, isTrue);
      expect(idle.color, isNot(const Color(0xFFABCDEF)));
    },
  );

  testWidgets('says when there are no actions yet', (tester) async {
    await tester.pumpWidget(app(InMemoryActionsRepository()));
    await tester.pumpAndSettle();
    expect(find.text('No actions yet.\nTap + to add one.'), findsOneWidget);
  });
}

/// Holds each save until the test answers it, or fails it.
class _GatedActionsRepository implements ActionsRepository {
  _GatedActionsRepository(this._inner);

  final InMemoryActionsRepository _inner;

  @override
  bool get reorderable => _inner.reorderable;

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

  /// How many times every action has been fetched.
  var fetches = 0;

  @override
  Future<String?> createAction(Map<String, Object?> fields) async {
    await _gate('create ${fields['name']}');
    return _inner.createAction(fields);
  }

  @override
  Future<void> updateAction(
    PlanAction action,
    Map<String, Object?> changes,
  ) async {
    await _gate('update ${action.id}');
    return _inner.updateAction(action, changes);
  }

  /// While set, fetching every action waits for it.
  Completer<void>? fetchGate;

  @override
  Future<ActionList> actions() async {
    fetches++;
    await fetchGate?.future;
    return _inner.actions();
  }

  @override
  Future<ActionList?> cachedActions() => _inner.cachedActions();

  @override
  Future<ActionList> reorderActions(List<String> ids) =>
      _inner.reorderActions(ids);
}

/// Needs sign-in until [signedIn], then answers with [inner]'s actions, or
/// throws [failure], as a server that can't answer would.
class _SignInActionsRepository extends InMemoryActionsRepository {
  _SignInActionsRepository(this._inner) : super(const []);

  final InMemoryActionsRepository _inner;
  bool signedIn = false;
  Exception? failure;

  @override
  Future<ActionList> actions() async {
    if (!signedIn) throw SignInRequiredException();
    if (failure case final failure?) throw failure;
    return _inner.actions();
  }
}

/// Counts what it's asked for: everyone, or the locations.
class _CountingPeopleRepository extends InMemoryPeopleRepository {
  _CountingPeopleRepository()
    : super(
        locations: const [Location(id: 'home', name: 'Home')],
      );

  final calls = <String>[];

  @override
  Future<PeopleList> people() {
    calls.add('people');
    return super.people();
  }

  @override
  Future<List<Location>> locations() {
    calls.add('locations');
    return super.locations();
  }
}
