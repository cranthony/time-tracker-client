import 'package:flutter/material.dart';

import 'cursor_modes.dart';
import 'cursor_snap.dart';

/// A cursor's settings, in a sheet: its [title] ("Anchor", "End"); what
/// it does with events -- an anchor's [anchorMode], or an end's
/// [endMode], if it has one; what it stops at besides the grid ([snap]);
/// and its time, to type ([onEditTime]). Each change is made at once.
Future<void> showCursorSheet(
  BuildContext context, {
  required String title,
  AnchorMode? anchorMode,
  EndMode? endMode,
  Set<SnapTo>? snap,
  ValueChanged<AnchorMode>? onAnchorMode,
  ValueChanged<EndMode>? onEndMode,
  ValueChanged<Set<SnapTo>>? onSnap,
  VoidCallback? onEditTime,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  builder: (context) {
    var anchor = anchorMode;
    var end = endMode;
    var stops = {...?snap};
    return StatefulBuilder(
      builder: (context, setState) {
        final theme = Theme.of(context);
        Widget heading(String text) => Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Text(text, style: theme.textTheme.titleSmall),
        );
        Widget mode<T>(
          T value,
          T picked,
          String label,
          String description,
          IconData icon,
        ) => RadioListTile<T>(
          value: value,
          secondary: Icon(icon),
          title: Text(label),
          subtitle: value == picked ? Text(description) : null,
        );
        return SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.only(bottom: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
                  child: Text(title, style: theme.textTheme.titleLarge),
                ),
                if (anchor case final picked?) ...[
                  heading('The event it is inside of'),
                  RadioGroup<AnchorMode>(
                    groupValue: picked,
                    onChanged: (m) {
                      if (m == null) return;
                      setState(() => anchor = m);
                      onAnchorMode?.call(m);
                    },
                    child: Column(
                      children: [
                        for (final m in AnchorMode.values)
                          mode(m, picked, m.label, m.description, m.icon),
                      ],
                    ),
                  ),
                ],
                if (end case final picked?) ...[
                  heading('What it does with the events in its way'),
                  RadioGroup<EndMode>(
                    groupValue: picked,
                    onChanged: (m) {
                      if (m == null) return;
                      setState(() => end = m);
                      onEndMode?.call(m);
                    },
                    child: Column(
                      children: [
                        for (final m in EndMode.values)
                          mode(m, picked, m.label, m.description, m.icon),
                      ],
                    ),
                  ),
                ],
                if (snap != null) heading('Stops at'),
                if (snap != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
                    child: Text(
                      "The grid's lines, set in Settings, and:",
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                for (final s in SnapTo.values)
                  if (snap != null)
                    CheckboxListTile(
                      value: stops.contains(s),
                      title: Text(s.label),
                      onChanged: (on) {
                        setState(
                          () => stops = {
                            for (final t in SnapTo.values)
                              if (t == s ? on ?? false : stops.contains(t)) t,
                          },
                        );
                        onSnap?.call(stops);
                      },
                    ),
                if (onEditTime != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
                    child: Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: TextButton.icon(
                        onPressed: () {
                          Navigator.of(context).pop();
                          onEditTime();
                        },
                        icon: const Icon(Icons.schedule),
                        label: const Text('Edit its time'),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  },
);

/// Asks for a cursor's time, starting at [initial]: its date, from
/// [first] to [last], and its time of day. Null if called off.
Future<DateTime?> showEditTimeDialog(
  BuildContext context, {
  required String title,
  required DateTime initial,
  required DateTime first,
  required DateTime last,
}) => showDialog<DateTime>(
  context: context,
  builder: (context) {
    var date = DateUtils.dateOnly(initial);
    var time = TimeOfDay.fromDateTime(initial);
    return StatefulBuilder(
      builder: (context, setState) {
        final strings = MaterialLocalizations.of(context);
        return AlertDialog(
          title: Text(title),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.event),
                title: Text(strings.formatMediumDate(date)),
                onTap: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: date,
                    firstDate: DateUtils.dateOnly(first),
                    lastDate: DateUtils.dateOnly(last),
                  );
                  if (picked != null) setState(() => date = picked);
                },
              ),
              ListTile(
                leading: const Icon(Icons.schedule),
                title: Text(strings.formatTimeOfDay(time)),
                onTap: () async {
                  final picked = await showTimePicker(
                    context: context,
                    initialTime: time,
                  );
                  if (picked != null) setState(() => time = picked);
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                var at = DateTime(
                  date.year,
                  date.month,
                  date.day,
                  time.hour,
                  time.minute,
                );
                if (at.isBefore(first)) at = first;
                if (at.isAfter(last)) at = last;
                Navigator.of(context).pop(at);
              },
              child: const Text('Done'),
            ),
          ],
        );
      },
    );
  },
);
