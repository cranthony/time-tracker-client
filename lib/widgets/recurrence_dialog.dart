import 'package:flutter/material.dart';

import '../models/goal.dart';
import '../models/recurrence.dart';
import 'properties_dialog.dart';

/// Which events of a series a change applies to.
enum SeriesScope {
  /// Every event in the series.
  all,

  /// The event it was opened from, and the ones after it.
  following,
}

/// Shows every property of the recurring series [recurrence], as the server
/// sent it, under its summary: its schedule in words, how it repeats, and the
/// properties its events share.
///
/// Tapping a value opens it for editing; "Save" sends every change with
/// [save]. Opened from one of its events ([fromEventId]), saving first asks
/// whether the change is for all its events or that one and the ones after
/// it. Returns what [save] returned, or null if nothing was saved.
Future<List<Recurrence>?> showRecurrenceDialog(
  BuildContext context,
  Recurrence recurrence, {
  required Future<List<Recurrence>> Function(
    Map<String, Object?> changes,
    SeriesScope scope,
  )
  save,
  String? fromEventId,
  Future<List<Goal>> Function()? goals,
}) {
  final typed = recurrence.toJson();
  // Asked as the save starts, then saved for.
  var scope = SeriesScope.all;
  return showPropertiesDialog<List<Recurrence>>(
    context,
    title: (values) => switch (values['summary']) {
      final String summary when summary.isNotEmpty => summary,
      _ => '(no summary)',
    },
    // The schedule first: it's what makes this a series.
    properties: {
      for (final key in ['schedule', 'repeat', 'summary', 'start', 'end'])
        key: typed[key],
      ...recurrence.properties,
      ...typed,
    },
    kinds: _kinds,
    // Every event has one; the rest can be cleared (see clearableFields).
    required: const {'summary'},
    inferred: {
      if (recurrence.properties['actions_from_label'] == true)
        'action_ids': 'from its label',
    },
    hints: const {
      'start': "When the series' first event starts.",
      'end': "When the series' first event ends.",
    },
    validate: (values) {
      final start = DateTime.parse(values['start'] as String);
      final end = DateTime.parse(values['end'] as String);
      return end.isAfter(start) ? null : 'The end has to be after the start.';
    },
    goals: goals,
    confirmSave: fromEventId == null
        ? null
        : (changes) async {
            final picked = await askSeriesScope(context, changes);
            if (picked != null) scope = picked;
            return picked != null;
          },
    save: (changes) => save(changes, scope),
    signInHint: 'Sign in again from the Events page, then try again.',
  );
}

/// Asks whether [changes] to a series are for every event in it, or the
/// one it was opened from and those after it; null to go back.
///
/// It first says what saving may do to events changed on their own. The
/// server found (time-tracking-google-calendar-mcp#116) that any edit to
/// a series resets every one of its events' properties but their times to
/// the series', even ones the edit leaves out, and that an edit to its
/// times moves every event onto them. That's Google Calendar's behavior,
/// not anything it documents, so this says "may".
Future<SeriesScope?> askSeriesScope(
  BuildContext context,
  Map<String, Object?> changes,
) => showDialog<SeriesScope>(
  context: context,
  builder: (context) {
    final theme = Theme.of(context);
    final moves = changes.containsKey('start') || changes.containsKey('end');
    return SimpleDialog(
      title: const Text('Change which events?'),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
          child: Text(
            moves
                ? "Saving may set every property of each of these events "
                      "to the series', and move each one to the series' new "
                      'time, even events you changed or moved on their own.'
                : "Saving may set every property of each of these events "
                      "to the series', except its time, even events you "
                      'changed on their own.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        SimpleDialogOption(
          onPressed: () => Navigator.of(context).pop(SeriesScope.all),
          child: const ListTile(
            leading: Icon(Icons.event_repeat),
            title: Text('All events'),
            subtitle: Text('Every event in the series.'),
          ),
        ),
        SimpleDialogOption(
          onPressed: () => Navigator.of(context).pop(SeriesScope.following),
          child: const ListTile(
            leading: Icon(Icons.east),
            title: Text('This and following events'),
            subtitle: Text(
              'Starts a new series from this event; the earlier ones stay '
              'as they are.',
            ),
          ),
        ),
        SimpleDialogOption(
          onPressed: () => Navigator.of(context).pop(),
          child: const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: Text('Go back'),
          ),
        ),
      ],
    );
  },
);

const _kinds = {
  'summary': PropertyKind.text,
  'start': PropertyKind.time,
  'end': PropertyKind.time,
  'description': PropertyKind.multiline,
  'location': PropertyKind.text,
  'action_ids': PropertyKind.goals,
  'priority': PropertyKind.integer,
};
