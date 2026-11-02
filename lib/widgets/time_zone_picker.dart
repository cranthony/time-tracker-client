import 'package:flutter/material.dart';

import '../models/time_zones.dart';

/// Asks for a time zone, searched by place or name, each with its offset
/// at [at] -- [current] first, marked. Returns the zone's IANA name, or
/// null if it's called off.
Future<String?> showTimeZonePicker(
  BuildContext context, {
  String? current,
  required DateTime at,
}) => showDialog<String>(
  context: context,
  builder: (_) => _TimeZonePicker(current: current, at: at),
);

class _TimeZonePicker extends StatefulWidget {
  const _TimeZonePicker({required this.current, required this.at});

  final String? current;
  final DateTime at;

  @override
  State<_TimeZonePicker> createState() => _TimeZonePickerState();
}

class _TimeZonePickerState extends State<_TimeZonePicker> {
  final _query = TextEditingController();
  late final List<String> _zones = zoneNames();

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  /// The zones whose name, place or abbreviation has every word typed;
  /// the current one first.
  List<String> get _shown {
    final words = _query.text.toLowerCase().split(RegExp(r'\s+'))
      ..removeWhere((w) => w.isEmpty);
    bool matches(String zone) {
      final said =
          '$zone ${zonePlace(zone)} ${zoneAbbreviation(zone, widget.at) ?? ''}'
              .toLowerCase();
      return words.every(said.contains);
    }

    final current = widget.current;
    return [
      if (current != null && matches(current)) current,
      for (final zone in _zones)
        if (zone != current && matches(zone)) zone,
    ];
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final shown = _shown;
    return AlertDialog(
      title: const Text('Time zone'),
      contentPadding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      content: SizedBox(
        width: 420,
        height: 480,
        child: Column(
          children: [
            TextField(
              controller: _query,
              autofocus: true,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Search places and zones',
                isDense: true,
              ),
              onChanged: (_) => setState(() {}),
              onSubmitted: (_) {
                if (shown.isNotEmpty) Navigator.of(context).pop(shown.first);
              },
            ),
            const SizedBox(height: 8),
            Expanded(
              child: shown.isEmpty
                  ? Center(
                      child: Text(
                        'No time zone matches.',
                        style: TextStyle(color: theme.hintColor),
                      ),
                    )
                  : ListView.builder(
                      itemCount: shown.length,
                      itemBuilder: (context, i) {
                        final zone = shown[i];
                        return ListTile(
                          dense: true,
                          selected: zone == widget.current,
                          trailing: zone == widget.current
                              ? const Icon(Icons.check)
                              : null,
                          title: Text(zoneLabel(zone, widget.at)),
                          subtitle: Text(zone),
                          onTap: () => Navigator.of(context).pop(zone),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
      ],
    );
  }
}
