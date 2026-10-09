import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:time_tracker_client/models/note.dart';
import 'package:time_tracker_client/outbox/note_outbox.dart';
import 'package:time_tracker_client/outbox/outbox.dart';
import 'package:time_tracker_client/outbox/outbox_store.dart';
import 'package:time_tracker_client/outbox/pending_note.dart';
import 'package:time_tracker_client/services/mcp_client.dart';
import 'package:time_tracker_client/services/notes_repository.dart';

/// A server that can be taken offline, or made to lose its responses.
class FlakyRepository extends InMemoryNotesRepository {
  bool offline = false;
  bool signedOut = false;

  /// Saves the note, then fails as if the response never arrived.
  bool loseResponses = false;
  int addCalls = 0;

  @override
  Future<List<Note>> uncompactedNotes() async {
    _check();
    return super.uncompactedNotes();
  }

  @override
  Future<Note> addNote(Note note) async {
    addCalls++;
    _check();
    await super.addNote(note);
    if (loseResponses) throw McpException('connection reset');
    return note;
  }

  void _check() {
    if (signedOut) throw SignInRequiredException();
    if (offline) throw McpException('offline');
  }
}

void main() {
  late FlakyRepository server;
  late InMemoryOutboxStore<PendingNote> store;
  late DateTime now;

  NoteOutbox outbox() =>
      NoteOutbox(store: store, repository: server, clock: () => now);

  final note = Note(
    timestamp: DateTime.utc(2026, 9, 29, 9, 30, 12, 345, 678),
    description: 'Standup',
  );

  setUp(() {
    server = FlakyRepository();
    store = InMemoryOutboxStore();
    now = DateTime.utc(2026, 9, 29, 10);
  });

  test('saves a note and forgets it', () async {
    final box = outbox();
    await box.add(note);
    expect(box.pending, hasLength(1));

    final result = await box.flush();

    expect(result.remaining, 0);
    expect(box.pending, isEmpty);
    expect(store.items, isEmpty);
    final saved = (await server.uncompactedNotes()).single;
    expect(saved.description, 'Standup');
    // Truncated to whole seconds.
    expect(saved.timestamp, DateTime.utc(2026, 9, 29, 9, 30, 12));
  });

  test('keeps unsaved notes for the next run of the app', () async {
    server.offline = true;
    await outbox().add(note);
    await outbox().flush();

    final restarted = outbox();
    await restarted.refresh();
    expect(restarted.pending.single.note.description, 'Standup');
  });

  test('backs off after a failure, then retries', () async {
    server.offline = true;
    final box = outbox();
    await box.add(note);
    await box.flush();

    final failed = box.pending.single;
    expect(failed.attempts, 1);
    expect(failed.lastError, 'offline');
    expect(failed.nextAttemptAt, now.add(const Duration(seconds: 5)));

    server.offline = false;
    await box.flush();
    expect(box.pending, hasLength(1), reason: 'not due yet');

    now = now.add(const Duration(seconds: 5));
    await box.flush();
    expect(box.pending, isEmpty);
  });

  test('backoff doubles up to a minute', () {
    expect(
      [for (var i = 1; i <= 6; i++) NoteOutbox.backoff(i).inSeconds],
      [5, 10, 20, 40, 60, 60],
    );
  });

  test('does not save twice when a response was lost', () async {
    server.loseResponses = true;
    final box = outbox();
    await box.add(note);
    await box.flush();
    expect(box.pending.single.attempts, 1);

    server.loseResponses = false;
    await box.flush(ignoreBackoff: true);

    expect(box.pending, isEmpty);
    expect(await server.uncompactedNotes(), hasLength(1));
    expect(server.addCalls, 1, reason: 'found on the server instead');
  });

  test('waits for sign-in without counting attempts', () async {
    server.signedOut = true;
    final box = outbox();
    await box.add(note);
    final result = await box.flush();

    expect(result.needsSignIn, isTrue);
    expect(box.needsSignIn, isTrue);
    expect(box.pending.single.attempts, 0);

    server.signedOut = false;
    await box.retryNow();
    expect(box.needsSignIn, isFalse);
    expect(box.pending, isEmpty);
  });

  test('sends oldest first, and stops at the first failure', () async {
    final box = outbox();
    await box.add(Note(timestamp: DateTime.utc(2026, 9, 29, 11)));
    await box.add(Note(timestamp: DateTime.utc(2026, 9, 29, 8)));
    server.offline = true;
    await box.flush();

    expect(server.addCalls, 1);
    expect(box.pending.first.note.timestamp.hour, 8);
    expect(box.pending.first.attempts, 1);
    expect(box.pending.last.attempts, 0);
  });

  test('leaves a note alone while another sender has it in flight', () async {
    store.items = [PendingNote(id: 'a', note: note, sendingSince: now)];
    final box = outbox();
    await box.flush(ignoreBackoff: true);
    expect(server.addCalls, 0);
    await box.refresh();
    expect(box.isSending(box.pending.single), isTrue);
    expect(await box.cancel(box.pending.single), isFalse);

    // That sender evidently died.
    now = now.add(NoteOutbox.inFlightTimeout);
    await box.flush();
    expect(box.pending, isEmpty);
  });

  test('takes over an abandoned note without saving it twice', () async {
    // The background task saved it, then was stopped before it could say
    // so: no failed attempts, just its stale claim.
    await server.addNote(note);
    store.items = [
      PendingNote(
        id: 'a',
        note: note,
        sendingSince: now.subtract(NoteOutbox.inFlightTimeout),
      ),
    ];
    final box = outbox();
    await box.flush();
    expect(box.pending, isEmpty);
    expect(server.addCalls, 1); // Only the background task's.
    expect(await server.uncompactedNotes(), hasLength(1));
  });

  test('a store that fails while claiming a note doesn\'t leave it '
      'saving', () async {
    final failing = _FailingStore()..items = [PendingNote(id: 'a', note: note)];
    store = failing;
    final box = outbox();
    failing.failSaves = true;
    final result = await box.flush();
    expect(result.remaining, 1);
    expect(box.isSending(box.pending.single), isFalse);
    expect(server.addCalls, 0);

    failing.failSaves = false;
    await box.flush();
    expect(box.pending, isEmpty);
    expect(server.addCalls, 1);
  });

  testWidgets('a store that never answers doesn\'t hold up later changes', (
    tester,
  ) async {
    final hanging = _FailingStore()..items = [PendingNote(id: 'a', note: note)];
    store = hanging;
    final box = outbox();
    hanging.hang = true;
    FlushResult? result;
    box.flush().then((r) => result = r);
    await tester.pump(NoteOutbox.storeTimeout);
    expect(result, isNotNull);

    hanging.hang = false;
    await tester.runAsync(() => box.flush());
    expect(box.pending, isEmpty);
    expect(server.addCalls, 1);
  });

  test('cancel drops a note; restore brings it back', () async {
    server.offline = true;
    final box = outbox();
    final pending = await box.add(note);

    expect(await box.cancel(pending), isTrue);
    expect(box.pending, isEmpty);
    expect(store.items, isEmpty);

    await box.restore(pending);
    expect(box.pending.single.id, pending.id);
  });

  test('PrefsOutboxStore round-trips', () async {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    final prefs = PrefsOutboxStore.notes();
    final pending = PendingNote(
      id: 'x',
      note: note,
      attempts: 2,
      lastError: 'offline',
      nextAttemptAt: now,
      sendingSince: now,
      sentBy: Outbox.backgroundSender,
    );
    await prefs.save([pending]);

    final loaded = (await PrefsOutboxStore.notes().load()).single;
    expect(loaded.toJson(), pending.toJson());

    await prefs.save([]);
    expect(await prefs.load(), isEmpty);
  });
}

/// Can fail to save, or stop answering altogether.
class _FailingStore extends InMemoryOutboxStore<PendingNote> {
  bool failSaves = false;
  bool hang = false;

  @override
  Future<List<PendingNote>> load() =>
      hang ? Completer<List<PendingNote>>().future : super.load();

  @override
  Future<void> save(List<PendingNote> notes) {
    if (hang) return Completer<void>().future;
    if (failSaves) throw StateError('disk full');
    return super.save(notes);
  }
}
