import 'dart:math';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/server_health.dart';
import '../services/client_health.dart';
import '../services/diagnostics.dart';
import '../services/diagnostics_repository.dart';
import '../services/work_timing.dart';
import '../widgets/app_menu.dart';
import '../widgets/hotkeys.dart';
import '../widgets/status_message.dart';

/// How the app and the server are doing: the server's health metrics
/// ([DiagnosticsRepository]) on its **Server** pane, and the app's own
/// ([ClientHealthRecorder]) on its **App** pane -- swiped between, as the
/// Plan page's are.
///
/// Each is graphs of one time range, the latest on the right. The
/// server's: its tool calls' latencies -- each tool's own work, stacked
/// under the rest of its request, to the whole request's time -- its
/// memory, and its restarts, ticked. The app's: its tool calls' latencies,
/// the app's and the background task's, and how many changes waited to
/// save, in each outbox, stacked; and its last errors, in full. Calls are
/// dots, not joined -- they come in bursts, with long gaps between -- and
/// memory is stacked by what holds it, each with their mean, median, p95
/// and max marked across; failed calls are red. Which tools' calls, how
/// far back, and each call
/// or a statistic of each bucket of them are picked from the menus above;
/// each graph says the mean, median, 95th percentile and max of what's in
/// view. Pinching -- on a touchscreen or a trackpad, or Ctrl and the mouse
/// wheel -- zooms all of a pane's graphs in on a stretch of time, two
/// fingers drag it along, and a double tap goes back to the whole range;
/// the buttons zoom keeping the latest in view. Scrolling scrolls the page.
/// The app bar's refresh button refreshes the pane shown, as pulling it
/// down does.
class DiagnosticsScreen extends StatefulWidget {
  const DiagnosticsScreen({
    super.key,
    required this.repository,
    this.client,
    this.clock = DateTime.now,
  });

  final DiagnosticsRepository repository;

  /// The app's own health; without it, its pane says it isn't recorded.
  final ClientHealthRecorder? client;
  final DateTime Function() clock;

  @override
  State<DiagnosticsScreen> createState() => _DiagnosticsScreenState();
}

class _DiagnosticsScreenState extends State<DiagnosticsScreen> {
  /// Each pane's pull-to-refresh, in the tabs' order: the refresh button
  /// pulls the one shown down.
  final _refreshers = [
    GlobalKey<RefreshIndicatorState>(),
    GlobalKey<RefreshIndicatorState>(),
  ];

