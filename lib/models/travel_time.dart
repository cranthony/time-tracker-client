import '../widgets/durations.dart' show formatMinutes;

/// How long one way of getting somewhere takes: [minutes], or from
/// [minutes] to [maxMinutes].
class TravelMode {
  const TravelMode({
    required this.modeId,
    required this.minutes,
    this.maxMinutes,
  });

  /// The action or action group it's done by ("Drive", "Transit").
  final String modeId;
  final int minutes;

  /// The most it takes, if it varies.
  final int? maxMinutes;

  factory TravelMode.fromJson(Map<String, dynamic> json) => TravelMode(
    modeId: json['mode_id'] as String,
    minutes: (json['minutes'] as num).round(),
    maxMinutes: (json['max_minutes'] as num?)?.round(),
  );

  Map<String, Object?> toJson() => {
    'mode_id': modeId,
    'minutes': minutes,
    'max_minutes': ?maxMinutes,
  };

  /// "25m", or "25m–40m" when it varies.
  String get describe => switch (maxMinutes) {
    final max? when max != minutes =>
      '${formatMinutes(minutes)}–${formatMinutes(max)}',
    _ => formatMinutes(minutes),
  };
}

/// Roughly how long it takes to get between two places -- each a location
/// or a location group -- by each way of getting there, mirroring the
/// server's `TravelTime`. It counts both ways unless it's [oneWay].
class TravelTime {
  const TravelTime({
    required this.id,
    required this.fromId,
    required this.toId,
    this.oneWay = false,
    this.times = const [],
    this.note,
  });

  final String id;
  final String fromId;
  final String toId;

  /// Whether it's only from [fromId] to [toId].
  final bool oneWay;
  final List<TravelMode> times;
  final String? note;

  factory TravelTime.fromJson(Map<String, dynamic> json) => TravelTime(
    id: json['id'] as String? ?? '',
    fromId: json['from_id'] as String? ?? '',
    toId: json['to_id'] as String? ?? '',
    oneWay: json['one_way'] == true,
    times: [
      for (final t in json['times'] as List? ?? const [])
        TravelMode.fromJson((t as Map).cast<String, dynamic>()),
    ],
    note: switch (json['note']) {
      final String note when note.trim().isNotEmpty => note,
      _ => null,
    },
  );

  /// As `create_travel_time` takes it.
  Map<String, Object?> toJson() => {
    'id': id,
    'from_id': fromId,
    'to_id': toId,
    'one_way': oneWay,
    'times': [for (final t in times) t.toJson()],
    'note': ?note,
  };
}
