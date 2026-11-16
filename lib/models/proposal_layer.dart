// The open proposal as a layer over the calendar: what's decided in it --
// Claude's decisions and the user's edits -- cuts, covers and splits the
// undecided events under it. The server works that out on every revision;
// the app does too, for what it shows before the server's said: the
// in-memory proposals, and edits waiting to be saved.

import 'note.dart';
import 'proposal.dart';

/// Where the layer of [events] ends: [through], or later where the last
/// decided event that starts before [through] ends.
DateTime layerEndOf(Iterable<ProposalEvent> events, DateTime through) {
  var end = through;
  for (final e in events) {
    if (e.decidedBy == null || !e.live || !e.start.isBefore(through)) continue;
    if (e.end.isAfter(end)) end = e.end;
  }
  return end;
}

/// [events] as the layer of those decided leaves the rest: each undecided
/// one it runs into cut to what's left of it -- the first piece the event
/// itself, `adjusted`; any later piece new, keyed `<id>~N` -- or covered,
/// cancelled, when nothing is. What was implied before is worked out
/// afresh, from where the plan had it. A covered event counts against
/// follow-through as [answers] say (by id), else as it did, else as a
/// cancel does: it counts.
List<ProposalEvent> implyLayer(
  Iterable<ProposalEvent> events,
  DateTime through, {
  Map<String, bool> answers = const {},
}) {
  final counted = <String, bool>{
    for (final e in events)
      if (e.covered && e.countsAgainstFollowThrough != null)
        e.id: e.countsAgainstFollowThrough!,
    ...answers,
  };
  final base = unimplied(events, through);
  final layer = [
    for (final e in base)
      if (e.decidedBy != null && e.live) e,
  ]..sort((a, b) => a.start.compareTo(b.start));
  final out = <ProposalEvent>[];
  for (final e in base) {
    final under =
        e.decidedBy == null &&
        e.live &&
        !e.revisited &&
        (e.status == ProposalEventStatus.onSchedule ||
            e.status == ProposalEventStatus.planned);
    final over = under
        ? [
            for (final l in layer)
              if (l.id != e.id &&
                  l.start.isBefore(e.end) &&
                  l.end.isAfter(e.start))
                l,
          ]
        : const <ProposalEvent>[];
    if (over.isEmpty) {
      out.add(e);
      continue;
    }
    // What's left of it, outside every layer event over it.
    var left = [(e.start, e.end)];
    for (final l in over) {
      left = [
        for (final (from, to) in left) ...[
          if (from.isBefore(l.start))
            (from, to.isBefore(l.start) ? to : l.start),
          if (to.isAfter(l.end)) (from.isAfter(l.end) ? from : l.end, to),
        ],
      ];
    }
    final by = over.first;
    Map<String, Object?> implied(String key) => {
      key: by.id,
      '${key}_summary': by.summary,
    };
    final planned = {
      'planned_start': localIsoTimestamp(e.start),
      'planned_end': localIsoTimestamp(e.end),
    };
    if (left.isEmpty) {
      final counts = counted[e.id] ?? true;
      out.add(
        ProposalEvent.fromJson({
          ...e.properties,
          ...planned,
          'status': ProposalEventStatus.cancelled.json,
          'decided_by': null,
          'counts_against_follow_through': counts,
          'follow_through': counts ? e.followThrough : const <String>[],
          ...implied('covered_by'),
        })!,
      );
      continue;
    }
    for (final (i, (from, to)) in left.indexed) {
      out.add(
        ProposalEvent.fromJson({
          ...e.properties,
          ...planned,
          'id': i == 0 ? e.id : '${e.id}~$i',
          'start': localIsoTimestamp(from),
          'end': localIsoTimestamp(to),
          'status': i == 0
              ? ProposalEventStatus.adjusted.json
              : ProposalEventStatus.created.json,
          'decided_by': null,
          ...implied('cut_by'),
        })!,
      );
    }
  }
  return out..sort((a, b) => a.start.compareTo(b.start));
}

/// [events] with what the layer implied of them undone: each where the
/// plan had it, the later pieces of those it split gone -- to edit, and
/// then lay the layer over again ([implyLayer]).
List<ProposalEvent> unimplied(
  Iterable<ProposalEvent> events,
  DateTime through,
) => [
  for (final e in events)
    if (!(e.splitPiece && e.cut)) _asPlanned(e, through),
];

/// [e] with what the layer implied of it undone: where the plan had it,
/// as planned -- on schedule before [through], still to come after.
ProposalEvent _asPlanned(ProposalEvent e, DateTime through) {
  if (!e.implied) return e;
  final start = e.plannedStart ?? e.start;
  return ProposalEvent.fromJson({
    ...e.properties,
    'start': localIsoTimestamp(start),
    'end': localIsoTimestamp(e.plannedEnd ?? e.end),
    'status': start.isBefore(through)
        ? ProposalEventStatus.onSchedule.json
        : ProposalEventStatus.planned.json,
    'cut_by': null,
    'covered_by': null,
    'cut_by_summary': null,
    'covered_by_summary': null,
    'counts_against_follow_through': null,
    'follow_through': null,
  })!;
}

/// What a calendar edit the user made by hand while a proposal was open
/// is to its layer, mirroring `calendar_edits`' `kind`.
enum CalendarEditKind {
  /// An edit of an event the layer cut.
  cut,

  /// An edit of an event the layer covered.
  covered,

  /// An edit in time the layer freed: the tail of an event it ended
  /// early.
  freed;

  static CalendarEditKind? parse(Object? json) {
    for (final kind in values) {
      if (kind.name == json) return kind;
    }
    return null;
  }
}

/// An event's summary and times, as an item of `calendar_edits` names it.
typedef EditedEvent = ({
  String eventId,
  String? summary,
  DateTime start,
  DateTime end,
});

/// A calendar edit the user made by hand while a proposal was open, around
/// its layer, mirroring an item of `get_proposal`'s `calendar_edits`: the
/// event as it left it, and the event it will overlap once the layer's
/// gone, if any -- one the layer had ended early, with its planned end
/// back. Abandoning the proposal leaves it as it is.
class CalendarEdit {
  const CalendarEdit({required this.event, this.kind, this.overlaps});

  final EditedEvent event;
  final CalendarEditKind? kind;
  final EditedEvent? overlaps;

  static EditedEvent? _event(Object? json) {
    if (json is! Map) return null;
    final start = DateTime.tryParse('${json['start']}');
    final end = DateTime.tryParse('${json['end']}');
    final id = json['event_id'];
    if (start == null || end == null || id == null) return null;
    return (
      eventId: '$id',
      summary: json['summary'] as String?,
      start: start,
      end: end,
    );
  }

  static CalendarEdit? fromJson(Map<String, Object?> json) =>
      switch (_event(json)) {
        final event? => CalendarEdit(
          event: event,
          kind: CalendarEditKind.parse(json['kind']),
          overlaps: _event(json['overlaps']),
        ),
        null => null,
      };
}
