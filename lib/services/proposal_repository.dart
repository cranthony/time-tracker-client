import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/event.dart';
import '../models/note.dart';
import '../models/proposal.dart';
import '../widgets/other_events.dart';
import 'events_repository.dart';
import 'mcp_client.dart';

/// The user's edits to a [Proposal], as `amend_proposal` takes them:
/// [updates] and [creates] keyed as `compact_notes` takes them (an update
/// naming its event by `event_id`, an event id or a key), [cancels], and
/// the events to put back [asPlanned].
class ProposalEdits {
  const ProposalEdits({
    this.updates = const [],
    this.creates = const [],
    this.cancels = const [],
    this.asPlanned = const [],
  });

  final List<Map<String, Object?>> updates;
  final List<Map<String, Object?>> creates;
  final List<({String eventId, bool countsAgainstFollowThrough})> cancels;
  final List<String> asPlanned;

  bool get isEmpty =>
      updates.isEmpty &&
      creates.isEmpty &&
      cancels.isEmpty &&
      asPlanned.isEmpty;

  /// The ids and keys of the events they name.
  Set<String> get eventIds => {
    for (final u in updates) '${u['event_id']}',
    for (final c in cancels) c.eventId,
    ...asPlanned,
  };

  Map<String, Object?> toJson() => {
    if (updates.isNotEmpty) 'updates': updates,
    if (creates.isNotEmpty) 'creates': creates,
    if (cancels.isNotEmpty)
      'cancels': [
        for (final c in cancels)
          {
            'event_id': c.eventId,
            'counts_against_follow_through': c.countsAgainstFollowThrough,
          },
      ],
    if (asPlanned.isNotEmpty) 'as_planned': asPlanned,
  };

  /// [over]'s changes to the events in a new or moved event's way, as
  /// edits: the cancels as changes of plan.
  factory ProposalEdits.over(
    Overwrite over, {
    List<Map<String, Object?>> updates = const [],
    List<Map<String, Object?>> creates = const [],
  }) => ProposalEdits(
    updates: [
      ...updates,
      for (final (event, changes) in over.updates)
        proposalUpdate(event, changes),
    ],
    creates: [
      ...creates,
      for (final rest in over.creates) proposalCreate(rest, strict: false),
    ],
    cancels: [
      for (final event in over.cancels)
        (eventId: event.id!, countsAgainstFollowThrough: false),
    ],
  );
}

