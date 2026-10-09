import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import 'cursor_modes.dart';
import 'cursor_snap.dart';
import 'day_timeline.dart';

/// Where a pushed event goes, to show: from [start] to [end], [label]led.
typedef PushedEvent = ({DateTime start, DateTime end, String label});

/// An event pending: a new one as it's being made, or one being moved --
/// a box between two cursors -- the one it was started from, with the
/// buttons ([cursor]), and, once one's been used, the [other] -- holding
/// the event ([span]).
@immutable
class PendingEventBox {
  const PendingEventBox(this.cursor, {this.other});

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
  PendingEventBox withCursor(DateTime cursor) =>
      PendingEventBox(cursor, other: other);

  /// It with its [other] cursor moved alone.
  PendingEventBox withOther(DateTime other) =>
      PendingEventBox(cursor, other: other);

  /// Whether the [cursor] is its top end: the [other] below it, or not
  /// apart from it.
  bool get cursorOnTop => other == null || !other!.isBefore(cursor);

  /// It with its top end at [time]: the [other] cursor, if there's no
  /// event between them yet, to make one above.
  PendingEventBox withTop(DateTime time) =>
      span != null && cursorOnTop ? withCursor(time) : withOther(time);

  /// It with its foot at [time]: the [other] cursor, if there's no event
  /// between them yet, to make one below.
  PendingEventBox withFoot(DateTime time) =>
      span != null && !cursorOnTop ? withCursor(time) : withOther(time);

  /// It moved whole, its size intact, its cursor to [cursor].
  PendingEventBox movedTo(DateTime cursor) => PendingEventBox(
    cursor,
    other: other?.add(cursor.difference(this.cursor)),
  );

  /// It with its cursors at [start] and [end] -- each where it was, the
  /// [cursor] still the earlier if it was.
  PendingEventBox at(DateTime start, DateTime end) => switch (other) {
    final other? when other.isBefore(cursor) => PendingEventBox(
      end,
      other: start,
    ),
    _ => PendingEventBox(start, other: end),
  };

  @override
  bool operator ==(Object other) =>
      other is PendingEventBox &&
      other.cursor == cursor &&
      other.other == this.other;

  @override
  int get hashCode => Object.hash(cursor, other);

  @override
  String toString() => 'PendingEventBox($cursor, other: $other)';
}

/// What a cursor's time is, besides a time: the start or end of an event
/// ([what] "start" or "end", [name] the event's), or a note ([what]
/// "note", [name] its text).
typedef SnapMark = ({String what, String name});

/// A [PendingEventBox], over a [DayTimeline] for [day] at [scale]: a
/// cursor, and once there's a box, two -- its top and its bottom, alike.
/// Each is a line across the timeline with, at its left, its time --
/// after a corner, ┌ for the top and └ for the bottom -- and what it's
/// on ([marks]: "end of Lunch", "start of Work", "note: …"), with
/// scissors where it's inside an event, cutting it ([cuts]); tapping its
/// time types it in ([onEditTime]). At its right, a handle that drags it.
///
/// Before there's a box, the cursor has on each side an arrow, stepping
/// it to its next stop, and a "+", making the box that way. Once there's
/// one, each cursor has on its outside -- away from the box -- a "+",
/// stretching the box at that end to its next stop, and a "−", shrinking
/// it; a step that can't go -- [canStep] says -- is greyed out. The
/// [selected] cursor -- the last touched -- is drawn bolder, and where
/// two cursors' buttons would overlap, only its are shown.
///
/// The box -- the event between the cursors -- is shaded
/// ([PendingEventShadow]), unless [shaded] is false: tinged red and
/// slowly pulsing where it [overwrites] events, and with its [mode]'s
/// icon, unless it trims, as it does by default. Dragged, it moves whole ([onMoveBox]); tapped, its mode can be
/// changed ([onTapBox]).
class PendingEventBoxView extends StatefulWidget {
  const PendingEventBoxView({
    super.key,
    required this.day,
    required this.dayEnd,
    required this.scale,
    required this.box,
    required this.mode,
    required this.onMoveCursor,
    required this.onMoveOther,
    required this.onMoveBox,
    required this.onStep,
    required this.onTapBox,
    required this.onEditTime,
    this.canStep,
    this.marks,
    this.cuts,
    this.onSelect,
    this.selected = CursorRole.anchor,
    this.shaded = true,
    this.overwrites = false,
    this.covers,
    this.pushed = const [],
    this.label,
  });

  final DateTime day;
  final DateTime dayEnd;
  final double scale;
  final PendingEventBox box;

