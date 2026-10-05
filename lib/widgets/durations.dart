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

/// A duration as one would type it: "1h 30m", "1h", "90m", "90" (minutes),
/// "1:30", or ISO 8601 ("PT1H30M"). Null if [text] is none of those.
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
    r'^(?:(\d+)\s*h(?:ours?|rs?)?)?\s*(?:(\d+)\s*m(?:in(?:ute)?s?)?)?$',
  ).firstMatch(t);
  if (match == null || (match[1] == null && match[2] == null)) return null;
  return Duration(
    hours: int.parse(match[1] ?? '0'),
    minutes: int.parse(match[2] ?? '0'),
  );
}

/// [minutes] as "10h", "45m" or "1h 30m".
String formatMinutes(num minutes) {
  final total = minutes.round();
  final (hours, rest) = (total ~/ 60, total % 60);
  if (hours == 0) return '${rest}m';
  return rest == 0 ? '${hours}h' : '${hours}h ${rest}m';
}
