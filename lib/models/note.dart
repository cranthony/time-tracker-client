/// A single time note, mirroring the Time Tracker MCP server's `NotedTime`:
/// a moment worth recording, with an optional description of what it marks.
class Note {
  const Note({required this.timestamp, this.description, this.compactionId});

  final DateTime timestamp;
  final String? description;

  /// Set once the note has been folded into an event by compaction.
  final String? compactionId;

  bool get isCompacted => compactionId != null;

  factory Note.fromJson(Map<String, dynamic> json) => Note(
    timestamp: DateTime.parse(json['timestamp'] as String),
    description: json['description'] as String?,
    compactionId: json['compaction_id'] as String?,
  );

  Map<String, dynamic> toJson() => {
    // Always send UTC with an explicit offset so the server never has to
    // guess the phone's time zone.
    'timestamp': timestamp.toUtc().toIso8601String(),
    if (description != null) 'description': description,
    if (compactionId != null) 'compaction_id': compactionId,
  };
}