  /// What the box does with the events in its way.
  final EndMode mode;

  /// Whether the event between the cursors is shaded.
  final bool shaded;

  /// Whether the event takes time from events already there.
  final bool overwrites;

  /// What the shadow covers, if it's more than the event: the events it
  /// cancels whole.
  final (DateTime, DateTime)? covers;

  /// Where the events it pushes go: each outlined there.
  final List<PushedEvent> pushed;

  /// What it is, by the box, above it: the event it's moving, if it's
  /// moving one.
  final String? label;

  /// The [PendingEventBox.cursor]'s handle dragged to a time.
  final ValueChanged<DateTime> onMoveCursor;

  /// The [PendingEventBox.other] cursor's handle dragged to a time.
  final ValueChanged<DateTime> onMoveOther;

  /// The box dragged: moved whole, its [PendingEventBox.cursor] to the
  /// time given.
  final ValueChanged<DateTime> onMoveBox;

  /// A cursor's button tapped: [role]'s cursor to its next stop, [later]
  /// or earlier. Before there's a box, a "+" makes it: the other cursor's
  /// step from the first.
  final void Function(CursorRole role, {required bool later}) onStep;

  /// Whether [role]'s cursor can step [later] (or earlier); all can, if
  /// null.
  final bool Function(CursorRole role, {required bool later})? canStep;

  /// The box tapped: to change what it does with the events in its way.
  final VoidCallback onTapBox;

  /// A cursor's time tapped: to type it in.
  final ValueChanged<CursorRole> onEditTime;

  /// What a cursor at a time is on; none, if null.
  final List<SnapMark> Function(DateTime time)? marks;

  /// Whether a cursor at a time is inside an event, cutting it.
  final bool Function(DateTime time)? cuts;

  /// A cursor touched -- dragged, or a button of it tapped: the one
  /// [selected] now.
  final ValueChanged<CursorRole>? onSelect;

  /// The cursor last touched.
  final CursorRole selected;

  @override
  State<PendingEventBoxView> createState() => _PendingEventBoxViewState();
}

class _PendingEventBoxViewState extends State<PendingEventBoxView> {
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

  /// How big a cursor's buttons are, how far apart, and how far from its
  /// line.
  static const _buttonSize = 48.0;
  static const _buttonSpacing = 12.0;
  static const _buttonGap = 6.0;

  /// How wide the cursors' handles are, and how tall.
  static const _handleWidth = 64.0;
  static const _handleHeight = 32.0;

  /// How wide a cursor's time, and what it's on, can be.
  static const _labelWidth = 150.0;

  void _select(CursorRole role) => widget.onSelect?.call(role);

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final box = widget.box;
    final span = box.span;
    return LayoutBuilder(
      builder: (context, constraints) {
        // The buttons, right of the cursors' labels, clear of the handles.
        final middle =
            (_labelWidth + 12 + constraints.maxWidth - _handleWidth - 8) / 2;
        final groups = <(CursorRole, Rect, Widget)>[];
        // The cursors, top first; each one's buttons on its outside.
        final cursors = <(CursorRole, DateTime, bool)>[];
        if (box.other case final other? when span != null) {
          final cursorOnTop = box.cursorOnTop;
          cursors
            ..add((CursorRole.anchor, box.cursor, cursorOnTop))
            ..add((CursorRole.end, other, !cursorOnTop));
          for (final (role, time, top) in cursors) {
            groups.add(
              _group(colors, role, _y(time), above: top, middle: middle),
            );
          }
        } else {
          cursors.add((CursorRole.anchor, box.cursor, true));
          final y = _y(box.cursor);
          groups
            ..add(_alone(colors, y, above: true, middle: middle))
            ..add(_alone(colors, y, above: false, middle: middle));
        }
        // Where two cursors' buttons would overlap, the selected one's.
        bool hidden((CursorRole, Rect, Widget) g) =>
            g.$1 != widget.selected &&
            groups.any((o) => o.$1 == widget.selected && o.$2.overlaps(g.$2));
        final alone = span == null;
        return Stack(
          clipBehavior: Clip.none,
          children: [
            if (span case (final start, final end) when widget.shaded)
              Positioned(
                left: timelineCardsLeft,
                right: 8,
                top: _y(widget.covers?.$1 ?? start),
                height:
                    (_y(widget.covers?.$2 ?? end) -
                            _y(widget.covers?.$1 ?? start))
                        .clamp(2.0, double.infinity),
                child: PendingEventShadow(
                  start: start,
                  end: end,
                  overwrites: widget.overwrites,
                  // Trimming goes without saying.
                  icon: widget.mode == EndMode.trim ? null : widget.mode.icon,
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
            // The box itself: dragged, moved whole; tapped, its mode.
            if (span case (final start, final end))
              Positioned(
                left: timelineCardsLeft,
                right: _handleWidth + 12,
                top: _y(start),
                height: (_y(end) - _y(start)).clamp(8.0, double.infinity),
                child: Tooltip(
                  message:
                      'Drag to move the event; tap for what it does '
                      'with the events in its way',
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    dragStartBehavior: DragStartBehavior.down,
                    onTap: widget.onTapBox,
                    onVerticalDragStart: (_) => _dragY = _y(box.cursor),
                    onVerticalDragUpdate: (details) {
                      _dragY += details.delta.dy;
                      widget.onMoveBox(_time(_dragY));
                    },
                  ),
                ),
              ),
            for (final (role, time, top) in cursors)
              ..._line(colors, role, time, top: alone ? null : top),
            for (final group in groups)
              if (!hidden(group))
                Positioned.fromRect(rect: group.$2, child: group.$3),
            // The label, above the box: what it's moving.
            if ((widget.label, span) case (final label?, (final start, _)))
              Positioned(
                left: timelineCardsLeft,
                top: _y(start) - 50,
                height: 20,
                child: IgnorePointer(child: _pill(colors, label)),
              ),
          ],
        );
      },
    );
  }

