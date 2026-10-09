import 'dart:math';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../models/server_health.dart';
import '../services/diagnostics.dart';
import '../services/diagnostics_repository.dart';
import '../widgets/status_message.dart';

/// How the app and the server are doing: the server's health metrics
/// ([DiagnosticsRepository]) on its **Server** pane, and the app's own on
/// its **App** pane -- swiped between, as the Plan page's are.
///
/// The server's are graphs of one time range, the latest on the right:
/// its tool calls' latencies -- each tool's own work, stacked under the
/// rest of its request, to the whole request's time, failed calls dotted
/// red -- its memory, and its restarts, ticked. Which tools' calls,
/// how far back, and each call or a statistic of each bucket of them are
/// picked from the menus above; each graph says the mean, median, 95th
/// percentile and max of what's in view. Pinching -- on a touchscreen or a
/// trackpad, or Ctrl and the mouse wheel -- or the buttons zooms all three
/// in on a stretch of time, two fingers drag it along, and a double tap
/// goes back to the whole range. Scrolling scrolls the page.
class DiagnosticsScreen extends StatefulWidget {
  const DiagnosticsScreen({
    super.key,
    required this.repository,
    this.clock = DateTime.now,
  });

  final DiagnosticsRepository repository;
  final DateTime Function() clock;

  @override
  State<DiagnosticsScreen> createState() => _DiagnosticsScreenState();
}

class _DiagnosticsScreenState extends State<DiagnosticsScreen> {
  ServerHealth? _health;
  Object? _error;
  bool _loading = true;

  ToolFilter _filter = const AllTools();
  TimeRange _range = TimeRange.day;
  Statistic? _statistic;
  BucketSize _bucket = BucketSize.hour;

