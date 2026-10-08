import 'event.dart';
import 'note.dart';

/// Where a [Proposal] is: awaiting the user's review, or Claude's
/// (while any note is open), being applied, applied, or given up.
enum ProposalState {
  awaitingReview('awaiting_review'),
  awaitingClaude('awaiting_claude'),
  applying('applying'),
  applied('applied'),
  abandoned('abandoned');

  const ProposalState(this.json);

  /// As the server writes it.
  final String json;

  static ProposalState parse(Object? json) => values.firstWhere(
    (s) => s.json == json,
    orElse: () => ProposalState.awaitingReview,
  );

  /// Whether it's still to be confirmed, or given up.
  bool get open => this == awaitingReview || this == awaitingClaude;
}

/// What a [Proposal] says happened to one of its events.
enum ProposalEventStatus {
  /// As planned.
  onSchedule('on_schedule'),

  /// Happened, but differently: moved, renamed, or its actions or facts
  /// set.
  adjusted('adjusted'),

  /// Happened, unplanned: it's made when the proposal's applied.
  created('new'),

  /// Didn't happen.
  cancelled('cancelled'),

  /// Folded into another event.
  merged('merged'),

  /// Still to come, after the proposal's `through`: the plan, untouched.
  planned('planned');

  const ProposalEventStatus(this.json);

  /// As the server writes it.
  final String json;

  static ProposalEventStatus parse(Object? json) => values.firstWhere(
    (s) => s.json == json,
    orElse: () => ProposalEventStatus.onSchedule,
  );
}

/// Who decided what a [ProposalEvent] is: Claude, or the user.
enum DecidedBy { claude, user }

/// One event as a revision of a [Proposal] leaves it, mirroring an item of
/// `get_proposal`'s `events`.
class ProposalEvent {
  const ProposalEvent({
    required this.id,
    required this.start,
    required this.end,
    required this.status,
    this.summary,
    this.description,
    this.actionIds = const [],
    this.facts,
    this.plannedStart,
    this.plannedEnd,
    this.decidedBy,
    this.historyUntil,
    this.isEndOfDaySleep = false,
    this.countsAgainstFollowThrough,
    this.followThrough = const [],
    this.properties = const {},
  });

  /// The calendar event's id, or, for one the proposal creates, its key
  /// (`<proposal>c<n>` for Claude's, `<proposal>u<n>` for the user's).
  final String id;
  final DateTime start;
  final DateTime end;
  final ProposalEventStatus status;
  final String? summary;
  final String? description;
  final List<String> actionIds;

  /// As the server sends them (see Facts).
  final Map<String, Object?>? facts;

  /// Where the plan had it, for one it moved.
  final DateTime? plannedStart;
  final DateTime? plannedEnd;
  final DecidedBy? decidedBy;

  /// Where history ends inside it, for one that starts before the
  /// proposal's window: the part before can't change.
  final DateTime? historyUntil;
  final bool isEndOfDaySleep;

  /// For a cancelled one, whether it counts against the follow-through of
  /// whoever a follow-through trait tracks it for -- a commitment dropped
  /// -- rather than being a change of plan.
  final bool? countsAgainstFollowThrough;

  /// For a cancelled one that counts, who it counts against, with the
  /// trait: "Sam (Reliable)".
  final List<String> followThrough;

  /// As the server sent it.
  final Map<String, Object?> properties;

  /// Whether it's part of what happened, to confirm: not the plan after
  /// `through`.
  bool get reviewed => status != ProposalEventStatus.planned;

  /// Whether it happens, in the proposal: not cancelled or merged.
  bool get live =>
      status != ProposalEventStatus.cancelled &&
      status != ProposalEventStatus.merged;

  /// Whether the proposal moves it from where the plan had it.
  bool get moved =>
      (plannedStart != null && !plannedStart!.isAtSameMomentAs(start)) ||
      (plannedEnd != null && !plannedEnd!.isAtSameMomentAs(end));

