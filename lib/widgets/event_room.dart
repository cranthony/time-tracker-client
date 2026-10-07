import '../models/event.dart';
import '../models/note.dart';

/// The other events an event's times are kept clear of, so that changing
/// them never makes it overlap one.
///
/// Overlaps it already has are left alone: only the times being changed
/// are kept clear.
class EventRoom {
  /// The [events] other than the one with id [except], and not cancelled.
  EventRoom(Iterable<Event> events, {String? except})
    : others = [
        for (final event in events)
          if (!event.isCancelled && (except == null || event.id != except))
            event,
      ]..sort((a, b) => a.start.compareTo(b.start));

  /// No other events: nothing to keep clear of.
  const EventRoom.none() : others = const [];

  /// Sorted by start.
  final List<Event> others;

  /// The shortest the quick buttons make an event.
  static const shortest = Duration(minutes: 15);

  /// The end of the last event that ends by [start]: how early it can
  /// start. Null if none does.
  DateTime? earliestStart(DateTime start) {
    DateTime? earliest;
    for (final other in others) {
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
    for (final other in others) {
      if (!other.start.isBefore(end)) return other.start;
    }
    return null;
  }

  /// The event it would start inside of, at [start].
  Event? _around(DateTime start) {
    for (final other in others) {
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

  /// What a new event from [start] to [end] takes from the others to fit,
  /// overwriting them: each it covers whole is cancelled; each it covers
  /// one end of is shortened to it; and one it falls inside of is split
  /// around it, the part after it made a new event.
  Overwrite overwrite(DateTime start, DateTime end) {
    final cancels = <Event>[];
    final updates = <(Event, Map<String, Object?>)>[];
    final creates = <Map<String, Object?>>[];
    for (final other in others) {
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
    for (final other in others) {
      if (!other.start.isBefore(start) && other.start.isBefore(end)) {
        return other.start;
      }
    }
    return end;
  }

  /// The first event that [start] to [end] would overlap, if any.
  Event? overlapping(DateTime start, DateTime end) {
    for (final other in others) {
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
/// them ([EventRoom.overwrite]): those to cancel, the changes to the
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
