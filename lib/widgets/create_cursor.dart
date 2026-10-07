import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import 'day_timeline.dart';

/// Whether a new event keeps clear of the events already there, or takes
/// its time from them.
enum CreateMode {
  keep(
    'Keep events',
    'The new event fits around the events already there: it never '
        'overlaps them.',
    Icons.lock_outline,
  ),
  overwrite(
    'Overwrite events',
    'The new event takes its time from the events already there: they '
        'are shortened, split or removed to make room.',
    Icons.layers_clear,
  );

  const CreateMode(this.label, this.description, this.icon);

  final String label;
  final String description;
  final IconData icon;
}

/// Asks which [CreateMode] to create in, [current] picked to start with;
/// null if dismissed.
Future<CreateMode?> showCreateModeDialog(
  BuildContext context,
  CreateMode current,
) => showDialog<CreateMode>(
  context: context,
  builder: (context) => SimpleDialog(
    title: const Text('Events in the way'),
    children: [
      RadioGroup<CreateMode>(
        groupValue: current,
        onChanged: (mode) => Navigator.of(context).pop(mode),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final mode in CreateMode.values)
              RadioListTile<CreateMode>(
                value: mode,
                secondary: Icon(mode.icon),
                title: Text(mode.label),
                subtitle: Text(mode.description),
              ),
          ],
        ),
      ),
    ],
  ),
);

/// Which end of a new event the cursor is.
enum CursorEnd { start, end }

/// The cursor a new event is made from, over a [DayTimeline] for [day]
/// at [scale]: a line across it at [at], with the time beside it; on it,
/// buttons to start the event there and to end it there -- tapped, or
/// dragged to where its other end goes -- and the [mode] to pick; and the
/// event as it would be, [span], shaded, tinged red and slowly pulsing
/// where it [overwrites] events. Dragging the line moves it.
class CreateCursor extends StatefulWidget {
  const CreateCursor({
    super.key,
    required this.day,
    required this.dayEnd,
    required this.scale,
    required this.at,
    required this.mode,
    required this.onMove,
    required this.onTap,
    required this.onDrag,
    required this.onPickMode,
    this.span,
    this.overwrites = false,
  });

  final DateTime day;
  final DateTime dayEnd;
  final double scale;

  /// Where the line is.
  final DateTime at;

  /// The new event as it would be, if it's been made.
  final (DateTime, DateTime)? span;
  final CreateMode mode;

  /// Whether [span] takes time from events already there.
  final bool overwrites;

  /// The line dragged to a time.
  final ValueChanged<DateTime> onMove;

  /// A button tapped: the event to start, or end, at [at].
  final ValueChanged<CursorEnd> onTap;

  /// A button dragged to a time: the event's other end.
  final void Function(CursorEnd end, DateTime to) onDrag;
  final VoidCallback onPickMode;

  @override
  State<CreateCursor> createState() => _CreateCursorState();
}

