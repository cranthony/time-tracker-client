import '../models/event.dart';

/// A Calendar event id in a server's message: 20 or more of `0-9a-v`
/// (Calendar's own, or one a compaction made), and, for one instance of a
/// series, `_` and when it was to start, in UTC ("_20261008T110000Z"),
/// quoted or not. Shorter ones -- a proposal's, a revision's -- aren't
/// matched.
final _eventId = RegExp(
  r"'?(?<![0-9A-Za-z_])([0-9a-v]{20,}(?:_(\d{8}T\d{6})Z?)?)(?![0-9A-Za-z])'?",
);

/// [message] with each event id in it named: "“Breakfast” (7:00 AM)" if
/// [lookup] finds it, or else "an event at 7:00 AM" for an instance of a
/// series (its id says when), or "an event" -- [time] saying when. With
/// the events found, each once, in the order they're first named.
({String text, List<Event> events}) nameEvents(
  String message, {
  required Event? Function(String id) lookup,
  required String Function(DateTime) time,
}) {
  final found = <String, Event>{};
  final text = message
      .replaceAll('valid event ids:', 'its events are')
      .replaceAllMapped(_eventId, (match) {
        final id = match[1]!;
        if (lookup(id) case final event?) {
          found[id] = event;
          final summary = switch (event.summary) {
            final s? when s.trim().isNotEmpty => '“${s.trim()}”',
            _ => 'an event with no title',
          };
          return '$summary (${time(event.start)})';
        }
        if (_instanceStart(match[2]) case final start?) {
          return 'an event at ${time(start)}';
        }
        return 'an event';
      });
  return (text: text, events: found.values.toList());
}

/// When an instance's id says it was to start: "20261008T110000", in UTC.
DateTime? _instanceStart(String? stamp) {
  if (stamp == null) return null;
  return DateTime.tryParse('${stamp}Z')?.toLocal();
}
