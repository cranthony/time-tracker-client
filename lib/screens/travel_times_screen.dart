import 'package:flutter/material.dart';

import '../models/person.dart';
import '../models/travel_time.dart';
import '../services/actions_repository.dart';
import '../services/people_repository.dart';
import '../services/plan_memory.dart';
import '../widgets/duration_field.dart';
import '../widgets/edit_page.dart';
import '../widgets/error_sheet.dart';
import '../widgets/actions_picker.dart';
import '../widgets/picker_sheet.dart';
import '../widgets/status_message.dart';
import '../widgets/tree_picker.dart';

/// Every location and group [memory] has, groups first: the places a
/// travel time can be between.
List<PickerNode> travelPlaces(PlanMemory memory) => [
  ...locationGroupNodes(memory.locationGroups ?? const []),
  for (final l in memory.locations ?? const <Location>[]) locationNode(l),
];

/// Every action and group in use that [memory] has: the ways of getting
/// somewhere a travel time can have.
List<PickerNode> travelModes(PlanMemory memory) => [
  for (final a in memory.shownActions?.actions ?? const [])
    if (a.id != null && a.status != 'deleted' && a.status != 'archived')
      actionNode(a),
];

/// The actions in [memory] a travel time can be by: those that are a way
/// to commute.
Set<String> travelCommutes(PlanMemory memory) => {
  for (final a in memory.shownActions?.actions ?? const [])
    if (a.commute) ?a.id,
};

/// Roughly how long it takes to get between places -- each a location or a
/// location group -- by each way of getting there: an action or action
/// group, such as Drive or Transit. Tapping one edits or deletes it; "+"
/// adds one. Each counts both ways unless it's one way. Shows what
/// [memory] has while it loads afresh, with the actions from [actions].
class TravelTimesScreen extends StatefulWidget {
  const TravelTimesScreen({
    super.key,
    required this.repository,
    required this.memory,
    this.actions,
  });

  final PeopleRepository repository;
  final PlanMemory memory;
  final ActionsRepository? actions;

  @override
  State<TravelTimesScreen> createState() => _TravelTimesScreenState();
}

