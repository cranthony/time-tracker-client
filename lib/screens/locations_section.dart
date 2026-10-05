import 'package:flutter/material.dart';

import '../models/person.dart';
import '../services/mcp_client.dart';
import '../services/people_repository.dart';
import '../widgets/person_dialog.dart';
import '../widgets/plan_section.dart';

/// The Plan page's Locations section -- where: each place events happen,
/// with the hint the assistant recognizes it by. Tapping one edits or
/// deletes it; "+" adds one.
class LocationsSection extends StatefulWidget {
  const LocationsSection({
    super.key,
    required this.repository,
    required this.expanded,
    required this.onExpanded,
    this.onLocations,
  });

  final PeopleRepository repository;
  final bool expanded;
  final ValueChanged<bool> onExpanded;

  /// Told what the locations are each time they load.
  final ValueChanged<List<Location>>? onLocations;

  @override
  State<LocationsSection> createState() => LocationsSectionState();
}

class LocationsSectionState extends State<LocationsSection> {
  List<Location>? _locations;
  Object? _error;

  @override
  void initState() {
    super.initState();
    reload();
  }

  /// Loads the locations afresh.
  Future<void> reload() async {
    try {
      final locations = await widget.repository.locations();
      if (!mounted) return;
      setState(() {
        _locations = locations;
        _error = null;
      });
      widget.onLocations?.call(locations);
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _edit(Location? location) async {
    final repository = widget.repository;
    final saved = await showLocationDialog(
      context,
      location: location,
      save: (fields) => location == null
          ? repository.createLocation(
              Location(
                id: '',
                name: fields['name'] as String,
                hint: fields['hint'] as String?,
              ),
            )
          : repository.updateLocation(location.id, fields),
      delete: location == null
          ? null
          : () => repository.deleteLocation(location.id),
    );
    if (saved != null) await reload();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final locations = _locations;
    return PlanSection(
      title: 'Locations',
      annotation: 'where',
      expanded: widget.expanded,
      onExpanded: widget.onExpanded,
      actions: [
        IconButton(
          tooltip: 'New location',
          icon: const Icon(Icons.add),
          onPressed: locations == null ? null : () => _edit(null),
        ),
      ],
      children: switch ((locations, _error)) {
        (null, final error?) => [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              "Couldn't load the locations. ${switch (error) {
                McpException(:final message) => message,
                _ => '$error',
              }}",
            ),
          ),
        ],
        (null, _) => const [LinearProgressIndicator()],
        (final locations?, _) => [
          for (final location in locations)
            ListTile(
              leading: const Icon(Icons.place_outlined),
              title: Text(location.name),
              subtitle: location.hint == null ? null : Text(location.hint!),
              onTap: () => _edit(location),
            ),
          if (locations.isEmpty)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'No locations yet. Tap + to add one, or let compaction '
                'add them as notes mention places.',
                style: theme.textTheme.bodySmall,
              ),
            ),
        ],
      },
    );
  }
}