class _CreateCursorState extends State<CreateCursor>
    with SingleTickerProviderStateMixin {
  /// The red tinge's slow pulse, while [CreateCursor.overwrites].
  late final _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  );

  /// Where a drag is, down the timeline.
  double _dragY = 0;

  @override
  void initState() {
    super.initState();
    _pulseIfOverwriting();
  }

  @override
  void didUpdateWidget(CreateCursor old) {
    super.didUpdateWidget(old);
    _pulseIfOverwriting();
  }

  void _pulseIfOverwriting() {
    if (widget.overwrites && !_pulse.isAnimating) {
      _pulse.repeat(reverse: true);
    } else if (!widget.overwrites && _pulse.isAnimating) {
      _pulse
        ..stop()
        ..value = 0;
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  double _y(DateTime time) => timelineOffset(
    time,
    day: widget.day,
    dayEnd: widget.dayEnd,
    scale: widget.scale,
  );

  DateTime _time(double y) => timelineTime(
    y,
    day: widget.day,
    dayEnd: widget.dayEnd,
    scale: widget.scale,
  );

  /// [t] as a time of day, here: the server's times are in UTC.
  String _clock(DateTime t) =>
      MaterialLocalizations.of(context)
          .formatTimeOfDay(TimeOfDay.fromDateTime(t.toLocal()));

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final y = _y(widget.at);
    return Stack(
      clipBehavior: Clip.none,
      children: [
        if (widget.span case (final start, final end))
          _shadow(colors, start, end),
        // The line, dragged to move it.
        Positioned(
          left: 0,
          right: 0,
          top: y - 14,
          height: 28,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            // From where the finger went down, so the line follows it.
            dragStartBehavior: DragStartBehavior.down,
            onVerticalDragStart: (_) => _dragY = y,
            onVerticalDragUpdate: (details) {
              _dragY += details.delta.dy;
              widget.onMove(_time(_dragY));
            },
            child: Stack(
              alignment: Alignment.centerLeft,
              children: [
                Positioned(
                  left: timelineTimesWidth - 4,
                  right: 0,
                  child: Container(height: 2, color: colors.primary),
                ),
                Positioned(
                  left: 4,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: colors.primary,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      _clock(widget.at),
                      style: TextStyle(
                        color: colors.onPrimary,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        Positioned(
          right: 8,
          top: y - 20,
          height: 40,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _endButton(
                colors,
                CursorEnd.start,
                Icons.vertical_align_top,
                'Start here: tap, or drag to where it ends',
              ),
              const SizedBox(width: 6),
              _endButton(
                colors,
                CursorEnd.end,
                Icons.vertical_align_bottom,
                'End here: tap, or drag to where it starts',
              ),
              const SizedBox(width: 6),
              _modeButton(colors),
            ],
          ),
        ),
      ],
    );
  }

  Widget _shadow(ColorScheme colors, DateTime start, DateTime end) {
    final top = _y(start);
    final height = (_y(end) - top).clamp(2.0, double.infinity);
    final tinge = Color.lerp(colors.primary, Colors.red, 0.6)!;
    return Positioned(
      left: timelineCardsLeft,
      right: 8,
      top: top,
      height: height,
      child: IgnorePointer(
        child: AnimatedBuilder(
          animation: _pulse,
          builder: (context, _) {
            final color = widget.overwrites ? tinge : colors.primary;
            final alpha = widget.overwrites ? 0.16 + 0.22 * _pulse.value : 0.2;
            return Container(
              padding: const EdgeInsets.all(4),
              // In its corner, solid, to read over the events under it.
              alignment: Alignment.bottomRight,
              decoration: BoxDecoration(
                color: color.withValues(alpha: alpha),
                border: Border.all(color: color, width: 1.5),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '${_clock(start)} – ${_clock(end)}',
                  maxLines: 1,
                  style: TextStyle(
                    color: widget.overwrites ? Colors.white : colors.onPrimary,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _endButton(
    ColorScheme colors,
    CursorEnd end,
    IconData icon,
    String tooltip,
  ) => Tooltip(
    message: tooltip,
    child: GestureDetector(
      dragStartBehavior: DragStartBehavior.down,
      onVerticalDragStart: (_) => _dragY = _y(widget.at),
      onVerticalDragUpdate: (details) {
        _dragY += details.delta.dy;
        widget.onDrag(end, _time(_dragY));
      },
      child: Material(
        color: colors.primaryContainer,
        shape: const CircleBorder(),
        elevation: 2,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: () => widget.onTap(end),
          child: SizedBox.square(
            dimension: 40,
            child: Icon(icon, color: colors.onPrimaryContainer),
          ),
        ),
      ),
    ),
  );

  Widget _modeButton(ColorScheme colors) => Tooltip(
    message: '${widget.mode.label}: tap to change',
    child: Material(
      color: widget.mode == CreateMode.overwrite
          ? Color.lerp(colors.errorContainer, colors.surface, 0.2)
          : colors.surfaceContainerHigh,
      shape: const StadiumBorder(),
      elevation: 2,
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: widget.onPickMode,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 8, 4, 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(widget.mode.icon, size: 22),
              const Icon(Icons.arrow_drop_down, size: 20),
            ],
          ),
        ),
      ),
    ),
  );
}
