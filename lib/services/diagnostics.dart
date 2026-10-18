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

/// Whose [statistic] of [values] is, by each one's entry in [names]: the
/// sample it falls on -- or, for the median of an even number, which is
/// halfway between two, both of theirs -- and every other of the same
/// value, as many calls time out alike: each name once, the commonest
/// first -- then the lower's, then the first given. Null for the mean,
/// which no one sample is, and for none.
List<String>? whoseStatistic(
  Statistic statistic,
  List<num> values,
  List<String> names,
) {
  if (values.isEmpty) return null;
  final sorted = [...values]..sort();
  final n = sorted.length;
  final ranks = switch (statistic) {
    Statistic.mean => const <int>[],
    Statistic.median => n.isOdd ? [n ~/ 2] : [n ~/ 2 - 1, n ~/ 2],
    Statistic.p95 => [(0.95 * (n - 1)).round()],
    Statistic.max => [n - 1],
  };
  if (ranks.isEmpty) return null;
  final at = {for (final r in ranks) sorted[r]};
  // Each name's count, lowest value and first place, in that order.
  final seen = <String, (int, num, int)>{};
  for (var i = 0; i < values.length; i++) {
    if (!at.contains(values[i])) continue;
    final (count, lowest, first) = seen[names[i]] ?? (0, values[i], i);
    seen[names[i]] = (count + 1, min(lowest, values[i]), first);
  }
  final whose = seen.keys.toList()
    ..sort((a, b) {
      final (countA, lowA, firstA) = seen[a]!;
      final (countB, lowB, firstB) = seen[b]!;
      return countB != countA
          ? countB.compareTo(countA)
          : lowA != lowB
          ? lowA.compareTo(lowB)
          : firstA.compareTo(firstB);
    });
  return whose;
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

/// A point of the memory graph, in MiB, and what it's made of when the
/// server said.
class MemoryPoint {
  const MemoryPoint({required this.at, required this.mib, this.parts});
  final DateTime at;
  final double mib;
  final List<MemoryPart>? parts;

  /// [parts], or with none, the whole of it as the rest of the server.
  List<MemoryPart> get partsOrWhole =>
      parts ?? [MemoryPart(name: MemoryPart.rest, mib: mib)];
}

/// A layer of the memory graph: a part of the server's memory -- or all
/// its sheet tabs together, as [sheets] -- with its MiB at each point.
class MemoryLayer {
  const MemoryLayer(this.name, this.values);

  /// A part's name, or [sheets].
  final String name;
  final List<double> values;

  static const sheets = 'Sheets';

  bool get isSheet => name == sheets || name.startsWith(MemoryPart.sheetPrefix);
}

/// [points]' parts as the memory graph stacks them, bottom up: the rest
/// of the server, whatever else isn't a sheet tab (the calendar), then
/// the sheet tabs, as the server first named them -- or with
/// [groupSheets], all of them as one. A point without a part has none
/// of it; one not broken down is all the rest of the server.
List<MemoryLayer> memoryLayers(
  List<MemoryPoint> points, {
  bool groupSheets = false,
}) {
  String layerOf(MemoryPart p) =>
      groupSheets && p.isSheet ? MemoryLayer.sheets : p.name;
  final others = <String>{MemoryPart.rest};
  final sheets = <String>{};
  for (final point in points) {
    for (final part in point.partsOrWhole) {
      (part.isSheet ? sheets : others).add(layerOf(part));
    }
  }
  return [
    for (final name in [...others, ...sheets])
      MemoryLayer(name, [
        for (final point in points)
          point.partsOrWhole
              .where((p) => layerOf(p) == name)
              .fold(0.0, (sum, p) => sum + p.mib),
      ]),
  ];
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
    return [
      for (final s in samples)
        MemoryPoint(at: s.at, mib: s.mib, parts: s.parts),
    ];
  }
  return [
    for (final (at, group) in _buckets(samples, (s) => s.at, bucket))
      () {
        final mib = statisticOf(statistic, [for (final s in group) s.mib]);
        return MemoryPoint(
          at: at,
          mib: mib,
          parts: statistic == Statistic.mean
              ? _meanParts(group)
              // The parts of the sample it falls on, or nearest it.
              : group
                    .reduce(
                      (a, b) =>
                          (b.mib - mib).abs() < (a.mib - mib).abs() ? b : a,
                    )
                    .parts,
        );
      }(),
  ];
}

/// Each part's mean over [samples], counting none of it where a sample
/// hasn't it, so they sum to the mean of their totals: a sample not
/// broken down counts as all the rest of the server. None, if none is.
List<MemoryPart>? _meanParts(List<MemorySample> samples) {
  if (samples.every((s) => s.parts == null)) return null;
  final sums = <String, double>{};
  for (final s in samples) {
    for (final p
        in s.parts ?? [MemoryPart(name: MemoryPart.rest, mib: s.mib)]) {
      sums[p.name] = (sums[p.name] ?? 0) + p.mib;
    }
  }
  // The rest last, as the server gives it.
  final rest = sums.remove(MemoryPart.rest);
  return [
    for (final MapEntry(:key, :value) in sums.entries)
      MemoryPart(name: key, mib: value / samples.length),
    if (rest != null)
      MemoryPart(name: MemoryPart.rest, mib: rest / samples.length),
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
