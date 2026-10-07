import 'package:flutter/material.dart';

import '../models/person.dart';
import '../widgets/status_message.dart';
import '../services/people_repository.dart';
import '../services/plan_memory.dart';
import '../widgets/person_dialog.dart';
import '../widgets/plan_pane.dart';
import '../widgets/plan_summaries.dart';

/// The Plan page's Locations pane -- where: each place events happen,
/// with the hint the assistant recognizes it by. Tapping one edits or
/// deletes it; "+" adds one. The search finds them by name and hint.
/// Above it all, with a [summary] to measure, the time at each location
/// in its window. It shows what [memory] has, while it loads afresh.
class LocationsPane extends StatefulWidget {
  const LocationsPane({
    super.key,
    required this.repository,
    required this.memory,
    this.summary,
    this.onLocations,
  });

  final PeopleRepository repository;
  final PlanMemory memory;

  /// What the summary measures, and how it's shown; null for none.
  final SummaryView? summary;

  /// Told what the locations are each time they load.
  final ValueChanged<List<Location>>? onLocations;

  @override
  State<LocationsPane> createState() => LocationsPaneState();
}

class LocationsPaneState extends State<LocationsPane> {
  List<Location>? get _locations => widget.memory.locations;
  Object? _error;

  /// What the search has in it.
  String _query = '';

  @override
  void initState() {
    super.initState();
    _settle(widget.memory.loadLocations(widget.repository));
  }

  /// Loads the locations afresh.
  Future<void> reload() =>
      _settle(widget.memory.loadLocations(widget.repository, again: true));

  /// Shows what [loading] loads, once it has, or why it couldn't.
  Future<void> _settle(Future<void> loading) async {
    try {
      await loading;
      if (!mounted) return;
      setState(() => _error = null);
      widget.onLocations?.call(_locations!);
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
    final view = widget.summary;
    return PlanPane(
      summary: view == null
          ? null
          : PlanSummary(
              view: view,
              titles: const ['By location'],
              pages: (events) => [
                locationTime(events, view.window, {
                  for (final l in locations ?? const <Location>[]) l.id: l.name,
                }),
              ],
            ),
      searchHint: 'Search locations',
      onSearch: (query) => setState(() => _query = query),
      actions: [
        IconButton(
          tooltip: 'New location',
          icon: const Icon(Icons.add),
          onPressed: locations == null ? null : () => _edit(null),
        ),
      ],
      child: RefreshIndicator(
        onRefresh: reload,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.only(bottom: 24),
          children: switch ((locations, _error)) {
            (null, final error?) => [
              LoadError(what: 'the locations', error: error, onRetry: reload),
            ],
            (null, _) => const [LinearProgressIndicator()],
            (final locations?, _) => [
              for (final location in locations)
                if (matchesSearch(_query, [location.name, location.hint]))
                  ListTile(
                    leading: const Icon(Icons.place_outlined),
                    title: Text(location.name),
                    subtitle: location.hint == null
                        ? null
                        : Text(location.hint!),
                    onTap: () => _edit(location),
                  ),
              if (locations.isNotEmpty &&
                  !locations.any(
                    (l) => matchesSearch(_query, [l.name, l.hint]),
                  ))
                NoMatches(query: _query),
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
        ),
      ),
    );
  }
}
