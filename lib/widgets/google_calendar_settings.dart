import 'package:flutter/material.dart';

import '../services/google_calendars.dart';

/// Settings' section for Google Calendar: whether its events are shown on
/// the Events page, and from which of the phone's calendars, by account.
/// Refused the calendar permission, it says so, and, refused for good,
/// offers the app's settings to allow it there. Nothing where there's no
/// [GoogleCalendars]: not on this platform.
class GoogleCalendarSettings extends StatelessWidget {
  const GoogleCalendarSettings({super.key});

  @override
  Widget build(BuildContext context) {
    final calendars = GoogleCalendars.of(context);
    if (calendars == null) return const SizedBox.shrink();
    final theme = Theme.of(context);
    // Opened before the Events page asked for them.
    if (calendars.enabled) calendars.loadCalendars();
    final byAccount = <String, List<int>>{};
    for (final (i, c) in calendars.calendars.indexed) {
      (byAccount[c.account] ??= []).add(i);
    }
    final refused = !calendars.enabled
        ? switch (calendars.permission) {
            CalendarPermission.denied =>
              "The app wasn't allowed to read your calendars.",
            CalendarPermission.blocked =>
              "The app isn't allowed to read your calendars. Allow it in "
                  "Android's settings for the app, then turn this on again.",
            _ => null,
          }
        : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
          child: Text('Google Calendar', style: theme.textTheme.titleMedium),
        ),
        SwitchListTile(
          value: calendars.enabled,
          title: const Text('Show its events'),
          subtitle: Text(
            refused ??
                'On the Events page, behind your own. Read from this phone '
                    'only: nothing is sent to the server.',
            style: refused == null
                ? null
                : TextStyle(color: theme.colorScheme.error),
          ),
          onChanged: (on) => on ? calendars.enable() : calendars.disable(),
        ),
        if (!calendars.enabled &&
            calendars.permission == CalendarPermission.blocked)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: TextButton.icon(
              onPressed: calendars.source.openSettings,
              icon: const Icon(Icons.settings_outlined),
              label: const Text("Open the app's settings"),
            ),
          ),
        if (calendars.enabled &&
            calendars.loaded &&
            calendars.calendars.isEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: Text(
              'No Google calendars are synced to this phone. Add your '
              "Google account in Android's settings, with Calendar on.",
              style: theme.textTheme.bodySmall,
            ),
          ),
        if (calendars.enabled)
          for (final MapEntry(key: account, value: indexes)
              in byAccount.entries) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Text(
                account,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            for (final i in indexes)
              if (calendars.calendars[i] case final calendar)
                CheckboxListTile(
                  value: calendars.selected.contains(calendar.id),
                  activeColor: calendar.color,
                  side: BorderSide(color: calendar.color, width: 2),
                  title: Text(calendar.name),
                  onChanged: (on) => calendars.select(calendar.id, on ?? false),
                ),
          ],
      ],
    );
  }
}
