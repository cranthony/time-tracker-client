import 'dart:math' as math;

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

/// A [PendingEventBox], over a [DayTimeline] for [day] at [scale]: its
/// [PendingEventBox.cursor] the anchor, where it was started from, and
/// its [PendingEventBox.other] the end. Each is a line across the
/// timeline with its time at its left, named "anchor" (with an anchor)
/// or "end", and a handle at its right that moves it alone.
///
/// Before there's an end, the anchor has on each side an arrow, stepping
/// it to its next stop that way, and a "+", making the box that way, to
/// its next stop. Once there's a box, each cursor has on its outside --
/// away from the box -- a "+", stretching the box at that end to its
/// next stop, and a "−", shrinking it; a button opening its own settings
/// ([onOpen]: its mode, what it stops at, its time); and the anchor, a
/// switch, making the end the anchor. A step that can't go -- [canStep]
/// says -- is greyed out.
///
/// The [selected] cursor -- the last touched -- is drawn bolder, and
/// where two cursors' buttons would overlap, only its are shown.
///
/// Between the cursors, the event is shaded ([PendingEventShadow]) --
/// unless [shaded] is false -- tinged red and slowly pulsing where it
/// [overwrites] events; and in it, a bigger, fainter handle that moves the
/// whole box.
class PendingEventBoxView extends StatefulWidget {
  const PendingEventBoxView({
    super.key,
    required this.day,
    required this.dayEnd,
    required this.scale,
    required this.box,
    required this.anchorMode,
    required this.endMode,
    required this.onMoveCursor,
    required this.onMoveOther,
    required this.onMoveBox,
    required this.onStep,
    required this.onOpen,
    this.canStep,
    this.onSelect,
    this.selected = CursorRole.anchor,
    this.shaded = true,
    this.overwrites = false,
    this.covers,
    this.pushed = const [],
    this.label,
    this.onSwap,
    this.swaps = 0,
  });

  final DateTime day;
  final DateTime dayEnd;
  final double scale;
  final PendingEventBox box;
  final AnchorMode anchorMode;
  final EndMode endMode;

  /// Whether the event between the cursors is shaded.
  final bool shaded;

  /// Whether the event takes time from events already there.
  final bool overwrites;

  /// What the shadow covers, if it's more than the event: the events it
  /// cancels whole.
  final (DateTime, DateTime)? covers;

  /// Where the events it pushes go: each outlined there.
  final List<PushedEvent> pushed;

  /// What it is, by the anchor, on its side away from the box: the event
  /// it's moving, if it's moving one.
  final String? label;

  /// The anchor and the end switched: the end the anchor.
  final VoidCallback? onSwap;

  /// How many times the cursors have been switched: each time, the
  /// anchor, where it is now, pings.
  final int swaps;

  /// The anchor's handle dragged to a time.
  final ValueChanged<DateTime> onMoveCursor;

  /// The end's handle dragged to a time.
  final ValueChanged<DateTime> onMoveOther;

  /// The box's handle dragged: the box moved whole, its anchor to the
  /// time given.
  final ValueChanged<DateTime> onMoveBox;

  /// A cursor's button tapped: [role]'s cursor to its next stop, [later]
  /// or earlier. Before there's an end, the anchor's "+" makes it: the
  /// end's step from the anchor.
  final void Function(CursorRole role, {required bool later}) onStep;

  /// Whether [role]'s cursor can step [later] (or earlier); all can, if
  /// null.
  final bool Function(CursorRole role, {required bool later})? canStep;

  /// A cursor's settings opened: its mode, what it stops at, its time.
  final ValueChanged<CursorRole> onOpen;

  /// A cursor touched -- dragged, or a button of it tapped: the one
  /// [selected] now.
  final ValueChanged<CursorRole>? onSelect;

  /// The cursor last touched.
  final CursorRole selected;

  @override
  State<PendingEventBoxView> createState() => _PendingEventBoxViewState();
}

