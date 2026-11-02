/// The user's circadian rhythm, as the server's `get_circadian_rhythm`
/// gives it: the times they woke naturally ([WakeRevision]s), and how
/// wide the windows either side of their temperature minimum are
/// ([CircadianWindows]). The app works out each day's minimum and windows
/// itself ([CircadianRhythm.spansOn]), so they're there offline too.
library;

/// How the temperature minimum and the windows either side of it are
/// worked out from the time the user woke naturally, in minutes.
class CircadianWindows {
  const CircadianWindows({
    this.minimumBeforeWaking = 120,
    this.dimBefore = 360,
    this.brightAfter = 240,
  });

  /// How long before waking the temperature minimum is.
  final int minimumBeforeWaking;

  /// How long before the minimum the dim window starts: light and
  /// exercise then shift the user's schedule later.
  final int dimBefore;

  /// How long after the minimum the bright window lasts: bright light
  /// and exercise then hold the schedule, or shift it earlier.
  final int brightAfter;

  /// The most any of them can be: a day.
  static const most = 1440;

  factory CircadianWindows.fromJson(Object? json) {
    if (json is! Map) return const CircadianWindows();
    int minutes(String key, int fallback) => switch (json[key]) {
      final num n when n >= 0 && n <= most => n.round(),
      _ => fallback,
    };
    return CircadianWindows(
      minimumBeforeWaking: minutes('minimum_before_waking_minutes', 120),
      dimBefore: minutes('dim_before_minutes', 360),
      brightAfter: minutes('bright_after_minutes', 240),
    );
  }

  Map<String, Object?> toJson() => {
    'minimum_before_waking_minutes': minimumBeforeWaking,
    'dim_before_minutes': dimBefore,
    'bright_after_minutes': brightAfter,
  };

  @override
  bool operator ==(Object other) =>
      other is CircadianWindows &&
      other.minimumBeforeWaking == minimumBeforeWaking &&
      other.dimBefore == dimBefore &&
      other.brightAfter == brightAfter;

  @override
  int get hashCode => Object.hash(minimumBeforeWaking, dimBefore, brightAfter);
}

/// "2026-11-02", of [day].
String circadianDate(DateTime day) =>
    '${day.year.toString().padLeft(4, '0')}-'
    '${day.month.toString().padLeft(2, '0')}-'
    '${day.day.toString().padLeft(2, '0')}';

/// [hour] and [minute] as "06:40".
String circadianTime(int hour, int minute) =>
    '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';

/// When the user woke naturally on a day: in effect from then till the
/// next one's day.
class WakeRevision {
  const WakeRevision({
    this.id,
    required this.date,
    required this.hour,
    required this.minute,
    this.note,
  });

  final String? id;

  /// The day, at midnight.
  final DateTime date;
  final int hour;
  final int minute;

  /// What the user said of it: "woke without alarm".
  final String? note;

  /// "06:40".
  String get time => circadianTime(hour, minute);

  /// One from the server; null for one that isn't one (a hand edit).
  static WakeRevision? fromJson(Object? json) {
    if (json is! Map) return null;
    final date = RegExp(r'^\s*(\d{4})-(\d{2})-(\d{2})\s*$')
        .firstMatch('${json['date']}');
    final time = RegExp(r'^\s*(\d{1,2}):(\d{2})\s*$')
        .firstMatch('${json['time']}');
    if (date == null || time == null) return null;
    final hour = int.parse(time[1]!), minute = int.parse(time[2]!);
    if (hour > 23 || minute > 59) return null;
    return WakeRevision(
      id: json['id'] as String?,
      date: DateTime(
        int.parse(date[1]!),
        int.parse(date[2]!),
        int.parse(date[3]!),
      ),
      hour: hour,
      minute: minute,
      note: switch (json['note']) {
        final String note when note.trim().isNotEmpty => note.trim(),
        _ => null,
      },
    );
  }

  Map<String, Object?> toJson() => {
    'id': ?id,
    'date': circadianDate(date),
    'time': time,
    'note': ?note,
  };
}

