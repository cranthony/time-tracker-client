import 'dart:async';
import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/event.dart';
import '../models/proposal.dart';
import '../services/events_repository.dart';
import '../services/mcp_client.dart';
import '../services/proposal_repository.dart';
import '../widgets/other_events.dart';
import 'outbox.dart';
import 'pending_event_write.dart';

export 'outbox.dart' show FlushResult;
export 'pending_event_write.dart';

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
  /// or, queued, it as the edit will leave it.
  Future<Proposal> amend(
    Proposal proposal,
    ProposalEdits edits, {
    String? label,
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
  }) => _proposals!.amend(proposal, edits);
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
class EventOutbox extends Outbox<PendingEventWrite, Object?>
    implements EventWrites {
  EventOutbox({
    required super.store,
    required this._events,
    this._proposals,
    this.persistPause = false,
    super.clock,
    Random? random,
  }) : _random = random ?? Random();

  final EventsRepository _events;
  final ProposalRepository? _proposals;
  final Random _random;

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

  @override
  Future<Proposal> amend(
    Proposal proposal,
    ProposalEdits edits, {
    String? label,
  }) async {
    // On the revision shown -- or, behind another edit of it, the one
    // that edit makes, once it's saved.
    final behind = items.any(
      (w) => w.kind == EventWriteKind.amend && w.proposalId == proposal.id,
    );
    final write = PendingEventWrite(
      id: _newId(),
      kind: EventWriteKind.amend,
      label: label ?? 'Change what happened',
      made: now(),
      proposalId: proposal.id,
      revision: behind ? null : proposal.revision,
      edits: edits,
    );
    await _add(write);
    return projectProposal(proposal)!;
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
    await change(
      (items) => [
        for (final w in items)
          if (w.id != write.id) w,
      ],
    );
    schedule(immediately: true);
    return true;
  }

  /// Replaces [write], one not being sent, with [edited]: it's tried
  /// afresh. False if it's being sent.
  Future<bool> edit(PendingEventWrite write, PendingEventWrite edited) async {
    if (isSending(write)) return false;
    if (conflict(edited, except: write.id) case final waiting?) throw waiting;
    await change(
      (items) => [
        for (final w in items)
          w.id == write.id
              ? edited.copyWith(
                  attempts: 0,
                  refused: false,
                  lastError: () => null,
                  nextAttemptAt: () => null,
                )
              : w,
      ],
    );
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
      EventWriteKind.cancel => await timed(
        _events.deleteEvent(
          item.event!,
          countsAgainstFollowThrough: item.countsAgainstFollowThrough,
          allowCompactedChanges: allow,
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
      EventWriteKind.makeRoom => await timed(
        _events.makeRoom(item.over, allowCompactedChanges: allow),
      ),
      EventWriteKind.amend => await _amend(item),
    };
    _saved.add((item, result));
    return result;
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

  Future<Proposal> _amend(PendingEventWrite item) async {
    final proposals = _proposals;
    if (proposals == null) throw StateError('No proposals to amend.');
    // Behind an edit that was dropped: on the revision there is now.
    final revision =
        item.revision ??
        (await proposals.current().timeout(Outbox.requestTimeout))?.revision;
    if (revision == null) {
      throw McpException('amend_proposal: there is no proposal open.');
    }
    final amended = await proposals
        .amend(
          Proposal(
            id: item.proposalId!,
            revision: revision,
            state: ProposalState.awaitingReview,
            windowStart: item.made,
            through: item.made,
          ),
          item.edits,
        )
        .timeout(Outbox.requestTimeout);
    // The next edit of it was made on this one.
    await change((items) {
      var next = true;
      return [
        for (final w in items)
          if (next &&
              w.id != item.id &&
              w.kind == EventWriteKind.amend &&
              w.proposalId == item.proposalId)
            () {
              next = false;
              return w.copyWith(revision: amended.revision);
            }()
          else
            w,
      ];
    });
    return amended;
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
