import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/weather.dart';
import '../services/app_settings.dart';
import '../services/maps.dart';
import '../services/weather.dart';

/// Settings' section for the weather: whether it's shown on the Events
/// page; where for -- where this device is, asked to know only once
/// that's picked, or a place given by its latitude and longitude, never
/// asking -- pasted as a maps app copies them, and opened in one
/// ([openMaps]) to check; and the units it's shown in. Refused the location, it says so,
/// and, refused for good, offers the device's settings to allow it there.
/// Nothing where there's no [Weather].
class WeatherSettings extends StatefulWidget {
  const WeatherSettings({
    super.key,
    required this.settings,
    this.openMaps = openInMaps,
  });

  final AppSettings settings;

  /// Opens a place, "47.61,-122.33", in a maps app.
  final Future<bool> Function(String place) openMaps;

  @override
  State<WeatherSettings> createState() => _WeatherSettingsState();
}

class _WeatherSettingsState extends State<WeatherSettings> {
  final _latitude = TextEditingController();
  final _longitude = TextEditingController();

  /// Whether "A place I give" is picked, before one's been given.
  var _giving = false;

  /// What's wrong with the place typed, once it's been tried.
  String? _problem;

  /// The place the fields were last filled from, to fill them again as
  /// it changes.
  Coordinates? _filledFrom;

  @override
  void dispose() {
    _latitude.dispose();
    _longitude.dispose();
    super.dispose();
  }

  void _fill(Coordinates? place) {
    if (place == _filledFrom) return;
    _filledFrom = place;
    if (place == null) return;
    _latitude.text = '${place.latitude}';
    _longitude.text = '${place.longitude}';
  }

  /// The place typed, if it's one; otherwise null, and [_problem] says
  /// why.
  Coordinates? _typed() {
    final latitude = double.tryParse(_latitude.text.trim());
    final longitude = double.tryParse(_longitude.text.trim());
    _problem = switch ((latitude, longitude)) {
      (null, _) || (_, null) => 'Type both, in degrees: say 47.61 and -122.33.',
      (final lat?, _) when lat < -90 || lat > 90 =>
        'Latitude is from -90 (south) to 90 (north).',
      (_, final lon?) when lon < -180 || lon > 180 =>
        'Longitude is from -180 (west) to 180 (east).',
      _ => null,
    };
    return _problem == null ? Coordinates(latitude!, longitude!) : null;
  }

  /// The place typed, if it's one, leaving [_problem] be.
  Coordinates? get _shown => switch ((
    double.tryParse(_latitude.text.trim()),
    double.tryParse(_longitude.text.trim()),
  )) {
    (final lat?, final lon?) when lat.abs() <= 90 && lon.abs() <= 180 =>
      Coordinates(lat, lon),
    _ => null,
  };

  /// Fills both fields from [place].
  void _put(Coordinates place) {
    _latitude.text = '${place.latitude}';
    _longitude.text = '${place.longitude}';
    _problem = null;
  }

