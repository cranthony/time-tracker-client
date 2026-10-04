import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../models/note.dart';
import '../services/notes_repository.dart';
import 'outbox.dart';
import 'pending_note.dart';

export 'outbox.dart' show FlushResult;

/// Notes waiting to be saved to the server: an [Outbox] of them, sent
/// oldest first, retrying with backoff until they're saved or cancelled.
///
/// Call [start] to have it send by itself while the app is in use, and
/// [stop] when the app goes to the background. The Android background task
/// uses its own instance and calls [flush] instead.
class NoteOutbox extends Outbox<PendingNote, void> {
  NoteOutbox({
    required super.store,
    required this._repository,
    super.clock,
    Random? random,
  }) : _random = random ?? Random();

  final NotesRepository _repository;
  final Random _random;

  static const inFlightTimeout = Outbox.inFlightTimeout;
  static const requestTimeout = Outbox.requestTimeout;
  static const storeTimeout = Outbox.storeTimeout;
  static Duration backoff(int attempts) => Outbox.backoff(attempts);

  /// Oldest first.
  List<PendingNote> get pending => items;

  /// Called after each note is saved.
  VoidCallback? onSaved;

  /// The uncompacted notes, fetched at most once a round, to check
  /// whether a note was saved already.
  List<Note>? _onServer;

  Future<PendingNote> add(Note note) async {
    final pending = PendingNote(
      id: '${now().microsecondsSinceEpoch}-${_random.nextInt(0x7fffffff)}',
      // Whole seconds, so the note can be recognised if the server stores
      // it with less precision (see _alreadySaved).
      note: Note(
        timestamp: _truncateToSeconds(note.timestamp),
        description: note.description,
      ),
    );
    await change((notes) => [...notes, pending]);
    schedule(immediately: true);
    return pending;
  }

  /// Drops [note] without sending it. Returns false if it's being sent.
  Future<bool> cancel(PendingNote note) async {
    if (isSending(note)) return false;
    await change((notes) => notes.where((n) => n.id != note.id).toList());
    schedule();
    return true;
  }

  /// Puts back a note removed by [cancel].
  Future<void> restore(PendingNote note) async {
    await change((notes) => [...notes, note]);
    schedule(immediately: true);
  }

  @override
  List<PendingNote> order(List<PendingNote> items) =>
      items..sort((a, b) => a.note.timestamp.compareTo(b.note.timestamp));

  @override
  void flushStarting() => _onServer = null;

  @override
  Future<void> send(PendingNote item, {required bool maybeSaved}) async {
    if (maybeSaved) {
      _onServer ??= await _repository.uncompactedNotes().timeout(
        Outbox.requestTimeout,
      );
    }
    final onServer = _onServer;
    if (onServer == null || !_alreadySaved(item.note, onServer)) {
      await _repository.addNote(item.note).timeout(Outbox.requestTimeout);
    }
  }

  @override
  void saved(PendingNote item, void result) => onSaved?.call();

  /// Whether an earlier attempt already saved [note], but we never heard.
  static bool _alreadySaved(Note note, List<Note> onServer) => onServer.any(
    (n) =>
        (n.description ?? '') == (note.description ?? '') &&
        n.timestamp.difference(note.timestamp).abs() <
            const Duration(seconds: 1),
  );

  static DateTime _truncateToSeconds(DateTime t) => t.subtract(
    Duration(microseconds: t.microsecond, milliseconds: t.millisecond),
  );
}
