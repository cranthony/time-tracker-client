import 'dart:async';
import 'dart:math';

import '../models/note.dart';
import '../services/server_errors.dart';
import '../services/notes_repository.dart';
import 'outbox.dart';
import 'pending_note.dart';

export 'outbox.dart' show FlushResult;

/// Changes to the notes waiting to be saved to the server -- new notes,
/// and edits and deletions of notes there: an [Outbox] of them, sent
/// oldest first, retrying with backoff until they're saved or cancelled.
/// An edit or a deletion the server refuses (the note was compacted, say)
/// waits, refused, to be cancelled or retried.
///
/// Call [start] to have it send by itself while the app is in use, and
/// [stop] when the app goes to the background. The Android background task
/// uses its own instance and calls [flush] instead.
class NoteOutbox extends Outbox<PendingNote, void> {
  NoteOutbox({
    required super.store,
    required this._repository,
    super.clock,
    super.sender,
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

  /// The uncompacted notes, fetched at most once a round, to check
  /// whether a note was saved already.
  List<Note>? _onServer;

  String _newId() =>
      '${now().microsecondsSinceEpoch}-${_random.nextInt(0x7fffffff)}';

  Future<PendingNote> add(Note note) async {
    final pending = PendingNote(
      id: _newId(),
      // Whole seconds, so the note can be recognised if the server stores
      // it with less precision (see savedIn).
      note: Note(
        timestamp: _truncateToSeconds(note.timestamp),
        description: note.description,
      ),
    );
    await change((notes) => [...notes, pending]);
    schedule(immediately: true);
    return pending;
  }

  /// Queues changing [original], a note on the server, to [edited]: in
  /// place of an edit of it still waiting, and from the note as the
  /// server had it then. Changed back to how it was, nothing waits. Gives
  /// the edit waiting, if any.
  Future<PendingNote?> edit(Note original, Note edited) async {
    PendingNote? queued;
    await change((items) {
      final waiting = _waiting(items, NoteChange.edit, original.id);
      final from = waiting?.original ?? original;
      final same =
          edited.timestamp.isAtSameMomentAs(from.timestamp) &&
          (edited.description ?? '') == (from.description ?? '');
      queued = same
          ? null
          : PendingNote(
              id: waiting?.id ?? _newId(),
              note: Note(
                timestamp: edited.timestamp,
                description: edited.description,
                id: from.id,
              ),
              change: NoteChange.edit,
              original: from,
            );
      return [
        for (final item in items)
          if (item.id != waiting?.id) item,
        ?queued,
      ];
    });
    schedule(immediately: true);
    return queued;
  }

  /// Queues deleting [original], a note on the server: in place of any
  /// edit of it still waiting.
  Future<PendingNote> delete(Note original) async {
    late PendingNote queued;
    await change((items) {
      final edit = _waiting(items, NoteChange.edit, original.id);
      final already = _waiting(items, NoteChange.delete, original.id);
      queued =
          already ??
          PendingNote(
            id: _newId(),
            note: edit?.original ?? original,
            change: NoteChange.delete,
            original: edit?.original ?? original,
          );
      return [
        for (final item in items)
          if (item.id != edit?.id && item.id != already?.id) item,
        queued,
      ];
    });
    schedule(immediately: true);
    return queued;
  }

  /// The [kind] of change to the note [noteId] waiting in [items], and not
  /// being sent, if there is one.
  PendingNote? _waiting(
    List<PendingNote> items,
    NoteChange kind,
    String? noteId,
  ) => items
      .where(
        (item) =>
            item.change == kind && item.noteId == noteId && !isSending(item),
      )
      .firstOrNull;

  /// Drops [note] without sending it. Returns false if it's being sent.
  Future<bool> cancel(PendingNote note) async {
    if (isSending(note)) return false;
    if (!await removeUnlessSending(note.id)) return false;
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

  /// Whether what's being sent is an edit or a deletion, which the server
  /// may refuse.
  bool _sendingChange = false;

  @override
  bool retries(Object error) =>
      !_sendingChange ||
      describeServerError(error).kind != FailureKind.refused;

  Future<List<Note>> _fetchOnServer() async => _onServer ??= await _repository
      .uncompactedNotes()
      .timeout(Outbox.requestTimeout);

  @override
  Future<void> send(PendingNote item, {required bool maybeSaved}) async {
    _sendingChange = item.change != NoteChange.add;
    switch (item.change) {
      case NoteChange.add:
        if (maybeSaved) await _fetchOnServer();
        final onServer = _onServer;
        if (onServer == null || !savedIn(item.note, onServer)) {
          await _repository.addNote(item.note).timeout(Outbox.requestTimeout);
        }
      case NoteChange.edit:
        // The same edit again does no harm.
        final original = item.original!;
        final retimed = !item.note.timestamp.isAtSameMomentAs(
          original.timestamp,
        );
        final described =
            (item.note.description ?? '') != (original.description ?? '');
        if (!retimed && !described) return;
        await _repository
            .editNote(
              item.noteId!,
              timestamp: retimed ? item.note.timestamp : null,
              // An empty description clears it.
              description: described ? item.note.description ?? '' : null,
            )
            .timeout(Outbox.requestTimeout);
      case NoteChange.delete:
        // Gone already: an earlier attempt deleted it, unheard.
        if (maybeSaved &&
            !(await _fetchOnServer()).any((n) => n.id == item.noteId)) {
          return;
        }
        await _repository
            .deleteNote(item.noteId!)
            .timeout(Outbox.requestTimeout);
    }
  }

  /// Whether [onServer] has [note]: an earlier attempt saved it, but we
  /// never heard, or it's been fetched since it was saved.
  static bool savedIn(Note note, List<Note> onServer) => onServer.any(
    (n) =>
        (n.description ?? '') == (note.description ?? '') &&
        n.timestamp.difference(note.timestamp).abs() <
            const Duration(seconds: 1),
  );

  static DateTime _truncateToSeconds(DateTime t) => t.subtract(
    Duration(microseconds: t.microsecond, milliseconds: t.millisecond),
  );
}