class _TravelTimesScreenState extends State<TravelTimesScreen> {
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool again = false}) async {
    final memory = widget.memory;
    try {
      await Future.wait([
        memory.loadTravelTimes(widget.repository, again: again),
        memory.loadLocations(widget.repository),
        if (widget.actions case final actions?) memory.loadActions(actions),
      ]);
      if (mounted) setState(() => _error = null);
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  /// Every location and group, groups first, each as its path.
  List<PickerNode> get _places => travelPlaces(widget.memory);
  List<PickerNode> get _modes => travelModes(widget.memory);

  Future<void> _edit(TravelTime? travel) async {
    final repository = widget.repository;
    final saved = await showEditPage<bool>(
      context,
      TravelTimeEditor(
        travel: travel,
        places: _places,
        modes: _modes,
        commutes: travelCommutes(widget.memory),
        save: (fields) => travel == null
            ? repository.createTravelTime(
                TravelTime.fromJson({'id': '', ...fields}),
              )
            : repository.updateTravelTime(travel.id, fields),
        delete: travel == null
            ? null
            : () => repository.deleteTravelTime(travel.id),
      ),
    );
    if (saved == true) await _load(again: true);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final travel = widget.memory.travelTimes;
    final (places, modes) = (_places, _modes);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Travel times'),
        actions: [
          IconButton(
            tooltip: 'New travel time',
            icon: const Icon(Icons.add),
            onPressed: travel == null ? null : () => _edit(null),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => _load(again: true),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.only(bottom: 24),
          children: switch ((travel, _error)) {
            (null, final error?) => [
              LoadError(
                what: 'the travel times',
                error: error,
                onRetry: () => _load(again: true),
              ),
            ],
            (null, _) => const [LinearProgressIndicator()],
            (final travel?, _) => [
              for (final t in travel)
                TravelTimeTile(
                  travel: t,
                  places: places,
                  modes: modes,
                  onTap: () => _edit(t),
                ),
              if (travel.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    'No travel times yet. Tap + to say roughly how long it '
                    'takes between two places -- or neighborhoods, or cities '
                    '-- by each way of getting there.',
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

/// [id]'s name among [choices] -- its path, if it's in a group -- or the
/// id, if it isn't among them.
String _name(String id, List<PickerNode> choices) =>
    switch (choices.where((c) => c.id == id).firstOrNull) {
      final c? => c.path ?? c.label,
      null => id,
    };

/// [travel] in a list: where it's between, with an arrow one way or both,
/// and how long each way of getting there takes, named from [places] and
/// [modes]; then its note.
class TravelTimeTile extends StatelessWidget {
  const TravelTimeTile({
    super.key,
    required this.travel,
    required this.places,
    required this.modes,
    this.onTap,
    this.dense,
    this.contentPadding,
  });

  final TravelTime travel;
  final List<PickerNode> places;
  final List<PickerNode> modes;
  final VoidCallback? onTap;
  final bool? dense;
  final EdgeInsetsGeometry? contentPadding;

  @override
  Widget build(BuildContext context) {
    final t = travel;
    return ListTile(
      dense: dense,
      contentPadding: contentPadding,
      leading: const Icon(Icons.directions_walk),
      title: Text.rich(
        TextSpan(
          children: [
            TextSpan(text: '${_name(t.fromId, places)} '),
            WidgetSpan(
              alignment: PlaceholderAlignment.middle,
              child: Icon(
                t.oneWay ? Icons.arrow_forward : Icons.sync_alt,
                size: 18,
                semanticLabel: t.oneWay ? 'to' : 'and',
              ),
            ),
            TextSpan(text: ' ${_name(t.toId, places)}'),
          ],
        ),
      ),
      subtitle: Text(
        [
          if (t.times.isNotEmpty)
            [for (final m in t.times) '${_name(m.modeId, modes)} ${m.describe}']
                .join(' · '),
          ?t.note,
        ].join('\n'),
      ),
      isThreeLine: t.times.isNotEmpty && t.note != null,
      onTap: onTap,
    );
  }
}

/// The travel times to and from [placeId] -- a location or a location
/// group -- under its edit dialog: each tapped to edit, and "Add travel
/// time", which picks the other place and opens the travel time both ways
/// between them. Loads into [memory] what it doesn't have, and the
/// actions from [actions].
class LocationTravelTimes extends StatefulWidget {
  const LocationTravelTimes({
    super.key,
    required this.placeId,
    required this.repository,
    required this.memory,
    this.actions,
  });

  final String placeId;
  final PeopleRepository repository;
  final PlanMemory memory;
  final ActionsRepository? actions;

  @override
  State<LocationTravelTimes> createState() => _LocationTravelTimesState();
}

class _LocationTravelTimesState extends State<LocationTravelTimes> {
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool again = false}) async {
    final memory = widget.memory;
    try {
      await Future.wait([
        memory.loadTravelTimes(widget.repository, again: again),
        memory.loadLocations(widget.repository),
        if (widget.actions case final actions?) memory.loadActions(actions),
      ]);
      if (mounted) setState(() => _error = null);
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  /// Edits [travel], or adds one from [fromId] to [toId].
  Future<void> _edit({TravelTime? travel, String? fromId, String? toId}) async {
    final repository = widget.repository;
    final saved = await showEditPage<bool>(
      context,
      TravelTimeEditor(
        travel: travel,
        fromId: fromId,
        toId: toId,
        places: travelPlaces(widget.memory),
        modes: travelModes(widget.memory),
        commutes: travelCommutes(widget.memory),
        save: (fields) => travel == null
            ? repository.createTravelTime(
                TravelTime.fromJson({'id': '', ...fields}),
              )
            : repository.updateTravelTime(travel.id, fields),
        delete: travel == null
            ? null
            : () => repository.deleteTravelTime(travel.id),
      ),
    );
    if (saved == true) await _load(again: true);
  }

  /// Picks the other place, then edits the travel time both ways between
  /// here and there: the one there is, or a new one, from here.
  Future<void> _add() async {
    final here = widget.placeId;
    final picked = await pickNode(
      context,
      title: 'Travel time between here and',
      nodes: [
        for (final p in travelPlaces(widget.memory))
          if (p.id != here) p,
      ],
      groupsPickable: true,
      searchHint: 'Search places',
      marker: (c) => Icon(
        c.group ? Icons.folder_outlined : Icons.place_outlined,
        size: 20,
      ),
    );
    final other = picked?.id;
    if (other == null || !mounted) return;
    final existing = widget.memory.travelTimes
        ?.where(
          (t) =>
              !t.oneWay &&
              ((t.fromId == here && t.toId == other) ||
                  (t.fromId == other && t.toId == here)),
        )
        .firstOrNull;
    await _edit(travel: existing, fromId: here, toId: other);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final here = widget.placeId;
    final travel = widget.memory.travelTimes;
    final (places, modes) = (
      travelPlaces(widget.memory),
      travelModes(widget.memory),
    );
    final mine = [
      for (final t in travel ?? const <TravelTime>[])
        if (t.fromId == here || t.toId == here) t,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Expanded(
              child: Text('Travel times', style: theme.textTheme.titleSmall),
            ),
            TextButton.icon(
              icon: const Icon(Icons.add_road, size: 18),
              label: const Text('Add travel time'),
              onPressed: travel == null ? null : _add,
            ),
          ],
        ),
        ...switch ((travel, _error)) {
          (null, final error?) => [
            LoadError(
              what: 'the travel times',
              error: error,
              onRetry: () => _load(again: true),
            ),
          ],
          (null, _) => const [
            Padding(
              padding: EdgeInsets.only(top: 8),
              child: LinearProgressIndicator(),
            ),
          ],
          (_?, _) when mine.isEmpty => [
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'No travel times to or from here yet.',
                style: theme.textTheme.bodySmall,
              ),
            ),
          ],
          (_?, _) => [
            for (final t in mine)
              TravelTimeTile(
                travel: t,
                places: places,
                modes: modes,
                dense: true,
                contentPadding: EdgeInsets.zero,
                onTap: () => _edit(travel: t),
              ),
          ],
        },
      ],
    );
  }
}

/// One way of getting there, as it's edited: its mode, and how long it
/// takes, in whole minutes -- at least, and at most if it varies.
class _Way {
  _Way([TravelMode? mode])
    : mode = mode?.modeId,
      minutes = TextEditingController(text: '${mode?.minutes ?? ''}'),
      max = TextEditingController(text: '${mode?.maxMinutes ?? ''}');

  String? mode;
  final TextEditingController minutes;
  final TextEditingController max;

  void dispose() {
    minutes.dispose();
    max.dispose();
  }
}

/// Adds a travel time (with no [travel]) or edits one, on a page of its
/// own: where it's from and to (from [places]), whether it's one way, how
/// long each way of getting there takes (each from [modes], with the
/// hours and minutes it takes, and at most, if it varies), and a note.
/// Saves with [save]; "Delete", asked first, calls [delete]. Closes with
/// true once it's saved or deleted.
class TravelTimeEditor extends StatefulWidget {
  const TravelTimeEditor({
    super.key,
    this.travel,
    required this.places,
    required this.modes,
    this.commutes = const {},
    required this.save,
    this.delete,
    this.fromId,
    this.toId,
  });

  final TravelTime? travel;

  /// Where a new one starts out from, and to.
  final String? fromId;
  final String? toId;
  final List<PickerNode> places;
  final List<PickerNode> modes;

  /// The ids among [modes] that are a way to commute: only they, the
  /// groups they're in, and what [travel] was already by are offered.
  final Set<String> commutes;
  final Future<void> Function(Map<String, Object?> fields) save;
  final Future<void> Function()? delete;

  @override
  State<TravelTimeEditor> createState() => _TravelTimeEditorState();
}

class _TravelTimeEditorState extends State<TravelTimeEditor> {
  late String? _from = widget.travel?.fromId ?? widget.fromId;
  late String? _to = widget.travel?.toId ?? widget.toId;
  late bool _oneWay = widget.travel?.oneWay ?? false;
  late final _note = TextEditingController(text: widget.travel?.note);
  late final List<_Way> _ways = [
    for (final t in widget.travel?.times ?? const <TravelMode>[]) _Way(t),
    if (widget.travel == null) _Way(),
  ];
  bool _saving = false;

  /// What a way can be by: the commute actions and what [travel] was
  /// already by, with the groups they're in.
  late final List<PickerNode> _modes = () {
    final byId = {for (final m in widget.modes) m.id: m};
    final offered = <String>{};
    for (final id in {
      ...widget.commutes,
      for (final t in widget.travel?.times ?? const <TravelMode>[]) t.modeId,
    }) {
      // Up through its groups, until one's already offered.
      for (var at = byId[id]; at != null && offered.add(at.id);) {
        at = byId[at.parentId];
      }
    }
    return [
      for (final m in widget.modes)
        if (offered.contains(m.id)) m,
    ];
  }();

  @override
  void dispose() {
    _note.dispose();
    for (final w in _ways) {
      w.dispose();
    }
    super.dispose();
  }

  static int? _whole(TextEditingController c) => int.tryParse(c.text.trim());

  /// What's wrong with it as it is, if anything.
  String? get _problem {
    if (_from == null || _to == null) return "Pick where it's from and to.";
    if (_from == _to) return 'Pick two different places.';
    for (final (i, w) in _ways.indexed) {
      if (w.mode == null) return 'Pick how each way gets there.';
      if (_ways.take(i).any((o) => o.mode == w.mode)) {
        return 'Give each way of getting there once.';
      }
      final minutes = _whole(w.minutes);
      if (minutes == null || minutes <= 0) {
        return 'Say how long each way takes.';
      }
      if (w.max.text.trim().isNotEmpty) {
        final max = _whole(w.max);
        if (max == null || max < minutes) {
          return '"Up to" is at least what it takes.';
        }
      }
    }
    return null;
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final saved = await runOrShowError(
      context,
      title: "Couldn't save",
      action: () => widget.save({
        'from_id': _from,
        'to_id': _to,
        'one_way': _oneWay,
        'times': [
          for (final w in _ways)
            TravelMode(
              modeId: w.mode!,
              minutes: _whole(w.minutes)!,
              maxMinutes: switch (_whole(w.max)) {
                final max? when max != _whole(w.minutes) => max,
                _ => null,
              },
            ).toJson(),
        ],
        'note': _note.text.trim().isEmpty ? null : _note.text.trim(),
      }),
    );
    if (!mounted) return;
    setState(() => _saving = false);
    if (saved) Navigator.of(context).pop(true);
  }

  Future<void> _delete() async {
    final sure = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete this travel time?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Keep it'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (sure != true || !mounted) return;
    final deleted = await runOrShowError(
      context,
      title: "Couldn't delete",
      action: widget.delete!,
    );
    if (deleted && mounted) Navigator.of(context).pop(true);
  }

  /// A place or a way of getting there, picked from [choices] -- a
  /// group, or anything in one; one that isn't among them, by its id.
  Widget _picker({
    required String label,
    required String? value,
    required List<PickerNode> choices,
    required ValueChanged<String?> onChanged,
    IconData place = Icons.place_outlined,
    String searchHint = 'Search places',
  }) => PickerField(
    label: label,
    nodes: choices,
    value: value,
    groupsPickable: true,
    searchHint: searchHint,
    marker: (c) => Icon(c.group ? Icons.folder_outlined : place, size: 20),
    onChanged: onChanged,
  );

  Widget _way(ThemeData theme, _Way way) => Card.outlined(
    margin: const EdgeInsets.only(top: 12),
    child: Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 4, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: _picker(
                  label: 'By',
                  value: way.mode,
                  choices: _modes,
                  place: Icons.directions,
                  searchHint: 'Search actions',
                  onChanged: (picked) => setState(() => way.mode = picked),
                ),
              ),
              IconButton(
                tooltip: 'Remove this way',
                icon: const Icon(Icons.delete_outline),
                onPressed: () => setState(() {
                  _ways.remove(way);
                  way.dispose();
                }),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: DurationField(
              controller: way.minutes,
              label: 'Takes',
              step: 5,
              onChanged: () => setState(() {}),
            ),
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: DurationField(
              controller: way.max,
              label: 'Up to (optional)',
              step: 5,
              onChanged: () => setState(() {}),
            ),
          ),
        ],
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final places = widget.places;
    String name(String? id) =>
        switch (places.where((p) => p.id == id).firstOrNull) {
          final p? => p.path ?? p.label,
          null => 'there',
        };
    return EditPage(
      title: widget.travel == null ? 'New travel time' : 'Edit travel time',
      problem: _problem,
      saving: _saving,
      onSave: _save,
      actions: [
        if (widget.delete != null)
          IconButton(
            tooltip: 'Delete',
            icon: const Icon(Icons.delete_outline),
            onPressed: _saving ? null : _delete,
          ),
      ],
      children: [
        _picker(
          label: 'From',
          value: _from,
          choices: places,
          onChanged: (picked) => setState(() => _from = picked),
        ),
        Align(
          child: IconButton(
            tooltip: 'Switch from and to',
            icon: const Icon(Icons.swap_vert),
            onPressed: () => setState(() {
              final from = _from;
              _from = _to;
              _to = from;
            }),
          ),
        ),
        _picker(
          label: 'To',
          value: _to,
          choices: places,
          onChanged: (picked) => setState(() => _to = picked),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('One way only'),
          subtitle: Text(
            _oneWay
                ? 'Only from ${name(_from)} to ${name(_to)}: give the way '
                      'back its own travel time.'
                : 'It takes as long both ways.',
          ),
          value: _oneWay,
          onChanged: (on) => setState(() => _oneWay = on),
        ),
        Text('Ways of getting there', style: theme.textTheme.titleSmall),
        if (widget.commutes.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              'Only actions that are a way to commute can be picked: turn '
              "that on for one, such as Drive, in the Plan page's Actions.",
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        for (final way in _ways) _way(theme, way),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: TextButton.icon(
            icon: const Icon(Icons.add),
            label: const Text('Add a way'),
            onPressed: () => setState(() => _ways.add(_Way())),
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _note,
          minLines: 1,
          maxLines: 3,
          decoration: const InputDecoration(
            labelText: 'Note (optional)',
            hintText: 'e.g. "worse at rush hour"',
            border: OutlineInputBorder(),
            isDense: true,
          ),
        ),
      ],
    );
  }
}
