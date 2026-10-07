import 'event.dart';
import 'facts.dart';
import 'person.dart';
import 'time_split.dart';

/// What the People pane says of each person beside their health, as the
/// Plan page's summary measures it: their time with the user in its 24
/// hours and 7 days -- each event's time split evenly among those there,
/// as "By person" splits it -- and the event with them nearest its
/// window: the last that started before it, or, looking on ("Next"), the
/// first that starts in or after it.
class PeopleTimes {
  PeopleTimes._(this.window, this._day, this._week, this._nearest);

  /// Measures [window] from [windowEvents] (null until they're loaded),
  /// and finds the nearest event with each person among [known]: every
  /// event the app has.
  factory PeopleTimes.compute({
    required SummaryWindow window,
    required List<Event>? windowEvents,
    required List<Event> known,
  }) {
    List<String> withIds(Event e) =>
        Facts.fromJson(e.properties['facts'])?.withIds ?? const [];
    final (day, week) = windowEvents == null
        ? (null, null)
        : window.split<String>(windowEvents, withIds, '');
    final nearest = <String, Event>{};
    for (final e in known) {
      if (e.isCancelled) continue;
      final ahead = !e.start.isBefore(window.asOf);
      if (ahead != window.forward) continue;
      for (final id in withIds(e)) {
        final had = nearest[id];
        if (had == null ||
            (window.forward
                ? e.start.isBefore(had.start)
                : e.start.isAfter(had.start))) {
          nearest[id] = e;
        }
      }
    }
    return PeopleTimes._(window, day, week, nearest);
  }

  final SummaryWindow window;
  final Map<String?, Duration>? _day;
  final Map<String?, Duration>? _week;
  final Map<String, Event> _nearest;

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
}) {
  Comparable<Object>? key(Person p) => switch (sort) {
    PeopleSort.listed => null,
    PeopleSort.health => health(p.id),
    PeopleSort.seen => times?.nearest(p.id)?.start,
    PeopleSort.day => times?.day(p.id),
    PeopleSort.week => times?.week(p.id),
  } as Comparable<Object>?;
  if (sort == PeopleSort.listed) return people;
  final indexed = [
    for (final (i, p) in people.indexed)
      if (!p.isSelf) (i, p, key(p)),
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
    for (final p in people)
      if (p.isSelf) p,
    for (final (_, p, _) in indexed) p,
  ];
}
