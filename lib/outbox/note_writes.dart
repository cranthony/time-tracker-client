import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/note.dart';
import '../services/actions_repository.dart';
import '../services/mcp_client.dart';
import '../services/notes_repository.dart';
import 'action_writes.dart';
import 'outbox.dart';
import 'outbox_store.dart';
import 'pending_note.dart';
import 'write_queue.dart';

export 'outbox.dart' show FlushResult;
export 'pending_note.dart';

/// The notes page's writes -- new notes, and edits and deletions of notes
/// there -- kept and sent by a [WriteQueue]: the app's, which sends
/// everything else too, so each is made once, in order, and one changed
/// elsewhere since is resolved field by field. A new note takes the id
/// the app gives it. Its listeners hear whenever the queue changes.
class NoteWrites implements Listenable {
  NoteWrites(this.queue);

  /// Writes kept in [store] (in memory, unless given) and made to
  /// [repository] itself: with no server, and in tests.
  factory NoteWrites.local(
    NotesRepository repository, {
    OutboxStore<PendingWrite>? store,
    String sender = Outbox.appSender,
    DateTime Function()? clock,
  }) => NoteWrites(
    WriteQueue(
      store: store ?? InMemoryOutboxStore(),
      call: localWrites(notes: repository),
      sender: sender,
      clock: clock,
    ),
  );

  final WriteQueue queue;

  static const _kind = WriteKind.note;

  /// [item], a note as the server gives it, as a [Note].
  static Note noteOf(Map<String, Object?> item) => Note(
    timestamp: DateTime.parse(item['timestamp'] as String).toLocal(),
    description: item['description'] as String?,
    compactionId: item['compaction_id'] as String?,
    id: item['id'] as String?,
  );

  /// [note] as the server gives it.
  static Map<String, Object?> itemOf(Note note) => {
    'id': ?note.id,
    ...note.toJson(),
  };

  /// [write], a write to a note, as the page shows it; null for any other.
  static PendingNote? view(PendingWrite write) {
    if (write.kind != _kind.name) return null;
    final base = {...?write.base, 'id': write.itemId};
    final changed = {...base, ...write.changes}
      ..removeWhere((_, value) => value == null);
    Note at(Map<String, Object?> item) => item['timestamp'] is String
        ? noteOf(item)
        : Note(timestamp: DateTime(0), id: write.itemId);
    return switch (write.op) {
      WriteOp.create => PendingNote(write: write, note: at(changed)),
      WriteOp.update => PendingNote(
        write: write,
        note: at(changed),
        change: NoteChange.edit,
        original: at(base),
      ),
      WriteOp.delete => PendingNote(
        write: write,
        note: at(base),
        change: NoteChange.delete,
        original: at(base),
      ),
    };
  }

  /// Every note write waiting, being sent, or that failed, oldest first.
  List<PendingNote> get pending => [for (final w in queue.items) ?view(w)];

  /// [pending], as an outbox's items.
  List<PendingNote> get items => pending;

  /// Those saved, till a fetch started after them is in.
  List<({PendingNote item, Map<String, Object?>? result})> get justSaved => [
    for (final s in queue.justSaved)
      if (view(s.item) case final item?) (item: item, result: s.result),
  ];

  bool isSending(PendingNote note) => queue.isSending(note.write);
  String? sendingBy(PendingNote note) => queue.sendingBy(note.write);
  bool get needsSignIn => queue.needsSignIn;
  bool get wantsFetch => queue.wantsFetch;
  void Function() fetching() => queue.fetching();
  Future<FlushResult> retryNow() => queue.retryNow();

  /// Queues [note], a new one, with an id of its own. Gives it, waiting.
  Future<PendingNote> add(Note note) async {
    final id = queue.create(_kind, {
      // Whole seconds: the server keeps no more.
      'timestamp': localIsoTimestamp(_toSeconds(note.timestamp)),
      'description': ?note.description,
    });
    await queue.queued;
    return pending.lastWhere((p) => p.write.itemId == id);
  }

