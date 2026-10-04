import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:time_tracker_client/outbox/goal_outbox.dart';
import 'package:time_tracker_client/models/event.dart';
import 'package:time_tracker_client/models/goal.dart';
import 'package:time_tracker_client/models/note.dart';
import 'package:time_tracker_client/models/recurrence.dart';
import 'package:time_tracker_client/outbox/note_outbox.dart';
import 'package:time_tracker_client/outbox/outbox_store.dart';
import 'package:time_tracker_client/screens/events_screen.dart';
import 'package:time_tracker_client/screens/home_screen.dart';
import 'package:time_tracker_client/services/events_repository.dart';
import 'package:time_tracker_client/services/goals_repository.dart';
import 'package:time_tracker_client/services/mcp_client.dart';
import 'package:time_tracker_client/services/notes_repository.dart';
import 'package:time_tracker_client/widgets/durations.dart';

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
    expect(find.text('No events.'), findsOneWidget);
  });

  testWidgets('tapping an event shows all its properties', (tester) async {
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

  group('editing in the event dialog', () {
    Event work() => Event.fromJson({
      'id': 'e1',
      'summary': 'Work',
      'start': localIsoTimestamp(at(30, 9)),
      'end': localIsoTimestamp(at(30, 10, 30)),
      'description': 'Deep work',
      'location': null,
      'goal_ids': ['g1'],
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
      expect(inDialog(find.text('Primary goal')), findsOneWidget);
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
          'goal_ids': ['g1', 'g2'],
        },
      ]);
    });

    testWidgets('goals inferred from its label are marked, and kept to '
        'confirm them', (tester) async {
      final inferred = Event.fromJson({
        ...work().toJson(),
        'goals_from_label': true,
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
          'goal_ids': ['g1'],
        },
      ]);
    });

    test(
      'McpEventsRepository says goals it sends are set, not inferred',
      () async {
        final client = _RecurrenceClient();
        final event = Event.fromJson({
          ...work().toJson(),
          'goals_from_label': true,
        });

        await McpEventsRepository(client)
            .updateEvent(event, {'summary': 'Focus'});
        expect((client.arguments!['event'] as Map)['goals_from_label'], isTrue);

        await McpEventsRepository(client).updateEvent(event, {
          'goal_ids': ['g1'],
        });
        expect(
          (client.arguments!['event'] as Map)['goals_from_label'],
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
          'rules': ['RRULE:FREQ=WEEKLY;BYDAY=MO,WE'],
          'schedule': 'Every week on Mon, Wed',
        }),
      ],
    );

    /// Opens the event, then its series, and renames the series.
    Future<void> renameSeries(WidgetTester tester) async {
      await tester.ensureVisible(find.text('Standup'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Standup'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Repeats: see or change the series'));
      await tester.pumpAndSettle();
      expect(find.text('Every week on Mon, Wed'), findsOneWidget);
      expect(find.text('RRULE:FREQ=WEEKLY;BYDAY=MO,WE'), findsOneWidget);
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
      // Both dialogs closed.
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

      expect(client.arguments, {
        'recurrence': {'id': 'standup', 'summary': 'Team standup'},
        'starting_at_event_id': 'standup_0930',
      });
      expect(saved.single.id, 'standup_new');
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

    testWidgets('opens on Notes, and switches to Events and Goals', (
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
      expect(find.text('No events.'), findsOneWidget);

      await tester.tap(find.text('Goals'));
      await tester.pumpAndSettle();
      expect(find.text('No goals yet.\nTap + to add one.'), findsOneWidget);
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

  @override
  Future<List<Event>> events(DateTime from, DateTime to, {bool keep = false}) {
    if (!signedIn()) throw SignInRequiredException();
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
}

/// Answers update_recurrence with one series, keeping what it was sent.
class _RecurrenceClient extends McpClient {
  _RecurrenceClient() : super(endpoint: Uri.parse('http://test'));

  Map<String, Object?>? arguments;

  @override
  Future<Object?> callTool(
    String name, [
    Map<String, Object?> arguments = const {},
  ]) async {
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
