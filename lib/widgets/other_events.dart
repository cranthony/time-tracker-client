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

/// What a new event takes from the events already there, to overwrite
/// them ([OtherEvents.overwrite]): those to cancel, the changes to the
/// times of those to shorten, and the new events left of those it splits.
class Overwrite {
  const Overwrite({
    this.cancels = const [],
    this.updates = const [],
    this.creates = const [],
  });

  final List<Event> cancels;
  final List<(Event, Map<String, Object?>)> updates;
  final List<Map<String, Object?>> creates;

  /// How many events it changes.
  int get count => cancels.length + updates.length;

  bool get isEmpty => count == 0;
}