  /// The stretch zoomed in on, if it is: within the range.
  (DateTime, DateTime)? _zoom;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final kept = _health == null
        ? await widget.repository.cachedServerHealth()
        : null;
    if (kept != null && mounted) setState(() => _health = kept);
    try {
      final health = await widget.repository.serverHealth();
      if (!mounted) return;
      setState(() {
        _health = health;
        _error = null;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  /// The whole range shown, before any zoom: back from now, or to the
  /// earliest sample.
  (DateTime, DateTime) get _window {
    final now = widget.clock().toUtc();
    final span = _range.span;
    if (span != null) return (now.subtract(span), now);
    final health = _health;
    final times = [
      if (health != null) ...[
        for (final t in health.tools)
          if (t.calls.isNotEmpty) t.calls.first.at,
        if (health.memory.isNotEmpty) health.memory.first.at,
        ...health.restarts,
      ],
    ];
    final earliest = times.isEmpty
        ? now.subtract(const Duration(days: 1))
        : times.reduce((a, b) => a.isBefore(b) ? a : b);
    return (earliest, now);
  }

  (DateTime, DateTime) get _shown => _zoom ?? _window;

  /// Zooms by [factor] (above 1, in) about [anchor] -- a fraction of the
  /// way across -- and moves by [shift], a fraction of the stretch shown.
  void _zoomBy(double factor, {double anchor = 0.5, double shift = 0}) {
    final (wholeFrom, wholeTo) = _window;
    final (from, to) = _shown;
    final whole = wholeTo.difference(wholeFrom).inMilliseconds;
    final span = to.difference(from).inMilliseconds;
    final next = (span / factor).clamp(
      min(60000, whole).toDouble(),
      whole.toDouble(),
    );
    final pivot = from.millisecondsSinceEpoch + anchor * span;
    var start = pivot - anchor * next - shift * next;
    start = start.clamp(
      wholeFrom.millisecondsSinceEpoch.toDouble(),
      wholeTo.millisecondsSinceEpoch - next,
    );
    setState(() {
      _zoom = next >= whole
          ? null
          : (
              DateTime.fromMillisecondsSinceEpoch(start.round(), isUtc: true),
              DateTime.fromMillisecondsSinceEpoch(
                (start + next).round(),
                isUtc: true,
              ),
            );
    });
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Diagnostics'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Server'),
              Tab(text: 'App'),
            ],
          ),
        ),
        body: TabBarView(children: [_server(context), const _AppPane()]),
      ),
    );
  }

  Widget _server(BuildContext context) {
    final health = _health;
    final error = _error;
    if (health == null) {
      if (_loading) return const Center(child: CircularProgressIndicator());
      return RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          children: [
            if (error != null && isUnknownTool(error))
              const _Note(
                icon: Icons.info_outline,
                text:
                    "The server doesn't report its health yet: it needs a "
                    'newer version.',
              )
            else if (error != null)
              LoadError(
                what: "the server's health",
                error: error,
                onRetry: _load,
              ),
          ],
        ),
      );
    }
    final (from, to) = _shown;
    final calls = within(
      [
        for (final t in health.tools)
          if (_filter.includes(t.tool)) ...t.calls,
      ]..sort((a, b) => a.at.compareTo(b.at)),
      (c) => c.at,
      from,
      to,
    );
    final memory = within(health.memory, (m) => m.at, from, to);
    final restarts = within(health.restarts, (r) => r, from, to);
    final filters = toolFilters([for (final t in health.tools) t.tool]);
    final filter = filters.contains(_filter) ? _filter : const AllTools();
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          if (error != null)
            LoadError(
              what: "the server's health",
              error: error,
              stale: true,
              onRetry: _load,
            ),
          _controls(context, filters, filter),
          _Zoomable(
            onZoom: _zoomBy,
            onReset: () => setState(() => _zoom = null),
            child: Column(
              children: [
                _LatencyCard(
                  calls: calls,
                  points: latencyPoints(
                    calls,
                    statistic: _statistic,
                    bucket: _bucket,
                  ),
                  from: from,
                  to: to,
                ),
                _MemoryCard(
                  memory: memory,
                  points: memoryPoints(
                    memory,
                    statistic: _statistic,
                    bucket: _bucket,
                  ),
                  from: from,
                  to: to,
                ),
                _RestartsCard(restarts: restarts, from: from, to: to),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _controls(
    BuildContext context,
    List<ToolFilter> filters,
    ToolFilter filter,
  ) {
    final strings = MaterialLocalizations.of(context);
    final (from, to) = _shown;
    String time(DateTime t) =>
        '${strings.formatShortMonthDay(t.toLocal())}, '
        '${strings.formatTimeOfDay(TimeOfDay.fromDateTime(t.toLocal()))}';
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 12,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _Picker<ToolFilter>(
                label: 'Tools',
                value: filter,
                items: {for (final f in filters) f: f.label},
                onChanged: (f) => setState(() => _filter = f),
              ),
              _Picker<TimeRange>(
                label: 'Range',
                value: _range,
                items: {for (final r in TimeRange.values) r: r.label},
                onChanged: (r) => setState(() {
                  _range = r;
                  _zoom = null;
                }),
              ),
              _Picker<Statistic?>(
                label: 'Show',
                value: _statistic,
                items: {
                  null: 'Each call',
                  for (final s in Statistic.values) s: s.label,
                },
                onChanged: (s) => setState(() => _statistic = s),
              ),
              if (_statistic != null)
                _Picker<BucketSize>(
                  label: 'Per',
                  value: _bucket,
                  items: {for (final b in BucketSize.values) b: b.label},
                  onChanged: (b) => setState(() => _bucket = b),
                ),
            ],
          ),
          Row(
            children: [
              Expanded(
                child: Text(
                  '${time(from)} – ${time(to)}${_zoom == null ? '' : ' (zoomed in)'}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
              IconButton(
                tooltip: 'Earlier',
                icon: const Icon(Icons.chevron_left),
                onPressed: _zoom == null ? null : () => _zoomBy(1, shift: 0.5),
              ),
              IconButton(
                tooltip: 'Zoom out',
                icon: const Icon(Icons.zoom_out),
                onPressed: _zoom == null ? null : () => _zoomBy(0.5),
              ),
              IconButton(
                tooltip: 'Zoom in',
                icon: const Icon(Icons.zoom_in),
                onPressed: () => _zoomBy(2),
              ),
              IconButton(
                tooltip: 'Later',
                icon: const Icon(Icons.chevron_right),
                onPressed: _zoom == null ? null : () => _zoomBy(1, shift: -0.5),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// A labelled drop-down of [items]' values, each with its label.
class _Picker<T> extends StatelessWidget {
  const _Picker({
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
  });

  final String label;
  final T value;
  final Map<T, String> items;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('$label: ', style: Theme.of(context).textTheme.labelLarge),
        DropdownButton<T>(
          value: value,
          isDense: true,
          onChanged: (v) {
            if (v != null || null is T) onChanged(v as T);
          },
          items: [
            for (final MapEntry(:key, :value) in items.entries)
              DropdownMenuItem<T>(value: key, child: Text(value)),
          ],
        ),
      ],
    );
  }
}

/// Turns pinches -- two fingers on a touchscreen (apart zooms in, moving
/// drags along), on a trackpad, or Ctrl and the mouse wheel, as browsers
/// send it -- and a double tap (back to the whole range) into [onZoom]s
/// and [onReset]s, for every graph in [child] at once: in time, across,
/// only. A [Listener], so scrolling, and a finger's own drags, still
/// scroll the page.
class _Zoomable extends StatefulWidget {
  const _Zoomable({
    required this.onZoom,
    required this.onReset,
    required this.child,
  });

  final void Function(double factor, {double anchor, double shift}) onZoom;
  final VoidCallback onReset;
  final Widget child;

  @override
  State<_Zoomable> createState() => _ZoomableState();
}

class _ZoomableState extends State<_Zoomable> {
  final _pointers = <int, Offset>{};

  /// A trackpad pinch's scale, as last seen.
  double _trackpadScale = 1;

  /// The two fingers' distance apart and middle, as last seen.
  (double, double)? _last;

  (double, double)? _pinch() {
    if (_pointers.length != 2) return null;
    final [a, b] = _pointers.values.toList();
    return ((a.dx - b.dx).abs(), (a.dx + b.dx) / 2);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // The graphs' plots: inside the cards' margins, and the value axis.
        final width = max(1.0, constraints.maxWidth - 104);
        double across(double x) => ((x - 80) / width).clamp(0.0, 1.0);
        return Listener(
          onPointerDown: (e) {
            _pointers[e.pointer] = e.localPosition;
            _last = _pinch();
          },
          onPointerMove: (e) {
            if (!_pointers.containsKey(e.pointer)) return;
            _pointers[e.pointer] = e.localPosition;
            final last = _last, now = _pinch();
            if (last == null || now == null) return;
            final (gap0, mid0) = last;
            final (gap1, mid1) = now;
            if (gap0 > 8 && gap1 > 8) {
              widget.onZoom(
                gap1 / gap0,
                anchor: across(mid1),
                shift: (mid1 - mid0) / width,
              );
            }
            _last = now;
          },
          onPointerUp: (e) {
            _pointers.remove(e.pointer);
            _last = _pinch();
          },
          onPointerCancel: (e) {
            _pointers.remove(e.pointer);
            _last = _pinch();
          },
          // Ctrl and the mouse wheel, as browsers send it: a pinch. The
          // wheel alone scrolls the page, as anywhere else.
          onPointerSignal: (e) {
            if (e is PointerScaleEvent && e.scale != 1) {
              GestureBinding.instance.pointerSignalResolver.register(e, (_) {
                widget.onZoom(e.scale, anchor: across(e.localPosition.dx));
              });
            }
          },
          // A trackpad's pinch. Its two-finger swipes come this way too:
          // a sideways one drags along; an up-and-down one is left to
          // scroll the page.
          onPointerPanZoomStart: (_) => _trackpadScale = 1,
          onPointerPanZoomUpdate: (e) {
            final factor = e.scale / _trackpadScale;
            _trackpadScale = e.scale;
            final sideways =
                e.localPanDelta.dx.abs() > e.localPanDelta.dy.abs();
            if (factor != 1 || sideways) {
              widget.onZoom(
                factor,
                anchor: across(e.localPosition.dx),
                shift: sideways ? e.localPanDelta.dx / width : 0,
              );
            }
          },
          child: GestureDetector(
            onDoubleTap: widget.onReset,
            child: widget.child,
          ),
        );
      },
    );
  }
}

/// A graph's card: its title, a line of what it shows, the graph, and a
/// table of what's in view.
class _GraphCard extends StatelessWidget {
  const _GraphCard({
    required this.title,
    this.subtitle,
    required this.graph,
    this.legend = const [],
    this.footer,
  });

  final String title;
  final String? subtitle;
  final Widget graph;
  final List<(Color, String)> legend;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 12, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: Text(title, style: theme.textTheme.titleMedium),
            ),
            if (subtitle != null)
              Padding(
                padding: const EdgeInsets.only(left: 8, bottom: 4),
                child: Text(subtitle!, style: theme.textTheme.bodySmall),
              ),
            if (legend.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(left: 8, bottom: 8),
                child: Wrap(
                  spacing: 16,
                  children: [
                    for (final (color, label) in legend)
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(width: 12, height: 12, color: color),
                          const SizedBox(width: 6),
                          Text(label, style: theme.textTheme.bodySmall),
                        ],
                      ),
                  ],
                ),
              ),
            Padding(padding: const EdgeInsets.only(top: 8), child: graph),
            if (footer != null)
              Padding(
                padding: const EdgeInsets.only(left: 8, top: 8),
                child: footer!,
              ),
          ],
        ),
      ),
    );
  }
}

