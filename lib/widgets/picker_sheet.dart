import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/facts.dart';
import '../models/person.dart';
import '../models/plan_action.dart';
import '../models/proposal.dart';
import '../models/share.dart';
import '../services/maps.dart';
import '../services/people_repository.dart';
import '../services/server_errors.dart';
import '../services/plan_memory.dart';
import 'actions_picker.dart';
import 'event_description.dart';
import 'hotkeys.dart';
import 'picker_edits.dart';
import 'picker_search.dart';
import 'share_dialog.dart';
import 'tree_picker.dart';

/// A sheet up from the foot of the screen, as a note's is, with room to
/// pick from a long list: [title] and Done across its top, and [body]
/// filling the rest. Done -- or Ctrl+Enter -- returns what [result] gives;
/// swiping it down, tapping above it, or Back, null.
Future<T?> showPickerSheet<T>(
  BuildContext context, {
  required String title,
  required Widget Function(BuildContext context, StateSetter setState) body,
  required T Function() result,
}) => showModalBottomSheet<T>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  showDragHandle: true,
  builder: (context) => FractionallySizedBox(
    heightFactor: 0.9,
    child: Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SaveHotkey(
        onSave: () => Navigator.of(context).pop(result()),
        child: StatefulBuilder(
          builder: (context, setState) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 12, 4),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                    FilledButton(
                      onPressed: () => Navigator.of(context).pop(result()),
                      child: const Text('Done'),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: body(context, setState),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  ),
);

/// Picks an event's actions in a [showPickerSheet]: an [ActionsPicker]
/// over the [actions], every group open, with the room to search them
/// and show what's found -- only actions, not groups, unless not
/// [leavesOnly]. Returns the ids picked, in order; null if dismissed.
///
/// The keyboard comes up to search at once. With a [query] -- the
/// event's summary, say -- the search starts with it, matching any of
/// its words, selected, to type over it. Where the app can (see [canEditActions]), an action can be
/// added from the sheet, and picked at once, and one long-pressed is
/// edited; then [reload] gives the actions as they are after.
Future<List<String>?> showActionsSheet(
  BuildContext context, {
  required Future<List<PlanAction>> actions,
  List<PlanAction>? loaded,
  required List<String> picked,
  required Widget Function(PlanAction action) marker,
  String? query,
  bool leavesOnly = true,
  Future<List<PlanAction>> Function()? reload,
}) {
  var ids = [...picked];
  var listed = actions;
  final editable = reload != null && canEditActions(context);
  final typed = query?.trim() ?? '';
  return showPickerSheet(
    context,
    title: 'Actions',
    result: () => ids,
    body: (context, setState) => _OwnSearch(
      text: typed,
      matchAny: typed.isNotEmpty,
      builder: (context, search) => FutureBuilder(
        future: listed,
        initialData: loaded,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Text(
              "Couldn't load actions. "
              '${describeServerError(snapshot.error!).message}',
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            );
          }
          final list = snapshot.data;
          if (list == null) {
            return const Align(
              alignment: Alignment.topCenter,
              child: LinearProgressIndicator(),
            );
          }
          return LayoutBuilder(
            builder: (context, constraints) => ActionsPicker(
              actions: list,
              picked: ids,
              leavesOnly: leavesOnly,
              marker: marker,
              search: search,
              autofocus: true,
              onChanged: (changed) => setState(() => ids = changed),
              onEdit: !editable
                  ? null
                  : (action) async {
                      if (await editAction(context, action)) {
                        setState(() => listed = reload());
                      }
                    },
              onAdd: !editable
                  ? null
                  : (name) async {
                      final id = await addAction(context, name);
                      if (id == null) return;
                      search.controller.clear();
                      setState(() {
                        listed = reload();
                        if (!ids.contains(id)) ids = [...ids, id];
                      });
                    },
              // The rest of the sheet, under the chips, the search and
              // the row to add one.
              maxListHeight: constraints.maxHeight - (editable ? 170 : 120),
            ),
          );
        },
      ),
    ),
  );
}

