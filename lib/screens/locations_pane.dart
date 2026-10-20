import 'package:flutter/material.dart';

import '../models/person.dart';
import '../widgets/hotkeys.dart';
import '../widgets/status_message.dart';
import '../services/actions_repository.dart';
import '../services/people_repository.dart';
import '../services/plan_memory.dart';
import '../widgets/person_dialog.dart';
import '../widgets/plan_pane.dart';
import '../widgets/plan_summaries.dart';
import '../widgets/tree_tile.dart';
import 'travel_times_screen.dart';
import '../widgets/quick_add_sheet.dart';

/// The Plan page's Locations pane -- where: each place events happen,
/// with the hint the assistant recognizes it by, under the location
/// groups it's in (a neighborhood, a city). Tapping one edits or deletes
/// it; "+" adds a location, and the folder a group. The search finds them
/// by name and hint, each shown with the groups it's in. The commute
/// button opens how long it takes between them ([TravelTimesScreen]), by
/// way of [actions].
/// Above it all, with a [summary] to measure, the time at each location
/// in its window. It shows what [memory] has, while it loads afresh.
class LocationsPane extends StatefulWidget {
  const LocationsPane({
    super.key,
    required this.repository,
    required this.memory,
    this.summary,
    this.onLocations,
    this.actions,
  });

  final PeopleRepository repository;

  /// The actions a travel time's ways of getting there are from.
  final ActionsRepository? actions;
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
  List<LocationGroup> get _groups => widget.memory.locationGroups ?? const [];
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
    if (location == null) {
      final added = await showAddLocationSheet<Location>(
        context,
        groups: _groups,
        save: (fields) =>
            repository.createLocation(Location.fromJson({'id': '', ...fields})),
      );
      if (added != null) await reload();
      return;
    }
    final saved = await showLocationDialog(
      context,
      location: location,
      groups: _groups,
      save: (fields) => repository.updateLocation(location.id, fields),
      delete: () => repository.deleteLocation(location.id),
      extra: LocationTravelTimes(
        placeId: location.id,
        repository: repository,
        memory: widget.memory,
        actions: widget.actions,
      ),
    );
    if (saved != null) await reload();
  }

  Future<void> _editGroup(LocationGroup? group) async {
    final repository = widget.repository;
    final saved = await showLocationGroupDialog(
      context,
      group: group,
      groups: _groups,
      save: (fields) => group == null
          ? repository.createLocationGroup(
              LocationGroup.fromJson({'id': '', ...fields}),
            )
          : repository.updateLocationGroup(group.id, fields),
      delete: group == null
          ? null
          : () => repository.deleteLocationGroup(group.id),
      extra: group == null
          ? null
          : LocationTravelTimes(
              placeId: group.id,
              repository: repository,
              memory: widget.memory,
              actions: widget.actions,
            ),
    );
    if (saved != null) await reload();
  }

  /// [location], [depth] groups in -- or, from the search, with the
  /// groups it's in ([path]).
  Widget _locationTile(Location location, {int depth = 0, bool path = false}) {
    final detail = path ? locationDetail(location, _groups) : location.hint;
    return TreeTile(
      depth: depth,
      leading: const Icon(Icons.place_outlined),
      title: Text(location.name),
      subtitle: detail == null ? null : Text(detail),
      onTap: () => _edit(location),
    );
  }

  /// [group], as [_locationTile] shows a location.
  Widget _groupTile(LocationGroup group, {int depth = 0, bool path = false}) {
    final detail = [
      if (path) ?groupsPath(group.groupId, _groups),
      ?group.note,
    ].join(' · ');
    return TreeTile(
      depth: depth,
      leading: const Icon(Icons.folder_outlined),
      title: Text(group.name),
      subtitle: detail.isEmpty ? null : Text(detail),
      onTap: () => _editGroup(group),
    );
  }

  /// Every group, with what's in it indented under it, then the locations
  /// in no group.
  List<Widget> _tree(List<Location> locations) {
    final groups = _groups;
    final known = {for (final g in groups) g.id};
    final tiles = <Widget>[];
    final shown = <String>{};
    void visit(LocationGroup group, int depth) {
      if (!shown.add(group.id)) return;
      tiles.add(_groupTile(group, depth: depth));
      for (final l in locations.where((l) => l.groupId == group.id)) {
        tiles.add(_locationTile(l, depth: depth + 1));
      }
      for (final g in groups.where((g) => g.groupId == group.id)) {
        visit(g, depth + 1);
      }
    }

    for (final g in groups) {
      if (g.groupId == null || !known.contains(g.groupId)) visit(g, 0);
    }
    for (final l in locations) {
      if (l.groupId == null || !known.contains(l.groupId)) {
        tiles.add(_locationTile(l));
      }
    }
    return tiles;
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
          tooltip: 'Travel times',
          icon: const Icon(Icons.directions_walk),
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => TravelTimesScreen(
                repository: widget.repository,
                memory: widget.memory,
                actions: widget.actions,
              ),
            ),
          ),
        ),
        IconButton(
          tooltip: 'New location group',
          icon: const Icon(Icons.create_new_folder_outlined),
          onPressed: locations == null ? null : () => _editGroup(null),
        ),
        NewHotkey(
          child: IconButton(
            tooltip: 'New location',
            icon: const Icon(Icons.add),
            onPressed: locations == null ? null : () => _edit(null),
          ),
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
            (final locations?, _) when _query.trim().isEmpty => [
              ..._tree(locations),
              if (locations.isEmpty && _groups.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    'No locations yet. Tap + to add one, or let compaction '
                    'add them as notes mention places.',
                    style: theme.textTheme.bodySmall,
                  ),
                ),
            ],
            (final locations?, _) => [
              for (final group in _groups)
                if (matchesSearch(_query, [group.name, group.note]))
                  _groupTile(group, path: true),
              for (final location in locations)
                if (matchesSearch(_query, [location.name, location.hint]))
                  _locationTile(location, path: true),
              if (!locations.any(
                    (l) => matchesSearch(_query, [l.name, l.hint]),
                  ) &&
                  !_groups.any((g) => matchesSearch(_query, [g.name, g.note])))
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