  /// From an item of `get_proposal`'s `events`; null if it has no times,
  /// of its own or the calendar's.
  static ProposalEvent? fromJson(Map<String, dynamic> json) {
    DateTime? time(Object? value) =>
        value is String ? DateTime.tryParse(value) : null;
    final start = time(json['start']) ?? time(json['planned_start']);
    final end = time(json['end']) ?? time(json['planned_end']);
    if (start == null || end == null) return null;
    return ProposalEvent(
      id: '${json['id']}',
      start: start,
      end: end,
      status: ProposalEventStatus.parse(json['status']),
      summary: json['summary'] as String?,
      description: json['description'] as String?,
      actionIds: [for (final id in json['action_ids'] as List? ?? []) '$id'],
      facts: (json['facts'] as Map?)?.cast<String, Object?>(),
      plannedStart: time(json['planned_start']),
      plannedEnd: time(json['planned_end']),
      decidedBy: switch (json['decided_by']) {
        'claude' => DecidedBy.claude,
        'user' => DecidedBy.user,
        _ => null,
      },
      historyUntil: time(json['history_until']),
      isEndOfDaySleep: json['is_end_of_day_sleep'] == true,
      countsAgainstFollowThrough:
          json['counts_against_follow_through'] as bool?,
      followThrough: [
        for (final f in json['follow_through'] as List? ?? []) '$f',
      ],
      properties: Map.unmodifiable(json),
    );
  }

  /// The proposal's fields, not the event's.
  static const _proposalOnly = {
    'status',
    'planned_start',
    'planned_end',
    'decided_by',
    'history_until',
    'counts_against_follow_through',
    'follow_through',
  };

  /// It as an [Event], to show and edit like the calendar's: over
  /// [calendar], the calendar's own event if it has one, for what the
  /// proposal leaves out (its priority, its actions' names). A cancelled
  /// or merged one is cancelled. The actions the proposal adds are named
  /// from [added], by ref.
  Event toEvent([Event? calendar, Map<String, String> added = const {}]) =>
      Event.fromJson({
        ...?calendar?.properties,
        for (final MapEntry(:key, :value) in properties.entries)
          if (!_proposalOnly.contains(key)) key: value,
        // Names for the calendar's own actions only: the proposal may have
        // changed them.
        if (actionIds.any(added.containsKey))
          'action_names': [for (final id in actionIds) added[id]]
        else if (calendar != null && !_sameIds(calendar.actionIds, actionIds))
          'action_names': null,
        // Its own priority, as the proposal has it, over what its actions
        // gave it on the calendar.
        if (properties['priority'] case final int priority)
          'effective_priority': priority,
        'is_cancelled': !live,
      });

  static bool _sameIds(List<String> a, List<String> b) =>
      a.length == b.length &&
      [for (var i = 0; i < a.length; i++) a[i] == b[i]].every((same) => same);
}

/// A note the user left for Claude on a [Proposal] (or the server's own,
/// when it needs Claude), and Claude's reply.
class ProposalFeedback {
  const ProposalFeedback({
    required this.id,
    required this.text,
    this.eventId,
    this.at,
    this.byUser = true,
    this.created,
    this.status = FeedbackStatus.open,
    this.reply,
    this.answeredIn,
    this.noteId,
  });

  /// `<proposal>f<n>`.
  final String id;
  final String text;

  /// The event it's about, if it's about one: an event id or a key.
  final String? eventId;

  /// The time it's about, if it's about one.
  final DateTime? at;

  /// Whether the user wrote it; else the server did.
  final bool byUser;
  final DateTime? created;
  final FeedbackStatus status;

  /// Claude's reply, once it's answered.
  final String? reply;

  /// The revision that answered it.
  final int? answeredIn;

  /// The time note it's about, if it's about one.
  final String? noteId;

  bool get open => status == FeedbackStatus.open;

  factory ProposalFeedback.fromJson(Map<String, dynamic> json) =>
      ProposalFeedback(
        id: '${json['id']}',
        text: json['text'] as String? ?? '',
        eventId: json['event_id'] as String?,
        at: switch (json['at']) {
          final String at => DateTime.tryParse(at),
          _ => null,
        },
        byUser: json['by'] != 'server',
        created: switch (json['created']) {
          final String at => DateTime.tryParse(at),
          _ => null,
        },
        status: switch (json['status']) {
          'answered' => FeedbackStatus.answered,
          'withdrawn' => FeedbackStatus.withdrawn,
          _ => FeedbackStatus.open,
        },
        reply: json['reply'] as String?,
        answeredIn: (json['answered_in'] as num?)?.toInt(),
        noteId: json['note_id'] as String?,
      );

