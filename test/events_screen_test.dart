import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:time_tracker_client/models/event.dart';
import 'package:time_tracker_client/models/note.dart';
import 'package:time_tracker_client/outbox/note_outbox.dart';
import 'package:time_tracker_client/outbox/outbox_store.dart';
import 'package:time_tracker_client/screens/events_screen.dart';
import 'package:time_tracker_client/screens/home_screen.dart';
import 'package:time_tracker_client/services/event_labels_repository.dart';
import 'package:time_tracker_client/services/events_repository.dart';
import 'package:time_tracker_client/services/mcp_client.dart';
import 'package:time_tracker_client/services/notes_repository.dart';

void main() {
  final now = DateTime(2026, 9, 30, 12);
  DateTime at(int day, int hour, [int minute = 0]) =>
      DateTime(2026, 9, day, hour, minute);

  Widget app(EventsRepository repo, {Future<void> Function()? onSignIn}) =>
      MaterialApp(
        home: EventsScreen(
          repository: repo,
          serverLabel: 'offline demo',
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
    expect(valueOf('min_duration'), 'PT1H');
    expect(valueOf('priority'), '1');
    expect(valueOf('is_cancelled'), 'false');
    // Ones the app doesn't know about yet too.
    expect(valueOf('is_end_of_day_sleep'), 'true');

    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    expect(dialog, findsNothing);
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
  Future<List<Event>> events(DateTime from, DateTime to) {
    if (!signedIn()) throw SignInRequiredException();
    return super.events(from, to);
  }
}
