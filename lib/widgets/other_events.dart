import '../models/event.dart';
import '../models/note.dart';

/// The other events an event's times are kept clear of, so that changing
/// them never makes it overlap one.
///
/// Overlaps it already has are left alone: only the times being changed
/// are kept clear.
class OtherEvents {
  /// The [events] other than the one with id [except], and not cancelled.
  OtherEvents(Iterable<Event> events, {String? except})
    : events = [
        for (final event in events)
          if (!event.isCancelled && (except == null || event.id != except))
            event,
      ]..sort((a, b) => a.start.compareTo(b.start));

  /// No other events: nothing to keep clear of.
  const OtherEvents.none() : events = const [];

  /// Sorted by start.
  final List<Event> events;

  /// The shortest the quick buttons make an event.
  static const shortest = Duration(minutes: 15);

  /// The end of the last event that ends by [start]: how early it can
  /// start. Null if none does.
  DateTime? earliestStart(DateTime start) {
    DateTime? earliest;
    for (final other in events) {
      if (!other.end.isAfter(start) &&
          (earliest == null || other.end.isAfter(earliest))) {
        earliest = other.end;
      }
    }
    return earliest;
  }

  /// The start of the first event that starts at or after [end]: how late
  /// it can end. Null if none does.
  DateTime? latestEnd(DateTime end) {
    for (final other in events) {
      if (!other.start.isBefore(end)) return other.start;
    }
    return null;
  }

  /// The event it would start inside of, at [start].
  Event? _around(DateTime start) {
    for (final other in events) {
      if (!other.start.isAfter(start) && other.end.isAfter(start)) {
        return other;
      }
    }
    return null;
  }

  /// [start] moved out of any event it's inside of, to its end, and the
  /// end [length] after it, or sooner if the next event starts sooner.
  (DateTime, DateTime) moveStart(DateTime start, Duration length) {
    var moved = start;
    for (var around = _around(moved); around != null; around = _around(moved)) {
      moved = around.end;
    }
    var end = moved.add(length);
    if (latestEnd(moved) case final next? when next.isBefore(end)) end = next;
    return (moved, end);
  }

  /// A box from [anchor] to [toward] -- either way -- fitted into free
  /// time: [anchor] moved out of any event it's in, to that event's edge
  /// on [toward]'s side, the box keeping its length; then its other end
  /// no further than the next event that way. Its ends meet if there's no
  /// free time there.
  (DateTime, DateTime) fitFrom(DateTime anchor, DateTime toward) {
    if (anchor == toward) return (anchor, toward);
    final later = toward.isAfter(anchor);
    final length = toward.difference(anchor);
    var from = anchor;
    for (
      var e = _covering(from, later);
      e != null;
      e = _covering(from, later)
    ) {
      from = later ? e.end : e.start;
    }
    var to = from.add(length);
    if (later) {
      if (latestEnd(from) case final next? when next.isBefore(to)) to = next;
    } else {
      if (earliestStart(from) case final last? when last.isAfter(to)) {
        to = last;
      }
    }
    return (from, to);
  }

  /// The event a box from [time], [later] or earlier, would start inside
  /// of.
  Event? _covering(DateTime time, bool later) {
    for (final e in events) {
      final inside = later
          ? !e.start.isAfter(time) && e.end.isAfter(time)
          : e.start.isBefore(time) && !e.end.isBefore(time);
      if (inside) return e;
    }
    return null;
  }

  /// A box from [start] for [length], moved as little as it can be to
  /// free time it fits in between [from] and [to] (the day); if no free
  /// time there is long enough, the nearest there is, filled.
  (DateTime, DateTime) fitMoved(
    DateTime start,
    Duration length, {
    required DateTime from,
    required DateTime to,
  }) {
    final gaps = [
      for (final (gapFrom, gapTo) in _gaps())
        if ((gapTo == null || gapTo.isAfter(from)) &&
            (gapFrom == null || gapFrom.isBefore(to)))
          (
            gapFrom == null || gapFrom.isBefore(from) ? from : gapFrom,
            gapTo == null || gapTo.isAfter(to) ? to : gapTo,
          ),
    ];
    if (gaps.isEmpty) return (start, start);
    (DateTime, DateTime)? best;
    Duration? moved;
    for (final (gapFrom, gapTo) in gaps) {
      if (gapTo.difference(gapFrom) < length) continue;
      var at = start;
      if (at.isBefore(gapFrom)) at = gapFrom;
      if (at.add(length).isAfter(gapTo)) at = gapTo.subtract(length);
      final by = at.difference(start).abs();
      if (moved == null || by < moved) {
        best = (at, at.add(length));
        moved = by;
      }
    }
    if (best != null) return best;
    // None long enough.
    Duration away((DateTime, DateTime) gap) {
      final (gapFrom, gapTo) = gap;
      if (start.isBefore(gapFrom)) return gapFrom.difference(start);
      if (start.isAfter(gapTo)) return start.difference(gapTo);
      return Duration.zero;
    }

    return gaps.reduce((a, b) => away(b) < away(a) ? b : a);
  }

