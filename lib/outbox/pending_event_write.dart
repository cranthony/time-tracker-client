import '../models/event.dart';
import '../models/note.dart';
import '../models/proposal.dart';
import '../services/proposal_repository.dart';
import '../widgets/other_events.dart';
import 'outbox.dart';

/// What a [PendingEventWrite] does.
enum EventWriteKind {
  /// Sets some of an event's fields.
  update,

  /// Cancels an event.
  cancel,

  /// Creates an event.
  create,

  /// Creates an event, and changes the events in its way.
  createOver,

  /// Changes events -- moving one, and what's in its way -- with no new
  /// one.
  makeRoom,

  /// Edits the open compaction proposal.
  amend,
}

/// A change to the calendar's events, or to the open compaction proposal,
/// made in the app and waiting to be saved to the server: kept, with how
/// sending it has gone, by the [EventOutbox].
///
/// Until it's saved, it's shown as made ([projectEvents],
/// [projectProposal]), and what it changes can't be changed again
/// ([locks]): the events, and their fields, it writes are as it left
/// them until the server has them.
class PendingEventWrite implements OutboxItem<PendingEventWrite> {
  const PendingEventWrite({
    required this.id,
    required this.kind,
    required this.label,
    required this.made,
    this.event,
    this.changes = const {},
    this.fields = const {},
    this.over = const Overwrite(),
    this.countsAgainstFollowThrough = false,
    this.allowHistory = false,
    this.proposalId,
    this.revision,
    this.edits = const ProposalEdits(),
    this.attempts = 0,
    this.lastError,
    this.nextAttemptAt,
    this.sendingSince,
    this.refused = false,
  });

  @override
  final String id;
  final EventWriteKind kind;

  /// What it does, to say in a line: "Move Lunch".
  final String label;

  /// When it was made.
  final DateTime made;

  /// The event an update or cancel is of, as it was shown when it was
  /// made: what's written, and what it's shown from until the server has
  /// it.
  final Event? event;

  /// An update's fields, keyed and encoded as `update_event` takes them;
  /// a null clears one.
  final Map<String, Object?> changes;

  /// A new event's fields, as `create_event` takes them.
  final Map<String, Object?> fields;

  /// What it does to the events in the way of a new or moved one.
  final Overwrite over;
  final bool countsAgainstFollowThrough;

  /// Whether the user approved changing history: an event compaction
  /// settled.
  final bool allowHistory;

  /// An amend's proposal, and the revision it's made on: that of the edit
  /// before it, once that's saved.
  final String? proposalId;
  final int? revision;
  final ProposalEdits edits;

  @override
  final int attempts;
  @override
  final String? lastError;
  @override
  final DateTime? nextAttemptAt;
  @override
  final DateTime? sendingSince;
  @override
  final bool refused;

  /// The id an event it creates goes by until the server gives it one:
  /// [n] counts those it creates.
  String pendingId([int n = 0]) => 'pending:$id:$n';

  /// Whether [eventId] is an event made here and not yet saved.
  static bool isPendingId(String? eventId) =>
      eventId?.startsWith('pending:') ?? false;

  /// Whether it says the server refused it as changing history, which the
  /// user can approve.
  bool get refusedAsHistory =>
      refused && (lastError?.contains('allow_compacted_changes') ?? false);

  /// The events it writes, by id, each with the fields it sets -- or
  /// null, for all of it: one it cancels, creates, or puts back.
  Map<String, Set<String>?> get locks {
    Map<String, Set<String>?> ofOver(Overwrite over, int firstCreate) => {
      for (final (e, changes) in over.updates) ?e.id: changes.keys.toSet(),
      for (final e in over.cancels) ?e.id: null,
      for (var i = 0; i < over.creates.length; i++)
        pendingId(firstCreate + i): null,
    };
    return switch (kind) {
      EventWriteKind.update => {?event?.id: changes.keys.toSet()},
      EventWriteKind.cancel => {?event?.id: null},
      EventWriteKind.create => {pendingId(): null},
      EventWriteKind.createOver => {pendingId(): null, ...ofOver(over, 1)},
      EventWriteKind.makeRoom => ofOver(over, 0),
      EventWriteKind.amend => {
        for (final u in edits.updates)
          updateFields(u).$1: updateFields(u).$2.keys.toSet(),
        for (final c in edits.cancels) c.eventId: null,
        for (final id in edits.asPlanned) id: null,
        for (var i = 0; i < edits.creates.length; i++) pendingId(i): null,
      },
    };
  }

