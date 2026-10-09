import 'package:flutter/material.dart';

import '../models/plan_action.dart';
import '../services/app_settings.dart';
import '../services/keep_rules.dart';
import '../services/plan_memory.dart';
import '../widgets/actions_picker.dart';
import '../widgets/habit_dialog.dart';
import '../widgets/cursor_snap.dart';

/// The app's [settings], to change: the grid the timeline's cursors snap
/// to, every so many minutes, or none, and what else they stop at; and the
/// rules for what a new or moved event's Keep list starts with.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key, required this.settings});

  final AppSettings settings;

  /// [grid] as the page names it.
  static String gridName(Duration? grid) => switch (grid?.inMinutes) {
    null => 'None',
    60 => 'Every hour',
    final m => 'Every $m minutes',
  };

  /// The rules for a new or moved event's Keep list, each removable, and
  /// a way to add another.
  List<Widget> _keepRules(BuildContext context, ThemeData theme) {
    final actions = <String, PlanAction>{
      for (final a
          in PlanMemoryScope.of(context)?.actions?.actions ??
              const <PlanAction>[])
        ?a.id: a,
    };
    final rules = settings.keepRules;
    return [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
        child: Text('Keep by default', style: theme.textTheme.titleMedium),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
        child: Text(
          "As a new or moved event's box starts, these go in its Keep "
          "list: the box doesn't take their time. \"Previous\" and "
          '"next" are before and after the cursor -- or the event moved -- '
          'but never the event it starts in.',
          style: theme.textTheme.bodySmall,
        ),
      ),
      if (rules.isEmpty)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Text('None', style: TextStyle(color: theme.hintColor)),
        ),
      for (final (i, rule) in rules.indexed)
        ListTile(
          leading: const Icon(Icons.lock_outline),
          title: Text(rule.describe(actions)),
          trailing: IconButton(
            tooltip: 'Remove “${rule.describe(actions)}”',
            icon: const Icon(Icons.delete_outline),
            onPressed: () => settings.setKeepRules([
              for (final (j, r) in rules.indexed)
                if (j != i) r,
            ]),
          ),
        ),
      Align(
        alignment: AlignmentDirectional.centerStart,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: PopupMenuButton<KeepRuleKind>(
            tooltip: 'Add a rule',
            onSelected: (kind) => _addRule(context, kind, actions),
            itemBuilder: (_) => [
              for (final kind in KeepRuleKind.values)
                PopupMenuItem(
                  value: kind,
                  child: Text(
                    kind.hasAction ? '${kind.label} an action…' : kind.label,
                  ),
                ),
            ],
            child: const Padding(
              padding: EdgeInsets.all(8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [Icon(Icons.add), SizedBox(width: 8), Text('Rule')],
              ),
            ),
          ),
        ),
      ),
    ];
  }

  /// Adds a rule of [kind]: for one with an action, picked from [actions]
  /// -- a group, or one of its own.
  Future<void> _addRule(
    BuildContext context,
    KeepRuleKind kind,
    Map<String, PlanAction> actions,
  ) async {
    String? actionId;
    if (kind.hasAction) {
      if (actions.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              "The actions aren't loaded yet: open Plan, then try again.",
            ),
          ),
        );
        return;
      }
      final picked = await showActionPicker(
        context,
        actions: [...actions.values],
        value: null,
        title: '${kind.label}…',
        marker: (a) => actionDot(a, size: 12),
      );
      actionId = picked?.id;
      if (actionId == null) return;
    }
    final rule = KeepRule(kind, actionId: actionId);
    if (settings.keepRules.contains(rule)) return;
    await settings.setKeepRules([...settings.keepRules, rule]);
  }

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
            ..._keepRules(context, theme),
          ],
        ),
      ),
    );
  }
}
