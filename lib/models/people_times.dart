import 'dart:math' as math;

import 'event.dart';
import 'facts.dart';
import 'person.dart';
import 'time_split.dart';

/// What the People pane says of each person beside their health, as the
/// Plan page's summary measures it: their time with the user in its 24
/// hours and 7 days -- each one's share of each event they were at
/// ([Event.withFractions]: with no share, all the time the others'
/// shares leave, as goals take it) -- and the event with them nearest its
/// window: the last that started before it, or, looking on ("Next"), the
/// first that starts in or after it.
class PeopleTimes {
  PeopleTimes._(
    this.window,
    this._day,
    this._week,
    this._nearest,
    this._circleDay,
    this._circleWeek,
    this._circleNearest,
  );

  /// Measures [window] from [windowEvents] (null until they're loaded),
  /// and finds the nearest event with each person among [known]: every
  /// event the app has. Each of [circles] -- its people's ids, by its id
  /// -- is measured as well: the time with any of its people, each
  /// event's counted once, their shares of it together, up to all of it.
  factory PeopleTimes.compute({
    required SummaryWindow window,
    required List<Event>? windowEvents,
    required List<Event> known,
    Map<String, Iterable<String>> circles = const {},
  }) {
    List<String> withIds(Event e) =>
        Facts.fromJson(e.properties['facts'])?.withIds ?? const [];
    final members = {
      for (final MapEntry(:key, :value) in circles.entries) key: {...value},
    };
    Map<String, double> circleFractions(Event e) {
      final fractions = e.withFractions;
      return {
        for (final MapEntry(key: id, value: people) in members.entries)
          if (people.any(fractions.containsKey))
            id: math.min(
              1.0,
              people.fold(0.0, (sum, p) => sum + (fractions[p] ?? 0)),
            ),
      };
    }

    final (day, week) = windowEvents == null
        ? (null, null)
        : window.splitParts<String>(windowEvents, (e) => e.withFractions, '');
    final (circleDay, circleWeek) = windowEvents == null
        ? (null, null)
        : window.splitParts<String>(windowEvents, circleFractions, '');
    final nearest = <String, Event>{};
    final circleNearest = <String, Event>{};
    void keep(Map<String, Event> nearest, String id, Event e) {
      final had = nearest[id];
      if (had == null ||
          (window.forward
              ? e.start.isBefore(had.start)
              : e.start.isAfter(had.start))) {
        nearest[id] = e;
      }
    }

    for (final e in known) {
      if (e.isCancelled) continue;
      final ahead = !e.start.isBefore(window.asOf);
      if (ahead != window.forward) continue;
      final ids = withIds(e);
      for (final id in ids) {
        keep(nearest, id, e);
      }
      for (final MapEntry(key: id, value: people) in members.entries) {
        if (ids.any(people.contains)) keep(circleNearest, id, e);
      }
    }
    return PeopleTimes._(
      window,
      day,
      week,
      nearest,
      circleDay,
      circleWeek,
      circleNearest,
    );
  }

  final SummaryWindow window;
  final Map<String?, Duration>? _day;
  final Map<String?, Duration>? _week;
  final Map<String, Event> _nearest;
  final Map<String?, Duration>? _circleDay;
  final Map<String?, Duration>? _circleWeek;
  final Map<String, Event> _circleNearest;

  /// Whether the window's events are in, for [day] and [week] to say.
  bool get measured => _day != null;

  /// [personId]'s time with the user in the window's 24 hours, or 7
  /// days; null until they're measured.
  Duration? day(String personId) =>
      _day == null ? null : _day[personId] ?? Duration.zero;
  Duration? week(String personId) =>
      _week == null ? null : _week[personId] ?? Duration.zero;

  /// The last event with [personId] before the window, or, looking on,
  /// the next; null if there's none the app has.
  Event? nearest(String personId) => _nearest[personId];

  /// [day], [week] and [nearest] for a circle measured, by its id: with
  /// any of its people.
  Duration? circleDay(String circleId) =>
      _circleDay == null ? null : _circleDay[circleId] ?? Duration.zero;
  Duration? circleWeek(String circleId) =>
      _circleWeek == null ? null : _circleWeek[circleId] ?? Duration.zero;
  Event? circleNearest(String circleId) => _circleNearest[circleId];
}

/// What the list of everyone can be sorted by.
enum PeopleSort {
  /// As the server lists them.
  listed('As listed'),
  health('Relationship health'),

  /// When they were last seen, or, looking on, will next be.
  seen('Last seen'),
  day('Time in 24h'),
  week('Time in 7d');

  const PeopleSort(this.label);

  final String label;

  /// Its label, looking on with [forward]: "Next seen", "Time in +24h".
  String labelFor({required bool forward}) => !forward
      ? label
      : switch (this) {
          seen => 'Next seen',
          day => 'Time in +24h',
          week => 'Time in +7d',
          _ => label,
        };
}

/// [people] sorted by [sort], [ascending] or not: by [health] (from each
/// one's id), or by [times]. Those with nothing to sort by go last,
/// either way; ties keep their order. Self stays first.
List<Person> sortPeople(
  List<Person> people,
  PeopleSort sort, {
  required bool ascending,
  required int? Function(String id) health,
  PeopleTimes? times,
}) => sortByPeopleSort(
  people,
  sort,
  ascending: ascending,
  first: (p) => p.isSelf,
  health: (p) => health(p.id),
  seen: (p) => times?.nearest(p.id)?.start,
  day: (p) => times?.day(p.id),
  week: (p) => times?.week(p.id),
);

/// [rows] -- people, or people and circles -- sorted by [sort],
/// [ascending] or not: by their [health], when they were [seen], or
/// their time in the [day] or [week]. Those with nothing to sort by go
/// last, either way; ties keep their order. Those [first] stay first.
List<T> sortByPeopleSort<T>(
  List<T> rows,
  PeopleSort sort, {
  required bool ascending,
  bool Function(T row)? first,
  required int? Function(T row) health,
  required DateTime? Function(T row) seen,
  required Duration? Function(T row) day,
  required Duration? Function(T row) week,
}) {
  Comparable<Object>? key(T row) => switch (sort) {
    PeopleSort.listed => null,
    PeopleSort.health => health(row),
    PeopleSort.seen => seen(row),
    PeopleSort.day => day(row),
    PeopleSort.week => week(row),
  } as Comparable<Object>?;
  if (sort == PeopleSort.listed) return rows;
  bool isFirst(T row) => first?.call(row) ?? false;
  final indexed = [
    for (final (i, row) in rows.indexed)
      if (!isFirst(row)) (i, row, key(row)),
  ];
  indexed.sort((a, b) {
    final (ia, _, ka) = a;
    final (ib, _, kb) = b;
    if (ka == null || kb == null) {
      if (ka == null && kb == null) return ia.compareTo(ib);
      return ka == null ? 1 : -1;
    }
    final by = ascending ? ka.compareTo(kb) : kb.compareTo(ka);
    return by != 0 ? by : ia.compareTo(ib);
  });
  return [
    for (final row in rows)
      if (isFirst(row)) row,
    for (final (_, row, _) in indexed) row,
  ];
}
