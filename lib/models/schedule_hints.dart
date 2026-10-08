/// When one of the user's scheduled Claude routines runs -- compacting
/// notes into a proposal, or answering the notes left on it -- as the
/// server's `get_compaction_schedule_hints` gives it: a time of day, and
/// what runs then. The routines set them; the app only reads them, to
/// fetch soon after each.
class ScheduleHint {
  const ScheduleHint({
    required this.hour,
    required this.minute,
    this.id,
    this.label,
  });

  final String? id;
  final int hour;
  final int minute;

  /// What runs then: "Morning compaction".
  final String? label;

  /// "07:30".
  String get time =>
      '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';

  /// One from the server; null for a time that isn't one (a hand edit).
  static ScheduleHint? fromJson(Object? json) {
    if (json is! Map) return null;
    final match = RegExp(r'^\s*(\d{1,2}):(\d{2})\s*$')
        .firstMatch('${json['time']}');
    if (match == null) return null;
    final hour = int.parse(match[1]!), minute = int.parse(match[2]!);
    if (hour > 23 || minute > 59) return null;
    return ScheduleHint(
      id: json['id'] as String?,
      hour: hour,
      minute: minute,
      label: switch (json['label']) {
        final String label when label.trim().isNotEmpty => label.trim(),
        _ => null,
      },
    );
  }

  Map<String, Object?> toJson() => {'id': ?id, 'time': time, 'label': ?label};
}

/// Every [ScheduleHint], earliest first, and the calendar's time zone,
/// which their times are in.
class ScheduleHints {
  const ScheduleHints({this.hints = const [], this.timeZone});

  final List<ScheduleHint> hints;

  /// An IANA name, "America/New_York"; null if the calendar has none.
  final String? timeZone;

  factory ScheduleHints.fromJson(Map<String, dynamic> json) => ScheduleHints(
    hints: [
      for (final h in json['hints'] as List? ?? const [])
        ?ScheduleHint.fromJson(h),
    ]..sort((a, b) => a.time.compareTo(b.time)),
    timeZone: json['time_zone'] as String?,
  );

  Map<String, Object?> toJson() => {
    'hints': [for (final h in hints) h.toJson()],
    'time_zone': ?timeZone,
  };
}
