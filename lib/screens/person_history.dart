import 'package:flutter/material.dart';

import '../models/event.dart';
import '../models/plan_action.dart';
import '../services/events_repository.dart';
import '../widgets/event_dialog.dart';
import '../widgets/event_summary_dialog.dart';

/// How far back a person's event history goes.
const historyYears = 10;

/// [personId]'s events over the last [historyYears] years to [now], newest
/// first, from the server ([EventsRepository.personEvents]): asked for
/// when wanted, not kept in the EventStore.
Future<List<Event>> loadPersonHistory(
  EventsRepository events,
  String personId, {
  DateTime? now,
}) async {
  final to = now ?? DateTime.now();
  final from = DateTime(to.year - historyYears, to.month, to.day);
  return (await events.personEvents(personId, from, to)).reversed.toList();
}

/// [history], a person's events newest first ([loadPersonHistory]): how
/// many, since when, then each ([historyTile]).
List<Widget> personHistoryTiles(
  BuildContext context,
  List<Event> history, {
  required String personId,
  Map<String, PlanAction> actions = const {},
}) {
  final theme = Theme.of(context);
  Widget padded(Widget child) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
    child: child,
  );
  if (history.isEmpty) {
    return [
      padded(
        Text(
          'No events in the last $historyYears years.',
          style: TextStyle(color: theme.hintColor),
        ),
      ),
    ];
  }
  final since = MaterialLocalizations.of(context)
      .formatMediumDate(history.last.start);
  return [
    padded(
      Text(
        '${history.length} ${history.length == 1 ? 'event' : 'events'} '
        'since $since',
        style: theme.textTheme.bodyMedium,
      ),
    ),
    for (final event in history)
      historyTile(context, event, personId: personId, actions: actions),
  ];
}

/// One of a person's events in their history: its date and summary, and
/// the note on [personId] if it has one. Tapping it opens it
/// ([openHistoryEvent]).
Widget historyTile(
  BuildContext context,
  Event event, {
  required String personId,
  Map<String, PlanAction> actions = const {},
}) {
  final localizations = MaterialLocalizations.of(context);
  final note = event.facts?.notes[personId];
  return ListTile(
    dense: true,
    title: Text(switch (event.summary) {
      final s? when s.isNotEmpty => s,
      _ => '(no title)',
    }),
    subtitle: Text(
      [
        localizations.formatMediumDate(event.start),
        if (note != null && note.isNotEmpty) '“$note”',
      ].join('\n'),
    ),
    onTap: () => openHistoryEvent(context, event, actions: actions),
  );
}

/// Opens [event] as the Events page does, its summary then, from it, its
/// details -- to see, not change: it's changed on the Events page, where
/// changes are queued and the days shown again.
Future<void> openHistoryEvent(
  BuildContext context,
  Event event, {
  Map<String, PlanAction> actions = const {},
}) async {
  final outcome = await showEventSummaryDialog(
    context,
    event,
    actions: actions,
  );
  if (outcome is SummaryDetails && context.mounted) {
    await showEventDialog(context, event);
  }
}
