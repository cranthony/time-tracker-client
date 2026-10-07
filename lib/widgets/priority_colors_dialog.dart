import 'package:flutter/material.dart';

import 'error_sheet.dart';
import 'color_picker.dart';

/// Each priority's color, as [priorityPalette] has them, any of which can
/// be changed: picking one calls [onSave] with its priority and color
/// ("#rrggbb"), and shows the new color once that's done.
class PriorityColorsDialog extends StatefulWidget {
  const PriorityColorsDialog({super.key, required this.onSave});

  final Future<void> Function(int priority, String color) onSave;

  @override
  State<PriorityColorsDialog> createState() => _PriorityColorsDialogState();
}

class _PriorityColorsDialogState extends State<PriorityColorsDialog> {
  /// The priority being saved, if one is.
  int? _saving;

  Future<void> _change(int priority) async {
    var picked = priorityColor(priority);
    final color = await showDialog<Color>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Priority $priority color'),
        content: SingleChildScrollView(
          child: StatefulBuilder(
            builder: (context, setPicked) => ColorPicker(
              color: picked,
              // A priority always has a color: "No color" keeps it.
              onChanged: (color) {
                if (color != null) setPicked(() => picked = color);
              },
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, picked),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (color == null ||
        colorToHex(color) == colorToHex(priorityColor(priority))) {
      return;
    }
    if (!mounted) return;
    setState(() => _saving = priority);
    try {
      await runOrShowError(
        context,
        title: "Couldn't save the color",
        action: () => widget.onSave(priority, colorToHex(color)),
      );
    } finally {
      if (mounted) setState(() => _saving = null);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Priority colors'),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          "Events without an action's color, and actions and groups "
          'without a color of their own, take their priority’s.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 8),
        ValueListenableBuilder(
          valueListenable: priorityPalette,
          builder: (context, _, _) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final p in priorities)
                ListTile(
                  key: Key('priority-color-$p'),
                  contentPadding: EdgeInsets.zero,
                  leading: ColorDot(color: priorityColor(p), size: 24),
                  title: Text(
                    p == defaultPriority ? 'P$p (and no priority)' : 'P$p',
                  ),
                  subtitle: Text(colorToHex(priorityColor(p))),
                  trailing: _saving == p
                      ? const SizedBox.square(
                          dimension: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.edit_outlined),
                  onTap: _saving == null ? () => _change(p) : null,
                ),
            ],
          ),
        ),
      ],
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Done'),
      ),
    ],
  );
}
