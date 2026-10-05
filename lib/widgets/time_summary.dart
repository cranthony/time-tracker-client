import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import 'durations.dart';

/// One share of some time: by priority or goal.
class SummarySlice {
  const SummarySlice(this.label, this.color, this.time);

  final String label;

  /// Its color; null for time on nothing in particular, drawn empty.
  final Color? color;
  final Duration time;
}

/// The colors of the shares of events with no goal, and of the goals
/// past the top few together.
const noGoalColor = Color(0xFFD0D0D0);
const otherGoalsColor = Color(0xFF8A8A8A);

/// [time]'s shares, most first: the [top] keys with the most, each as
/// [slice] makes it, then the rest together as "N other goals". Keys
/// with no time are left out.
List<SummarySlice> topShares<K>(
  Map<K, Duration> time,
  SummarySlice Function(K key, Duration time) slice, {
  int top = 3,
}) {
  final ranked = [
    for (final MapEntry(:key, :value) in time.entries)
      if (value > Duration.zero) key,
  ]..sort((a, b) => time[b]!.compareTo(time[a]!));
  final rest = ranked
      .skip(top)
      .fold(Duration.zero, (sum, key) => sum + time[key]!);
  return [
    for (final key in ranked.take(top)) slice(key, time[key]!),
    if (rest > Duration.zero)
      SummarySlice('${ranked.length - top} other goals', otherGoalsColor, rest),
  ];
}

/// Some time at a glance, under a page's heading: [pages], such as
/// [SummaryBar]s, under their [titles]. Swiping, or tapping a title,
/// turns between them, and it grows or shrinks between their heights as
/// it's swiped. With [onCollapsed], a chevron folds it away, leaving
/// only a quiet "Show summary" to bring it back. With [onDurations], a
/// button by it turns its [SummaryBar]s between percentages and
/// durations.
class TimeSummary extends StatefulWidget {
  const TimeSummary({
    super.key,
    required this.titles,
    required this.pages,
    this.initialPage = 0,
    this.collapsed = false,
    this.onCollapsed,
    this.durations = false,
    this.onDurations,
  });

  final List<String> titles;
  final List<Widget> pages;

  final int initialPage;

  /// Whether it's folded away.
  final bool collapsed;

  /// Called with whether it's to be [collapsed]; null for no chevron.
  final ValueChanged<bool>? onCollapsed;

  /// Whether its [SummaryBar]s show each share's duration, rather than
  /// its percentage.
  final bool durations;

  /// Called with whether to show [durations]; null for no button.
  final ValueChanged<bool>? onDurations;

  @override
  State<TimeSummary> createState() => _TimeSummaryState();
}

class _TimeSummaryState extends State<TimeSummary> {
  late final _pages = PageController(initialPage: widget.initialPage);
  late int _page = widget.initialPage;

  /// Each page's height, once it's laid out.
  final _heights = <int, double>{};

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surfaceContainerLow,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            // Room for the chevron's button, if there is one.
            padding: widget.onCollapsed == null
                ? const EdgeInsets.fromLTRB(16, 8, 16, 0)
                : const EdgeInsets.fromLTRB(16, 0, 4, 0),
            child: _header(context),
          ),
          // Kept, though folded away, so it opens on the page it was on.
          AnimatedSize(
            duration: const Duration(milliseconds: 200),
            alignment: Alignment.topCenter,
            child: Offstage(
              offstage: widget.collapsed,
              child: TickerMode(
                enabled: !widget.collapsed,
                child: SummaryUnit(durations: widget.durations, child: _body()),
              ),
            ),
          ),
          Divider(height: 1, color: theme.colorScheme.outlineVariant),
        ],
      ),
    );
  }

  Widget _body() => ListenableBuilder(
    listenable: _pages,
    builder: (context, pages) {
      final at = _pages.hasClients && _pages.position.haveDimensions
          ? _pages.page!
          : _page.toDouble();
      final from = _heights[at.floor()] ?? _heights[at.ceil()];
      final to = _heights[at.ceil()] ?? from;
      return SizedBox(
        height: lerpDouble(from, to, at - at.floor()) ?? 0,
        child: pages,
      );
    },
    child: PageView(
      controller: _pages,
      onPageChanged: (page) => setState(() => _page = page),
      children: [
        for (final (i, page) in widget.pages.indexed)
          // As tall as it needs, whatever the summary's height this frame.
          OverflowBox(
            alignment: Alignment.topCenter,
            minHeight: 0,
            maxHeight: double.infinity,
            child: _Measured(
              onHeight: (height) {
                if (mounted) setState(() => _heights[i] = height);
              },
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                child: page,
              ),
            ),
          ),
      ],
    ),
  );

  /// The titles, the current one bold and underlined, then the
  /// chevron; folded away, only a quiet "Show summary" by the
  /// chevron.
  Widget _header(BuildContext context) {
    final theme = Theme.of(context);
    final onCollapsed = widget.onCollapsed;
    if (widget.collapsed && onCollapsed != null) {
      return Row(
        children: [
          const Spacer(),
          GestureDetector(
            onTap: () => onCollapsed(false),
            child: Text(
              'Show summary',
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            tooltip: 'Show summary',
            icon: const Icon(Icons.expand_more),
            onPressed: () => onCollapsed(false),
          ),
        ],
      );
    }
    return Row(
      children: [
        for (final (i, title) in widget.titles.indexed) ...[
          if (i > 0) const SizedBox(width: 14),
          GestureDetector(
            onTap: () => _pages.animateToPage(
              i,
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeOut,
            ),
            child: Text(
              title,
              style: theme.textTheme.labelLarge?.copyWith(
                color: i == _page
                    ? theme.colorScheme.onSurface
                    : theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
                fontWeight: i == _page ? FontWeight.w700 : FontWeight.w500,
                decoration: i == _page ? TextDecoration.underline : null,
                decorationThickness: 2,
              ),
            ),
          ),
        ],
        const Spacer(),
        if (widget.onDurations case final onDurations?)
          IconButton(
            visualDensity: VisualDensity.compact,
            tooltip: widget.durations ? 'Show percentages' : 'Show durations',
            isSelected: widget.durations,
            icon: const Icon(Icons.percent),
            selectedIcon: const Icon(Icons.schedule),
            onPressed: () => onDurations(!widget.durations),
          ),
        if (onCollapsed != null)
          IconButton(
            visualDensity: VisualDensity.compact,
            tooltip: 'Hide summary',
            icon: const Icon(Icons.expand_less),
            onPressed: () => onCollapsed(true),
          ),
      ],
    );
  }
}

