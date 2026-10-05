/// A single time note, mirroring the Time Tracker MCP server's `NotedTime`:
/// a moment worth recording, with an optional description of what it marks.
class Note {
  const Note({
    required this.timestamp,
    this.description,
    this.compactionId,
    this.id,
  });

  final DateTime timestamp;
  final String? description;

  /// Set once the note has been folded into an event by compaction.
  final String? compactionId;

  /// The server's id for the note, which edit_note and delete_note take;
  /// null until it's saved. It changes when the note's timestamp does.
  final String? id;

  bool get isCompacted => compactionId != null;

  factory Note.fromJson(Map<String, dynamic> json) => Note(
    timestamp: DateTime.parse(json['timestamp'] as String),
    description: json['description'] as String?,
    compactionId: json['compaction_id'] as String?,
    id: json['id'] as String?,
  );

  /// As the note tool's NotedTime, which has no id.
  Map<String, dynamic> toJson() => {
    // In the device's time zone, with its UTC offset: the server keeps the
    // offset, so the note reads as local time wherever it's shown.
    'timestamp': localIsoTimestamp(timestamp),
    if (description != null) 'description': description,
    if (compactionId != null) 'compaction_id': compactionId,
  };
}

/// When notes were last compacted into the calendar, and the latest note
/// compacted, mirroring the server's `get_compaction_status`.
class CompactionStatus {
  const CompactionStatus({
    this.lastCompaction,
    this.latestCompacted,
    this.judgmentsPending,
  });

  /// Null if notes have never been compacted.
  final DateTime? lastCompaction;
  final Note? latestCompacted;

  /// The last compaction's id, if the assistant hasn't yet judged all its
  /// events against people's traits: it isn't complete until then.
  final String? judgmentsPending;

  factory CompactionStatus.fromJson(Map<String, dynamic> json) =>
      CompactionStatus(
        lastCompaction: switch (json['last_compaction']) {
          final String at => DateTime.tryParse(at),
          _ => null,
        },
        latestCompacted: switch (json['latest_compacted_note']) {
          final Map note => Note.fromJson(note.cast<String, dynamic>()),
          _ => null,
        },
        judgmentsPending: json['judgments_pending'] as String?,
      );
}

/// [time] as ISO 8601 in the device's time zone, with its UTC offset at
/// that moment (so daylight saving is right), e.g. 2026-09-30T08:15:00-07:00.
/// Dart's own toIso8601String() leaves the offset off local times.
String localIsoTimestamp(DateTime time) {
  final local = time.toLocal();
  return isoTimestampWithOffset(local, local.timeZoneOffset);
}

/// [wallClock]'s date and time as written, followed by [offset].
String isoTimestampWithOffset(DateTime wallClock, Duration offset) {
  String two(int n) => n.toString().padLeft(2, '0');
  final t = wallClock;
  final fraction = t.millisecond == 0 && t.microsecond == 0
      ? ''
      : '.${t.millisecond.toString().padLeft(3, '0')}'
            '${t.microsecond == 0 ? '' : t.microsecond.toString().padLeft(3, '0')}';
  final sign = offset.isNegative ? '-' : '+';
  final minutes = offset.inMinutes.abs();
  return '${t.year.toString().padLeft(4, '0')}-${two(t.month)}-${two(t.day)}'
      'T${two(t.hour)}:${two(t.minute)}:${two(t.second)}$fraction'
      '$sign${two(minutes ~/ 60)}:${two(minutes % 60)}';
}
