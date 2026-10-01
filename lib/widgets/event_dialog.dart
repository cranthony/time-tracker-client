import 'package:flutter/material.dart';

import '../models/event.dart';

/// Shows every property of [event], as the server sent it, under its
/// summary. Start and end are in local time; the rest are as sent.
Future<void> showEventDialog(BuildContext context, Event event) => showDialog(
  context: context,
  builder: (context) => _EventDialog(event: event),
);

class _EventDialog extends StatelessWidget {
  const _EventDialog({required this.event});

  final Event event;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final summary = event.summary;
    // The typed fields first, for an event made without the server's.
    final properties = <String, Object?>{
      'id': event.id,
      'summary': summary,
      'start': event.start,
      'end': event.end,
      'is_cancelled': event.isCancelled,
      ...event.properties,
    };
    return AlertDialog(
      title: Text(
        summary == null || summary.isEmpty ? '(no summary)' : summary,
      ),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final MapEntry(:key, :value) in properties.entries)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      key,
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: theme.colorScheme.primary,
                      ),
                    ),
                    if (value == null)
                      Text('(none)', style: TextStyle(color: theme.hintColor))
                    else
                      SelectableText(_format(context, key, value)),
                  ],
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }

  String _format(BuildContext context, String key, Object value) {
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
  }
}
