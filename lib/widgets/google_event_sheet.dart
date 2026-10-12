import 'package:flutter/material.dart';

import '../models/google_calendar.dart';
import 'event_description.dart';

/// What to do with a Google Calendar event, from its sheet.
enum GoogleEventChoice { log, open }

/// Shows [event]: its title, times, calendar and where. Says whether the
/// user chose to log it as an event of their own, or open it in Google
/// Calendar; null if neither.
Future<GoogleEventChoice?> showGoogleEventSheet(
  BuildContext context,
  GoogleEvent event,
) => showModalBottomSheet<GoogleEventChoice>(
  context: context,
  showDragHandle: true,
  // As tall as a long description needs, up to most of the screen,
  // scrolling past that.
  isScrollControlled: true,
  constraints: BoxConstraints(
    maxHeight: MediaQuery.sizeOf(context).height * 0.85,
  ),
  builder: (context) {
    final theme = Theme.of(context);
    final local = MaterialLocalizations.of(context);
    String time(DateTime t) =>
        local.formatTimeOfDay(TimeOfDay.fromDateTime(t.toLocal()));
    final last = event.end.subtract(const Duration(days: 1));
    final when = event.allDay
        ? last.isAfter(event.start)
              ? 'All day, ${local.formatMediumDate(event.start)} – '
                    '${local.formatMediumDate(last)}'
              : 'All day, ${local.formatMediumDate(event.start)}'
        : '${local.formatMediumDate(event.start)}, '
              '${time(event.start)} – ${time(event.end)}';
    Widget row(IconData icon, String text, {Color? color}) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(
            icon,
            size: 20,
            color: color ?? theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 16),
          Expanded(child: Text(text, style: theme.textTheme.bodyMedium)),
        ],
      ),
    );
    return SafeArea(
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 14,
                    height: 14,
                    decoration: BoxDecoration(
                      color: event.calendar.color,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(event.title, style: theme.textTheme.titleLarge),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              row(Icons.schedule, when),
              if (event.location case final where?)
                row(Icons.place_outlined, where),
              if (event.description case final about?
                  when about.trim().isNotEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.notes,
                        size: 20,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 16),
                      Expanded(child: EventDescription(about)),
                    ],
                  ),
                ),
              row(
                Icons.event_outlined,
                '${event.calendar.name} · ${event.calendar.account}',
              ),
              const SizedBox(height: 4),
              Text(
                event.allDay
                    ? "From Google Calendar. It isn't one of your events."
                    : "From Google Calendar. It isn't one of your events: "
                          'logging it makes one with its times.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton.icon(
                    onPressed: () =>
                        Navigator.pop(context, GoogleEventChoice.open),
                    icon: const Icon(Icons.open_in_new),
                    label: const Text('Open in Calendar'),
                  ),
                  const SizedBox(width: 8),
                  if (!event.allDay)
                    FilledButton.icon(
                      onPressed: () =>
                          Navigator.pop(context, GoogleEventChoice.log),
                      icon: const Icon(Icons.add),
                      label: const Text('Log this'),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  },
);
