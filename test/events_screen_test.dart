import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:time_tracker_client/outbox/goal_outbox.dart';
import 'package:time_tracker_client/models/event.dart';
import 'package:time_tracker_client/models/goal.dart';
import 'package:time_tracker_client/models/note.dart';
import 'package:time_tracker_client/models/recurrence.dart';
import 'package:time_tracker_client/models/repeat.dart';
import 'package:time_tracker_client/outbox/note_outbox.dart';
import 'package:time_tracker_client/outbox/outbox_store.dart';
import 'package:time_tracker_client/screens/events_screen.dart';
import 'package:time_tracker_client/screens/home_screen.dart';
import 'package:time_tracker_client/services/event_store.dart';
import 'package:time_tracker_client/services/events_repository.dart';
import 'package:time_tracker_client/services/goals_repository.dart';
import 'package:time_tracker_client/services/mcp_client.dart';
import 'package:time_tracker_client/services/notes_repository.dart';
import 'package:time_tracker_client/services/plan_memory.dart';
import 'package:time_tracker_client/widgets/day_timeline.dart';
import 'package:time_tracker_client/widgets/durations.dart';
import 'package:time_tracker_client/widgets/event_summary_dialog.dart';

void main() {
  final now = DateTime(2026, 9, 30, 12);
  DateTime at(int day, int hour, [int minute = 0]) =>
      DateTime(2026, 9, day, hour, minute);

  Widget app(
    EventsRepository repo, {
    Future<void> Function()? onSignIn,
    GoalsRepository? goals,
  }) => MaterialApp(
    home: EventsScreen(
      repository: repo,
      serverLabel: 'offline demo',
      goalsRepository: goals,
      onSignIn: onSignIn,
      clock: () => now,
    ),
  );

  test('Event.fromJson keeps every property the server sent', () {
    final event = Event.fromJson({
      'id': 'e1',
      'summary': 'Sleep',
      'start': '2026-09-30T06:19:15Z',
      'end': '2026-09-30T13:45:00Z',
      'is_cancelled': false,
      'event_label_id': 'label-1',
    });
    expect(event.summary, 'Sleep');
    expect(event.start, DateTime.utc(2026, 9, 30, 6, 19, 15));
    expect(event.end, DateTime.utc(2026, 9, 30, 13, 45));
    expect(event.isCancelled, isFalse);
    expect(event.properties['event_label_id'], 'label-1');
  });

  testWidgets("shares the app's events: shows a day it has at once, and "
      'puts in each day it loads', (tester) async {
    final store =
        EventStore(
          repository: InMemoryEventsRepository(),
          clock: () => now,
        )..putDay(at(30, 0), [
          Event(id: 'kept', start: at(30, 8), end: at(30, 9), summary: 'Walk'),
        ]);
    final repo = _SlowRepository(
      [
        Event(
          id: 'lunch',
          start: at(30, 15),
          end: at(30, 16),
          summary: 'Lunch',
        ),
        Event(
          id: 'dinner',
          start: at(29, 18),
          end: at(29, 19),
          summary: 'Dinner',
        ),
      ],
      slow: {at(30, 0)},
    );
    await tester.pumpWidget(
      MaterialApp(
        home: EventsScreen(
          repository: repo,
          serverLabel: 'offline demo',
          memory: PlanMemory(eventStore: store),
          clock: () => now,
        ),
      ),
    );
    await tester.pump();

    // What the app had, while it's asked for again.
    expect(find.text('Walk'), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(find.text('Lunch'), findsOneWidget);
    expect(find.text('Walk'), findsNothing);
    expect(store.day(at(30, 0))?.map((e) => e.id), ['lunch']);
    // The days either side, loaded in the background, too.
    expect(store.day(at(29, 0))?.map((e) => e.id), ['dinner']);
  });

  testWidgets('shows today\'s events, and steps between days', (tester) async {
    final repo = InMemoryEventsRepository([
      Event(start: at(30, 15), end: at(30, 16), summary: 'Lunch'),
      Event(start: at(30, 9), end: at(30, 10, 30), summary: 'Work'),
      Event(start: at(29, 23), end: at(30, 7), summary: 'Sleep'),
      Event(start: at(29, 18), end: at(29, 19), summary: 'Dinner'),
    ]);
    await tester.pumpWidget(app(repo));
    await tester.pumpAndSettle();

    expect(find.text('Today'), findsOneWidget);
    // Down the timeline, by start time; one that began the day before
    // from the top.
    double top(String summary) => tester.getTopLeft(find.text(summary)).dy;
    expect(top('Sleep'), lessThan(top('Work')));
    expect(top('Work'), lessThan(top('Lunch')));
    expect(find.bySemanticsLabel('Sleep, 11:00 PM to 7:00 AM'), findsOneWidget);
    expect(find.bySemanticsLabel('Work, 9:00 AM to 10:30 AM'), findsOneWidget);
    expect(find.text('Dinner'), findsNothing);

    await tester.tap(find.byTooltip('Previous day'));
    await tester.pumpAndSettle();
    expect(find.text('Yesterday'), findsOneWidget);
    expect(find.text('Dinner'), findsOneWidget);
    expect(find.text('Sleep'), findsOneWidget);
    expect(find.bySemanticsLabel('Dinner, 6:00 PM to 7:00 PM'), findsOneWidget);
    expect(find.text('Lunch'), findsNothing);

    await tester.tap(find.byTooltip('Next day'));
    await tester.tap(find.byTooltip('Next day'));
    await tester.pumpAndSettle();
    expect(find.text('Lunch'), findsNothing);
    // Nothing that day: its empty timeline, to tap to add one.
    expect(find.text('No events.\nTap a time to add one.'), findsOneWidget);
  });

  testWidgets('swiping left or right steps a day', (tester) async {
    final repo = InMemoryEventsRepository([
      Event(start: at(30, 11), end: at(30, 13), summary: 'Today'),
      Event(start: at(29, 11), end: at(29, 13), summary: 'Before'),
    ]);
    await tester.pumpWidget(app(repo));
    await tester.pumpAndSettle();

    await tester.fling(find.byType(ListView), const Offset(300, 0), 1000);
    await tester.pumpAndSettle();
    expect(find.text('Yesterday'), findsOneWidget);
    expect(find.text('Before'), findsOneWidget);

    await tester.fling(find.byType(ListView), const Offset(-300, 0), 1000);
    await tester.pumpAndSettle();
    expect(find.text('Before'), findsNothing);
    expect(find.text('Today'), findsWidgets);
  });

  testWidgets("the day's summary folds away to \"Show summary\", and back", (
    tester,
  ) async {
    final repo = InMemoryEventsRepository([
      Event(start: at(30, 11), end: at(30, 13), summary: 'Today'),
    ]);
    await tester.pumpWidget(app(repo));
    await tester.pumpAndSettle();
    expect(find.text('Priorities'), findsOneWidget);

    await tester.tap(find.byTooltip('Hide summary'));
    await tester.pumpAndSettle();
    expect(find.text('Priorities'), findsNothing);
    expect(find.text('Show summary'), findsOneWidget);

    await tester.tap(find.text('Show summary'));
    await tester.pumpAndSettle();
    expect(find.text('Priorities'), findsOneWidget);
    expect(find.text('Show summary'), findsNothing);
  });

  testWidgets('the days either side are loaded, and slide in with a drag', (
    tester,
  ) async {
    final repo = InMemoryEventsRepository([
      Event(start: at(30, 11), end: at(30, 13), summary: 'Today'),
      Event(start: at(29, 11), end: at(29, 13), summary: 'Before'),
    ]);
    await tester.pumpWidget(app(repo));
    await tester.pumpAndSettle();

    final axis = tester.getRect(find.byType(TimelineAxis));
    final todays = find.descendant(
      of: find.byType(PageView),
      matching: find.text('Today'),
    );
    final today = tester.getRect(todays);

    // Part-way through a drag to the right, the day before is already
    // there beside today, scrolled to the same time of day; the times
    // down the side stay still.
    final drag = await tester.startGesture(
      tester.getCenter(find.byType(ListView)),
    );
    await drag.moveBy(const Offset(30, 0));
    await drag.moveBy(const Offset(200, 0));
    await tester.pump();
    expect(tester.getRect(find.byType(TimelineAxis)), axis);
    expect(tester.getRect(todays).left, greaterThan(today.left));
    expect(find.text('Before'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(tester.getTopLeft(find.text('Before')).dy, today.top);
    await drag.moveBy(const Offset(300, 0));
    await drag.up();
    await tester.pumpAndSettle();
    expect(find.text('Yesterday'), findsOneWidget);
    expect(find.text('Before'), findsOneWidget);
  });

  testWidgets('swiping keeps the time of day, past days still loading or '
      'with no events', (tester) async {
    final repo = _SlowRepository(
      [
        Event(start: at(30, 18), end: at(30, 19), summary: 'Tea'),
        Event(start: at(26, 18), end: at(26, 19), summary: 'Dinner'),
      ],
      slow: {DateTime(2026, 9, 28), DateTime(2026, 9, 27)},
    );
    await tester.pumpWidget(app(repo));
    await tester.pumpAndSettle();
    // Opened on now, noon; down to the evening.
    await tester.drag(find.byType(ListView), const Offset(0, -500));
    await tester.pumpAndSettle();
    final y = tester.getTopLeft(find.text('Tea')).dy;

    // Back a day, with no events; on to one still loading; on to one
    // with no events, then to one with an event at the same time.
    for (var i = 0; i < 4; i++) {
      await tester.fling(find.byType(ListView), const Offset(300, 0), 1000);
      await tester.pumpAndSettle();
    }
    await tester.pumpAndSettle(const Duration(seconds: 1));
    expect(find.textContaining('Sep 26'), findsOneWidget);
    expect(tester.getTopLeft(find.text('Dinner')).dy, moreOrLessEquals(y));

    for (var i = 0; i < 4; i++) {
      await tester.fling(find.byType(ListView), const Offset(-300, 0), 1000);
      await tester.pumpAndSettle();
    }
    await tester.pumpAndSettle(const Duration(seconds: 1));
    expect(find.text('Today'), findsOneWidget);
    expect(tester.getTopLeft(find.text('Tea')).dy, moreOrLessEquals(y));
  });

  testWidgets('pinching zooms, and doesn\'t step a day', (tester) async {
    final repo = InMemoryEventsRepository([
      Event(start: at(30, 11), end: at(30, 13), summary: 'Work'),
    ]);
    await tester.pumpWidget(app(repo));
    await tester.pumpAndSettle();
    double height() => tester
        .getSize(
          find
              .ancestor(of: find.text('Work'), matching: find.byType(InkWell))
              .first,
        )
        .height;
    final before = height();

    final center = tester.getCenter(find.byType(ListView));
    final a = await tester.startGesture(center - const Offset(40, 0));
    final b = await tester.startGesture(center + const Offset(40, 0));
    for (var i = 1; i <= 8; i++) {
      await a.moveTo(center - Offset(40.0 + 10 * i, 0));
      await b.moveTo(center + Offset(40.0 + 10 * i, 0));
      await tester.pump();
    }
    await a.up();
    await b.up();
    await tester.pumpAndSettle();

    // From 80 apart to 240: three times as tall.
    expect(height(), moreOrLessEquals(before * 3, epsilon: 1));
    expect(find.text('Today'), findsOneWidget);
  });

  testWidgets("an event's Details show all its properties", (tester) async {
    final repo = InMemoryEventsRepository([
      Event.fromJson({
        'id': 'e1',
        'summary': 'Work',
        'start': localIsoTimestamp(at(30, 9)),
        'end': localIsoTimestamp(at(30, 10, 30)),
        'description': 'Deep work\nNo email',
        'location': null,
        'min_duration': 'PT1H',
        'priority': 1,
        'is_cancelled': false,
        'is_end_of_day_sleep': true,
      }),
    ]);
    await tester.pumpWidget(app(repo));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Work'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Work'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Details'));
    await tester.pumpAndSettle();
    final dialog = find.byType(AlertDialog);
    expect(dialog, findsOneWidget);
    String? valueOf(String key) {
      final label = find.descendant(of: dialog, matching: find.text(key));
      final column = find.ancestor(of: label, matching: find.byType(Column));
      final value = find.descendant(
        of: column.first,
        matching: find.byWidgetPredicate(
          (w) => w is SelectableText || (w is Text && w.data != key),
        ),
      );
      return switch (tester.widget(value.first)) {
        SelectableText(:final data) => data,
        Text(:final data) => data,
        _ => null,
      };
    }

    expect(valueOf('id'), 'e1');
    expect(valueOf('summary'), 'Work');
    expect(valueOf('start'), 'Wednesday, September 30, 2026, 9:00 AM');
    expect(valueOf('end'), 'Wednesday, September 30, 2026, 10:30 AM');
    expect(valueOf('description'), 'Deep work\nNo email');
    expect(valueOf('location'), '(none)');
    expect(valueOf('min_duration'), '1h');
    expect(valueOf('priority'), '1');
    expect(valueOf('is_cancelled'), 'false');
    // Ones the app doesn't know about yet too.
    expect(valueOf('is_end_of_day_sleep'), 'true');

    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    expect(dialog, findsNothing);
  });

  group("editing in an event's Details", () {
    Event work() => Event.fromJson({
      'id': 'e1',
      'summary': 'Work',
      'start': localIsoTimestamp(at(30, 9)),
      'end': localIsoTimestamp(at(30, 10, 30)),
      'description': 'Deep work',
      'location': null,
      'action_ids': ['g1'],
      'min_duration': 'PT1H',
      'priority': 2,
      'is_fixed_time': false,
      'is_cancelled': false,
    });

    Future<void> openWork(WidgetTester tester, EventsRepository repo) async {
      await tester.pumpWidget(
        app(
          repo,
          goals: InMemoryGoalsRepository([
            const Goal(id: 'g1', name: 'Deep focus', priority: 1),
            const Goal(id: 'g2', name: 'Exercise', priority: 2),
            const Goal(id: 'g3', name: 'Old', status: 'inactive'),
          ]),
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Work').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Work').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Details'));
      await tester.pumpAndSettle();
    }

    Finder inDialog(Finder f) =>
        find.descendant(of: find.byType(AlertDialog), matching: f);

    /// Taps [value], scrolling the dialog to it first.
    Future<void> edit(WidgetTester tester, Finder value) async {
      await tester.ensureVisible(value);
      await tester.pumpAndSettle();
      await tester.tap(value);
      await tester.pumpAndSettle();
    }

    testWidgets('tapping a value edits it; Save sends the changes', (
      tester,
    ) async {
      final repo = _RecordingRepository([work()]);
      await openWork(tester, repo);

      await edit(tester, inDialog(find.text('Deep work')));
      await tester.enterText(find.byType(TextField), 'Invoice export');
      await tester.tap(find.byTooltip('Keep edit'));
      await tester.pumpAndSettle();
      // The new value, the old one struck through, and a count.
      expect(inDialog(find.text('Invoice export')), findsOneWidget);
      expect(inDialog(find.text('Deep work')), findsOneWidget);
      expect(find.text('Save 1 change'), findsOneWidget);

      // The summary's row, not the title.
      await edit(tester, inDialog(find.text('Work')).last);
      await tester.enterText(find.byType(TextField), 'Admin');
      await tester.tap(find.byTooltip('Keep edit'));
      await tester.pumpAndSettle();
      expect(find.text('Save 2 changes'), findsOneWidget);

      await tester.tap(find.text('Save 2 changes'));
      await tester.pumpAndSettle();
      expect(repo.saved, [
        {'description': 'Invoice export', 'summary': 'Admin'},
      ]);
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.text('Saved.'), findsOneWidget);
      expect(find.text('Admin'), findsOneWidget);
    });

    testWidgets('shows the server\'s error and keeps the edits', (
      tester,
    ) async {
      final repo = _RecordingRepository([work()])
        ..error = McpException(
          'Tool update_event failed: Overlaps a fixed-time event',
        );
      await openWork(tester, repo);

      await edit(tester, inDialog(find.text('2')));
      await tester.enterText(find.byType(TextField), '1');
      await tester.tap(find.byTooltip('Keep edit'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save 1 change'));
      await tester.pumpAndSettle();

      expect(
        find.text(
          "Couldn't save. Tool update_event failed: "
          'Overlaps a fixed-time event',
        ),
        findsOneWidget,
      );
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.text('Save 1 change'), findsOneWidget);

      // Fixed on the server: trying again works.
      repo.error = null;
      await tester.tap(find.text('Save 1 change'));
      await tester.pumpAndSettle();
      expect(repo.saved, [
        {'priority': 1},
      ]);
      expect(find.byType(AlertDialog), findsNothing);
    });

    testWidgets('says when signing in again is needed', (tester) async {
      final repo = _RecordingRepository([work()])
        ..error = SignInRequiredException();
      await openWork(tester, repo);
      await edit(tester, inDialog(find.text('Deep work')));
      await tester.enterText(find.byType(TextField), 'x');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Sign in again'), findsOneWidget);
    });

    testWidgets('says how many other events moved', (tester) async {
      final repo = _RecordingRepository([work()])
        ..alsoMoved = [
          Event(id: 'e2', start: at(30, 11), end: at(30, 12)),
          Event(id: 'e3', start: at(30, 12), end: at(30, 13)),
        ];
      await openWork(tester, repo);
      await edit(tester, inDialog(find.text('1h')));
      await tester.enterText(find.byType(TextField), 'soon');
      await tester.tap(find.byTooltip('Keep edit'));
      await tester.pumpAndSettle();
      expect(find.text('Enter a duration, like 1h 30m.'), findsOneWidget);

      await tester.enterText(find.byType(TextField), '1h 30m');
      await tester.tap(find.byTooltip('Keep edit'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save 1 change'));
      await tester.pumpAndSettle();
      expect(repo.saved, [
        {'min_duration': 'PT1H30M'},
      ]);
      expect(
        find.text('Saved. 2 other events moved to make room.'),
        findsOneWidget,
      );
    });

    testWidgets('picks goals by name, the first kept as primary', (
      tester,
    ) async {
      final repo = _RecordingRepository([work()]);
      await openWork(tester, repo);
      // Shown by name straight away.
      await edit(tester, inDialog(find.text('Deep focus')));
      // Active goals only; the first picked is the primary goal.
      expect(inDialog(find.text('Old')), findsNothing);
      expect(inDialog(find.byTooltip('Primary goal')), findsOneWidget);
      await tester.ensureVisible(inDialog(find.text('Exercise')));
      await tester.pumpAndSettle();
      await tester.tap(inDialog(find.text('Exercise')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byTooltip('Keep edit'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Keep edit'));
      await tester.pumpAndSettle();
      // Names, now that they're loaded.
      expect(inDialog(find.text('Deep focus, Exercise')), findsOneWidget);
      await tester.tap(find.text('Save 1 change'));
      await tester.pumpAndSettle();
      expect(repo.saved, [
        {
          'action_ids': ['g1', 'g2'],
        },
      ]);
    });

    testWidgets('goals inferred from its label are marked, and kept to '
        'confirm them', (tester) async {
      final inferred = Event.fromJson({
        ...work().toJson(),
        'actions_from_label': true,
      });
      final repo = _RecordingRepository([inferred]);
      await openWork(tester, repo);

      expect(
        inDialog(find.text('Deep focus (from its label)', findRichText: true)),
        findsOneWidget,
      );
      // Kept as it is: confirmed, which is a change to save.
      await edit(tester, inDialog(find.textContaining('Deep focus')));
      await tester.ensureVisible(find.byTooltip('Keep edit'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Keep edit'));
      await tester.pumpAndSettle();
      expect(
        inDialog(find.text('Deep focus (from its label)', findRichText: true)),
        findsNothing,
      );
      await tester.tap(find.text('Save 1 change'));
      await tester.pumpAndSettle();
      expect(repo.saved, [
        {
          'action_ids': ['g1'],
        },
      ]);
    });

    test(
      'McpEventsRepository says goals it sends are set, not inferred',
      () async {
        final client = _RecurrenceClient();
        final event = Event.fromJson({
          ...work().toJson(),
          'actions_from_label': true,
        });

        await McpEventsRepository(client)
            .updateEvent(event, {'summary': 'Focus'});
        expect(
          (client.arguments!['event'] as Map)['actions_from_label'],
          isTrue,
        );

        await McpEventsRepository(client).updateEvent(event, {
          'action_ids': ['g1'],
        });
        expect(
          (client.arguments!['event'] as Map)['actions_from_label'],
          isFalse,
        );
      },
    );

    testWidgets('asks before throwing edits away; Revert drops them', (
      tester,
    ) async {
      final repo = _RecordingRepository([work()]);
      await openWork(tester, repo);
      await edit(tester, inDialog(find.text('Deep work')));
      await tester.enterText(find.byType(TextField), 'Other');
      await tester.tap(find.byTooltip('Keep edit'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      expect(find.text('Discard changes?'), findsOneWidget);
      await tester.tap(find.text('Keep editing'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Revert'));
      await tester.pumpAndSettle();
      expect(inDialog(find.text('Deep work')), findsOneWidget);
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(repo.saved, isEmpty);
    });

    testWidgets('cancels an event after asking', (tester) async {
      final repo = _RecordingRepository([work()]);
      await openWork(tester, repo);
      await tester.tap(find.text('Cancel event'));
      await tester.pumpAndSettle();
      expect(find.text('Cancel this event?'), findsOneWidget);
      await tester.tap(find.text('Cancel event').last);
      await tester.pumpAndSettle();
      expect(repo.saved, [
        {'is_cancelled': true},
      ]);
      // The server doesn't list cancelled events, so it leaves the list.
      expect(find.text('Event cancelled.'), findsOneWidget);
      expect(find.text('9:00 AM – 10:30 AM'), findsNothing);
    });

    test('durations read as typed and as the server sends them', () {
      expect(parseDuration('1h 30m'), const Duration(minutes: 90));
      expect(parseDuration('90m'), const Duration(minutes: 90));
      expect(parseDuration('90'), const Duration(minutes: 90));
      expect(parseDuration('1:30'), const Duration(minutes: 90));
      expect(parseDuration('2h'), const Duration(hours: 2));
      expect(parseDuration('PT45M'), const Duration(minutes: 45));
      expect(parseDuration('soon'), isNull);
      expect(parseIsoDuration('PT1H30M'), const Duration(minutes: 90));
      expect(parseIsoDuration('P1DT2H'), const Duration(hours: 26));
      expect(parseIsoDuration('PT'), isNull);
      expect(isoDuration(const Duration(minutes: 90)), 'PT1H30M');
      expect(isoDuration(Duration.zero), 'PT0S');
      expect(formatDuration(const Duration(minutes: 45)), '45m');
    });
  });

  group('the event summary', () {
    Event work() => Event.fromJson({
      'id': 'e1',
      'summary': 'Work',
      'start': localIsoTimestamp(at(30, 9)),
      'end': localIsoTimestamp(at(30, 10, 30)),
      'description': 'Deep work',
      'location': null,
      'action_ids': ['g1'],
      'action_names': ['Deep focus'],
      'priority': 2,
      'effective_priority': 2,
      'is_fixed_time': false,
      'is_cancelled': false,
    });

    Future<void> open(WidgetTester tester, EventsRepository repo) async {
      await tester.pumpWidget(
        app(
          repo,
          goals: InMemoryGoalsRepository([
            const Goal(
              id: 'g1',
              name: 'Deep focus',
              priority: 1,
              backgroundColor: '#4986e7',
            ),
            const Goal(id: 'g2', name: 'Exercise', priority: 2),
          ]),
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Work').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Work').first);
      await tester.pumpAndSettle();
    }

    Finder inDialog(Finder f) =>
        find.descendant(of: find.byType(AlertDialog), matching: f);

    testWidgets('shows the properties one edits, blank ones as hints', (
      tester,
    ) async {
      await open(tester, _RecordingRepository([work()]));
      expect(inDialog(find.text('P2')), findsOneWidget);
      expect(inDialog(find.text('Work')), findsOneWidget);
      expect(
        inDialog(find.text('Wed, Sep 30 · 9:00 AM – 10:30 AM')),
        findsOneWidget,
      );
      expect(inDialog(find.text('Add location')), findsOneWidget);
      expect(inDialog(find.text('Deep work')), findsOneWidget);
      expect(inDialog(find.text('Flexible time')), findsOneWidget);
      expect(inDialog(find.text('Deep focus')), findsOneWidget);
      // Not in a series, so no link to one.
      expect(inDialog(find.text('Repeats · see series')), findsNothing);
      // Nor the properties it leaves to Details.
      expect(inDialog(find.text('id')), findsNothing);

      await tester.tap(find.text('Details'));
      await tester.pumpAndSettle();
      expect(inDialog(find.text('is_cancelled')), findsOneWidget);
    });

    testWidgets('tapping a property edits it; Save sends the changes', (
      tester,
    ) async {
      final repo = _RecordingRepository([work()]);
      await open(tester, repo);

      await tester.tap(inDialog(find.text('P2')));
      await tester.pumpAndSettle();
      await tester.tap(inDialog(find.text('P0')));
      await tester.pumpAndSettle();

      await tester.tap(inDialog(find.text('Work')));
      await tester.pumpAndSettle();
      await tester.enterText(inDialog(find.byType(TextField)), 'Admin');
      await tester.pumpAndSettle();

      await tester.tap(inDialog(find.text('Add location')));
      await tester.pumpAndSettle();
      await tester.enterText(inDialog(find.byType(TextField)), 'Office');
      await tester.pumpAndSettle();

      await tester.ensureVisible(inDialog(find.text('Flexible time')));
      await tester.tap(inDialog(find.text('Flexible time')));
      await tester.pumpAndSettle();
      expect(inDialog(find.text('Fixed time')), findsOneWidget);

      // With changes, Details gives way to Cancel and Save.
      expect(find.text('Details'), findsNothing);
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(repo.saved, [
        {
          'priority': 0,
          'summary': 'Admin',
          'location': 'Office',
          'is_fixed_time': true,
        },
      ]);
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.text('Saved.'), findsOneWidget);
    });

    testWidgets('changing the start keeps its length', (tester) async {
      final repo = _RecordingRepository([work()]);
      await open(tester, repo);
      await tester.tap(inDialog(find.textContaining('Sep 30 ·')));
      await tester.pumpAndSettle();
      await tester.tap(inDialog(find.text('9:00 AM')));
      await tester.pumpAndSettle();
      // The time picker, typed into.
      await tester.tap(find.byIcon(Icons.keyboard_outlined));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).at(0), '11');
      await tester.enterText(find.byType(TextField).at(1), '00');
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(
        inDialog(find.text('Wed, Sep 30 · 11:00 AM – 12:30 PM')),
        findsOneWidget,
      );
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(repo.saved, [
        {
          'end': localIsoTimestamp(at(30, 12, 30)),
          'start': localIsoTimestamp(at(30, 11)),
        },
      ]);
    });

    testWidgets('− and + move the times a quarter hour, up to the events '
        'either side', (tester) async {
      final repo = _RecordingRepository([
        Event(id: 'b', start: at(30, 8), end: at(30, 8, 50), summary: 'Run'),
        work(),
        Event(id: 'l', start: at(30, 11), end: at(30, 12), summary: 'Lunch'),
      ]);
      await open(tester, repo);
      await tester.tap(inDialog(find.textContaining('Sep 30 ·')));
      await tester.pumpAndSettle();
      expect(
        inDialog(find.textContaining('Free from 8:50 AM to 11:00 AM')),
        findsOneWidget,
      );

      IconButton button(String tooltip) => tester.widget<IconButton>(
        find.ancestor(
          of: find.byTooltip(tooltip),
          matching: find.byType(IconButton),
        ),
      );
      Future<void> press(String tooltip) async {
        await tester.tap(find.byTooltip(tooltip));
        await tester.pumpAndSettle();
      }

      await press('Start 15 min earlier');
      expect(button('Start 15 min earlier').onPressed, isNull);
      await press('End 15 min later');
      await press('End 15 min later');
      expect(button('End 15 min later').onPressed, isNull);
      await press('End 15 min earlier');
      expect(
        inDialog(find.text('Wed, Sep 30 · 8:50 AM – 10:45 AM')),
        findsOneWidget,
      );
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(repo.saved, [
        {
          'start': localIsoTimestamp(at(30, 8, 50)),
          'end': localIsoTimestamp(at(30, 10, 45)),
        },
      ]);
    });

    testWidgets('a start picked inside the next event moves to its end', (
      tester,
    ) async {
      final repo = _RecordingRepository([
        work(),
        Event(id: 'l', start: at(30, 11), end: at(30, 12), summary: 'Lunch'),
        Event(id: 'm', start: at(30, 13), end: at(30, 14), summary: 'Call'),
      ]);
      await open(tester, repo);
      await tester.tap(inDialog(find.textContaining('Sep 30 ·')));
      await tester.pumpAndSettle();
      await tester.tap(inDialog(find.text('9:00 AM')));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.keyboard_outlined));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).at(0), '11');
      await tester.enterText(find.byType(TextField).at(1), '30');
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      // After Lunch, kept an hour and a half until Call cuts it short.
      expect(
        inDialog(find.text('Wed, Sep 30 · 12:00 PM – 1:00 PM')),
        findsOneWidget,
      );
    });

    testWidgets('picks goals, shown with their diamonds', (tester) async {
      final repo = _RecordingRepository([work()]);
      await open(tester, repo);
      expect(inDialog(find.byType(GoalDiamond)), findsOneWidget);
      await tester.ensureVisible(inDialog(find.text('Deep focus')));
      await tester.tap(inDialog(find.text('Deep focus')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(inDialog(find.text('Exercise')));
      await tester.pumpAndSettle();
      await tester.tap(inDialog(find.text('Exercise')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(inDialog(find.text('Done')));
      await tester.tap(inDialog(find.text('Done')));
      await tester.pumpAndSettle();
      expect(inDialog(find.byType(GoalDiamond)), findsNWidgets(2));
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(repo.saved, [
        {
          'action_ids': ['g1', 'g2'],
        },
      ]);
    });

    testWidgets('the trash can cancels it, after asking', (tester) async {
      final repo = _RecordingRepository([work()]);
      await open(tester, repo);
      await tester.tap(find.byTooltip('Cancel event'));
      await tester.pumpAndSettle();
      expect(find.text('Cancel this event?'), findsOneWidget);
      expect(
        find.text(
          '"Work" on Wed, Sep 30 leaves the list. This can\'t be undone.',
        ),
        findsOneWidget,
      );
      await tester.tap(find.text('Keep event'));
      await tester.pumpAndSettle();
      expect(repo.saved, isEmpty);

      await tester.tap(find.byTooltip('Cancel event'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel event'));
      await tester.pumpAndSettle();
      expect(repo.saved, [
        {'is_cancelled': true},
      ]);
      expect(find.text('Event cancelled.'), findsOneWidget);
    });

    testWidgets('clears its priority and description', (tester) async {
      final repo = _RecordingRepository([work()]);
      await open(tester, repo);
      await tester.tap(inDialog(find.text('P2')));
      await tester.pumpAndSettle();
      await tester.tap(inDialog(find.text('From its goals')));
      await tester.pumpAndSettle();
      expect(inDialog(find.text('From goals')), findsOneWidget);

      await tester.tap(inDialog(find.text('Deep work')));
      await tester.pumpAndSettle();
      await tester.enterText(inDialog(find.byType(TextField)), '');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(repo.saved, [
        {'priority': null, 'description': null},
      ]);
    });

    testWidgets("an emptied summary isn't a change", (tester) async {
      final repo = _RecordingRepository([work()]);
      await open(tester, repo);
      await tester.tap(inDialog(find.text('Work')));
      await tester.pumpAndSettle();
      await tester.enterText(inDialog(find.byType(TextField)), ' ');
      await tester.pumpAndSettle();
      expect(find.text('Save'), findsNothing);
    });

    test('McpEventsRepository lists the fields cleared to clear', () async {
      final client = _RecurrenceClient();
      await McpEventsRepository(client).updateEvent(work(), {
        'priority': null,
        'location': null,
        'summary': 'Admin',
      });
      expect(client.name, 'update_event');
      expect(client.arguments!['clear_fields'], ['priority', 'location']);
      // Never moving other events to make room.
      expect(client.arguments!['reallocate'], isFalse);
      expect((client.arguments!['event'] as Map)['summary'], 'Admin');

      await McpEventsRepository(client).updateEvent(work(), {'summary': 'x'});
      expect(client.arguments!.containsKey('clear_fields'), isFalse);
    });

    testWidgets("shows the server's error and keeps the edits", (tester) async {
      final repo = _RecordingRepository([work()])
        ..error = McpException('Overlaps a fixed-time event');
      await open(tester, repo);
      await tester.tap(inDialog(find.text('P2')));
      await tester.pumpAndSettle();
      await tester.tap(inDialog(find.text('P1')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(
        find.text("Couldn't save. Overlaps a fixed-time event"),
        findsOneWidget,
      );
      expect(find.text('Save'), findsOneWidget);
    });
  });

  group('creating an event', () {
    Finder inDialog(Finder f) =>
        find.descendant(of: find.byType(AlertDialog), matching: f);

    /// Taps today's timeline, away from the times, at [time].
    Future<void> tapAt(WidgetTester tester, DateTime time) async {
      final timeline = find.byType(DayTimeline);
      final y = timelineOffset(
        time,
        day: at(30, 0),
        dayEnd: at(31, 0),
        scale: defaultTimelineScale,
      );
      await tester.tapAt(
        tester.getTopLeft(timeline) +
            Offset(tester.getSize(timeline).width / 2, y),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('tapping between events opens a blank one there, up to the '
        'next', (tester) async {
      final repo = _RecordingRepository([
        Event(id: 'w', start: at(30, 9), end: at(30, 10, 30), summary: 'Work'),
        Event(id: 'l', start: at(30, 12), end: at(30, 13), summary: 'Lunch'),
      ]);
      await tester.pumpWidget(app(repo));
      await tester.pumpAndSettle();
      await tapAt(tester, at(30, 11, 20));

      // From the quarter hour, cut short by Lunch.
      expect(
        inDialog(find.text('Wed, Sep 30 · 11:15 AM – 12:00 PM')),
        findsOneWidget,
      );
      expect(inDialog(find.text('Add location')), findsOneWidget);
      expect(inDialog(find.text('Add description')), findsOneWidget);
      expect(find.byTooltip('Cancel event'), findsNothing);
      expect(find.text('Details'), findsNothing);
      // Its summary, open to type; it can't be made without one.
      final summary = inDialog(find.byType(TextField));
      expect(tester.widget<TextField>(summary).controller!.text, isEmpty);
      final create = find.widgetWithText(FilledButton, 'Create');
      expect(tester.widget<FilledButton>(create).onPressed, isNull);

      await tester.enterText(summary, 'Admin');
      await tester.pumpAndSettle();
      await tester.tap(create);
      await tester.pumpAndSettle();
      expect(repo.created, [
        {
          'start': localIsoTimestamp(at(30, 11, 15)),
          'end': localIsoTimestamp(at(30, 12)),
          'summary': 'Admin',
        },
      ]);
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.text('Event created.'), findsOneWidget);
      expect(find.text('Admin'), findsOneWidget);
    });

    testWidgets('starts after the event before, and + stops at the next', (
      tester,
    ) async {
      final repo = _RecordingRepository([
        Event(id: 'w', start: at(30, 9), end: at(30, 10, 35), summary: 'Work'),
        Event(id: 'l', start: at(30, 12), end: at(30, 13), summary: 'Lunch'),
      ]);
      await tester.pumpWidget(app(repo));
      await tester.pumpAndSettle();
      await tapAt(tester, at(30, 10, 44));
      // Not from 10:30, inside Work.
      expect(
        inDialog(find.text('Wed, Sep 30 · 10:35 AM – 11:35 AM')),
        findsOneWidget,
      );
      await tester.enterText(inDialog(find.byType(TextField)), 'Admin');
      await tester.tap(inDialog(find.textContaining('Sep 30 ·')));
      await tester.pumpAndSettle();
      for (var i = 0; i < 4; i++) {
        await tester.tap(find.byTooltip('End 15 min later'));
        await tester.pumpAndSettle();
      }
      expect(
        inDialog(find.text('Wed, Sep 30 · 10:35 AM – 12:00 PM')),
        findsOneWidget,
      );
      await tester.tap(find.text('Create'));
      await tester.pumpAndSettle();
      expect(repo.created, [
        {
          'start': localIsoTimestamp(at(30, 10, 35)),
          'end': localIsoTimestamp(at(30, 12)),
          'summary': 'Admin',
        },
      ]);
    });

    testWidgets('on an empty day, lasts an hour; Cancel makes nothing', (
      tester,
    ) async {
      final repo = _RecordingRepository([]);
      await tester.pumpWidget(app(repo));
      await tester.pumpAndSettle();
      await tapAt(tester, at(30, 14, 5));
      expect(
        inDialog(find.text('Wed, Sep 30 · 2:00 PM – 3:00 PM')),
        findsOneWidget,
      );
      await tester.enterText(inDialog(find.byType(TextField)), 'Gym');
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(repo.created, isEmpty);
      expect(find.byType(AlertDialog), findsNothing);
    });

    testWidgets('tapping the "No events." card opens one there', (
      tester,
    ) async {
      final repo = _RecordingRepository([]);
      await tester.pumpWidget(app(repo));
      await tester.pumpAndSettle();
      // It lets the tap through, to the timeline under it.
      await tester.tap(
        find.text('No events.\nTap a time to add one.'),
        warnIfMissed: false,
      );
      await tester.pumpAndSettle();
      expect(find.text('Create'), findsOneWidget);
    });

    testWidgets('tapping an event still opens it', (tester) async {
      final repo = _RecordingRepository([
        Event(id: 'w', start: at(30, 11), end: at(30, 13), summary: 'Work'),
      ]);
      await tester.pumpWidget(app(repo));
      await tester.pumpAndSettle();
      await tapAt(tester, at(30, 12));
      expect(inDialog(find.text('Work')), findsOneWidget);
      expect(find.text('Create'), findsNothing);
    });

    testWidgets("shows the server's error and keeps what was typed", (
      tester,
    ) async {
      final repo = _RecordingRepository([])
        ..error = McpException('Overlaps a fixed-time event');
      await tester.pumpWidget(app(repo));
      await tester.pumpAndSettle();
      await tapAt(tester, at(30, 14));
      await tester.enterText(inDialog(find.byType(TextField)), 'Gym');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Create'));
      await tester.pumpAndSettle();
      expect(
        find.text("Couldn't save. Overlaps a fixed-time event"),
        findsOneWidget,
      );
      expect(inDialog(find.text('Gym')), findsOneWidget);
    });

    test('McpEventsRepository sends create_event its fields set', () async {
      final client = _RecurrenceClient();
      await McpEventsRepository(client).createEvent({
        'start': localIsoTimestamp(at(30, 14)),
        'end': localIsoTimestamp(at(30, 15)),
        'summary': 'Gym',
        'priority': null,
        'action_ids': ['g1'],
      });
      expect(client.name, 'create_event');
      expect(client.arguments, {
        'event': {
          'start': localIsoTimestamp(at(30, 14)),
          'end': localIsoTimestamp(at(30, 15)),
          'summary': 'Gym',
          'action_ids': ['g1'],
        },
        // Never moving other events to make room.
        'reallocate': false,
      });
    });
  });

  group('a recurring series', () {
    InMemoryEventsRepository series() => InMemoryEventsRepository(
      [
        Event.fromJson({
          'id': 'standup_0930',
          'summary': 'Standup',
          'start': localIsoTimestamp(at(30, 9)),
          'end': localIsoTimestamp(at(30, 10)),
          'recurring_event_id': 'standup',
        }),
      ],
      [
        Recurrence.fromJson({
          'id': 'standup',
          'summary': 'Standup',
          'start': localIsoTimestamp(at(7, 9)),
          'end': localIsoTimestamp(at(7, 10)),
          'repeat': {
            'every': 'week',
            'weekdays': ['mon', 'wed'],
          },
          'schedule': 'Every week on Mon, Wed',
          'priority': 1,
        }),
      ],
    );

    /// Opens the event, then its series' Details, and renames the series.
    Future<void> renameSeries(WidgetTester tester) async {
      await tester.ensureVisible(find.text('Standup'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Standup'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Repeats · see series'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Details').last);
      await tester.pumpAndSettle();
      expect(find.text('Every week on Mon, Wed'), findsOneWidget);
      final dialog = find.byType(AlertDialog).last;
      await tester.tap(
        find.descendant(of: dialog, matching: find.text('Standup')).last,
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.descendant(of: dialog, matching: find.byType(TextField)),
        'Team standup',
      );
      await tester.tap(find.byTooltip('Keep edit'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save 1 change'));
      await tester.pumpAndSettle();
    }

    testWidgets('an event links to its series, which can be changed from '
        'it on', (tester) async {
      final repo = series();
      await tester.pumpWidget(app(repo));
      await tester.pumpAndSettle();

      await renameSeries(tester);
      expect(find.text('Change which events?'), findsOneWidget);
      await tester.tap(find.text('This and following events'));
      await tester.pumpAndSettle();

      expect(repo.splits, ['standup_0930']);
      expect((await repo.recurrence('standup')).summary, 'Team standup');
      expect(find.text('Saved this and following events.'), findsOneWidget);
      // Every dialog closed.
      expect(find.byType(AlertDialog), findsNothing);
    });

    testWidgets('changes every event, or goes back without saving', (
      tester,
    ) async {
      final repo = series();
      await tester.pumpWidget(app(repo));
      await tester.pumpAndSettle();

      await renameSeries(tester);
      await tester.tap(find.text('Go back'));
      await tester.pumpAndSettle();
      expect(repo.splits, isEmpty);
      expect(find.text('Save 1 change'), findsOneWidget); // Still open.

      await tester.tap(find.text('Save 1 change'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('All events'));
      await tester.pumpAndSettle();
      expect(repo.splits, [null]);
      expect(find.text('Saved every event in the series.'), findsOneWidget);
    });

    /// Opens the event, then its series' summary.
    Future<void> openSeries(WidgetTester tester) async {
      await tester.ensureVisible(find.text('Standup'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Standup'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Repeats · see series'));
      await tester.pumpAndSettle();
    }

    Finder inSeries(Finder f) =>
        find.descendant(of: find.byType(AlertDialog).last, matching: f);

    testWidgets("the series' summary shows how it repeats, and its first "
        "event's times", (tester) async {
      await tester.pumpWidget(app(series()));
      await tester.pumpAndSettle();
      await openSeries(tester);
      expect(inSeries(find.text('Series')), findsOneWidget);
      expect(inSeries(find.text('Every week on Mon, Wed')), findsOneWidget);
      expect(
        inSeries(find.text('9:00 AM – 10:00 AM · from Mon, Sep 7')),
        findsOneWidget,
      );
    });

    testWidgets('saving the series says what it may change, but for the '
        'time', (tester) async {
      final repo = series();
      await tester.pumpWidget(app(repo));
      await tester.pumpAndSettle();
      await openSeries(tester);
      await tester.tap(inSeries(find.text('Standup')));
      await tester.pumpAndSettle();
      await tester.enterText(inSeries(find.byType(TextField)), 'Sync');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(
        find.text(
          'Saving may set every property of each of these events to the '
          "series', except its time, even events you changed on their own.",
        ),
        findsOneWidget,
      );
      await tester.tap(find.text('All events'));
      await tester.pumpAndSettle();
      expect(repo.splits, [null]);
      expect((await repo.recurrence('standup')).summary, 'Sync');
      expect(find.text('Saved every event in the series.'), findsOneWidget);
      expect(find.byType(AlertDialog), findsNothing);
    });

    testWidgets("saving the series' time says it may move every event", (
      tester,
    ) async {
      await tester.pumpWidget(app(series()));
      await tester.pumpAndSettle();
      await openSeries(tester);
      await tester.tap(inSeries(find.textContaining('from Mon, Sep 7')));
      await tester.pumpAndSettle();
      await tester.tap(inSeries(find.text('Mon, Sep 7')).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('8'));
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(
        find.text(
          'Saving may set every property of each of these events to the '
          "series', and move each one to the series' new time, even events "
          'you changed or moved on their own.',
        ),
        findsOneWidget,
      );
      await tester.tap(find.text('Go back'));
      await tester.pumpAndSettle();
      expect(find.text('Save'), findsOneWidget); // Still open.
    });

    testWidgets('changes how the series repeats', (tester) async {
      final repo = series();
      await tester.pumpWidget(app(repo));
      await tester.pumpAndSettle();
      await openSeries(tester);
      await tester.tap(inSeries(find.text('Every week on Mon, Wed')));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('fri'));
      await tester.pumpAndSettle();
      expect(
        inSeries(find.text('Every week on Mon, Wed, Fri')),
        findsOneWidget,
      );
      await tester.tap(find.text('After'));
      await tester.pumpAndSettle();
      expect(
        inSeries(find.text('Every week on Mon, Wed, Fri, 10 times')),
        findsOneWidget,
      );
      await tester.ensureVisible(find.text('Save'));
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('This and following events'));
      await tester.pumpAndSettle();
      expect(repo.splits, ['standup_0930']);
      expect((await repo.recurrence('standup')).repeat?.toJson(), {
        'every': 'week',
        'interval': 1,
        'weekdays': ['mon', 'wed', 'fri'],
        'count': 10,
      });
    });

    testWidgets('the trash can deletes this and following events, after '
        'asking', (tester) async {
      final repo = series();
      await tester.pumpWidget(app(repo));
      await tester.pumpAndSettle();
      await openSeries(tester);
      await tester.tap(find.byTooltip('Delete this and following events'));
      await tester.pumpAndSettle();
      expect(find.text('Delete this and following events?'), findsOneWidget);
      await tester.tap(find.text('Keep events'));
      await tester.pumpAndSettle();
      expect(find.text('Series'), findsOneWidget); // Still open.

      await tester.tap(find.byTooltip('Delete this and following events'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete events'));
      await tester.pumpAndSettle();
      expect(find.text('Deleted this and following events.'), findsOneWidget);
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.text('Standup'), findsNothing);
    });

    test('McpEventsRepository deletes from an event on, never the whole '
        'series', () async {
      final client = _RecurrenceClient();
      final recurrence = Recurrence.fromJson({
        'id': 'standup',
        'start': '2026-09-07T09:00:00Z',
        'end': '2026-09-07T10:00:00Z',
      });
      await McpEventsRepository(client)
          .deleteRecurrence(recurrence, startingAt: 'standup_0930');
      expect(client.name, 'delete_recurrence');
      expect(client.arguments, {
        'id': 'standup',
        'starting_at_event_id': 'standup_0930',
      });
    });

    test('Repeat says how it repeats in words', () {
      expect(
        Repeat.fromJson({
          'every': 'week',
          'weekdays': ['mon', 'wed'],
        }).describe(),
        'Every week on Mon, Wed',
      );
      expect(
        Repeat.fromJson({
          'every': 'month',
          'interval': 2,
          'month_days': [1, -1],
          'until': '2026-12-31',
        }).describe(),
        'Every 2 months on the 1st, the last day, until Dec 31, 2026',
      );
      expect(
        Repeat.fromJson({
          'every': 'year',
          'months': [11],
          'nth_weekdays': [
            {'nth': 4, 'weekday': 'thu'},
          ],
          'count': 1,
        }).describe(),
        'Every year on the fourth Thu in Nov, once',
      );
      // What the app doesn't edit is sent back as it was.
      expect(
        Repeat.fromJson({
          'every': 'week',
          'skipped': ['2026-10-05T09:00:00-04:00'],
        }).copyWith(interval: 2).toJson(),
        {
          'every': 'week',
          'interval': 2,
          'skipped': ['2026-10-05T09:00:00-04:00'],
        },
      );
    });

    test('McpEventsRepository sends update_recurrence what changed', () async {
      final client = _RecurrenceClient();
      final recurrence = Recurrence.fromJson({
        'id': 'standup',
        'start': '2026-09-07T09:00:00Z',
        'end': '2026-09-07T10:00:00Z',
      });

      final saved = await McpEventsRepository(client).updateRecurrence(
        recurrence,
        {'summary': 'Team standup', 'location': null},
        startingAt: 'standup_0930',
      );

      // A field cleared is listed to clear: as null, it'd be kept.
      expect(client.arguments, {
        'recurrence': {'id': 'standup', 'summary': 'Team standup'},
        'starting_at_event_id': 'standup_0930',
        'clear_fields': ['location'],
      });
      expect(saved.single.id, 'standup_new');
    });

    testWidgets("clears the series' priority, to follow its goals'", (
      tester,
    ) async {
      final repo = series();
      await tester.pumpWidget(app(repo));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Standup'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Standup'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Repeats · see series'));
      await tester.pumpAndSettle();
      final dialog = find.byType(AlertDialog).last;
      await tester.tap(find.descendant(of: dialog, matching: find.text('P1')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('From its goals'));
      await tester.pumpAndSettle();
      expect(
        find.descendant(of: dialog, matching: find.text('From goals')),
        findsOneWidget,
      );
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('All events'));
      await tester.pumpAndSettle();
      final saved = await repo.recurrence('standup');
      expect(saved.properties.containsKey('priority'), isTrue);
      expect(saved.properties['priority'], isNull);
    });
  });

  testWidgets('asks to sign in when the server needs it', (tester) async {
    var signedIn = false;
    final repo = _SignInRepository(() => signedIn, [
      Event(start: at(30, 9), end: at(30, 10), summary: 'Work'),
    ]);
    await tester.pumpWidget(app(repo, onSignIn: () async => signedIn = true));
    await tester.pumpAndSettle();
    expect(find.text('Sign in to see your events.'), findsOneWidget);

    await tester.tap(find.text('Sign in'));
    await tester.pumpAndSettle();
    expect(find.text('Work'), findsOneWidget);
  });

  testWidgets('a server error after sign-in is shown, not the sign-in '
      'prompt', (tester) async {
    var signedIn = false;
    final repo = _SignInRepository(() => signedIn, [])
      ..failure = McpException('Tool list_events failed: token revoked');
    await tester.pumpWidget(app(repo, onSignIn: () async => signedIn = true));
    await tester.pumpAndSettle();
    expect(find.text('Sign in to see your events.'), findsOneWidget);

    await tester.tap(find.text('Sign in'));
    await tester.pumpAndSettle();
    expect(find.text('Sign in to see your events.'), findsNothing);
    expect(find.textContaining('Could not load events.'), findsOneWidget);
    expect(find.textContaining('token revoked'), findsOneWidget);
  });

  testWidgets('"Go to now" shows today, with now a third of the way down', (
    tester,
  ) async {
    final repo = InMemoryEventsRepository([
      Event(start: at(29, 6), end: at(29, 7), summary: 'Early'),
    ]);
    await tester.pumpWidget(app(repo));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Previous day'));
    await tester.pumpAndSettle();
    expect(find.text('Yesterday'), findsOneWidget);

    await tester.tap(find.byTooltip('Go to now'));
    await tester.pumpAndSettle();
    expect(find.text('Today'), findsOneWidget);
    final position = tester
        .state<ScrollableState>(
          find.byWidgetPredicate(
            (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
          ),
        )
        .position;
    final day = DateTime(2026, 9, 30);
    expect(
      position.pixels,
      moreOrLessEquals(
        timelineOffset(
              now,
              day: day,
              dayEnd: DateTime(2026, 10, 1),
              scale: defaultTimelineScale,
            ) -
            position.viewportDimension / 3,
      ),
    );
  });

  testWidgets('marks the notes not yet compacted, saved or not', (
    tester,
  ) async {
    final notes = InMemoryNotesRepository([
      Note(timestamp: at(30, 8), description: 'Up'),
      Note(timestamp: at(30, 7), description: 'Old', compactionId: 'c1'),
      Note(timestamp: at(29, 22), description: 'Yesterday'),
    ]);
    // Not started, so it stays unsaved.
    final outbox = NoteOutbox(store: InMemoryOutboxStore(), repository: notes);
    await tester.pumpWidget(
      MaterialApp(
        home: EventsScreen(
          repository: InMemoryEventsRepository(),
          serverLabel: 'offline demo',
          notesRepository: notes,
          outbox: outbox,
          clock: () => now,
        ),
      ),
    );
    await tester.pumpAndSettle();
    List<DateTime> marked() =>
        tester.widget<DayTimeline>(find.byType(DayTimeline).first).pendingNotes
          ..sort();
    expect(marked(), [at(29, 22), at(30, 8)]);

    await tester.runAsync(
      () => outbox.add(Note(timestamp: at(30, 9, 30), description: 'Coffee')),
    );
    await tester.pumpAndSettle();
    expect(marked(), [at(29, 22), at(30, 8), at(30, 9, 30)]);
  });

  group('HomeScreen', () {
    late NoteOutbox outbox;

    Widget home({Stream<DateTime>? addNoteRequests}) {
      final notes = InMemoryNotesRepository();
      outbox = NoteOutbox(store: InMemoryOutboxStore(), repository: notes)
        ..start();
      return MaterialApp(
        home: HomeScreen(
          notesRepository: notes,
          eventsRepository: InMemoryEventsRepository(),
          goalsRepository: InMemoryGoalsRepository(),
          outbox: outbox,
          goalOutbox: GoalOutbox(
            store: InMemoryOutboxStore(),
            repository: InMemoryGoalsRepository(),
          ),
          addNoteRequests: addNoteRequests,
        ),
      );
    }

    testWidgets('opens on Notes, and switches to Events and Plan', (
      tester,
    ) async {
      await tester.pumpWidget(home());
      await tester.pumpAndSettle();
      expect(
        find.text('No uncompacted notes.\nTap + to add one.'),
        findsOneWidget,
      );

      await tester.tap(find.text('Events'));
      await tester.pumpAndSettle();
      expect(find.text('No events.\nTap a time to add one.'), findsOneWidget);

      // The bar's, not the day summary's.
      await tester.tap(
        find.descendant(
          of: find.byType(NavigationBar),
          matching: find.text('Plan'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('No actions yet.\nTap + to add one.'), findsOneWidget);
      outbox.stop();
    });

    testWidgets('the home screen "+" goes back to Notes to add one', (
      tester,
    ) async {
      final taps = StreamController<DateTime>();
      await tester.pumpWidget(home(addNoteRequests: taps.stream));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Events'));
      await tester.pumpAndSettle();

      taps.add(DateTime.now());
      await tester.pumpAndSettle();
      expect(find.text('New note'), findsOneWidget);
      outbox.stop();
      await taps.close();
    });
  });
}

/// Needs sign-in until [signedIn] says otherwise.
class _SignInRepository extends InMemoryEventsRepository {
  _SignInRepository(this.signedIn, super.events);

  final bool Function() signedIn;

  /// Thrown once signed in, as a server that can't answer would.
  Exception? failure;

  @override
  Future<List<Event>> events(DateTime from, DateTime to, {bool keep = false}) {
    if (!signedIn()) throw SignInRequiredException();
    if (failure case final failure?) throw failure;
    return super.events(from, to);
  }
}

/// Takes a second to load the days in [slow].
class _SlowRepository extends InMemoryEventsRepository {
  _SlowRepository(super.events, {required this.slow});

  final Set<DateTime> slow;

  @override
  Future<List<Event>> events(
    DateTime from,
    DateTime to, {
    bool keep = false,
  }) async {
    if (slow.contains(from)) await Future.delayed(const Duration(seconds: 1));
    return super.events(from, to);
  }
}

/// Records what's saved, and fails with [error] while it's set.
class _RecordingRepository extends InMemoryEventsRepository {
  _RecordingRepository(super.events);

  final saved = <Map<String, Object?>>[];
  Object? error;

  /// Returned as moved by every save.
  List<Event> alsoMoved = const [];

  @override
  Future<List<Event>> updateEvent(
    Event event,
    Map<String, Object?> changes,
  ) async {
    if (error case final error?) throw error;
    saved.add(changes);
    return [...await super.updateEvent(event, changes), ...alsoMoved];
  }

  final created = <Map<String, Object?>>[];

  @override
  Future<List<Event>> createEvent(Map<String, Object?> fields) async {
    if (error case final error?) throw error;
    created.add(fields);
    return [...await super.createEvent(fields), ...alsoMoved];
  }
}

/// Answers update_recurrence with one series, keeping what it was sent.
class _RecurrenceClient extends McpClient {
  _RecurrenceClient() : super(endpoint: Uri.parse('http://test'));

  String? name;
  Map<String, Object?>? arguments;

  @override
  Future<Object?> callTool(
    String name, [
    Map<String, Object?> arguments = const {},
  ]) async {
    this.name = name;
    this.arguments = arguments;
    return [
      {
        'id': 'standup_new',
        'start': '2026-09-30T09:00:00Z',
        'end': '2026-09-30T10:00:00Z',
      },
    ];
  }
}