/// An edit the proposal can't take, said in a way to show the user.
class ProposalEditException implements Exception {
  ProposalEditException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// What a proposal's events can have set: the rest are the calendar's,
/// changed once it's confirmed.
const _proposalFields = {'summary', 'start', 'end', 'action_ids', 'facts'};

/// The names of the fields a proposal can't change, for saying so.
const _fieldNames = {
  'location': 'Its location (as the calendar has it)',
  'priority': 'Its priority',
  'judgments': 'Its judgments',
  'is_cancelled': 'Whether it was cancelled',
};

/// [changes], keyed as `update_event` takes them, to [event] as an
/// update of `amend_proposal`. A new description has to add to the old
/// one: what it adds is annotated. A change to a field a proposal doesn't
/// set throws a [ProposalEditException].
Map<String, Object?> proposalUpdate(Event event, Map<String, Object?> changes) {
  final update = <String, Object?>{'event_id': event.id};
  for (final MapEntry(:key, :value) in changes.entries) {
    if (_proposalFields.contains(key)) {
      // Empty facts remove them; null would keep them.
      update[key] = key == 'facts' ? value ?? const {} : value;
    } else if (key == 'description') {
      update['annotate'] = _added(
        event.properties['description'] as String?,
        value as String?,
      );
    } else {
      throw ProposalEditException(
        '${_fieldNames[key] ?? 'Its $key'} can\'t be changed in what '
        'happened, to confirm. Change it once that\'s confirmed, or leave '
        'a note for Claude.',
      );
    }
  }
  return update;
}

/// [fields], keyed as `create_event` takes them, as a create of
/// `amend_proposal`: its description annotated. [strict]ly, a field a
/// proposal can't set throws a [ProposalEditException]; otherwise it's
/// left out -- for what's left of an event split to make room.
Map<String, Object?> proposalCreate(
  Map<String, Object?> fields, {
  bool strict = true,
}) {
  final create = <String, Object?>{};
  for (final MapEntry(:key, :value) in fields.entries) {
    if (value == null) continue;
    if (_proposalFields.contains(key)) {
      create[key] = value;
    } else if (key == 'description') {
      if ('$value'.trim().isNotEmpty) create['annotate'] = value;
    } else if (strict) {
      throw ProposalEditException(
        '${_fieldNames[key] ?? 'Its $key'} can\'t be set on an event in '
        'what happened, to confirm. Set it once that\'s confirmed.',
      );
    }
  }
  return create;
}

/// What [now] adds to [before]: the description can only be added to.
String? _added(String? before, String? now) {
  final old = (before ?? '').trimRight();
  final changed = (now ?? '').trimRight();
  if (changed == old) return null;
  if (!changed.startsWith(old)) {
    throw ProposalEditException(
      'In what happened, to confirm, a description can only be added to. '
      'Leave a note for Claude to change it.',
    );
  }
  final added = changed.substring(old.length).trim();
  return added.isEmpty ? null : added;
}

/// Where proposals come from: the open one, the user's edits and notes,
/// and confirming it. The app talks to this rather than to MCP directly
/// so screens can be exercised without a server.
abstract class ProposalRepository {
  /// The open proposal's current revision, or null if none is open. With
  /// [sinceRevision], its [Proposal.changedSince] says what changed after
  /// that revision.
  Future<Proposal?> current({int? sinceRevision});

  /// Records [edits] to [proposal], from its [Proposal.revision], and
  /// returns the new revision -- with, in [Proposal.replaced], Claude's
  /// newer changes they overrode. Refused, writing nothing, if an edit
  /// names an event outside its window, the result overlaps, or it
  /// changes history: nothing is moved to make room.
  Future<Proposal> amend(Proposal proposal, ProposalEdits edits);

  /// Leaves [text] for Claude on [proposal], about [eventId] or [at] if
  /// given. Until Claude answers, the proposal can't be confirmed.
  Future<ProposalFeedback> addNote(
    Proposal proposal,
    String text, {
    String? eventId,
    DateTime? at,
  });

  /// Withdraws the open note [feedbackId].
  Future<void> withdrawNote(String feedbackId);

  /// Confirms [proposal]'s [Proposal.revision]: applies it, unless the
  /// calendar changed since it was planned, or it can't be planned any
  /// more. Refused unless it's the current revision and no note is open.
  Future<ProposalOutcome> confirm(Proposal proposal);

  /// Resumes [proposal]'s apply where it stopped.
  Future<ProposalOutcome> finish(Proposal proposal);

  /// Gives [proposal] up. Writes already made stay.
  Future<void> abandon(Proposal proposal);
}

/// Proposals via the Time Tracker MCP server's tools:
/// `get_compaction_status`, `get_proposal`, `amend_proposal`,
/// `add_proposal_note`, `withdraw_proposal_note`, `confirm_proposal`,
/// `finish_proposal` and `abandon_compaction`.
class McpProposalRepository implements ProposalRepository {
  McpProposalRepository(this._client);

  final McpClient _client;

  @override
  Future<Proposal?> current({int? sinceRevision}) async {
    final status = await _client.callTool('get_compaction_status', {});
    final open = (status as Map)['proposal'];
    if (open is! Map) return null;
    return _proposal(
      await _client.callTool('get_proposal', {
        'proposal_id': open['id'],
        'since_revision': ?sinceRevision,
      }),
    );
  }

