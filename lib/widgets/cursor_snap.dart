import '../services/app_settings.dart';

/// What a cursor on the timeline stops at, besides the grid's lines: the
/// edges of events, notes, both, or neither.
enum SnapTo {
  events('Event edges'),
  notes('Notes');

  const SnapTo(this.label);

  final String label;
}

/// Which cursor it is, for what it snaps to, kept for each: a new or
/// moved event's anchor -- where it was started from -- and its end; and
/// the end of a compaction's window, extended.
enum CursorRole {
  anchor('anchor'),
  end('end'),
  windowEnd('window_end');

  const CursorRole(this.key);

  /// How it's kept on the device.
  final String key;
}

/// The times a cursor stops at, in order: the [grid]'s lines from [from]
/// to [to] (every minute, with none), and the [edges] and [notes] given
/// -- those of what it snaps to.
class CursorStops {
  CursorStops({
    required this.from,
    required this.to,
    required this.grid,
    Iterable<DateTime> edges = const [],
    Iterable<DateTime> notes = const [],
  }) : _marks = ({
         ...edges,
         ...notes,
       }.where((t) => !t.isBefore(from) && !t.isAfter(to)).toList()..sort());

  /// The stretch of time it stops in.
  final DateTime from;
  final DateTime to;
  final Duration? grid;

  /// The edges' and notes' times, in order, each once.
  final List<DateTime> _marks;

  /// The grid's line on or past [time], [later] or earlier.
  DateTime _line(DateTime time, {required bool later}) {
    final step = (grid?.inMinutes ?? 1).clamp(1, 24 * 60);
    final midnight = DateTime(time.year, time.month, time.day);
    final minutes = time.difference(midnight).inSeconds / 60;
    final n = later ? (minutes / step).ceil() : (minutes / step).floor();
    return DateTime(time.year, time.month, time.day, 0, n * step);
  }

  /// The next stop [later] than [time] -- or earlier -- if there's one
  /// before the ends.
  DateTime? next(DateTime time, {required bool later}) {
    // On the grid of the day as it's lived: local time.
    time = time.toLocal();
    var line = _line(time, later: later);
    if (line.isAtSameMomentAs(time)) {
      line = _line(time.add(Duration(minutes: later ? 1 : -1)), later: later);
    }
    final mark = later
        ? _marks.where((m) => m.isAfter(time)).firstOrNull
        : _marks.where((m) => m.isBefore(time)).lastOrNull;
    final stop = switch (mark) {
      final m? when later ? m.isBefore(line) : m.isAfter(line) => m,
      _ => line,
    };
    if (stop.isBefore(from) || stop.isAfter(to)) return null;
    return stop;
  }

  /// Where a cursor dragged to [time] stops: at an edge or a note within
  /// [reach] of it, the nearest; or else on the grid's nearest line.
  DateTime nearest(DateTime time, {required Duration reach}) {
    time = time.toLocal();
    DateTime? best;
    for (final mark in _marks) {
      final gap = mark.difference(time).abs();
      if (gap <= reach && (best == null || gap < best.difference(time).abs())) {
        best = mark;
      }
    }
    return best ?? snapToGrid(time, grid);
  }
}