  Widget _pill(ColorScheme colors, String text) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    decoration: BoxDecoration(
      color: colors.primary,
      borderRadius: BorderRadius.circular(10),
    ),
    child: Text(
      text,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        color: colors.onPrimary,
        fontSize: 11,
        fontWeight: FontWeight.w600,
      ),
    ),
  );

  /// The cursor's buttons before there's a box, [above] its line or
  /// below: an arrow, stepping it that way, and a "+", making the box.
  (CursorRole, Rect, Widget) _alone(
    ColorScheme colors,
    double y, {
    required bool above,
    required double middle,
  }) {
    final later = !above;
    return _row(CursorRole.anchor, y, above: above, middle: middle, [
      _button(
        colors,
        icon: later ? Icons.arrow_downward : Icons.arrow_upward,
        tooltip: later
            ? 'Move the cursor to its next stop, later'
            : 'Move the cursor to its next stop, earlier',
        enabled: widget.canStep?.call(CursorRole.anchor, later: later) ?? true,
        onTap: () {
          _select(CursorRole.anchor);
          widget.onStep(CursorRole.anchor, later: later);
        },
      ),
      _button(
        colors,
        icon: Icons.add,
        arrow: later ? Icons.arrow_downward : Icons.arrow_upward,
        primary: true,
        tooltip: later ? 'Stretch it later' : 'Stretch it earlier',
        onTap: () {
          _select(CursorRole.end);
          widget.onStep(CursorRole.end, later: later);
        },
        // Dragged, the box made where it goes.
        onDragTo: (to) {
          _select(CursorRole.end);
          widget.onMoveOther(to);
        },
        from: y,
      ),
    ]);
  }

  /// [role]'s buttons, at [y], [above] its line or below -- the way that's
  /// out of the box: its "−" and its "+".
  (CursorRole, Rect, Widget) _group(
    ColorScheme colors,
    CursorRole role,
    double y, {
    required bool above,
    required double middle,
  }) {
    // Outward: earlier above the line, later below it.
    final later = !above;
    return _row(role, y, above: above, middle: middle, [
      _button(
        colors,
        icon: Icons.remove,
        arrow: later ? Icons.arrow_upward : Icons.arrow_downward,
        tooltip: later ? 'Shrink it from the foot' : 'Shrink it from the top',
        enabled: widget.canStep?.call(role, later: !later) ?? true,
        onTap: () {
          _select(role);
          widget.onStep(role, later: !later);
        },
      ),
      _button(
        colors,
        icon: Icons.add,
        arrow: later ? Icons.arrow_downward : Icons.arrow_upward,
        primary: true,
        tooltip: later ? 'Stretch it later' : 'Stretch it earlier',
        enabled: widget.canStep?.call(role, later: later) ?? true,
        onTap: () {
          _select(role);
          widget.onStep(role, later: later);
        },
        // Dragged, this end where it goes.
        onDragTo: (to) {
          _select(role);
          role == CursorRole.anchor
              ? widget.onMoveCursor(to)
              : widget.onMoveOther(to);
        },
        from: y,
      ),
    ]);
  }

  (CursorRole, Rect, Widget) _row(
    CursorRole role,
    double y,
    List<Widget> buttons, {
    required bool above,
    required double middle,
  }) {
    final width =
        buttons.length * _buttonSize + (buttons.length - 1) * _buttonSpacing;
    return (
      role,
      Rect.fromLTWH(
        middle - width / 2,
        above ? y - _buttonGap - _buttonSize : y + _buttonGap,
        width,
        _buttonSize,
      ),
      Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final (i, b) in buttons.indexed) ...[
            if (i > 0) const SizedBox(width: _buttonSpacing),
            b,
          ],
        ],
      ),
    );
  }

  Widget _button(
    ColorScheme colors, {
    required IconData icon,
    IconData? arrow,
    required String tooltip,
    required VoidCallback onTap,
    bool primary = false,
    bool enabled = true,
    ValueChanged<DateTime>? onDragTo,
    double? from,
  }) {
    final color = !enabled
        ? colors.outline
        : primary
        ? colors.onPrimaryContainer
        : colors.onSurface;
    final button = Material(
      color: primary && enabled
          ? colors.primaryContainer
          : colors.surfaceContainerHigh,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: enabled ? 2 : 0,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: enabled ? onTap : null,
        child: SizedBox.square(
          dimension: _buttonSize,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: arrow == null ? 24 : 20, color: color),
              if (arrow != null) Icon(arrow, size: 16, color: color),
            ],
          ),
        ),
      ),
    );
    return Tooltip(
      message: tooltip,
      child: onDragTo == null || from == null
          ? button
          : GestureDetector(
              dragStartBehavior: DragStartBehavior.down,
              // From the line it's by.
              onVerticalDragStart: (_) => _dragY = from,
              onVerticalDragUpdate: (details) {
                _dragY += details.delta.dy;
                onDragTo(_time(_dragY));
              },
              child: button,
            ),
    );
  }

  /// [role]'s cursor, at [time]: a line across the timeline -- bolder if
  /// it's [PendingEventBoxView.selected] -- with its label at its left and
  /// its handle at its right. [top]: whether it's the box's top, or its
  /// bottom; null before there's a box. Only the label and the handle take
  /// a touch: elsewhere, it goes to the timeline.
  List<Widget> _line(
    ColorScheme colors,
    CursorRole role,
    DateTime time, {
    required bool? top,
  }) {
    final y = _y(time);
    final selected = widget.selected == role;
    final thickness = selected ? 3.0 : 2.0;
    final onDragTo = role == CursorRole.anchor
        ? widget.onMoveCursor
        : widget.onMoveOther;
    final where = switch (top) {
      true => 'the top',
      false => 'the bottom',
      null => 'the cursor',
    };
    return [
      Positioned(
        left: timelineTimesWidth - 4,
        right: 0,
        top: y - thickness / 2,
        height: thickness,
        child: IgnorePointer(child: ColoredBox(color: colors.primary)),
      ),
      // Its label, on its line; what it's on into the box -- below a
      // lone cursor, or the top; above the bottom.
      Positioned(
        left: 4,
        width: _labelWidth,
        top: y - 10 - (top == false ? _marksHeight(time) : 0),
        child: _label(colors, role, time, top: top),
      ),
      Positioned(
        right: 4,
        top: y - _handleHeight / 2,
        width: _handleWidth,
        height: _handleHeight,
        child: Tooltip(
          message: 'Drag to move $where',
          child: GestureDetector(
            // From where the finger went down, so the line follows it.
            dragStartBehavior: DragStartBehavior.down,
            onVerticalDragStart: (_) {
              _select(role);
              _dragY = y;
            },
            onVerticalDragUpdate: (details) {
              _dragY += details.delta.dy;
              onDragTo(_time(_dragY));
            },
            child: Material(
              color: colors.primary,
              shape: const StadiumBorder(),
              elevation: selected ? 4 : 2,
              child: Icon(Icons.drag_handle, size: 20, color: colors.onPrimary),
            ),
          ),
        ),
      ),
    ];
  }

  /// How tall what a cursor at [time] is on is, under its time.
  double _marksHeight(DateTime time) =>
      (widget.marks?.call(time).length ?? 0) * 15.0;

  /// [role]'s label: its time, after its corner -- [top] ┌, or └ -- and
  /// scissors if it cuts an event; then, a line each, what it's on. Its
  /// time, tapped, is typed in. For the bottom, what it's on goes above
  /// its time, into the box.
  Widget _label(
    ColorScheme colors,
    CursorRole role,
    DateTime time, {
    required bool? top,
  }) {
    final marks = widget.marks?.call(time) ?? const <SnapMark>[];
    final cuts = widget.cuts?.call(time) ?? false;
    final style = TextStyle(
      color: colors.onPrimaryContainer,
      fontSize: 11,
      fontWeight: FontWeight.w500,
    );
    // "start of Lunch" over "end of Work", their words lined up.
    Widget mark(SnapMark m) => Row(
      children: [
        if (m.what != 'note')
          SizedBox(
            width: 30,
            child: Text(m.what, textAlign: TextAlign.end, style: style),
          ),
        const SizedBox(width: 3),
        Expanded(
          child: Text(
            m.what == 'note' ? 'note: ${m.name}' : 'of ${m.name}',
            maxLines: 1,
            softWrap: false,
            overflow: TextOverflow.fade,
            style: style,
          ),
        ),
      ],
    );
    final timePill = Tooltip(
      message: 'Type in its time',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          _select(role);
          widget.onEditTime(role);
        },
        child: Container(
          height: 20,
          padding: const EdgeInsets.symmetric(horizontal: 6),
          decoration: BoxDecoration(
            color: colors.primary,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (top != null) ...[
                CustomPaint(
                  size: const Size(9, 9),
                  painter: _CornerPainter(top: top, color: colors.onPrimary),
                ),
                const SizedBox(width: 4),
              ],
              Text(
                clockTime(context, time),
                style: TextStyle(
                  color: colors.onPrimary,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (cuts) ...[
                const SizedBox(width: 4),
                Semantics(
                  label: 'Cuts an event',
                  child: Icon(
                    Icons.content_cut,
                    size: 12,
                    color: colors.onPrimary,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
    final marksBox = marks.isEmpty
        ? null
        : IgnorePointer(
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 2),
              padding: const EdgeInsets.symmetric(horizontal: 4),
              decoration: BoxDecoration(
                color: colors.primaryContainer.withValues(alpha: 0.92),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final m in marks) SizedBox(height: 15, child: mark(m)),
                ],
              ),
            ),
          );
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (top == false) ?marksBox,
        timePill,
        if (top != false) ?marksBox,
      ],
    );
  }
}

