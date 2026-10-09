import 'dart:math';

import '../models/server_health.dart';

/// What part of the app a server tool is for, to filter the Diagnostics
/// page's tool calls by.
enum ToolArea {
  events('Events'),
  notes('Notes'),
  proposals('Proposals and compaction'),
  people('People, traits and locations'),
  actions('Actions'),
  habits('Habits'),
  other('Other');

  const ToolArea(this.label);
  final String label;
}

/// [tool]'s area, by its name.
ToolArea areaOf(String tool) {
  bool has(String part) => tool.contains(part);
  if (has('habit')) return ToolArea.habits;
  if (has('proposal') || has('compact') || has('judgment')) {
    return ToolArea.proposals;
  }
  if (tool == 'note' || has('_note')) return ToolArea.notes;
  if (has('event') || has('recurrence') || has('time_zone')) {
    return ToolArea.events;
  }
  if (has('action') || has('priority')) return ToolArea.actions;
  if (has('trait') ||
      has('person') ||
      has('people') ||
      has('circle') ||
      has('location')) {
    return ToolArea.people;
  }
  return ToolArea.other;
}

/// The server's tools that only read: the rest may write. As the server
/// lists them (its tests' `_READ_ONLY_TOOLS`); one it adds later counts
/// as a write here until it's added.
const readOnlyTools = {
  'list_events',
  'get_event',
  'get_recurrence',
  'get_compaction_status',
  'get_proposal',
  'get_notes',
  'get_traits',
  'get_actions',
  'get_action',
  'get_action_groups',
  'get_action_group',
  'get_priority_colors',
  'get_people',
  'get_person',
  'get_circles',
  'get_circle',
  'get_locations',
  'get_location',
  'get_habits',
  'get_habit',
  'get_compaction_schedule_hints',
  'prepare_judgments',
  'prepare_habit_judgments',
  'get_health',
};

/// Which tools' calls the Diagnostics page shows.
sealed class ToolFilter {
  const ToolFilter();

  String get label;
  bool includes(String tool);
}

final class AllTools extends ToolFilter {
  const AllTools();
  @override
  String get label => 'All tools';
  @override
  bool includes(String tool) => true;
  @override
  bool operator ==(Object other) => other is AllTools;
  @override
  int get hashCode => 0;
}

/// Those that only read ([readOnlyTools]), or those that may write.
final class ReadsOrWrites extends ToolFilter {
  const ReadsOrWrites({required this.writes});
  final bool writes;
  @override
  String get label => writes ? 'Writes' : 'Reads';
  @override
  bool includes(String tool) => readOnlyTools.contains(tool) != writes;
  @override
  bool operator ==(Object other) =>
      other is ReadsOrWrites && other.writes == writes;
  @override
  int get hashCode => writes.hashCode;
}

final class InArea extends ToolFilter {
  const InArea(this.area);
  final ToolArea area;
  @override
  String get label => area.label;
  @override
  bool includes(String tool) => areaOf(tool) == area;
  @override
  bool operator ==(Object other) => other is InArea && other.area == area;
  @override
  int get hashCode => area.hashCode;
}

final class OneTool extends ToolFilter {
  const OneTool(this.tool);
  final String tool;
  @override
  String get label => tool;
  @override
  bool includes(String tool) => tool == this.tool;
  @override
  bool operator ==(Object other) => other is OneTool && other.tool == tool;
  @override
  int get hashCode => tool.hashCode;
}

/// The filters to pick from for [tools]: all, reads, writes, each area
/// one of them is in, then each of them.
List<ToolFilter> toolFilters(Iterable<String> tools) {
  final sorted = {...tools}.toList()..sort();
  final areas = {for (final t in sorted) areaOf(t)};
  return [
    const AllTools(),
    const ReadsOrWrites(writes: false),
    const ReadsOrWrites(writes: true),
    for (final area in ToolArea.values)
      if (areas.contains(area)) InArea(area),
    for (final tool in sorted) OneTool(tool),
  ];
}

/// How far back the graphs go, to start with.
enum TimeRange {
  day('Last day', Duration(days: 1)),
  week('Last week', Duration(days: 7)),
  all('Everything', null);

  const TimeRange(this.label, this.span);
  final String label;
  final Duration? span;
}

/// What a bucket of samples is shown as.
enum Statistic {
  mean('Mean'),
  median('Median'),
  p95('95th percentile'),
  max('Max');

  const Statistic(this.label);
  final String label;
}

/// How long each bucket of samples is.
enum BucketSize {
  quarterHour('15 minutes', Duration(minutes: 15)),
  hour('Hour', Duration(hours: 1)),
  sixHours('6 hours', Duration(hours: 6)),
  day('Day', Duration(days: 1));

