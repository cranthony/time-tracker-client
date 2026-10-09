import '../models/note.dart';
import 'outbox.dart';

/// A note that hasn't been saved to the server yet.
class PendingNote implements OutboxItem<PendingNote> {
  const PendingNote({
    required this.id,
    required this.note,
    this.attempts = 0,
    this.lastError,
    this.nextAttemptAt,
    this.sendingSince,
    this.sentBy,
    this.refused = false,
  });

  @override
  final String id;
  final Note note;

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

  /// Never, as notes are sent: every failure is tried again.
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