/// Which of the windows either side of the temperature minimum a
/// [CircadianSpan] is.
enum CircadianKind {
  /// Before the minimum: light and exercise shift the schedule later.
  dim,

  /// After it: bright light and exercise hold it, or shift it earlier.
  bright,
}

/// One of a day's windows, from [start] to [end], and the [minimum] it's
/// either side of.
typedef CircadianSpan = ({
  CircadianKind kind,
  DateTime start,
  DateTime end,
  DateTime minimum,
});

/// A day's temperature minimum and its windows, unclipped.
typedef CircadianDay = ({
  WakeRevision revision,
  DateTime minimum,
  ({DateTime start, DateTime end}) dim,
  ({DateTime start, DateTime end}) bright,
});

/// The user's [revisions], oldest first, and the [windows] they're
/// worked out with; their times are in the calendar's [timeZone].
class CircadianRhythm {
  const CircadianRhythm({
    this.windows = const CircadianWindows(),
    this.revisions = const [],
    this.timeZone,
  });

  final CircadianWindows windows;
  final List<WakeRevision> revisions;

  /// An IANA name, "America/New_York"; null if the calendar has none.
  /// The app takes it as the device's, as it does the routines' times.
  final String? timeZone;

  factory CircadianRhythm.fromJson(Map<String, dynamic> json) =>
      CircadianRhythm(
        windows: CircadianWindows.fromJson(json['windows']),
        revisions: [
          for (final r in json['revisions'] as List? ?? const [])
            ?WakeRevision.fromJson(r),
        ]..sort((a, b) => a.date.compareTo(b.date)),
        timeZone: json['time_zone'] as String?,
      );

  Map<String, Object?> toJson() => {
    'time_zone': timeZone,
    'windows': windows.toJson(),
    'revisions': [for (final r in revisions) r.toJson()],
  };

  /// The revision in effect on [day]: the latest on or before it; null
  /// if there's none.
  WakeRevision? revisionOn(DateTime day) {
    final date = DateTime(day.year, day.month, day.day);
    WakeRevision? found;
    for (final r in revisions) {
      if (r.date.isAfter(date)) break;
      found = r;
    }
    return found;
  }

  /// [day]'s temperature minimum -- [CircadianWindows.minimumBeforeWaking]
  /// before the time it says the user wakes, so perhaps the evening
  /// before -- and its windows; null with no revision in effect.
  CircadianDay? dayOf(DateTime day) {
    final revision = revisionOn(day);
    if (revision == null) return null;
    final waking = DateTime(
      day.year,
      day.month,
      day.day,
      revision.hour,
      revision.minute,
    );
    final minimum = waking.subtract(
      Duration(minutes: windows.minimumBeforeWaking),
    );
    return (
      revision: revision,
      minimum: minimum,
      dim: (
        start: minimum.subtract(Duration(minutes: windows.dimBefore)),
        end: minimum,
      ),
      bright: (
        start: minimum,
        end: minimum.add(Duration(minutes: windows.brightAfter)),
      ),
    );
  }

  /// The windows to shade on [day], from midnight to midnight: its own,
  /// and those of the days either side of it that reach into it, each
  /// cut off at its midnights. Earliest first.
  List<CircadianSpan> spansOn(DateTime day) {
    final from = DateTime(day.year, day.month, day.day);
    final to = DateTime(day.year, day.month, day.day + 1);
    return [
      for (final offset in const [-1, 0, 1])
        if (dayOf(DateTime(day.year, day.month, day.day + offset))
            case final d?)
          for (final (kind, window) in [
            (CircadianKind.dim, d.dim),
            (CircadianKind.bright, d.bright),
          ])
            if (window.end.isAfter(window.start) &&
                window.start.isBefore(to) &&
                window.end.isAfter(from))
              (
                kind: kind,
                start: window.start.isBefore(from) ? from : window.start,
                end: window.end.isAfter(to) ? to : window.end,
                minimum: d.minimum,
              ),
    ]..sort((a, b) => a.start.compareTo(b.start));
  }
}
