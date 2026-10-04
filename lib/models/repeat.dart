/// How a recurring series repeats, mirroring the Time Tracker MCP server's
/// `Repeat`: its events fall at its first event's time of day, every
/// [interval]th day, week, month or year ([every]), on the days the rest
/// say. Leaving out [weekdays], [nthWeekdays], [monthDays] and [months]
/// repeats on the first event's own day.
///
/// The app edits [every], [interval], [weekdays] and how it ends ([count]
/// or [until]); the rest are kept as the server sent them.
class Repeat {
  const Repeat({
    required this.every,
    this.interval = 1,
    this.weekdays,
    this.nthWeekdays,
    this.monthDays,
    this.months,
    this.count,
    this.until,
    this.properties = const {},
  });

  /// "day", "week", "month" or "year".
  final String every;
  final int interval;

  /// E.g. ["mon", "wed"].
  final List<String>? weekdays;

  /// E.g. [{"nth": -1, "weekday": "fri"}] for the last Friday.
  final List<Map<String, Object?>>? nthWeekdays;

  /// 1 to 31, or -1 for the last day.
  final List<int>? monthDays;

  /// 1 (January) to 12.
  final List<int>? months;

  /// How many events it has, from its first; at most one of this and
  /// [until] is set, and neither for a series that never ends.
  final int? count;

  /// An ISO 8601 date ("2026-12-31", through the end of that day) or
  /// timestamp: no event starts after it.
  final String? until;

  /// The repeat as the server sent it, including what isn't typed
  /// (`week_starts_on`, `skipped`, `added`), which is sent back as it was.
  final Map<String, Object?> properties;

  static const weekdayKeys = ['mon', 'tue', 'wed', 'thu', 'fri', 'sat', 'sun'];

  /// [weekdayKeys]' day, for [DateTime.weekday] (Monday is 1).
  static String weekdayOf(DateTime day) => weekdayKeys[day.weekday - 1];

  factory Repeat.fromJson(Map<String, Object?> json) => Repeat(
    every: json['every'] as String,
    interval: json['interval'] as int? ?? 1,
    weekdays: (json['weekdays'] as List?)?.cast<String>(),
    nthWeekdays: [
      for (final nth in json['nth_weekdays'] as List? ?? const [])
        (nth as Map).cast<String, Object?>(),
    ].nullIfEmpty,
    monthDays: (json['month_days'] as List?)?.cast<int>(),
    months: (json['months'] as List?)?.cast<int>(),
    count: json['count'] as int?,
    until: json['until'] as String?,
    properties: Map.unmodifiable(json),
  );

  /// As `update_recurrence` takes it: whole, since it replaces how the
  /// series repeats whole.
  Map<String, Object?> toJson() => {
    ...properties,
    'every': every,
    'interval': interval,
    'weekdays': weekdays,
    'nth_weekdays': nthWeekdays,
    'month_days': monthDays,
    'months': months,
    'count': count,
    'until': until,
  }..removeWhere((_, value) => value == null);

  /// It, with what's given changed. [clearDays] drops [weekdays],
  /// [nthWeekdays], [monthDays] and [months] first; [clearEnd], [count]
  /// and [until].
  Repeat copyWith({
    String? every,
    int? interval,
    List<String>? weekdays,
    bool clearDays = false,
    int? count,
    String? until,
    bool clearEnd = false,
  }) => Repeat(
    every: every ?? this.every,
    interval: interval ?? this.interval,
    weekdays: weekdays ?? (clearDays ? null : this.weekdays),
    nthWeekdays: clearDays ? null : nthWeekdays,
    monthDays: clearDays ? null : monthDays,
    months: clearDays ? null : months,
    count: count ?? (clearEnd || until != null ? null : this.count),
    until: until ?? (clearEnd || count != null ? null : this.until),
    properties: properties,
  );

  @override
  bool operator ==(Object other) =>
      other is Repeat && _sameJson(toJson(), other.toJson());

  @override
  int get hashCode => every.hashCode ^ interval.hashCode;

  /// In words, like the server's `schedule`: "Every week on Mon, Wed",
  /// "Every 2 months on the 1st, until Dec 31, 2026".
  String describe() {
    final unit = interval == 1 ? every : '${every}s';
    final parts = [interval == 1 ? 'Every $unit' : 'Every $interval $unit'];
    final days = [
      for (final nth in nthWeekdays ?? const <Map<String, Object?>>[])
        'the ${_nths[nth['nth']] ?? '${nth['nth']}th'} '
            '${_dayNames[nth['weekday']] ?? nth['weekday']}',
      for (final day in weekdays ?? const <String>[]) _dayNames[day] ?? day,
      for (final day in monthDays ?? const <int>[])
        day == -1 ? 'the last day' : 'the ${_ordinal(day)}',
    ];
    if (days.isNotEmpty) parts.add('on ${days.join(', ')}');
    if (months case final months? when months.isNotEmpty) {
      parts.add(
        'in ${[for (final m in months) _monthNames[m - 1]].join(', ')}',
      );
    }
    var said = parts.join(' ');
    if (count case final count?) {
      said += ', ${count == 1 ? 'once' : '$count times'}';
    } else if (until case final until?) {
      said += ', until ${formatDay(DateTime.parse(until))}';
    }
    return said;
  }

  /// "Dec 31, 2026".
  static String formatDay(DateTime day) =>
      '${_monthNames[day.month - 1]} ${day.day}, ${day.year}';

  static const _dayNames = {
    'mon': 'Mon',
    'tue': 'Tue',
    'wed': 'Wed',
    'thu': 'Thu',
    'fri': 'Fri',
    'sat': 'Sat',
    'sun': 'Sun',
  };
  static const _nths = {
    1: 'first',
    2: 'second',
    3: 'third',
    4: 'fourth',
    5: 'fifth',
    -1: 'last',
  };
  static const _monthNames = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];

  static String _ordinal(int n) => switch (n % 100) {
    11 || 12 || 13 => '${n}th',
    _ => switch (n % 10) {
      1 => '${n}st',
      2 => '${n}nd',
      3 => '${n}rd',
      _ => '${n}th',
    },
  };
}

bool _sameJson(Object? a, Object? b) => switch ((a, b)) {
  (final Map a, final Map b) =>
    a.length == b.length &&
        a.keys.every((k) => b.containsKey(k) && _sameJson(a[k], b[k])),
  (final List a, final List b) =>
    a.length == b.length &&
        [for (var i = 0; i < a.length; i++) i]
            .every((i) => _sameJson(a[i], b[i])),
  _ => a == b,
};

extension<T> on List<T> {
  List<T>? get nullIfEmpty => isEmpty ? null : this;
}
