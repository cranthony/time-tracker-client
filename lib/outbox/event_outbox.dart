import 'dart:async';
import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/event.dart';
import '../models/note.dart' show localIsoTimestamp;
import '../models/proposal.dart';
import '../services/events_repository.dart';
import '../services/mcp_client.dart';
import '../services/proposal_repository.dart';
import '../widgets/other_events.dart';
import 'outbox.dart';
import 'pending_event_write.dart';
import 'proposal_notices.dart';

export 'outbox.dart' show FlushResult;
export 'pending_event_write.dart';
export 'proposal_notices.dart';

/// How the Events page changes events and the open proposal: at once, on
/// the server ([DirectEventWrites]), or by way of the [EventOutbox],
/// which keeps each change and sends it when it can.
abstract interface class EventWrites {
  /// Whether changes wait in a queue, shown as made until they're saved,
  /// rather than being saved before these return.
  bool get queued;

  /// Each returns the events the server changed -- none, if the change
  /// is queued: [EventOutbox.project] shows it till it's saved.
  Future<List<Event>> update(
    Event event,
    Map<String, Object?> changes, {
    bool allowHistory = false,
  });
  Future<List<Event>> cancel(
    Event event, {
    bool countsAgainstFollowThrough = false,
    bool allowHistory = false,
  });
  Future<List<Event>> create(Map<String, Object?> fields);
  Future<List<Event>> createOver(
    Map<String, Object?> fields,
    Overwrite over, {
    bool allowHistory = false,
  });
  Future<List<Event>> makeRoom(
    Overwrite over, {
    bool allowHistory = false,
    String? label,
  });

  /// Edits [proposal]; returns it as edited -- the server's new revision,
  /// or, queued, it as the edit will leave it. [allowHistory]: the user
  /// approved it changing history ([changesHistory]).
  Future<Proposal> amend(
    Proposal proposal,
    ProposalEdits edits, {
    String? label,
    bool allowHistory = false,
  });
}

/// Saves each change on the server before it returns, as the app did
/// before the [EventOutbox]: refusals are thrown.
class DirectEventWrites implements EventWrites {
  DirectEventWrites(this._events, [this._proposals]);

  final EventsRepository _events;
  final ProposalRepository? _proposals;

  @override
  bool get queued => false;

  @override
  Future<List<Event>> update(
    Event event,
    Map<String, Object?> changes, {
    bool allowHistory = false,
  }) =>
      _events.updateEvent(event, changes, allowCompactedChanges: allowHistory);

  @override
  Future<List<Event>> cancel(
    Event event, {
    bool countsAgainstFollowThrough = false,
    bool allowHistory = false,
  }) => _events.deleteEvent(
    event,
    countsAgainstFollowThrough: countsAgainstFollowThrough,
    allowCompactedChanges: allowHistory,
  );

  @override
  Future<List<Event>> create(Map<String, Object?> fields) =>
      _events.createEvent(fields);

  @override
  Future<List<Event>> createOver(
    Map<String, Object?> fields,
    Overwrite over, {
    bool allowHistory = false,
  }) => _events.createOver(fields, over, allowCompactedChanges: allowHistory);

  @override
  Future<List<Event>> makeRoom(
    Overwrite over, {
    bool allowHistory = false,
    String? label,
  }) => _events.makeRoom(over, allowCompactedChanges: allowHistory);

  @override
  Future<Proposal> amend(
    Proposal proposal,
    ProposalEdits edits, {
    String? label,
    bool allowHistory = false,
  }) => _proposals!.amend(proposal, edits, allowHistory: allowHistory);
}