/// Shows an event's description in a [showPickerSheet], as its HTML lays
/// it out, links tappable and its text selectable by touching and holding
/// it ([EventDescription]); the pencil at its foot -- or E -- edits it,
/// as typed. Blank, it's edited at once. Returns it as edited, or null if
/// it wasn't, or the sheet was dismissed. Blank is no description.
/// Ctrl+Enter saves it and closes; Esc, in the field, leaves it; out of
/// it, Esc closes, but once it's been changed, the first Esc only warns,
/// and the second discards it ([SaveOrDiscard]).
Future<String?> showTextSheet(
  BuildContext context, {
  required String title,
  required String? text,
  required String hint,
}) {
  String? typed;
  return showPickerSheet<String?>(
    context,
    title: title,
    result: () => typed?.trim(),
    body: (context, setState) => _TextSheetBody(
      text: text,
      hint: hint,
      onChanged: (changed) => typed = changed,
    ),
  );
}

/// [showTextSheet]'s body: [text] to read, with a pencil at the foot that
/// turns it into a field to edit it in -- or, blank, the field at once.
class _TextSheetBody extends StatefulWidget {
  const _TextSheetBody({
    required this.text,
    required this.hint,
    required this.onChanged,
  });

  final String? text;
  final String hint;
  final ValueChanged<String> onChanged;

  @override
  State<_TextSheetBody> createState() => _TextSheetBodyState();
}

class _TextSheetBodyState extends State<_TextSheetBody> {
  late var _editing = widget.text?.trim().isEmpty ?? true;

  /// What's typed, once anything is.
  String? _typed;

  bool get _changed =>
      _typed != null && _typed!.trim() != (widget.text ?? '').trim();

  @override
  Widget build(BuildContext context) => SaveOrDiscard(
    changed: () => _changed,
    onSave: () => Navigator.of(context).pop(_changed ? _typed!.trim() : null),
    more: [
      if (!_editing)
        HotkeyBinding(
          const HotkeyTrigger.key(LogicalKeyboardKey.keyE),
          () => setState(() => _editing = true),
        ),
    ],
    child: _body(context),
  );

  Widget _body(BuildContext context) {
    if (_editing) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: _TextSheetField(
          text: widget.text,
          hint: widget.hint,
          onChanged: (typed) {
            widget.onChanged(typed);
            setState(() => _typed = typed);
          },
        ),
      );
    }
    return Stack(
      children: [
        Positioned.fill(
          child: SingleChildScrollView(
            // Room at the foot for the pencil, over the last of it.
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 88),
            child: EventDescription(
              widget.text!,
              maxLines: null,
              selectable: true,
            ),
          ),
        ),
        PositionedDirectional(
          end: 0,
          bottom: 16,
          child: HotkeyHint(
            Hotkey.editText,
            child: FloatingActionButton(
              heroTag: null,
              tooltip: 'Edit',
              onPressed: () => setState(() => _editing = true),
              child: const Icon(Icons.edit),
            ),
          ),
        ),
      ],
    );
  }
}

/// [_TextSheetBody]'s field, filling the sheet: with a controller of its
/// own, kept as long as the sheet is, closing and all.
class _TextSheetField extends StatefulWidget {
  const _TextSheetField({
    required this.text,
    required this.hint,
    required this.onChanged,
  });

  final String? text;
  final String hint;
  final ValueChanged<String> onChanged;

  @override
  State<_TextSheetField> createState() => _TextSheetFieldState();
}

class _TextSheetFieldState extends State<_TextSheetField> {
  late final _controller = TextEditingController(text: widget.text);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => TextField(
    controller: _controller,
    autofocus: true,
    expands: true,
    minLines: null,
    maxLines: null,
    textAlignVertical: TextAlignVertical.top,
    keyboardType: TextInputType.multiline,
    textCapitalization: TextCapitalization.sentences,
    decoration: InputDecoration(
      hintText: widget.hint,
      border: const OutlineInputBorder(),
    ),
    onChanged: widget.onChanged,
  );
}