  /// The free times between the events, in order: from and to, null for
  /// none before the first event, or after the last.
  List<(DateTime?, DateTime?)> _gaps() {
    final gaps = <(DateTime?, DateTime?)>[];
    DateTime? free;
    var first = true;
    for (final e in events) {
      if (first) {
        gaps.add((null, e.start));
        first = false;
      } else if (free != null && e.start.isAfter(free)) {
        gaps.add((free, e.start));
      }
      if (free == null || e.end.isAfter(free)) free = e.end;
    }
    gaps.add((free, null));
    return gaps;
  }

  /// What a new event from [start] to [end] takes from the others to fit,
  /// overwriting them: each it covers whole is cancelled; each it covers
  /// one end of is shortened to it; and one it falls inside of is split
  /// around it, the part after it made a new event.
  Overwrite overwrite(DateTime start, DateTime end) {
    final cancels = <Event>[];
    final updates = <(Event, Map<String, Object?>)>[];
    final creates = <Map<String, Object?>>[];
    for (final other in events) {
      if (!other.start.isBefore(end) || !other.end.isAfter(start)) continue;
      final before = other.start.isBefore(start);
      final after = other.end.isAfter(end);
      if (before && after) {
        updates.add((other, {'end': localIsoTimestamp(start)}));
        creates.add(_rest(other, end, other.end));
      } else if (before) {
        updates.add((other, {'end': localIsoTimestamp(start)}));
      } else if (after) {
        updates.add((other, {'start': localIsoTimestamp(end)}));
      } else {
        cancels.add(other);
      }
    }
    return Overwrite(cancels: cancels, updates: updates, creates: creates);
  }

  /// What a new event from [start] to [end] takes from the others when
  /// they're cancelled rather than trimmed: every one it touches,
  /// cancelled whole.
  Overwrite cancelling(DateTime start, DateTime end) => Overwrite(
    cancels: [
      for (final other in events)
        if (other.start.isBefore(end) && other.end.isAfter(start)) other,
    ],
  );

  /// From [start] to [end], stretched to take in every event it touches:
  /// what [cancelling] takes away.
  (DateTime, DateTime) touching(DateTime start, DateTime end) {
    var (from, to) = (start, end);
    for (final other in events) {
      if (!other.start.isBefore(end) || !other.end.isAfter(start)) continue;
      if (other.start.isBefore(from)) from = other.start;
      if (other.end.isAfter(to)) to = other.end;
    }
    return (from, to);
  }

  /// What a new event from [start] to [end] does to the others, pushing
  /// them: [later], from [start] (or else earlier, from [end]). An event
  /// [start] -- or [end] -- is inside of is cut there, as [inside] says;
  /// then the events after it -- or before -- are pushed along, their
  /// lengths kept, as far as they must be, into the free time beyond.
  Overwrite pushing(
    DateTime start,
    DateTime end, {
    required bool later,
    Inside inside = Inside.trim,
  }) => _push(start, end, later: later, inside: inside).$1;

  /// How far [pushing] pushes the events: the end of the last one pushed
  /// -- or, earlier, the start of the first -- or [end] (or [start]) if
  /// none is.
  DateTime pushedTo(
    DateTime start,
    DateTime end, {
    required bool later,
    Inside inside = Inside.trim,
  }) => _push(start, end, later: later, inside: inside).$2;