  @override
  Widget build(BuildContext context) {
    final client = widget.client;
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Diagnostics'),
          actions: [
            Builder(
              builder: (context) => RefreshButton(
                onRefresh: () async =>
                    _refreshers[DefaultTabController.of(context).index]
                        .currentState
                        ?.show(),
              ),
            ),
          ],
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Server'),
              Tab(text: 'App'),
            ],
          ),
        ),
        body: _PausingFrames(
          child: Builder(
            builder: (context) {
              final tabs = DefaultTabController.of(context);
              void go(int by) =>
                  tabs.animateTo((tabs.index + by).clamp(0, tabs.length - 1));
              return HotkeyBindings(
                bindings: [
                  HotkeyBinding(
                    const HotkeyTrigger.key(LogicalKeyboardKey.keyH),
                    () => go(-1),
                  ),
                  HotkeyBinding(
                    const HotkeyTrigger.key(LogicalKeyboardKey.keyL),
                    () => go(1),
                  ),
                ],
                child: TabBarView(
                  children: [
                    _ServerPane(
                      repository: widget.repository,
                      clock: widget.clock,
                      refresher: _refreshers[0],
                    ),
                    if (client != null)
                      _ClientPane(
                        client: client,
                        clock: widget.clock,
                        refresher: _refreshers[1],
                      )
                    else
                      const _AppPane(),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

/// [child], with the app's slow frames not recorded while it's shown: its
/// graphs, drawn again as each was recorded, would only record more.
class _PausingFrames extends StatefulWidget {
  const _PausingFrames({required this.child});

  final Widget child;

  @override
  State<_PausingFrames> createState() => _PausingFramesState();
}

class _PausingFramesState extends State<_PausingFrames> {
  @override
  void initState() {
    super.initState();
    framesPaused++;
  }

  @override
  void dispose() {
    framesPaused--;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// What a pane's graphs show, picked from its menus: which tools' calls,
/// how far back, each call or a statistic of each bucket of them, and the
/// stretch zoomed in on, if any.
mixin _Timeline<T extends StatefulWidget> on State<T> {
  ToolFilter filter = const AllTools();
  TimeRange range = TimeRange.day;
  Statistic? statistic;
  BucketSize bucket = BucketSize.hour;

  /// The stretch zoomed in on, if it is: within the range.
  (DateTime, DateTime)? zoom;

  DateTime Function() get clock;

  /// When each series starts: for "Everything" to start at the earliest.
  Iterable<DateTime> get starts;

  /// The whole range shown, before any zoom: back from now, or to the
  /// earliest sample.
  (DateTime, DateTime) get window {
    final now = clock().toUtc();
    final span = range.span;
    if (span != null) return (now.subtract(span), now);
    final times = starts.toList();
    final earliest = times.isEmpty
        ? now.subtract(const Duration(days: 1))
        : times.reduce((a, b) => a.isBefore(b) ? a : b);
    return (earliest, now);
  }

  (DateTime, DateTime) get shown => zoom ?? window;

  /// Zooms by [factor] (above 1, in) about [anchor] -- a fraction of the
  /// way across: by default the right, the latest, kept where it is -- and
  /// moves by [shift], a fraction of the stretch shown.
  void zoomBy(double factor, {double anchor = 1, double shift = 0}) {
    final (wholeFrom, wholeTo) = window;
    final (from, to) = shown;
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
      zoom = next >= whole
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

  /// [child], the pane's list of graphs: J and K go from one to the next
  /// ([HotkeyItems]), = zooms in and - out, while it's shown.
  Widget withKeys(Widget child) => HotkeyBindings(
    bindings: [
      HotkeyBinding(
        const HotkeyTrigger.key(LogicalKeyboardKey.equal),
        () => zoomBy(2),
        when: () => isPainted(context),
      ),
      for (final key in const [
        LogicalKeyboardKey.minus,
        LogicalKeyboardKey.numpadSubtract,
      ])
        HotkeyBinding(HotkeyTrigger.key(key), () {
          if (zoom != null) zoomBy(0.5);
        }, when: () => isPainted(context)),
    ],
    child: HotkeyItems(child: child),
  );

  /// [child]'s graphs, zoomed together.
  Widget zoomable(Widget child) => _Zoomable(
    onZoom: zoomBy,
    onReset: () => setState(() => zoom = null),
    child: child,
  );

  /// The menus, for [tools] and [buckets], and the stretch shown, with the
  /// buttons to zoom and move along it.
  Widget controls(
    BuildContext context,
    Iterable<String> tools, {
    List<BucketSize> buckets = BucketSize.values,
  }) {
    final filters = toolFilters(tools);
    if (!filters.contains(filter)) filter = const AllTools();
    final strings = MaterialLocalizations.of(context);
    final (from, to) = shown;
    String time(DateTime t) =>
        '${strings.formatShortMonthDay(t.toLocal())}, '
        '${strings.formatTimeOfDay(TimeOfDay.fromDateTime(t.toLocal()))}';
    // Not a graph: J and K pass it by, though Tab goes to it.
    return NotAnItem(
      child: Padding(
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
                  onChanged: (f) => setState(() => filter = f),
                ),
                _Picker<TimeRange>(
                  label: 'Range',
                  value: range,
                  items: {for (final r in TimeRange.values) r: r.label},
                  onChanged: (r) => setState(() {
                    range = r;
                    zoom = null;
                  }),
                ),
                _Picker<Statistic?>(
                  label: 'Show',
                  value: statistic,
                  items: {
                    null: 'Each call',
                    for (final s in Statistic.values) s: s.label,
                  },
                  onChanged: (s) => setState(() => statistic = s),
                ),
                if (statistic != null)
                  _Picker<BucketSize>(
                    label: 'Per',
                    value: bucket,
                    items: {for (final b in buckets) b: b.label},
                    onChanged: (b) => setState(() => bucket = b),
                  ),
              ],
            ),
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${time(from)} – ${time(to)}${zoom == null ? '' : ' (zoomed in)'}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
                IconButton(
                  tooltip: 'Earlier',
                  icon: const Icon(Icons.chevron_left),
                  onPressed: zoom == null ? null : () => zoomBy(1, shift: 0.5),
                ),
                IconButton(
                  tooltip: 'Zoom out',
                  icon: const Icon(Icons.zoom_out),
                  onPressed: zoom == null ? null : () => zoomBy(0.5),
                ),
                IconButton(
                  tooltip: 'Zoom in',
                  icon: const Icon(Icons.zoom_in),
                  onPressed: () => zoomBy(2),
                ),
                IconButton(
                  tooltip: 'Later',
                  icon: const Icon(Icons.chevron_right),
                  onPressed: zoom == null ? null : () => zoomBy(1, shift: -0.5),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// The server's health, from its `get_health`.
class _ServerPane extends StatefulWidget {
  const _ServerPane({
    required this.repository,
    required this.clock,
    required this.refresher,
  });

  final DiagnosticsRepository repository;
  final DateTime Function() clock;

  /// Its pull-to-refresh's.
  final GlobalKey<RefreshIndicatorState> refresher;

  @override
  State<_ServerPane> createState() => _ServerPaneState();
}

class _ServerPaneState extends State<_ServerPane>
    with _Timeline, AutomaticKeepAliveClientMixin {
  ServerHealth? _health;
  Object? _error;
  bool _loading = true;

  @override
  bool get wantKeepAlive => true;

  @override
  DateTime Function() get clock => widget.clock;

  @override
  Iterable<DateTime> get starts => [
    if (_health case final health?) ...[
      for (final t in health.tools)
        if (t.calls.isNotEmpty) t.calls.first.at,
      if (health.memory.isNotEmpty) health.memory.first.at,
      ...health.restarts,
    ],
  ];

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

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final health = _health;
    final error = _error;
    if (health == null) {
      if (_loading) return const Center(child: CircularProgressIndicator());
      return RefreshIndicator(
        key: widget.refresher,
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
    final (from, to) = shown;
    final calls = within(
      [
        for (final t in health.tools)
          if (filter.includes(t.tool)) ...t.calls,
      ]..sort((a, b) => a.at.compareTo(b.at)),
      (c) => c.at,
      from,
      to,
    );
    final memory = within(health.memory, (m) => m.at, from, to);
    final restarts = within(health.restarts, (r) => r, from, to);
    // Samples are this far apart at the closest: no bucket's finer.
    final interval = health.memoryInterval;
    final buckets = BucketSize.atLeast(interval);
    if (!buckets.contains(bucket)) bucket = buckets.first;
    return RefreshIndicator(
      key: widget.refresher,
      onRefresh: _load,
      child: withKeys(
        ListView(
          padding: const EdgeInsets.only(bottom: 24),
          children: [
            if (error != null)
              NotAnItem(
                child: LoadError(
                  what: "the server's health",
                  error: error,
                  stale: true,
                  onRetry: _load,
                ),
              ),
            controls(context, [
              for (final t in health.tools) t.tool,
            ], buckets: buckets),
            zoomable(
              Column(
                children: [
                  _LatencyCard(
                    calls: calls,
                    points: latencyPoints(
                      calls,
                      statistic: statistic,
                      bucket: bucket,
                    ),
                    tools: filter.label,
                    from: from,
                    to: to,
                  ),
                  _MemoryCard(
                    memory: memory,
                    points: memoryPoints(
                      memory,
                      statistic: statistic,
                      bucket: bucket,
                    ),
                    from: from,
                    to: to,
                    interval: interval,
                    joinWithin: memoryJoinWithin(
                      interval,
                      statistic: statistic,
                      bucket: bucket,
                    ),
                  ),
                  _RestartsCard(restarts: restarts, from: from, to: to),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The app's own health: its tool calls, its outboxes' queues, and its
/// last errors -- as [client] has recorded them, here and in the
/// background, read again as it records more.
class _ClientPane extends StatefulWidget {
  const _ClientPane({
    required this.client,
    required this.clock,
    required this.refresher,
  });

  final ClientHealthRecorder client;
  final DateTime Function() clock;

  /// Its pull-to-refresh's.
  final GlobalKey<RefreshIndicatorState> refresher;

  @override
  State<_ClientPane> createState() => _ClientPaneState();
}

class _ClientPaneState extends State<_ClientPane>
    with _Timeline, AutomaticKeepAliveClientMixin {
  ClientHealth? _health;

  @override
  bool get wantKeepAlive => true;

  @override
  DateTime Function() get clock => widget.clock;

  @override
  Iterable<DateTime> get starts => [
    if (_health case final health?) ...[
      for (final calls in health.calls.values)
        if (calls.isNotEmpty) calls.first.at,
      if (health.queue.isNotEmpty) health.queue.first.at,
      for (final work in health.work.values)
        if (work.isNotEmpty) work.first.at,
      if (health.frames.isNotEmpty) health.frames.first.at,
      if (health.visits.isNotEmpty) health.visits.first.at,
    ],
  ];

  @override
  void initState() {
    super.initState();
    widget.client.addListener(_load);
    _load();
  }

  @override
  void dispose() {
    widget.client.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    final health = await widget.client.read();
    if (mounted) setState(() => _health = health);
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final health = _health;
    if (health == null) return const Center(child: CircularProgressIndicator());
    final (from, to) = shown;
    final calls = within(
      [
        for (final MapEntry(key: tool, value: calls) in health.calls.entries)
          if (filter.includes(tool)) ...calls,
      ]..sort((a, b) => a.at.compareTo(b.at)),
      (c) => c.at,
      from,
      to,
    );
    // The queue as it stood as the stretch began, then each change in it.
    final before = health.queue.where((q) => q.at.isBefore(from)).lastOrNull;
    final queue = [
      if (before != null)
        QueueSample(
          at: from,
          notes: before.notes,
          actions: before.actions,
          events: before.events,
        ),
      ...within(health.queue, (q) => q.at, from, to),
    ];
    final visits = within(health.visits, (v) => v.at, from, to);
    final frames = within(health.frames, (f) => f.at, from, to);
    final work = {
      for (final MapEntry(:key, :value) in health.work.entries)
        key: within(value, (w) => w.at, from, to),
    };
    final errors = [
      for (final e in health.errors.reversed)
        if (e.tool == null ? filter is AllTools : filter.includes(e.tool!)) e,
    ];
    return RefreshIndicator(
      key: widget.refresher,
      onRefresh: () async {
        await widget.client.flush();
        await _load();
      },
      child: withKeys(
        ListView(
          padding: const EdgeInsets.only(bottom: 24),
          children: [
            controls(context, health.calls.keys),
            zoomable(
              Column(
                children: [
                  _ClientCallsCard(
                    calls: calls,
                    statistic: statistic,
                    bucket: bucket,
                    tools: filter.label,
                    from: from,
                    to: to,
                  ),
                  _QueueCard(queue: queue, from: from, to: to),
                  _SlowFramesCard(frames: frames, from: from, to: to),
                ],
              ),
            ),
            _PlanVisitsCard(visits: visits),
            _WorkCard(work: work),
            _ErrorsCard(errors: errors, kept: health.errors.length),
          ],
        ),
      ),
    );
  }
}

/// A card of the page -- a graph, say -- that J and K can highlight,
/// outlined while it is.
class _ItemCard extends StatelessWidget {
  const _ItemCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Focus(
    child: Builder(
      builder: (context) {
        final focused = Focus.of(context).hasPrimaryFocus;
        return Card(
          margin: const EdgeInsets.fromLTRB(12, 8, 12, 4),
          shape: focused
              ? RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(
                    color: Theme.of(context).colorScheme.primary,
                    width: 2,
                  ),
                )
              : null,
          child: child,
        );
      },
    ),
  );
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
    return _ItemCard(
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

AxisTitles _valueAxis(
  BuildContext context,
  String Function(num) format, {
  double? interval,
}) => AxisTitles(
  sideTitles: SideTitles(
    showTitles: true,
    interval: interval,
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

/// [spots] as dots alone, unjoined: samples come in bursts with long gaps
/// between, which a line would draw across as if it knew what was there.
/// Each is [color], or [colorOf] it, by its index.
LineChartBarData _dots(
  List<FlSpot> spots,
  Color color, {
  Color Function(int index)? colorOf,
}) => LineChartBarData(
  spots: spots,
  color: color,
  barWidth: 0,
  dotData: FlDotData(
    getDotPainter: (_, _, _, i) => FlDotCirclePainter(
      radius: 2.5,
      color: colorOf?.call(i) ?? color,
      strokeWidth: 0,
    ),
  ),
);

/// The four of [summary] its markers are drawn at.
List<double> _marked(Summary? summary) => summary == null
    ? const []
    : [summary.mean, summary.median, summary.p95, summary.max];

/// A dashed line across the graph at each of [summary]'s mean, median,
/// 95th percentile and max, each labelled with which it is, whose -- the
/// tools whose calls it falls on ([whose]), or for the mean, which is no
/// one call's, [what], the tools shown -- and its value; lines that fall
/// together, of the same tools, are one, labelled with all they are.
/// Tools too many to fit across are cut short: "a / b / 3 more".
///
/// The labels take turns at the left, the right and the middle, so lines
/// close together -- the mean and p95 under a far-off max, say -- don't
/// cover each other's; the median's is under its line, as it's most often
/// a little under the mean, whose label is over it -- unless that's off
/// the foot of the graph, which runs over [range].
ExtraLinesData _markers(
  BuildContext context,
  Summary? summary,
  String Function(num) format, {
  required (double, double) range,
  String? what,
  List<String>? Function(Statistic)? whose,
}) {
  if (summary == null) return const ExtraLinesData();
  final colors = Theme.of(context).colorScheme;
  final style = Theme.of(context).textTheme.labelSmall?.copyWith(
    color: colors.onSurface,
    background: Paint()
      ..color = colors.surfaceContainerLow.withValues(alpha: 0.85),
  );
  const padding = EdgeInsets.symmetric(horizontal: 4, vertical: 1);
  // The plot's width, as [_Zoomable] reckons it.
  final room = MediaQuery.sizeOf(context).width - 104 - padding.horizontal;
  final scaler = MediaQuery.textScalerOf(context);
  bool fits(String text) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
      textScaler: scaler,
    )..layout();
    final width = painter.width;
    painter.dispose();
    return width <= room;
  }

  /// [head] · as many of [who] as fit · [tail].
  String fitted(String head, List<String>? who, String tail) {
    String label(List<String> who, [int more = 0]) => [
      head,
      if (who.isNotEmpty) [...who, if (more > 0) '$more more'].join(' / '),
      tail,
    ].join(' · ');
    if (who == null || who.isEmpty) return label(const []);
    for (var k = who.length; k > 0; k--) {
      final text = label(who.take(k).toList(), who.length - k);
      if (fits(text)) return text;
    }
    // Not even one whole: the first, shortened.
    var first = who.first;
    while (first.length > 1) {
      first = first.substring(0, first.length - 1);
      final text = label(['$first…'], who.length - 1);
      if (fits(text)) return text;
    }
    return label(['$first…'], who.length - 1);
  }

  final (low, high) = range;
  // A label's height is about a sixteenth of a graph's.
  final nearFoot = (summary.median - low) / max(1e-9, high - low) < 0.06;
  // Each line: which it is, whose, where, and its label's place.
  final lines = <(List<String>, List<String>?, double, Alignment)>[];
  for (final (statistic, name, y, alignment) in [
    (Statistic.mean, 'Mean', summary.mean, Alignment.topLeft),
    (
      Statistic.median,
      'Median',
      summary.median,
      nearFoot ? Alignment.topRight : Alignment.bottomRight,
    ),
    (Statistic.p95, 'p95', summary.p95, Alignment.topCenter),
    (Statistic.max, 'Max', summary.max, Alignment.topRight),
  ]) {
    final who = whose?.call(statistic) ?? [?what];
    final same = lines.indexWhere(
      (l) => l.$3 == y && l.$2?.join(' / ') == who.join(' / '),
    );
    if (same >= 0) {
      // Labelled as the highest of them is placed.
      final (names, _, _, _) = lines[same];
      lines[same] = ([...names, name], who, y, alignment);
    } else {
      lines.add(([name], who, y, alignment));
    }
  }
  return ExtraLinesData(
    horizontalLines: [
      for (final (names, who, y, alignment) in lines)
        HorizontalLine(
          y: y,
          color: colors.outline,
          strokeWidth: 1,
          dashArray: const [4, 3],
          label: HorizontalLineLabel(
            show: true,
            alignment: alignment,
            padding: padding,
            style: style,
            labelResolver: (_) => fitted(names.join(', '), who, format(y)),
          ),
        ),
    ],
  );
}

/// What's said in a graph with nothing in view.
Widget _empty(BuildContext context, String text) => SizedBox(
  height: 120,
  child: Center(
    child: Text(text, style: Theme.of(context).textTheme.bodyMedium),
  ),
);

/// The tool calls' graph: a dot for each call's own work, and one for the
/// whole request's time, auth and transport included -- red if it failed
/// -- with the whole request's mean, median, p95 and max marked across.
class _LatencyCard extends StatelessWidget {
  const _LatencyCard({
    required this.calls,
    required this.points,
    required this.tools,
    required this.from,
    required this.to,
  });

  final List<ToolCall> calls;
  final List<LatencyPoint> points;

  /// Which tools' calls they are, as the menu says it.
  final String tools;
  final DateTime from;
  final DateTime to;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final work = colors.primary;
    final whole = colors.tertiary;
    final failed = calls.where((c) => !c.ok).length;
    final total = Summary.of([for (final c in calls) c.wholeMs]);
    final top = points.isEmpty
        ? 1.0
        : [for (final p in points) p.total, ..._marked(total)].reduce(max) *
              1.1;
    return _GraphCard(
      title: 'Tool calls',
      subtitle:
          '${calls.length} call${calls.length == 1 ? '' : 's'} in view'
          '${failed == 0 ? '' : ', $failed failed'}',
      legend: [
        (work, "The tool's work"),
        (whole, 'Whole request'),
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
                  extraLinesData: _markers(
                    context,
                    total,
                    _ms,
                    range: (0, max(1, top)),
                    what: tools,
                    whose: (s) => whoseStatistic(
                      s,
                      [for (final c in calls) c.wholeMs],
                      [for (final c in calls) c.tool],
                    ),
                  ),
                  lineBarsData: [
                    _dots([
                      for (final p in points) FlSpot(_x(p.at), p.work),
                    ], work),
                    _dots(
                      [for (final p in points) FlSpot(_x(p.at), p.total)],
                      whole,
                      colorOf: (i) =>
                          points[i].errors > 0 ? colors.error : whole,
                    ),
                  ],
                  lineTouchData: LineTouchData(
                    touchTooltipData: LineTouchTooltipData(
                      getTooltipItems: (spots) => [
                        for (final s in spots)
                          LineTooltipItem(
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
          ('Total', total),
        ],
      ),
    );
  }
}

/// The server's memory, the most of each [interval] after a call or its
/// own work in the background, stacked by what it's made of as the server
/// reckons it -- the rest of the server at the foot, then the calendar it
/// keeps, then its sheet tabs, as one layer while they're many, until
/// opened out -- with the total's mean, median, p95 and max marked
/// across. Points further apart than [joinWithin] aren't joined.
///
/// Tapping a layer in the legend shows it alone, and tapping it again,
/// or "All", shows them all. Tapping the graph, or hovering on it, says
/// under it what that point is made of, largest first: at first, the
/// latest. Samples from a server that doesn't break its memory down are
/// all the rest of the server.
class _MemoryCard extends StatefulWidget {
  const _MemoryCard({
    required this.memory,
    required this.points,
    required this.from,
    required this.to,
    required this.interval,
    required this.joinWithin,
  });

  final List<MemorySample> memory;
  final List<MemoryPoint> points;
  final DateTime from;
  final DateTime to;

  /// The server's [ServerHealth.memoryInterval].
  final Duration interval;
  final Duration joinWithin;

  @override
  State<_MemoryCard> createState() => _MemoryCardState();
}

class _MemoryCardState extends State<_MemoryCard> {
  /// The layer shown alone -- a part's name, or all the sheet tabs' -- if
  /// one is.
  String? _alone;

  /// Whether each sheet tab is a layer of its own: at first, only while
  /// they're few.
  bool? _tabsOpen;

  /// When the point said under the graph is: none, the latest.
  DateTime? _picked;

  /// Sheet tabs more than this are one layer, to begin with.
  static const _fewTabs = 3;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final points = widget.points;
    final tabs = {
      for (final s in widget.memory)
        for (final part in s.parts ?? const <MemoryPart>[])
          if (part.isSheet) part.name,
    }.toList();
    final tabsOpen = _tabsOpen ?? tabs.length <= _fewTabs;
    final layers = memoryLayers(points, groupSheets: !tabsOpen);
    final broken = layers.length > 1;
    var alone = _alone;
    bool shows(String name) =>
        alone == null ||
        name == alone ||
        (alone == MemoryLayer.sheets &&
            name.startsWith(MemoryPart.sheetPrefix));
    if (!layers.any((l) => shows(l.name))) alone = null;
    final shown = [
      for (final l in layers)
        if (shows(l.name)) l,
    ];

    final hsl = HSLColor.fromColor(colors.primary);
    Color colorOf(String name) {
      if (name == MemoryPart.rest) return colors.outlineVariant;
      if (name == MemoryPart.calendar) return colors.tertiary;
      if (name == MemoryLayer.sheets) return colors.primary;
      final i = tabs.indexOf(name);
      if (i < 0) return colors.secondary;
      // A family of the primary's, muted: darker to lighter, a little
      // apart in hue.
      final t = tabs.length < 2 ? 0.5 : i / (tabs.length - 1);
      return hsl
          .withSaturation(min(hsl.saturation, 0.5))
          .withLightness(0.3 + 0.4 * t)
          .withHue((hsl.hue - 15 + 30 * t) % 360)
          .toColor();
    }

    // What's summed up: the whole, or what's shown alone, of each sample.
    final List<double> values;
    if (alone == null) {
      values = [for (final s in widget.memory) s.mib];
    } else {
      final sampled = memoryLayers([
        for (final s in widget.memory)
          MemoryPoint(at: s.at, mib: s.mib, parts: s.parts),
      ], groupSheets: !tabsOpen);
      values = [
        for (var i = 0; i < widget.memory.length; i++)
          sampled
              .where((l) => shows(l.name))
              .fold(0.0, (sum, l) => sum + l.values[i]),
      ];
    }
    final summary = Summary.of(values);

    // Each point's index among the spots, with a break where they're far
    // apart -- the same in every layer, so each fills between its own.
    final at = <int?>[];
    for (final (i, p) in points.indexed) {
      if (i > 0 && p.at.difference(points[i - 1].at) > widget.joinWithin) {
        at.add(null);
      }
      at.add(i);
    }
    List<FlSpot> spotsOf(double Function(int) y) => [
      for (final i in at)
        i == null ? FlSpot.nullSpot : FlSpot(_x(points[i].at), y(i)),
    ];
    final tops = <List<FlSpot>>[];
    final sum = List.filled(points.length, 0.0);
    for (final layer in shown) {
      for (var i = 0; i < points.length; i++) {
        sum[i] += layer.values[i];
      }
      final heights = [...sum];
      tops.add(spotsOf((i) => heights[i]));
    }
    final high = [...sum, ..._marked(summary)].fold(0.0, max);
    final maxY = high + max(1.0, high * 0.12);

    final picked =
        points.where((p) => p.at == _picked).firstOrNull ?? points.lastOrNull;
    final byX = {for (final p in points) _x(p.at): p};
    // A point alone in its stretch, with nothing to fill to, is a dot.
    bool lone(FlSpot spot, LineChartBarData bar) {
      final i = bar.spots.indexOf(spot);
      bool gap(int j) =>
          j < 0 || j >= bar.spots.length || bar.spots[j].isNull();
      return gap(i - 1) && gap(i + 1);
    }

    final markers = _markers(context, summary, _mib, range: (0, maxY));
    final style = Theme.of(context).textTheme.bodySmall;

    Widget chip(String name, {String? label, bool sheets = false}) {
      final selected = name == alone;
      return InputChip(
        label: Text(label ?? name),
        labelStyle: style,
        avatar: Container(width: 12, height: 12, color: colorOf(name)),
        selected: selected,
        showCheckmark: false,
        visualDensity: VisualDensity.compact,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        tooltip: selected ? 'Show all' : 'Show ${label ?? name} alone',
        onSelected: (_) => setState(() => _alone = selected ? null : name),
        onDeleted: sheets
            ? () => setState(() {
                _tabsOpen = !tabsOpen;
                if (alone != null && alone.startsWith(MemoryPart.sheetPrefix)) {
                  _alone = MemoryLayer.sheets;
                }
              })
            : null,
        deleteIcon: Icon(tabsOpen ? Icons.unfold_less : Icons.unfold_more),
        deleteButtonTooltipMessage: tabsOpen
            ? 'Show the tabs as one'
            : 'Show each tab',
      );
    }

    // The legend, the top of the stack first. Opened out, the tabs come
    // after "Sheets", which shows them all alone.
    final sheetsChip = chip(
      MemoryLayer.sheets,
      label: 'Sheets (${tabs.length})',
      sheets: true,
    );
    final legend = <Widget>[];
    for (final l in layers.reversed) {
      if (!l.name.startsWith(MemoryPart.sheetPrefix)) {
        legend.add(l.name == MemoryLayer.sheets ? sheetsChip : chip(l.name));
      } else {
        if (!legend.contains(sheetsChip)) legend.add(sheetsChip);
        legend.add(
          chip(l.name, label: l.name.substring(MemoryPart.sheetPrefix.length)),
        );
      }
    }

    return _GraphCard(
      title: 'Memory',
      subtitle:
          "The server's resident memory, the most of "
          '${eachInterval(widget.interval)} after a call or its work in the '
          "background${broken ? ', stacked by what holds it' : ''}",
      graph: points.isEmpty
          ? _empty(context, 'No memory samples in view.')
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (broken)
                  Padding(
                    padding: const EdgeInsets.only(left: 8, bottom: 8),
                    child: Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        ...legend,
                        if (alone != null)
                          ActionChip(
                            label: const Text('All'),
                            labelStyle: style,
                            avatar: const Icon(Icons.layers_outlined),
                            visualDensity: VisualDensity.compact,
                            materialTapTargetSize:
                                MaterialTapTargetSize.shrinkWrap,
                            onPressed: () => setState(() => _alone = null),
                          ),
                      ],
                    ),
                  ),
                SizedBox(
                  height: 180,
                  child: LineChart(
                    LineChartData(
                      minX: _x(widget.from),
                      maxX: _x(widget.to),
                      minY: 0,
                      maxY: maxY,
                      clipData: const FlClipData.all(),
                      titlesData: FlTitlesData(
                        bottomTitles: _timeAxis(
                          context,
                          widget.from,
                          widget.to,
                        ),
                        leftTitles: _valueAxis(context, _mib),
                        topTitles: _noTitles,
                        rightTitles: _noTitles,
                      ),
                      borderData: FlBorderData(show: false),
                      extraLinesData: ExtraLinesData(
                        horizontalLines: markers.horizontalLines,
                        verticalLines: [
                          if (picked != null)
                            VerticalLine(
                              x: _x(picked.at),
                              color: colors.onSurfaceVariant,
                              strokeWidth: 1,
                            ),
                        ],
                      ),
                      lineBarsData: [
                        // The foot, each layer filled from the one under it.
                        LineChartBarData(
                          spots: spotsOf((_) => 0),
                          barWidth: 0,
                          dotData: const FlDotData(show: false),
                        ),
                        for (final (i, spots) in tops.indexed)
                          LineChartBarData(
                            spots: spots,
                            // The whole's edge, over the top layer.
                            color: colors.onSurfaceVariant,
                            barWidth: i == tops.length - 1 ? 1 : 0,
                            dotData: FlDotData(
                              show: i == tops.length - 1,
                              checkToShowDot: lone,
                              getDotPainter: (_, _, _, _) => FlDotCirclePainter(
                                radius: 2.5,
                                color: colors.onSurfaceVariant,
                                strokeWidth: 0,
                              ),
                            ),
                          ),
                      ],
                      betweenBarsData: [
                        for (final (i, layer) in shown.indexed)
                          BetweenBarsData(
                            fromIndex: i,
                            toIndex: i + 1,
                            color: colorOf(layer.name).withValues(alpha: 0.85),
                          ),
                      ],
                      lineTouchData: LineTouchData(
                        handleBuiltInTouches: false,
                        touchSpotThreshold: double.infinity,
                        touchCallback: (event, response) {
                          final x = response?.lineBarSpots?.firstOrNull?.x;
                          final point = byX[x];
                          if (!event.isInterestedForInteractions ||
                              point == null ||
                              point.at == picked?.at) {
                            return;
                          }
                          setState(() => _picked = point.at);
                        },
                      ),
                    ),
                  ),
                ),
                if (picked != null)
                  _MemoryBreakdown(
                    point: picked,
                    latest: picked == points.last,
                    interval: widget.interval,
                    colorOf: colorOf,
                  ),
              ],
            ),
      footer: _SummaryTable(
        format: _mib,
        rows: [(alone ?? 'Memory', summary)],
        extra: ('Latest', [values.isEmpty ? '–' : _mib(values.last)]),
      ),
    );
  }
}

/// What [point] of the memory graph is made of: when it is, its total,
/// and each part, largest first, each in its layer's color.
class _MemoryBreakdown extends StatelessWidget {
  const _MemoryBreakdown({
    required this.point,
    required this.latest,
    required this.interval,
    required this.colorOf,
  });

  final MemoryPoint point;
  final bool latest;

  /// The server's [ServerHealth.memoryInterval].
  final Duration interval;
  final Color Function(String) colorOf;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodySmall;
    final strings = MaterialLocalizations.of(context);
    final t = point.at.toLocal();
    final seconds = t.second.toString().padLeft(2, '0');
    // To the second while samples can be under a minute apart.
    final minutes = strings.formatTimeOfDay(TimeOfDay.fromDateTime(t));
    final clock = interval < const Duration(minutes: 1)
        ? minutes.replaceFirstMapped(
            RegExp(r':(\d\d)'),
            (m) => ':${m[1]}:$seconds',
          )
        : minutes;
    final parts = point.parts?.toList()
      ?..sort((a, b) => b.mib.compareTo(a.mib));
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 0, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${latest ? 'Latest · ' : ''}'
            '${strings.formatShortMonthDay(t)}, $clock · ${_mib(point.mib)}',
            style: style?.copyWith(fontWeight: FontWeight.w600),
          ),
          if (parts == null)
            Text('Not broken down by the server', style: style)
          else
            for (final part in parts)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Row(
                  children: [
                    Container(width: 10, height: 10, color: colorOf(part.name)),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        part.name,
                        style: style,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Text(_mib(part.mib), style: style),
                  ],
                ),
              ),
        ],
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

/// The app's tool calls: a dot for each of the app's, and each of the
/// background task's -- or a statistic of each bucket of them -- its whole
/// time, retries and the network included; failed calls red. All of
/// them's mean, median, p95 and max are marked across.
class _ClientCallsCard extends StatelessWidget {
  const _ClientCallsCard({
    required this.calls,
    required this.statistic,
    required this.bucket,
    required this.tools,
    required this.from,
    required this.to,
  });

  final List<ClientCall> calls;
  final Statistic? statistic;
  final BucketSize bucket;

  /// Which tools' calls they are, as the menu says it.
  final String tools;
  final DateTime from;
  final DateTime to;

  /// [calls] of [origin] as the graph shows them.
  List<LatencyPoint> _points(CallOrigin origin) => latencyPoints(
    [
      for (final c in calls)
        if (c.origin == origin)
          ToolCall(tool: c.tool, at: c.at, workMs: c.ms, ok: c.ok),
    ],
    statistic: statistic,
    bucket: bucket,
  );

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final app = colors.primary;
    final background = colors.tertiary;
    final failed = calls.where((c) => !c.ok).length;
    final series = [
      (_points(CallOrigin.app), app),
      (_points(CallOrigin.background), background),
    ];
    final all = [for (final (points, _) in series) ...points];
    List<num> msOf(CallOrigin? origin) => [
      for (final c in calls)
        if (origin == null || c.origin == origin) c.ms,
    ];
    final summary = Summary.of(msOf(null));
    final top = all.isEmpty
        ? 1.0
        : [for (final p in all) p.total, ..._marked(summary)].reduce(max) * 1.1;
    return _GraphCard(
      title: 'Tool calls',
      subtitle:
          '${calls.length} call${calls.length == 1 ? '' : 's'} in view'
          '${failed == 0 ? '' : ', $failed failed'}: the whole call, retries '
          'and the network included',
      legend: [
        (app, CallOrigin.app.label),
        (background, CallOrigin.background.label),
        (colors.error, 'Failed'),
      ],
      graph: all.isEmpty
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
                  extraLinesData: _markers(
                    context,
                    summary,
                    _ms,
                    range: (0, max(1, top)),
                    what: tools,
                    whose: (s) => whoseStatistic(s, msOf(null), [
                      for (final c in calls) c.tool,
                    ]),
                  ),
                  lineBarsData: [
                    for (final (points, color) in series)
                      _dots(
                        [for (final p in points) FlSpot(_x(p.at), p.total)],
                        color,
                        colorOf: (i) =>
                            points[i].errors > 0 ? colors.error : color,
                      ),
                  ],
                  lineTouchData: LineTouchData(
                    touchTooltipData: LineTouchTooltipData(
                      getTooltipItems: (spots) => [
                        for (final s in spots)
                          LineTooltipItem(
                            '${s.barIndex == 0 ? 'App' : 'Background'} ${_ms(s.y)}',
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
          (CallOrigin.app.label, Summary.of(msOf(CallOrigin.app))),
          (
            CallOrigin.background.label,
            Summary.of(msOf(CallOrigin.background)),
          ),
          ('All', summary),
        ],
      ),
    );
  }
}

/// How many changes waited to save, in each outbox, stacked: notes under
/// actions under events, each step a change.
class _QueueCard extends StatelessWidget {
  const _QueueCard({required this.queue, required this.from, required this.to});

  final List<QueueSample> queue;
  final DateTime from;
  final DateTime to;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final notes = colors.primary;
    final actions = colors.secondary;
    final events = colors.tertiary;
    // Each step held till the next, and the last till now.
    final steps = [
      ...queue,
      if (queue.isNotEmpty)
        QueueSample(
          at: to,
          notes: queue.last.notes,
          actions: queue.last.actions,
          events: queue.last.events,
        ),
    ];
    final top = steps.isEmpty ? 1 : steps.map((q) => q.total).reduce(max);
    final surface = colors.surfaceContainerLow;
    // Each level filled down to nothing, the tallest first, so each lower
    // one is drawn over it: stacked, step by step.
    LineChartBarData level(int Function(QueueSample) height, Color color) =>
        LineChartBarData(
          spots: [
            for (final q in steps) FlSpot(_x(q.at), height(q).toDouble()),
          ],
          isStepLineChart: true,
          // Each count held till the next change.
          lineChartStepData: const LineChartStepData(
            stepDirection: LineChartStepData.stepDirectionForward,
          ),
          color: color,
          barWidth: 1.5,
          dotData: const FlDotData(show: false),
          belowBarData: BarAreaData(
            show: true,
            color: Color.alphaBlend(color.withValues(alpha: 0.4), surface),
          ),
        );
    return _GraphCard(
      title: 'Waiting to save',
      subtitle: 'How many changes waited, in each outbox',
      legend: [(notes, 'Notes'), (actions, 'Actions'), (events, 'Events')],
      graph: steps.isEmpty
          ? _empty(context, 'Nothing waited in view.')
          : SizedBox(
              height: 140,
              child: LineChart(
                LineChartData(
                  minX: _x(from),
                  maxX: _x(to),
                  minY: 0,
                  maxY: max(1, top * 1.2).toDouble(),
                  gridData: FlGridData(
                    horizontalInterval: max(1, (top / 3).ceil()).toDouble(),
                  ),
                  clipData: const FlClipData.all(),
                  titlesData: FlTitlesData(
                    bottomTitles: _timeAxis(context, from, to),
                    leftTitles: _valueAxis(
                      context,
                      (v) => '${v.round()}',
                      interval: max(1, (top / 3).ceil()).toDouble(),
                    ),
                    topTitles: _noTitles,
                    rightTitles: _noTitles,
                  ),
                  borderData: FlBorderData(show: false),
                  lineBarsData: [
                    level((q) => q.total, events),
                    level((q) => q.notes + q.actions, actions),
                    level((q) => q.notes, notes),
                  ],
                  lineTouchData: const LineTouchData(enabled: false),
                ),
              ),
            ),
      footer: _SummaryTable(
        format: (v) =>
            v == v.roundToDouble() ? '${v.round()}' : v.toStringAsFixed(1),
        rows: [
          ('Waiting', Summary.of([for (final q in queue) q.total])),
        ],
        extra: ('Latest', [queue.isEmpty ? '–' : '${queue.last.total}']),
      ),
    );
  }
}

/// The errors kept, in brief: how many, and the newest; a button opens
/// them all ([_ErrorsScreen]).
class _ErrorsCard extends StatelessWidget {
  const _ErrorsCard({required this.errors, required this.kept});

  /// Those of the tools picked, newest first.
  final List<ClientError> errors;

  /// How many are kept, of every tool.
  final int kept;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final newest = errors.firstOrNull;
    return _ItemCard(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Errors', style: theme.textTheme.titleMedium),
            Text(
              kept == 0
                  ? 'None kept.'
                  : errors.isEmpty
                  ? 'None of the $kept kept are of these tools.'
                  : "${errors.length} of these tools' kept, of the last "
                        '${ClientHealthRecorder.keepErrors}. The newest:',
              style: theme.textTheme.bodySmall,
            ),
            if (newest != null) ...[
              const SizedBox(height: 4),
              Text(
                '${_errorTime(context, newest.at)} · '
                '${newest.tool ?? 'Not caught'}',
                style: theme.textTheme.bodyMedium,
              ),
              Text(
                newest.message.split('\n').first,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall,
              ),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  icon: const Icon(Icons.chevron_right),
                  iconAlignment: IconAlignment.end,
                  label: Text(
                    errors.length == 1
                        ? 'See it in full'
                        : 'See all ${errors.length}',
                  ),
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => _ErrorsScreen(errors: errors),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// When an error was, as its row says it: "Oct 2, 1:30 PM".
String _errorTime(BuildContext context, DateTime t) {
  final strings = MaterialLocalizations.of(context);
  return '${strings.formatShortMonthDay(t.toLocal())}, '
      '${strings.formatTimeOfDay(TimeOfDay.fromDateTime(t.toLocal()))}';
}

/// The errors kept, of the tools picked, on a page of their own, newest
/// first, each opened to read in full -- its message and, for one the app
/// didn't catch, where -- and copy.
class _ErrorsScreen extends StatelessWidget {
  const _ErrorsScreen({required this.errors});

  final List<ClientError> errors;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text('Errors (${errors.length})')),
    body: ListView.builder(
      padding: const EdgeInsets.only(bottom: 24),
      itemCount: errors.length,
      itemBuilder: (context, i) => _tile(context, errors[i]),
    ),
  );

  Widget _tile(BuildContext context, ClientError e) {
    final theme = Theme.of(context);
    String time(DateTime t) => _errorTime(context, t);
    return ExpansionTile(
      leading: Icon(
        e.tool == null ? Icons.bug_report_outlined : Icons.cloud_off,
        color: theme.colorScheme.error,
      ),
      title: Text(e.tool ?? 'Not caught', style: theme.textTheme.bodyMedium),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${time(e.at)} · ${e.origin.label}'
            '${e.kind == null ? '' : ' · ${e.kind}'}',
          ),
          Text(
            e.message.split('\n').first,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
      childrenPadding: const EdgeInsets.fromLTRB(16, 0, 8, 12),
      expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SelectableText(
          [e.message, ?e.stack].join('\n\n'),
          style: theme.textTheme.bodySmall?.copyWith(fontFamily: 'monospace'),
        ),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            icon: const Icon(Icons.copy, size: 18),
            label: const Text('Copy'),
            onPressed: () {
              Clipboard.setData(
                ClipboardData(
                  text: [
                    '${e.at.toIso8601String()} ${e.origin.name}'
                        '${e.tool == null ? '' : ' ${e.tool}'}'
                        '${e.kind == null ? '' : ' ${e.kind}'}',
                    e.message,
                    ?e.stack,
                  ].join('\n\n'),
                ),
              );
              ScaffoldMessenger.of(context)
                  .showSnackBar(const SnackBar(content: Text('Copied.')));
            },
          ),
        ),
      ],
    );
  }
}

/// Each kind of the device's own work's color, in the visits' bars and
/// the work's table.
Color _workColor(ColorScheme colors, WorkKind kind) => switch (kind) {
  WorkKind.traitScores => colors.primary,
  WorkKind.actionTime => colors.tertiary,
  WorkKind.peopleTime => colors.secondary,
  WorkKind.planRebuild => colors.error,
};

/// Each visit to Plan in view, oldest first, from opening it to
/// everything loaded: a bar of the device's own work, kind by kind, under
/// the time it waited -- on the server, mostly.
class _PlanVisitsCard extends StatelessWidget {
  const _PlanVisitsCard({required this.visits});

  final List<PlanVisit> visits;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final waiting = colors.outlineVariant;
    final strings = MaterialLocalizations.of(context);
    final top = visits.isEmpty ? 1.0 : visits.map((v) => v.ms).reduce(max);
    return _GraphCard(
      title: 'Plan visits',
      subtitle:
          '${visits.length} visit${visits.length == 1 ? '' : 's'} in view, '
          'from opening Plan to everything loaded, by what the time went to',
      legend: [
        for (final kind in WorkKind.values)
          (_workColor(colors, kind), kind.label),
        (waiting, 'Waiting, on the server mostly'),
      ],
      graph: visits.isEmpty
          ? _empty(context, 'No visits to Plan in view.')
          : SizedBox(
              height: 180,
              child: BarChart(
                BarChartData(
                  minY: 0,
                  maxY: max(1, top * 1.1),
                  alignment: BarChartAlignment.spaceAround,
                  titlesData: FlTitlesData(
                    leftTitles: _valueAxis(context, _ms),
                    bottomTitles: _noTitles,
                    topTitles: _noTitles,
                    rightTitles: _noTitles,
                  ),
                  borderData: FlBorderData(show: false),
                  barGroups: [
                    for (final (i, v) in visits.indexed)
                      BarChartGroupData(
                        x: i,
                        barRods: [
                          BarChartRodData(
                            toY: v.ms,
                            width: max(3, min(16, 240 / visits.length)),
                            borderRadius: BorderRadius.zero,
                            color: waiting,
                            rodStackItems: () {
                              var y = 0.0;
                              return [
                                for (final kind in WorkKind.values)
                                  if (v.msOf(kind) > 0)
                                    BarChartRodStackItem(
                                      y,
                                      y += v.msOf(kind),
                                      _workColor(colors, kind),
                                    ),
                                BarChartRodStackItem(y, v.ms, waiting),
                              ];
                            }(),
                          ),
                        ],
                      ),
                  ],
                  barTouchData: BarTouchData(
                    touchTooltipData: BarTouchTooltipData(
                      getTooltipItem: (group, _, _, _) {
                        final v = visits[group.x];
                        final at = v.at.toLocal();
                        return BarTooltipItem(
                          [
                            '${strings.formatShortMonthDay(at)}, '
                                '${strings.formatTimeOfDay(TimeOfDay.fromDateTime(at))}: '
                                '${_ms(v.ms)}',
                            for (final kind in WorkKind.values)
                              if (v.msOf(kind) > 0)
                                '${kind.label} ${_ms(v.msOf(kind))}',
                            'Waiting ${_ms(v.waitingMs)}',
                          ].join('\n'),
                          TextStyle(
                            color: colors.onInverseSurface,
                            fontSize: 12,
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ),
            ),
      footer: _SummaryTable(
        format: _ms,
        rows: [
          ('Whole visit', Summary.of([for (final v in visits) v.ms])),
          (
            'Own work',
            Summary.of([for (final v in visits) v.ms - v.waitingMs]),
          ),
          ('Waiting', Summary.of([for (final v in visits) v.waitingMs])),
        ],
      ),
    );
  }
}

/// Each frame in view slower than [SlowFrame.budget], as tall as it took:
/// those while Plan was open apart from the rest, and any long enough to
/// see the screen freeze, red.
class _SlowFramesCard extends StatelessWidget {
  const _SlowFramesCard({
    required this.frames,
    required this.from,
    required this.to,
  });

  final List<SlowFrame> frames;
  final DateTime from;
  final DateTime to;

  /// A frame this slow is a freeze anyone would see.
  static const _freeze = 100.0;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final plan = colors.primary;
    final elsewhere = colors.outline;
    final top = frames.isEmpty ? 1.0 : frames.map((f) => f.ms).reduce(max);
    List<num> msOf(bool onPlan) => [
      for (final f in frames)
        if (f.plan == onPlan) f.ms,
    ];
    final onPlan = msOf(true), off = msOf(false);
    return _GraphCard(
      title: 'Slow frames',
      subtitle:
          '${frames.length} frame${frames.length == 1 ? '' : 's'} in view '
          'over ${(SlowFrame.budget.inMicroseconds / 1000).round()} ms, each '
          "as tall as it took; none's recorded while this page is open",
      legend: [
        (plan, 'Plan open'),
        (elsewhere, 'Elsewhere'),
        (colors.error, 'Over ${_freeze.round()} ms: a freeze'),
      ],
      graph: frames.isEmpty
          ? _empty(context, 'No slow frames in view.')
          : SizedBox(
              height: 140,
              child: ScatterChart(
                ScatterChartData(
                  minX: _x(from),
                  maxX: _x(to),
                  minY: 0,
                  maxY: max(1, top * 1.1),
                  clipData: const FlClipData.all(),
                  titlesData: FlTitlesData(
                    bottomTitles: _timeAxis(context, from, to),
                    leftTitles: _valueAxis(context, _ms),
                    topTitles: _noTitles,
                    rightTitles: _noTitles,
                  ),
                  borderData: FlBorderData(show: false),
                  scatterSpots: [
                    for (final f in frames)
                      ScatterSpot(
                        _x(f.at),
                        f.ms,
                        dotPainter: FlDotCirclePainter(
                          radius: 3,
                          color: f.ms > _freeze
                              ? colors.error
                              : f.plan
                              ? plan
                              : elsewhere,
                          strokeWidth: 0,
                        ),
                      ),
                  ],
                  scatterTouchData: ScatterTouchData(
                    touchTooltipData: ScatterTouchTooltipData(
                      getTooltipItems: (spot) {
                        final f = frames.firstWhere(
                          (f) => _x(f.at) == spot.x && f.ms == spot.y,
                          orElse: () => frames.first,
                        );
                        return ScatterTooltipItem(
                          '${_ms(f.ms)}: build ${_ms(f.buildUs / 1000)}, '
                          'draw ${_ms(f.rasterUs / 1000)}',
                          textStyle: TextStyle(
                            color: colors.onInverseSurface,
                            fontSize: 12,
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ),
            ),
      footer: _SummaryTable(
        format: _ms,
        rows: [
          ('Plan open', Summary.of(onPlan)),
          ('Elsewhere', Summary.of(off)),
        ],
        extra: ('Frames', ['${onPlan.length}', '${off.length}']),
      ),
    );
  }
}

/// How long each kind of the device's own work took, in view: each run
/// whole, what's done inside it included, and how many runs. And why the
/// traits' scores were worked out again, each time they were.
class _WorkCard extends StatelessWidget {
  const _WorkCard({required this.work});

  final Map<WorkKind, List<WorkSample>> work;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final kinds = [
      for (final kind in WorkKind.values)
        if (work[kind]?.isNotEmpty ?? false) kind,
    ];
    final whys = <String, int>{};
    for (final s in work[WorkKind.traitScores] ?? const <WorkSample>[]) {
      for (final why in (s.why ?? '').split(', ')) {
        if (why.isNotEmpty) whys[why] = (whys[why] ?? 0) + 1;
      }
    }
    return _ItemCard(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Work on the device', style: theme.textTheme.titleMedium),
            Text(
              kinds.isEmpty
                  ? 'None in view.'
                  : 'Each run whole, with what it does inside it; the last '
                        '${ClientHealthRecorder.keepWork} of each are kept.',
              style: theme.textTheme.bodySmall,
            ),
            if (kinds.isNotEmpty) ...[
              const SizedBox(height: 8),
              _SummaryTable(
                format: _ms,
                rows: [
                  for (final kind in kinds)
                    (
                      kind.label,
                      Summary.of([for (final s in work[kind]!) s.ms]),
                    ),
                ],
                extra: (
                  'Runs',
                  [for (final kind in kinds) '${work[kind]!.length}'],
                ),
              ),
            ],
            if (whys.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                'Trait scores were worked out again for: '
                '${[for (final MapEntry(:key, :value) in (whys.entries.toList()..sort((a, b) => b.value.compareTo(a.value)))) '$key ×$value'].join(', ')}',
                style: theme.textTheme.bodySmall,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// The app's pane, where its health isn't recorded.
class _AppPane extends StatelessWidget {
  const _AppPane();

  @override
  Widget build(BuildContext context) => ListView(
    children: const [
      _Note(
        icon: Icons.phone_android,
        text: "The app's own health isn't recorded here.",
      ),
    ],
  );
}
