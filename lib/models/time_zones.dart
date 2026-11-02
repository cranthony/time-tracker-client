import 'package:timezone/data/latest_10y.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

/// The IANA time zones events can be kept in (an event's or series'
/// `time_zone`), from the tz database the app carries: their offsets, and
/// a time's clock in one.

bool _loaded = false;

/// The tz database, loaded the first time it's needed.
void _load() {
  if (_loaded) return;
  tzdata.initializeTimeZones();
  _loaded = true;
}

/// The regions whose zones are offered to pick from: the rest of the
/// database is old aliases ("US/Eastern") of these.
const _regions = {
  'Africa',
  'America',
  'Antarctica',
  'Asia',
  'Atlantic',
  'Australia',
  'Europe',
  'Indian',
  'Pacific',
};

/// The zones to pick from, by name: each region's, and UTC.
List<String> zoneNames() {
  _load();
  return [
    'UTC',
    ...tz.timeZoneDatabase.locations.keys.where(
      (name) => _regions.contains(name.split('/').first),
    ),
  ]..sort();
}

/// The zone [name], if the database has it.
tz.Location? zoneOf(String? name) {
  if (name == null || name.isEmpty) return null;
  // Google's name for it; the database's is "Etc/UTC".
  if (name == 'UTC') return tz.UTC;
  _load();
  try {
    return tz.getLocation(name);
  } on tz.LocationNotFoundException {
    return null;
  }
}

/// How far ahead of UTC [zone] is at [at]; null if there's no such zone.
Duration? zoneOffset(String zone, DateTime at) =>
    zoneOf(zone)?.timeZone(at.millisecondsSinceEpoch).offset;

/// What [zone] is called at [at]: "EST", say; null if there's no such
/// zone, or only its offset names it ("+0530").
String? zoneAbbreviation(String zone, DateTime at) {
  final abbreviation = zoneOf(zone)
      ?.timeZone(at.millisecondsSinceEpoch)
      .abbreviation;
  return abbreviation == null || RegExp(r'^[+-]\d').hasMatch(abbreviation)
      ? null
      : abbreviation;
}

/// An offset from UTC as it's written: "UTC−5", "UTC+5:30", "UTC".
String offsetLabel(Duration offset) {
  if (offset == Duration.zero) return 'UTC';
  final minutes = offset.inMinutes.abs();
  final sign = offset.isNegative ? '−' : '+';
  final hours = minutes ~/ 60;
  final rest = minutes % 60;
  return 'UTC$sign$hours${rest == 0 ? '' : ':${'$rest'.padLeft(2, '0')}'}';
}

/// [zone]'s place, as one would say it: "New York" for
/// "America/New_York", "Indiana/Knox" for "America/Indiana/Knox".
String zonePlace(String zone) {
  final parts = zone.split('/');
  final place = parts.length == 1 ? zone : parts.skip(1).join('/');
  return place.replaceAll('_', ' ');
}

/// [zone] at [at] in a few words: "New York (EST, UTC−5)"; "UTC".
String zoneLabel(String zone, DateTime at) {
  final offset = zoneOffset(zone, at);
  if (offset == null) return zone;
  final abbreviation = zoneAbbreviation(zone, at);
  final said = offsetLabel(offset);
  if (zonePlace(zone) == said) return said;
  return '${zonePlace(zone)} '
      '(${abbreviation == null || abbreviation == said ? said : '$abbreviation, $said'})';
}

/// [at]'s clock in [zone] -- the year, month, day, hour and minute one
/// would read there -- as a local [DateTime] holding them; in this
/// device's zone if [zone] is null or isn't one.
DateTime clockIn(DateTime at, String? zone) {
  final location = zoneOf(zone);
  if (location == null) return at.toLocal();
  final there = tz.TZDateTime.from(at, location);
  return DateTime(
    there.year,
    there.month,
    there.day,
    there.hour,
    there.minute,
    there.second,
  );
}

/// The moment [clock] -- a time of day on a day -- comes in [zone]; in
/// this device's zone if [zone] is null or isn't one.
DateTime atClockIn(DateTime clock, String? zone) {
  final location = zoneOf(zone);
  if (location == null) {
    return DateTime(
      clock.year,
      clock.month,
      clock.day,
      clock.hour,
      clock.minute,
      clock.second,
    );
  }
  return DateTime.fromMillisecondsSinceEpoch(
    tz.TZDateTime(
      location,
      clock.year,
      clock.month,
      clock.day,
      clock.hour,
      clock.minute,
      clock.second,
    ).millisecondsSinceEpoch,
  );
}

/// [at], kept at the same time of day as it's moved from zone [from]
/// (this device's, if null) to [to]: 6pm in New York becomes 6pm in
/// London.
DateTime sameClock(DateTime at, String? from, String to) =>
    atClockIn(clockIn(at, from), to);

/// Whether [at]'s clock in [zone] reads differently from this device's:
/// whether its time there is worth saying too.
bool clockDiffers(DateTime at, String zone) => switch (zoneOffset(zone, at)) {
  final offset? => offset != at.toLocal().timeZoneOffset,
  null => false,
};
