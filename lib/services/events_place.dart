import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Where the Events page was left: the [day] shown, the time at the top
/// of the screen, the zoom, and when it was left.
class EventsPlace {
  const EventsPlace({
    required this.day,
    required this.top,
    required this.scale,
    required this.leftAt,
  });

  /// Midnight, local time, at the start of the day shown.
  final DateTime day;

  /// The time at the top of the screen.
  final DateTime top;

  /// The timeline's zoom.
  final double scale;
  final DateTime leftAt;

  /// How long the Events page is left for before it opens on now again.
  static const keptFor = Duration(minutes: 30);

  /// Whether to go back here at [now]: if it was left less than [keptFor]
  /// ago, and not on a day that's since become yesterday, so it never
  /// opens on yesterday just after midnight.
  bool keptAt(DateTime now) {
    final away = now.difference(leftAt);
    if (away.isNegative || away > keptFor) return false;
    final leftOn = DateTime(leftAt.year, leftAt.month, leftAt.day);
    final today = DateTime(now.year, now.month, now.day);
    return !(day == leftOn && today != leftOn);
  }

  Map<String, Object?> toJson() => {
    'day': day.toIso8601String(),
    'top': top.toIso8601String(),
    'scale': scale,
    'left_at': leftAt.millisecondsSinceEpoch,
  };

  factory EventsPlace.fromJson(Map<String, dynamic> json) => EventsPlace(
    day: DateTime.parse(json['day'] as String),
    top: DateTime.parse(json['top'] as String),
    scale: (json['scale'] as num).toDouble(),
    leftAt: DateTime.fromMillisecondsSinceEpoch(json['left_at'] as int),
  );
}

/// Keeps where the Events page was left: in memory, for switching back
/// to it, and on the device, for when the app is closed meanwhile.
class EventsPlaceStore {
  EventsPlaceStore({this.persist = true});

  /// Whether to keep it on the device too.
  final bool persist;

  EventsPlace? _place;

  /// Where it was left, if this store has been told since the app opened.
  EventsPlace? get remembered => _place;

  /// Where it was left: [remembered], or else what's kept on the device.
  /// Best effort: null if there's nothing kept, or it can't be read.
  Future<EventsPlace?> load() async {
    if (_place case final place?) return place;
    if (!persist) return null;
    try {
      final json = await SharedPreferencesAsync().getString(_key);
      if (json == null) return null;
      return _place ??= EventsPlace.fromJson(
        (jsonDecode(json) as Map).cast<String, dynamic>(),
      );
    } catch (_) {
      return null; // Nowhere to keep it, or from an older version.
    }
  }

  void save(EventsPlace place) {
    _place = place;
    if (!persist) return;
    try {
      SharedPreferencesAsync()
          .setString(_key, jsonEncode(place.toJson()))
          .catchError((_) {});
    } catch (_) {
      // Nowhere to keep it: it lasts until the app closes.
    }
  }

  static const _key = 'events_place';
}
