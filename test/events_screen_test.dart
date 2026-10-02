import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:time_tracker_client/models/event.dart';
import 'package:time_tracker_client/models/event_label.dart';
import 'package:time_tracker_client/models/note.dart';
import 'package:time_tracker_client/outbox/note_outbox.dart';
import 'package:time_tracker_client/outbox/outbox_store.dart';
import 'package:time_tracker_client/screens/events_screen.dart';
import 'package:time_tracker_client/screens/home_screen.dart';
import 'package:time_tracker_client/services/event_labels_repository.dart';
import 'package:time_tracker_client/services/events_repository.dart';
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
    EventLabelsRepository? labels,
  }) => MaterialApp(
    home: EventsScreen(
      repository: repo,
      serverLabel: 'offline demo',
      labelsRepository: labels,
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
    // By start time; one that began the day before shows its date.
    final summaries = tester
        .widgetList<ListTile>(find.byType(ListTile))
        .map((t) => (t.title as Text).data)
        .toList();
    expect(summaries, ['Sleep', 'Work', 'Lunch']);
    expect(find.text('Sep 29, 11:00 PM – 7:00 AM'), findsOneWidget);
    expect(find.text('9:00 AM – 10:30 AM'), findsOneWidget);
    expect(find.text('Dinner'), findsNothing);

    await tester.tap(find.byTooltip('Previous day'));
    await tester.pumpAndSettle();
    expect(find.text('Yesterday'), findsOneWidget);
    expect(find.text('Dinner'), findsOneWidget);
    expect(find.text('Sleep'), findsOneWidget);
    expect(find.text('6:00 PM – 7:00 PM'), findsOneWidget);
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
      'event_label_id': 'l1',
      'min_duration': 'PT1H',
      'priority': 2,
      'is_fixed_time': false,
      'is_cancelled': false,
    });

    Future<void> openWork(WidgetTester tester, EventsRepository repo) async {
      await tester.pumpWidget(
        app(
          repo,
          labels: InMemoryEventLabelsRepository([
            const EventLabel(id: 'l1', name: 'Work', priority: 1),
            const EventLabel(id: 'l2', name: 'Exercise', priority: 2),
          ]),
        ),
      );
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

    testWidgets('picks a label by name', (tester) async {
      final repo = _RecordingRepository([work()]);
      await openWork(tester, repo);
      await edit(tester, inDialog(find.text('l1')));
      await tester.tap(find.byType(DropdownButton<String?>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Exercise').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Keep edit'));
      await tester.pumpAndSettle();
      // Names, now that they're loaded.
      expect(inDialog(find.text('Exercise')), findsOneWidget);
      await tester.tap(find.text('Save 1 change'));
      await tester.pumpAndSettle();
      expect(repo.saved, [
        {'event_label_id': 'l2'},
      ]);
    });

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
          eventLabelsRepository: InMemoryEventLabelsRepository(),
          outbox: outbox,
          addNoteRequests: addNoteRequests,
        ),
      );
    }

    testWidgets('opens on Notes, and switches to Events and Labels', (
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

      await tester.tap(find.text('Labels'));
      await tester.pumpAndSettle();
      expect(find.text('No event labels.'), findsOneWidget);
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
