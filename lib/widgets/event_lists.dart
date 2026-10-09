import 'package:flutter/material.dart';

import '../models/event.dart';
import '../models/note.dart';
import 'other_events.dart';

/// Events picked, in the order picked: a selection of them, by id, for
/// any purpose -- one [EventList]'s, say. Listeners hear every change.
/// A round of picking can be called off, putting it back as it was
/// ([begin], [revert]).
class EventSelection extends ChangeNotifier {
  EventSelection([Iterable<String> ids = const []]) : _ids = {...ids};

  Set<String> _ids;
  Set<String>? _before;

  /// The ids picked, in the order picked.
  Set<String> get ids => Set.unmodifiable(_ids);

  bool get isEmpty => _ids.isEmpty;
  bool contains(String? id) => _ids.contains(id);

  /// Picks [id], or unpicks it if it's picked.
  void toggle(String id) {
    if (!_ids.remove(id)) _ids.add(id);
    notifyListeners();
  }

  /// Unpicks [id], if it's picked.
  void remove(String id) {
    if (_ids.remove(id)) notifyListeners();
  }

  /// Sets what's picked to [ids].
  void set(Iterable<String> ids) {
    _ids = {...ids};
    notifyListeners();
  }

  /// Starts a round of picking: [revert] puts it back as it is now.
  void begin() => _before = {..._ids};

  /// Ends the round, keeping what was picked.
  void commit() => _before = null;

  /// Ends the round, putting back what was picked before it.
  void revert() {
    if (_before case final before?) _ids = before;
    _before = null;
    notifyListeners();
  }
}

/// A list of events a new or moved event's box treats as it says, in
/// place of trimming them: [keep] them as they are, the box going no
/// further; push them out of its way, [pushUp] or [pushDown]; or [cancel]
/// them.
enum EventList {
  keep(
    'Keep',
    'keep',
    "Kept as they are: the box, and what it pushes, doesn't go into them.",
    Icons.lock_outline,
  ),
  pushUp(
    'Push up',
    'push up',
    'Moved, whole, to just above the box, when it -- or what it pushes -- '
        'reaches them.',
    Icons.keyboard_double_arrow_up,
  ),
  pushDown(
    'Push down',
    'push down',
    'Moved, whole, to just below the box, when it -- or what it pushes -- '
        'reaches them.',
    Icons.keyboard_double_arrow_down,
  ),
  cancel('Cancel', 'cancel', 'Cancelled, whole.', Icons.event_busy);

  const EventList(this.label, this.verb, this.description, this.icon);

  final String label;

  /// What's done to them: "Select events to [verb]".
  final String verb;
  final String description;
  final IconData icon;
}