  ProposalFeedback withStatus(FeedbackStatus status) => ProposalFeedback(
    id: id,
    text: text,
    eventId: eventId,
    at: at,
    byUser: byUser,
    created: created,
    status: status,
    reply: reply,
    answeredIn: answeredIn,
    noteId: noteId,
  );
}

enum FeedbackStatus { open, answered, withdrawn }

/// A compaction under review: "this is what happened from [windowStart]
/// to [through]", as its current [revision] has it, mirroring
/// `get_proposal`. Claude prepares it; the user edits it, or leaves notes
/// for Claude ([feedback]), and only the user's confirmation applies it.
class Proposal {
  const Proposal({
    required this.id,
    required this.revision,
    required this.state,
    required this.windowStart,
    required this.through,
    this.claudeThrough,
    this.events,
    this.problem,
    this.reason,
    this.byUser = false,
    this.warnings = const [],
    this.timeline,
    this.notes = const [],
    this.additions = const [],
    this.settledAdditions = const [],
    this.feedback = const [],
    this.userEdits = const [],
    this.changedSince = const {},
    this.replaced = const [],
  });

  /// 12 hex digits.
  final String id;

  /// The current revision, numbered from 1: only it can be confirmed.
  final int revision;
  final ProposalState state;

  /// Where it starts: the last confirmed proposal's [through], where
  /// history ends.
  final DateTime windowStart;

  /// Where what happened ends, and the plan goes on.
  final DateTime through;

  /// Where Claude's own revision ran to: from there to [through], the
  /// user extended it. Null from a server that doesn't say -- or as
  /// [through].
  final DateTime? claudeThrough;

  /// Whether the user extended it past where Claude's revision ran to.
  bool get extended => claudeThrough?.isBefore(through) ?? false;

  /// Whether [time] is in the stretch the user extended it by.
  bool inExtension(DateTime time) =>
      extended && time.isAfter(claudeThrough!) && !time.isAfter(through);

  /// Every event of its days, as it leaves them; null when it no longer
  /// plans, with [problem] saying why.
  final List<ProposalEvent>? events;
  final String? problem;

  /// Why this revision was made: "proposed", "user edit", "recheck"...
  final String? reason;

  /// Whether the user's edit made this revision.
  final bool byUser;
  final List<String> warnings;

  /// The notes beside the events, as text.
  final String? timeline;

  /// The notes in its window, by time, and what became of each.
  final List<ProposalNote> notes;

  /// The people, actions and locations its decisions add, made when it's
  /// applied: until then, named by their refs.
  final List<ProposalAddition> additions;

  /// Those of [additions] the user settled, no longer listed there:
  /// made, found among those already there, or dropped.
  final List<AdditionSettled> settledAdditions;

  /// The names of [additions], by ref.
  Map<String, String> get addedNames => {
    for (final a in additions) a.ref: a.name,
  };

  /// The cancelled events of what happened: each counting against
  /// follow-through, or not.
  List<ProposalEvent> get cancels => [
    for (final e in reviewed)
      if (e.status == ProposalEventStatus.cancelled) e,
  ];
  final List<ProposalFeedback> feedback;

  /// The user's edits, each as `amend_proposal` took it.
  final List<Map<String, Object?>> userEdits;

  /// The ids (and keys) of the events whose outcome changed since the
  /// revision asked about.
  final Set<String> changedSince;

  /// After an amend, the ids of the events whose newer change from
  /// Claude it overrode.
  final List<String> replaced;

  /// The notes still waiting on Claude.
  List<ProposalFeedback> get openFeedback => [
    for (final f in feedback)
      if (f.open) f,
  ];

  /// Whether it can be confirmed: no note is waiting on Claude. One that
  /// no longer plans can be too: that hands it to Claude.
  bool get confirmable =>
      state == ProposalState.awaitingReview && openFeedback.isEmpty;

  /// The events of what happened, to confirm.
  List<ProposalEvent> get reviewed => [
    for (final e in events ?? const <ProposalEvent>[])
      if (e.reviewed) e,
  ];

  ProposalEvent? event(String? id) {
    if (id == null) return null;
    for (final e in events ?? const <ProposalEvent>[]) {
      if (e.id == id) return e;
    }
    return null;
  }

  /// Whether [start] to [end] is in what happened.
  bool covers(DateTime start, DateTime end) =>
      start.isBefore(through) && end.isAfter(windowStart);