/// A corner: the top's, ┌, or the bottom's, └.
class _CornerPainter extends CustomPainter {
  const _CornerPainter({required this.top, required this.color});

  final bool top;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.square;
    final path = Path();
    if (top) {
      path
        ..moveTo(size.width, 1)
        ..lineTo(1, 1)
        ..lineTo(1, size.height);
    } else {
      path
        ..moveTo(1, 0)
        ..lineTo(1, size.height - 1)
        ..lineTo(size.width, size.height - 1);
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_CornerPainter old) =>
      old.top != top || old.color != color;
}

/// The new event, shaded from [start] to [end], with its times in its
/// corner: tinged red, and slowly pulsing, where it [overwrites] events.
/// It takes no touches: they go to what's under it.
class PendingEventShadow extends StatefulWidget {
  const PendingEventShadow({
    super.key,
    required this.start,
    required this.end,
    this.overwrites = false,
    this.icon,
  });

  final DateTime start;
  final DateTime end;
  final bool overwrites;

  /// What it does with the events in its way, in its corner.
  final IconData? icon;

  @override
  State<PendingEventShadow> createState() => _PendingEventShadowState();
}

class _PendingEventShadowState extends State<PendingEventShadow>
    with SingleTickerProviderStateMixin {
  /// The red tinge's slow pulse, while [PendingEventShadow.overwrites].
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
  void didUpdateWidget(PendingEventShadow old) {
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
          Widget chip(String text) => Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: widget.overwrites ? Colors.white : colors.onPrimary,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          );
          return Container(
            // Clear of the handles at the right.
            padding: const EdgeInsets.fromLTRB(4, 4, 76, 4),
            decoration: BoxDecoration(
              color: color.withValues(alpha: alpha),
              border: Border.all(color: color, width: 1.5),
              borderRadius: BorderRadius.circular(8),
            ),
            // In its corners, solid, to read over the events under it.
            child: Stack(
              children: [
                if (widget.icon case final icon?)
                  Align(
                    alignment: Alignment.topRight,
                    child: Container(
                      padding: const EdgeInsets.all(3),
                      decoration: BoxDecoration(
                        color: color,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        icon,
                        size: 14,
                        color: widget.overwrites
                            ? Colors.white
                            : colors.onPrimary,
                      ),
                    ),
                  ),
                Align(
                  alignment: Alignment.bottomRight,
                  child: chip(
                    '${clockTime(context, widget.start)} – '
                    '${clockTime(context, widget.end)}',
                  ),
                ),
              ],
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

/// Where keeping events moved a [PendingEventBox]: a pointed arrow down the
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
