import 'package:flutter/material.dart';

import '../models/plan_action.dart';
import 'color_picker.dart';
import 'plow_icon.dart';

/// [action]'s icon in a list: a folder for a group, a walking person for
/// an action that's a way to commute, a plow for any other action, in its
/// color -- filled where the color is set on it, outlined where
/// it's inherited (from a group, or its priority). One that isn't active
/// has no color of its own on the calendar: it's grey.
class ActionIcon extends StatelessWidget {
  const ActionIcon(this.action, {super.key, this.size = 24});

  final PlanAction action;
  final double size;

  @override
  Widget build(BuildContext context) {
    final own = parseColor(action.backgroundColor);
    final color =
        (action.active ? own ?? parseColor(action.effectiveColor) : null) ??
        Theme.of(context).colorScheme.outline;
    final filled = own != null;
    if (action.isGroup) {
      return Icon(
        filled ? Icons.folder : Icons.folder_outlined,
        color: color,
        size: size,
      );
    }
    if (action.commute) {
      return Icon(
        filled ? Icons.directions_walk : Icons.directions_walk_outlined,
        color: color,
        size: size,
      );
    }
    return PlowIcon(color: color, size: size, filled: filled);
  }
}
