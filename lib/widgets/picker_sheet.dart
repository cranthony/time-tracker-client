import 'package:flutter/material.dart';

import '../models/facts.dart';
import '../models/person.dart';
import '../models/plan_action.dart';
import '../models/proposal.dart';
import '../services/maps.dart';
import '../services/people_repository.dart';
import '../services/server_errors.dart';
import '../services/plan_memory.dart';
import 'actions_picker.dart';
import 'picker_edits.dart';
import 'picker_search.dart';

/// A sheet up from the foot of the screen, as a note's is, with room to
/// pick from a long list: [title] and Done across its top, and [body]
/// filling the rest. Done returns what [result] gives; swiping it down,
/// tapping above it, or Back, null.
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
);

/// Picks an event's actions in a [showPickerSheet]: an [ActionsPicker]
/// over the [actions], with the room to search them and show what's
/// found. Returns the ids picked, in order; null if dismissed.
///
/// With a [query] -- the event's summary, say -- the search starts with
/// it, matching any of its words, selected, with the keyboard up to type
/// over it. Where the app can (see [canEditActions]), an action can be
/// added from the sheet, and picked at once, and one long-pressed is
/// edited; then [reload] gives the actions as they are after.
Future<List<String>?> showActionsSheet(
  BuildContext context, {
  required Future<List<PlanAction>> actions,
  List<PlanAction>? loaded,
  required List<String> picked,
  required Widget Function(PlanAction action) marker,
  String? query,
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
              leavesOnly: true,
              marker: marker,
              search: search,
              autofocus: typed.isNotEmpty,
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

/// Edits an event's description in a [showPickerSheet]; returns it, or
/// null if dismissed. Blank is no description.
Future<String?> showTextSheet(
  BuildContext context, {
  required String title,
  required String? text,
  required String hint,
}) {
  var typed = text ?? '';
  return showPickerSheet<String>(
    context,
    title: title,
    result: () => typed.trim(),
    body: (context, setState) => _TextSheetField(
      text: text,
      hint: hint,
      onChanged: (changed) => typed = changed,
    ),
  );
}

/// [showTextSheet]'s field, filling the sheet: with a controller of its
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
/// With a [query] -- the event's summary, say -- each search starts with
/// it, matching any of its words. Each tab keeps its own search as it's
/// swiped away and back, and takes the keyboard as it's swiped to, what's
/// typed selected; with a [query], the first takes it at once.
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
  final repository = PeopleScope.of(context);
  final memory = PlanMemoryScope.of(context);
  var people = _people(repository, memory);
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
      void picking(Iterable<String> ids) => setState(() {
        picked
          ..clear()
          ..addAll(ids);
        other.removeAll(ids);
      });
      return ListPicker<Person>(
        items: [
          ...known,
          // Without the list, at least who's already there.
          if (snapshot.data == null)
            for (final id in {...with_, ...for_})
              if (!addedPeople.any((p) => p.id == id)) Person(id: id, name: id),
          ...addedPeople,
        ],
        id: (p) => p.id,
        label: (p) => personName(p, context: true),
        picked: [...picked],
        hint: hint,
        empty: 'No one yet.',
        search: search,
        onChanged: picking,
        onEdit: repository == null
            ? null
            : (p) async {
                if (!known.contains(p)) return;
                if (await editPerson(context, person: p) == null) return;
                setState(() => people = _people(repository, memory));
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
                  people = _people(repository, memory);
                  picking({...picked, added.id});
                },
              ),
      );
    },
  );

  // Where it was: a location, or a new one.
  Widget place(StateSetter setState, PickerSearch search) => FutureBuilder(
    future: locations,
    initialData: memory?.locations,
    builder: (context, snapshot) {
      final loaded = snapshot.data ?? const <Location>[];
      final known = [...loaded, ...addedLocations];
      return ListPicker<Location>(
        items: [
          ...known,
          for (final id in where_)
            if (!known.any((l) => l.id == id)) Location(id: id, name: id),
        ],
        id: (l) => l.id,
        label: (l) => l.name,
        detail: (l) => l.hint,
        picked: [...where_],
        hint: 'Where it was: one place, or each it moved between',

        empty: 'No locations yet.',
        search: search,
        onChanged: (ids) => setState(
          () => where_
            ..clear()
            ..addAll(ids),
        ),
        onEdit: repository == null
            ? null
            : (l) async {
                if (!loaded.contains(l)) return;
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
      facts: Facts(
        locationIds: [...where_],
        withIds: [...with_],
        forIds: [...for_],
        notes: {
          for (final MapEntry(:key, :value) in facts.notes.entries)
            if (key == selfPersonId || with_.contains(key)) key: value,
        },
      ),
      mapLocation: map,
    ),
    body: (context, setState) => where
        ? _TabbedSearches(
            tabs: const ['Location', 'Map location'],
            texts: [typed, map ?? ''],
            matchAny: typed.isNotEmpty,
            focusFirst: typed.isNotEmpty,
            pages: (searches) => [
              place(setState, searches[0]),
              FutureBuilder(
                future: locations,
                initialData: memory?.locations,
                builder: (context, snapshot) => _MapLocationPage(
                  search: searches[1],
                  fallback: _firstMap(snapshot.data, where_),
                  onChanged: (typed) => map = typed,
                ),
              ),
            ],
          )
        : _TabbedSearches(
            tabs: const ['With', 'For'],
            texts: [typed, typed],
            matchAny: typed.isNotEmpty,
            focusFirst: typed.isNotEmpty,
            pages: (searches) => [
              pick(setState, searches[0], with_, for_, 'Who was there'),
              pick(
                setState,
                searches[1],
                for_,
                with_,
                "Who it was for, who wasn't there",
              ),
            ],
          ),
  );
}

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
/// away and back, and selected as it's swiped to.
class _MapLocationPage extends StatelessWidget {
  const _MapLocationPage({
    required this.search,
    required this.onChanged,
    this.fallback,
  });

  final PickerSearch search;

  /// Its location's map location, used while it has none of its own.
  final String? fallback;
  final ValueChanged<String> onChanged;

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
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: opened.trim().isEmpty
                    ? null
                    : () => openInMaps(opened),
                icon: Icon(placeButton(opened).icon),
                label: Text(placeButton(opened).tooltip),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Everyone, from what the app has, or is loading, rather than asking
/// again; what it kept, if that fails.
Future<PeopleList>? _people(PeopleRepository? repository, PlanMemory? memory) {
  if (repository == null) return null;
  if (memory == null) return repository.people();
  return _kept(memory.loadPeople(repository), () => memory.people);
}

/// The locations, as [_people] has everyone.
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

/// Picks from a flat list of [items], as [ActionsPicker] does from the
/// actions: those [picked] as chips on top, a search over them, and the
/// list under it, each with a check. With [single], picking one replaces
/// any other, and there are no chips.
///
/// Its [search] is kept by whoever gives it, so it can start with words
/// typed, and outlive the picker. Long-pressing an item calls [onEdit]
/// with it; with [add], a row between the search and the list -- kept in
/// view as the list scrolls -- adds one, given what's typed.
class ListPicker<T> extends StatelessWidget {
  const ListPicker({
    super.key,
    required this.items,
    required this.id,
    required this.label,
    required this.picked,
    required this.onChanged,
    required this.hint,
    required this.empty,
    required this.search,
    this.detail,
    this.single = false,
    this.onEdit,
    this.add,
  });

  final List<T> items;
  final String Function(T item) id;
  final String Function(T item) label;
  final String? Function(T item)? detail;
  final List<String> picked;
  final ValueChanged<List<String>> onChanged;

  /// What the list is of, over it.
  final String hint;

  /// What's said when there's nothing to pick.
  final String empty;
  final PickerSearch search;
  final bool single;
  final ValueChanged<T>? onEdit;

  /// What one added is called, its icon, and how it's added.
  final ({String noun, IconData icon, ValueChanged<String> onAdd})? add;

  /// What [item] is searched by: its label and detail.
  String _text(T item) => '${label(item)} ${detail?.call(item) ?? ''}';

  void _toggle(String id, bool on) => onChanged(
    single
        ? [if (on) id]
        : [
            for (final other in picked)
              if (other != id) other,
            if (on) id,
          ],
  );

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: search,
    builder: (context, _) => _build(context),
  );

  Widget _build(BuildContext context) {
    final theme = Theme.of(context);
    final query = search.query;
    final shown = query.isEmpty ? items : query.filter(items, _text);
    final byId = {for (final item in items) id(item): item};
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Text(hint, style: theme.textTheme.bodySmall),
        ),
        if (!single && picked.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final picked in picked)
                  InputChip(
                    label: Text(switch (byId[picked]) {
                      final item? => label(item),
                      null => picked,
                    }),
                    onDeleted: () => _toggle(picked, false),
                  ),
              ],
            ),
          ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: PickerSearchField(
            search: search,
            // The top match, picked (or unpicked) from the keyboard.
            // What's typed now, which may not have been built yet.
            onSubmitted: (text) {
              final query = PickerQuery(text, any: search.matchAny);
              if (query.isEmpty) return;
              final top = query.filter(items, _text).firstOrNull;
              if (top == null) return;
              final topId = id(top);
              _toggle(topId, !picked.contains(topId));
              search.controller.clear();
            },
          ),
        ),
        // Above the list, not in it: always to hand.
        if (add case (:final noun, :final icon, :final onAdd))
          PickerAddTile(noun: noun, search: search, icon: icon, onAdd: onAdd),
        Expanded(
          child: _oneOf(
            ListView(
              children: [
                if (items.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(8),
                    child: Text(
                      empty,
                      style: TextStyle(color: theme.hintColor),
                    ),
                  )
                else if (shown.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(8),
                    child: Text('Nothing matches.'),
                  ),
                for (final item in shown) _editable(item, _tile(item)),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _tile(T item) => single
      // Only one: a radio button each. Tapped again, the one picked is
      // unpicked, leaving none.
      ? RadioListTile<String>(
          value: id(item),
          toggleable: true,
          controlAffinity: ListTileControlAffinity.leading,
          title: Text(label(item)),
          subtitle: _detail(item),
        )
      : CheckboxListTile(
          value: picked.contains(id(item)),
          controlAffinity: ListTileControlAffinity.leading,
          title: Text(label(item)),
          subtitle: _detail(item),
          onChanged: (on) => _toggle(id(item), on ?? false),
        );

  /// [tile], long-pressed to edit [item].
  Widget _editable(T item, Widget tile) => switch (onEdit) {
    final edit? => GestureDetector(
      key: ValueKey(id(item)),
      onLongPress: () => edit(item),
      child: tile,
    ),
    null => tile,
  };

  Widget? _detail(T item) => switch (detail?.call(item)) {
    final detail? when detail.isNotEmpty => Text(detail),
    _ => null,
  };

  /// [list], its radio buttons grouped where only one is picked.
  Widget _oneOf(Widget list) => single
      ? RadioGroup<String>(
          groupValue: picked.firstOrNull,
          onChanged: (id) => onChanged([?id]),
          child: list,
        )
      : list;
}
