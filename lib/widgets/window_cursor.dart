import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import 'day_timeline.dart';
import 'pending_event_box.dart';

/// The end of a compaction proposal's window, being extended, over a
/// [DayTimeline] for [day] at [scale]: its anchor, fixed, where Claude's
/// revision ran to ([anchor]); and its end ([end]), a line across with its
/// time and a handle that drags it ([onMove]). Below the end, a "−" and a
/// "+" stepping it to its next stop ([onStep], greyed out where it can't:
/// [canStep]); its settings ([onOpen]: what it stops at, its time); and
/// "Extend", saving it ([onDone]), or "×", leaving it ([onCancel]).
class WindowCursorView extends StatefulWidget {
  const WindowCursorView({
    super.key,
    required this.day,
    required this.dayEnd,
    required this.scale,
    required this.anchor,
    required this.end,
    required this.onMove,
    required this.onStep,
    required this.canStep,
    required this.onOpen,
    required this.onDone,
    required this.onCancel,
  });

  final DateTime day;
  final DateTime dayEnd;
  final double scale;
  final DateTime anchor;
  final DateTime end;
  final ValueChanged<DateTime> onMove;
  final void Function({required bool later}) onStep;
  final bool Function({required bool later}) canStep;
  final VoidCallback onOpen;

  /// Saves it; null while there's nothing to extend.
  final VoidCallback? onDone;
  final VoidCallback onCancel;

  @override
  State<WindowCursorView> createState() => _WindowCursorViewState();
}

class _WindowCursorViewState extends State<WindowCursorView> {
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

  static const _size = 40.0;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final anchorY = _y(widget.anchor);
    final endY = _y(widget.end);
    Widget pill(String text, Color color, Color on, {IconData? icon}) =>
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 12, color: on),
                const SizedBox(width: 2),
              ],
              Text(
                text,
                style: TextStyle(
                  color: on,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        );
    Widget button({
      required IconData icon,
      IconData? arrow,
      required String tooltip,
      required VoidCallback? onTap,
      bool primary = false,
    }) {
      final enabled = onTap != null;
      final color = !enabled
          ? colors.outline
          : primary
          ? colors.onPrimaryContainer
          : colors.onSurface;
      return Tooltip(
        message: tooltip,
        child: Material(
          color: primary && enabled
              ? colors.primaryContainer
              : colors.surfaceContainerHigh,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          elevation: enabled ? 2 : 0,
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: onTap,
            child: SizedBox.square(
              dimension: _size,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, size: arrow == null ? 22 : 18, color: color),
                  if (arrow != null) Icon(arrow, size: 14, color: color),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final middle = (timelineCardsLeft + constraints.maxWidth - 44) / 2;
        return Stack(
          clipBehavior: Clip.none,
          children: [
            // The anchor: fixed, where Claude's revision ran to.
            Positioned(
              left: timelineTimesWidth - 4,
              right: 0,
              top: anchorY - 0.75,
              height: 1.5,
              child: IgnorePointer(child: ColoredBox(color: colors.secondary)),
            ),
            Positioned(
              left: 4,
              top: anchorY - 10,
              height: 20,
              child: IgnorePointer(
                child: Semantics(
                  label: "Anchor, where Claude's revision ends",
                  child: pill(
                    '${clockTime(context, widget.anchor)} anchor',
                    colors.secondary,
                    colors.onSecondary,
                    icon: Icons.anchor,
                  ),
                ),
              ),
            ),
            // The end.
            Positioned(
              left: timelineTimesWidth - 4,
              right: 0,
              top: endY - 1.5,
              height: 3,
              child: IgnorePointer(child: ColoredBox(color: colors.primary)),
            ),
            Positioned(
              left: 4,
              top: endY - 10,
              height: 20,
              child: IgnorePointer(
                child: pill(
                  '${clockTime(context, widget.end)} end',
                  colors.primary,
                  colors.onPrimary,
                ),
              ),
            ),
            Positioned(
              right: 4,
              top: endY - 16,
              width: 32,
              height: 32,
              child: Tooltip(
                message: 'Drag to move the end of what happened',
                child: GestureDetector(
                  dragStartBehavior: DragStartBehavior.down,
                  onVerticalDragStart: (_) => _dragY = endY,
                  onVerticalDragUpdate: (details) {
                    _dragY += details.delta.dy;
                    widget.onMove(_time(_dragY));
                  },
                  child: Material(
                    color: colors.primary,
                    shape: const StadiumBorder(),
                    elevation: 4,
                    child: Icon(
                      Icons.drag_handle,
                      size: 18,
                      color: colors.onPrimary,
                    ),
                  ),
                ),
              ),
            ),
            // Its buttons, below it: out of what happened.
            Positioned(
              left: 0,
              right: 0,
              top: endY + 4,
              height: _size,
              child: Align(
                alignment: Alignment(
                  (middle / constraints.maxWidth) * 2 - 1,
                  0,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    button(
                      icon: Icons.remove,
                      arrow: Icons.arrow_upward,
                      tooltip: 'Shrink the extension',
                      onTap: widget.canStep(later: false)
                          ? () => widget.onStep(later: false)
                          : null,
                    ),
                    const SizedBox(width: 6),
                    button(
                      icon: Icons.add,
                      arrow: Icons.arrow_downward,
                      primary: true,
                      tooltip: 'Extend it later',
                      onTap: widget.canStep(later: true)
                          ? () => widget.onStep(later: true)
                          : null,
                    ),
                    const SizedBox(width: 6),
                    button(
                      icon: Icons.tune,
                      tooltip: 'The end of what happened: its settings',
                      onTap: widget.onOpen,
                    ),
                    const SizedBox(width: 6),
                    button(
                      icon: Icons.close,
                      tooltip: "Don't extend it",
                      onTap: widget.onCancel,
                    ),
                    const SizedBox(width: 6),
                    Tooltip(
                      message: 'Extend what happened to here',
                      child: FilledButton.icon(
                        onPressed: widget.onDone,
                        icon: const Icon(Icons.check),
                        label: const Text('Extend'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
