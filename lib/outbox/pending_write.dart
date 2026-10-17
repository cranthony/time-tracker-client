import 'outbox.dart';

/// What a [PendingWrite] does to its item -- or, [batch], to several of a
/// kind at once, by its batch tool ([WriteKind.batchTool]): its changes
/// are then its parts (see [PendingWrite.parts]).
enum WriteOp { create, update, delete, batch }

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
    this.ordered = false,
    this.conflictId,
    this.moreConflicts = const [],
  });

  @override
  final String id;

  /// Whether it's sent only after every write of its [kind] queued before
  /// it -- one of several changes the server takes only in that order (a
  /// goal closed after its sub-goals). One of those refused holds it till
  /// the user retries or drops that one.
  final bool ordered;

  /// For a [WriteOp.batch] write, [conflicted]: the item whose part the
  /// server found changed elsewhere since its base.
  final String? conflictId;

  /// For a [WriteOp.batch] write, [conflicted]: the other items the server
  /// found changed elsewhere, each `{id, current}`, to resolve after
  /// [conflictId], one by one, before it's sent again.
  final List<Map<String, Object?>> moreConflicts;

  /// A [WriteOp.batch] write's parts: the items it makes (each with its
  /// id), changes (`{id, changes, base}`) and deletes (`{id, base}`).
  List<Map<String, Object?>> parts(String which) => [
    for (final p in changes[which] as List? ?? const [])
      (p as Map).cast<String, Object?>(),
  ];

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
    String? Function()? conflictId,
    List<Map<String, Object?>>? moreConflicts,
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
    ordered: ordered,
    conflictId: conflictId == null ? this.conflictId : conflictId(),
    moreConflicts: moreConflicts ?? this.moreConflicts,
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
    ordered: ordered,
    conflictId: refused == false ? null : conflictId,
    moreConflicts: refused == false ? const [] : moreConflicts,
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
    ordered: json['ordered'] as bool? ?? false,
    conflictId: json['conflict_id'] as String?,
    moreConflicts: [
      for (final c in json['more_conflicts'] as List? ?? const [])
        (c as Map).cast<String, Object?>(),
    ],
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
    if (ordered) 'ordered': true,
    'conflict_id': ?conflictId,
    if (moreConflicts.isNotEmpty) 'more_conflicts': moreConflicts,
  };

  static DateTime? _date(Object? value) =>
      value == null ? null : DateTime.parse(value as String);
}