/// Changes to the calendar's events, and to the open compaction proposal,
/// made in the app and waiting to be saved: an [Outbox] of
/// [PendingEventWrite]s, kept on the device and sent strictly in the
/// order they were made -- one the server refuses stops the queue there,
/// as what comes after may depend on it, until it's edited, approved (as
/// changing history), tried again or dropped. It can be paused, and
/// resumed; paused, it stays paused across restarts.
///
/// Until each is saved, it's shown as made ([project],
/// [projectProposal]), and what it writes can't be written again
/// ([locked]): the events, and fields, it changes stay as it left them.
/// [saved] says what each saved, for the app's events to be updated.
///
/// What's done to the proposal is queued too: edits, notes for Claude,
/// and confirming, finishing or abandoning it ([confirm], [finish],
/// [abandon]) -- after which nothing more of it is taken ([closing]).
/// What comes of one that the user should hear of, even if it's sent
/// with the app closed, goes in [notices]: an edit that replaced Claude's
/// newer changes, and what a confirm came to.
class EventOutbox extends Outbox<PendingEventWrite, Object?>
    implements EventWrites {
  EventOutbox({
    required super.store,
    required this._events,
    this._proposals,
    this.notices,
    this.persistPause = false,
    super.clock,
    super.sender,
    Random? random,
  }) : _random = random ?? Random();

  final EventsRepository _events;
  final ProposalRepository? _proposals;
  final Random _random;

  /// Where what came of the proposal's changes is said; without it, it
  /// isn't.
  final ProposalNotices? notices;

  /// Whether a pause is kept on the device, for the next run of the app,
  /// and the background task, to keep to.
  final bool persistPause;

  final _saved = StreamController<(PendingEventWrite, Object?)>.broadcast();

  /// Each write once it's saved, with what the server gave: the events it
  /// changed, or the proposal's new revision.
  Stream<(PendingEventWrite, Object?)> get saved => _saved.stream;

  @override
  bool get queued => true;

  @override
  bool get inOrder => true;

  /// Oldest first: the order they're sent in.
  List<PendingEventWrite> get pending => items;

  static const _pauseKey = 'event_outbox_paused';

  /// Picks up a pause kept from before. Best effort.
  Future<void> loadPause() async {
    if (!persistPause) return;
    try {
      final paused = await SharedPreferencesAsync().getBool(_pauseKey);
      if (paused != null) super.setPaused(paused);
    } catch (_) {
      // Not paused, then.
    }
  }

  @override
  void setPaused(bool paused) {
    super.setPaused(paused);
    if (!persistPause) return;
    try {
      SharedPreferencesAsync()
          .setBool(_pauseKey, paused)
          .catchError((Object _) {});
    } catch (_) {
      // Paused for this run only.
    }
  }

  @override
  Future<FlushResult> flush({bool ignoreBackoff = false}) async {
    // The background task's, without the app's to say: what's kept.
    await loadPause();
    return super.flush(ignoreBackoff: ignoreBackoff);
  }

  @override
  void dispose() {
    _saved.close();
    super.dispose();
  }

  String _newId() =>
      '${now().microsecondsSinceEpoch}-${_random.nextInt(0x7fffffff)}';

  Future<List<Event>> _add(PendingEventWrite write) async {
    if (conflict(write) case final waiting?) throw waiting;
    await change((items) => [...items, write]);
    schedule(immediately: true);
    return const [];
  }

  static String _name(Event? e) => switch (e?.summary) {
    final s? when s.isNotEmpty => '“$s”',
    _ => 'an event',
  };

  static String _nameOf(Map<String, Object?> fields) =>
      switch (fields['summary']) {
        final String s when s.isNotEmpty => '“$s”',
        _ => 'an event',
      };

  @override
  Future<List<Event>> update(
    Event event,
    Map<String, Object?> changes, {
    bool allowHistory = false,
    String? label,
  }) => _add(
    PendingEventWrite(
      id: _newId(),
      kind: EventWriteKind.update,
      label:
          label ??
          (changes.keys.every({'start', 'end'}.contains)
              ? 'Move ${_name(event)}'
              : 'Change ${_name(event)}'),
      made: now(),
      event: event,
      changes: changes,
      allowHistory: allowHistory,
    ),
  );

  @override
  Future<List<Event>> cancel(
    Event event, {
    bool countsAgainstFollowThrough = false,
    bool allowHistory = false,
  }) => _add(
    PendingEventWrite(
      id: _newId(),
      kind: EventWriteKind.cancel,
      label: 'Cancel ${_name(event)}',
      made: now(),
      event: event,
      countsAgainstFollowThrough: countsAgainstFollowThrough,
      allowHistory: allowHistory,
    ),
  );

  @override
  Future<List<Event>> create(Map<String, Object?> fields) => _add(
    PendingEventWrite(
      id: _newId(),
      kind: EventWriteKind.create,
      label: 'Add ${_nameOf(fields)}',
      made: now(),
      fields: fields,
    ),
  );

  @override
  Future<List<Event>> createOver(
    Map<String, Object?> fields,
    Overwrite over, {
    bool allowHistory = false,
  }) => _add(
    PendingEventWrite(
      id: _newId(),
      kind: EventWriteKind.createOver,
      label:
          'Add ${_nameOf(fields)}'
          '${over.isEmpty ? '' : ', changing ${_count(over.count)}'}',
      made: now(),
      fields: fields,
      over: over,
      allowHistory: allowHistory,
    ),
  );

  @override
  Future<List<Event>> makeRoom(
    Overwrite over, {
    bool allowHistory = false,
    String? label,
  }) => _add(
    PendingEventWrite(
      id: _newId(),
      kind: EventWriteKind.makeRoom,
      label: label ?? 'Change ${_count(over.count)}',
      made: now(),
      over: over,
      allowHistory: allowHistory,
    ),
  );

  static String _count(int n) => n == 1 ? '1 event' : '$n events';

  /// [proposal] is the revision the user is looking at, as the server
  /// gave it -- not as the writes waiting show it: the edit is laid over
  /// whatever's current when it's sent, from that revision, so the server
  /// says which of Claude's newer changes it replaced.
  @override
  Future<Proposal> amend(
    Proposal proposal,
    ProposalEdits edits, {
    String? label,
    bool allowHistory = false,
  }) async {
    _refuseIfClosing(proposal);
    await _add(
      PendingEventWrite(
        id: _newId(),
        kind: EventWriteKind.amend,
        label: label ?? 'Change what happened',
        made: now(),
        proposalId: proposal.id,
        revision: proposal.revision,
        edits: edits,
        allowHistory: allowHistory,
      ),
    );
    return projectProposal(proposal)!;
  }

  /// Queues confirming [proposal]'s revision, as the server gave it: it's
  /// applied once it's sent, if that's still the current revision and
  /// the calendar still plans it the same. Refused while an edit of it
  /// waits: what's confirmed is to be what's shown.
  Future<void> confirm(Proposal proposal) async {
    _refuseIfClosing(proposal);
    if (amends(proposal)) {
      throw ProposalEditException(
        'A change to it is still waiting to save. Confirm it once '
        "that's saved, so what you confirm is what's shown.",
      );
    }
    await _addOf(proposal, EventWriteKind.confirm, 'Confirm what happened');
  }

  /// Queues finishing applying [proposal], confirmed, where it stopped.
  Future<void> finish(Proposal proposal) async {
    _refuseIfClosing(proposal);
    await _addOf(
      proposal,
      EventWriteKind.finish,
      'Finish applying what happened',
    );
  }

  /// Queues abandoning [proposal]. Writes of it already made stay.
  Future<void> abandon(Proposal proposal) async {
    _refuseIfClosing(proposal);
    await _addOf(proposal, EventWriteKind.abandon, 'Abandon the proposal');
  }

  /// Queues leaving [text] for Claude on [proposal], about [eventId], [at]
  /// or the time note [noteId], if given. Until it's answered, the
  /// proposal can't be confirmed.
  Future<void> addNote(
    Proposal proposal,
    String text, {
    String? eventId,
    DateTime? at,
    String? noteId,
  }) async {
    _refuseIfClosing(proposal);
    await _addOf(
      proposal,
      EventWriteKind.addNote,
      'Note for Claude',
      note: {
        'text': text,
        'event_id': ?eventId,
        'at': ?(at == null ? null : localIsoTimestamp(at)),
        'note_id': ?noteId,
      },
    );
  }

  /// Queues withdrawing the note [feedbackId] from [proposal] -- or, if
  /// it's one still waiting to be left, drops that.
  Future<void> withdrawNote(Proposal proposal, String feedbackId) async {
    final waiting = items
        .where(
          (w) =>
              w.kind == EventWriteKind.addNote && w.pendingId() == feedbackId,
        )
        .firstOrNull;
    if (waiting != null) {
      if (!await drop(waiting)) {
        throw ProposalEditException(
          "It's being sent: withdraw it once it's left.",
        );
      }
      return;
    }
    _refuseIfClosing(proposal);
    await _addOf(
      proposal,
      EventWriteKind.withdrawNote,
      'Withdraw a note for Claude',
      feedbackId: feedbackId,
    );
  }

  Future<void> _addOf(
    Proposal proposal,
    EventWriteKind kind,
    String label, {
    Map<String, Object?> note = const {},
    String? feedbackId,
  }) => _add(
    PendingEventWrite(
      id: _newId(),
      kind: kind,
      label: label,
      made: now(),
      proposalId: proposal.id,
      revision: proposal.revision,
      note: note,
      feedbackId: feedbackId,
    ),
  );

  /// The write waiting that confirms, finishes or abandons [proposalId],
  /// if one does: nothing more of it is taken after it.
  PendingEventWrite? closing(String proposalId) => items
      .where((w) => w.kind.closes && w.proposalId == proposalId)
      .firstOrNull;

  void _refuseIfClosing(Proposal proposal) {
    if (closing(proposal.id) case final w?) {
      throw ProposalEditException(
        '“${w.label}” is waiting to save: nothing more of it can be '
        'changed. Drop that, from the changes waiting, to change it.',
      );
    }
  }

  /// The writes of [write]'s proposal waiting after it: made on top of
  /// it, so they may not mean the same without it.
  List<PendingEventWrite> after(PendingEventWrite write) {
    if (!write.kind.ofProposal) return const [];
    final i = items.indexWhere((w) => w.id == write.id);
    if (i < 0) return const [];
    return [
      for (final w in items.skip(i + 1))
        if (w.kind.ofProposal && w.proposalId == write.proposalId) w,
    ];
  }

  /// [events], as the server last had them, with every write applied:
  /// those it changes or cancels, as it leaves them; those it creates,
  /// under a pending id -- each that overlaps [from] to [to], by start.
  List<Event> project(List<Event> events, DateTime from, DateTime to) {
    if (items.isEmpty) return events;
    final byId = {for (final e in events) e.id ?? '${e.start}-${e.summary}': e};
    final shown = {...byId};
    for (final write in items) {
      write.projectEvents(shown);
    }
    return [
      for (final e in shown.values)
        if (e.start.isBefore(to) && e.end.isAfter(from)) e,
    ]..sort((a, b) => a.start.compareTo(b.start));
  }

  /// [proposal] with every edit of it applied; null for none.
  Proposal? projectProposal(Proposal? proposal) {
    if (proposal == null) return null;
    var shown = proposal;
    for (final write in items) {
      shown = write.projectProposal(shown);
    }
    return shown;
  }

  /// Whether any write is of [proposal].
  bool amends(Proposal proposal) => items.any(
    (w) => w.kind == EventWriteKind.amend && w.proposalId == proposal.id,
  );

  /// The writes of [eventId], oldest first.
  List<PendingEventWrite> writesOf(String eventId) => [
    for (final w in items)
      if (w.locks.containsKey(eventId)) w,
  ];

  /// The fields of [eventId] a write sets, which can't change until it's
  /// saved -- or null, if none of it can: it's cancelled, created, or put
  /// back.
  Set<String>? locked(String eventId) {
    final fields = <String>{};
    for (final w in items) {
      if (!w.locks.containsKey(eventId)) continue;
      final set = w.locks[eventId];
      if (set == null) return null;
      fields.addAll(set);
    }
    return fields;
  }

  /// Whether [field] of [eventId] -- or, with no field, any of it --
  /// waits for a write.
  bool isLocked(String eventId, [String? field]) {
    final fields = locked(eventId);
    if (fields == null) return true;
    return field == null ? fields.isNotEmpty : fields.contains(field);
  }

  /// Whether all of [eventId] waits: nothing of it can change.
  bool isWhollyLocked(String eventId) => locked(eventId) == null;

  /// What stops [write] being made, if anything: a write already waiting
  /// that changes what it changes -- the same event, cancelled, created
  /// or put back, or the same field of it. None waits on itself, so
  /// [except] leaves that one out, for an edit of it.
  WaitingForWrite? conflict(PendingEventWrite write, {String? except}) {
    for (final MapEntry(key: id, value: touches) in write.locks.entries) {
      for (final w in items) {
        if (w.id == except || w.id == write.id) continue;
        if (!w.locks.containsKey(id)) continue;
        final held = w.locks[id];
        final clash = held == null || touches == null
            ? true
            : _asTime(held).intersection(_asTime(touches)).isNotEmpty;
        if (clash) return WaitingForWrite(w, fields: held, touches: touches);
      }
    }
    return null;
  }

  /// [fields], an event's start and end standing for each other: they're
  /// its time, which waits whole.
  static Set<String> _asTime(Set<String> fields) =>
      fields.contains('start') || fields.contains('end')
      ? {...fields, 'start', 'end'}
      : fields;

  /// Drops [write] without sending it. False if it's being sent: the
  /// server may already have it.
  Future<bool> drop(PendingEventWrite write) async {
    if (isSending(write)) return false;
    if (!await removeUnlessSending(write.id)) return false;
    schedule(immediately: true);
    return true;
  }

  /// Replaces [write], one not being sent, with [edited]: it's tried
  /// afresh. False if it's being sent.
  Future<bool> edit(PendingEventWrite write, PendingEventWrite edited) async {
    if (isSending(write)) return false;
    if (conflict(edited, except: write.id) case final waiting?) throw waiting;
    final replaced = await replaceUnlessSending(
      write.id,
      (_) => edited.copyWith(
        attempts: 0,
        refused: false,
        lastError: () => null,
        nextAttemptAt: () => null,
      ),
    );
    if (!replaced) return false;
    schedule(immediately: true);
    return true;
  }

  /// Sends [write] again, the user having approved changing history.
  Future<void> approveHistory(PendingEventWrite write) async {
    await edit(write, write.copyWith(allowHistory: true));
    await retryNow();
  }

  @override
  bool retries(Object error) => !_refusal(error);

  /// Whether the server answered, saying no: an overlap, history, a stale
  /// revision, something not there. Those aren't tried again by
  /// themselves.
  static bool _refusal(Object error) =>
      error is McpException || error is ProposalEditException;

  @override
  Future<Object?> send(
    PendingEventWrite item, {
    required bool maybeSaved,
  }) async {
    final allow = item.allowHistory;
    Future<T> timed<T>(Future<T> f) => f.timeout(Outbox.requestTimeout);
    final Object? result = switch (item.kind) {
      EventWriteKind.update => await timed(
        _events.updateEvent(
          item.event!,
          item.changes,
          allowCompactedChanges: allow,
        ),
      ),
      EventWriteKind.cancel => await _unlessDone(
        maybeSaved,
        () => timed(
          _events.deleteEvent(
            item.event!,
            countsAgainstFollowThrough: item.countsAgainstFollowThrough,
            allowCompactedChanges: allow,
          ),
        ),
      ),
      EventWriteKind.create =>
        (maybeSaved ? await _alreadyMade(item.fields) : null) ??
            await timed(_events.createEvent(item.fields)),
      EventWriteKind.createOver =>
        (maybeSaved ? await _alreadyMade(item.fields) : null) ??
            await timed(
              _events.createOver(
                item.fields,
                item.over,
                allowCompactedChanges: allow,
              ),
            ),
      EventWriteKind.makeRoom =>
        (maybeSaved && item.over.creates.isNotEmpty
                ? await _alreadyMade(item.over.creates.first)
                : null) ??
            await _unlessDone(
              maybeSaved,
              () => timed(
                _events.makeRoom(item.over, allowCompactedChanges: allow),
              ),
            ),
      EventWriteKind.amend => await _amend(item, maybeSaved: maybeSaved),
      EventWriteKind.confirm => await _confirm(item, maybeSaved: maybeSaved),
      EventWriteKind.finish => await _outcome(
        item,
        await _proposalsOf().finish(_of(item)).timeout(Outbox.requestTimeout),
      ),
      EventWriteKind.abandon => await _abandon(item, maybeSaved: maybeSaved),
      EventWriteKind.addNote => await _addNote(item, maybeSaved: maybeSaved),
      EventWriteKind.withdrawNote => await () async {
        await _proposalsOf()
            .withdrawNote(item.feedbackId!)
            .timeout(Outbox.requestTimeout);
        return null;
      }(),
    };
    _saved.add((item, result));
    return result;
  }

  /// [write]'s result -- or, if an earlier attempt, unheard ([maybeSaved]),
  /// made it, none: the server refuses to cancel an event again, saying
  /// it's "cancelled already", and nothing of a batch is made once one
  /// change of it is refused.
  static Future<List<Event>> _unlessDone(
    bool maybeSaved,
    Future<List<Event>> Function() write,
  ) async {
    try {
      return await write();
    } on McpException catch (e) {
      if (maybeSaved && '$e'.contains('is cancelled already')) return const [];
      rethrow;
    }
  }

  /// The event [fields] make, if an earlier attempt made it unheard: one
  /// of the same title and times.
  Future<List<Event>?> _alreadyMade(Map<String, Object?> fields) async {
    final start = DateTime.tryParse('${fields['start']}');
    final end = DateTime.tryParse('${fields['end']}');
    if (start == null || end == null) return null;
    final there = await _events
        .events(start, end)
        .timeout(Outbox.requestTimeout);
    final made = there
        .where(
          (e) =>
              !e.isCancelled &&
              e.start.isAtSameMomentAs(start) &&
              e.end.isAtSameMomentAs(end) &&
              (e.summary ?? '') == (fields['summary'] ?? ''),
        )
        .firstOrNull;
    return made == null ? null : [made];
  }

  ProposalRepository _proposalsOf() =>
      _proposals ?? (throw StateError('No proposals to change.'));

  /// [item]'s proposal, at the revision it's of, as the repository takes
  /// it.
  static Proposal _of(PendingEventWrite item, [int? revision]) => Proposal(
    id: item.proposalId!,
    revision: revision ?? item.revision ?? 0,
    state: ProposalState.awaitingReview,
    windowStart: item.made,
    through: item.made,
  );

  /// Sends [item]'s edits. Sent again after an attempt nobody heard back
  /// from ([maybeSaved]), most say the same twice, which is no matter;
  /// but the events it creates, and the additions it makes, already
  /// there aren't made again -- and with nothing else, it's not sent.
  Future<Proposal> _amend(
    PendingEventWrite item, {
    required bool maybeSaved,
  }) async {
    final proposals = _proposalsOf();
    final current = item.revision == null || maybeSaved
        ? await proposals.current().timeout(Outbox.requestTimeout)
        : null;
    // Kept by an older version, behind an edit that was dropped: on the
    // revision there is now.
    final revision = item.revision ?? current?.revision;
    if (revision == null) {
      throw McpException('amend_proposal: there is no proposal open.');
    }
    var edits = item.edits;
    if (maybeSaved && current != null && current.id == item.proposalId) {
      edits = _unmade(edits, current);
      if (edits.isEmpty) return current;
    }
    final amended = await proposals
        .amend(_of(item, revision), edits, allowHistory: item.allowHistory)
        .timeout(Outbox.requestTimeout);
    if (amended.replaced.isNotEmpty) {
      await _notice(
        item,
        ProposalNoticeKind.replaced,
        revision: amended.revision,
        eventIds: amended.replaced,
        eventNames: [
          for (final id in amended.replaced)
            switch (amended.event(id)?.summary) {
              final s? when s.isNotEmpty => '“$s”',
              _ => 'an event',
            },
        ],
      );
    }
    return amended;
  }

  /// [edits] less what [current] shows they made already: the events
  /// they create that it has, as the user's, and the additions they make
  /// that it no longer has to settle.
  static ProposalEdits _unmade(ProposalEdits edits, Proposal current) {
    bool made(Map<String, Object?> create) => (current.events ?? const []).any(
      (e) =>
          e.status == ProposalEventStatus.created &&
          e.decidedBy == DecidedBy.user &&
          e.start.isAtSameMomentAs(
            DateTime.tryParse('${create['start']}') ?? DateTime(0),
          ) &&
          e.end.isAtSameMomentAs(
            DateTime.tryParse('${create['end']}') ?? DateTime(0),
          ) &&
          (e.summary ?? '') == (create['summary'] ?? ''),
    );
    final pending = {for (final a in current.additions) a.ref};
    return ProposalEdits(
      updates: edits.updates,
      creates: [
        for (final c in edits.creates)
          if (!made(c)) c,
      ],
      cancels: edits.cancels,
      asPlanned: edits.asPlanned,
      notes: edits.notes,
      additions: [
        for (final a in edits.additions)
          if (pending.contains(a.ref)) a,
      ],
      through: edits.through,
    );
  }

  /// Confirms [item]'s revision. An earlier attempt, unheard
  /// ([maybeSaved]), may have started applying it, or applied it: that's
  /// finished instead -- as is one the server says is being applied.
  Future<ProposalOutcome> _confirm(
    PendingEventWrite item, {
    required bool maybeSaved,
  }) async {
    final proposals = _proposalsOf();
    Future<ProposalOutcome> finish() async => _outcome(
      item,
      await proposals.finish(_of(item)).timeout(Outbox.requestTimeout),
    );
    if (maybeSaved) {
      try {
        return await finish();
      } on McpException catch (e) {
        // Not confirmed yet: confirm it.
        if (!'$e'.contains("hasn't been confirmed")) rethrow;
      }
    }
    try {
      return await _outcome(
        item,
        await proposals.confirm(_of(item)).timeout(Outbox.requestTimeout),
      );
    } on McpException catch (e) {
      if (!'$e'.contains('already being applied')) rethrow;
      return finish();
    }
  }

  /// Abandons [item]'s proposal -- unless an earlier attempt, unheard
  /// ([maybeSaved]), did: it's no longer the one open.
  Future<Object?> _abandon(
    PendingEventWrite item, {
    required bool maybeSaved,
  }) async {
    final proposals = _proposalsOf();
    final gone =
        maybeSaved &&
        (await proposals.current().timeout(Outbox.requestTimeout))?.id !=
            item.proposalId;
    if (!gone) {
      await proposals.abandon(_of(item)).timeout(Outbox.requestTimeout);
    }
    await _notice(item, ProposalNoticeKind.abandoned);
    return null;
  }

  /// Leaves [item]'s note for Claude -- unless an earlier attempt, unheard
  /// ([maybeSaved]), did: one of the same text, about the same, is open.
  Future<ProposalFeedback> _addNote(
    PendingEventWrite item, {
    required bool maybeSaved,
  }) async {
    final proposals = _proposalsOf();
    final text = '${item.note['text'] ?? ''}';
    final eventId = item.note['event_id'] as String?;
    final noteId = item.note['note_id'] as String?;
    if (maybeSaved) {
      final current = await proposals.current().timeout(Outbox.requestTimeout);
      final left = current?.id != item.proposalId
          ? null
          : current?.feedback
                .where(
                  (f) =>
                      f.open &&
                      f.byUser &&
                      f.text == text &&
                      f.eventId == eventId &&
                      f.noteId == noteId,
                )
                .firstOrNull;
      if (left != null) return left;
    }
    return proposals
        .addNote(
          _of(item),
          text,
          eventId: eventId,
          at: DateTime.tryParse('${item.note['at']}'),
          noteId: noteId,
        )
        .timeout(Outbox.requestTimeout);
  }

  /// [outcome], of confirming or finishing [item]'s proposal, said in
  /// [notices].
  Future<ProposalOutcome> _outcome(
    PendingEventWrite item,
    ProposalOutcome outcome,
  ) async {
    await _notice(
      item,
      switch (outcome.status) {
        ProposalOutcomeStatus.applied => ProposalNoticeKind.applied,
        ProposalOutcomeStatus.rechecked => ProposalNoticeKind.rechecked,
        ProposalOutcomeStatus.rebuilt => ProposalNoticeKind.rebuilt,
        ProposalOutcomeStatus.needsClaude => ProposalNoticeKind.needsClaude,
        ProposalOutcomeStatus.abandoned => ProposalNoticeKind.abandoned,
      },
      revision: outcome.proposal?.revision,
      message: outcome.message,
    );
    return outcome;
  }

  Future<void> _notice(
    PendingEventWrite item,
    ProposalNoticeKind kind, {
    int? revision,
    String? message,
    List<String> eventIds = const [],
    List<String> eventNames = const [],
  }) async {
    try {
      await notices?.add(
        ProposalNotice(
          id: '${item.id}-${kind.name}',
          kind: kind,
          proposalId: item.proposalId!,
          at: now(),
          revision: revision,
          message: message,
          eventIds: eventIds,
          eventNames: eventNames,
        ),
      );
    } catch (_) {
      // Saved all the same: only not said.
    }
  }
}

