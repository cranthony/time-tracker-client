import 'package:flutter/material.dart';

/// One of the modes the Events page can be in, on its [ModeStack]: its
/// [icon], and its [label], saying what it's for.
@immutable
class EventsMode {
  const EventsMode(this.icon, this.label);

  /// Placing a cursor: where a new event starts, or where to split one.
  static const placeCursor = EventsMode(Icons.my_location, 'Place a cursor');

  /// Making a new event: its box.
  static const create = EventsMode(Icons.add_box_outlined, 'Create an event');

  /// Changing an event's times: its box.
  static const edit = EventsMode(Icons.edit_calendar_outlined, 'Edit an event');

  /// Extending the open proposal's compaction window.
  static const extend = EventsMode(
    Icons.expand,
    'Extend the compaction window',
  );

  final IconData icon;
  final String label;

  @override
  bool operator ==(Object other) =>
      other is EventsMode && other.icon == icon && other.label == label;

  @override
  int get hashCode => Object.hash(icon, label);
}

/// The modes the Events page is in, [modes] from the first entered to the
/// last -- the top -- as a row of icons, the top on the left, drawn
/// strongest, and its label above the row. Nothing, with none. Back, or ✕,
/// leaves the top one.
class ModeStack extends StatelessWidget {
  const ModeStack({super.key, required this.modes});

  final List<EventsMode> modes;

  @override
  Widget build(BuildContext context) {
    if (modes.isEmpty) return const SizedBox.shrink();
    final colors = Theme.of(context).colorScheme;
    final top = modes.last;
    return Semantics(
      container: true,
      label: 'Mode: ${top.label}',
      child: ExcludeSemantics(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: colors.inverseSurface,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                top.label,
                style: TextStyle(
                  color: colors.onInverseSurface,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(height: 6),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // The top first, on the left.
                for (final (i, mode) in modes.reversed.indexed) ...[
                  if (i > 0) const SizedBox(width: 6),
                  Container(
                    width: i == 0 ? 40 : 32,
                    height: i == 0 ? 40 : 32,
                    decoration: BoxDecoration(
                      color: i == 0
                          ? colors.secondaryContainer
                          : colors.surfaceContainerHigh,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: i == 0
                            ? colors.secondary
                            : colors.outlineVariant,
                        width: i == 0 ? 2 : 1,
                      ),
                    ),
                    child: Icon(
                      mode.icon,
                      size: i == 0 ? 22 : 18,
                      color: i == 0
                          ? colors.onSecondaryContainer
                          : colors.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}