  @override
  Future<Proposal> amend(Proposal proposal, ProposalEdits edits) async {
    final result = await _client.callTool('amend_proposal', {
      'proposal_id': proposal.id,
      'revision': proposal.revision,
      ...edits.toJson(),
    });
    // Refused: the current revision, and the edits refused.
    if (result case {'refused': final refused} when refused != null) {
      throw McpException(
        "amend_proposal: ${result['message'] ?? result['error'] ?? 'refused'}"
        '${refused is List && refused.isNotEmpty ? ' (${refused.join('; ')})' : ''}',
      );
    }
    return _proposal(result);
  }

  @override
  Future<ProposalFeedback> addNote(
    Proposal proposal,
    String text, {
    String? eventId,
    DateTime? at,
  }) async {
    final result = await _client.callTool('add_proposal_note', {
      'proposal_id': proposal.id,
      'text': text,
      'event_id': ?eventId,
      'at': ?(at == null ? null : localIsoTimestamp(at)),
    });
    return ProposalFeedback.fromJson((result as Map).cast<String, dynamic>());
  }

  @override
  Future<void> withdrawNote(String feedbackId) =>
      _client.callTool('withdraw_proposal_note', {'feedback_id': feedbackId});

  @override
  Future<ProposalOutcome> confirm(Proposal proposal) async => _outcome(
    await _client.callTool('confirm_proposal', {
      'proposal_id': proposal.id,
      'revision': proposal.revision,
    }),
  );

  @override
  Future<ProposalOutcome> finish(Proposal proposal) async => _outcome(
    await _client.callTool('finish_proposal', {'proposal_id': proposal.id}),
  );

  @override
  Future<void> abandon(Proposal proposal) =>
      _client.callTool('abandon_compaction', {'proposal_id': proposal.id});

  static Proposal _proposal(Object? result) =>
      Proposal.fromJson((result as Map).cast<String, dynamic>());

  static ProposalOutcome _outcome(Object? result) =>
      ProposalOutcome.fromJson((result as Map).cast<String, dynamic>());
}

/// Keeps a proposal in memory, applying the user's edits as the server
/// would, roughly: for the sample data, and tests. Confirming it writes
/// it to [events], if given, and tells [onApplied].
class InMemoryProposalRepository implements ProposalRepository {
  InMemoryProposalRepository(
    this._proposal, {
    this.events,
    this.onApplied,
    Map<int, Set<String>> changed = const {},
  }) : _changed = {...changed};

  Proposal? _proposal;
  final EventsRepository? events;
  final void Function(Proposal applied)? onApplied;

  /// The ids each revision changed, by revision.
  final Map<int, Set<String>> _changed;

  /// What [current] would return.
  Proposal? get proposal => _proposal;

  /// Each tool the app called, in order, by its server name.
  final calls = <String>[];

  /// Called on [confirm], before anything's checked: a test's chance to
  /// change the proposal under it.
  Future<ProposalOutcome?> Function(Proposal proposal)? onConfirm;

  @override
  Future<Proposal?> current({int? sinceRevision}) async {
    calls.add('get_proposal');
    final proposal = _proposal;
    if (proposal == null) return null;
    return proposal.copyWith(
      changedSince: sinceRevision == null
          ? const {}
          : {
              for (var r = sinceRevision + 1; r <= proposal.revision; r++)
                ...?_changed[r],
            },
    );
  }

  Proposal _open() {
    final proposal = _proposal;
    if (proposal == null || !proposal.state.open) {
      throw McpException('No proposal is open.');
    }
    return proposal;
  }

  int _keys = 0;
  int _notes = 0;