  (Overwrite, DateTime) _push(
    DateTime start,
    DateTime end, {
    required bool later,
    required Inside inside,
  }) {
    final updates = <(Event, Map<String, Object?>)>[];
    final creates = <Map<String, Object?>>[];
    final anchor = later ? start : end;
    var frontier = later ? end : start;
    // Places a piece [length] long at the frontier, moving it along.
    (DateTime, DateTime) place(Duration length) {
      final piece = later
          ? (frontier, frontier.add(length))
          : (frontier.subtract(length), frontier);
      frontier = later ? piece.$2 : piece.$1;
      return piece;
    }

    // Cut at the anchor: the part on the new event's side, trimmed away,
    // or split off and pushed along first.
    final cut = <Event>{};
    final rests = <(Event, Duration)>[];
    for (final other in events) {
      if (!other.start.isBefore(anchor) || !other.end.isAfter(anchor)) {
        continue;
      }
      cut.add(other);
      final at = localIsoTimestamp(anchor);
      updates.add((other, later ? {'end': at} : {'start': at}));
      if (inside == Inside.split) {
        rests.add((
          other,
          later ? other.end.difference(anchor) : anchor.difference(other.start),
        ));
      }
    }
    for (final (other, length) in rests) {
      final (from, to) = place(length);
      creates.add(_rest(other, from, to));
    }
    // The rest, from the anchor on, nearest first, until one's clear.
    final beyond = [
      for (final other in events)
        if (!cut.contains(other) &&
            (later
                ? !other.start.isBefore(anchor)
                : !other.end.isAfter(anchor)))
          other,
    ];
    if (!later) beyond.sort((a, b) => b.end.compareTo(a.end));
    for (final other in beyond) {
      final clear = later
          ? !other.start.isBefore(frontier)
          : !other.end.isAfter(frontier);
      if (clear) break;
      final (from, to) = place(other.end.difference(other.start));
      updates.add((
        other,
        {'start': localIsoTimestamp(from), 'end': localIsoTimestamp(to)},
      ));
    }
    return (Overwrite(updates: updates, creates: creates), frontier);
  }

  /// [anchor] out of any event it's strictly inside of, to that event's
  /// nearer edge: where two events meet, it can sit between them.
  DateTime between(DateTime anchor) {
    var at = anchor;
    for (var i = 0; i < events.length; i++) {
      final around = events.where(
        (e) => e.start.isBefore(at) && e.end.isAfter(at),
      );
      if (around.isEmpty) break;
      final e = around.first;
      at = at.difference(e.start) <= e.end.difference(at) ? e.start : e.end;
    }
    return at;
  }

  /// A box from [anchor] to [toward] -- either way -- no longer than
  /// leaves room, between [from] and [to] (the day), for the events it
  /// pushes ([pushing]): [toward], moved back toward [anchor] if it must.
  DateTime pushFit(
    DateTime anchor,
    DateTime toward, {
    required DateTime from,
    required DateTime to,
    Inside inside = Inside.trim,
  }) {
    final later = toward.isAfter(anchor);
    var end = toward;
    for (var i = 0; i < 100 && end != anchor; i++) {
      final reached = later
          ? pushedTo(anchor, end, later: true, inside: inside)
          : pushedTo(end, anchor, later: false, inside: inside);
      final over = later ? reached.difference(to) : from.difference(reached);
      if (over <= Duration.zero) break;
      end = later ? end.subtract(over) : end.add(over);
      if (later ? end.isBefore(anchor) : end.isAfter(anchor)) end = anchor;
    }
    return end;
  }

  /// What's left of [event] from [start] to [end], as a new event: what
  /// was done there and who it was with, not what was said of it.
  static Map<String, Object?> _rest(Event event, DateTime start, DateTime end) {
    const kept = {
      'summary',
      'description',
      'location',
      'action_ids',
      'priority',
      'facts',
    };
    return {
      for (final MapEntry(:key, :value) in event.properties.entries)
        if (kept.contains(key) && value != null) key: value,
      'start': localIsoTimestamp(start),
      'end': localIsoTimestamp(end),
    };
  }

  /// [end], or the start of the first event between [start] and it, if
  /// one is.
  DateTime fitEnd(DateTime start, DateTime end) {
    for (final other in events) {
      if (!other.start.isBefore(start) && other.start.isBefore(end)) {
        return other.start;
      }
    }
    return end;
  }

  /// The first event that [start] to [end] would overlap, if any.
  Event? overlapping(DateTime start, DateTime end) {
    for (final other in events) {
      if (other.start.isBefore(end) && other.end.isAfter(start)) return other;
    }
    return null;
  }