  /// A field typed in: split across both if it's a whole place, pasted
  /// as a maps app copies one.
  void _typedIn(String text) => setState(() {
    if (Coordinates.tryParse(text) case final place?) _put(place);
  });

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (!mounted) return;
    setState(() {
      if (Coordinates.tryParse(data?.text ?? '') case final place?) {
        _put(place);
      } else {
        _problem =
            "What's copied isn't a latitude and longitude, like "
            '"47.61, -122.33".';
      }
    });
  }

  void _usePlace(Weather weather) {
    final place = _typed();
    setState(() {});
    if (place == null) return;
    _giving = false;
    weather.usePlace(place);
    FocusScope.of(context).unfocus();
  }

  @override
  Widget build(BuildContext context) {
    final weather = Weather.of(context);
    if (weather == null) return const SizedBox.shrink();
    final settings = widget.settings;
    final theme = Theme.of(context);
    _fill(weather.place);
    final givesPlace = _giving || !weather.usesDevice;
    final refused = weather.usesDevice
        ? switch (weather.access) {
            LocationAccess.denied =>
              "The app wasn't allowed to know where this device is: ask "
                  'again, or give a place.',
            LocationAccess.blocked =>
              "The app isn't allowed to know where this device is. Allow it "
                  "in the device's settings for the app, or give a place.",
            LocationAccess.serviceOff =>
              "This device's location is off. Turn it on, or give a place.",
            _ => null,
          }
        : null;
    final error = TextStyle(color: theme.colorScheme.error);
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
          subtitle: const Text(
            "On the Events page: the day's above the timeline, and the "
            "hours' down its band, in place of the priorities. From "
            'Open-Meteo, for the place below; nothing goes to the server.',
          ),
          onChanged: (on) => on ? weather.enable() : weather.disable(),
        ),
        if (weather.enabled) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Text(
              'For',
              style: theme.textTheme.labelLarge?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          RadioGroup<bool>(
            groupValue: !givesPlace,
            onChanged: (device) {
              if (device == true) {
                setState(() => _giving = false);
                weather.useDevice();
              } else if (weather.place case final place?) {
                weather.usePlace(place);
              } else {
                setState(() => _giving = true);
              }
            },
            child: Column(
              children: [
                const RadioListTile<bool>(
                  value: false,
                  title: Text('A place I give'),
                  subtitle: Text(
                    'By its latitude and longitude, in degrees. The device '
                    "isn't asked where it is.",
                  ),
                ),
                if (givesPlace)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(72, 4, 16, 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _latitude,
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                      signed: true,
                                      decimal: true,
                                    ),
                                onChanged: _typedIn,
                                decoration: const InputDecoration(
                                  labelText: 'Latitude',
                                  hintText: '47.61',
                                  border: OutlineInputBorder(),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: TextField(
                                controller: _longitude,
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                      signed: true,
                                      decimal: true,
                                    ),
                                onChanged: _typedIn,
                                decoration: const InputDecoration(
                                  labelText: 'Longitude',
                                  hintText: '-122.33',
                                  border: OutlineInputBorder(),
                                ),
                                onSubmitted: (_) => _usePlace(weather),
                              ),
                            ),
                          ],
                        ),
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(
                            'In a maps app, drop a pin where you want the '
                            'weather for and copy its coordinates, then paste '
                            'them here.',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                        Wrap(
                          spacing: 8,
                          children: [
                            TextButton.icon(
                              onPressed: _paste,
                              icon: const Icon(Icons.content_paste),
                              label: const Text('Paste coordinates'),
                            ),
                            if (_shown case final place?)
                              TextButton.icon(
                                onPressed: () => widget.openMaps(
                                  '${place.latitude},${place.longitude}',
                                ),
                                icon: const Icon(Icons.map_outlined),
                                label: const Text('Open in maps'),
                              ),
                          ],
                        ),
                        if (_problem case final problem?)
                          Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Text(
                              problem,
                              style: theme.textTheme.bodySmall?.merge(error),
                            ),
                          ),
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Row(
                            children: [
                              FilledButton.tonal(
                                onPressed: () => _usePlace(weather),
                                child: const Text('Use this place'),
                              ),
                              const SizedBox(width: 12),
                              if (!weather.usesDevice && weather.place != null)
                                Expanded(
                                  child: Text(
                                    'Using ${weather.place!.latitude}, '
                                    '${weather.place!.longitude}',
                                    style: theme.textTheme.bodySmall,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                RadioListTile<bool>(
                  value: true,
                  title: const Text('Where this device is'),
                  subtitle: Text(
                    refused ??
                        'Roughly, asked for as this is picked, and sent to '
                            'Open-Meteo to about a kilometer.',
                    style: refused == null ? null : error,
                  ),
                ),
                if (refused != null)
                  Padding(
                    padding: const EdgeInsets.only(left: 56),
                    child: Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: weather.access == LocationAccess.denied
                          ? TextButton.icon(
                              onPressed: weather.useDevice,
                              icon: const Icon(Icons.my_location),
                              label: const Text('Ask again'),
                            )
                          : TextButton.icon(
                              onPressed: weather.location.openSettings,
                              icon: const Icon(Icons.settings_outlined),
                              label: const Text('Open the settings'),
                            ),
                    ),
                  ),
              ],
            ),
          ),
        ],
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
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