class _PendingEventBoxViewState extends State<PendingEventBoxView>
    with SingleTickerProviderStateMixin {
  /// Where a drag is, down the timeline.
  double _dragY = 0;

  /// The anchor's ping, after the cursors are switched: twice, outward.
  late final _ping = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  );

  @override
  void didUpdateWidget(PendingEventBoxView old) {
    super.didUpdateWidget(old);
    if (widget.swaps != old.swaps) _ping.forward(from: 0);
  }

  @override
  void dispose() {
    _ping.dispose();
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

  /// How tall a cursor's buttons are, and how far from its line.
  static const _buttonSize = 40.0;
  static const _buttonGap = 4.0;

  void _select(CursorRole role) => widget.onSelect?.call(role);

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final box = widget.box;
    final anchorY = _y(box.cursor);
    // Whether the box goes down from the anchor, or up.
    final down = box.other?.isAfter(box.cursor) ?? true;
    return LayoutBuilder(
      builder: (context, constraints) {
        final middle = (timelineCardsLeft + constraints.maxWidth - 44) / 2;
        // Each cursor's buttons: where, and what.
        final groups = <(CursorRole, Rect, Widget)>[];
        if (box.other case final other? when box.span != null) {
          final endY = _y(other);
          // Each on its outside: the anchor's away from the end.
          groups
            ..add(
              _group(
                colors,
                CursorRole.anchor,
                anchorY,
                above: down,
                middle: middle,
              ),
            )
            ..add(
              _group(
                colors,
                CursorRole.end,
                endY,
                above: !down,
                middle: middle,
              ),
            );
        } else {
          groups
            ..add(
              _group(
                colors,
                CursorRole.anchor,
                anchorY,
                above: true,
                middle: middle,
                alone: true,
              ),
            )
            ..add(
              _group(
                colors,
                CursorRole.anchor,
                anchorY,
                above: false,
                middle: middle,
                alone: true,
              ),
            );
        }
        // Where two cursors' buttons would overlap, the selected one's.
        bool hidden((CursorRole, Rect, Widget) g) =>
            g.$1 != widget.selected &&
            groups.any((o) => o.$1 == widget.selected && o.$2.overlaps(g.$2));
        return Stack(
          clipBehavior: Clip.none,
          children: [
            if (box.span case (final start, final end) when widget.shaded)
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
                CursorRole.end,
                other,
                tooltip: 'Drag to move the end',
                onDragTo: widget.onMoveOther,
              ),
            ],
            ..._line(
              colors,
              CursorRole.anchor,
              box.cursor,
              tooltip: 'Drag to move the anchor',
              onDragTo: widget.onMoveCursor,
            ),
            for (final group in groups)
              if (!hidden(group))
                Positioned.fromRect(rect: group.$2, child: group.$3),
            // The label, by the anchor, away from the box: from the left,
            // up to its buttons.
            if (widget.label case final label?)
              Positioned(
                left: 4,
                top: down ? anchorY - 34 : anchorY + 14,
                height: 20,
                width: math.max(0, middle - _groupWidth / 2 - 10),
                child: IgnorePointer(
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: _pill(colors, label),
                  ),
                ),
              ),
            // The anchor pinging, twice, where it is after a switch.
            Positioned(
              left: timelineTimesWidth - 4,
              right: 0,
              top: anchorY - 30,
              height: 60,
              child: IgnorePointer(
                child: AnimatedBuilder(
                  animation: _ping,
                  builder: (context, _) {
                    if (!_ping.isAnimating) return const SizedBox.shrink();
                    final phase = (_ping.value * 2) % 1;
                    return Center(
                      child: Container(
                        height: 4 + 52 * phase,
                        decoration: BoxDecoration(
                          color: colors.primary.withValues(
                            alpha: 0.35 * (1 - phase),
                          ),
                          borderRadius: BorderRadius.circular(30),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  /// How wide a cursor's buttons are, side by side, at most.
  static const _groupWidth = 4 * _buttonSize + 3 * 6.0;

  Widget _pill(ColorScheme colors, String text, {Widget? leading}) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    decoration: BoxDecoration(
      color: colors.primary,
      borderRadius: BorderRadius.circular(10),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ?leading,
        Flexible(
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
        ),
      ],
    ),
  );

  /// [role]'s buttons, at [y], [above] its line or below -- the way that's
  /// out of the box -- centered on [middle]: before there's a box
  /// ([alone]), the anchor's arrow and "+" that way; else its "−", "+",
  /// settings and, for the anchor, the switch.
  (CursorRole, Rect, Widget) _group(
    ColorScheme colors,
    CursorRole role,
    double y, {
    required bool above,
    required double middle,
    bool alone = false,
  }) {
    // Outward: earlier above the line, later below it.
    final later = !above;
    final buttons = <Widget>[
      if (alone) ...[
        _button(
          colors,
          icon: later ? Icons.arrow_downward : Icons.arrow_upward,
          tooltip: later
              ? 'Move the anchor to its next stop, later'
              : 'Move the anchor to its next stop, earlier',
          enabled: widget.canStep?.call(role, later: later) ?? true,
          onTap: () {
            _select(role);
            widget.onStep(role, later: later);
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
          // Dragged, the end made where it goes.
          onDragTo: (to) {
            _select(CursorRole.end);
            widget.onMoveOther(to);
          },
          from: y,
        ),
        // The anchor's settings above, and the end's -- for the box it
        // makes -- below.
        _settings(colors, later ? CursorRole.end : role),
      ] else ...[
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
        _settings(colors, role),
        if (role == CursorRole.anchor && widget.onSwap != null)
          _swapButton(colors),
      ],
    ];
    final width = buttons.length * _buttonSize + (buttons.length - 1) * 6.0;
    final rect = Rect.fromLTWH(
      middle - width / 2,
      above ? y - _buttonGap - _buttonSize : y + _buttonGap,
      width,
      _buttonSize,
    );
    return (
      role,
      rect,
      Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final (i, b) in buttons.indexed) ...[
            if (i > 0) const SizedBox(width: 6),
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
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      elevation: enabled ? 2 : 0,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: enabled ? onTap : null,
        child: SizedBox.square(
          dimension: _buttonSize,
          child: arrow == null
              ? Icon(icon, size: 22, color: color)
              : Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(icon, size: 18, color: color),
                    Icon(arrow, size: 14, color: color),
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

  /// [role]'s settings: its mode's icon, opening them.
  Widget _settings(ColorScheme colors, CursorRole role) {
    final (icon, label, changes) = switch (role) {
      CursorRole.anchor => (
        widget.anchorMode.icon,
        widget.anchorMode.label,
        widget.anchorMode.changes,
      ),
      _ => (
        widget.endMode.icon,
        widget.endMode.label,
        widget.endMode != EndMode.keep,
      ),
    };
    final name = role == CursorRole.anchor ? 'Anchor' : 'End';
    return Tooltip(
      message: '$name: $label. Tap for its settings',
      child: Material(
        color: changes
            ? Color.lerp(colors.errorContainer, colors.surface, 0.2)
            : colors.surfaceContainerHigh,
        shape: const CircleBorder(),
        elevation: 2,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: () {
            _select(role);
            widget.onOpen(role);
          },
          child: SizedBox.square(
            dimension: _buttonSize,
            child: Icon(icon, size: 20, color: colors.onSurface),
          ),
        ),
      ),
    );
  }

  /// The switch: the end the anchor, and the anchor the end -- an anchor
  /// on it, to say so.
  Widget _swapButton(ColorScheme colors) => Tooltip(
    message: 'Switch the anchor to the other end',
    child: Material(
      color: colors.surfaceContainerHigh,
      shape: const CircleBorder(),
      elevation: 2,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: () {
          _select(CursorRole.anchor);
          widget.onSwap!();
        },
        child: SizedBox.square(
          dimension: _buttonSize,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Icon(Icons.swap_vert, size: 22, color: colors.onSurface),
              Positioned(
                right: 4,
                bottom: 4,
                child: Icon(Icons.anchor, size: 12, color: colors.primary),
              ),
            ],
          ),
        ),
      ),
    ),
  );

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
            onVerticalDragStart: (_) {
              _select(CursorRole.anchor);
              _dragY = _y(cursor);
            },
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

  /// [role]'s cursor: a line across the timeline at [time] -- bolder if
  /// it's [PendingEventBoxView.selected] -- with its time and name at its
  /// left and, at its right, a handle that's dragged to [onDragTo] a time.
  /// Only the handle takes a touch: a tap elsewhere goes to the timeline.
  List<Widget> _line(
    ColorScheme colors,
    CursorRole role,
    DateTime time, {
    required String tooltip,
    required ValueChanged<DateTime> onDragTo,
  }) {
    final y = _y(time);
    final selected = widget.selected == role;
    final thickness = selected ? 3.0 : 2.0;
    final anchor = role == CursorRole.anchor;
    return [
      Positioned(
        left: timelineTimesWidth - 4,
        right: 0,
        top: y - thickness / 2,
        height: thickness,
        child: IgnorePointer(child: ColoredBox(color: colors.primary)),
      ),
      Positioned(
        left: 4,
        top: y - 10,
        height: 20,
        child: IgnorePointer(
          child: Semantics(
            label: anchor ? 'Anchor' : 'End',
            child: _pill(
              colors,
              '${clockTime(context, time)} ${anchor ? 'anchor' : 'end'}',
              leading: anchor
                  ? Padding(
                      padding: const EdgeInsets.only(right: 2),
                      child: Icon(
                        Icons.anchor,
                        size: 12,
                        color: colors.onPrimary,
                      ),
                    )
                  : null,
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
              child: Icon(
                anchor ? Icons.anchor : Icons.drag_handle,
                size: 18,
                color: colors.onPrimary,
              ),
            ),
          ),
        ),
      ),
    ];
  }
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
  });

  final DateTime start;
  final DateTime end;
  final bool overwrites;

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
            padding: const EdgeInsets.fromLTRB(4, 4, 36, 4),
            decoration: BoxDecoration(
              color: color.withValues(alpha: alpha),
              border: Border.all(color: color, width: 1.5),
              borderRadius: BorderRadius.circular(8),
            ),
            // In its corner, solid, to read over the events under it.
            alignment: Alignment.bottomRight,
            child: chip(
              '${clockTime(context, widget.start)} – '
              '${clockTime(context, widget.end)}',
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