  /// [events] -- by id, as last shown -- with it applied: each it
  /// changes, changed; each it cancels, cancelled; each it creates, there
  /// under a [pendingId]. One not among [events] (on another day, say) is
  /// changed from how it was when this was made.
  void projectEvents(Map<String, Event> events) {
    Event apply(Event? e, Map<String, Object?> changes) =>
        Event.fromJson({...?e?.toJson(), ...changes});
    void update(Event at, Map<String, Object?> changes) {
      final id = at.id;
      if (id == null) return;
      events[id] = apply(events[id] ?? at, changes);
    }

    void cancel(Event at) {
      final id = at.id;
      if (id == null) return;
      events[id] = apply(events[id] ?? at, const {'is_cancelled': true});
    }

    void create(Map<String, Object?> fields, String id) =>
        events[id] = apply(null, {...fields, 'id': id});

    void ofOver(Overwrite over, int firstCreate) {
      for (final (e, changes) in over.updates) {
        update(e, changes);
      }
      over.cancels.forEach(cancel);
      for (var i = 0; i < over.creates.length; i++) {
        create(over.creates[i], pendingId(firstCreate + i));
      }
    }

    switch (kind) {
      case EventWriteKind.update:
        if (event case final e?) update(e, changes);
      case EventWriteKind.cancel:
        if (event case final e?) cancel(e);
      case EventWriteKind.create:
        create(fields, pendingId());
      case EventWriteKind.createOver:
        create(fields, pendingId());
        ofOver(over, 1);
      case EventWriteKind.makeRoom:
        ofOver(over, 0);
      case EventWriteKind.amend:
        break;
    }
  }

  /// [proposal] with it applied, if it's an edit of it: the events it
  /// updates, cancels, puts back and creates, as the user decided them.
  Proposal projectProposal(Proposal proposal) {
    if (kind != EventWriteKind.amend || proposalId != proposal.id) {
      return proposal;
    }
    if (edits.through case final through?
        when through.isAfter(proposal.through)) {
      proposal = proposal.copyWith(through: through);
    }
    final events = [...?proposal.events];
    ProposalEvent? edited(ProposalEvent e, Map<String, Object?> json) =>
        ProposalEvent.fromJson({
          ...e.properties,
          'id': e.id,
          'start': localIsoTimestamp(e.start),
          'end': localIsoTimestamp(e.end),
          'decided_by': 'user',
          ...json,
        });
    void replace(String id, Map<String, Object?> json) {
      final i = events.indexWhere((e) => e.id == id);
      if (i < 0) return;
      if (edited(events[i], json) case final e?) events[i] = e;
    }

    for (final u in edits.updates) {
      final (id, fields) = updateFields(u);
      final current = events.where((e) => e.id == id).firstOrNull;
      replace(id, {
        ...fields,
        if (current != null && current.status == ProposalEventStatus.onSchedule)
          'status': ProposalEventStatus.adjusted.json,
      });
    }
    for (final c in edits.cancels) {
      replace(c.eventId, {
        'status': ProposalEventStatus.cancelled.json,
        'counts_against_follow_through': c.countsAgainstFollowThrough,
      });
    }
    for (final id in edits.asPlanned) {
      final e = events.where((e) => e.id == id).firstOrNull;
      if (e == null) continue;
      replace(id, {
        'status': ProposalEventStatus.onSchedule.json,
        if (e.plannedStart case final start?) 'start': localIsoTimestamp(start),
        if (e.plannedEnd case final end?) 'end': localIsoTimestamp(end),
        'decided_by': null,
      });
    }
    for (final (i, c) in edits.creates.indexed) {
      if (ProposalEvent.fromJson({
            ...c,
            'id': pendingId(i),
            'status': ProposalEventStatus.created.json,
            'decided_by': 'user',
          })
          case final e?) {
        events.add(e);
      }
    }
    events.sort((a, b) => a.start.compareTo(b.start));
    return proposal.copyWith(events: events);
  }