/// Picks who an event was with and who it was for, in a
/// [showPickerSheet], a tab each -- or, [where], where it was, its
/// location -- each a search over a [ListPicker]. The rest of [facts] --
/// the notes, and the other of who or where -- kept. Returns them; null
/// if dismissed. The people and locations come from the [PeopleScope],
/// as [showFactsDialog]'s do, with those a compaction proposal adds --
/// its [additions], by their refs, marked new. Someone, or a location,
/// can be added from here, and picked at once; one long-pressed is
/// edited.
///
/// [withCaption] and [forCaption] say what each tab is -- an event's,
/// by default; a goal's, say.
///
/// With a [query] -- the event's summary, say -- each search starts with
/// it, matching any of its words. Each tab keeps its own search as it's
/// swiped away and back, and takes the keyboard as it's swiped to, what's
/// typed selected; the first takes it at once.
///
/// Where, there's a second page, swiped to: its [mapLocation], the place
/// as a maps app would find it, to see and edit in full -- or, without
/// one, its location's, shown as a hint. It's returned as typed, or as it
/// was.
Future<({Facts facts, String? mapLocation})?> showWhoWhereSheet(
  BuildContext context,
  Facts facts, {
  bool where = false,
  String? mapLocation,
  String? query,
  List<ProposalAddition> additions = const [],
  int? eventMinutes,
  String withCaption = 'Who was there',
  String forCaption = "Who it was for, who wasn't there",
}) {
  var map = mapLocation;
  final typed = query?.trim() ?? '';
  final addedPeople = [
    for (final a in additions)
      if (a.kind == AdditionKind.person)
        Person(id: a.ref, name: '${a.name} (new)', context: a.detail),
  ];
  final addedLocations = [
    for (final a in additions)
      if (a.kind == AdditionKind.location)
        Location(id: a.ref, name: '${a.name} (new)', hint: a.detail),
  ];
  final with_ = {...facts.withIds}..remove(selfPersonId);
  final for_ = {...facts.forIds}..remove(selfPersonId);
  final where_ = [...facts.locationIds];
  // How much of it each takes, for those given minutes or a percent.
  var withSplits = facts.withSplits;
  var forSplits = facts.forSplits;
  var whereSplits = facts.locationSplits;
  final minutes = eventMinutes;

  // Sets how much of it [share]'s person or place takes, called [name].
  Future<S?> setShare<S extends Share>(
    S share,
    String name,
    String kind,
    String rest,
    S Function(int? minutes, int? percent, bool remaining) make,
  ) async {
    if (minutes == null) return null;
    return showShareDialog(
      context,
      title: name,
      share: share,
      eventMinutes: minutes,
      kind: kind,
      rest: rest,
      make: make,
    );
  }

  final repository = PeopleScope.of(context);
  final memory = PlanMemoryScope.of(context);
  var people = knownPeople(repository, memory);
  var locations = _locations(repository, memory);

  // Who it was with, or for: everyone to pick from, [picked] picked;
  // picking one takes them out of [other], since no one is both.
  Widget pick(
    StateSetter setState,
    PickerSearch search,
    Set<String> picked,
    Set<String> other,
    String hint,
  ) => FutureBuilder(
    future: people,
    initialData: memory?.people,
    builder: (context, snapshot) {
      final known = [
        for (final p in snapshot.data?.withSelf ?? const <Person>[])
          if (!p.isSelf &&
              (p.active || with_.contains(p.id) || for_.contains(p.id)))
            p,
      ];
      final byId = {for (final p in known) p.id: p};
      void picking(Iterable<String> ids) => setState(() {
        picked
          ..clear()
          ..addAll(ids);
        other.removeAll(ids);
      });
      final isWith = identical(picked, with_);
      Map<String, PersonShare> splits() => isWith ? withSplits : forSplits;
      return TreePicker(
        nodes: [
          for (final p in [
            ...known,
            // Without the list, at least who's already there.
            if (snapshot.data == null)
              for (final id in {...with_, ...for_})
                if (!addedPeople.any((p) => p.id == id))
                  Person(id: id, name: id),
            ...addedPeople,
          ])
            PickerNode(id: p.id, label: personName(p, context: true)),
        ],
        picked: [...picked],
        caption: hint,
        empty: 'No one yet.',
        search: search,
        onChanged: picking,
        chipDetail: minutes == null
            ? null
            : (id) => splits()[id]?.label ?? 'The rest',
        onChipTap: minutes == null
            ? null
            : (id) async {
                final set = await setShare(
                  splits()[id] ?? PersonShare(id),
                  switch (byId[id]) {
                    final p? => personName(p),
                    null => id,
                  },
                  'person',
                  "They take the time the others' durations and percents "
                      'leave, as everyone given neither does.',
                  (minutes, percent, remaining) => PersonShare(
                    id,
                    minutes: minutes,
                    percent: percent,
                    remaining: remaining,
                  ),
                );
                if (set == null) return;
                setState(() {
                  if (isWith) {
                    withSplits = Facts.withSplit(withSplits, set);
                  } else {
                    forSplits = Facts.withSplit(forSplits, set);
                  }
                });
              },
        onEdit: repository == null
            ? null
            : (node) async {
                final p = byId[node.id];
                if (p == null) return;
                if (await editPerson(context, person: p) == null) return;
                setState(() => people = knownPeople(repository, memory));
              },
        add: repository == null
            ? null
            : (
                noun: 'person',
                icon: Icons.person_add_alt,
                onAdd: (name) async {
                  final added = await editPerson(context, name: name);
                  if (added == null) return;
                  search.controller.clear();
                  people = knownPeople(repository, memory);
                  picking({...picked, added.id});
                },
              ),
      );
    },
  );

  // Where it was: the locations it was at, in their groups -- which
  // can't be picked themselves -- or a new one.
  Widget place(StateSetter setState, PickerSearch search) => FutureBuilder(
    future: locations,
    initialData: memory?.locations,
    builder: (context, snapshot) {
      final loaded = snapshot.data ?? const <Location>[];
      final byId = {for (final l in loaded) l.id: l};
      final known = [...loaded, ...addedLocations];
      return TreePicker(
        nodes: [
          ...locationGroupNodes(memory?.locationGroups ?? const []),
          for (final l in [
            ...known,
            for (final id in where_)
              if (!known.any((l) => l.id == id)) Location(id: id, name: id),
          ])
            locationNode(l),
        ],
        picked: [...where_],
        caption: 'Where it was: one place, or each it moved between',
        empty: 'No locations yet.',
        search: search,
        chipDetail: minutes == null
            ? null
            : (id) => whereSplits[id]?.label ?? 'The rest',
        onChipTap: minutes == null
            ? null
            : (id) async {
                final set = await setShare(
                  whereSplits[id] ?? LocationShare(id),
                  byId[id]?.name ?? id,
                  'location',
                  "It shares the time the other places' durations and "
                      'percents leave evenly with the others given neither.',
                  (minutes, percent, remaining) => LocationShare(
                    id,
                    minutes: minutes,
                    percent: percent,
                    remaining: remaining,
                  ),
                );
                if (set == null) return;
                setState(() => whereSplits = Facts.withSplit(whereSplits, set));
              },
        onChanged: (ids) => setState(
          () => where_
            ..clear()
            ..addAll(ids),
        ),
        onEdit: repository == null
            ? null
            : (node) async {
                final l = byId[node.id];
                if (l == null) return;
                if (await editLocation(context, location: l) == null) return;
                setState(() => locations = _locations(repository, memory));
              },
        add: repository == null
            ? null
            : (
                noun: 'location',
                icon: Icons.add_location_alt,
                onAdd: (name) async {
                  final added = await editLocation(context, name: name);
                  if (added == null) return;
                  search.controller.clear();
                  setState(() {
                    if (!where_.contains(added.id)) where_.add(added.id);
                    locations = _locations(repository, memory);
                  });
                },
              ),
      );
    },
  );

  return showPickerSheet<({Facts facts, String? mapLocation})>(
    context,
    title: where ? 'Location' : 'Who',
    result: () => (
      facts: facts.copyWith(
        locationIds: [...where_],
        withIds: [...with_],
        forIds: [...for_],
        notes: {
          for (final MapEntry(:key, :value) in facts.notes.entries)
            if (key == selfPersonId || with_.contains(key)) key: value,
        },
        locationSplits: whereSplits,
        withSplits: withSplits,
        forSplits: forSplits,
      ),
      mapLocation: map,
    ),
    body: (context, setState) => where
        ? _TabbedSearches(
            tabs: const ['Location', 'Map location'],
            texts: [typed, map ?? ''],
            matchAny: typed.isNotEmpty,
            focusFirst: true,
            pages: (searches) => [
              place(setState, searches[0]),
              FutureBuilder(
                future: locations,
                initialData: memory?.locations,
                builder: (context, snapshot) => _MapLocationPage(
                  search: searches[1],
                  fallback: _firstMap(snapshot.data, where_),
                  onChanged: (typed) => map = typed,
                  onAssign: repository == null
                      ? null
                      : (typed) async {
                          final assigned = await _pickMapLocationHolder(
                            context,
                            map: typed,
                            locations: locations,
                            loaded: memory?.locations,
                            groups: memory?.locationGroups ?? const [],
                          );
                          if (assigned == null) return;
                          // The location has it now: it's at that, with
                          // none of its own.
                          searches[1].controller.clear();
                          setState(() {
                            map = '';
                            if (!where_.contains(assigned.id)) {
                              where_.add(assigned.id);
                            }
                            locations = _locations(repository, memory);
                          });
                        },
                ),
              ),
            ],
          )
        : _TabbedSearches(
            tabs: const ['With', 'For'],
            texts: [typed, typed],
            matchAny: typed.isNotEmpty,
            focusFirst: true,
            pages: (searches) => [
              pick(setState, searches[0], with_, for_, withCaption),
              pick(setState, searches[1], for_, with_, forCaption),
            ],
          ),
  );
}