  factory Proposal.fromJson(Map<String, dynamic> json) => Proposal(
    id: '${json['id']}',
    revision: (json['revision'] as num).toInt(),
    state: ProposalState.parse(json['state']),
    windowStart: DateTime.parse(
      (json['window_start'] ?? json['from']) as String,
    ),
    through: DateTime.parse(json['through'] as String),
    claudeThrough: switch (json['claude_through']) {
      final String t => DateTime.parse(t),
      _ => null,
    },
    events: switch (json['events']) {
      final List events => [
        for (final e in events)
          ?ProposalEvent.fromJson((e as Map).cast<String, dynamic>()),
      ],
      _ => null,
    },
    problem: json['problem'] as String?,
    reason: json['reason'] as String?,
    byUser: json['by'] == 'user',
    warnings: [for (final w in json['warnings'] as List? ?? []) '$w'],
    timeline: switch (json['timeline']) {
      {'text': final String text} => text,
      final String text => text,
      _ => null,
    },
    notes: ProposalNote.allFrom(json),
    additions: ProposalAddition.allFrom(json['additions']),
    settledAdditions: [
      for (final s in (json['settled_additions'] as List? ?? []).cast<Map>())
        ?AdditionSettled.fromJson(s.cast<String, Object?>()),
    ],
    feedback: [
      for (final f in json['feedback'] as List? ?? [])
        ProposalFeedback.fromJson((f as Map).cast<String, dynamic>()),
    ],
    userEdits: [
      for (final e in json['user_edits'] as List? ?? [])
        (e as Map).cast<String, Object?>(),
    ],
    changedSince: {
      for (final id in json['changed_since'] as List? ?? []) '$id',
    },
    replaced: [for (final id in json['replaced'] as List? ?? []) '$id'],
  );

  Proposal copyWith({
    int? revision,
    DateTime? through,
    ProposalState? state,
    List<ProposalEvent>? events,
    List<ProposalFeedback>? feedback,
    List<Map<String, Object?>>? userEdits,
    Set<String>? changedSince,
    List<String>? replaced,
    String? reason,
    bool? byUser,
    List<ProposalNote>? notes,
    List<ProposalAddition>? additions,
    List<AdditionSettled>? settledAdditions,
  }) => Proposal(
    id: id,
    revision: revision ?? this.revision,
    state: state ?? this.state,
    windowStart: windowStart,
    through: through ?? this.through,
    // Claude's end, kept where the user extends it.
    claudeThrough: claudeThrough ?? this.through,
    events: events ?? this.events,
    problem: problem,
    reason: reason ?? this.reason,
    byUser: byUser ?? this.byUser,
    warnings: warnings,
    timeline: timeline,
    notes: notes ?? this.notes,
    additions: additions ?? this.additions,
    settledAdditions: settledAdditions ?? this.settledAdditions,
    feedback: feedback ?? this.feedback,
    userEdits: userEdits ?? this.userEdits,
    changedSince: changedSince ?? this.changedSince,
    replaced: replaced ?? this.replaced,
  );
}

/// What a [ProposalAddition] is.
enum AdditionKind {
  person('people', 'Person'),
  action('actions', 'Action'),
  location('locations', 'Location');

  const AdditionKind(this.json, this.label);

  /// Its list in `additions`.
  final String json;
  final String label;
}

/// A person, action or location a [Proposal]'s decisions add, mirroring
/// an item of `get_proposal`'s `additions`: named by its [ref] ("new:
/// priya") wherever an id would go, until it's made, when the proposal's
/// applied.
class ProposalAddition {
  const ProposalAddition({
    required this.ref,
    required this.kind,
    required this.name,
    this.fields = const {},
  });

  final String ref;
  final AdditionKind kind;
  final String name;

  /// As the server sent it: a person's context, a location's hint, an
  /// action's group and priority...
  final Map<String, Object?> fields;

  /// What tells it apart: a person's context, or a location's hint.
  String? get detail => switch (kind) {
    AdditionKind.person => fields['context'] as String?,
    AdditionKind.location => fields['hint'] as String?,
    AdditionKind.action => null,
  };