String _ms(num ms) => ms >= 10000
    ? '${(ms / 1000).toStringAsFixed(0)} s'
    : ms >= 1000
    ? '${(ms / 1000).toStringAsFixed(1)} s'
    : '${ms.round()} ms';

String _mib(num mib) => '${mib.toStringAsFixed(mib >= 100 ? 0 : 1)} MiB';

/// The mean, median, 95th percentile and max of each row's values: a
/// row for each of [rows], under a header.
class _SummaryTable extends StatelessWidget {
  const _SummaryTable({required this.rows, required this.format, this.extra});

  final List<(String, Summary?)> rows;
  final String Function(num) format;

  /// One more column, after the rest: its header, and each row's.
  final (String, List<String>)? extra;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = theme.textTheme.bodySmall;
    final head = style?.copyWith(fontWeight: FontWeight.w600);
    Widget cell(String text, TextStyle? style, {bool end = true}) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 4),
      child: Text(
        text,
        style: style,
        maxLines: 1,
        softWrap: false,
        textAlign: end ? TextAlign.end : TextAlign.start,
      ),
    );
    final extra = this.extra;
    // Narrower than the card, it's scaled down to fit, not wrapped.
    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerLeft,
      child: Table(
        defaultColumnWidth: const IntrinsicColumnWidth(),
        children: [
          TableRow(
            children: [
              cell('', head),
              cell('Mean', head),
              cell('Median', head),
              cell('p95', head),
              cell('Max', head),
              if (extra != null) cell(extra.$1, head),
            ],
          ),
          for (final (i, (name, summary)) in rows.indexed)
            TableRow(
              children: [
                cell(name, head, end: false),
                for (final v in [
                  summary?.mean,
                  summary?.median,
                  summary?.p95,
                  summary?.max,
                ])
                  cell(v == null ? '–' : format(v), style),
                if (extra != null) cell(extra.$2[i], style),
              ],
            ),
        ],
      ),
    );
  }
}

