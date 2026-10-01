/// One of the calendar's event labels, mirroring the Time Tracker MCP
/// server's `EventLabel`.
///
/// Only the fields the app uses so far are typed; everything the server
/// sent stays in [properties].
class EventLabel {
  const EventLabel({
    this.id,
    this.name,
    this.backgroundColor,
    this.priority,
    this.fixedTime,
    this.properties = const {},
  });

  final String? id;
  final String? name;

  /// The calendar's color for the label, e.g. "#a4bdfc".
  final String? backgroundColor;

  /// Null when no event label sheet tracks the label.
  final int? priority;

  /// Whether the label's events stay at their set time; null if unknown.
  final bool? fixedTime;

  /// The label as the server sent it.
  final Map<String, dynamic> properties;

  factory EventLabel.fromJson(Map<String, dynamic> json) => EventLabel(
    id: json['id'] as String?,
    name: json['name'] as String?,
    backgroundColor: json['background_color'] as String?,
    priority: json['priority'] as int?,
    fixedTime: json['fixed_time'] as bool?,
    properties: Map.unmodifiable(json),
  );
}

/// [label]'s name, or "(no name)".
String labelName(EventLabel label) {
  final name = label.name;
  return name == null || name.isEmpty ? '(no name)' : name;
}