  @override
  Future<Proposal> amend(Proposal proposal, ProposalEdits edits) async {
    calls.add('amend_proposal');
    final current = _open();
    final events = [...?current.events];
    int indexOf(String id) {
      final i = events.indexWhere((e) => e.id == id && e.reviewed);
      if (i < 0) {
        throw McpException(
          "amend_proposal: $id isn't in what happened, from "
          '${current.windowStart} to ${current.through}.',
        );
      }
      return i;
    }

    final changed = <String>{};
    ProposalEvent edited(
      ProposalEvent e, {
      Map<String, Object?> fields = const {},
      ProposalEventStatus? status,
      String? id,
    }) {
      DateTime time(String key, DateTime old) => switch (fields[key]) {
        final String t => DateTime.parse(t),
        _ => old,
      };
      final description = switch (fields['annotate']) {
        final String added => [?e.description, added].join('\n'),
        _ => e.description,
      };
      final json = <String, dynamic>{
        ...e.properties,
        'id': id ?? e.id,
        'start': localIsoTimestamp(time('start', e.start)),
        'end': localIsoTimestamp(time('end', e.end)),
        'summary': fields['summary'] ?? e.summary,
        'description': description,
        'action_ids': fields['action_ids'] ?? e.actionIds,
        'facts': switch (fields['facts']) {
          final Map facts when facts.isEmpty => null,
          final Map facts => facts,
          _ => e.facts,
        },
        'status': (status ?? e.status).json,
        'planned_start': localIsoTimestamp(e.plannedStart ?? e.start),
        'planned_end': localIsoTimestamp(e.plannedEnd ?? e.end),
        'decided_by': 'user',
      };
      changed.add(id ?? e.id);
      return ProposalEvent.fromJson(json)!;
    }

    for (final update in edits.updates) {
      final i = indexOf('${update['event_id']}');
      final e = events[i];
      events[i] = edited(
        e,
        fields: update,
        status: e.status == ProposalEventStatus.created
            ? ProposalEventStatus.created
            : ProposalEventStatus.adjusted,
      );
    }
    for (final cancel in edits.cancels) {
      final i = indexOf(cancel.eventId);
      events[i] = edited(events[i], status: ProposalEventStatus.cancelled);
    }
    for (final id in edits.asPlanned) {
      final i = indexOf(id);
      final e = events[i];
      events[i] = edited(
        e,
        fields: {
          'start': localIsoTimestamp(e.plannedStart ?? e.start),
          'end': localIsoTimestamp(e.plannedEnd ?? e.end),
        },
        status: ProposalEventStatus.onSchedule,
      );
    }
    for (final create in edits.creates) {
      final start = DateTime.parse(create['start'] as String);
      final end = DateTime.parse(create['end'] as String);
      events.add(
        edited(
          ProposalEvent(
            id: '',
            start: start,
            end: end,
            status: ProposalEventStatus.created,
          ),
          fields: create,
          id: '${current.id}u${++_keys}',
        ),
      );
    }
    events.sort((a, b) => a.start.compareTo(b.start));
    final live = [
      for (final e in events)
        if (e.live) e,
    ];
    for (var i = 0; i + 1 < live.length; i++) {
      if (live[i].end.isAfter(live[i + 1].start)) {
        throw McpException(
          'amend_proposal: "${live[i].summary}" and '
          '"${live[i + 1].summary}" would overlap. Nothing is moved to make '
          'room.',
        );
      }
    }
    final revision = current.revision + 1;
    _changed[revision] = changed;
    _proposal = current.copyWith(
      revision: revision,
      events: events,
      reason: 'user edit',
      byUser: true,
      userEdits: [...current.userEdits, edits.toJson()],
      replaced: const [],
    );
    return _proposal!;
  }

  @override
  Future<ProposalFeedback> addNote(
    Proposal proposal,
    String text, {
    String? eventId,
    DateTime? at,
  }) async {
    calls.add('add_proposal_note');
    final current = _open();
    final note = ProposalFeedback(
      id: '${current.id}f${++_notes + current.feedback.length}',
      text: text,
      eventId: eventId,
      at: at,
    );
    _proposal = current.copyWith(
      feedback: [...current.feedback, note],
      state: ProposalState.awaitingClaude,
    );
    return note;
  }

  @override
  Future<void> withdrawNote(String feedbackId) async {
    calls.add('withdraw_proposal_note');
    final current = _open();
    final feedback = [
      for (final f in current.feedback)
        f.id == feedbackId && f.open
            ? f.withStatus(FeedbackStatus.withdrawn)
            : f,
    ];
    _proposal = current.copyWith(
      feedback: feedback,
      state: feedback.any((f) => f.open)
          ? ProposalState.awaitingClaude
          : ProposalState.awaitingReview,
    );
  }

