import 'package:flutter/material.dart';

import '../models/facts.dart';
import '../models/person.dart';
import '../models/plan_action.dart';
import '../models/proposal.dart';
import '../services/people_repository.dart';
import '../services/server_errors.dart';
import '../services/plan_memory.dart';
import 'actions_picker.dart';
import 'person_dialog.dart';

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
Future<List<String>?> showActionsSheet(
  BuildContext context, {
  required Future<List<PlanAction>> actions,
  List<PlanAction>? loaded,
  required List<String> picked,
  required Widget Function(PlanAction action) marker,
}) {
  var ids = [...picked];
  return showPickerSheet(
    context,
    title: 'Actions',
    result: () => ids,
    body: (context, setState) => FutureBuilder(
      future: actions,
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
            onChanged: (changed) => setState(() => ids = changed),
            // The rest of the sheet, under the chips and the search.
            maxListHeight: constraints.maxHeight - 120,
          ),
        );
      },
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

/// Picks who an event was with, who it was for, and where it was, in a
/// [showPickerSheet], a tab for each: each a search over a [ListPicker].
/// The rest of [facts] -- the notes -- kept. Where can be put in words
/// too, as the event's [place]: its free-text location. Returns them;
/// null if dismissed. The people and locations come from the
/// [PeopleScope], as
/// [showFactsDialog]'s do, with those a compaction proposal adds -- its
/// [additions], by their refs, marked new; a new location can be added
/// from here.
Future<({Facts facts, String? place})?> showWhoWhereSheet(
  BuildContext context,
  Facts facts, {
  String? place,
  List<ProposalAddition> additions = const [],
}) {
  var said = place ?? '';
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
  var location = facts.locationId;
  final repository = PeopleScope.of(context);
  final memory = PlanMemoryScope.of(context);
  var people = _people(repository, memory);
  var locations = _locations(repository, memory);
  return showPickerSheet<({Facts facts, String? place})>(
    context,
    title: 'Who and where',
    result: () => (
      facts: Facts(
        locationId: location,
        withIds: [...with_],
        forIds: [...for_],
        notes: {
          for (final MapEntry(:key, :value) in facts.notes.entries)
            if (key == selfPersonId || with_.contains(key)) key: value,
        },
      ),
      place: said.trim().isEmpty ? null : said.trim(),
    ),
    body: (context, setState) => DefaultTabController(
      length: 3,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const TabBar(
            tabs: [
              Tab(text: 'With'),
              Tab(text: 'For'),
              Tab(text: 'Where'),
            ],
          ),
          Expanded(
            child: FutureBuilder(
              future: people,
              initialData: memory?.people,
              builder: (context, snapshot) {
                final everyone = [
                  for (final p in snapshot.data?.withSelf ?? const <Person>[])
                    if (!p.isSelf &&
                        (p.active ||
                            with_.contains(p.id) ||
                            for_.contains(p.id)))
                      p,
                  // Without the list, at least who's already there.
                  if (snapshot.data == null)
                    for (final id in {...with_, ...for_})
                      if (!addedPeople.any((p) => p.id == id))
                        Person(id: id, name: id),
                  ...addedPeople,
                ];
                Widget pick(
                  Set<String> picked,
                  Set<String> other,
                  String hint,
                ) => ListPicker<Person>(
                  items: everyone,
                  id: (p) => p.id,
                  label: (p) => personName(p, context: true),
                  picked: [...picked],
                  hint: hint,
                  empty: 'No one yet: add people on the Plan page.',
                  // No one is both there and not.
                  onChanged: (ids) => setState(() {
                    picked
                      ..clear()
                      ..addAll(ids);
                    other.removeAll(ids);
                  }),
                );
                return TabBarView(
                  children: [
                    pick(with_, for_, 'Who was there'),
                    pick(for_, with_, "Who it was for, while they weren't"),
                    // A location, or where in words: the event's own.
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: _PlaceField(
                            text: place,
                            onChanged: (text) => said = text,
                          ),
                        ),
                        Expanded(
                          child: FutureBuilder(
                            future: locations,
                            initialData: memory?.locations,
                            builder: (context, snapshot) {
                              final known = [
                                ...snapshot.data ?? const <Location>[],
                                ...addedLocations,
                              ];
                              return ListPicker<Location>(
                                items: [
                                  ...known,
                                  if (location != null &&
                                      !known.any((l) => l.id == location))
                                    Location(id: location!, name: location!),
                                ],
                                id: (l) => l.id,
                                label: (l) => l.name,
                                detail: (l) => l.hint,
                                picked: [?location],
                                single: true,
                                hint: 'Where it was',
                                empty: 'No locations yet.',
                                onChanged: (ids) =>
                                    setState(() => location = ids.firstOrNull),
                                extra: repository == null
                                    ? null
                                    : ListTile(
                                        leading: const Icon(
                                          Icons.add_location_alt,
                                        ),
                                        title: const Text('New location…'),
                                        onTap: () async {
                                          final created =
                                              await showLocationDialog(
                                                context,
                                                save: (fields) =>
                                                    repository.createLocation(
                                                      Location(
                                                        id: '',
                                                        name:
                                                            fields['name']
                                                                as String,
                                                        hint:
                                                            fields['hint']
                                                                as String?,
                                                      ),
                                                    ),
                                              );
                                          if (created == null) return;
                                          setState(() {
                                            location = created.id;
                                            locations = _locations(
                                              repository,
                                              memory,
                                              again: true,
                                            );
                                          });
                                        },
                                      ),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    ),
  );
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
/// any other, and there are no chips. [extra] goes at the foot of the
/// list: a way to add one, say.
class ListPicker<T> extends StatefulWidget {
  const ListPicker({
    super.key,
    required this.items,
    required this.id,
    required this.label,
    required this.picked,
    required this.onChanged,
    required this.hint,
    required this.empty,
    this.detail,
    this.single = false,
    this.extra,
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
  final bool single;
  final Widget? extra;

  @override
  State<ListPicker<T>> createState() => _ListPickerState<T>();
}

class _ListPickerState<T> extends State<ListPicker<T>> {
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  /// Whether every word typed is in [item]'s label or detail.
  bool _matches(T item, List<String> words) {
    final text = '${widget.label(item)} ${widget.detail?.call(item) ?? ''}'
        .toLowerCase();
    return words.every(text.contains);
  }

  void _toggle(String id, bool on) => widget.onChanged(
    widget.single
        ? [if (on) id]
        : [
            for (final picked in widget.picked)
              if (picked != id) picked,
            if (on) id,
          ],
  );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final words = [
      for (final w in _search.text.toLowerCase().split(RegExp(r'\s+')))
        if (w.isNotEmpty) w,
    ];
    final shown = [
      for (final item in widget.items)
        if (_matches(item, words)) item,
    ];
    final byId = {for (final item in widget.items) widget.id(item): item};
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Text(widget.hint, style: theme.textTheme.bodySmall),
        ),
        if (!widget.single && widget.picked.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final id in widget.picked)
                  InputChip(
                    label: Text(switch (byId[id]) {
                      final item? => widget.label(item),
                      null => id,
                    }),
                    onDeleted: () => _toggle(id, false),
                  ),
              ],
            ),
          ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: TextField(
            controller: _search,
            decoration: InputDecoration(
              isDense: true,
              border: const OutlineInputBorder(),
              prefixIcon: const Icon(Icons.search),
              hintText: 'Search',
              suffixIcon: _search.text.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'Clear search',
                      icon: const Icon(Icons.close),
                      onPressed: () => setState(_search.clear),
                    ),
            ),
            onChanged: (_) => setState(() {}),
            // The top match, picked (or unpicked) from the keyboard.
            onSubmitted: (_) {
              final top = shown.firstOrNull;
              if (top == null) return;
              final id = widget.id(top);
              _toggle(id, !widget.picked.contains(id));
              setState(_search.clear);
            },
          ),
        ),
        Expanded(
          child: ListView(
            children: [
              if (widget.items.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: Text(
                    widget.empty,
                    style: TextStyle(color: theme.hintColor),
                  ),
                )
              else if (shown.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(8),
                  child: Text('Nothing matches.'),
                ),
              for (final item in shown)
                CheckboxListTile(
                  value: widget.picked.contains(widget.id(item)),
                  controlAffinity: ListTileControlAffinity.leading,
                  title: Text(widget.label(item)),
                  subtitle: switch (widget.detail?.call(item)) {
                    final detail? when detail.isNotEmpty => Text(detail),
                    _ => null,
                  },
                  onChanged: (on) => _toggle(widget.id(item), on ?? false),
                ),
              ?widget.extra,
            ],
          ),
        ),
      ],
    );
  }
}

/// Where an event was, in words: its free-text location, with a
/// controller of its own, as the sheet's kept.
class _PlaceField extends StatefulWidget {
  const _PlaceField({required this.text, required this.onChanged});

  final String? text;
  final ValueChanged<String> onChanged;

  @override
  State<_PlaceField> createState() => _PlaceFieldState();
}

class _PlaceFieldState extends State<_PlaceField> {
  late final _controller = TextEditingController(text: widget.text);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => TextField(
    controller: _controller,
    textCapitalization: TextCapitalization.sentences,
    decoration: const InputDecoration(
      isDense: true,
      border: OutlineInputBorder(),
      labelText: 'Where, in words',
      hintText: 'An address, or anywhere not a location',
    ),
    onChanged: widget.onChanged,
  );
}