  /// The proposal's `additions`, people first, then actions, then
  /// locations.
  static List<ProposalAddition> allFrom(Object? additions) => [
    if (additions is Map)
      for (final kind in AdditionKind.values)
        for (final item in (additions[kind.json] as List? ?? []).cast<Map>())
          if (item['ref'] case final String ref)
            ProposalAddition(
              ref: ref,
              kind: kind,
              name: switch (item['name']) {
                final String name when name.trim().isNotEmpty => name,
                _ => ref,
              },
              fields: Map.unmodifiable(item.cast<String, Object?>()),
            ),
  ];
}

/// How the user settled one of a proposal's additions.
enum AdditionUse {
  /// Made now, perhaps renamed.
  create,

  /// One already there.
  existing,

  /// Not real: taken out of every event.
  drop;

  static AdditionUse? parse(Object? json) {
    for (final use in values) {
      if (use.name == json) return use;
    }
    return null;
  }
}

/// One of a proposal's additions the user settled, mirroring an item of
/// `get_proposal`'s `settled_additions`: [ref]'s [use], and the [id] it's
/// named by now -- none, dropped.
class AdditionSettled {
  const AdditionSettled({required this.ref, required this.use, this.id});

  final String ref;
  final AdditionUse use;
  final String? id;

  static AdditionSettled? fromJson(Map<String, Object?> json) =>
      switch ((json['ref'], AdditionUse.parse(json['use']))) {
        (final String ref, final use?) => AdditionSettled(
          ref: ref,
          use: use,
          id: json['id'] as String?,
        ),
        _ => null,
      };
}

/// What a [Proposal] does with one of its notes.
enum NoteUse {
  /// It sets an edge of an event, and isn't added to one.
  edge('edge'),

  /// Its text is added to an event's description.
  annotates('annotates'),

  /// It's left out.
  ignored('ignored'),

  /// It has no text, or no event to add it to.
  unused('unused');

  const NoteUse(this.json);

  /// As the server writes it.
  final String json;

  static NoteUse? parse(Object? json) {
    for (final use in values) {
      if (use.json == json) return use;
    }
    return null;
  }
}

/// A note in a [Proposal]'s window, and what the proposal does with it,
/// mirroring an item of `get_proposal`'s `notes`.
class ProposalNote {
  const ProposalNote({
    required this.id,
    required this.time,
    this.text,
    this.use = NoteUse.unused,
    this.eventId,
    this.edgeOf,
    this.decidedBy,
    this.anchors = const [],
    this.annotates,
    this.compacted = false,
  });

  /// `<timestamp>#<row>`.
  final String id;
  final DateTime time;
  final String? text;
  final NoteUse use;

  /// The event (id, or key) it's added to -- or, for an [NoteUse.edge],
  /// whose edge it sets.
  final String? eventId;

  /// The event (id, or key) whose start or end it sets, if it sets one,
  /// whether or not it's added to an event too. Annotating it without
  /// naming an event adds it to this one; nothing the user says of the
  /// note moves the edge.
  final String? edgeOf;

  /// Who said what it's for: none for a note just added where it falls.
  final DecidedBy? decidedBy;

  /// The event edges it sets, as the timeline says them, e.g. "start of
  /// Breakfast".
  final List<String> anchors;

  /// The summary of the event it's added to, as the timeline says it.
  final String? annotates;

  /// Whether an earlier compaction used it: the latest that did, before
  /// the proposal's window, there as context. It can't be changed.
  final bool compacted;

  /// Whether it's left out: added to no event.
  bool get ignored => use == NoteUse.ignored;

  ProposalNote copyWith({
    NoteUse? use,
    String? Function()? eventId,
    DecidedBy? Function()? decidedBy,
  }) => ProposalNote(
    id: id,
    time: time,
    text: text,
    use: use ?? this.use,
    eventId: eventId == null ? this.eventId : eventId(),
    edgeOf: edgeOf,
    decidedBy: decidedBy == null ? this.decidedBy : decidedBy(),
    anchors: anchors,
    annotates: annotates,
    compacted: compacted,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'timestamp': localIsoTimestamp(time),
    'description': text,
    'use': use.json,
    'event_id': eventId,
    'edge_of': edgeOf,
    'decided_by': decidedBy?.name,
  };