/// The time axis's labels, across [from] to [to], in local time.
AxisTitles _timeAxis(BuildContext context, DateTime from, DateTime to) {
  final strings = MaterialLocalizations.of(context);
  final span = to.difference(from);
  final interval = max(1, span.inMilliseconds / 4).toDouble();
  return AxisTitles(
    sideTitles: SideTitles(
      showTitles: true,
      reservedSize: 28,
      interval: interval,
      getTitlesWidget: (value, meta) {
        if (value == meta.min || value == meta.max) {
          return const SizedBox.shrink();
        }
        final t = DateTime.fromMillisecondsSinceEpoch(
          value.round(),
          isUtc: true,
        ).toLocal();
        final text = span > const Duration(days: 2)
            ? strings.formatShortMonthDay(t)
            : strings.formatTimeOfDay(TimeOfDay.fromDateTime(t));
        return SideTitleWidget(
          meta: meta,
          child: Text(text, style: Theme.of(context).textTheme.labelSmall),
        );
      },
    ),
  );
}

AxisTitles _valueAxis(BuildContext context, String Function(num) format) =>
    AxisTitles(
      sideTitles: SideTitles(
        showTitles: true,
        reservedSize: 60,
        getTitlesWidget: (value, meta) {
          // The ends fall between the grid's lines: only those are labelled.
          if (value == meta.max || (value == meta.min && value != 0)) {
            return const SizedBox.shrink();
          }
          return SideTitleWidget(
            meta: meta,
            child: Text(
              format(value),
              maxLines: 1,
              softWrap: false,
              style: Theme.of(context).textTheme.labelSmall,
            ),
          );
        },
      ),
    );

const _noTitles = AxisTitles();

double _x(DateTime t) => t.millisecondsSinceEpoch.toDouble();

/// What's said in a graph with nothing in view.
Widget _empty(BuildContext context, String text) => SizedBox(
  height: 120,
  child: Center(
    child: Text(text, style: Theme.of(context).textTheme.bodyMedium),
  ),
);

