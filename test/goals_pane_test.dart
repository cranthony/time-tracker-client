import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:time_tracker_client/models/event.dart';
import 'package:time_tracker_client/models/goal.dart';
import 'package:time_tracker_client/screens/goal_screen.dart';
import 'package:time_tracker_client/screens/goals_pane.dart';
import 'package:time_tracker_client/services/event_store.dart';
import 'package:time_tracker_client/services/events_repository.dart';
import 'package:time_tracker_client/services/goals_repository.dart';
import 'package:time_tracker_client/services/plan_memory.dart';
import 'package:time_tracker_client/widgets/goal_fields.dart';
import 'package:time_tracker_client/widgets/goal_tile.dart';
import 'package:time_tracker_client/widgets/html_editor.dart';
import 'package:time_tracker_client/widgets/priority_chip.dart';

List<Map<String, Object?>> _history(String status) => [
  {'status': status, 'at': '2026-10-01T09:00:00'},
];

Goal _goal(
  String id,
  String title, {
  String? parent,
  String status = 'active',
  String? deadline = '2026-12-01',
  int? minutes,
  bool required = false,
}) => Goal.fromJson({
  'id': id,
  'title': title,
  'parent_id': parent,
  'status': status,
  'deadline': deadline,
  'expected_minutes': minutes,
  'required': required,
  'history': _history(status),
});

final _goals = [
  _goal('ship', 'Ship the app', minutes: 600),
  _goal('pane', 'Write the pane', parent: 'ship', deadline: '2026-11-15'),
  _goal('icon', 'Draw the icon', parent: 'pane', deadline: '2026-11-01'),
  _goal('polish', 'Polish', parent: 'ship', status: 'inactive', deadline: null),
  _goal(
    'docs',
    'Write docs',
    parent: 'ship',
    status: 'inactive',
    deadline: null,
  ),
  _goal('learn', 'Learn Rust', deadline: '2026-11-20'),
  _goal('old', 'Old idea', status: 'obsolete', deadline: null),
];