/// What a new or moved event's box from [start] to [end] does to the
/// [others], with [lists] saying what to do with some of them: each in no
/// list is trimmed where the box takes its time, or cancelled if it's
/// covered whole. Those to [EventList.pushDown] that the box -- or what
/// it pushes down -- reaches are moved whole to just below it, one after
/// another, in the order they were; those to [EventList.pushUp], just
/// above it. What's pushed trims what it runs into, as the box does, but
/// never moves it. Those to [EventList.cancel] are cancelled; those to
/// [EventList.keep] left be ([blocked] says whether they're in the way).
///
/// An event the box's [anchor] -- the cursor it was made from -- is
/// inside of is split there first: the part before it, the event itself;
/// the part after, a new one, in the same list.
class BoxEffect {
  BoxEffect(
    OtherEvents others, {
    required DateTime start,
    required DateTime end,
    DateTime? anchor,
    Map<EventList, Set<String>> lists = const {},
  }) {
    final listOf = <String, EventList>{
      for (final MapEntry(:key, :value) in lists.entries)
        for (final id in value) id: key,
    };
    // The pieces worked with: each event, or the two halves of the one
    // the anchor's inside of.
    final pieces = <_Piece>[];
    final split = anchor == null ? null : others.inside(anchor);
    for (final e in others.events) {
      final list = listOf[e.id];
      if (e == split && anchor != null) {
        pieces
          ..add(_Piece(e, e.start, anchor, list))
          ..add(_Piece(e, anchor, e.end, list, rest: true));
      } else {
        pieces.add(_Piece(e, e.start, e.end, list));
      }
    }
    // Pushed down: from the box's end, while what's pushed reaches more.
    var foot = end;
    var top = start;
    bool reaches(_Piece p, DateTime from, DateTime to) =>
        p.start.isBefore(to) && p.end.isAfter(from);
    final moved = <_Piece, (DateTime, DateTime)>{};
    // In the order they were: nearest the box first.
    final down = [
      for (final p in pieces)
        if (p.list == EventList.pushDown) p,
    ]..sort((a, b) => a.start.compareTo(b.start));
    final up = [
      for (final p in pieces)
        if (p.list == EventList.pushUp) p,
    ]..sort((a, b) => b.end.compareTo(a.end));
    for (var changed = true; changed;) {
      changed = false;
      for (final p in down) {
        if (moved.containsKey(p) || !reaches(p, start, foot)) continue;
        moved[p] = (foot, foot.add(p.length));
        foot = foot.add(p.length);
        changed = true;
      }
    }
    for (var changed = true; changed;) {
      changed = false;
      for (final p in up) {
        if (moved.containsKey(p) || !reaches(p, top, end)) continue;
        moved[p] = (top.subtract(p.length), top);
        top = top.subtract(p.length);
        changed = true;
      }
    }
    span = (top, foot);
    // What's left of each piece: moved, cancelled, kept, or trimmed out
    // of the span the box and what it pushes take.
    final kept = <_Piece>[];
    for (final p in pieces) {
      if (moved[p] case (final from, final to)) {
        p.place(from, to);
      } else if (p.list == EventList.cancel) {
        p.cancel();
      } else if (p.list == EventList.keep) {
        kept.add(p);
      } else {
        p.trim(top, foot);
      }
    }
    blocked = kept.any((p) => reaches(p, top, foot));

    // As changes: each event's first piece its own, its rest a new one.
    final cancels = <Event>[];
    final updates = <(Event, Map<String, Object?>)>[];
    final creates = <Map<String, Object?>>[];
    final rests = <Map<String, Object?>>[];
    for (final p in pieces) {
      final e = p.event;
      if (p.rest) {
        for (final (from, to) in p.left) {
          rests.add(OtherEvents.restOf(e, from, to));
        }
        continue;
      }
      final first = p.left.firstOrNull;
      if (first == null) {
        // Unless its rest is left, cancelled whole.
        cancels.add(e);
        continue;
      }
      final (from, to) = first;
      if (from != e.start || to != e.end) {
        updates.add((
          e,
          {
            if (from != e.start) 'start': localIsoTimestamp(from),
            if (to != e.end) 'end': localIsoTimestamp(to),
          },
        ));
      }
      for (final (from, to) in p.left.skip(1)) {
        creates.add(OtherEvents.restOf(e, from, to));
      }
    }
    overwrite = Overwrite(
      cancels: cancels,
      updates: updates,
      creates: [...creates, ...rests],
    );
    pushed = [
      for (final MapEntry(key: p, value: (from, to)) in moved.entries)
        (p.event, from, to, p.rest),
    ];
  }

  /// What it does to the others, as changes to write.
  late final Overwrite overwrite;

  /// What the box and what it pushes take, from the top of what's pushed
  /// up to the foot of what's pushed down.
  late final (DateTime, DateTime) span;

  /// Whether that runs into an event to keep: the box can't be there.
  late final bool blocked;

  /// Each event pushed, where it goes, and whether it's the rest of one
  /// split.
  late final List<(Event, DateTime, DateTime, bool)> pushed;
}

/// A piece of an event the box works with: the whole of it, or a half of
/// one split at the box's anchor ([rest], the later half); what's [left]
/// of it, once the box is done.
class _Piece {
  _Piece(this.event, this.start, this.end, this.list, {this.rest = false})
    : left = [(start, end)];

  final Event event;
  final DateTime start;
  final DateTime end;
  final EventList? list;
  final bool rest;
  List<(DateTime, DateTime)> left;

  Duration get length => end.difference(start);

  void place(DateTime from, DateTime to) => left = [(from, to)];

  void cancel() => left = [];

  /// Trimmed out of [from] to [to]: shortened, split around it, or gone.
  void trim(DateTime from, DateTime to) {
    if (!start.isBefore(to) || !end.isAfter(from)) return;
    left = [
      if (start.isBefore(from)) (start, from),
      if (end.isAfter(to)) (to, end),
    ];
  }
}
