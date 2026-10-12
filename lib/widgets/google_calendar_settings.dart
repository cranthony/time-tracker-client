import 'package:flutter/material.dart';

import '../services/google_calendars.dart';

/// Settings' section for Google Calendar: whether its events are shown on
/// the Events page, and from which of the phone's calendars, by account.
/// Nothing where there's no [GoogleCalendars]: not on this platform.
class GoogleCalendarSettings extends StatefulWidget {
  const GoogleCalendarSettings({super.key});

  @override
  State<GoogleCalendarSettings> createState() => _GoogleCalendarSettingsState();
}

class _GoogleCalendarSettingsState extends State<GoogleCalendarSettings> {
  var _denied = false;

  @override
  Widget build(BuildContext context) {
    final calendars = GoogleCalendars.of(context);
    if (calendars == null) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final byAccount = <String, List<int>>{};
    for (final (i, c) in calendars.calendars.indexed) {
      (byAccount[c.account] ??= []).add(i);
    }
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
            _denied
                ? "The app isn't allowed to read your calendars. Allow it in "
                      "Android's settings for the app, then try again."
                : 'On the Events page, faintly, behind your own. Read from '
                      'this phone only: nothing is sent to the server.',
          ),
          onChanged: (on) async {
            if (!on) return calendars.disable();
            final enabled = await calendars.enable();
            if (mounted) setState(() => _denied = !enabled);
          },
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