  /// The quarter hour before [time]; [time] less a quarter if it's on one.
  static DateTime quarterBefore(DateTime time) {
    final floor = DateTime(
      time.year,
      time.month,
      time.day,
      time.hour,
      time.minute - time.minute % 15,
    );
    return floor.isBefore(time)
        ? floor
        : DateTime(
            time.year,
            time.month,
            time.day,
            time.hour,
            time.minute - 15,
          );
  }

  /// The quarter hour after [time].
  static DateTime quarterAfter(DateTime time) => DateTime(
    time.year,
    time.month,
    time.day,
    time.hour,
    time.minute - time.minute % 15 + 15,
  );

  /// Where "−15 min" moves [start] to, a quarter hour earlier but no
  /// earlier than the event before it ends; null if it can't move.
  DateTime? earlierStart(DateTime start) {
    var to = quarterBefore(start);
    if (earliestStart(start) case final earliest? when to.isBefore(earliest)) {
      to = earliest;
    }
    return to.isBefore(start) ? to : null;
  }

  /// Where "+15 min" moves [start] to, a quarter hour later, keeping at
  /// least [shortest] before [end]; null if it can't move.
  DateTime? laterStart(DateTime start, DateTime end) {
    final to = quarterAfter(start);
    return to.add(shortest).isAfter(end) ? null : to;
  }

  /// Where "−15 min" moves [end] to, a quarter hour earlier, keeping at
  /// least [shortest] after [start]; null if it can't move.
  DateTime? earlierEnd(DateTime start, DateTime end) {
    final to = quarterBefore(end);
    return to.isBefore(start.add(shortest)) ? null : to;
  }

  /// Where "+15 min" moves [end] to, a quarter hour later but no later
  /// than the event after it starts; null if it can't move.
  DateTime? laterEnd(DateTime end) {
    var to = quarterAfter(end);
    if (latestEnd(end) case final latest? when to.isAfter(latest)) {
      to = latest;
    }
    return to.isAfter(end) ? to : null;
  }
}

/// What [OtherEvents.pushing] does with an event the new one starts
/// inside of: cuts it short there, or splits it there, pushing along the
/// rest.
enum Inside { trim, split }

/// What a new event takes from the events already there, to overwrite
/// them ([OtherEvents.overwrite]): those to cancel, the changes to the
/// times of those to shorten, and the new events left of those it splits.
class Overwrite {
  const Overwrite({
    this.cancels = const [],
    this.updates = const [],
    this.creates = const [],
    this.countsAgainst = const {},
  });

  final List<Event> cancels;

  /// The ids of [cancels] that count against follow-through: commitments
  /// dropped, as the user said (see askFollowThrough). The rest are
  /// changes of plan.
  final Set<String> countsAgainst;

  /// It, with [ids] of its cancels counting against follow-through.
  Overwrite counting(Set<String> ids) => Overwrite(
    cancels: cancels,
    updates: updates,
    creates: creates,
    countsAgainst: ids,
  );

  /// Whether cancelling [event] counts against follow-through.
  bool counts(Event event) => countsAgainst.contains(event.id);
  final List<(Event, Map<String, Object?>)> updates;
  final List<Map<String, Object?>> creates;

  /// How many events it changes.
  int get count => cancels.length + updates.length;

  bool get isEmpty => count == 0;

  /// It as it's kept, waiting to be sent: each event whole, as it was.
  Map<String, Object?> toJson() => {
    'cancels': [for (final e in cancels) e.toJson()],
    'updates': [
      for (final (e, changes) in updates)
        {'event': e.toJson(), 'changes': changes},
    ],
    'creates': creates,
    if (countsAgainst.isNotEmpty) 'counts_against': [...countsAgainst],
  };

  factory Overwrite.fromJson(Map<String, dynamic> json) {
    Event event(Object? e) => Event.fromJson((e as Map).cast());
    return Overwrite(
      cancels: [for (final e in json['cancels'] as List? ?? []) event(e)],
      updates: [
        for (final u in json['updates'] as List? ?? [])
          (
            event((u as Map)['event']),
            (u['changes'] as Map).cast<String, Object?>(),
          ),
      ],
      creates: [
        for (final c in json['creates'] as List? ?? [])
          (c as Map).cast<String, Object?>(),
      ],
      countsAgainst: {
        for (final id in json['counts_against'] as List? ?? []) '$id',
      },
    );
  }
}