/// Picks the location to give [map] -- an event's map location -- in a
/// [showPickerSheet] of its own, over the event's: one of [locations]
/// (what [loaded] has, till they are), in their [groups], tapped; or a
/// new one, named as it's typed, [map] its map location to start with.
/// See [assignMapLocation] for one that has its own. Returns the
/// location, as saved; null if it's dismissed, or called off.
Future<Location?> _pickMapLocationHolder(
  BuildContext context, {
  required String map,
  required Future<List<Location>>? locations,
  List<Location>? loaded,
  List<LocationGroup> groups = const [],
}) => showPickerSheet<Location?>(
  context,
  title: 'Assign to a location',
  result: () => null,
  body: (context, _) => _OwnSearch(
    text: '',
    matchAny: false,
    builder: (context, search) => FutureBuilder(
      future: locations,
      initialData: loaded,
      builder: (context, snapshot) {
        final byId = {for (final l in snapshot.data ?? const []) l.id: l};
        void done(Location? assigned) {
          if (assigned != null && context.mounted) {
            Navigator.of(context).pop(assigned);
          }
        }

        return TreePicker(
          nodes: [
            ...locationGroupNodes(groups),
            for (final l in byId.values) locationNode(l),
          ],
          picked: const [],
          single: true,
          autofocus: true,
          caption: 'The location to give "$map" to, as its map location',
          empty: 'No locations yet.',
          search: search,
          onChanged: (ids) async {
            final l = byId[ids.firstOrNull];
            if (l == null) return;
            done(await assignMapLocation(context, l, map));
          },
          add: (
            noun: 'location',
            icon: Icons.add_location_alt,
            onAdd: (name) async =>
                done(await editLocation(context, name: name, mapLocation: map)),
          ),
        );
      },
    ),
  ),
);

