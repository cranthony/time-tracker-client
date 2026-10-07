import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import 'create_mode_icon.dart';
import 'day_timeline.dart';
import 'other_events.dart';

/// What a new event does with the events already there: keeps clear of
/// them; overwrites them -- trimming them, or cancelling them; or pushes
/// them along, out of its way.
enum CreateMode {
  keep(
    'Keep events',
    'The new event fits around the events already there: it never '
        'overlaps them.',
    Icons.lock_outline,
  ),
  trim(
    'Overwrite and trim',
    'The new event takes its time from the events already there: they '
        'are shortened, or split around it, to make room; one it covers '
        'whole is cancelled.',
    Icons.content_cut,
  ),
  cancel(
    'Overwrite and cancel',
    'Every event the new one touches is cancelled, whole.',
    Icons.event_busy,
  ),
  push(
    'Push',
    'Like Keep, the cursor snaps out of events -- but it can sit between '
        'two that meet. The events after it are pushed along, into free '
        'time, to make room -- as far as the day has room.',
    Icons.keyboard_double_arrow_down,
  ),
  trimPush(
    'Trim and push',
    'An event the new one starts inside of is cut short there; the events '
        'after it are pushed along, into free time, to make room -- as '
        'far as the day has room.',
    // Drawn: scissors over a push (see [CreateModeIcon]).
    null,
  ),
  splitPush(
    'Split and push',
    'An event the new one starts inside of is split there, and the rest '
        'of it pushed along after the new one, with the events after it, '
        'into free time -- as far as the day has room.',
    // Drawn: a zipper coming open over a push (see [CreateModeIcon]).
    null,
  );

  const CreateMode(this.label, this.description, this.icon);

  final String label;
  final String description;

  /// Its Material icon; null where [CreateModeIcon] draws its own.
  final IconData? icon;

  /// Whether it changes the events in the way.
  bool get overwrites => this != keep;

  /// Whether it pushes the events in the way along ([OtherEvents.pushing]).
  bool get pushes => this == trimPush || this == push || this == splitPush;

  /// What, pushing, it does with an event it starts inside of.
  Inside get inside => this == splitPush ? Inside.split : Inside.trim;
}

/// Where a pushed event goes, to show: from [start] to [end], [label]led.
typedef PushedEvent = ({DateTime start, DateTime end, String label});

