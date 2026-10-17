import '../models/note.dart';
import 'pending_write.dart';

/// What a [PendingNote] does to the notes on the server.
enum NoteChange {
  /// Adds [PendingNote.note].
  add,

  /// Changes the note [PendingNote.original] to [PendingNote.note].
  edit,

  /// Deletes the note [PendingNote.original].
  delete,
}

/// A change to the notes that hasn't been saved to the server yet -- a
/// new note, or an edit or deletion of one there -- as the notes page
/// shows it: a [write] waiting in the [WriteQueue], or that failed.
class PendingNote {
  const PendingNote({
    required this.write,
    required this.note,
    this.change = NoteChange.add,
    this.original,
  });

  /// The write it is.
  final PendingWrite write;

  String get id => write.id;

  /// The note added -- with the id the app gave it; for an edit, the note
  /// as it's changed to; for a deletion, the note deleted.
  final Note note;
  final NoteChange change;

  /// For an edit or a deletion, the note on the server, as it was: its id
  /// is the one changed.
  final Note? original;

  /// The id, on the server, of the note an edit or a deletion is of.
  String? get noteId => original?.id;

  int get attempts => write.attempts;
  String? get lastError => write.lastError;

  /// Whether the server refused it: an edit of a note compacted since,
  /// say. It waits to be retried or cancelled.
  bool get refused => write.refused;
}