/// The map location of the first of [ids] in [locations] to have one.
String? _firstMap(List<Location>? locations, List<String> ids) => [
  for (final id in ids)
    ?locations?.where((l) => l.id == id).firstOrNull?.mapLocation,
].firstOrNull;

/// A [PickerSearch] of its own for what [builder] builds, kept as long as
/// it is, starting with [text]; [matchAny] as given.
class _OwnSearch extends StatefulWidget {
  const _OwnSearch({
    required this.text,
    required this.matchAny,
    required this.builder,
  });

  final String text;
  final bool matchAny;
  final Widget Function(BuildContext context, PickerSearch search) builder;

  @override
  State<_OwnSearch> createState() => _OwnSearchState();
}

class _OwnSearchState extends State<_OwnSearch> {
  late final _search = PickerSearch(
    text: widget.text,
    matchAny: widget.matchAny,
  );

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _search);
}

/// Pages swiped between under a tab each, each with a [PickerSearch] of
/// its own -- starting with its [texts], [matchAny] as given -- kept as
/// they're swiped away and back. Each takes the keyboard as it's swiped
/// to, what's typed in it selected; with [focusFirst], the first does at
/// once.
class _TabbedSearches extends StatefulWidget {
  const _TabbedSearches({
    required this.tabs,
    required this.texts,
    required this.matchAny,
    required this.focusFirst,
    required this.pages,
  });

