import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import 'day_timeline.dart';
import 'pending_event_box.dart';

/// Where a new note goes, being placed, over a [DayTimeline] for [day] at
/// [scale]: a line across at [at], with its time and a handle that drags
/// it ([onMove]). Below it, a "−" and a "+" stepping it to its next stop
/// ([onStep], greyed out where it can't: [canStep]). The page's ✓ opens
/// the New note sheet at its time.
class NoteCursorView extends StatefulWidget {
  const NoteCursorView({
    super.key,
    required this.day,
    required this.dayEnd,
    required this.scale,
    required this.at,
    required this.onMove,
    required this.onStep,
    required this.canStep,
  });

  final DateTime day;
  final DateTime dayEnd;
  final double scale;
  final DateTime at;
  final ValueChanged<DateTime> onMove;
  final void Function({required bool later}) onStep;
  final bool Function({required bool later}) canStep;

  @override
  State<NoteCursorView> createState() => _NoteCursorViewState();
}

class _NoteCursorViewState extends State<NoteCursorView> {
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
    final y = _y(widget.at);
    Widget button({
      required IconData icon,
      required IconData arrow,
      required String tooltip,
      required VoidCallback? onTap,
    }) {
      final enabled = onTap != null;
      final color = enabled ? colors.onSurface : colors.outline;
      return Tooltip(
        message: tooltip,
        child: Material(
          color: colors.surfaceContainerHigh,
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
                  Icon(icon, size: 18, color: color),
                  Icon(arrow, size: 14, color: color),
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
            Positioned(
              left: timelineTimesWidth - 4,
              right: 0,
              top: y - 1.5,
              height: 3,
              child: IgnorePointer(child: ColoredBox(color: colors.tertiary)),
            ),
            Positioned(
              left: 4,
              top: y - 10,
              height: 20,
              child: IgnorePointer(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: colors.tertiary,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.edit_note, size: 12, color: colors.onTertiary),
                      const SizedBox(width: 2),
                      Text(
                        clockTime(context, widget.at),
                        style: TextStyle(
                          color: colors.onTertiary,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
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
                message: 'Drag to move where the note goes',
                child: GestureDetector(
                  dragStartBehavior: DragStartBehavior.down,
                  onVerticalDragStart: (_) => _dragY = y,
                  onVerticalDragUpdate: (details) {
                    _dragY += details.delta.dy;
                    widget.onMove(_time(_dragY));
                  },
                  child: Material(
                    color: colors.tertiary,
                    shape: const StadiumBorder(),
                    elevation: 4,
                    child: Icon(
                      Icons.drag_handle,
                      size: 18,
                      color: colors.onTertiary,
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              top: y + 4,
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
                      tooltip: 'Earlier',
                      onTap: widget.canStep(later: false)
                          ? () => widget.onStep(later: false)
                          : null,
                    ),
                    const SizedBox(width: 6),
                    button(
                      icon: Icons.add,
                      arrow: Icons.arrow_downward,
                      tooltip: 'Later',
                      onTap: widget.canStep(later: true)
                          ? () => widget.onStep(later: true)
                          : null,
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