/// The tool calls' graph: their own work, filled, under the rest of the
/// request, filled lighter, to the whole request's time; failed calls
/// dotted red.
class _LatencyCard extends StatelessWidget {
  const _LatencyCard({
    required this.calls,
    required this.points,
    required this.from,
    required this.to,
  });

  final List<ToolCall> calls;
  final List<LatencyPoint> points;
  final DateTime from;
  final DateTime to;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final work = colors.primary;
    final overhead = colors.tertiary;
    final failed = calls.where((c) => !c.ok).length;
    final top = points.isEmpty
        ? 1.0
        : points.map((p) => p.total).reduce(max) * 1.1;
    return _GraphCard(
      title: 'Tool calls',
      subtitle:
          '${calls.length} call${calls.length == 1 ? '' : 's'} in view'
          '${failed == 0 ? '' : ', $failed failed'}',
      legend: [
        (work, "The tool's work"),
        (overhead.withValues(alpha: 0.5), 'Auth and transport'),
        (colors.error, 'Failed'),
      ],
      graph: points.isEmpty
          ? _empty(context, 'No calls in view.')
          : SizedBox(
              height: 200,
              child: LineChart(
                LineChartData(
                  minX: _x(from),
                  maxX: _x(to),
                  minY: 0,
                  maxY: max(1, top),
                  clipData: const FlClipData.all(),
                  titlesData: FlTitlesData(
                    bottomTitles: _timeAxis(context, from, to),
                    leftTitles: _valueAxis(context, _ms),
                    topTitles: _noTitles,
                    rightTitles: _noTitles,
                  ),
                  borderData: FlBorderData(show: false),
                  lineBarsData: [
                    LineChartBarData(
                      spots: [for (final p in points) FlSpot(_x(p.at), p.work)],
                      color: work,
                      barWidth: 1.5,
                      dotData: const FlDotData(show: false),
                      belowBarData: BarAreaData(
                        show: true,
                        color: work.withValues(alpha: 0.35),
                      ),
                    ),
                    LineChartBarData(
                      spots: [
                        for (final p in points) FlSpot(_x(p.at), p.total),
                      ],
                      color: overhead,
                      barWidth: 1.5,
                      dotData: const FlDotData(show: false),
                    ),
                    LineChartBarData(
                      spots: [
                        for (final p in points)
                          if (p.errors > 0) FlSpot(_x(p.at), p.total),
                      ],
                      color: Colors.transparent,
                      barWidth: 0,
                      dotData: FlDotData(
                        getDotPainter: (_, _, _, _) => FlDotCirclePainter(
                          radius: 4,
                          color: colors.error,
                          strokeWidth: 0,
                        ),
                      ),
                    ),
                  ],
                  betweenBarsData: [
                    BetweenBarsData(
                      fromIndex: 0,
                      toIndex: 1,
                      color: overhead.withValues(alpha: 0.25),
                    ),
                  ],
                  lineTouchData: LineTouchData(
                    touchTooltipData: LineTouchTooltipData(
                      getTooltipItems: (spots) => [
                        for (final s in spots)
                          s.barIndex == 2
                              ? null
                              : LineTooltipItem(
                                  '${s.barIndex == 0 ? 'Work' : 'Total'} ${_ms(s.y)}',
                                  TextStyle(
                                    color: colors.onInverseSurface,
                                    fontSize: 12,
                                  ),
                                ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
      footer: _SummaryTable(
        format: _ms,
        rows: [
          ("Tool's work", Summary.of([for (final c in calls) c.workMs])),
          (
            'Auth and transport',
            Summary.of([
              for (final c in calls)
                if (c.totalMs != null) c.overheadMs,
            ]),
          ),
          ('Total', Summary.of([for (final c in calls) c.wholeMs])),
        ],
      ),
    );
  }
}

/// The server's memory after each call, whichever tool's.
class _MemoryCard extends StatelessWidget {
  const _MemoryCard({
    required this.memory,
    required this.points,
    required this.from,
    required this.to,
  });

  final List<MemorySample> memory;
  final List<MemoryPoint> points;
  final DateTime from;
  final DateTime to;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final values = [for (final p in points) p.mib];
    final low = values.isEmpty ? 0.0 : values.reduce(min);
    final high = values.isEmpty ? 1.0 : values.reduce(max);
    final pad = max(1.0, (high - low) * 0.15);
    return _GraphCard(
      title: 'Memory',
      subtitle:
          "The server's resident memory after each call, whichever tool's",
      graph: points.isEmpty
          ? _empty(context, 'No memory samples in view.')
          : SizedBox(
              height: 160,
              child: LineChart(
                LineChartData(
                  minX: _x(from),
                  maxX: _x(to),
                  minY: max(0, low - pad),
                  maxY: high + pad,
                  clipData: const FlClipData.all(),
                  titlesData: FlTitlesData(
                    bottomTitles: _timeAxis(context, from, to),
                    leftTitles: _valueAxis(context, _mib),
                    topTitles: _noTitles,
                    rightTitles: _noTitles,
                  ),
                  borderData: FlBorderData(show: false),
                  lineBarsData: [
                    LineChartBarData(
                      spots: [for (final p in points) FlSpot(_x(p.at), p.mib)],
                      color: colors.secondary,
                      barWidth: 2,
                      dotData: const FlDotData(show: false),
                    ),
                  ],
                  lineTouchData: LineTouchData(
                    touchTooltipData: LineTouchTooltipData(
                      getTooltipItems: (spots) => [
                        for (final s in spots)
                          LineTooltipItem(
                            _mib(s.y),
                            TextStyle(
                              color: colors.onInverseSurface,
                              fontSize: 12,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
      footer: _SummaryTable(
        format: _mib,
        rows: [
          ('Memory', Summary.of([for (final m in memory) m.mib])),
        ],
        extra: ('Latest', [memory.isEmpty ? '–' : _mib(memory.last.mib)]),
      ),
    );
  }
}

/// When the server started, each a tick: there's one server, so each is
/// a restart -- a crash or a deploy.
class _RestartsCard extends StatelessWidget {
  const _RestartsCard({
    required this.restarts,
    required this.from,
    required this.to,
  });

  final List<DateTime> restarts;
  final DateTime from;
  final DateTime to;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final strings = MaterialLocalizations.of(context);
    final n = restarts.length;
    String time(DateTime t) =>
        '${strings.formatShortMonthDay(t.toLocal())}, '
        '${strings.formatTimeOfDay(TimeOfDay.fromDateTime(t.toLocal()))}';
    return _GraphCard(
      title: 'Restarts',
      subtitle: n == 0
          ? 'None in view'
          : '$n in view, crashes or deploys: the last at ${time(restarts.last)}',
      graph: SizedBox(
        height: 76,
        child: LineChart(
          LineChartData(
            minX: _x(from),
            maxX: _x(to),
            minY: 0,
            maxY: 1,
            clipData: const FlClipData.all(),
            titlesData: FlTitlesData(
              bottomTitles: _timeAxis(context, from, to),
              leftTitles: const AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 60,
                  getTitlesWidget: _blank,
                ),
              ),
              topTitles: _noTitles,
              rightTitles: _noTitles,
            ),
            gridData: const FlGridData(show: false),
            borderData: FlBorderData(
              show: true,
              border: Border(bottom: BorderSide(color: theme.dividerColor)),
            ),
            // A chart with no line draws nothing at all, ticks and axis
            // included: an unseen one, across the range.
            lineBarsData: [
              LineChartBarData(
                spots: [FlSpot(_x(from), 0), FlSpot(_x(to), 0)],
                color: Colors.transparent,
                barWidth: 0,
                dotData: const FlDotData(show: false),
              ),
            ],
            extraLinesData: ExtraLinesData(
              verticalLines: [
                for (final r in restarts)
                  VerticalLine(
                    x: _x(r),
                    color: theme.colorScheme.error,
                    strokeWidth: 2,
                  ),
              ],
            ),
            lineTouchData: const LineTouchData(enabled: false),
          ),
        ),
      ),
    );
  }
}

Widget _blank(double value, TitleMeta meta) => const SizedBox.shrink();

class _Note extends StatelessWidget {
  const _Note({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          Icon(icon, size: 40, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(height: 12),
          Text(
            text,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyLarge,
          ),
        ],
      ),
    );
  }
}

/// The app's own metrics: none yet.
class _AppPane extends StatelessWidget {
  const _AppPane();

  @override
  Widget build(BuildContext context) => ListView(
    children: const [
      _Note(
        icon: Icons.phone_android,
        text: "The app's own metrics come later.",
      ),
    ],
  );
}