  final List<String> tabs;
  final List<String> texts;
  final bool matchAny;
  final bool focusFirst;
  final List<Widget> Function(List<PickerSearch> searches) pages;

  @override
  State<_TabbedSearches> createState() => _TabbedSearchesState();
}

class _TabbedSearchesState extends State<_TabbedSearches>
    with SingleTickerProviderStateMixin {
  late final _searches = [
    for (final text in widget.texts)
      PickerSearch(text: text, matchAny: widget.matchAny),
  ];
  late final _tabs = TabController(length: widget.tabs.length, vsync: this)
    ..addListener(_swiped);
  var _shown = 0;

  @override
  void initState() {
    super.initState();
    if (widget.focusFirst) _focus(0);
  }

  /// Once a page is settled on, its search takes the keyboard.
  void _swiped() {
    if (_tabs.indexIsChanging || _tabs.index == _shown) return;
    _shown = _tabs.index;
    _focus(_shown);
  }

  /// After this frame, once [index]'s page is built.
  void _focus(int index) => WidgetsBinding.instance.addPostFrameCallback((_) {
    if (mounted && _tabs.index == index) _searches[index].focusAll();
  });

  @override
  void dispose() {
    _tabs.dispose();
    for (final search in _searches) {
      search.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      TabBar(
        controller: _tabs,
        tabs: [for (final tab in widget.tabs) Tab(text: tab)],
      ),
      Expanded(
        child: TabBarView(controller: _tabs, children: widget.pages(_searches)),
      ),
    ],
  );
}

/// The place an event was, as a maps app would find it -- an address,
/// or a place's name -- to type in full, and open in Maps; or a link, to
/// open. Typed in [search]'s box, so it's kept as the page is swiped
/// away and back, and selected as it's swiped to. With [onAssign], what's
/// typed can be given to a location.
class _MapLocationPage extends StatelessWidget {
  const _MapLocationPage({
    required this.search,
    required this.onChanged,
    this.fallback,
    this.onAssign,
  });

  final PickerSearch search;

