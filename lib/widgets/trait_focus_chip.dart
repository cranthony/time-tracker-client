import 'package:flutter/material.dart';

import '../models/trait.dart';
import '../models/trait_focus.dart';
import 'trait_focus_style.dart';
import 'trait_icon.dart';

/// The trait in focus, at the head of the day's summary: its icon (or,
/// without one, its name), then its rating of the day ([reading]) in the
/// color of its lean, or a dash where it rated nothing. Tapping it picks
/// another of the [traits], or none, by [onFocus]. With none in focus, a
/// quiet button to pick one.
class TraitFocusChip extends StatelessWidget {
  const TraitFocusChip({
    super.key,
    required this.traits,
    required this.focus,
    required this.reading,
    required this.onFocus,
  });

  /// The traits to pick from: the active ones, in order.
  final List<Trait> traits;
  final Trait? focus;
  final TraitReading? reading;
  final ValueChanged<String?> onFocus;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final focus = this.focus;
    final Widget label;
    final String tooltip;
    if (focus == null) {
      tooltip = 'Focus on a trait';
      label = Icon(
        Icons.center_focus_weak,
        size: 18,
        color: theme.colorScheme.onSurfaceVariant,
      );
    } else {
      final reading = this.reading;
      tooltip = reading == null
          ? '${focus.name}: nothing rated this day'
          : '${focus.name}: ${reading.score} this day';
      label = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (TraitIcon.hasIcon(focus))
            TraitIcon(focus, size: 18, color: theme.colorScheme.onSurface)
          else
            Text(focus.name, style: theme.textTheme.labelLarge),
          const SizedBox(width: 6),
          if (reading == null)
            Text(
              '–',
              style: theme.textTheme.labelLarge?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            )
          else ...[
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: traitLeanColor(reading.lean),
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 4),
            Text(
              '${reading.score}',
              style: theme.textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ],
      );
    }
    return PopupMenuButton<String>(
      tooltip: tooltip,
      position: PopupMenuPosition.under,
      onSelected: (id) => onFocus(id.isEmpty ? null : id),
      itemBuilder: (context) => [
        for (final trait in traits)
          if (trait.id case final id?)
            CheckedPopupMenuItem(
              value: id,
              checked: id == focus?.id,
              child: Row(
                children: [
                  SizedBox.square(
                    dimension: 20,
                    child: TraitIcon(trait, size: 20),
                  ),
                  const SizedBox(width: 8),
                  Flexible(child: Text(trait.name)),
                ],
              ),
            ),
        if (focus != null) ...[
          const PopupMenuDivider(),
          const PopupMenuItem(value: '', child: Text('No focus')),
        ],
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 2),
        child: label,
      ),
    );
  }
}
