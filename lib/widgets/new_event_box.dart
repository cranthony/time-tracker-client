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

/// Which way from the [NewEventBox.cursor] a button moves its other end:
/// later ([start]: the event starts at the cursor) or earlier ([end]).
enum CursorEnd { start, end }

/// A new event as it's being made: a box between two cursors -- the one
/// it was started from, with the buttons ([cursor]), and, once one's been
/// used, the [other] -- holding the event ([span]).
@immutable
class NewEventBox {
  const NewEventBox(this.cursor, {this.other});

  final DateTime cursor;
  final DateTime? other;

  /// The event: from the earlier cursor to the later; null until there
  /// are two, apart.
  (DateTime, DateTime)? get span => switch (other) {
    final other? when other != cursor =>
      cursor.isBefore(other) ? (cursor, other) : (other, cursor),
    _ => null,
  };

  /// How long the box is: nothing until there are two cursors.
  Duration get length => switch (other) {
    final other? => other.difference(cursor).abs(),
    null => Duration.zero,
  };

  /// It with its [cursor] moved alone.
  NewEventBox withCursor(DateTime cursor) => NewEventBox(cursor, other: other);

  /// It with its [other] cursor moved alone.
  NewEventBox withOther(DateTime other) => NewEventBox(cursor, other: other);

  /// It moved whole, its size intact, its cursor to [cursor].
  NewEventBox movedTo(DateTime cursor) =>
      NewEventBox(cursor, other: other?.add(cursor.difference(this.cursor)));

  /// It with its cursors at [start] and [end] -- each where it was, the
  /// [cursor] still the earlier if it was.
  NewEventBox at(DateTime start, DateTime end) => switch (other) {
    final other? when other.isBefore(cursor) => NewEventBox(end, other: start),
    _ => NewEventBox(start, other: end),
  };

  @override
  bool operator ==(Object other) =>
      other is NewEventBox &&
      other.cursor == cursor &&
      other.other == this.other;

  @override
  int get hashCode => Object.hash(cursor, other);

  @override
  String toString() => 'NewEventBox($cursor, other: $other)';
}

/// A [NewEventBox], over a [DayTimeline] for [day] at [scale]. Each of
/// its cursors is a line across the timeline, with its time at its left
/// and a handle at its right that moves it alone. The [box]'s
/// [NewEventBox.cursor] has in its middle a button below it, which moves
/// the other cursor an hour later each tap, and one above it, an hour
/// earlier -- an hour from it to start with -- or puts the other cursor
/// where either's dragged to; and the [mode] to pick. Between the
/// cursors, the event is shaded ([NewEventShadow]) -- unless [shaded] is
/// false -- tinged red and slowly pulsing where it [overwrites] events;
/// and in it, a bigger, fainter handle that moves the whole box.
class NewEventBoxView extends StatefulWidget {
  const NewEventBoxView({
    super.key,
    required this.day,
    required this.dayEnd,
    required this.scale,
    required this.box,
    required this.mode,
    required this.onMoveCursor,
    required this.onMoveOther,
    required this.onMoveBox,
    required this.onTap,
    required this.onDrag,
    required this.onPickMode,
    this.shaded = true,
    this.overwrites = false,
  });

  final DateTime day;
  final DateTime dayEnd;
  final double scale;
  final NewEventBox box;
  final CreateMode mode;

  /// Whether the event between the cursors is shaded.
  final bool shaded;

  /// Whether the event takes time from events already there.
  final bool overwrites;

  /// The [NewEventBox.cursor]'s handle dragged to a time.
  final ValueChanged<DateTime> onMoveCursor;

  /// The [NewEventBox.other] cursor's handle dragged to a time.
  final ValueChanged<DateTime> onMoveOther;

  /// The box's handle dragged: the box moved whole, its cursor to the
  /// time given.
  final ValueChanged<DateTime> onMoveBox;

  /// A button tapped: the other cursor an hour later, for
  /// [CursorEnd.start], or earlier.
  final ValueChanged<CursorEnd> onTap;

