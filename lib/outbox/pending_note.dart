import '../models/note.dart';
import 'outbox.dart';

/// What a [PendingNote] does to the notes on the server.
enum NoteChange {
  /// Adds [PendingNote.note].
  add,

  /// Changes the note [PendingNote.original] to [PendingNote.note].
  edit,

  /// Deletes the note [PendingNote.original].
  delete,
}

/// A change to the notes that hasn't been saved to the server yet: a new
/// note, or an edit or deletion of one there.
class PendingNote implements OutboxItem<PendingNote> {
  const PendingNote({
    required this.id,
    required this.note,
    this.change = NoteChange.add,
    this.original,
    this.attempts = 0,
    this.lastError,
    this.nextAttemptAt,
    this.sendingSince,
    this.sentBy,
    this.refused = false,
  });

  @override
  final String id;

  /// The note added; for an edit, the note as it's changed to; for a
  /// deletion, the note deleted.
  final Note note;
  final NoteChange change;

  /// For an edit or a deletion, the note on the server, as it was: its id
  /// is the one changed.
  final Note? original;

  /// The id, on the server, of the note an edit or a deletion is of.
  String? get noteId => original?.id;

  @override
  final int attempts;
  @override
  final String? lastError;
  @override
  final DateTime? nextAttemptAt;
  @override
  final DateTime? sendingSince;
  @override
  final String? sentBy;

  /// Whether the server refused an edit or a deletion: the note was
  /// compacted, say. A new note is never refused: every failure is tried
  /// again.
  @override
  final bool refused;

  @override
  PendingNote copyWith({
    int? attempts,
    String? Function()? lastError,
    DateTime? Function()? nextAttemptAt,
    DateTime? Function()? sendingSince,
    String? Function()? sentBy,
    bool? refused,
  }) => PendingNote(
    id: id,
    note: note,
    change: change,
    original: original,
    attempts: attempts ?? this.attempts,
    lastError: lastError == null ? this.lastError : lastError(),
    nextAttemptAt: nextAttemptAt == null ? this.nextAttemptAt : nextAttemptAt(),
    sendingSince: sendingSince == null ? this.sendingSince : sendingSince(),
    sentBy: sentBy == null ? this.sentBy : sentBy(),
    refused: refused ?? this.refused,
  );

  factory PendingNote.fromJson(Map<String, dynamic> json) => PendingNote(
    id: json['id'] as String,
    note: Note.fromJson((json['note'] as Map).cast<String, dynamic>()),
    // None from a version that only added notes.
    change: NoteChange.values.asNameMap()[json['change']] ?? NoteChange.add,
    original: switch (json['original']) {
      final Map original => Note.fromJson(original.cast<String, dynamic>()),
      _ => null,
    },
    attempts: json['attempts'] as int? ?? 0,
    lastError: json['last_error'] as String?,
    nextAttemptAt: _date(json['next_attempt_at']),
    sendingSince: _date(json['sending_since']),
    sentBy: json['sent_by'] as String?,
    refused: json['refused'] as bool? ?? false,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'note': note.toJson(),
    if (change != NoteChange.add) 'change': change.name,
    // With its id, which Note.toJson leaves out.
    if (original case final original?)
      'original': {...original.toJson(), 'id': original.id},
    'attempts': attempts,
    'last_error': ?lastError,
    'next_attempt_at': ?nextAttemptAt?.toUtc().toIso8601String(),
    'sending_since': ?sendingSince?.toUtc().toIso8601String(),
    'sent_by': ?sentBy,
    if (refused) 'refused': true,
  };

  static DateTime? _date(Object? value) =>
      value == null ? null : DateTime.parse(value as String);
}
