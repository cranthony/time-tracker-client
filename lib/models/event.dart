import 'facts.dart';
import 'note.dart';
import 'share.dart';

/// A calendar event, mirroring the Time Tracker MCP server's `PublicEvent`.
///
/// Only the fields the app uses so far are typed; everything the server
/// sent, including app-specific properties, stays in [properties].
class Event {
  const Event({
    required this.start,
    required this.end,
    this.summary,
    this.id,
    this.isCancelled = false,
    this.properties = const {},
  });

  final DateTime start;
  final DateTime end;
  final String? summary;
  final String? id;
  final bool isCancelled;

  /// The event as the server sent it.
  final Map<String, dynamic> properties;

  /// The priority it's treated as: its own, else the highest (lowest
  /// numbered) among all its actions, each action's own or its nearest
  /// ancestor's; null if none of them has one.
  int? get effectivePriority =>
      properties['effective_priority'] as int? ??
      properties['priority'] as int?;

  /// Its actions, the first setting its color, and how much of it each
  /// takes.
  List<ActionShare> get actionShares => [
    for (final a in properties['action_ids'] as List? ?? const [])
      ?ActionShare.fromJson(a),
  ];

  /// The ids of its actions, the first setting its color.
  List<String> get actionIds => [for (final a in actionShares) a.actionId];

  /// The fraction of it each of its actions takes ([shareFractions]), by
  /// id -- as the summaries and traits' durations count its time -- with
  /// only those [counted] (all, without it) as its actions. What they
  /// leave is no action's.
  Map<String, double> actionFractions([bool Function(String id)? counted]) =>
      shareFractions(
        [
          for (final a in actionShares)
            if (counted == null || counted(a.actionId)) a,
        ],
        end.difference(start),
        split: RemainingSplit.even,
      );

  /// The names of [actionIds], in the same order, if the server sent them.
  List<String?> get actionNames => [
    for (final name in properties['action_names'] as List? ?? const [])
      name as String?,
  ];

  /// What compaction established about it, if anything.
  Facts? get facts => Facts.fromJson(properties['facts']);

  /// The fraction of it each person it was with takes, by id, as their
  /// shares say: each given neither takes all the remaining time, so
  /// together they may take more than all of it (see [scaledDown]).
  Map<String, double> get withFractions =>
      shareFractions(facts?.withShares ?? const [], end.difference(start));

  /// The fraction of it each person it was for takes, as [withFractions].
  Map<String, double> get forFractions =>
      shareFractions(facts?.forShares ?? const [], end.difference(start));

  /// The fraction of it each place it was at takes, by id, as their
  /// shares say: those given neither share the remaining time evenly.
  Map<String, double> get locationFractions => shareFractions(
    facts?.locationShares ?? const [],
    end.difference(start),
    split: RemainingSplit.even,
  );

  /// Whether it's getting from one place to another.
  bool get isCommute => facts?.commute ?? false;

  factory Event.fromJson(Map<String, dynamic> json) => Event(
    start: DateTime.parse(json['start'] as String),
    end: DateTime.parse(json['end'] as String),
    summary: json['summary'] as String?,
    id: json['id'] as String?,
    isCancelled: json['is_cancelled'] == true,
    properties: Map.unmodifiable(json),
  );

  /// The event as `update_event` takes it: as the server sent it, with the
  /// typed fields (times in local time) over the top.
  Map<String, Object?> toJson() => {
    ...properties,
    'id': id,
    'summary': summary,
    'start': localIsoTimestamp(start),
    'end': localIsoTimestamp(end),
    'is_cancelled': isCancelled,
  };
}
