/// A calendar event, mirroring the Time Tracker MCP server's `PublicEvent`.
///
/// Only the fields the app uses so far are typed; everything the server
/// sent, including app-specific properties, stays in [properties].
class Event {
  const Event({
    required this.start,
    required this.end,
    this.summary,
    this.id,
    this.isCancelled = false,
    this.properties = const {},
  });

  final DateTime start;
  final DateTime end;
  final String? summary;
  final String? id;
  final bool isCancelled;

  /// The event as the server sent it.
  final Map<String, dynamic> properties;

  factory Event.fromJson(Map<String, dynamic> json) => Event(
    start: DateTime.parse(json['start'] as String),
    end: DateTime.parse(json['end'] as String),
    summary: json['summary'] as String?,
    id: json['id'] as String?,
    isCancelled: json['is_cancelled'] == true,
    properties: Map.unmodifiable(json),
  );
}
