import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/event.dart';
import '../models/note.dart';
import '../models/person.dart';
import '../models/proposal.dart';
import '../widgets/other_events.dart';
import 'actions_repository.dart';
import 'events_repository.dart';
import 'mcp_client.dart';
import 'people_repository.dart';

/// The user's edits to a [Proposal], as `amend_proposal` takes them:
/// [updates] and [creates] keyed as `compact_notes` takes them (an update
/// naming its event by `event_id`, an event id or a key), [cancels], what
/// [notes] are for, and the events and notes to put back [asPlanned].
/// A note edit adds the note to the event it falls within -- or, with
/// an `eventId`, to that event -- or, [ignore]d, leaves it out.
class ProposalEdits {
  const ProposalEdits({
    this.updates = const [],
    this.creates = const [],
    this.cancels = const [],
    this.asPlanned = const [],
    this.notes = const [],
    this.additions = const [],
    this.through,
  });

  /// Where to extend the proposal to: later than its `through`, no later
  /// than now. Each note it takes in is added where it falls, unless
  /// [notes] says otherwise.
  final DateTime? through;

  final List<Map<String, Object?>> updates;
  final List<Map<String, Object?>> creates;
  final List<({String eventId, bool countsAgainstFollowThrough})> cancels;

  /// Events' ids and keys, notes' ids, and additions' refs.
  final List<String> asPlanned;
  final List<({String noteId, bool ignore, String? eventId})> notes;

  /// What's to become of a proposal's additions: each made now -- with,
  /// if it's corrected, its [name] and a person's context or a location's
  /// hint ([detail]) -- found among those there ([id]), or dropped.
  final List<
    ({
      String ref,
      AdditionUse use,
      String? id,
      String? name,
      String? detail,
      AdditionKind kind,
    })
  >
  additions;

  bool get isEmpty =>
      updates.isEmpty &&
      creates.isEmpty &&
      cancels.isEmpty &&
      asPlanned.isEmpty &&
      notes.isEmpty &&
      additions.isEmpty &&
      through == null;

  /// The ids and keys of the events they name, and the notes' ids.
  Set<String> get eventIds => {
    for (final u in updates) updateFields(u).$1,
    for (final c in cancels) c.eventId,
    ...asPlanned,
    for (final n in notes) n.noteId,
  };

  Map<String, Object?> toJson() => {
    if (through case final t?) 'through': localIsoTimestamp(t),
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
    if (notes.isNotEmpty)
      'notes': [
        for (final n in notes)
          {
            'note_id': n.noteId,
            'use': n.ignore ? 'ignore' : 'annotate',
            'event_id': ?n.eventId,
          },
      ],
    if (additions.isNotEmpty)
      'additions': [
        for (final a in additions)
          {
            'ref': a.ref,
            'use': a.use.name,
            'id': ?a.id,
            'name': ?a.name,
            if (a.detail != null)
              a.kind == AdditionKind.location ? 'hint' : 'context': a.detail,
          },
      ],
  };

  /// Them as [toJson] wrote them, as they're kept waiting to be sent.
  factory ProposalEdits.fromJson(Map<String, dynamic> json) {
    List<Map<String, Object?>> maps(String key) => [
      for (final m in json[key] as List? ?? []) (m as Map).cast(),
    ];
    return ProposalEdits(
      updates: maps('updates'),
      creates: maps('creates'),
      cancels: [
        for (final c in maps('cancels'))
          (
            eventId: '${c['event_id']}',
            countsAgainstFollowThrough:
                c['counts_against_follow_through'] == true,
          ),
      ],
      asPlanned: [for (final id in json['as_planned'] as List? ?? []) '$id'],
      through: switch (json['through']) {
        final String t => DateTime.parse(t),
        _ => null,
      },
      notes: [
        for (final n in maps('notes'))
          (
            noteId: '${n['note_id']}',
            ignore: n['use'] == 'ignore',
            eventId: n['event_id'] as String?,
          ),
      ],
      additions: [
        for (final a in maps('additions'))
          (
            ref: '${a['ref']}',
            use: AdditionUse.values.byName('${a['use']}'),
            id: a['id'] as String?,
            name: a['name'] as String?,
            detail: (a['hint'] ?? a['context']) as String?,
            // Only where a detail goes: a location's hint, else a
            // person's context.
            kind: a.containsKey('hint')
                ? AdditionKind.location
                : AdditionKind.person,
          ),
      ],
    );
  }

