import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:time_tracker_client/models/event.dart';
import 'package:time_tracker_client/models/goal.dart';
import 'package:time_tracker_client/screens/goal_screen.dart';
import 'package:time_tracker_client/screens/goals_pane.dart';
import 'package:time_tracker_client/services/event_store.dart';
import 'package:time_tracker_client/services/events_repository.dart';
import 'package:time_tracker_client/services/goals_repository.dart';
import 'package:time_tracker_client/services/plan_memory.dart';
import 'package:time_tracker_client/widgets/goal_tile.dart';
import 'package:time_tracker_client/widgets/html_editor.dart';

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
  }) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    repository = InMemoryGoalsRepository(
      _goals,
      () => DateTime(2026, 10, 17, 9),
    );
    final now = DateTime.now();
    final store = EventStore(repository: InMemoryEventsRepository(events));
    store.putDay(DateTime(now.year, now.month, now.day), events);
    memory = PlanMemory(eventStore: store);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: GoalsPane(repository: repository, memory: memory),
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

  testWidgets('marking a goal done asks what becomes of what is left open', (
    tester,
  ) async {
    await pump(tester);
    await tester.tap(find.text('Learn Rust'));
    await tester.pumpAndSettle();

    // Nothing under it: done at once.
    await tester.tap(find.widgetWithText(OutlinedButton, 'Mark done'));
    await tester.pumpAndSettle();
    expect(
      (await repository.goals()).firstWhere((g) => g.id == 'learn').status,
      'done',
    );
    expect(memory.goals!.firstWhere((g) => g.id == 'learn').closed, isTrue);
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

  testWidgets('selected sub-goals are activated together, each given a '
      'deadline', (tester) async {
    await pump(tester);
    await tester.tap(find.text('Ship the app'));
    await tester.pumpAndSettle();

    await tester.longPress(find.text('Polish'));
    await tester.pump();
    await tester.tap(find.text('Write docs'));
    await tester.pump();
    expect(find.text('2 selected'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, 'Activate'));
    await tester.pumpAndSettle();

    expect(find.text('When are they due?'), findsOneWidget);
    final activate = find.widgetWithText(FilledButton, 'Activate');
    expect(tester.widget<FilledButton>(activate).onPressed, isNull);
    await tester.tap(find.text('End of today').first);
    await tester.tap(find.text("Parent's").last);
    await tester.pump();
    await tester.tap(activate);
    await tester.pumpAndSettle();

    final saved = {for (final g in await repository.goals()) g.id: g};
    expect(saved['polish']!.active, isTrue);
    expect(saved['docs']!.active, isTrue);
    expect(saved['docs']!.deadline, '2026-12-01');
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

    await tester.tap(find.text("Follow its parent's deadline"));
    await tester.pumpAndSettle();
    await tester.tap(find.text('1 week before'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Due Tue, Nov 24'), findsOneWidget);
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
}