/// Asks which [CreateMode] to create in, [current] picked to start with;
/// null if dismissed. Only the one picked says what it does: tapping
/// another picks it, and tapping it again, or Done, settles on it.
Future<CreateMode?> showCreateModeDialog(
  BuildContext context,
  CreateMode current,
) => showDialog<CreateMode>(
  context: context,
  builder: (context) {
    var picked = current;
    return StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: const Text('Events in the way'),
        contentPadding: const EdgeInsets.symmetric(vertical: 16),
        content: SingleChildScrollView(
          child: RadioGroup<CreateMode>(
            groupValue: picked,
            onChanged: (mode) => setState(() => picked = mode ?? picked),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Its icon beside its radio, ahead of the text, to pick
                // out.
                for (final mode in CreateMode.values)
                  ListTile(
                    onTap: () => mode == picked
                        ? Navigator.of(context).pop(mode)
                        : setState(() => picked = mode),
                    contentPadding: const EdgeInsetsDirectional.only(
                      start: 12,
                      end: 24,
                    ),
                    titleAlignment: ListTileTitleAlignment.top,
                    leading: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Radio<CreateMode>(value: mode),
                        CreateModeIcon(mode),
                      ],
                    ),
                    title: Text(mode.label),
                    subtitle: mode == picked ? Text(mode.description) : null,
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(picked),
            child: const Text('Done'),
          ),
        ],
      ),
    );
  },
);

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
    this.covers,
    this.pushed = const [],
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

  /// What the shadow covers, if it's more than the event: the events it
  /// cancels whole.
  final (DateTime, DateTime)? covers;

  /// Where the events it pushes go: each outlined there.
  final List<PushedEvent> pushed;

  /// The [NewEventBox.cursor]'s handle dragged to a time.
  final ValueChanged<DateTime> onMoveCursor;

  /// The [NewEventBox.other] cursor's handle dragged to a time.
  final ValueChanged<DateTime> onMoveOther;

  /// The box's handle dragged: the box moved whole, its cursor to the
  /// time given.
  final ValueChanged<DateTime> onMoveBox;

  /// A button tapped: the other cursor moved by its [step] -- an hour
  /// later, below the cursor, or earlier, above it.
  final ValueChanged<Duration> onTap;

  /// A button dragged to a time: the other cursor there, on the side of
  /// the cursor its [step] goes.
  final void Function(Duration step, DateTime to) onDrag;
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
            top: _y(widget.covers?.$1 ?? start),
            height:
                (_y(widget.covers?.$2 ?? end) - _y(widget.covers?.$1 ?? start))
                    .clamp(2.0, double.infinity),
            child: NewEventShadow(
              start: start,
              end: end,
              overwrites: widget.overwrites,
            ),
          ),
        for (final pushed in widget.pushed)
          Positioned(
            left: timelineCardsLeft,
            right: 8,
            top: _y(pushed.start),
            height: (_y(pushed.end) - _y(pushed.start)).clamp(
              2.0,
              double.infinity,
            ),
            child: PushedEventOutline(label: pushed.label),
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
                    _stepButton(
                      colors,
                      -_hour,
                      Icons.arrow_upward,
                      'An hour earlier: tap to move the other end, or drag it',
                    ),
                    const SizedBox(height: 2 * _buttonGap),
                    _stepButton(
                      colors,
                      _hour,
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

  /// How far a tap on a button moves the other cursor.
  static const _hour = Duration(hours: 1);

  /// The button moving the other cursor by [step] -- later, below the
  /// line, or earlier, above it: a "+", with [arrow] pointing the way the
  /// event goes from the cursor. Tapped, by [step]; dragged, to where the
  /// other cursor goes.
  Widget _stepButton(
    ColorScheme colors,
    Duration step,
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
          widget.onDrag(step, _time(_dragY));
        },
        child: Material(
          color: colors.primaryContainer,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          elevation: 2,
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () => widget.onTap(step),
            child: SizedBox(
              width: 40,
              height: _buttonHeight,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                // The arrow away from the line, the "+" by it.
                children: step.isNegative ? icons.reversed.toList() : icons,
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
      color: widget.mode.overwrites
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
              CreateModeIcon(widget.mode, size: 22),
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

/// Where keeping events moved a [NewEventBox]: a pointed arrow down the
/// timeline for [day] at [scale], [from] where it was put [to] where it
/// fits, that draws out to its point and then fades away. It takes no
/// touches.
class KeptMoveArrow extends StatefulWidget {
  const KeptMoveArrow({
    super.key,
    required this.from,
    required this.to,
    required this.day,
    required this.dayEnd,
    required this.scale,
  });

  final DateTime from;
  final DateTime to;
  final DateTime day;
  final DateTime dayEnd;
  final double scale;

  @override
  State<KeptMoveArrow> createState() => _KeptMoveArrowState();
}

class _KeptMoveArrowState extends State<KeptMoveArrow>
    with SingleTickerProviderStateMixin {
  late final _shown = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  )..forward();

  @override
  void dispose() {
    _shown.dispose();
    super.dispose();
  }

  double _y(DateTime time) => timelineOffset(
    time,
    day: widget.day,
    dayEnd: widget.dayEnd,
    scale: widget.scale,
  );

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary;
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _shown,
        builder: (context, _) {
          final t = _shown.value;
          if (t == 1) return const SizedBox.shrink();
          return CustomPaint(
            size: Size.infinite,
            painter: _ArrowPainter(
              from: _y(widget.from),
              to: _y(widget.to),
              color: color,
              // Drawn out over the first quarter; held; faded over the
              // last half.
              drawn: Curves.easeOut.transform((t * 4).clamp(0.0, 1.0)),
              opacity:
                  1 - Curves.easeIn.transform(((t - 0.5) * 2).clamp(0.0, 1.0)),
            ),
          );
        },
      ),
    );
  }
}

class _ArrowPainter extends CustomPainter {
  _ArrowPainter({
    required this.from,
    required this.to,
    required this.color,
    required this.drawn,
    required this.opacity,
  });

  final double from;
  final double to;
  final Color color;
  final double drawn;
  final double opacity;

  @override
  void paint(Canvas canvas, Size size) {
    // Too short to point anywhere.
    if ((to - from).abs() < 12) return;
    // Left of the box's middle, clear of its buttons and handles.
    final x = timelineCardsLeft + (size.width - timelineCardsLeft - 8) * 0.2;
    final paint = Paint()
      ..color = color.withValues(alpha: color.a * opacity)
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    // Where it was put: a ring.
    canvas.drawCircle(Offset(x, from), 6, paint..strokeWidth = 3);
    final down = to > from ? 1.0 : -1.0;
    final start = from + down * 8;
    final tip = start + (to - start) * drawn;
    canvas.drawLine(Offset(x, start), Offset(x, tip), paint..strokeWidth = 4);
    final head = Path()
      ..moveTo(x, tip + down * 4)
      ..lineTo(x - 10, tip - down * 12)
      ..lineTo(x + 10, tip - down * 12)
      ..close();
    canvas.drawPath(head, Paint()..color = paint.color);
  }

  @override
  bool shouldRepaint(_ArrowPainter old) =>
      old.from != from ||
      old.to != to ||
      old.color != color ||
      old.drawn != drawn ||
      old.opacity != opacity;
}

/// Where a pushed event goes ([PushedEvent]): outlined, with its [label]
/// and an arrow, over what's there. It takes no touches.
class PushedEventOutline extends StatelessWidget {
  const PushedEventOutline({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return IgnorePointer(
      child: Container(
        padding: const EdgeInsets.fromLTRB(8, 2, 40, 2),
        alignment: Alignment.topLeft,
        decoration: BoxDecoration(
          color: colors.tertiaryContainer.withValues(alpha: 0.85),
          border: Border.all(color: colors.tertiary, width: 1.5),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Icon(Icons.redo, size: 14, color: colors.onTertiaryContainer),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelMedium
                    ?.copyWith(color: colors.onTertiaryContainer),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
