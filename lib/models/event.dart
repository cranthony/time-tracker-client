import 'note.dart';

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

  /// The priority it's treated as: its own, else the highest (lowest
  /// numbered) among all its goals, each goal's own or its nearest
  /// ancestor's; null if none of them has one.
  int? get effectivePriority =>
      properties['effective_priority'] as int? ??
      properties['priority'] as int?;

  /// The ids of the goals it serves, primary goal first.
  List<String> get goalIds => [
    for (final id in properties['goal_ids'] as List? ?? const []) '$id',
  ];

  /// The names of [goalIds], in the same order, if the server sent them.
  List<String?> get goalNames => [
    for (final name in properties['goal_names'] as List? ?? const [])
      name as String?,
  ];

  factory Event.fromJson(Map<String, dynamic> json) => Event(
    start: DateTime.parse(json['start'] as String),
    end: DateTime.parse(json['end'] as String),
    summary: json['summary'] as String?,
    id: json['id'] as String?,
    isCancelled: json['is_cancelled'] == true,
    properties: Map.unmodifiable(json),
  );

  /// The event as `update_event` takes it: as the server sent it, with the
  /// typed fields (times in local time) over the top.
  Map<String, Object?> toJson() => {
    ...properties,
    'id': id,
    'summary': summary,
    'start': localIsoTimestamp(start),
    'end': localIsoTimestamp(end),
    'is_cancelled': isCancelled,
  };
}
