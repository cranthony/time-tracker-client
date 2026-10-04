import 'package:flutter/material.dart';

import 'color_picker.dart';

/// A priority as a small chip, "P2", in the priority's color, as the Events
/// page shows them: filled when it's [own], outlined when it's inherited
/// (from goals or an ancestor). With no [priority], [label] in an outline
/// of the theme's color, or nothing if there's no [label] either.
class PriorityChip extends StatelessWidget {
  const PriorityChip({
    super.key,
    required this.priority,
    required this.own,
    this.label,
    this.large = false,
  });

  final int? priority;
  final bool own;

  /// Said in place of "P2", e.g. "No priority".
  final String? label;

  /// For a dialog's header, rather than a list.
  final bool large;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text = label ?? (priority == null ? null : 'P$priority');
    if (text == null) return const SizedBox.shrink();
    final color = priority == null
        ? theme.colorScheme.outline
        : priorityColor(priority);
    final filled = own && priority != null;
    final style = large
        ? theme.textTheme.labelLarge
        : theme.textTheme.labelSmall;
    return Container(
      padding: EdgeInsets.symmetric(horizontal: large ? 8 : 5, vertical: 1),
      decoration: BoxDecoration(
        color: filled ? color : null,
        border: Border.all(color: color, width: 1.5),
        borderRadius: BorderRadius.circular(large ? 6 : 4),
      ),
      child: Text(
        text,
        style: style?.copyWith(
          color: filled ? Colors.black87 : theme.colorScheme.onSurface,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