  @override
  PendingEventWrite copyWith({
    int? attempts,
    String? Function()? lastError,
    DateTime? Function()? nextAttemptAt,
    DateTime? Function()? sendingSince,
    bool? refused,
    String? label,
    Map<String, Object?>? changes,
    Map<String, Object?>? fields,
    bool? countsAgainstFollowThrough,
    bool? allowHistory,
    int? revision,
    ProposalEdits? edits,
  }) => PendingEventWrite(
    id: id,
    kind: kind,
    label: label ?? this.label,
    made: made,
    event: event,
    changes: changes ?? this.changes,
    fields: fields ?? this.fields,
    over: over,
    countsAgainstFollowThrough:
        countsAgainstFollowThrough ?? this.countsAgainstFollowThrough,
    allowHistory: allowHistory ?? this.allowHistory,
    proposalId: proposalId,
    revision: revision ?? this.revision,
    edits: edits ?? this.edits,
    attempts: attempts ?? this.attempts,
    lastError: lastError != null ? lastError() : this.lastError,
    nextAttemptAt: nextAttemptAt != null ? nextAttemptAt() : this.nextAttemptAt,
    sendingSince: sendingSince != null ? sendingSince() : this.sendingSince,
    refused: refused ?? this.refused,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'kind': kind.name,
    'label': label,
    'made': made.toUtc().toIso8601String(),
    'event': ?event?.toJson(),
    if (changes.isNotEmpty) 'changes': changes,
    if (fields.isNotEmpty) 'fields': fields,
    if (!over.isEmpty || over.creates.isNotEmpty) 'over': over.toJson(),
    if (countsAgainstFollowThrough) 'counts_against_follow_through': true,
    if (allowHistory) 'allow_history': true,
    'proposal_id': ?proposalId,
    'revision': ?revision,
    if (!edits.isEmpty) 'edits': edits.toJson(),
    'attempts': attempts,
    'last_error': ?lastError,
    'next_attempt_at': ?nextAttemptAt?.toUtc().toIso8601String(),
    'sending_since': ?sendingSince?.toUtc().toIso8601String(),
    if (refused) 'refused': true,
  };

  factory PendingEventWrite.fromJson(Map<String, dynamic> json) {
    DateTime? time(Object? t) =>
        t is String ? DateTime.tryParse(t)?.toLocal() : null;
    Map<String, Object?> map(Object? m) =>
        m is Map ? m.cast<String, Object?>() : const {};
    return PendingEventWrite(
      id: json['id'] as String,
      kind: EventWriteKind.values.byName(json['kind'] as String),
      label: json['label'] as String? ?? '',
      made: time(json['made']) ?? DateTime.now(),
      event: json['event'] is Map
          ? Event.fromJson((json['event'] as Map).cast())
          : null,
      changes: map(json['changes']),
      fields: map(json['fields']),
      over: json['over'] is Map
          ? Overwrite.fromJson((json['over'] as Map).cast())
          : const Overwrite(),
      countsAgainstFollowThrough: json['counts_against_follow_through'] == true,
      allowHistory: json['allow_history'] == true,
      proposalId: json['proposal_id'] as String?,
      revision: json['revision'] as int?,
      edits: json['edits'] is Map
          ? ProposalEdits.fromJson((json['edits'] as Map).cast())
          : const ProposalEdits(),
      attempts: json['attempts'] as int? ?? 0,
      lastError: json['last_error'] as String?,
      nextAttemptAt: time(json['next_attempt_at']),
      sendingSince: time(json['sending_since']),
      refused: json['refused'] == true,
    );
  }
}
