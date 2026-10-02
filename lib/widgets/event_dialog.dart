import 'package:flutter/material.dart';

import '../models/event.dart';
import '../models/event_label.dart';
import 'properties_dialog.dart';

/// Shows every property of [event], as the server sent it, under its
/// summary. Start and end are in local time; the rest are as sent.
///
/// Tapping a value the server lets one change opens it for editing, in
/// place; "Save" sends every change with [save]. Returns what [save]
/// returned (the events the server changed), or null if nothing was saved.
/// Without [save], or for an event with no id, nothing can be edited.
Future<List<Event>?> showEventDialog(
  BuildContext context,
  Event event, {
  Future<List<Event>> Function(Event event, Map<String, Object?> changes)? save,
  Future<List<EventLabel>> Function()? labels,
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
    save: save == null || event.id == null
        ? null
        : (changes) => save(event, changes),
    validate: (values) {
      final start = DateTime.parse(values['start'] as String);
      final end = DateTime.parse(values['end'] as String);
      return end.isAfter(start) ? null : 'The end has to be after the start.';
    },
    labels: labels,
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
  'event_label_id': PropertyKind.label,
  'priority': PropertyKind.integer,
  'is_fixed_time': PropertyKind.flag,
  'is_fixed_duration': PropertyKind.flag,
  'min_duration': PropertyKind.duration,
};