  @override
  Future<ProposalOutcome> confirm(Proposal proposal) async {
    calls.add('confirm_proposal');
    if (await onConfirm?.call(proposal) case final outcome?) return outcome;
    final current = _open();
    if (proposal.revision != current.revision) {
      throw McpException(
        'confirm_proposal: revision ${proposal.revision} isn\'t current: '
        "it's ${current.revision}.",
      );
    }
    if (current.openFeedback.isNotEmpty) {
      throw McpException('confirm_proposal: a note is still open.');
    }
    await _apply(current);
    final applied = current.copyWith(state: ProposalState.applied);
    _proposal = null;
    onApplied?.call(applied);
    return ProposalOutcome(
      status: ProposalOutcomeStatus.applied,
      message: 'Applied.',
      proposal: applied,
    );
  }

  /// Writes [proposal]'s outcome to [events].
  Future<void> _apply(Proposal proposal) async {
    final events = this.events;
    if (events == null) return;
    for (final e in proposal.reviewed) {
      final fields = {
        'summary': e.summary,
        'start': localIsoTimestamp(e.start),
        'end': localIsoTimestamp(e.end),
        'description': e.description,
        'action_ids': e.actionIds,
        'facts': e.facts,
      };
      switch (e.status) {
        case ProposalEventStatus.adjusted:
          await events.updateEvent(
            Event(id: e.id, start: e.start, end: e.end),
            fields,
          );
        case ProposalEventStatus.created:
          await events.createEvent(fields);
        case ProposalEventStatus.cancelled || ProposalEventStatus.merged:
          await events.deleteEvent(Event(id: e.id, start: e.start, end: e.end));
        case ProposalEventStatus.onSchedule || ProposalEventStatus.planned:
      }
    }
  }

  @override
  Future<ProposalOutcome> finish(Proposal proposal) async {
    calls.add('finish_proposal');
    final current = _proposal;
    if (current == null || current.state != ProposalState.applying) {
      throw McpException("finish_proposal: it isn't being applied.");
    }
    await _apply(current);
    final applied = current.copyWith(state: ProposalState.applied);
    _proposal = null;
    onApplied?.call(applied);
    return ProposalOutcome(
      status: ProposalOutcomeStatus.applied,
      proposal: applied,
    );
  }

  @override
  Future<void> abandon(Proposal proposal) async {
    calls.add('abandon_compaction');
    _open();
    _proposal = null;
  }
}

/// The revision of each proposal the user last saw, so what's changed
/// since can be shown: in memory, and on the device unless not to
/// [persist].
class ProposalSeenStore {
  ProposalSeenStore({this.persist = true, this._seen});

  final bool persist;
  Map<String, int>? _seen;

  /// The revision of [proposalId] last seen, if it's been seen.
  Future<int?> seen(String proposalId) async {
    if (_seen == null && persist) {
      try {
        final json = await SharedPreferencesAsync().getString(_key);
        if (json != null) {
          _seen = {
            for (final MapEntry(:key, :value)
                in (jsonDecode(json) as Map).entries)
              '$key': (value as num).toInt(),
          };
        }
      } catch (_) {
        // Nowhere to keep it, or from an older version.
      }
    }
    return _seen?[proposalId];
  }

  /// Keeps [revision] of [proposalId] as seen, forgetting other
  /// proposals: only one is open at a time.
  void saw(String proposalId, int revision) {
    if (_seen?[proposalId] == revision) return;
    _seen = {proposalId: revision};
    if (!persist) return;
    try {
      SharedPreferencesAsync()
          .setString(_key, jsonEncode(_seen))
          .catchError((_) {});
    } catch (_) {
      // Nowhere to keep it: it lasts until the app closes.
    }
  }

  static const _key = 'proposal_seen';
}
