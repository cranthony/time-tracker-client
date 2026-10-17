import 'outbox.dart';

/// What a [PendingWrite] does to its item.
enum WriteOp { create, update, delete }

/// One write waiting in the [WriteQueue] to be saved to the server: an
/// item of some [kind] ([WriteKind.name]) made, changed or deleted. It's
/// made once however many times it's sent by what it names -- a new item
/// by the id the app gave it -- and the version it was made to.
class PendingWrite implements OutboxItem<PendingWrite> {
  const PendingWrite({
    required this.id,
    required this.kind,
    required this.op,
    required this.itemId,
    this.changes = const {},
    this.base,
    this.conflicted = false,
    this.current,
    this.attempts = 0,
    this.lastError,
    this.nextAttemptAt,
    this.sendingSince,
    this.sentBy,
    this.refused = false,
  });

  @override
  final String id;

  /// What it writes: a [WriteKind.name].
  final String kind;
  final WriteOp op;

  /// The item's id: for a new one, the id the app gave it.
  final String itemId;

  /// A new item's fields; an update's, changed -- a null clears it. Keyed
  /// as the server takes them.
  final Map<String, Object?> changes;

  /// The item as the app last saw it, as the server gave it -- with its
  /// version -- that the changes were made to; null if it wasn't known.
  final Map<String, Object?>? base;

  /// Whether the server refused it as changed elsewhere since [base]: it
  /// waits, [refused], to be resolved.
  final bool conflicted;

  /// When [conflicted], the item as the server has it now; null if it's
  /// been deleted.
  final Map<String, Object?>? current;

  /// The version it was made from: what the server's to check it against.
  int? get baseVersion => switch (base?['version']) {
    final int version => version,
    _ => null,
  };

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
  @override
  final bool refused;

  /// It, changed: its [changes], [base], or whether it's [conflicted]
  /// (with [current]).
  PendingWrite rewritten({
    Map<String, Object?>? changes,
    Map<String, Object?>? Function()? base,
    bool? conflicted,
    Map<String, Object?>? Function()? current,
  }) => PendingWrite(
    id: id,
    kind: kind,
    op: op,
    itemId: itemId,
    changes: changes ?? this.changes,
    base: base == null ? this.base : base(),
    conflicted: conflicted ?? this.conflicted,
    current: current == null ? this.current : current(),
    attempts: attempts,
    lastError: lastError,
    nextAttemptAt: nextAttemptAt,
    sendingSince: sendingSince,
    sentBy: sentBy,
    refused: refused,
  );

  @override
  PendingWrite copyWith({
    int? attempts,
    String? Function()? lastError,
    DateTime? Function()? nextAttemptAt,
    DateTime? Function()? sendingSince,
    String? Function()? sentBy,
    bool? refused,
  }) => PendingWrite(
    id: id,
    kind: kind,
    op: op,
    itemId: itemId,
    changes: changes,
    base: base,
    // Retried, it's sent as it is: its conflict, if any, is let go.
    conflicted: refused == false ? false : conflicted,
    current: refused == false ? null : current,
    attempts: attempts ?? this.attempts,
    lastError: lastError == null ? this.lastError : lastError(),
    nextAttemptAt: nextAttemptAt == null ? this.nextAttemptAt : nextAttemptAt(),
    sendingSince: sendingSince == null ? this.sendingSince : sendingSince(),
    sentBy: sentBy == null ? this.sentBy : sentBy(),
    refused: refused ?? this.refused,
  );

  factory PendingWrite.fromJson(Map<String, dynamic> json) => PendingWrite(
    id: json['id'] as String,
    kind: json['kind'] as String,
    op: WriteOp.values.byName(json['op'] as String),
    itemId: json['item_id'] as String,
    changes: (json['changes'] as Map? ?? const {}).cast<String, Object?>(),
    base: (json['base'] as Map?)?.cast<String, Object?>(),
    conflicted: json['conflicted'] as bool? ?? false,
    current: (json['current'] as Map?)?.cast<String, Object?>(),
    attempts: json['attempts'] as int? ?? 0,
    lastError: json['last_error'] as String?,
    nextAttemptAt: _date(json['next_attempt_at']),
    sendingSince: _date(json['sending_since']),
    sentBy: json['sent_by'] as String?,
    refused: json['refused'] as bool? ?? false,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'kind': kind,
    'op': op.name,
    'item_id': itemId,
    if (changes.isNotEmpty) 'changes': changes,
    'base': ?base,
    if (conflicted) 'conflicted': true,
    'current': ?current,
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
