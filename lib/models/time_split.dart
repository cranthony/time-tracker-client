import 'event.dart';

/// How [from] to [to] is spent among [events]: for each stretch of it,
/// the events then, each with an even part of it. The stretches with no
/// events are null's. Cancelled events don't count.
Map<Event?, Duration> timeByEvent(
  List<Event> events,
  DateTime from,
  DateTime to,
) {
  DateTime clip(DateTime t) =>
      t.isBefore(from) ? from : (t.isAfter(to) ? to : t);
  final shown = [
    for (final event in events)
      if (!event.isCancelled && clip(event.end).isAfter(clip(event.start)))
        event,
  ];
  final edges = {
    from,
    to,
    for (final event in shown) ...[clip(event.start), clip(event.end)],
  }.toList()..sort();
  // Swept edge by edge, in order: each event joins those going on at its
  // start and leaves at its end, so each stretch looks only at those
  // going on in it, not at every event.
  final starting = [...shown]
    ..sort((a, b) => clip(a.start).compareTo(clip(b.start)));
  final ending = [...shown]..sort((a, b) => clip(a.end).compareTo(clip(b.end)));
  var started = 0, ended = 0;
  final during = <Event>[];
  final time = <Event?, Duration>{};
  for (var i = 0; i + 1 < edges.length; i++) {
    final (start, end) = (edges[i], edges[i + 1]);
    while (ended < ending.length && !clip(ending[ended].end).isAfter(start)) {
      final gone = ending[ended++];
      during.removeAt(during.indexWhere((e) => identical(e, gone)));
    }
    while (started < starting.length &&
        !clip(starting[started].start).isAfter(start)) {
      during.add(starting[started++]);
    }
    final length = end.difference(start);
    if (during.isEmpty) time[null] = (time[null] ?? Duration.zero) + length;
    for (final event in during) {
      time[event] = (time[event] ?? Duration.zero) + length ~/ during.length;
    }
  }
  return time;
}

/// [from] to [to]'s time by what each event counts toward, as [keysOf]
/// says, an event's time split evenly between its keys: an event with
/// none counts toward [none]. The time with no events is null's. Every
/// key's time adds up to the whole span.
Map<K?, Duration> timeBy<K>(
  List<Event> events,
  DateTime from,
  DateTime to,
  Iterable<K> Function(Event) keysOf,
  K none,
) {
  final time = <K?, Duration>{};
  for (final MapEntry(key: event, value: length) in timeByEvent(
    events,
    from,
    to,
  ).entries) {
    final keys = event == null ? {null} : keysOf(event).toSet();
    if (keys.isEmpty) keys.add(none);
    for (final key in keys) {
      time[key] = (time[key] ?? Duration.zero) + length ~/ keys.length;
    }
  }
  return time;
}

/// The two spans the Plan page's summaries measure: the 24 hours and 7
/// days up to [asOf], or with [forward], from it on.
class SummaryWindow {
  const SummaryWindow({required this.asOf, this.forward = false});

  final DateTime asOf;
  final bool forward;

  /// The [length] up to [asOf], or with [forward], from it.
  (DateTime, DateTime) span(Duration length) =>
      forward ? (asOf, asOf.add(length)) : (asOf.subtract(length), asOf);

  (DateTime, DateTime) get day => span(const Duration(hours: 24));
  (DateTime, DateTime) get week => span(const Duration(days: 7));

  /// The labels of [day]'s and [week]'s rows.
  (String, String) get labels => forward ? ('+24h', '+7d') : ('24h', '7d');

  /// [day] and [week]'s time, by [keysOf], as [timeBy] splits it.
  (Map<K?, Duration>, Map<K?, Duration>) split<K>(
    List<Event> events,
    Iterable<K> Function(Event) keysOf,
    K none,
  ) {
    final (dayFrom, dayTo) = day;
    final (weekFrom, weekTo) = week;
    return (
      timeBy(events, dayFrom, dayTo, keysOf, none),
      timeBy(events, weekFrom, weekTo, keysOf, none),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is SummaryWindow && other.asOf == asOf && other.forward == forward;

  @override
  int get hashCode => Object.hash(asOf, forward);
}