void main() {
  late InMemoryGoalsRepository repository;
  late PlanMemory memory;

  Future<void> pump(
    WidgetTester tester, {
    List<Event> events = const [],
    VoidCallback? onQuickAdd,
    List<Goal>? goals,
    Size size = const Size(800, 1600),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    repository = InMemoryGoalsRepository(
      goals ?? _goals,
      () => DateTime(2026, 10, 17, 9),
    );
    final now = DateTime.now();
    final store = EventStore(repository: InMemoryEventsRepository(events));
    store.putDay(DateTime(now.year, now.month, now.day), events);
    memory = PlanMemory(eventStore: store);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: GoalsPane(
            repository: repository,
            memory: memory,
            onQuickAdd: onQuickAdd,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('lists the open top-level goals, soonest due first', (
    tester,
  ) async {
    await pump(tester);

    final titles = [
      for (final tile in tester.widgetList<GoalTile>(find.byType(GoalTile)))
        tile.goal.title,
    ];
    expect(titles, ['Learn Rust', 'Ship the app']);
    expect(find.text('Write the pane'), findsNothing);
  });

  testWidgets('has no round "+" without a quick New goal sheet', (
    tester,
  ) async {
    await pump(tester);
    expect(find.byType(FloatingActionButton), findsNothing);
  });

  testWidgets('the round "+" opens the quick New goal sheet, given one', (
    tester,
  ) async {
    var opened = 0;
    await pump(tester, onQuickAdd: () => opened++);
    await tester.tap(find.byTooltip('Add goal'));
    expect(opened, 1);
  });

  testWidgets('the last goal scrolls clear of the round "+"', (tester) async {
    await pump(tester, onQuickAdd: () {});
    // Too short for every goal: the list scrolls.
    tester.view.physicalSize = const Size(400, 260);
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ReorderableListView), const Offset(0, -2000));
    await tester.pumpAndSettle();

    final last = tester.getRect(find.byType(GoalTile).last);
    final plus = tester.getRect(find.byType(FloatingActionButton));
    expect(last.bottom, lessThanOrEqualTo(plus.top));
  });

  testWidgets('shows the time spent toward a goal against what it expects', (
    tester,
  ) async {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day, 9);
    await pump(
      tester,
      events: [
        Event(
          id: 'e1',
          start: start,
          end: start.add(const Duration(hours: 2)),
          properties: {
            'goals': [
              {'goal_id': 'icon', 'minutes': 90},
              {'goal_id': 'ship', 'minutes': 30},
            ],
          },
        ),
      ],
    );

    expect(find.textContaining('2h of 10h'), findsOneWidget);
  });

  testWidgets("a goal's page has its path, its depth and what's under it", (
    tester,
  ) async {
    await pump(tester);

    await tester.tap(find.text('Ship the app'));
    await tester.pumpAndSettle();
    expect(find.byType(GoalScreen), findsOneWidget);
    expect(find.text('Write the pane'), findsOneWidget);
    expect(find.text('Polish'), findsOneWidget);
    expect(find.text('Draw the icon'), findsNothing);

    await tester.tap(find.text('Write the pane'));
    await tester.pumpAndSettle();
    expect(find.text('Ship the app'), findsOneWidget); // Its path.
    final bars = tester.widget<DepthBars>(find.byType(DepthBars).last);
    expect(bars.depth, 1);
    expect(find.text('Draw the icon'), findsOneWidget);
  });

  testWidgets("a goal's page has its title in full, above its status", (
    tester,
  ) async {
    const title =
        'Sign up for the community garden plot before the spring waitlist '
        'closes';
    // A phone's width, where the bar cuts the title short.
    await pump(
      tester,
      goals: [_goal('garden', title)],
      size: const Size(360, 1600),
    );
    await tester.tap(find.text(title));
    await tester.pumpAndSettle();
    expect(find.byType(GoalScreen), findsOneWidget);

    final field = find.ancestor(
      of: find.text('Title'),
      matching: find.byType(GoalField),
    );
    final text = find.descendant(of: field, matching: find.text(title));
    expect(text, findsOneWidget);
    final paragraph = tester.renderObject<RenderParagraph>(text);
    expect(paragraph.didExceedMaxLines, isFalse);
    // Wrapped over several lines, not cut to one.
    expect(tester.getSize(text).height, greaterThan(40));
    expect(
      tester.getTopLeft(find.text('Title')).dy,
      lessThan(tester.getTopLeft(find.text('Status')).dy),
    );
  });

  testWidgets('marking a goal done asks what becomes of what is left open', (
    tester,
  ) async {
    await pump(tester);
    await tester.tap(find.text('Learn Rust'));
    await tester.pumpAndSettle();

    // Nothing under it: just a note asked for, and done without one.
    await tester.tap(find.widgetWithText(OutlinedButton, 'Mark done'));
    await tester.pumpAndSettle();
    expect(
      find.text("What becomes of what's still open under it?"),
      findsNothing,
    );
    expect(find.text('Mark Learn Rust done'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Mark done'));
    await tester.pumpAndSettle();
    final learn = (await repository.goals()).firstWhere((g) => g.id == 'learn');
    expect(learn.status, 'done');
    expect(learn.history.last.note, isNull);
    expect(memory.goals!.firstWhere((g) => g.id == 'learn').closed, isTrue);
  });

  testWidgets('marking a goal done keeps the note left with it, shown on its '
      'page and changed from its history', (tester) async {
    await pump(tester);
    await tester.tap(find.text('Learn Rust'));
    await tester.pumpAndSettle();

    // Enter in the note marks it done with the note.
    await tester.tap(find.widgetWithText(OutlinedButton, 'Mark done'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), ' Read the book through ');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    var learn = (await repository.goals()).firstWhere((g) => g.id == 'learn');
    expect(learn.status, 'done');
    expect(learn.history.last.note, 'Read the book through');
    // With when it was done, and on its history entry.
    expect(find.textContaining('Read the book through'), findsNWidgets(2));

    // The history entry's note can be changed, or taken off.
    await tester.tap(find.byTooltip('Change the note'));
    await tester.pumpAndSettle();
    expect(find.text('Note on “Learn Rust” done'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'Skimmed it');
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();
    learn = (await repository.goals()).firstWhere((g) => g.id == 'learn');
    expect(learn.history.last.note, 'Skimmed it');
    expect(learn.history.map((c) => c.status), ['active', 'done']);
    expect(find.textContaining('Skimmed it'), findsNWidgets(2));

    await tester.tap(find.byTooltip('Change the note'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '');
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();
    learn = (await repository.goals()).firstWhere((g) => g.id == 'learn');
    expect(learn.history.last.note, isNull);
    expect(find.textContaining('Skimmed it'), findsNothing);
    expect(find.byTooltip('Add a note'), findsNWidgets(2));
  });

  testWidgets('the note goes with what becomes of the open sub-goals', (
    tester,
  ) async {
    await pump(tester);
    await tester.tap(find.text('Ship the app'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(OutlinedButton, 'Mark missed'));
    await tester.pumpAndSettle();
    expect(
      find.text("What becomes of what's still open under it?"),
      findsOneWidget,
    );
    await tester.enterText(find.byType(TextField), 'Ran out of time');
    await tester.tap(find.widgetWithText(FilledButton, 'Mark missed'));
    await tester.pumpAndSettle();

    final saved = {for (final g in await repository.goals()) g.id: g};
    expect(saved['ship']!.status, 'missed');
    expect(saved['ship']!.history.last.note, 'Ran out of time');
    // Its sub-goals, closed with it, get none.
    expect(saved['pane']!.status, 'missed');
    expect(saved['pane']!.history.last.note, isNull);
  });

  testWidgets('closing a goal closes or moves its open sub-goals first', (
    tester,
  ) async {
    await pump(tester);
    await tester.tap(find.text('Ship the app'));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(PopupMenuButton<String>).last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Mark obsolete').last);
    await tester.pumpAndSettle();
    expect(
      find.text("What becomes of what's still open under it?"),
      findsOneWidget,
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Mark obsolete'));
    await tester.pumpAndSettle();

    final saved = {for (final g in await repository.goals()) g.id: g.status};
    expect(saved, containsPair('ship', 'obsolete'));
    expect(saved, containsPair('pane', 'obsolete'));
    expect(saved, containsPair('icon', 'obsolete'));
    expect(saved, containsPair('polish', 'obsolete'));
  });

  testWidgets('a goal marked missed has its open sub-goals missed too', (
    tester,
  ) async {
    await pump(tester);
    await tester.tap(find.text('Ship the app'));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(OutlinedButton, 'Mark missed'));
    await tester.pumpAndSettle();
    expect(
      find.text("What becomes of what's still open under it?"),
      findsOneWidget,
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Mark missed'));
    await tester.pumpAndSettle();

    final saved = {for (final g in await repository.goals()) g.id: g.status};
    expect(saved, containsPair('ship', 'missed'));
    expect(saved, containsPair('pane', 'missed'));
    expect(saved, containsPair('polish', 'missed'));
    expect(memory.goals!.firstWhere((g) => g.id == 'ship').closed, isTrue);
  });

  testWidgets('the HTML editor previews to the right, and keeps the cursor '
      'for coming back', (tester) async {
    String? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async => result = await showHtmlEditor(
              context,
              title: 'Description',
              text: '<p>Hello <b>there</b></p>',
            ),
            child: const Text('Open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    final field = tester.widget<TextField>(find.byType(TextField));
    field.controller!.selection = const TextSelection(
      baseOffset: 3,
      extentOffset: 8,
    );
    await tester.tap(find.text('Preview'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Hello'), findsWidgets);

    field.controller!.selection = const TextSelection.collapsed(offset: 0);
    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();
    expect(
      field.controller!.selection,
      const TextSelection(baseOffset: 3, extentOffset: 8),
    );

    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(result, '<p>Hello <b>there</b></p>');
  });

  testWidgets("a sub-goal's deadline can follow its parent's, a week before "
      'it', (tester) async {
    await pump(tester);
    await tester.tap(find.text('Ship the app'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Write the pane'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Edit').first);
    await tester.pumpAndSettle();

    await tester.tap(find.text("Before its parent's"));
    await tester.pumpAndSettle();
    await tester.tap(find.text('1 week before'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Tue, Nov 24 · 1w before'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    var saved = {for (final g in await repository.goals()) g.id: g};
    expect(saved['pane']!.deadline, '2026-11-24');
    expect(saved['pane']!.deadlineOffsetMinutes, 7 * 24 * 60);
    await repository.updateGoal('ship', {'deadline': '2026-12-10'});
    saved = {for (final g in await repository.goals()) g.id: g};
    expect(saved['pane']!.deadline, '2026-12-03');
  });

  testWidgets("a goal's status is changed on its edit page, with what that "
      'takes', (tester) async {
    await pump(tester);
    await tester.tap(find.text('Ship the app'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Edit').first);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Active').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Obsolete').last);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();
    expect(
      find.text("What becomes of what's still open under it?"),
      findsOneWidget,
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Mark obsolete'));
    await tester.pumpAndSettle();

    final saved = {for (final g in await repository.goals()) g.id: g.status};
    expect(saved, containsPair('ship', 'obsolete'));
    expect(saved, containsPair('pane', 'obsolete'));
  });

  testWidgets('a priority set on the edit page lists the goal first, '
      'its chip filled, and what is under it inherits it', (tester) async {
    await pump(tester);
    List<(String, int?, bool)> chips() => [
      for (final tile in tester.widgetList<GoalTile>(find.byType(GoalTile)))
        (
          tile.goal.title,
          tester
              .widget<PriorityChip>(
                find.descendant(
                  of: find.byWidget(tile),
                  matching: find.byType(PriorityChip),
                ),
              )
              .priority,
          tester
              .widget<PriorityChip>(
                find.descendant(
                  of: find.byWidget(tile),
                  matching: find.byType(PriorityChip),
                ),
              )
              .own,
        ),
    ];
    expect(chips(), [('Learn Rust', 3, false), ('Ship the app', 3, false)]);

    await tester.tap(find.byTooltip('Edit Ship the app'));
    await tester.pumpAndSettle();
    expect(find.text('None (P3)'), findsOneWidget);
    await tester.tap(find.text('P1'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    expect(
      {for (final g in await repository.goals()) g.id: g.priority}['ship'],
      1,
    );
    expect(chips(), [('Ship the app', 1, true), ('Learn Rust', 3, false)]);

    await tester.tap(find.text('Ship the app'));
    await tester.pumpAndSettle();
    expect(chips().first, ('Write the pane', 1, false));
    await tester.tap(find.byTooltip('Edit Write the pane'));
    await tester.pumpAndSettle();
    expect(find.text('Inherit (P1)'), findsOneWidget);
  });
}