  const BucketSize(this.label, this.span);
  final String label;
  final Duration span;
}

/// [statistic] of [values], none empty: a percentile is the nearest
/// rank's, as the server reckons it.
double statisticOf(Statistic statistic, List<num> values) {
  final sorted = [for (final v in values) v.toDouble()]..sort();
  return switch (statistic) {
    Statistic.mean => sorted.reduce((a, b) => a + b) / sorted.length,
    Statistic.median =>
      sorted.length.isOdd
          ? sorted[sorted.length ~/ 2]
          : (sorted[sorted.length ~/ 2 - 1] + sorted[sorted.length ~/ 2]) / 2,
    Statistic.p95 => sorted[(0.95 * (sorted.length - 1)).round()],
    Statistic.max => sorted.last,
  };
}

/// The mean, median, 95th percentile and max of some values.
class Summary {
  const Summary({
    required this.mean,
    required this.median,
    required this.p95,
    required this.max,
  });

  final double mean;
  final double median;
  final double p95;
  final double max;

  /// Of [values]; null for none.
  static Summary? of(List<num> values) => values.isEmpty
      ? null
      : Summary(
          mean: statisticOf(Statistic.mean, values),
          median: statisticOf(Statistic.median, values),
          p95: statisticOf(Statistic.p95, values),
          max: statisticOf(Statistic.max, values),
        );
}

/// A point of the tool calls' graph: a call, or a bucket of them, as
/// [statistic] has it -- the tools' own work, stacked under the rest of
/// the request to the whole request's time ([total]) -- with how many
/// calls it stands for, and how many failed.
class LatencyPoint {
  const LatencyPoint({
    required this.at,
    required this.work,
    required this.total,
    this.count = 1,
    this.errors = 0,
  });

  final DateTime at;
  final double work;
  final double total;
  final int count;
  final int errors;

  double get overhead => total - work;
}

/// A point of the memory graph, in MiB.
class MemoryPoint {
  const MemoryPoint({required this.at, required this.mib});
  final DateTime at;
  final double mib;
}

/// Which of [samples] fall in [from] to [to], each at [at].
List<T> within<T>(
  List<T> samples,
  DateTime Function(T) at,
  DateTime from,
  DateTime to,
) => [
  for (final s in samples)
    if (!at(s).isBefore(from) && !at(s).isAfter(to)) s,
];

/// [calls] as the graph shows them: each call, or with a [statistic],
/// those in each [bucket] (counted from the epoch, in UTC) as one point,
/// at its middle. A bucket's total is the statistic of its calls' whole
/// times, never less than of their work.
List<LatencyPoint> latencyPoints(
  List<ToolCall> calls, {
  Statistic? statistic,
  BucketSize bucket = BucketSize.hour,
}) {
  if (statistic == null) {
    return [
      for (final c in calls)
        LatencyPoint(
          at: c.at,
          work: c.workMs.toDouble(),
          total: c.wholeMs.toDouble(),
          errors: c.ok ? 0 : 1,
        ),
    ];
  }
  return [
    for (final (at, group) in _buckets(calls, (c) => c.at, bucket))
      () {
        final work = statisticOf(statistic, [for (final c in group) c.workMs]);
        final total = statisticOf(statistic, [
          for (final c in group) c.wholeMs,
        ]);
        return LatencyPoint(
          at: at,
          work: work,
          total: max(work, total),
          count: group.length,
          errors: group.where((c) => !c.ok).length,
        );
      }(),
  ];
}

/// [samples] as the memory graph shows them: each, or with a
/// [statistic], each [bucket]'s as one point.
List<MemoryPoint> memoryPoints(
  List<MemorySample> samples, {
  Statistic? statistic,
  BucketSize bucket = BucketSize.hour,
}) {
  if (statistic == null) {
    return [for (final s in samples) MemoryPoint(at: s.at, mib: s.mib)];
  }
  return [
    for (final (at, group) in _buckets(samples, (s) => s.at, bucket))
      MemoryPoint(
        at: at,
        mib: statisticOf(statistic, [for (final s in group) s.mib]),
      ),
  ];
}

/// [samples] grouped by [bucket], oldest first, each with its middle.
List<(DateTime, List<T>)> _buckets<T>(
  List<T> samples,
  DateTime Function(T) at,
  BucketSize bucket,
) {
  final span = bucket.span.inMilliseconds;
  final groups = <int, List<T>>{};
  for (final s in samples) {
    groups.putIfAbsent(at(s).millisecondsSinceEpoch ~/ span, () => []).add(s);
  }
  final keys = groups.keys.toList()..sort();
  return [
    for (final k in keys)
      (
        DateTime.fromMillisecondsSinceEpoch(k * span + span ~/ 2, isUtc: true),
        groups[k]!,
      ),
  ];
}
