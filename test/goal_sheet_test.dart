import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:time_tracker_client/services/goal_drafts.dart';
import 'package:time_tracker_client/widgets/goal_sheet.dart';

void main() {
  // A Sunday.
  final now = DateTime(2026, 10, 18, 9, 30);

  late List<Map<String, Object?>> kept;
  late GoalDrafts drafts;
  GoalSheetResult? result;

  Future<void> open(WidgetTester tester, {GoalDrafts? withDrafts}) async {
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
}