/// A change refused because it changes what a write already waiting
/// changes: it can't, until that's saved.
class WaitingForWrite implements Exception {
  WaitingForWrite(this.write, {this.fields, this.touches});

  /// The write waiting.
  final PendingEventWrite write;

  /// What of the event it holds: its fields, or null for all of it.
  final Set<String>? fields;

  /// What of it the change refused would have changed; null for all.
  final Set<String>? touches;

  /// The fields both change, said as one would: "its time", "its
  /// summary and actions".
  String get what {
    final both = fields == null
        ? touches
        : touches == null
        ? fields
        : fields!.intersection(touches!);
    if (both == null || both.isEmpty) return 'it';
    final names = {for (final f in both) fieldName(f)}.toList();
    return 'its ${names.length == 1 ? names.single : '${names.sublist(0, names.length - 1).join(', ')} and ${names.last}'}';
  }

  /// [field], as one would say it.
  static String fieldName(String field) => switch (field) {
    'start' || 'end' => 'time',
    'action_ids' => 'actions',
    'facts' => 'who, where and notes',
    'summary' => 'title',
    'is_cancelled' => 'being cancelled',
    final f => f.replaceAll('_', ' '),
  };

  @override
  String toString() =>
      "Can't change $what yet: “${write.label}” is waiting to save. Once "
      "it's saved, change it again -- or change or cancel that write, from "
      'the changes waiting.';
}

/// The fields of an event as dialogs are told of them when all of it
/// waits for a write: it's cancelled, created or put back.
const allWaiting = {'*'};

/// A change called off by the user keeping history: nothing's queued.
class HistoryKept implements Exception {
  const HistoryKept();

  @override
  String toString() => 'Kept as history: nothing was changed.';
}