  /// A button dragged to a time: the other cursor there, the event to
  /// have its [end] at the cursor.
  final void Function(CursorEnd end, DateTime to) onDrag;
  final VoidCallback onPickMode;

  @override
  State<NewEventBoxView> createState() => _NewEventBoxViewState();
}

class _NewEventBoxViewState extends State<NewEventBoxView> {
  /// Where a drag is, down the timeline.
  double _dragY = 0;

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

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final box = widget.box;
    final y = _y(box.cursor);
    return Stack(
      clipBehavior: Clip.none,
      children: [
        if (box.span case (final start, final end) when widget.shaded)
          Positioned(
            left: timelineCardsLeft,
            right: 8,
            top: _y(start),
            height: (_y(end) - _y(start)).clamp(2.0, double.infinity),
            child: NewEventShadow(
              start: start,
              end: end,
              overwrites: widget.overwrites,
            ),
          ),
        if (box.other case final other?) ...[
          _boxHandle(colors, box.cursor, other),
          ..._line(
            colors,
            other,
            tooltip: 'Drag to move the other end',
            onDragTo: widget.onMoveOther,
          ),
        ],
        ..._line(
          colors,
          box.cursor,
          tooltip: 'Drag to move the cursor',
          onDragTo: widget.onMoveCursor,
        ),
        // In the middle of the cursor, clear of its handle: each button
        // on the side its event goes, touching the line.
        Positioned(
          left: timelineCardsLeft,
          right: 44,
          top: y - _buttonHeight - _buttonGap,
          height: 2 * (_buttonHeight + _buttonGap),
          child: Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _endButton(
                      colors,
                      CursorEnd.end,
                      Icons.arrow_upward,
                      'An hour earlier: tap to move the other end, or drag it',
                    ),
                    const SizedBox(height: 2 * _buttonGap),
                    _endButton(
                      colors,
                      CursorEnd.start,
                      Icons.arrow_downward,
                      'An hour later: tap to move the other end, or drag it',
                    ),
                  ],
                ),
                const SizedBox(width: 8),
                _modeButton(colors),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// The box's own handle, in its middle, right of its buttons: bigger
  /// than the cursors', and fainter, to move the whole box by -- there
  /// whether or not the event's shaded.
  Widget _boxHandle(ColorScheme colors, DateTime cursor, DateTime other) {
    final middle = (_y(cursor) + _y(other)) / 2;
    final color = widget.overwrites
        ? Color.lerp(colors.primary, Colors.red, 0.6)!
        : colors.primary;
    return Positioned(
      left: timelineCardsLeft,
      right: 8,
      top: middle - 20,
      height: 40,
      child: Align(
        alignment: const Alignment(0.6, 0),
        child: Tooltip(
          message: 'Drag to move the event',
          child: GestureDetector(
            dragStartBehavior: DragStartBehavior.down,
            onVerticalDragStart: (_) => _dragY = _y(cursor),
            onVerticalDragUpdate: (details) {
              _dragY += details.delta.dy;
              widget.onMoveBox(_time(_dragY));
            },
            child: Container(
              width: 72,
              height: 40,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.18),
                border: Border.all(color: color.withValues(alpha: 0.35)),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Icon(
                Icons.unfold_more,
                size: 28,
                color: color.withValues(alpha: 0.7),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// A cursor: a line across the timeline at [time], with the time at its
  /// left and, at its right, a handle that's dragged to [onDragTo] a time.
  /// Only the handle takes a touch: a tap elsewhere goes to the timeline.
  List<Widget> _line(
    ColorScheme colors,
    DateTime time, {
    required String tooltip,
    required ValueChanged<DateTime> onDragTo,
  }) {
    final y = _y(time);
    return [
      Positioned(
        left: timelineTimesWidth - 4,
        right: 0,
        top: y - 1,
        height: 2,
        child: IgnorePointer(child: ColoredBox(color: colors.primary)),
      ),
      Positioned(
        left: 4,
        top: y - 10,
        height: 20,
        child: IgnorePointer(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: colors.primary,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              clockTime(context, time),
              style: TextStyle(
                color: colors.onPrimary,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ),
      Positioned(
        right: 4,
        top: y - 16,
        width: 32,
        height: 32,
        child: Tooltip(
          message: tooltip,
          child: GestureDetector(
            // From where the finger went down, so the line follows it.
            dragStartBehavior: DragStartBehavior.down,
            onVerticalDragStart: (_) => _dragY = y,
            onVerticalDragUpdate: (details) {
              _dragY += details.delta.dy;
              onDragTo(_time(_dragY));
            },
            child: Material(
              color: colors.primary,
              shape: const StadiumBorder(),
              elevation: 2,
              child: Icon(Icons.drag_handle, size: 20, color: colors.onPrimary),
            ),
          ),
        ),
      ),
    ];
  }

  /// How tall the buttons above and below the line are, and how far
  /// from it.
  static const _buttonHeight = 44.0;
  static const _buttonGap = 3.0;

  /// The button moving the other cursor [end]'s way: a "+", with [arrow]
  /// pointing the way the event goes from the cursor -- up, above the
  /// line; down, below it. Tapped for an hour; dragged to where the other
  /// cursor goes.
  Widget _endButton(
    ColorScheme colors,
    CursorEnd end,
    IconData arrow,
    String tooltip,
  ) {
    final color = colors.onPrimaryContainer;
    final icons = [
      Icon(Icons.add, size: 20, color: color),
      Icon(arrow, size: 14, color: color),
    ];
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        dragStartBehavior: DragStartBehavior.down,
        onVerticalDragStart: (_) => _dragY = _y(widget.box.cursor),
        onVerticalDragUpdate: (details) {
          _dragY += details.delta.dy;
          widget.onDrag(end, _time(_dragY));
        },
        child: Material(
          color: colors.primaryContainer,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          elevation: 2,
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () => widget.onTap(end),
            child: SizedBox(
              width: 40,
              height: _buttonHeight,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                // The arrow away from the line, the "+" by it.
                children: end == CursorEnd.end
                    ? icons.reversed.toList()
                    : icons,
              ),
            ),
          ),
        ),
      ),
    );
  }

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

/// The new event, shaded from [start] to [end], with its times in its
/// corner: tinged red, and slowly pulsing, where it [overwrites] events.
/// It takes no touches: they go to what's under it.
class NewEventShadow extends StatefulWidget {
  const NewEventShadow({
    super.key,
    required this.start,
    required this.end,
    this.overwrites = false,
  });

  final DateTime start;
  final DateTime end;
  final bool overwrites;

  @override
  State<NewEventShadow> createState() => _NewEventShadowState();
}

class _NewEventShadowState extends State<NewEventShadow>
    with SingleTickerProviderStateMixin {
  /// The red tinge's slow pulse, while [NewEventShadow.overwrites].
  late final _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  );

  @override
  void initState() {
    super.initState();
    _pulseIfOverwriting();
  }

  @override
  void didUpdateWidget(NewEventShadow old) {
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

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final tinge = Color.lerp(colors.primary, Colors.red, 0.6)!;
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _pulse,
        builder: (context, _) {
          final color = widget.overwrites ? tinge : colors.primary;
          final alpha = widget.overwrites ? 0.16 + 0.22 * _pulse.value : 0.2;
          return Container(
            // Clear of the handles at the right.
            padding: const EdgeInsets.fromLTRB(4, 4, 36, 4),
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
                '${clockTime(context, widget.start)} – '
                '${clockTime(context, widget.end)}',
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
    );
  }
}

/// [time] as a time of day, here: the server's times are in UTC.
String clockTime(BuildContext context, DateTime time) =>
    MaterialLocalizations.of(context)
        .formatTimeOfDay(TimeOfDay.fromDateTime(time.toLocal()));
