import 'note.dart';

/// A recurring series of events, as a whole, mirroring the Time Tracker MCP
/// server's `PublicRecurrence`: its own id (every one of its events'
/// `recurring_event_id`), when its first event starts and ends, its RFC
/// 5545 [rules], and its [schedule] in words. Its other properties apply
/// to every event in it that wasn't edited on its own.
///
/// Only the fields the app uses are typed; everything the server sent
/// stays in [properties].
class Recurrence {
  const Recurrence({
    required this.id,
    required this.start,
    required this.end,
    this.summary,
    this.rules = const [],
    this.schedule,
    this.properties = const {},
  });

  final String id;
  final DateTime start;
  final DateTime end;
  final String? summary;

  /// E.g. ["RRULE:FREQ=WEEKLY;BYDAY=MO,WE"].
  final List<String> rules;

  /// [rules] in words, e.g. "Every week on Mon, Wed".
  final String? schedule;

  /// The series as the server sent it.
  final Map<String, dynamic> properties;

  factory Recurrence.fromJson(Map<String, dynamic> json) => Recurrence(
    id: json['id'] as String,
    start: DateTime.parse(json['start'] as String),
    end: DateTime.parse(json['end'] as String),
    summary: json['summary'] as String?,
    rules: [...(json['rules'] as List? ?? const []).cast<String>()],
    schedule: json['schedule'] as String?,
    properties: Map.unmodifiable(json),
  );

  /// The series as the server sent it, with the typed fields (times in
  /// local time) over the top.
  Map<String, Object?> toJson() => {
    ...properties,
    'id': id,
    'summary': summary,
    'start': localIsoTimestamp(start),
    'end': localIsoTimestamp(end),
    'rules': rules,
    'schedule': schedule,
  };
}