  /// Queues changing [original], a note on the server, to [edited]: in
  /// place of an edit of it not tried yet, and from the note as the
  /// server had it then. Changed back to how it was, nothing waits. Gives
  /// the edit waiting, if any.
  Future<PendingNote?> edit(Note original, Note edited) async {
    final id = original.id!;
    final waiting = pending
        .where(
          (p) =>
              p.change == NoteChange.edit &&
              p.noteId == id &&
              p.attempts == 0 &&
              !isSending(p),
        )
        .firstOrNull;
    final from = waiting?.original ?? original;
    final changes = <String, Object?>{
      if (!edited.timestamp.isAtSameMomentAs(from.timestamp))
        'timestamp': localIsoTimestamp(edited.timestamp),
      if ((edited.description ?? '') != (from.description ?? ''))
        'description': edited.description,
    };
    if (waiting != null) {
      if (changes.isEmpty) {
        await queue.drop(waiting.write);
        return null;
      }
      await queue.resend(waiting.write, changes: changes);
    } else {
      if (changes.isEmpty) return null;
      queue.update(_kind, id, changes, base: itemOf(original));
      await queue.queued;
    }
    return pending
        .where((p) => p.change == NoteChange.edit && p.noteId == id)
        .lastOrNull;
  }

  /// Queues deleting [original], a note on the server: in place of any
  /// edit of it not tried yet. Gives the deletion waiting.
  Future<PendingNote> delete(Note original) async {
    final id = original.id!;
    queue.delete(_kind, id, base: itemOf(original));
    await queue.queued;
    return pending.lastWhere(
      (p) => p.change == NoteChange.delete && p.noteId == id,
    );
  }

  /// Drops [note] without sending it. False if it's being sent.
  Future<bool> cancel(PendingNote note) => queue.drop(note.write);

  /// Puts back a note write [cancel] dropped.
  Future<void> restore(PendingNote note) => queue.putBack(note.write);

  /// Whether [onServer] has [note], one added: by its id, or -- one an
  /// older version added, without an id of its own -- by when it is and
  /// what it says.
  static bool savedIn(Note note, List<Note> onServer) => onServer.any(
    (n) =>
        (note.id != null && n.id == note.id) ||
        ((n.description ?? '') == (note.description ?? '') &&
            n.timestamp.difference(note.timestamp).abs() <
                const Duration(seconds: 1)),
  );

  static DateTime _toSeconds(DateTime t) => t.subtract(
    Duration(microseconds: t.microsecond, milliseconds: t.millisecond),
  );

  // As the queue's.
  void start() => queue.start();
  void stop() => queue.stop();
  Future<void> refresh() => queue.refresh();
  Future<FlushResult> flush({bool ignoreBackoff = false}) =>
      queue.flush(ignoreBackoff: ignoreBackoff);
  bool get hasUnsent => queue.hasUnsent;
  void dispose() => queue.dispose();

  @override
  void addListener(VoidCallback listener) => queue.addListener(listener);

  @override
  void removeListener(VoidCallback listener) => queue.removeListener(listener);
}

/// Makes the note writes' tool calls to [repository] itself, as the
/// server would: with no server, and in tests.
WriteCall localNoteCalls(NotesRepository repository) =>
    (tool, arguments) async {
      switch (tool) {
        case 'note':
          final item = (arguments['noted_time'] as Map).cast<String, Object?>();
          final made = await repository.addNote(NoteWrites.noteOf(item));
          return {...NoteWrites.itemOf(made), 'version': 1};
        case 'edit_note':
          final edited = await repository.editNote(
            arguments['note_id'] as String,
            timestamp: switch (arguments['timestamp']) {
              final String at => DateTime.parse(at),
              _ => null,
            },
            description: arguments['description'] as String?,
          );
          return NoteWrites.itemOf(edited);
        case 'delete_note':
          await repository.deleteNote(arguments['note_id'] as String);
          return {'id': arguments['note_id']};
      }
      throw McpException('No tool $tool here');
    };

/// Makes the writes' tool calls to [actions] and [notes] themselves, as
/// the server would: with no server, and in tests.
WriteCall localWrites({ActionsRepository? actions, NotesRepository? notes}) {
  final toActions = actions == null ? null : localActionCalls(actions);
  final toNotes = notes == null ? null : localNoteCalls(notes);
  return (tool, arguments) {
    final call = const {'note', 'edit_note', 'delete_note'}.contains(tool)
        ? toNotes
        : toActions;
    if (call == null) throw McpException('No tool $tool here');
    return call(tool, arguments);
  };
}