  /// [over]'s changes to the events in a new or moved event's way, as
  /// edits: the cancels counting against follow-through as
  /// [Overwrite.countsAgainst] says.
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
        (eventId: event.id!, countsAgainstFollowThrough: over.counts(event)),
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

/// What a proposal's events can have set, as `update_event` takes them.
const _proposalFields = {
  'summary',
  'start',
  'end',
  'description',
  'location',
  'priority',
  'action_ids',
  'facts',
};

/// What a proposal's events can have cleared, by `clear_fields`.
const _clearable = {'description', 'location', 'facts'};

/// Why each field a proposal won't take, won't.
const _refused = {
  'priority': "A proposal can't clear an event's priority: set one instead.",
  'judgments':
      "Judgments are made once it's confirmed, not in what "
      'happened, to confirm.',
  'is_cancelled': 'Cancel it instead.',
};

/// [changes], keyed as `update_event` takes them, to [event] as an update
/// of `amend_proposal`: `{event: {id, ...}, clear_fields}` -- only the
/// fields changed, so the rest stay as the proposal has them. A
/// description is the event's whole description, notes and all. Null
/// clears a field that can be; a change a proposal won't take throws a
/// [ProposalEditException].
Map<String, Object?> proposalUpdate(Event event, Map<String, Object?> changes) {
  final set = <String, Object?>{'id': event.id};
  final cleared = <String>[];
  for (final MapEntry(:key, :value) in changes.entries) {
    if (value == null && _clearable.contains(key)) {
      cleared.add(key);
    } else if (value != null && _proposalFields.contains(key)) {
      set[key] = value;
    } else {
      throw ProposalEditException(
        _refused[key] ??
            "Its $key can't be changed in what happened, to confirm. "
                "Change it once that's confirmed, or leave a note for Claude.",
      );
    }
  }
  return {'event': set, if (cleared.isNotEmpty) 'clear_fields': cleared};
}

/// [fields], keyed as `create_event` takes them, as a create of
/// `amend_proposal`: those it can take that are set. [strict]ly, any
/// other throws a [ProposalEditException]; otherwise it's left out --
/// for what's left of an event split to make room.
Map<String, Object?> proposalCreate(
  Map<String, Object?> fields, {
  bool strict = true,
}) {
  final create = <String, Object?>{};
  for (final MapEntry(:key, :value) in fields.entries) {
    if (value == null) continue;
    if (_proposalFields.contains(key)) {
      create[key] = value;
    } else if (strict) {
      throw ProposalEditException(
        _refused[key] ??
            "Its $key can't be set on an event in what happened, to "
                "confirm. Set it once that's confirmed.",
      );
    }
  }
  return create;
}

/// An `amend_proposal` update's event id (or key), and the fields it sets
/// -- those it clears as null.
(String, Map<String, Object?>) updateFields(Map<String, Object?> update) {
  final event = (update['event']! as Map).cast<String, Object?>();
  return (
    '${event['id']}',
    {
      for (final MapEntry(:key, :value) in event.entries)
        if (key != 'id') key: value,
      for (final key in update['clear_fields'] as List? ?? const [])
        '$key': null,
    },
  );
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

  /// Leaves [text] for Claude on [proposal], about [eventId], [at] or the
  /// time note [noteId] if given. Until Claude answers, the proposal can't
  /// be confirmed.
  Future<ProposalFeedback> addNote(
    Proposal proposal,
    String text, {
    String? eventId,
    DateTime? at,
    String? noteId,
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

/// Whether [id] is a time note's (`<timestamp>#<row>`), not an event's or
/// a key.
bool isNoteId(String id) => id.contains('#');

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
    String? noteId,
  }) async {
    final result = await _client.callTool('add_proposal_note', {
      'proposal_id': proposal.id,
      'text': text,
      'event_id': ?eventId,
      'at': ?(at == null ? null : localIsoTimestamp(at)),
      'note_id': ?noteId,
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
    this.people,
    this.actions,
    Map<int, Set<String>> changed = const {},
  }) : _changed = {...changed},
       _claude = _proposal,
       _claudeNotes = {for (final n in _proposal?.notes ?? []) n.id: n},
       _followThrough = {
         for (final e in _proposal?.events ?? <ProposalEvent>[])
           if (e.followThrough.isNotEmpty) e.id: e.followThrough,
       };

  /// Who each event's cancel counts against, as the proposal had it: for
  /// a cancel the user says counts.
  final Map<String, List<String>> _followThrough;

  Proposal? _proposal;

  /// The notes as Claude had them, for putting back.
  final Map<String, ProposalNote> _claudeNotes;
  final EventsRepository? events;
  final void Function(Proposal applied)? onApplied;

  /// Where an addition made now is made, if anywhere: people and
  /// locations, and actions.
  final PeopleRepository? people;
  final ActionsRepository? actions;

  /// The events' actions and facts before each addition was settled, by
  /// ref, then event id: to put back when it's unsettled.
  final _beforeSettling =
      <String, Map<String, (List<String>, Map<String, Object?>?)>>{};

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
      // Set, cleared (null), or kept as it was.
      Object? field(String key, Object? old) =>
          fields.containsKey(key) ? fields[key] : old;
      final json = <String, dynamic>{
        ...e.properties,
        'id': id ?? e.id,
        'location': field('location', e.properties['location']),
        'priority': field('priority', e.properties['priority']),
        'start': localIsoTimestamp(time('start', e.start)),
        'end': localIsoTimestamp(time('end', e.end)),
        'summary': fields['summary'] ?? e.summary,
        'description': field('description', e.description),
        'action_ids': fields['action_ids'] ?? e.actionIds,
        'facts': field('facts', e.facts),
        'status': (status ?? e.status).json,
        'planned_start': localIsoTimestamp(e.plannedStart ?? e.start),
        'planned_end': localIsoTimestamp(e.plannedEnd ?? e.end),
        'decided_by': 'user',
        ...switch (status ?? e.status) {
          ProposalEventStatus.cancelled => () {
            final counts =
                fields['counts_against_follow_through'] as bool? ??
                e.countsAgainstFollowThrough ??
                true;
            return {
              'counts_against_follow_through': counts,
              'follow_through': counts
                  ? (e.followThrough.isNotEmpty
                        ? e.followThrough
                        : _followThrough[e.id] ?? const <String>[])
                  : const <String>[],
            };
          }(),
          _ => {'counts_against_follow_through': null, 'follow_through': null},
        },
      };
      changed.add(id ?? e.id);
      return ProposalEvent.fromJson(json)!;
    }

    for (final update in edits.updates) {
      final (id, fields) = updateFields(update);
      final i = indexOf(id);
      final e = events[i];
      events[i] = edited(
        e,
        fields: fields,
        status: e.status == ProposalEventStatus.created
            ? ProposalEventStatus.created
            : ProposalEventStatus.adjusted,
      );
    }
    for (final cancel in edits.cancels) {
      final i = indexOf(cancel.eventId);
      events[i] = edited(
        events[i],
        status: ProposalEventStatus.cancelled,
        fields: {
          'counts_against_follow_through': cancel.countsAgainstFollowThrough,
        },
      );
    }
    for (final id in edits.asPlanned) {
      if (isNoteId(id) || id.startsWith('new:')) continue;
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
    final notes = _editedNotes(current, events, edits);
    final (additions, settled) = await _settle(current, events, edits, changed);
    final revision = current.revision + 1;
    _changed[revision] = changed;
    _proposal = current.copyWith(
      revision: revision,
      through: switch (edits.through) {
        final t? when t.isAfter(current.through) => t,
        _ => null,
      },
      events: events,
      notes: notes,
      additions: additions,
      settledAdditions: settled,
      reason: 'user edit',
      byUser: true,
      userEdits: [...current.userEdits, edits.toJson()],
      replaced: const [],
    );
    return _proposal!;
  }

  /// [current]'s additions, and those settled, after [edits] settle or
  /// unsettle them: each made now (in [people] or [actions]), found, or
  /// dropped, and [events] naming it by its id, or not at all, in place of
  /// its ref -- or, unsettled, by its ref again. Those changed go in
  /// [changed].
  Future<(List<ProposalAddition>, List<AdditionSettled>)> _settle(
    Proposal current,
    List<ProposalEvent> events,
    ProposalEdits edits,
    Set<String> changed,
  ) async {
    final pending = [...current.additions];
    final settled = [...current.settledAdditions];
    final all = {
      for (final a in [...?_claude?.additions, ...current.additions]) a.ref: a,
    };
    for (final ref in edits.asPlanned) {
      if (!ref.startsWith('new:')) continue;
      final was = settled.where((s) => s.ref == ref).firstOrNull;
      if (was == null || all[ref] == null) {
        throw McpException("amend_proposal: $ref isn't settled.");
      }
      settled.remove(was);
      pending.add(all[ref]!);
      for (final MapEntry(key: id, value: (actions, facts))
          in (_beforeSettling.remove(ref) ?? const {}).entries) {
        final i = events.indexWhere((e) => e.id == id);
        if (i < 0) continue;
        events[i] = ProposalEvent.fromJson({
          ...events[i].properties,
          'action_ids': actions,
          'facts': facts,
        })!;
        changed.add(id);
      }
    }
    for (final edit in edits.additions) {
      final addition = pending.where((a) => a.ref == edit.ref).firstOrNull;
      if (addition == null) {
        throw McpException(
          "amend_proposal: ${edit.ref} isn't one of the proposal's additions "
          'still to settle.',
        );
      }
      final name = edit.name ?? addition.name;
      final detail = edit.detail ?? addition.detail;
      final String? id;
      switch (edit.use) {
        case AdditionUse.existing:
          id =
              edit.id ??
              (throw McpException('amend_proposal: say which one it is.'));
        case AdditionUse.drop:
          id = null;
        case AdditionUse.create:
          id = switch (addition.kind) {
            AdditionKind.person => switch (people) {
              final people? => (await people.createPerson(
                Person(id: '', name: name, context: detail),
              )).id,
              null => 'person-${edit.ref.substring(4)}',
            },
            AdditionKind.location => switch (people) {
              final people? => (await people.createLocation(
                Location(id: '', name: name, hint: detail),
              )).id,
              null => 'location-${edit.ref.substring(4)}',
            },
            AdditionKind.action =>
              await actions?.createAction(
                    {...addition.fields, 'name': name, 'status': 'active'}
                      ..remove('ref'),
                  ) ??
                  'action-${edit.ref.substring(4)}',
          };
      }
      pending.remove(addition);
      settled.add(AdditionSettled(ref: edit.ref, use: edit.use, id: id));
      final before = _beforeSettling[edit.ref] = {};
      for (final (i, e) in events.indexed) {
        final facts = _named(e.facts, edit.ref, id) as Map<String, Object?>?;
        final actions = [
          for (final a in e.actionIds)
            if (a != edit.ref) a else ?id,
        ];
        if (_sameJson(facts, e.facts) && _sameJson(actions, e.actionIds)) {
          continue;
        }
        before[e.id] = (e.actionIds, e.facts);
        events[i] = ProposalEvent.fromJson({
          ...e.properties,
          'action_ids': actions,
          'facts': facts,
        })!;
        changed.add(e.id);
      }
    }
    return (pending, settled);
  }

  /// The proposal as Claude made it.
  final Proposal? _claude;

  /// [json] -- facts -- naming [id] wherever it named [ref]; or, with no
  /// [id], not naming it.
  static Object? _named(Object? json, String ref, String? id) => switch (json) {
    final Map map => {
      for (final MapEntry(:key, :value) in map.entries)
        if (key == ref)
          ?id: ?_named(value, ref, id)
        else if (value != ref || id != null)
          '$key': _named(value, ref, id),
    },
    final List list => [
      for (final v in list)
        if (v != ref || id != null) _named(v, ref, id),
    ],
    final String s when s == ref => id,
    _ => json,
  };

  static bool _sameJson(Object? a, Object? b) => jsonEncode(a) == jsonEncode(b);

  /// [current]'s notes, with [edits]' to them, among [events]: one
  /// annotating goes to the event named, or the one it falls within.
  List<ProposalNote> _editedNotes(
    Proposal current,
    List<ProposalEvent> events,
    ProposalEdits edits,
  ) {
    final notes = {for (final n in current.notes) n.id: n};
    ProposalNote known(String id) =>
        notes[id] ??
        (throw McpException("amend_proposal: there's no note $id."));
    for (final id in edits.asPlanned) {
      if (!isNoteId(id)) continue;
      known(id);
      notes[id] = _claudeNotes[id]!;
    }
    for (final edit in edits.notes) {
      final note = known(edit.noteId);
      if (edit.ignore) {
        notes[edit.noteId] = note.copyWith(
          use: NoteUse.ignored,
          eventId: () => null,
          decidedBy: () => DecidedBy.user,
        );
        continue;
      }
      final live = [
        for (final e in events)
          if (e.reviewed && e.live) e,
      ];
      final ProposalEvent? to;
      if (edit.eventId ?? note.edgeOf case final id?) {
        to = live.where((e) => e.id == id).firstOrNull;
        if (to == null) {
          throw McpException(
            "amend_proposal: there's no event $id to add it to.",
          );
        }
      } else {
        to = live
            .where(
              (e) => !e.start.isAfter(note.time) && e.end.isAfter(note.time),
            )
            .firstOrNull;
      }
      notes[edit.noteId] = note.copyWith(
        use: to == null ? NoteUse.unused : NoteUse.annotates,
        eventId: () => to?.id,
        decidedBy: () => DecidedBy.user,
      );
    }
    return notes.values.toList()..sort((a, b) => a.time.compareTo(b.time));
  }

  @override
  Future<ProposalFeedback> addNote(
    Proposal proposal,
    String text, {
    String? eventId,
    DateTime? at,
    String? noteId,
  }) async {
    calls.add('add_proposal_note');
    final current = _open();
    final note = ProposalFeedback(
      id: '${current.id}f${++_notes + current.feedback.length}',
      text: text,
      eventId: eventId,
      at: at,
      noteId: noteId,
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
        'location': e.properties['location'],
        'priority': e.properties['priority'],
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
          await events.deleteEvent(
            Event(id: e.id, start: e.start, end: e.end),
            countsAgainstFollowThrough: e.countsAgainstFollowThrough ?? false,
          );
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
