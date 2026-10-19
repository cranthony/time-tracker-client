import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:time_tracker_client/models/goal.dart';
import 'package:time_tracker_client/services/goal_drafts.dart';
import 'package:time_tracker_client/widgets/goal_sheet.dart';

Goal _goal(String id, {String? parent, String status = 'active'}) =>
    Goal.fromJson({
      'id': id,
      'title': id,
      'parent_id': parent,
      'status': status,
      'deadline': '2026-12-01',
      'history': [
        {'status': status, 'at': '2026-10-01T09:00:00'},
      ],
    });

void main() {
  // A Sunday.
  final now = DateTime(2026, 10, 18, 9, 30);

  late List<Map<String, Object?>> kept;
  late GoalDrafts drafts;
  GoalSheetResult? result;

  Future<void> open(
    WidgetTester tester, {
    GoalDrafts? withDrafts,
    List<Goal> goals = const [],
  }) async {
    kept = [];
    drafts = withDrafts ?? GoalDrafts.inMemory();
    result = null;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async => result = await showAddGoalSheet(
                context,
                keep: (fields) async => kept.add(fields),
                goals: goals,
                drafts: drafts,
                now: () => now,
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
  }

  FilledButton add(WidgetTester tester) =>
      tester.widget(find.widgetWithText(FilledButton, 'Add'));

  testWidgets('starts due today, shown with its day of the week', (
    tester,
  ) async {
    await open(tester);
    expect(find.text('New goal'), findsOneWidget);
    expect(find.text('Sun, Oct 18'), findsOneWidget);
    // Nothing to add yet.
    expect(add(tester).onPressed, isNull);
  });

  testWidgets('+ and - move it a day, not before today; Today goes back', (
    tester,
  ) async {
    await open(tester);
    final earlier = find.widgetWithIcon(IconButton, Icons.remove);
    expect(tester.widget<IconButton>(earlier).onPressed, isNull);

    await tester.tap(find.byTooltip('A day later'));
    await tester.tap(find.byTooltip('A day later'));
    await tester.tap(find.byTooltip('A day later'));
    await tester.pump();
    expect(find.text('Wed, Oct 21'), findsOneWidget);
    await tester.tap(earlier);
    await tester.pump();
    expect(find.text('Tue, Oct 20'), findsOneWidget);

    await tester.tap(find.text('Today'));
    await tester.pump();
    expect(find.text('Sun, Oct 18'), findsOneWidget);
  });

  testWidgets('Add keeps an active goal due by the end of the day', (
    tester,
  ) async {
    await open(tester);
    await tester.enterText(find.byType(TextField), '  Ship it ');
    await tester.tap(find.byTooltip('A day later'));
    await tester.pump();
    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();

    expect(kept.single, {
      'title': 'Ship it',
      'deadline': '2026-10-19',
      'status': 'active',
    });
    expect(result, isA<AddedGoal>());
    expect(find.text('New goal'), findsNothing);
    expect(drafts.draft, isNull);
  });

  testWidgets("More closes it, giving what's typed", (tester) async {
    await open(tester);
    await tester.enterText(find.byType(TextField), 'Ship it');
    await tester.tap(find.byTooltip('A day later'));
    await tester.pump();
    await tester.tap(find.text('More'));
    await tester.pumpAndSettle();

    final more = result as MoreGoal;
    expect(more.title, 'Ship it');
    expect(more.deadline, '2026-10-19');
    expect(kept, isEmpty);
    expect(drafts.draft?.title, 'Ship it');
  });

  testWidgets('its parent is picked searching for its title, by any word, '
      'selected to type over', (tester) async {
    final goals = [
      _goal('Health'),
      _goal('Run a marathon', parent: 'Health'),
      _goal('Someday', status: 'inactive'),
    ];
    await open(tester, goals: goals);
    await tester.enterText(find.byType(TextField), 'Run 10k');
    await tester.pump();
    expect(find.text('Top level'), findsOneWidget);
    await tester.tap(find.text('Top level'));
    await tester.pumpAndSettle();

    final search = tester.widget<TextField>(
      find.widgetWithText(TextField, 'Run 10k').last,
    );
    expect(search.controller!.selection.start, 0);
    expect(search.controller!.selection.end, 'Run 10k'.length);
    expect(search.focusNode!.hasFocus, isTrue);
    expect(
      tester
          .widget<FilterChip>(find.widgetWithText(FilterChip, 'Any'))
          .selected,
      isTrue,
    );
    // Only active goals: the new one is active.
    expect(find.text('Someday'), findsNothing);
    await tester.tap(find.text('Run a marathon'));
    await tester.pumpAndSettle();
    expect(find.text('Under Health › Run a marathon'), findsOneWidget);
    expect(drafts.draft?.parentId, 'Run a marathon');

    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();
    expect(kept.single['parent_id'], 'Run a marathon');
  });

  testWidgets('More gives its parent, description and definition of done', (
    tester,
  ) async {
    await open(tester, goals: [_goal('Running')]);
    await tester.enterText(find.byType(TextField), 'Run 10k');
    await tester.tap(find.text('Top level'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Running'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Add description'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'Around the lake');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('Around the lake'), findsOneWidget);
    expect(drafts.draft?.description, 'Around the lake');

    await tester.tap(find.text('Add definition of done'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'Under an hour');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('More'));
    await tester.pumpAndSettle();
    final more = result as MoreGoal;
    expect(more.parentId, 'Running');
    expect(more.description, 'Around the lake');
    expect(more.definitionOfDone, 'Under an hour');
  });

  testWidgets('Add keeps its description and definition of done', (
    tester,
  ) async {
    final withDraft = GoalDrafts.inMemory();
    await withDraft.put(
      GoalDraft(
        title: 'Run 10k',
        day: now,
        description: 'Around the lake',
        definitionOfDone: 'Under an hour',
        parentId: 'Gone',
      ),
    );
    await open(tester, withDrafts: withDraft);
    // Its parent's gone: it's at the top level.
    expect(find.text('Top level'), findsOneWidget);
    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();
    expect(kept.single, {
      'title': 'Run 10k',
      'deadline': '2026-10-18',
      'status': 'active',
      'description': 'Around the lake',
      'definition_of_done': 'Under an hour',
    });
  });

  testWidgets("what's typed is kept as a draft, which the next sheet "
      'carries on with, or its trash can throws away', (tester) async {
    await open(tester);
    await tester.enterText(find.byType(TextField), 'Ship it');
    await tester.tap(find.byTooltip('A day later'));
    await tester.pump();
    expect(drafts.draft?.title, 'Ship it');
    expect(drafts.draft?.day, DateTime(2026, 10, 19));

    // Dismissed, then opened again.
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.text('Ship it'), findsOneWidget);
    expect(find.text('Mon, Oct 19'), findsOneWidget);

    await tester.tap(find.byTooltip('Discard draft'));
    await tester.pumpAndSettle();
    expect(find.text('New goal'), findsNothing);
    expect(drafts.draft, isNull);
  });

  testWidgets('a draft from days ago is due today at the earliest', (
    tester,
  ) async {
    final old = GoalDrafts.inMemory();
    await old.put(GoalDraft(title: 'Old', day: DateTime(2026, 10, 1)));
    await open(tester, withDrafts: old);
    expect(find.text('Old'), findsOneWidget);
    expect(find.text('Sun, Oct 18'), findsOneWidget);
  });

  testWidgets('a failed keep stays open, saying so, to try again', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showAddGoalSheet(
                context,
                keep: (_) async => throw Exception('disk full'),
                now: () => now,
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Ship it');
    await tester.pump();
    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();
    expect(find.textContaining("Couldn't add the goal"), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
  });

  testWidgets('says when its field has focus, for the keyboard', (
    tester,
  ) async {
    var focused = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showAddGoalSheet(
                context,
                keep: (_) async {},
                now: () => now,
                onFieldFocused: () => focused++,
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(focused, 1);
  });

  testWidgets('on a phone, the buttons go under the date, at the right', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await open(tester);
    await tester.enterText(find.byType(TextField), 'Ship it');
    await tester.pump();

    // The test font is wider than any real one, so the date's controls
    // themselves wrap here; on a phone they keep to one line.
    final later = find.byTooltip('A day later');
    // The buttons under the date, at the right.
    final add = find.widgetWithText(FilledButton, 'Add');
    expect(
      tester.getTopLeft(add).dy,
      greaterThan(tester.getBottomLeft(later).dy),
    );
    expect(tester.getTopRight(add).dx, closeTo(320 - 16, 1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('on a wide screen, it is all one line', (tester) async {
    await open(tester);
    final add = tester.getCenter(find.text('Add')).dy;
    expect(tester.getCenter(find.text('Today')).dy, closeTo(add, 4));
    expect(tester.takeException(), isNull);
  });
}
