import '../models/note.dart';

/// A note that hasn't been saved to the server yet.
class PendingNote {
  const PendingNote({
    required this.id,
    required this.note,
    this.attempts = 0,
    this.lastError,
    this.nextAttemptAt,
    this.sendingSince,
  });

  /// Local only; the server knows nothing about it.
  final String id;
  final Note note;

  /// Failed attempts so far. Once non-zero, an earlier attempt may have
  /// reached the server even though we never heard back, so the next
  /// attempt checks for that before sending again.
  final int attempts;
  final String? lastError;

  /// When to try again; null means as soon as possible.
  final DateTime? nextAttemptAt;

  /// Set while some sender (this app, or its background task) has a
  /// request for this note in flight.
  final DateTime? sendingSince;

  PendingNote copyWith({
    int? attempts,
    String? Function()? lastError,
    DateTime? Function()? nextAttemptAt,
    DateTime? Function()? sendingSince,
  }) => PendingNote(
    id: id,
    note: note,
    attempts: attempts ?? this.attempts,
    lastError: lastError == null ? this.lastError : lastError(),
    nextAttemptAt: nextAttemptAt == null ? this.nextAttemptAt : nextAttemptAt(),
    sendingSince: sendingSince == null ? this.sendingSince : sendingSince(),
  );

  factory PendingNote.fromJson(Map<String, dynamic> json) => PendingNote(
    id: json['id'] as String,
    note: Note.fromJson((json['note'] as Map).cast<String, dynamic>()),
    attempts: json['attempts'] as int? ?? 0,
    lastError: json['last_error'] as String?,
    nextAttemptAt: _date(json['next_attempt_at']),
    sendingSince: _date(json['sending_since']),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'note': note.toJson(),
    'attempts': attempts,
    'last_error': ?lastError,
    'next_attempt_at': ?nextAttemptAt?.toUtc().toIso8601String(),
    'sending_since': ?sendingSince?.toUtc().toIso8601String(),
  };

  static DateTime? _date(Object? value) =>
      value == null ? null : DateTime.parse(value as String);
}
