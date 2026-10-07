import 'event.dart';

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
  };

  /// It as an [Event], to show and edit like the calendar's: over
  /// [calendar], the calendar's own event if it has one, for what the
  /// proposal leaves out (its priority, its actions' names). A cancelled
  /// or merged one is cancelled.
  Event toEvent([Event? calendar]) => Event.fromJson({
    ...?calendar?.properties,
    for (final MapEntry(:key, :value) in properties.entries)
      if (!_proposalOnly.contains(key)) key: value,
    // Names for the calendar's own actions only: the proposal may have
    // changed them.
    if (calendar != null && !_sameIds(calendar.actionIds, actionIds))
      'action_names': null,
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
    this.events,
    this.problem,
    this.reason,
    this.byUser = false,
    this.warnings = const [],
    this.timeline,
    this.notes = const [],
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
    ProposalState? state,
    List<ProposalEvent>? events,
    List<ProposalFeedback>? feedback,
    List<Map<String, Object?>>? userEdits,
    Set<String>? changedSince,
    List<String>? replaced,
    String? reason,
    bool? byUser,
  }) => Proposal(
    id: id,
    revision: revision ?? this.revision,
    state: state ?? this.state,
    windowStart: windowStart,
    through: through,
    events: events ?? this.events,
    problem: problem,
    reason: reason ?? this.reason,
    byUser: byUser ?? this.byUser,
    warnings: warnings,
    timeline: timeline,
    notes: notes,
    feedback: feedback ?? this.feedback,
    userEdits: userEdits ?? this.userEdits,
    changedSince: changedSince ?? this.changedSince,
    replaced: replaced ?? this.replaced,
  );
}

/// A note in a [Proposal]'s window, and what became of it, mirroring an
/// item of its `timeline`'s `notes`.
class ProposalNote {
  const ProposalNote({
    required this.id,
    required this.time,
    this.text,
    this.anchors = const [],
    this.annotates,
    this.ignored = false,
  });

  final String id;
  final DateTime time;
  final String? text;

  /// The event edges it sets, e.g. "start of Breakfast".
  final List<String> anchors;

  /// The summary of the event its text is added to, if it's added to one.
  final String? annotates;

  /// Whether Claude left it out: added to no event.
  final bool ignored;

  /// [proposal]'s notes, as `get_proposal` gives them: from its
  /// `timeline`, which says what became of each -- leaving out those an
  /// earlier compaction used, shown only as context -- or else from its
  /// `notes`.
  static List<ProposalNote> allFrom(Map<String, dynamic> proposal) {
    DateTime? time(Object? value) =>
        value is String ? DateTime.tryParse(value) : null;
    final notes = switch (proposal['timeline']) {
      {'notes': final List notes} => [
        for (final n in notes.cast<Map>())
          if (n['compacted'] != true)
            if (time(n['time']) case final at?)
              ProposalNote(
                id: '${n['id']}',
                time: at,
                text: n['text'] as String?,
                anchors: [for (final a in n['anchors'] as List? ?? []) '$a'],
                annotates: n['annotates'] as String?,
                ignored: n['ignored'] == true,
              ),
      ],
      _ => [
        for (final n in (proposal['notes'] as List? ?? []).cast<Map>())
          if (time(n['timestamp']) case final at?)
            ProposalNote(
              id: '${n['id']}',
              time: at,
              text: n['description'] as String?,
            ),
      ],
    };
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
