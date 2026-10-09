import 'package:flutter/material.dart';

import '../services/app_settings.dart';
import '../widgets/cursor_snap.dart';

/// The app's [settings], to change: the grid the timeline's cursors snap
/// to, every so many minutes, or none, and what else they stop at.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key, required this.settings});

  final AppSettings settings;

  /// [grid] as the page names it.
  static String gridName(Duration? grid) => switch (grid?.inMinutes) {
    null => 'None',
    60 => 'Every hour',
    final m => 'Every $m minutes',
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListenableBuilder(
        listenable: settings,
        builder: (context, _) => ListView(
          padding: const EdgeInsets.symmetric(vertical: 8),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: Text('Snap to grid', style: theme.textTheme.titleMedium),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(
                "On the Events page, a cursor stops on the grid's lines as "
                'it moves, and its buttons step it to the next. With none, '
                'it stops at any minute.',
                style: theme.textTheme.bodySmall,
              ),
            ),
            RadioGroup<Duration?>(
              groupValue: settings.grid,
              onChanged: settings.setGrid,
              child: Column(
                children: [
                  for (final grid in AppSettings.grids)
                    RadioListTile<Duration?>(
                      value: grid,
                      title: Text(gridName(grid)),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
              child: Text('Also stop at', style: theme.textTheme.titleMedium),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(
                'Every cursor stops at these too, between the lines, and a '
                'dragged one snaps to them as it comes near.',
                style: theme.textTheme.bodySmall,
              ),
            ),
            for (final snap in SnapTo.values)
              CheckboxListTile(
                value: settings.snap.contains(snap),
                title: Text(snap.label),
                onChanged: (on) => settings.setSnap({
                  for (final s in SnapTo.values)
                    if (s == snap ? on ?? false : settings.snap.contains(s)) s,
                }),
              ),
          ],
        ),
      ),
    );
  }
}
