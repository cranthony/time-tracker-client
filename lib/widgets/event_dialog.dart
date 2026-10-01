import 'package:flutter/material.dart';

import '../models/event.dart';
import 'properties_dialog.dart';

/// Shows every property of [event], as the server sent it, under its
/// summary. Start and end are in local time; the rest are as sent.
Future<void> showEventDialog(BuildContext context, Event event) {
  final summary = event.summary;
  return showPropertiesDialog(
    context,
    title: summary == null || summary.isEmpty ? '(no summary)' : summary,
    // The typed fields first, for an event made without the server's.
    properties: {
      'id': event.id,
      'summary': summary,
      'start': event.start,
      'end': event.end,
      'is_cancelled': event.isCancelled,
      ...event.properties,
    },
    format: (context, key, value) {
      final DateTime? time = switch (key) {
        'start' => event.start,
        'end' => event.end,
        _ => null,
      };
      if (time == null) return '$value';
      final local = time.toLocal();
      final strings = MaterialLocalizations.of(context);
      return '${strings.formatFullDate(local)}, '
          '${strings.formatTimeOfDay(TimeOfDay.fromDateTime(local))}';
    },
  );
}