/// Whether the [SummaryBar]s under it show durations, rather than
/// percentages.
class SummaryUnit extends InheritedWidget {
  const SummaryUnit({super.key, required this.durations, required super.child});

  final bool durations;

  /// Whether [context]'s bars show durations; percentages, with no
  /// [SummaryUnit] over it.
  static bool durationsOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<SummaryUnit>()?.durations ??
      false;

  @override
  bool updateShouldNotify(SummaryUnit oldWidget) =>
      durations != oldWidget.durations;
}

/// [rows] as bars split by share, one over another, with one legend
/// under them: each share's percentage of each row's whole, or, under a
/// [SummaryUnit] with durations, its time, to the minute. A row's
/// label, if it has one, goes before its bar. Time on nothing in
/// particular is left empty.
class SummaryBar extends StatelessWidget {
  const SummaryBar({super.key, required this.rows});

  /// One bar, with no label.
  SummaryBar.single({super.key, required List<SummarySlice> slices})
    : rows = [(null, slices)];

  final List<(String?, List<SummarySlice>)> rows;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final outline = theme.colorScheme.outlineVariant;
    final small = theme.textTheme.bodySmall;
    // The shares in the order the rows first have them, the empty ones
    // last, as in each bar.
    final labels = <String>[];
    final colors = <String, Color?>{};
    for (final (_, slices) in rows) {
      for (final slice in slices) {
        if (!colors.containsKey(slice.label)) labels.add(slice.label);
        colors[slice.label] = slice.color;
      }
    }
    final legend = [
      ...labels.where((label) => colors[label] != null),
      ...labels.where((label) => colors[label] == null),
    ];
    final durations = SummaryUnit.durationsOf(context);
    String amount(List<SummarySlice> slices, String label) {
      final slice = slices.where((s) => s.label == label).firstOrNull;
      if (slice == null) return '–';
      if (durations) {
        return formatDuration(
          Duration(minutes: (slice.time.inSeconds / 60).round()),
        )!;
      }
      final total = slices.fold(0, (sum, s) => sum + s.time.inSeconds);
      return '${(100 * slice.time.inSeconds / total).round()}%';
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final (label, slices) in rows)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Row(
              children: [
                if (label != null)
                  SizedBox(
                    width: 30,
                    child: Text(
                      label,
                      style: small?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                Expanded(child: _bar(slices, outline)),
              ],
            ),
          ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 14,
          runSpacing: 4,
          children: [
            for (final label in legend)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: colors[label],
                      border: colors[label] == null
                          ? Border.all(color: outline, width: 1.5)
                          : null,
                      borderRadius: BorderRadius.circular(2.5),
                    ),
                  ),
                  const SizedBox(width: 5),
                  ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: rows.length > 1 ? 110 : 130,
                    ),
                    child: Text(
                      label,
                      overflow: TextOverflow.ellipsis,
                      style: small,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    [for (final (_, slices) in rows) amount(slices, label)]
                        .join(' · '),
                    style: small?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ],
              ),
          ],
        ),
      ],
    );
  }

  Widget _bar(List<SummarySlice> slices, Color outline) => Container(
    height: 14,
    decoration: BoxDecoration(
      border: Border.all(color: outline),
      borderRadius: BorderRadius.circular(7),
    ),
    child: ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: Row(
        children: [
          for (final (i, slice) in slices.indexed)
            Expanded(
              flex: slice.time.inMinutes,
              child: Container(
                margin: EdgeInsets.only(left: i == 0 ? 0 : 1),
                color: slice.color,
              ),
            ),
        ],
      ),
    ),
  );
}

/// [child], telling [onHeight] its height after each layout that changes
/// it.
class _Measured extends SingleChildRenderObjectWidget {
  const _Measured({required this.onHeight, super.child});

  final ValueChanged<double> onHeight;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderMeasured(onHeight);

  @override
  void updateRenderObject(BuildContext context, _RenderMeasured renderObject) =>
      renderObject.onHeight = onHeight;
}

class _RenderMeasured extends RenderProxyBox {
  _RenderMeasured(this.onHeight);

  ValueChanged<double> onHeight;
  double? _height;

  @override
  void performLayout() {
    super.performLayout();
    final height = size.height;
    if (height == _height) return;
    _height = height;
    WidgetsBinding.instance.addPostFrameCallback((_) => onHeight(height));
  }
}
