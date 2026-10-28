/// [iso], an ISO 8601 duration such as "PT1H30M", or null if it isn't one.
Duration? parseIsoDuration(String iso) {
  final match = RegExp(
    r'^P(?:(\d+)D)?(?:T(?:(\d+)H)?(?:(\d+)M)?(?:(\d+(?:\.\d+)?)S)?)?$',
  ).firstMatch(iso.trim());
  if (match == null || iso.trim() == 'P' || iso.trim().endsWith('T')) {
    return null;
  }
  int part(int i) => int.parse(match[i] ?? '0');
  return Duration(
    days: part(1),
    hours: part(2),
    minutes: part(3),
    microseconds: (double.parse(match[4] ?? '0') * 1e6).round(),
  );
}

/// [duration] as `update_event` takes it, e.g. "PT1H30M".
String isoDuration(Duration duration) {
  final hours = duration.inHours;
  final minutes = duration.inMinutes % 60;
  final seconds = duration.inSeconds % 60;
  if (duration == Duration.zero) return 'PT0S';
  return 'PT${hours > 0 ? '${hours}H' : ''}'
      '${minutes > 0 ? '${minutes}M' : ''}'
      '${seconds > 0 ? '${seconds}S' : ''}';
}

/// [duration] as one would write it, e.g. "1h 30m"; null for null.
String? formatDuration(Duration? duration) {
  if (duration == null) return null;
  final hours = duration.inHours;
  final minutes = duration.inMinutes % 60;
  final seconds = duration.inSeconds % 60;
  final parts = [
    if (hours > 0) '${hours}h',
    if (minutes > 0) '${minutes}m',
    if (seconds > 0) '${seconds}s',
  ];
  return parts.isEmpty ? '0m' : parts.join(' ');
}

/// [duration] in weeks, days, hours and minutes, as one would write it:
/// "1w 2d", "1d 3h"; "0d" for none.
String formatDays(Duration duration) {
  final minutes = duration.inMinutes;
  final parts = [
    if (minutes ~/ Duration.minutesPerDay ~/ 7 case final w when w > 0) '${w}w',
    if (minutes ~/ Duration.minutesPerDay % 7 case final d when d > 0) '${d}d',
    if (minutes ~/ 60 % 24 case final h when h > 0) '${h}h',
    if (minutes % 60 case final m when m > 0) '${m}m',
  ];
  return parts.isEmpty ? '0d' : parts.join(' ');
}

/// [duration] in days, hours and minutes, as one would write it: "8d 3h",
/// "5h"; "0h" for none.
String formatDaysHours(Duration duration) {
  final minutes = duration.inMinutes;
  final parts = [
    if (minutes ~/ Duration.minutesPerDay case final d when d > 0) '${d}d',
    if (minutes ~/ 60 % 24 case final h when h > 0) '${h}h',
    if (minutes % 60 case final m when m > 0) '${m}m',
  ];
  return parts.isEmpty ? '0h' : parts.join(' ');
}

/// A duration as one would type it: "1h 30m", "1h", "90m", "90" (minutes),
/// "1:30", with weeks and days too ("1w 2d", "1d 3h"), or ISO 8601
/// ("PT1H30M"). Null if [text] is none of those.
Duration? parseDuration(String text) {
  final t = text.trim().toLowerCase();
  if (t.startsWith('p')) return parseIsoDuration(t.toUpperCase());
  final clock = RegExp(r'^(\d+):([0-5]\d)$').firstMatch(t);
  if (clock != null) {
    return Duration(hours: int.parse(clock[1]!), minutes: int.parse(clock[2]!));
  }
  final minutes = int.tryParse(t);
  if (minutes != null) return Duration(minutes: minutes);
  final match = RegExp(
    r'^(?:(\d+)\s*w(?:eeks?|ks?)?)?\s*(?:(\d+)\s*d(?:ays?)?)?\s*'
    r'(?:(\d+)\s*h(?:ours?|rs?)?)?\s*(?:(\d+)\s*m(?:in(?:ute)?s?)?)?$',
  ).firstMatch(t);
  if (match == null || [1, 2, 3, 4].every((i) => match[i] == null)) {
    return null;
  }
  int part(int i) => int.parse(match[i] ?? '0');
  return Duration(
    days: part(1) * 7 + part(2),
    hours: part(3),
    minutes: part(4),
  );
}

/// [minutes] as "10h", "45m" or "1h 30m".
String formatMinutes(num minutes) {
  final total = minutes.round();
  final (hours, rest) = (total ~/ 60, total % 60);
  if (hours == 0) return '${rest}m';
  return rest == 0 ? '${hours}h' : '${hours}h ${rest}m';
}
