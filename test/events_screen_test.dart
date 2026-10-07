import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:time_tracker_client/outbox/action_outbox.dart';
import 'package:time_tracker_client/models/event.dart';
import 'package:time_tracker_client/models/plan_action.dart';
import 'package:time_tracker_client/models/note.dart';
import 'package:time_tracker_client/models/recurrence.dart';
import 'package:time_tracker_client/models/repeat.dart';
import 'package:time_tracker_client/outbox/note_outbox.dart';
import 'package:time_tracker_client/outbox/outbox_store.dart';
import 'package:time_tracker_client/screens/events_screen.dart';
import 'package:time_tracker_client/screens/home_screen.dart';
import 'package:time_tracker_client/services/event_store.dart';
import 'package:time_tracker_client/services/events_repository.dart';
import 'package:time_tracker_client/services/actions_repository.dart';
import 'package:time_tracker_client/services/mcp_client.dart';
import 'package:time_tracker_client/services/notes_repository.dart';
import 'package:time_tracker_client/services/plan_memory.dart';
import 'package:time_tracker_client/widgets/pending_event_box.dart';
import 'package:time_tracker_client/widgets/other_events.dart';
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
    ActionsRepository? actions,
  }) => MaterialApp(
    home: EventsScreen(
      repository: repo,
      serverLabel: 'offline demo',
      actionsRepository: actions,
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

  testWidgets("draws a day the app has as it slides in, before it's "
      'loaded here', (tester) async {
    final store =
        EventStore(
          repository: InMemoryEventsRepository(),
          clock: () => now,
        )..putDay(at(29, 0), [
          Event(id: 'kept', start: at(29, 8), end: at(29, 9), summary: 'Walk'),
        ]);
    // Yesterday takes a second to come from the server.
    final repo = _SlowRepository(
      [
        Event(
          id: 'dinner',
          start: at(29, 18),
          end: at(29, 19),
          summary: 'Dinner',
        ),
      ],
      slow: {at(29, 0)},
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

    await tester.tap(find.byTooltip('Previous day'));
    // A few frames into the slide: there already, not a spinner.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('Walk'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);

    // Then as the server has it.
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(find.text('Dinner'), findsOneWidget);
    expect(find.text('Walk'), findsNothing);
  });

  testWidgets("shows a day the app loads as soon as it's there", (
    tester,
  ) async {
    final store = EventStore(
      repository: InMemoryEventsRepository(),
      clock: () => now,
    );
    // Today never comes from the server here.
    final repo = _SlowRepository(const [], slow: {at(30, 0)});
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
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    // The app loads it, as it opens, say.
    store.putDay(at(30, 0), [
      Event(id: 'kept', start: at(30, 8), end: at(30, 9), summary: 'Walk'),
    ]);
    await tester.pump();
    expect(find.text('Walk'), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
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
    expect(find.text('No events.\nTap + to add one.'), findsOneWidget);
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
          actions: InMemoryActionsRepository([
            const PlanAction(id: 'g1', name: 'Deep focus', priority: 1),
            const PlanAction(id: 'g2', name: 'Exercise', priority: 2),
            const PlanAction(id: 'g3', name: 'Old', status: 'inactive'),
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

    testWidgets("picks from the app's actions at once, without asking the "
        'server again', (tester) async {
      final actions = _CountingActionsRepository([
        const PlanAction(id: 'g1', name: 'Deep focus', priority: 1),
        const PlanAction(id: 'g2', name: 'Exercise', priority: 2),
      ]);
      await tester.pumpWidget(
        app(_RecordingRepository([work()]), actions: actions),
      );
      await tester.pumpAndSettle();
      // Once, as the page opened.
      expect(actions.fetches, 1);

      await tester.ensureVisible(find.text('Work').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Work').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Details'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(inDialog(find.text('Deep focus')));
      await tester.pumpAndSettle();
      await tester.tap(inDialog(find.text('Deep focus')));
      // Drawn straight away: no bar while they load.
      await tester.pump();
      expect(inDialog(find.text('Exercise')), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsNothing);
      expect(actions.fetches, 1);
    });

    testWidgets('picks actions by name, the first kept as primary', (
      tester,
    ) async {
      final repo = _RecordingRepository([work()]);
      await openWork(tester, repo);
      // Shown by name straight away.
      await edit(tester, inDialog(find.text('Deep focus')));
      // Active actions only; the first picked is the primary action.
      expect(inDialog(find.text('Old')), findsNothing);
      expect(inDialog(find.byTooltip('Primary action')), findsOneWidget);
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

    testWidgets('actions inferred from its label are marked, and kept to '
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
      'McpEventsRepository says actions it sends are set, not inferred',
      () async {
        final client = _RecurrenceClient();
        final event = Event.fromJson({
          ...work().toJson(),
          'actions_from_label': true,
        });

        Map sent() =>
            ((client.arguments!['updates'] as List).single as Map)['event']
                as Map;

        await McpEventsRepository(client)
            .updateEvent(event, {'summary': 'Focus'});
        expect(sent()['actions_from_label'], isTrue);

        await McpEventsRepository(client).updateEvent(event, {
          'action_ids': ['g1'],
        });
        expect(sent()['actions_from_label'], isFalse);
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
      // Cancelled with delete_event, not saved -- counting against
      // follow-through, as the switch starts.
      expect(repo.saved, isEmpty);
      expect(repo.deleted, [('e1', true)]);
      // The server doesn't list cancelled events, so it leaves the list.
      expect(find.text('Event cancelled.'), findsOneWidget);
      expect(find.text('9:00 AM – 10:30 AM'), findsNothing);
    });

    testWidgets('cancelling it can be just a change of plan', (tester) async {
      final repo = _RecordingRepository([work()]);
      await openWork(tester, repo);
      await tester.tap(find.text('Cancel event'));
      await tester.pumpAndSettle();
      expect(find.text('Count against follow-through'), findsOneWidget);
      await tester.tap(find.text('Count against follow-through'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel event').last);
      await tester.pumpAndSettle();
      expect(repo.deleted, [('e1', false)]);
      expect(find.text('Event cancelled.'), findsOneWidget);
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
          actions: InMemoryActionsRepository([
            const PlanAction(
              id: 'g1',
              name: 'Deep focus',
              priority: 1,
              backgroundColor: '#4986e7',
            ),
            const PlanAction(id: 'g2', name: 'Exercise', priority: 2),
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

      // With changes, Details gives way to Cancel and Save.
      expect(find.text('Details'), findsNothing);
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(repo.saved, [
        {'priority': 0, 'summary': 'Admin', 'location': 'Office'},
      ]);
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.text('Saved.'), findsOneWidget);
    });

    testWidgets('changing history asks first, and goes through once agreed', (
      tester,
    ) async {
      final repo = _RecordingRepository([work()])..history = true;
      await open(tester, repo);
      await tester.tap(inDialog(find.text('Work')));
      await tester.pumpAndSettle();
      await tester.enterText(inDialog(find.byType(TextField)), 'Admin');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save'));
      // Saving shows a spinner while it asks, so it never settles.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.text('Change history?'), findsOneWidget);
      await tester.tap(find.text('Change it'));
      await tester.pumpAndSettle();
      expect(repo.allowed, [false, true]);
      expect(repo.saved, [
        {'summary': 'Admin'},
      ]);
      expect(find.text('Saved.'), findsOneWidget);
    });

    testWidgets('keeping history saves nothing', (tester) async {
      final repo = _RecordingRepository([work()])..history = true;
      await open(tester, repo);
      await tester.tap(inDialog(find.text('Work')));
      await tester.pumpAndSettle();
      await tester.enterText(inDialog(find.byType(TextField)), 'Admin');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      await tester.tap(find.text('Keep history'));
      await tester.pumpAndSettle();
      expect(repo.saved, isEmpty);
      expect(find.textContaining('is history'), findsOneWidget);
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

    testWidgets('picks actions, shown with their diamonds', (tester) async {
      final repo = _RecordingRepository([work()]);
      await open(tester, repo);
      expect(inDialog(find.byType(ActionDiamond)), findsOneWidget);
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
      expect(inDialog(find.byType(ActionDiamond)), findsNWidgets(2));
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
      expect(repo.saved, isEmpty);
      expect(repo.deleted, [('e1', true)]);
      expect(find.text('Event cancelled.'), findsOneWidget);
    });

    testWidgets('the trash can can make it just a change of plan', (
      tester,
    ) async {
      final repo = _RecordingRepository([work()]);
      await open(tester, repo);
      await tester.tap(find.byTooltip('Cancel event'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Count against follow-through'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel event'));
      await tester.pumpAndSettle();
      expect(repo.deleted, [('e1', false)]);
    });

    testWidgets('clears its priority and description', (tester) async {
      final repo = _RecordingRepository([work()]);
      await open(tester, repo);
      await tester.tap(inDialog(find.text('P2')));
      await tester.pumpAndSettle();
      await tester.tap(inDialog(find.text('From its actions')));
      await tester.pumpAndSettle();
      expect(inDialog(find.text('From actions')), findsOneWidget);

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
      Map update() => (client.arguments!['updates'] as List).single as Map;
      expect(client.name, 'update_event');
      expect(update()['clear_fields'], ['priority', 'location']);
      expect((update()['event'] as Map)['summary'], 'Admin');
      expect(client.arguments!.containsKey('allow_compacted_changes'), isFalse);

      await McpEventsRepository(client).updateEvent(work(), {'summary': 'x'});
      expect(update().containsKey('clear_fields'), isFalse);

      await McpEventsRepository(client)
          .updateEvent(work(), {'summary': 'y'}, allowCompactedChanges: true);
      expect(client.arguments!['allow_compacted_changes'], isTrue);
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

    double y(DateTime time) => timelineOffset(
      time,
      day: at(30, 0),
      dayEnd: at(31, 0),
      scale: defaultTimelineScale,
    );

    /// Taps today's timeline at [time]: on its events, but left of the
    /// box's buttons.
    Future<void> tapAt(WidgetTester tester, DateTime time) async {
      final timeline = find.byKey(ValueKey(('shown', at(30, 0))));
      await tester.tapAt(
        tester.getTopLeft(timeline) + Offset(timelineCardsLeft + 40, y(time)),
      );
      await tester.pumpAndSettle();
    }

    final startHere = find.byTooltip(
      'An hour later: tap to stretch it down, or drag its foot',
    );
    final endHere = find.byTooltip(
      'An hour earlier: tap to stretch it up, or drag its top',
    );

    /// Taps "+", which puts the cursor at now: noon.
    Future<void> plus(WidgetTester tester) async {
      await tester.tap(find.byTooltip('New event'));
      await tester.pumpAndSettle();
    }

    /// Taps [button] on the cursor, scrolled into view.
    Future<void> tapButton(WidgetTester tester, Finder button) async {
      await tester.ensureVisible(button);
      await tester.pumpAndSettle();
      await tester.tap(button);
      await tester.pumpAndSettle();
    }

    /// Lets a second go by: the overwriting pulse never settles.
    Future<void> settle(WidgetTester tester) async {
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    /// Taps [button] on the cursor, scrolled into view, while the
    /// overwriting pulse may be going: it never settles.
    Future<void> tapPulsing(WidgetTester tester, Finder button) async {
      await tester.ensureVisible(button);
      await settle(tester);
      await tester.tap(button);
      await settle(tester);
    }

    Future<void> continueToDialog(WidgetTester tester) async {
      await tester.tap(find.byTooltip('Continue'));
      await settle(tester);
    }

    Future<void> drag(WidgetTester tester, Finder button, Duration by) async {
      await tester.ensureVisible(button);
      await tester.pumpAndSettle();
      await tester.drag(
        button,
        Offset(0, by.inMinutes * defaultTimelineScale),
        warnIfMissed: false,
      );
      await settle(tester);
    }

    /// Drags the cursor, by its handle, [by].
    Future<void> moveLine(WidgetTester tester, Duration by) async {
      await drag(tester, find.byTooltip('Drag to move the cursor'), by);
    }

    final otherHandle = find.byTooltip('Drag to move the other end');

    FloatingActionButton continueButton(WidgetTester tester) =>
        tester.widget<FloatingActionButton>(
          find.ancestor(
            of: find.byIcon(Icons.check),
            matching: find.byType(FloatingActionButton),
          ),
        );

    /// The box, as it's drawn.
    PendingEventBox box(WidgetTester tester) => tester
        .widget<PendingEventBoxView>(find.byType(PendingEventBoxView))
        .box;

    /// Whether the box takes time from events already there.
    bool overwrites(WidgetTester tester) => tester
        .widget<PendingEventBoxView>(find.byType(PendingEventBoxView))
        .overwrites;

    testWidgets('tapping a blank space does nothing', (tester) async {
      final repo = _RecordingRepository([
        Event(id: 'w', start: at(30, 9), end: at(30, 10, 30), summary: 'Work'),
      ]);
      await tester.pumpWidget(app(repo));
      await tester.pumpAndSettle();
      await tapAt(tester, at(30, 11, 20));

      expect(find.byType(AlertDialog), findsNothing);
      expect(find.byType(PendingEventBoxView), findsNothing);
      // No zooming buttons: pinching zooms.
      expect(find.byTooltip('Zoom in'), findsNothing);
      expect(find.byTooltip('Zoom out'), findsNothing);
    });

    testWidgets('+ puts a cursor at now; starting there and continuing '
        'opens one there', (tester) async {
      final repo = _RecordingRepository([
        Event(id: 'w', start: at(30, 9), end: at(30, 10, 30), summary: 'Work'),
      ]);
      await tester.pumpWidget(app(repo));
      await tester.pumpAndSettle();
      await plus(tester);

      expect(box(tester).cursor, at(30, 12));
      expect(box(tester).span, isNull);
      // "+" is now cancel and continue -- continue waiting for an event.
      expect(find.byTooltip('New event'), findsNothing);
      expect(find.byTooltip('Cancel'), findsOneWidget);
      expect(continueButton(tester).onPressed, isNull);

      await tapButton(tester, startHere);
      // An hour, to a second cursor.
      expect(box(tester).other, at(30, 13));
      expect(box(tester).span, (at(30, 12), at(30, 13)));
      expect(continueButton(tester).onPressed, isNotNull);

      await continueToDialog(tester);
      expect(
        inDialog(find.text('Wed, Sep 30 · 12:00 PM – 1:00 PM')),
        findsOneWidget,
      );
      expect(inDialog(find.text('Add location')), findsOneWidget);
      final create = find.widgetWithText(FilledButton, 'Create');
      expect(tester.widget<FilledButton>(create).onPressed, isNull);
      await tester.enterText(inDialog(find.byType(TextField)), 'Admin');
      await tester.pumpAndSettle();
      await tester.tap(create);
      await tester.pumpAndSettle();

      expect(repo.created, [
        {
          'start': localIsoTimestamp(at(30, 12)),
          'end': localIsoTimestamp(at(30, 13)),
          'summary': 'Admin',
        },
      ]);
      expect(find.text('Event created.'), findsOneWidget);
      expect(find.text('Admin'), findsOneWidget);
      // Done: "+" again.
      expect(find.byType(PendingEventBoxView), findsNothing);
      expect(find.byTooltip('New event'), findsOneWidget);
    });

    testWidgets('keeping events, the box fits into free time: up to the next '
        'event, out of one a cursor is in, and moved whole to the nearest '
        'free time it fits', (tester) async {
      final repo = _RecordingRepository([
        Event(
          id: 'l',
          start: at(30, 11, 30),
          end: at(30, 12, 30),
          summary: 'Lunch',
        ),
        Event(id: 't', start: at(30, 14), end: at(30, 15), summary: 'Tea'),
      ]);
      await tester.pumpWidget(app(repo));
      await tester.pumpAndSettle();
      // At noon, in Lunch.
      await plus(tester);
      expect(box(tester).cursor, at(30, 12));

      // Out of Lunch, an hour.
      await tapButton(tester, startHere);
      expect(box(tester).span, (at(30, 12, 30), at(30, 13, 30)));
      expect(continueButton(tester).onPressed, isNotNull);
      // Then up to Tea, no further.
      await tapButton(tester, startHere);
      expect(box(tester).span, (at(30, 12, 30), at(30, 14)));
      expect(overwrites(tester), isFalse);

      // Moved whole into Tea, by a tap on it: its size kept, as near as it
      // fits -- after Tea.
      await tapAt(tester, at(30, 14, 30));
      expect(box(tester).span, (at(30, 15), at(30, 16, 30)));
      // Its handle, back to before Tea.
      await drag(
        tester,
        find.byTooltip('Drag to move the event'),
        const Duration(hours: -2),
      );
      expect(box(tester).span, (at(30, 12, 30), at(30, 14)));

      // Overwriting, it can cover Tea; keeping again, it's out of the way.
      await tapButton(tester, find.byTooltip('Keep events: tap to change'));
      await tester.tap(find.text('Overwrite and trim'));
      await tester.pump();
      await tester.tap(find.text('Done'));
      await settle(tester);
      await drag(tester, otherHandle, const Duration(hours: 1));
      expect(box(tester).span, (at(30, 12, 30), at(30, 15)));
      expect(overwrites(tester), isTrue);
      final mode = find.byTooltip('Overwrite and trim: tap to change');
      await tester.ensureVisible(mode);
      await settle(tester);
      await tester.tap(mode);
      await settle(tester);
      await tester.tap(find.text('Keep events'));
      await tester.pump();
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      expect(box(tester).span, (at(30, 12, 30), at(30, 14)));
    });

    testWidgets('keeping events, an arrow shows where the box was moved to, '
        'then fades; a button scrolls back to it', (tester) async {
      final repo = _RecordingRepository([
        Event(id: 't', start: at(30, 14), end: at(30, 15), summary: 'Tea'),
      ]);
      await tester.pumpWidget(app(repo));
      await tester.pumpAndSettle();
      await plus(tester);
      await tapButton(tester, startHere);
      expect(box(tester).span, (at(30, 12), at(30, 13)));
      // Free where it's put: no arrow.
      expect(find.byType(KeptMoveArrow), findsNothing);

      // Put in Tea, it's moved before it: an arrow from the middle of where
      // it was put to the middle of where it went.
      final timeline = find.byKey(ValueKey(('shown', at(30, 0))));
      await tester.tapAt(
        tester.getTopLeft(timeline) +
            Offset(tester.getSize(timeline).width / 2, y(at(30, 14))),
      );
      await tester.pump(const Duration(milliseconds: 100));
      expect(box(tester).span, (at(30, 13), at(30, 14)));
      final arrow = tester.widget<KeptMoveArrow>(find.byType(KeptMoveArrow));
      expect((arrow.from, arrow.to), (at(30, 14, 30), at(30, 13, 30)));
      expect(
        find.descendant(
          of: find.byType(KeptMoveArrow),
          matching: find.byType(CustomPaint),
        ),
        findsOneWidget,
      );
      // Faded away.
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: find.byType(KeptMoveArrow),
          matching: find.byType(CustomPaint),
        ),
        findsNothing,
      );

      // Scrolled well away, the button brings it to the middle.
      await tester.drag(find.byType(ListView).first, const Offset(0, 2000));
      await tester.pumpAndSettle();
      final handle = find.byTooltip('Drag to move the event');
      final list = tester.getRect(find.byType(ListView).first);
      expect(tester.getCenter(handle).dy, greaterThan(list.bottom));
      await tester.tap(find.byTooltip('Go to the new event'));
      await tester.pumpAndSettle();
      expect(tester.getCenter(handle).dy, closeTo(list.center.dy, 2));
    });

    testWidgets('dragging a button makes the event up to where it goes; each '
        "cursor's handle moves its end, and the shadow's both", (tester) async {
      final repo = _RecordingRepository([]);
      await tester.pumpWidget(app(repo));
      await tester.pumpAndSettle();
      await plus(tester);

      await drag(tester, startHere, const Duration(hours: 2));
      expect(box(tester).span, (at(30, 12), at(30, 14)));
      // Each end alone.
      await drag(tester, otherHandle, const Duration(minutes: -30));
      expect(box(tester).span, (at(30, 12), at(30, 13, 30)));
      await moveLine(tester, const Duration(minutes: 30));
      expect(box(tester).span, (at(30, 12, 30), at(30, 13, 30)));
      // Both together.
      await drag(
        tester,
        find.byTooltip('Drag to move the event'),
        const Duration(hours: -1),
      );
      expect(box(tester).span, (at(30, 11, 30), at(30, 12, 30)));

      // Its top dragged up, from the cursor, to 10.
      await drag(tester, endHere, const Duration(minutes: -90));
      expect(box(tester).span, (at(30, 10), at(30, 12, 30)));

      await continueToDialog(tester);
      expect(
        inDialog(find.text('Wed, Sep 30 · 10:00 AM – 12:30 PM')),
        findsOneWidget,
      );
    });

    testWidgets('overwriting: tinged red where it would, and saved in one go, '
        'shortening, cancelling and splitting what was there', (tester) async {
      final repo = _RecordingRepository([
        Event(id: 'a', start: at(30, 11), end: at(30, 12, 30), summary: 'A'),
        Event(id: 'b', start: at(30, 13), end: at(30, 13, 30), summary: 'B'),
        Event(id: 'c', start: at(30, 14), end: at(30, 17), summary: 'C'),
      ]);
      await tester.pumpWidget(app(repo));
      await tester.pumpAndSettle();
      await plus(tester);

      // Picked from the drop-down, each said what it does.
      await tester.tap(find.byTooltip('Keep events: tap to change'));
      await tester.pumpAndSettle();
      // Only the one picked says what it does.
      expect(find.textContaining('never overlaps them'), findsOneWidget);
      expect(find.textContaining('touches is cancelled, whole'), findsNothing);
      await tester.tap(find.text('Overwrite and cancel'));
      await tester.pumpAndSettle();
      expect(find.textContaining('never overlaps them'), findsNothing);
      expect(
        find.textContaining('touches is cancelled, whole'),
        findsOneWidget,
      );
      await tester.tap(find.text('Overwrite and trim'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('shortened, or split around it'),
        findsOneWidget,
      );
      // Still open, until Done.
      expect(find.text('Events in the way'), findsOneWidget);
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      expect(
        find.byTooltip('Overwrite and trim: tap to change'),
        findsOneWidget,
      );

      await drag(tester, startHere, const Duration(hours: 3));
      expect(box(tester).span, (at(30, 12), at(30, 15)));
      expect(overwrites(tester), isTrue);

      await continueToDialog(tester);
      await tester.enterText(inDialog(find.byType(TextField)), 'Party');
      await settle(tester);
      await tester.tap(find.text('Create'));
      // Done, so no pulse.
      await tester.pumpAndSettle();

      expect(repo.created.first['summary'], 'Party');
      // A shortened, B cancelled (just a change of plan), C's start moved.
      expect(repo.saved, [
        {'end': localIsoTimestamp(at(30, 12))},
        {'start': localIsoTimestamp(at(30, 15))},
      ]);
      expect(repo.deleted, [('b', false)]);
      expect(
        find.text('Event created. 3 other events changed to make room.'),
        findsOneWidget,
      );
    });

    testWidgets('each "+" stretches the box an hour, from its top or its '
        'foot, and each "−" shrinks it an hour, from that end', (tester) async {
      final repo = _RecordingRepository([]);
      await tester.pumpWidget(app(repo));
      await tester.pumpAndSettle();
      await plus(tester);
      final shrinkTop = find.byTooltip('Shrink it an hour, from the top');
      final shrinkFoot = find.byTooltip('Shrink it an hour, from the foot');
      // Nothing to shrink yet.
      Material shrinking(Finder button) => tester.widget<Material>(
        find.descendant(of: button, matching: find.byType(Material)),
      );
      expect(shrinking(shrinkTop).elevation, 0);

      // Two below: two hours, from the cursor.
      await tapButton(tester, startHere);
      await tapButton(tester, startHere);
      expect(box(tester).span, (at(30, 12), at(30, 14)));
      // One above: an hour more, at the top -- the cursor going with it.
      await tapButton(tester, endHere);
      expect(box(tester).span, (at(30, 11), at(30, 14)));
      expect(box(tester).cursor, at(30, 11));
      // Shrunk from the top, and from the foot.
      await tapButton(tester, shrinkTop);
      expect(box(tester).span, (at(30, 12), at(30, 14)));
      await tapButton(tester, shrinkFoot);
      expect(box(tester).span, (at(30, 12), at(30, 13)));
      // No shorter than a quarter hour.
      await tapButton(tester, shrinkFoot);
      expect(box(tester).span, (at(30, 12), at(30, 12, 15)));
      expect(shrinking(shrinkFoot).elevation, 0);
    });

    testWidgets("the other cursor's own \"−\" and \"+\", on its outside, "
        'shrink and stretch the box at that end', (tester) async {
      final repo = _RecordingRepository([]);
      await tester.pumpWidget(app(repo));
      await tester.pumpAndSettle();
      await plus(tester);
      final stretch = find.byTooltip(
        'Stretch it an hour, at this end: tap, or drag it',
      );
      final shrink = find.byTooltip('Shrink it an hour, at this end');
      // Not until there's a box.
      expect(stretch, findsNothing);

      await tapButton(tester, startHere);
      await tapButton(tester, startHere);
      expect(box(tester).span, (at(30, 12), at(30, 14)));
      // The foot: below its line.
      final line = tester.getCenter(otherHandle).dy;
      expect(tester.getTopLeft(stretch).dy, greaterThan(line));
      await tapButton(tester, stretch);
      expect(box(tester).span, (at(30, 12), at(30, 15)));
      await tapButton(tester, shrink);
      expect(box(tester).span, (at(30, 12), at(30, 14)));

      // Switched, the other cursor's the top: above its line.
      await tapButton(tester, find.byTooltip('Switch the cursors'));
      expect(
        tester.getBottomLeft(stretch).dy,
        lessThan(tester.getCenter(otherHandle).dy),
      );
      await tapButton(tester, stretch);
      expect(box(tester).span, (at(30, 11), at(30, 14)));
    });

    testWidgets('keeping events, "+" above stretches the box up into the '
        'free time before it, no further than the event before', (
      tester,
    ) async {
      final repo = _RecordingRepository([
        Event(id: 'w', start: at(30, 9), end: at(30, 10, 30), summary: 'Work'),
        Event(id: 's', start: at(30, 12), end: at(30, 13), summary: 'Siesta'),
      ]);
      await tester.pumpWidget(app(repo));
      await tester.pumpAndSettle();
      await tester.longPress(find.text('Siesta'));
      await tester.pumpAndSettle();
      await tapButton(tester, find.byTooltip('Push: tap to change'));
      await tester.tap(find.text('Keep events'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();

      await tapButton(tester, endHere);
      expect(box(tester).span, (at(30, 11), at(30, 13)));
      await tapButton(tester, endHere);
      // Up to Work's end.
      expect(box(tester).span, (at(30, 10, 30), at(30, 13)));
    });

    testWidgets('overwriting and cancelling: the shadow covers every event '
        'it touches, whole, and saving cancels them', (tester) async {
      final repo = _RecordingRepository([
        Event(id: 'a', start: at(30, 11), end: at(30, 12, 30), summary: 'A'),
        Event(id: 'b', start: at(30, 13, 30), end: at(30, 15), summary: 'B'),
      ]);
      await tester.pumpWidget(app(repo));
      await tester.pumpAndSettle();
      await plus(tester);
      await tapButton(tester, find.byTooltip('Keep events: tap to change'));
      await tester.tap(find.text('Overwrite and cancel'));
      await tester.pump();
      await tester.tap(find.text('Done'));
      await settle(tester);

      await tapPulsing(tester, startHere);
      await tapPulsing(tester, startHere);
      // 12-2, touching A and B: the shadow over both, whole.
      expect(box(tester).span, (at(30, 12), at(30, 14)));
      final view = tester.widget<PendingEventBoxView>(
        find.byType(PendingEventBoxView),
      );
      expect(view.covers, (at(30, 11), at(30, 15)));
      expect(view.overwrites, isTrue);

      await continueToDialog(tester);
      // The new event keeps the box's times.
      expect(
        inDialog(find.text('Wed, Sep 30 · 12:00 PM – 2:00 PM')),
        findsOneWidget,
      );
      await tester.enterText(inDialog(find.byType(TextField)), 'Party');
      await settle(tester);
      await tester.tap(find.text('Create'));
      await tester.pumpAndSettle();
      expect(repo.created.single['summary'], 'Party');
      expect(repo.saved, isEmpty);
      expect(repo.deleted, [('a', false), ('b', false)]);
    });

    testWidgets("the new event's trash clears the time of the events under it, "
        'after asking, making no new one', (tester) async {
      final repo = _RecordingRepository([
        Event(id: 'a', start: at(30, 11), end: at(30, 12, 30), summary: 'A'),
        Event(id: 'b', start: at(30, 12, 45), end: at(30, 13), summary: 'B'),
      ]);
      await tester.pumpWidget(app(repo));
      await tester.pumpAndSettle();
      await plus(tester);
      // Keeping events, there's nothing under it to clear.
      await tapButton(tester, startHere);
      await continueToDialog(tester);
      expect(find.byTooltip('Clear this time instead'), findsNothing);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      // Overwriting and trimming, afresh from noon: A trimmed, B cancelled,
      // nothing made.
      await tester.tap(find.byTooltip('Cancel'));
      await tester.pumpAndSettle();
      await plus(tester);
      await tapButton(tester, find.byTooltip('Keep events: tap to change'));
      await tester.tap(find.text('Overwrite and trim'));
      await tester.pump();
      await tester.tap(find.text('Done'));
      await settle(tester);
      await tapPulsing(tester, startHere);
      expect(box(tester).span, (at(30, 12), at(30, 13)));
      await continueToDialog(tester);
      await tester.tap(find.byTooltip('Clear this time instead'));
      await settle(tester);
      expect(find.text('Clear this time of 2 events?'), findsOneWidget);
      await tester.tap(find.text('Clear the time'));
      await tester.pumpAndSettle();

      expect(repo.created, isEmpty);
      expect(repo.saved, [
        {'end': localIsoTimestamp(at(30, 12))},
      ]);
      expect(repo.deleted, [('b', false)]);
      expect(find.text('Time cleared: 2 events changed.'), findsOneWidget);
      expect(find.byType(PendingEventBoxView), findsNothing);
    });

    /// Picks [mode] from the box's drop-down.
    Future<void> pickMode(WidgetTester tester, String mode) async {
      await tapPulsing(tester, find.byTooltip(RegExp(r'^.*: tap to change$')));
      await tester.ensureVisible(find.text(mode));
      await settle(tester);
      await tester.tap(find.text(mode));
      await tester.pump();
      await tester.tap(find.text('Done'));
      await settle(tester);
      await settle(tester);
    }

    /// Where the box shows the events it pushes going.
    List<PushedEvent> pushed(WidgetTester tester) => tester
        .widget<PendingEventBoxView>(find.byType(PendingEventBoxView))
        .pushed;

    testWidgets('trimming and pushing: the event the cursor is inside of is '
        'cut short, and the next pushed along, shown where it goes', (
      tester,
    ) async {
      final repo = _RecordingRepository([
        Event(
          id: 'l',
          start: at(30, 11, 30),
          end: at(30, 12, 30),
          summary: 'Lunch',
        ),
        Event(
          id: 't',
          start: at(30, 12, 30),
          end: at(30, 13, 30),
          summary: 'Tea',
        ),
        Event(id: 'w', start: at(30, 14), end: at(30, 15), summary: 'Walk'),
      ]);
      await tester.pumpWidget(app(repo));
      await tester.pumpAndSettle();
      await plus(tester);
      await pickMode(tester, 'Trim and push');
      await tapPulsing(tester, startHere);
      // In Lunch, at noon, an hour: Lunch cut at noon, Tea pushed to 1-2;
      // Walk, at 2, clear.
      expect(box(tester).span, (at(30, 12), at(30, 13)));
      expect(pushed(tester), [
        (start: at(30, 13), end: at(30, 14), label: 'Tea'),
      ]);
      expect(find.byType(PushedEventOutline), findsOneWidget);
      expect(overwrites(tester), isTrue);

      await continueToDialog(tester);
      await tester.enterText(inDialog(find.byType(TextField)), 'Party');
      await settle(tester);
      await tester.tap(find.text('Create'));
      await settle(tester);
      expect(repo.created.single['summary'], 'Party');
      expect(repo.saved, [
        {'end': localIsoTimestamp(at(30, 12))},
        {
          'start': localIsoTimestamp(at(30, 13)),
          'end': localIsoTimestamp(at(30, 14)),
        },
      ]);
      expect(
        find.text('Event created. 2 other events changed to make room.'),
        findsOneWidget,
      );
    });

    testWidgets('pushing: the cursor snaps out of an event, to between two '
        'that meet, and the trash just makes room', (tester) async {
      final repo = _RecordingRepository([
        Event(
          id: 'a',
          start: at(30, 11, 30),
          end: at(30, 12, 15),
          summary: 'A',
        ),
        Event(id: 'b', start: at(30, 12, 15), end: at(30, 13), summary: 'B'),
        Event(
          id: 'c',
          start: at(30, 13, 30),
          end: at(30, 14, 30),
          summary: 'C',
        ),
      ]);
      await tester.pumpWidget(app(repo));
      await tester.pumpAndSettle();
      await plus(tester);
      await pickMode(tester, 'Push');
      // Noon, in A, nearer its end: where A and B meet.
      expect(box(tester).cursor, at(30, 12, 15));
      await tapPulsing(tester, startHere);
      expect(box(tester).span, (at(30, 12, 15), at(30, 13, 15)));
      // B pushed to 1:15-2, and C, on, to 2-3. Nothing cut.
      expect(pushed(tester), [
        (start: at(30, 13, 15), end: at(30, 14), label: 'B'),
        (start: at(30, 14), end: at(30, 15), label: 'C'),
      ]);
      expect(overwrites(tester), isFalse);

      await continueToDialog(tester);
      await tester.tap(find.byTooltip('Clear this time instead'));
      await settle(tester);
      expect(find.text('Make room, changing 2 events?'), findsOneWidget);
      await tester.tap(find.text('Make room'));
      await settle(tester);
      expect(repo.created, isEmpty);
      expect(repo.saved, [
        {
          'start': localIsoTimestamp(at(30, 13, 15)),
          'end': localIsoTimestamp(at(30, 14)),
        },
        {
          'start': localIsoTimestamp(at(30, 14)),
          'end': localIsoTimestamp(at(30, 15)),
        },
      ]);
    });

    testWidgets('splitting and pushing: the rest of the event the cursor is '
        "inside of goes after the new one, pushing the rest -- only as far "
        "as the days on the timeline have room", (tester) async {
      final repo = _RecordingRepository([
        Event(id: 'k', start: at(30, 11), end: at(30, 13), summary: 'Class'),
        // On to 11:30 PM tomorrow, the last of the days on the timeline.
        Event(id: 'f', start: at(30, 13), end: at(30, 47, 30), summary: 'Long'),
      ]);
      await tester.pumpWidget(app(repo));
      await tester.pumpAndSettle();
      await plus(tester);
      await pickMode(tester, 'Split and push');
      await tapPulsing(tester, startHere);
      // An hour would push Long past tomorrow's midnight, off the days on
      // the timeline: half an hour, no more.
      expect(box(tester).span, (at(30, 12), at(30, 12, 30)));
      expect(pushed(tester), [
        (start: at(30, 13, 30), end: at(30, 48), label: 'Long'),
        (start: at(30, 12, 30), end: at(30, 13, 30), label: 'Event (the rest)'),
      ]);
      expect(overwrites(tester), isFalse);

      await continueToDialog(tester);
      await tester.enterText(inDialog(find.byType(TextField)), 'Call');
      await settle(tester);
      await tester.tap(find.text('Create'));
      await settle(tester);
      expect(repo.saved, [
        {'end': localIsoTimestamp(at(30, 12))},
        {
          'start': localIsoTimestamp(at(30, 13, 30)),
          'end': localIsoTimestamp(at(30, 48)),
        },
      ]);
      expect(
        [for (final c in repo.created) (c['start'], c['end'])],
        [
          (localIsoTimestamp(at(30, 12)), localIsoTimestamp(at(30, 12, 30))),
          (
            localIsoTimestamp(at(30, 12, 30)),
            localIsoTimestamp(at(30, 13, 30)),
          ),
        ],
      );
    });

    testWidgets('pressing and holding an event moves it: the box around it, '
        'pushing to start with, and saying which; saved with what it '
        'pushes, in one go', (tester) async {
      final repo = _RecordingRepository([
        Event(id: 't', start: at(30, 12), end: at(30, 13), summary: 'Tea'),
        Event(id: 'w', start: at(30, 14), end: at(30, 15), summary: 'Walk'),
        Event(id: 'x', start: at(30, 15), end: at(30, 16), summary: 'Talk'),
      ]);
      await tester.pumpWidget(app(repo));
      await tester.pumpAndSettle();
      await tester.longPress(find.text('Tea'));
      await tester.pumpAndSettle();
      expect(box(tester).span, (at(30, 12), at(30, 13)));
      expect(find.byTooltip('Push: tap to change'), findsOneWidget);
      expect(find.text('Moving “Tea”'), findsOneWidget);
      // Faint where it was.
      expect(
        find.ancestor(of: find.text('Tea'), matching: find.byType(Opacity)),
        findsOneWidget,
      );

      // Onto Walk: Walk, and Talk after it, pushed along.
      await tapAt(tester, at(30, 14));
      expect(box(tester).span, (at(30, 14), at(30, 15)));
      expect(pushed(tester), [
        (start: at(30, 15), end: at(30, 16), label: 'Walk'),
        (start: at(30, 16), end: at(30, 17), label: 'Talk'),
      ]);
      await tester.tap(find.byTooltip('Move it here'));
      await tester.pumpAndSettle();
      expect(repo.created, isEmpty);
      expect(repo.saved, [
        {
          'start': localIsoTimestamp(at(30, 14)),
          'end': localIsoTimestamp(at(30, 15)),
        },
        {
          'start': localIsoTimestamp(at(30, 15)),
          'end': localIsoTimestamp(at(30, 16)),
        },
        {
          'start': localIsoTimestamp(at(30, 16)),
          'end': localIsoTimestamp(at(30, 17)),
        },
      ]);
      expect(
        find.text('Event moved. 2 events changed to make room.'),
        findsOneWidget,
      );
      expect(find.byType(PendingEventBoxView), findsNothing);
      // A new event keeps events again, as it did before the move.
      await plus(tester);
      expect(find.byTooltip('Keep events: tap to change'), findsOneWidget);
    });

    testWidgets("the label's on the cursor, away from the box; switching "
        'the cursors turns the box around, pointing to where the cursor went', (
      tester,
    ) async {
      final repo = _RecordingRepository([
        Event(id: 't', start: at(30, 12), end: at(30, 13), summary: 'Tea'),
      ]);
      await tester.pumpWidget(app(repo));
      await tester.pumpAndSettle();
      await tester.longPress(find.text('Tea'));
      await tester.pumpAndSettle();
      final top = tester
          .getTopLeft(find.byKey(ValueKey(('shown', at(30, 0)))))
          .dy;
      final label = find.text('Moving “Tea”');
      // Above the cursor, at noon, the box going down from it.
      expect(box(tester).cursor, at(30, 12));
      expect(tester.getCenter(label).dy, lessThan(top + y(at(30, 12))));

      await tester.tap(find.byTooltip('Switch the cursors'));
      await tester.pump(const Duration(milliseconds: 100));
      expect(box(tester).cursor, at(30, 13));
      expect(box(tester).other, at(30, 12));
      // An arrow from where the cursor was to where it is.
      final arrow = tester.widget<KeptMoveArrow>(find.byType(KeptMoveArrow));
      expect((arrow.from, arrow.to), (at(30, 12), at(30, 13)));
      await tester.pumpAndSettle();
      // Below it now, the box going up from it.
      expect(tester.getCenter(label).dy, greaterThan(top + y(at(30, 13))));

      // Saved as it is: the same times, so nothing to save.
      await tester.tap(find.byTooltip('Move it here'));
      await tester.pumpAndSettle();
      expect(repo.saved, isEmpty);
    });

    testWidgets('a move dropped, or left where it was, saves nothing', (
      tester,
    ) async {
      final repo = _RecordingRepository([
        Event(id: 't', start: at(30, 12), end: at(30, 13), summary: 'Tea'),
      ]);
      await tester.pumpWidget(app(repo));
      await tester.pumpAndSettle();
      await tester.longPress(find.text('Tea'));
      await tester.pumpAndSettle();
      await tapAt(tester, at(30, 15));
      await tester.tap(find.byTooltip('Cancel'));
      await tester.pumpAndSettle();
      expect(find.byType(PendingEventBoxView), findsNothing);
      expect(find.text('Moving “Tea”'), findsNothing);

      await tester.longPress(find.text('Tea'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Move it here'));
      await tester.pumpAndSettle();
      expect(repo.saved, isEmpty);
      expect(find.byType(PendingEventBoxView), findsNothing);
    });

    testWidgets('while the box is up, the days either side are stacked '
        'above and below, without moving what is on screen; a new event '
        'can cross midnight', (tester) async {
      final repo = _RecordingRepository([
        Event(id: 't', start: at(30, 12), end: at(30, 13), summary: 'Tea'),
        Event(id: 'y', start: at(29, 20), end: at(29, 21), summary: 'Late'),
      ]);
      await tester.pumpWidget(app(repo));
      await tester.pumpAndSettle();
      final tea = tester.getTopLeft(find.text('Tea')).dy;
      // Just the day shown.
      expect(find.text('Late'), findsNothing);
      expect(find.byType(DayTimeline), findsOneWidget);

      await plus(tester);
      expect(find.byType(DayTimeline), findsNWidgets(3));
      expect(find.text('Late'), findsOneWidget);
      expect(find.textContaining('Sep 29'), findsOneWidget);
      expect(find.textContaining('Oct 1'), findsOneWidget);
      // Tea where it was.
      expect(tester.getTopLeft(find.text('Tea')).dy, moreOrLessEquals(tea));

      // From 11 PM, two hours: on into tomorrow.
      await tester.drag(find.byType(ListView), const Offset(0, -900));
      await tester.pumpAndSettle();
      await tapAt(tester, at(30, 23));
      await tapButton(tester, startHere);
      await tapButton(tester, startHere);
      expect(box(tester).span, (at(30, 23), at(31, 1)));
      await continueToDialog(tester);
      await tester.enterText(inDialog(find.byType(TextField)), 'Late show');
      await settle(tester);
      await tester.tap(find.text('Create'));
      await tester.pumpAndSettle();
      expect(repo.created.single['start'], localIsoTimestamp(at(30, 23)));
      expect(repo.created.single['end'], localIsoTimestamp(at(31, 1)));

      // Put away, just the day shown again.
      expect(find.byType(DayTimeline), findsOneWidget);
      expect(find.text('Late'), findsNothing);
    });

    testWidgets('Cancel makes nothing', (tester) async {
      final repo = _RecordingRepository([]);
      await tester.pumpWidget(app(repo));
      await tester.pumpAndSettle();
      await plus(tester);
      await tapButton(tester, startHere);
      await tester.tap(find.byTooltip('Cancel'));
      await tester.pumpAndSettle();

      expect(find.byType(PendingEventBoxView), findsNothing);
      expect(repo.created, isEmpty);
    });

    testWidgets("while the cursor's up, tapping an event doesn't open it, "
        'but moves the box there', (tester) async {
      final repo = _RecordingRepository([
        Event(id: 'w', start: at(30, 14), end: at(30, 16), summary: 'Work'),
      ]);
      await tester.pumpWidget(app(repo));
      await tester.pumpAndSettle();
      await plus(tester);
      // Clear of the cursor's buttons, at noon.
      await tapAt(tester, at(30, 15, 10));

      expect(find.byType(AlertDialog), findsNothing);
      expect(box(tester).cursor, at(30, 15, 15));
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
        ..error = McpException('Overlaps another event');
      await tester.pumpWidget(app(repo));
      await tester.pumpAndSettle();
      await plus(tester);
      await tapButton(tester, startHere);
      await continueToDialog(tester);
      await tester.enterText(inDialog(find.byType(TextField)), 'Gym');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Create'));
      await tester.pumpAndSettle();
      expect(
        find.text("Couldn't save. Overlaps another event"),
        findsOneWidget,
      );
      expect(inDialog(find.text('Gym')), findsOneWidget);
    });

    test('McpEventsRepository clears time in one update_event batch', () async {
      final client = _RecurrenceClient();
      await McpEventsRepository(client).makeRoom(
        Overwrite(
          cancels: [Event(id: 'b', start: at(30, 12), end: at(30, 12, 30))],
        ),
      );
      expect(client.name, 'update_event');
      expect(client.arguments, {
        'cancels': [
          {'event_id': 'b', 'counts_against_follow_through': false},
        ],
      });
    });

    test('McpEventsRepository overwrites in one update_event batch', () async {
      final client = _RecurrenceClient();
      await McpEventsRepository(client).createOver(
        {
          'start': localIsoTimestamp(at(30, 12)),
          'end': localIsoTimestamp(at(30, 13)),
          'summary': 'Party',
        },
        Overwrite(
          cancels: [Event(id: 'b', start: at(30, 12), end: at(30, 12, 30))],
          updates: [
            (
              Event(id: 'a', start: at(30, 11), end: at(30, 12, 30)),
              {'end': localIsoTimestamp(at(30, 12))},
            ),
          ],
        ),
        allowCompactedChanges: true,
      );
      expect(client.name, 'update_event');
      expect(client.arguments, {
        'creates': [
          {
            'start': localIsoTimestamp(at(30, 12)),
            'end': localIsoTimestamp(at(30, 13)),
            'summary': 'Party',
          },
        ],
        'updates': [
          {
            'event': {'id': 'a', 'end': localIsoTimestamp(at(30, 12))},
          },
        ],
        'cancels': [
          {'event_id': 'b', 'counts_against_follow_through': false},
        ],
        'allow_compacted_changes': true,
      });
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
        'events': [
          {
            'start': localIsoTimestamp(at(30, 14)),
            'end': localIsoTimestamp(at(30, 15)),
            'summary': 'Gym',
            'action_ids': ['g1'],
          },
        ],
      });
    });

    test('McpEventsRepository cancels with delete_event', () async {
      final client = _RecurrenceClient();
      await McpEventsRepository(client).deleteEvent(
        Event.fromJson({
          'id': 'e1',
          'start': localIsoTimestamp(at(30, 9)),
          'end': localIsoTimestamp(at(30, 10)),
        }),
        countsAgainstFollowThrough: true,
      );
      expect(client.name, 'delete_event');
      expect(client.arguments, {
        'cancels': [
          {'event_id': 'e1', 'counts_against_follow_through': true},
        ],
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

    testWidgets("clears the series' priority, to follow its actions'", (
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
      await tester.tap(find.text('From its actions'));
      await tester.pumpAndSettle();
      expect(
        find.descendant(of: dialog, matching: find.text('From actions')),
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
        tester
            .widget<DayTimeline>(
              find.byKey(ValueKey(('shown', at(30, 0)))).first,
            )
            .pendingNotes
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
          actionsRepository: InMemoryActionsRepository(),
          outbox: outbox,
          actionOutbox: ActionOutbox(
            store: InMemoryOutboxStore(),
            repository: InMemoryActionsRepository(),
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
      expect(find.text('No events.\nTap + to add one.'), findsOneWidget);

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
  Future<List<Event>> events(DateTime from, DateTime to) {
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
  Future<List<Event>> events(DateTime from, DateTime to) async {
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

  /// Whether each save allowed changing history.
  final allowed = <bool>[];

  /// Refuses saves as history until one allows changing it.
  bool history = false;

  @override
  Future<List<Event>> updateEvent(
    Event event,
    Map<String, Object?> changes, {
    bool allowCompactedChanges = false,
  }) async {
    if (error case final error?) throw error;
    allowed.add(allowCompactedChanges);
    if (history && !allowCompactedChanges) {
      throw McpException(
        "'Work' (e1) is history -- so it can't be changed unless the user has explicitly approved "
        'changing history (allow_compacted_changes).',
      );
    }
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
    final events = [
      {
        'id': 'standup_new',
        'start': '2026-09-30T09:00:00Z',
        'end': '2026-09-30T10:00:00Z',
      },
    ];
    // A batch of event changes answers with its events; the rest, a list.
    return name.endsWith('_event') ? {'events': events} : events;
  }
}

/// Counts how often every action is fetched.
class _CountingActionsRepository extends InMemoryActionsRepository {
  _CountingActionsRepository(super.actions);

  var fetches = 0;

  @override
  Future<ActionList> actions() {
    fetches++;
    return super.actions();
  }
}
