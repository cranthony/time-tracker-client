import 'package:flutter/material.dart';

import '../models/weather.dart';
import '../services/app_settings.dart';
import '../services/weather.dart';

/// Settings' section for the weather: whether it's shown on the Events
/// page -- asking, as it's turned on, to know roughly where the device is
/// -- and the units it's shown in. Refused, it says so, and, refused for
/// good, offers the device's settings to allow it there. Nothing where
/// there's no [Weather].
class WeatherSettings extends StatelessWidget {
  const WeatherSettings({super.key, required this.settings});

  final AppSettings settings;

  @override
  Widget build(BuildContext context) {
    final weather = Weather.of(context);
    if (weather == null) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final refused = !weather.enabled
        ? switch (weather.access) {
            LocationAccess.denied =>
              "The app wasn't allowed to know where this device is.",
            LocationAccess.blocked =>
              "The app isn't allowed to know where this device is. Allow "
                  "it in the device's settings for the app, then turn this "
                  'on again.',
            LocationAccess.serviceOff =>
              "This device's location is off. Turn it on, then turn this "
                  'on again.',
            _ => null,
          }
        : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
          child: Text('Weather', style: theme.textTheme.titleMedium),
        ),
        SwitchListTile(
          value: weather.enabled,
          title: const Text('Show the weather'),
          subtitle: Text(
            refused ??
                "On the Events page: the day's above the timeline, and the "
                    "hours' down its band, in place of the priorities. For "
                    'roughly where this device is: that goes to Open-Meteo, '
                    'for its forecast, and not to the server.',
            style: refused == null
                ? null
                : TextStyle(color: theme.colorScheme.error),
          ),
          onChanged: (on) => on ? weather.enable() : weather.disable(),
        ),
        if (!weather.enabled &&
            (weather.access == LocationAccess.blocked ||
                weather.access == LocationAccess.serviceOff))
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: TextButton.icon(
              onPressed: weather.location.openSettings,
              icon: const Icon(Icons.settings_outlined),
              label: const Text('Open the settings'),
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: DropdownMenu<TemperatureUnit>(
            initialSelection: settings.temperatureUnit,
            expandedInsets: EdgeInsets.zero,
            requestFocusOnTap: false,
            label: const Text('Temperature'),
            onSelected: (unit) {
              if (unit != null) settings.setTemperatureUnit(unit);
            },
            dropdownMenuEntries: [
              for (final unit in TemperatureUnit.values)
                DropdownMenuEntry(value: unit, label: unit.label),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: DropdownMenu<PrecipitationUnit>(
            initialSelection: settings.precipitationUnit,
            expandedInsets: EdgeInsets.zero,
            requestFocusOnTap: false,
            label: const Text('Rain and snow'),
            onSelected: (unit) {
              if (unit != null) settings.setPrecipitationUnit(unit);
            },
            dropdownMenuEntries: [
              for (final unit in PrecipitationUnit.values)
                DropdownMenuEntry(value: unit, label: unit.label),
            ],
          ),
        ),
      ],
    );
  }
}
