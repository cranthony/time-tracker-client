import 'package:flutter/material.dart';

import '../models/event.dart';
import '../models/goal.dart';
import 'properties_dialog.dart';

/// Shows every property of [event], as the server sent it, under its
/// summary. Start and end are in local time; the rest are as sent.
///
/// Tapping a value the server lets one change opens it for editing, in
/// place; "Save" sends every change with [save]. Returns what [save]
/// returned (the events the server changed), or null if nothing was saved.
/// Without [save], or for an event with no id, nothing can be edited.
///
/// With [openSeries], an event in a recurring series links to it: tapping
/// its recurring_event_id calls [openSeries] with the series' id, and if
/// that saved a change to the series (returning true), this closes,
/// returning null.
Future<List<Event>?> showEventDialog(
  BuildContext context,
  Event event, {
  Future<List<Event>> Function(Event event, Map<String, Object?> changes)? save,
  Future<List<Goal>> Function()? goals,
  Future<bool> Function(String seriesId)? openSeries,
}) {
  final typed = event.toJson();
  return showPropertiesDialog<List<Event>>(
    context,
    title: (values) => switch (values['summary']) {
      final String summary when summary.isNotEmpty => summary,
      _ => '(no summary)',
    },
    // The typed fields first, for an event made without the server's.
    properties: {
      for (final key in ['id', 'summary', 'start', 'end', 'is_cancelled'])
        key: typed[key],
      ...event.properties,
      ...typed,
    },
    kinds: _kinds,
    links: {
      if ((openSeries, event.properties['recurring_event_id']) case (
        final open?,
        final String seriesId,
      ))
        'recurring_event_id': PropertyLink(
          label: 'Repeats: see or change the series',
          open: () => open(seriesId),
        ),
    },
    save: save == null || event.id == null
        ? null
        : (changes) => save(event, changes),
    validate: (values) {
      final start = DateTime.parse(values['start'] as String);
      final end = DateTime.parse(values['end'] as String);
      return end.isAfter(start) ? null : 'The end has to be after the start.';
    },
    goals: goals,
    oneWayAction: event.isCancelled
        ? null
        : const OneWayAction(
            label: 'Cancel event',
            question: 'Cancel this event?',
            explanation:
                "This can't be undone. The event leaves the list once it's "
                'cancelled.',
            keepLabel: 'Keep event',
            changes: {'is_cancelled': true},
          ),
    signInHint: 'Sign in again from the Events page, then try again.',
  );
}

const _kinds = {
  'summary': PropertyKind.text,
  'start': PropertyKind.time,
  'end': PropertyKind.time,
  'description': PropertyKind.multiline,
  'location': PropertyKind.text,
  // Its label follows its goals, so it isn't edited itself.
  'goal_ids': PropertyKind.goals,
  'priority': PropertyKind.integer,
  'is_fixed_time': PropertyKind.flag,
  'is_fixed_duration': PropertyKind.flag,
  'min_duration': PropertyKind.duration,
};
