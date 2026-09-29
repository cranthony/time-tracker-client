import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:time_tracker_client/models/note.dart';
import 'package:time_tracker_client/outbox/note_outbox.dart';
import 'package:time_tracker_client/outbox/outbox_store.dart';
import 'package:time_tracker_client/screens/today_screen.dart';
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
  }) {
    outboxNow = now;
    outbox = NoteOutbox(
      store: InMemoryOutboxStore(),
      repository: repo,
      clock: () => outboxNow,
    )..start();
    return MaterialApp(
      home: TodayScreen(
        repository: repo,
        outbox: outbox,
        clock: () => now,
        onSignIn: onSignIn,
        onSignOut: onSignOut,
      ),
    );
  }

  screenTest('shows only today\'s uncompacted notes', (tester) async {
    final repo = InMemoryNotesRepository([
      Note(timestamp: today(9, 30), description: 'Standup'),
      Note(
        timestamp: today(18, 0).subtract(const Duration(days: 1)),
        description: 'Yesterday',
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

    expect(find.text('Standup'), findsOneWidget);
    expect(find.text('(no description)'), findsOneWidget);
    expect(find.text('Yesterday'), findsNothing);
    expect(find.text('Compacted'), findsNothing);
  });

  screenTest('shows an empty state', (tester) async {
    await tester.pumpWidget(app(InMemoryNotesRepository()));
    await tester.pumpAndSettle();
    expect(find.textContaining('No notes yet today'), findsOneWidget);
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