  /// Its location's map location, used while it has none of its own.
  final String? fallback;
  final ValueChanged<String> onChanged;

  /// Gives a location what's typed, as its map location.
  final ValueChanged<String>? onAssign;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final controller = search.controller;
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final fallback = this.fallback?.trim() ?? '';
        final typed = controller.text.trim();
        final opened = typed.isEmpty ? fallback : controller.text;
        return ListView(
          padding: const EdgeInsets.symmetric(vertical: 12),
          children: [
            Text(
              'Where it was, as a maps app would find it: an address, or a '
              "place's name -- or a link, to a map or a video call, say. "
              'Kept apart from the location on the other page.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              focusNode: search.focus,
              minLines: 3,
              maxLines: null,
              keyboardType: TextInputType.multiline,
              textCapitalization: TextCapitalization.words,
              decoration: InputDecoration(
                hintText: fallback.isEmpty
                    ? 'e.g. 1600 Amphitheatre Pkwy, Mountain View'
                    : "The location's: $fallback",
                border: const OutlineInputBorder(),
                suffixIcon: controller.text.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Clear',
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          controller.clear();
                          onChanged('');
                        },
                      ),
              ),
              onChanged: onChanged,
            ),
            const SizedBox(height: 8),
            Wrap(
              alignment: WrapAlignment.end,
              spacing: 8,
              children: [
                if (onAssign case final onAssign?)
                  TextButton.icon(
                    onPressed: typed.isEmpty ? null : () => onAssign(typed),
                    icon: const Icon(Icons.add_location_alt_outlined),
                    label: const Text('Assign to a location'),
                  ),
                TextButton.icon(
                  onPressed: opened.trim().isEmpty
                      ? null
                      : () => openInMaps(opened),
                  icon: Icon(placeButton(opened).icon),
                  label: Text(placeButton(opened).tooltip),
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}

/// Everyone, from what the app has, or is loading, rather than asking
/// again; what it kept, if that fails.
Future<PeopleList>? knownPeople(
  PeopleRepository? repository,
  PlanMemory? memory,
) {
  if (repository == null) return null;
  if (memory == null) return repository.people();
  return _kept(memory.loadPeople(repository), () => memory.people);
}

/// The locations, as [knownPeople] has everyone.
Future<List<Location>>? _locations(
  PeopleRepository? repository,
  PlanMemory? memory, {
  bool again = false,
}) {
  if (repository == null) return null;
  if (memory == null) return repository.locations();
  return _kept(
    memory.loadLocations(repository, again: again),
    () => memory.locations,
  );
}

/// What [loading] leaves [kept], or what it kept already, if it fails.
Future<T> _kept<T>(Future<void> loading, T? Function() kept) async {
  try {
    await loading;
  } catch (_) {
    if (kept() case final had?) return had;
    rethrow;
  }
  return kept() as T;
}

/// One of [nodes], or with [none], none: [label] over it, and in it, the
/// one picked, by its path. Tapped, it opens a sheet up from the foot to
/// search and browse them ([pickNode]), as an event's actions are picked:
/// tapping one
/// picks it and closes the sheet. With [groupsPickable], a group is picked
/// as anything else is, its arrow opening it; otherwise tapping a group
/// opens it. [marker] goes before a name.
class PickerField extends StatelessWidget {
  const PickerField({
    super.key,
    required this.label,
    required this.nodes,
    required this.value,
    required this.onChanged,
    this.none,
    this.groupsPickable = false,
    this.marker,
    this.searchHint = 'Search',
  });

  final String label;
  final List<PickerNode> nodes;
  final String? value;
  final ValueChanged<String?> onChanged;
  final String? none;
  final bool groupsPickable;
  final Widget Function(PickerNode node)? marker;
  final String searchHint;

  Future<void> _pick(BuildContext context) async {
    final picked = await pickNode(
      context,
      title: label,
      nodes: nodes,
      value: value,
      none: none,
      groupsPickable: groupsPickable,
      marker: marker,
      searchHint: searchHint,
    );
    if (picked != null && picked.id != value) onChanged(picked.id);
  }

  @override
  Widget build(BuildContext context) {
    final node = nodes.where((n) => n.id == value).firstOrNull;
    return InkWell(
      borderRadius: BorderRadius.circular(4),
      onTap: () => _pick(context),
      child: InputDecorator(
        isEmpty: value == null && none == null,
        decoration: InputDecoration(
          labelText: label,
          isDense: true,
          border: const OutlineInputBorder(),
          suffixIcon: const Icon(Icons.arrow_drop_down),
        ),
        child: switch (value) {
          null => Text(none ?? ''),
          final id => Row(
            children: [
              if ((marker, node) case (final marker?, final node?)) ...[
                marker(node),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: Text(
                  node?.path ?? node?.label ?? id,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        },
      ),
    );
  }
}

/// Picks one of [nodes] in a [showPickerSheet] under [title], searched as
/// [searchHint] says, [value] picked to start with: the one picked (null
/// for [none]), or null if it's dismissed. Every group starts open, and
/// the keyboard comes up to search; with a [query], the search starts
/// with it, selected, to type over.
Future<({String? id})?> pickNode(
  BuildContext context, {
  required String title,
  required List<PickerNode> nodes,
  String? value,
  String? none,
  bool groupsPickable = false,
  Widget Function(PickerNode node)? marker,
  String searchHint = 'Search',
  String? query,
}) => showPickerSheet<({String? id})>(
  context,
  title: title,
  result: () => (id: value),
  body: (context, _) => _OwnSearch(
    text: query?.trim() ?? '',
    matchAny: query?.trim().isNotEmpty ?? false,
    builder: (context, search) => TreePicker(
      nodes: nodes,
      picked: [?value],
      single: true,
      groupsPickable: groupsPickable,
      none: none,
      search: search,
      searchHint: searchHint,
      autofocus: true,
      marker: marker,
      onChanged: (ids) => Navigator.of(context).pop((id: ids.firstOrNull)),
    ),
  ),
);

/// Picks any of [nodes] in a [showPickerSheet] under [title], as
/// [pickNode] picks one: [picked] to start with, every group open, the
/// keyboard up to search -- starting with a [query], if any, selected.
/// The picked show as chips on top. Done returns the ids picked, in the
/// order they were; null if it's dismissed.
Future<List<String>?> pickNodes(
  BuildContext context, {
  required String title,
  required List<PickerNode> nodes,
  required List<String> picked,
  bool groupsPickable = false,
  Widget Function(PickerNode node)? marker,
  String searchHint = 'Search',
  String empty = 'Nothing yet.',
  String? query,
}) {
  var ids = [...picked];
  final typed = query?.trim() ?? '';
  return showPickerSheet<List<String>>(
    context,
    title: title,
    result: () => ids,
    body: (context, setState) => _OwnSearch(
      text: typed,
      matchAny: typed.isNotEmpty,
      builder: (context, search) => TreePicker(
        nodes: nodes,
        picked: ids,
        groupsPickable: groupsPickable,
        search: search,
        searchHint: searchHint,
        empty: empty,
        autofocus: true,
        marker: marker,
        onChanged: (changed) => setState(() => ids = changed),
      ),
    ),
  );
}

/// [location] as a [TreePicker] shows it: by its name, in its group.
PickerNode locationNode(Location location) => PickerNode(
  id: location.id,
  label: location.name,
  parentId: location.groupId,
  path: location.path,
  detail: location.hint,
);

/// [groups] as a [TreePicker] shows them: folders.
List<PickerNode> locationGroupNodes(List<LocationGroup> groups) => [
  for (final g in groups)
    PickerNode(
      id: g.id,
      label: g.name,
      parentId: g.groupId,
      path: g.path,
      detail: g.note,
      group: true,
    ),
];
