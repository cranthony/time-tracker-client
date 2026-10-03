import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:time_tracker_client/models/note.dart';
import 'package:time_tracker_client/outbox/note_outbox.dart';
import 'package:time_tracker_client/outbox/outbox_store.dart';
import 'package:time_tracker_client/screens/notes_screen.dart';
import 'package:time_tracker_client/services/mcp_client.dart';
import 'package:time_tracker_client/services/notes_repository.dart';

void main() {
  late NoteOutbox outbox;

  /// Stops the outbox before flutter_test checks for pending timers.
  void screenTest(String name, Future<void> Function(WidgetTester) body) =>
      testWidgets(name, (tester) async {
        await body(tester);
        outbox.stop();
      });

  // Real today: the add-note dialog stamps notes with the real time.
  final now = DateTime.now();
  DateTime today(int hour, int minute) =>
      DateTime(now.year, now.month, now.day, hour, minute);

  /// The outbox's clock, moved along by hand with the fake timers.
  late DateTime outboxNow;
  Future<void> wait(WidgetTester tester, Duration d) async {
    outboxNow = outboxNow.add(d);
    await tester.pump(d);
    await tester.pumpAndSettle();
  }

  Widget app(
    NotesRepository repo, {
    Future<void> Function()? onSignIn,
    Future<void> Function()? onSignOut,
    Stream<DateTime>? addNoteRequests,
    String? version,
  }) {
    outboxNow = now;
    outbox = NoteOutbox(
      store: InMemoryOutboxStore(),
      repository: repo,
      clock: () => outboxNow,
    )..start();
    return MaterialApp(
      home: NotesScreen(
        repository: repo,
        outbox: outbox,
        clock: () => now,
        onSignIn: onSignIn,
        onSignOut: onSignOut,
        addNoteRequests: addNoteRequests,
        version: version,
      ),
    );
  }

  screenTest('shows when notes were last compacted, and the latest note '
      'compacted', (tester) async {
    await tester.pumpWidget(
      app(
        InMemoryNotesRepository(
          [Note(timestamp: today(9, 0), description: 'Started')],
          CompactionStatus(
            lastCompaction: DateTime(2026, 10, 2, 21, 5),
            latestCompacted: Note(
              timestamp: DateTime(2026, 10, 2, 20, 30),
              description: 'Done with dinner',
              compactionId: 'c1',
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Last compacted Oct 2, 2026, 9:05 PM'), findsOneWidget);
    expect(
      find.text(
        'Latest compacted note: Oct 2, 2026, 8:30 PM · Done with dinner',
      ),
      findsOneWidget,
    );
  });

  screenTest('says when notes were never compacted, even with none to show', (
    tester,
  ) async {
    await tester.pumpWidget(app(InMemoryNotesRepository()));
    await tester.pumpAndSettle();

    expect(find.text('Notes not compacted yet'), findsOneWidget);
    expect(
      find.text('No uncompacted notes.\nTap + to add one.'),
      findsOneWidget,
    );
  });

  test('CompactionStatus.fromJson reads get_compaction_status', () {
    final status = CompactionStatus.fromJson({
      'last_compaction': '2026-10-02T21:05:00-04:00',
      'latest_compacted_note': {
        'timestamp': '2026-10-02T20:30:00-04:00',
        'description': 'Done with dinner',
        'compaction_id': 'c1',
      },
    });
    expect(status.lastCompaction, DateTime.utc(2026, 10, 3, 1, 5));
    expect(status.latestCompacted?.description, 'Done with dinner');
    expect(CompactionStatus.fromJson({}).lastCompaction, isNull);
  });

  screenTest('shows all uncompacted notes, by day', (tester) async {
    final repo = InMemoryNotesRepository([
      Note(timestamp: today(9, 30), description: 'Standup'),
      Note(
        timestamp: today(18, 0).subtract(const Duration(days: 1)),
        description: 'Yesterday evening',
      ),
      Note(
        timestamp: today(8, 0).subtract(const Duration(days: 3)),
        description: 'Days ago',
      ),
      Note(
        timestamp: today(11, 0),
        description: 'Compacted',
        compactionId: 'c1',
      ),
      Note(timestamp: today(13, 0)),
    ]);
    await tester.pumpWidget(app(repo));
    await tester.pumpAndSettle();

    expect(find.text('Compacted'), findsNothing);
    final threeDaysAgo = MaterialLocalizations.of(
      tester.element(find.text('Standup')),
    ).formatMediumDate(today(8, 0).subtract(const Duration(days: 3)));
    // Oldest first, each day under its heading.
    final order = [
      threeDaysAgo,
      'Days ago',
      'Yesterday',
      'Yesterday evening',
      'Today',
      'Standup',
      '(no description)',
    ];
    final ys = [for (final t in order) tester.getTopLeft(find.text(t)).dy];
    expect(ys, [...ys]..sort());
  });

  screenTest('shows an empty state', (tester) async {
    await tester.pumpWidget(app(InMemoryNotesRepository()));
    await tester.pumpAndSettle();
    expect(find.textContaining('No uncompacted notes'), findsOneWidget);
  });

  Future<void> addNote(WidgetTester tester, String text) async {
    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), text);
    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();
  }

  screenTest('+ adds a note', (tester) async {
    final repo = InMemoryNotesRepository();
    await tester.pumpWidget(app(repo));
    await tester.pumpAndSettle();

    await addNote(tester, 'Writing Flutter app');

    expect(
      (await repo.uncompactedNotes()).single.description,
      'Writing Flutter app',
    );
    expect(find.text('Writing Flutter app'), findsOneWidget);
    expect(find.byTooltip('Cancel note'), findsNothing);
  });

  screenTest('keeps an unsaved note on screen and retries it', (tester) async {
    final repo = _FlakyRepository()..offline = true;
    await tester.pumpWidget(app(repo));
    await tester.pumpAndSettle();

    await addNote(tester, 'On the train');

    expect(find.text('On the train'), findsOneWidget);
    expect(find.textContaining('Not saved'), findsOneWidget);
    expect(find.byTooltip('Cancel note'), findsOneWidget);

    repo.offline = false;
    await wait(tester, const Duration(seconds: 5));

    expect(find.text('On the train'), findsOneWidget);
    expect(find.textContaining('Not saved'), findsNothing);
    expect(find.byTooltip('Cancel note'), findsNothing);
    expect(await repo.uncompactedNotes(), hasLength(1));
  });

  screenTest('cancelling an unsaved note removes it, with undo', (
    tester,
  ) async {
    final repo = _FlakyRepository()..offline = true;
    await tester.pumpWidget(app(repo));
    await tester.pumpAndSettle();
    await addNote(tester, 'Never mind');

    await tester.tap(find.byTooltip('Cancel note'));
    await tester.pumpAndSettle();
    expect(find.text('Never mind'), findsNothing);
    expect(outbox.pending, isEmpty);

    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(find.text('Never mind'), findsOneWidget);
    expect(outbox.pending, hasLength(1));
  });

  screenTest('notes added while signed out are saved after sign-in', (
    tester,
  ) async {
    final repo = _SignInRepository([
      Note(timestamp: today(9, 30), description: 'Standup'),
    ]);
    await tester.pumpWidget(
      app(
        repo,
        onSignIn: () async => repo.signedIn = true,
        onSignOut: () async => repo.signedIn = false,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Sign in to see your notes.'), findsOneWidget);

    await addNote(tester, 'Offline thought');
    expect(find.text('Not saved · sign in to save'), findsOneWidget);

    await tester.tap(find.text('Sign in'));
    await tester.pumpAndSettle();
    expect(find.text('Standup'), findsOneWidget);
    expect(find.text('Offline thought'), findsOneWidget);
    expect(find.textContaining('Not saved'), findsNothing);
    expect(await repo.uncompactedNotes(), hasLength(2));
  });

  screenTest('tapping a note edits it', (tester) async {
    final repo = InMemoryNotesRepository([
      Note(timestamp: today(9, 30), description: 'Standup'),
    ]);
    await tester.pumpWidget(app(repo));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Standup'));
    await tester.pumpAndSettle();
    expect(find.text('Edit note'), findsOneWidget);
    expect(find.text('9:30 AM'), findsWidgets);
    await tester.enterText(find.byType(TextField), 'Standup, ran long');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    final saved = (await repo.uncompactedNotes()).single;
    expect(saved.description, 'Standup, ran long');
    expect(saved.timestamp, today(9, 30));
    expect(find.text('Standup, ran long'), findsOneWidget);
  });

  screenTest('clearing a note\'s description removes it', (tester) async {
    final repo = InMemoryNotesRepository([
      Note(timestamp: today(9, 30), description: 'Standup'),
    ]);
    await tester.pumpWidget(app(repo));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Standup'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '  ');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect((await repo.uncompactedNotes()).single.description, isNull);
    expect(find.text('(no description)'), findsOneWidget);
  });

  screenTest('deleting a note removes it, with undo', (tester) async {
    final repo = InMemoryNotesRepository([
      Note(timestamp: today(9, 30), description: 'Standup'),
    ]);
    await tester.pumpWidget(app(repo));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Standup'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Delete note'));
    await tester.pumpAndSettle();

    expect(await repo.uncompactedNotes(), isEmpty);
    expect(find.text('Standup'), findsNothing);
    expect(find.text('Note deleted'), findsOneWidget);

    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    final restored = (await repo.uncompactedNotes()).single;
    expect(restored.description, 'Standup');
    expect(restored.timestamp, today(9, 30));
    expect(find.text('Standup'), findsOneWidget);
  });

  screenTest('a failed edit says why and keeps the note', (tester) async {
    final repo = _FailingEditsRepository([
      Note(timestamp: today(9, 30), description: 'Standup'),
    ]);
    await tester.pumpWidget(app(repo));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Standup'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Changed');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(
      find.text('Could not change the note: That note was compacted'),
      findsOneWidget,
    );
    expect(find.text('Standup'), findsOneWidget);
  });

  screenTest('About shows the app\'s version and server', (tester) async {
    await tester.pumpWidget(
      app(InMemoryNotesRepository(), version: '1.1.0 (25)'),
    );
    await tester.pumpAndSettle();
    // Only in About, not taking up room on the notes screen.
    expect(find.textContaining('offline demo'), findsNothing);

    await tester.tap(find.byTooltip('Show menu'));
    await tester.pumpAndSettle();
    expect(find.text('Sign out'), findsNothing); // no sign-in here
    await tester.tap(find.text('About'));
    await tester.pumpAndSettle();

    expect(find.text('Time Tracker'), findsOneWidget);
    expect(find.text('1.1.0 (25)'), findsOneWidget);
    expect(find.text('Server: offline demo'), findsOneWidget);
  });

  screenTest('the home screen "+" opens the dialog at the time it was tapped', (
    tester,
  ) async {
    final repo = InMemoryNotesRepository();
    final taps = StreamController<DateTime>();
    await tester.pumpWidget(app(repo, addNoteRequests: taps.stream));
    await tester.pumpAndSettle();

    final tappedAt = today(7, 5);
    taps.add(tappedAt);
    // A second tap while the dialog is open doesn't stack another one.
    taps.add(today(7, 6));
    await tester.pumpAndSettle();

    expect(find.text('New note'), findsOneWidget);
    expect(find.text('7:05 AM'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'Woke up');
    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();

    final saved = (await repo.uncompactedNotes()).single;
    expect(saved.description, 'Woke up');
    expect(saved.timestamp, tappedAt);
    await taps.close();
  });
}

class _SignInRepository extends InMemoryNotesRepository {
  _SignInRepository(super.notes);
  bool signedIn = false;

  @override
  Future<List<Note>> uncompactedNotes() async {
    if (!signedIn) throw SignInRequiredException();
    return super.uncompactedNotes();
  }

  @override
  Future<Note> addNote(Note note) async {
    if (!signedIn) throw SignInRequiredException();
    return super.addNote(note);
  }
}

class _FlakyRepository extends InMemoryNotesRepository {
  bool offline = false;

  @override
  Future<Note> addNote(Note note) async {
    if (offline) throw McpException('offline');
    return super.addNote(note);
  }
}

class _FailingEditsRepository extends InMemoryNotesRepository {
  _FailingEditsRepository(super.notes);

  @override
  Future<Note> editNote(
    String id, {
    DateTime? timestamp,
    String? description,
  }) async =>
      throw McpException('Tool edit_note failed: That note was compacted');
}
