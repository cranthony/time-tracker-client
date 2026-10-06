import 'package:flutter/material.dart';

import '../models/event.dart';
import '../models/goal.dart';
import 'event_room.dart';
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
///
/// New times that would overlap an event in [room] can't be saved.
///
/// With [cancel] too, "Cancel event" cancels it after asking -- and asks
/// whether that counts against follow-through (see
/// [followThroughOption]) -- returning what [cancel] returned.
Future<List<Event>?> showEventDialog(
  BuildContext context,
  Event event, {
  Future<List<Event>> Function(Event event, Map<String, Object?> changes)? save,
  Future<List<Event>> Function(Event event, bool countsAgainstFollowThrough)?
  cancel,
  EventRoom room = const EventRoom.none(),
  Future<List<Goal>> Function()? goals,
  Future<bool> Function(String seriesId)? openSeries,
}) {
  final typed = event.toJson();
  final strings = MaterialLocalizations.of(context);
  String time(DateTime t) =>
      strings.formatTimeOfDay(TimeOfDay.fromDateTime(t.toLocal()));
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
    // Every event has one; the rest can be cleared (see clearableFields).
    required: const {'summary'},
    inferred: {
      if (event.properties['actions_from_label'] == true)
        'action_ids': 'from its label',
    },
    hints: const {
      'action_ids':
          'Actions shown "from its label" were never set: they come from the '
          "event's label. Keep or change them to set them.",
    },
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
        : (changes) => switch ((changes['is_cancelled'], cancel)) {
            // Cancelling isn't an update: see OneWayAction below.
            (true, final cancel?) => cancel(
              event,
              changes[followThroughOption.key] == true,
            ),
            _ => save(event, changes),
          },
    validate: (values) {
      final start = DateTime.parse(values['start'] as String);
      final end = DateTime.parse(values['end'] as String);
      if (!end.isAfter(start)) return 'The end has to be after the start.';
      // Overlaps it had already are left alone.
      if (start.isAtSameMomentAs(event.start) &&
          end.isAtSameMomentAs(event.end)) {
        return null;
      }
      return switch (room.overlapping(start, end)) {
        final other? =>
          'It would overlap ${switch (other.summary) {
            final s? when s.isNotEmpty => '"$s"',
            _ => 'another event',
          }}, ${time(other.start)} – ${time(other.end)}.',
        null => null,
      };
    },
    goals: goals,
    oneWayAction: event.isCancelled || cancel == null
        ? null
        : const OneWayAction(
            label: 'Cancel event',
            question: 'Cancel this event?',
            explanation:
                "This can't be undone. The event leaves the list once it's "
                'cancelled.',
            keepLabel: 'Keep event',
            changes: {'is_cancelled': true},
            option: followThroughOption,
          ),
    signInHint: 'Sign in again from the Events page, then try again.',
  );
}

/// The switch cancelling an event offers: whether it counts against the
/// follow-through of whoever a follow-through trait tracks it for, rather
/// than being just a change of plan. On to begin with: turning it off says
/// the plan merely changed.
const followThroughOption = ConfirmOption(
  key: 'counts_against_follow_through',
  label: 'Count against follow-through',
  explanation:
      'A commitment dropped, not just a change of plan: it lowers the '
      'follow-through of the people, and for the actions, a trait tracks.',
  initial: true,
);

const _kinds = {
  'summary': PropertyKind.text,
  'start': PropertyKind.time,
  'end': PropertyKind.time,
  'description': PropertyKind.multiline,
  'location': PropertyKind.text,
  // Its label follows its goals, so it isn't edited itself.
  'action_ids': PropertyKind.goals,
  'priority': PropertyKind.integer,
  'is_fixed_time': PropertyKind.flag,
  'is_fixed_duration': PropertyKind.flag,
  'min_duration': PropertyKind.duration,
};
