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
/// sent it, under its summary: its schedule in words, its rules, and the
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
      for (final key in ['schedule', 'rules', 'summary', 'start', 'end'])
        key: typed[key],
      ...recurrence.properties,
      ...typed,
    },
    kinds: _kinds,
    hints: const {
      'rules':
          'One rule per line, like RRULE:FREQ=WEEKLY;BYDAY=MO,WE. The '
          'schedule above says them in words.',
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
            final picked = await _askScope(context);
            if (picked != null) scope = picked;
            return picked != null;
          },
    save: (changes) => save(changes, scope),
    signInHint: 'Sign in again from the Events page, then try again.',
  );
}

/// Asks whether a change is for every event in the series, or the one it
/// was opened from and those after it; null to go back.
Future<SeriesScope?> _askScope(BuildContext context) => showDialog<SeriesScope>(
  context: context,
  builder: (context) => SimpleDialog(
    title: const Text('Change which events?'),
    children: [
      SimpleDialogOption(
        onPressed: () => Navigator.of(context).pop(SeriesScope.all),
        child: const ListTile(
          leading: Icon(Icons.event_repeat),
          title: Text('All events'),
          subtitle: Text(
            'Every event in the series, except any changed on its own.',
          ),
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
  ),
);

const _kinds = {
  'summary': PropertyKind.text,
  'rules': PropertyKind.lines,
  'start': PropertyKind.time,
  'end': PropertyKind.time,
  'description': PropertyKind.multiline,
  'location': PropertyKind.text,
  'goal_ids': PropertyKind.goals,
  'priority': PropertyKind.integer,
  'is_fixed_time': PropertyKind.flag,
  'is_fixed_duration': PropertyKind.flag,
  'min_duration': PropertyKind.duration,
};