  /// [proposal]'s notes, by time, as `get_proposal` gives them: its
  /// `notes`, each saying what it's for, with how its `timeline` words
  /// the edges it sets; and, from the timeline, the latest note an
  /// earlier compaction used, there as context ([compacted]). From a
  /// server that doesn't say what each note is for, what the timeline
  /// says.
  static List<ProposalNote> allFrom(Map<String, dynamic> proposal) {
    DateTime? time(Object? value) =>
        value is String ? DateTime.tryParse(value) : null;
    final timeline = {
      if (proposal['timeline'] case {'notes': final List notes})
        for (final n in notes.cast<Map>()) '${n['id']}': n,
    };
    ProposalNote? fromTimeline(String id, Map n) => switch (time(n['time'])) {
      final at? when n['compacted'] == true => ProposalNote(
        id: id,
        time: at,
        text: n['text'] as String?,
        compacted: true,
      ),
      final at? => ProposalNote(
        id: id,
        time: at,
        text: n['text'] as String?,
        use: n['ignored'] == true
            ? NoteUse.ignored
            : n['annotates'] != null
            ? NoteUse.annotates
            : (n['anchors'] as List? ?? []).isNotEmpty
            ? NoteUse.edge
            : NoteUse.unused,
        anchors: [for (final a in n['anchors'] as List? ?? []) '$a'],
        annotates: n['annotates'] as String?,
      ),
      _ => null,
    };
    final listed = (proposal['notes'] as List? ?? []).cast<Map>();
    // A server that doesn't say what each note is for: the timeline.
    final older = listed.isEmpty || !listed.any((n) => n.containsKey('use'));
    final notes = <ProposalNote>[
      if (older)
        for (final MapEntry(:key, :value) in timeline.entries)
          if (value['compacted'] != true) ?fromTimeline(key, value),
      if (!older)
        for (final n in listed)
          if (time(n['timestamp']) case final at?)
            if (timeline['${n['id']}']?['compacted'] != true)
              ProposalNote(
                id: '${n['id']}',
                time: at,
                text: n['description'] as String?,
                use: NoteUse.parse(n['use']) ?? NoteUse.unused,
                eventId: n['event_id'] as String?,
                edgeOf: n['edge_of'] as String?,
                decidedBy: switch (n['decided_by']) {
                  'claude' => DecidedBy.claude,
                  'user' => DecidedBy.user,
                  _ => null,
                },
                anchors: [
                  for (final a
                      in timeline['${n['id']}']?['anchors'] as List? ?? [])
                    '$a',
                ],
                annotates: timeline['${n['id']}']?['annotates'] as String?,
              ),
      for (final MapEntry(:key, :value) in timeline.entries)
        if (value['compacted'] == true) ?fromTimeline(key, value),
    ];
    // An old server's notes, with no timeline.
    if (notes.isEmpty && timeline.isEmpty) {
      for (final n in listed) {
        if (time(n['timestamp']) case final at?) {
          notes.add(
            ProposalNote(
              id: '${n['id']}',
              time: at,
              text: n['description'] as String?,
            ),
          );
        }
      }
    }
    return notes..sort((a, b) => a.time.compareTo(b.time));
  }
}

/// What confirming a [Proposal], or finishing one whose apply stopped,
/// came to, mirroring `confirm_proposal` and `finish_proposal`.
class ProposalOutcome {
  const ProposalOutcome({required this.status, this.message, this.proposal});

  final ProposalOutcomeStatus status;
  final String? message;

  /// The proposal as it is now: a new revision to confirm, if it was
  /// rechecked or rebuilt.
  final Proposal? proposal;

  factory ProposalOutcome.fromJson(Map<String, dynamic> json) =>
      ProposalOutcome(
        status: switch (json['status']) {
          'rechecked' => ProposalOutcomeStatus.rechecked,
          'needs_claude' => ProposalOutcomeStatus.needsClaude,
          'rebuilt' => ProposalOutcomeStatus.rebuilt,
          'abandoned' => ProposalOutcomeStatus.abandoned,
          _ => ProposalOutcomeStatus.applied,
        },
        message: json['message'] as String?,
        proposal: switch (json['proposal']) {
          final Map p => Proposal.fromJson(p.cast<String, dynamic>()),
          _ => null,
        },
      );
}

enum ProposalOutcomeStatus {
  /// Applied: what happened is history now.
  applied,

  /// The calendar changed since it was planned: a new revision, to
  /// confirm again.
  rechecked,

  /// It can't be planned any more: handed to Claude, with a note of the
  /// server's.
  needsClaude,

  /// A write that can never succeed stopped its apply: a new revision,
  /// to confirm again.
  rebuilt,

  /// It had been given up.
  abandoned,
}
