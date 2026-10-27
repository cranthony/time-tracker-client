import 'package:flutter/material.dart';

import '../models/person.dart';
import '../services/people_repository.dart';
import '../services/plan_memory.dart';
import 'hotkeys.dart';
import 'picker_edits.dart';
import 'picker_sheet.dart';
import 'tree_picker.dart';

// The people picker, for whoever can be picked -- people, circles, or
// either -- each as a row of a [TreePicker], searched, added to and
// edited from the picker itself: from what the app has, in the
// [PeopleScope] and [PlanMemoryScope].

/// [person] as a people picker shows them: by name, with their context.
PickerNode personNode(Person person) =>
    PickerNode(id: person.id, label: personName(person, context: true));

/// [circle] as a people picker shows it: by name, with its note under
/// it; by [id] in place of its own, among people.
PickerNode circleNode(Circle circle, {String? id}) => PickerNode(
  id: id ?? circle.id,
  label: circleName(circle),
  detail: circle.note,
);

/// What a people picker that picks either shows: everyone, or only
/// people, or only circles.
enum WhoShown {
  everyone('Everyone'),
  people('People'),
  circles('Circles');

  const WhoShown(this.label);

  final String label;
}

/// A circle's id among people's, in a picker of either.
const _circlePrefix = 'circle:';

/// Picks a person or a circle, under [title], in a [showPickerSheet]: the
/// circles, then the active people, Self among them -- each a row, a
/// circle's marked by its icon -- searched, or shown only people or only
/// circles. Tapping one picks it. A person or a circle can be added,
/// named as it's typed, and is picked; one long-pressed is edited.
/// Returns the [Person] or [Circle] picked; null if it's dismissed. They
/// come from [memory], by default the [PlanMemoryScope]'s.
Future<Object?> pickPersonOrCircle(
  BuildContext context, {
  required String title,
  PlanMemory? memory,
}) {
  final repository = PeopleScope.of(context);
  memory ??= PlanMemoryScope.of(context);
  var people = knownPeople(repository, memory);
  var shown = WhoShown.everyone;
  return showPickerSheet<Object?>(
    context,
    title: title,
    result: () => null,
    body: (context, setState) => OwnPickerSearch(
      builder: (context, search) => FutureBuilder(
        future: people,
        initialData: memory?.people,
        builder: (context, snapshot) {
          final list = snapshot.data ?? const PeopleList();
          final circles = {
            for (final c in list.circles) '$_circlePrefix${c.id}': c,
          };
          final everyone = {
            for (final p in list.withSelf)
              if (p.active) p.id: p,
          };
          void picked(Object? who) {
            if (who != null && context.mounted) Navigator.of(context).pop(who);
          }

          final addPerson = (
            noun: 'person',
            icon: Icons.person_add_alt,
            onAdd: (String name) async =>
                picked(await editPerson(context, name: name)),
          );
          final addCircle = (
            noun: 'circle',
            icon: Icons.group_add_outlined,
            onAdd: (String name) async =>
                picked(await editCircle(context, name: name, memory: memory)),
          );
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SegmentedButton<WhoShown>(
                segments: [
                  for (final who in WhoShown.values)
                    ButtonSegment(value: who, label: Text(who.label)),
                ],
                selected: {shown},
                showSelectedIcon: false,
                onSelectionChanged: (picked) =>
                    setState(() => shown = picked.single),
              ),
              Expanded(
                child: TreePicker(
                  nodes: [
                    if (shown != WhoShown.people)
                      for (final MapEntry(:key, :value) in circles.entries)
                        circleNode(value, id: key),
                    if (shown != WhoShown.circles)
                      for (final p in everyone.values) personNode(p),
                  ],
                  picked: const [],
                  single: true,
                  autofocus: true,
                  search: search,
                  searchHint: switch (shown) {
                    WhoShown.everyone => 'Search people and circles',
                    WhoShown.people => 'Search people',
                    WhoShown.circles => 'Search circles',
                  },
                  empty: switch (shown) {
                    WhoShown.circles => 'No circles yet.',
                    _ => 'No one yet.',
                  },
                  marker: (node) => Icon(
                    circles.containsKey(node.id)
                        ? Icons.groups_outlined
                        : Icons.person_outline,
                    size: 20,
                  ),
                  onChanged: (ids) => picked(
                    circles[ids.firstOrNull] ?? everyone[ids.firstOrNull],
                  ),
                  onEdit: repository == null
                      ? null
                      : (node) async {
                          final circle = circles[node.id];
                          final person = everyone[node.id];
                          final edited = circle != null
                              ? await editCircle(
                                  context,
                                  circle: circle,
                                  memory: memory,
                                )
                              : person != null
                              ? await editPerson(context, person: person)
                              : null;
                          if (edited == null) return;
                          setState(
                            () => people = knownPeople(repository, memory),
                          );
                        },
                  add: repository == null || shown == WhoShown.circles
                      ? null
                      : addPerson,
                  adds: [
                    if (repository != null && shown != WhoShown.people)
                      addCircle,
                  ],
                ),
              ),
            ],
          );
        },
      ),
    ),
  );
}

/// Picks any of the circles -- the app's, or till it has them, [circles]
/// -- [picked] to start with, under [title], in a [showPickerSheet]: each
/// a row, searched, the picked as chips on top. A
/// circle can be added, named as it's typed, and is picked; one
/// long-pressed is edited. Done returns the ids picked, in the order they
/// were; null if it's dismissed.
Future<List<String>?> pickCircles(
  BuildContext context, {
  String title = 'Circles',
  List<Circle> circles = const [],
  required List<String> picked,
}) {
  final repository = PeopleScope.of(context);
  final memory = PlanMemoryScope.of(context);
  var people = knownPeople(repository, memory);
  var ids = [...picked];
  return showPickerSheet<List<String>>(
    context,
    title: title,
    result: () => ids,
    body: (context, setState) => OwnPickerSearch(
      builder: (context, search) => FutureBuilder(
        future: people,
        initialData: memory?.people ?? PeopleList(circles: circles),
        builder: (context, snapshot) {
          final circles = {
            for (final c in snapshot.data?.circles ?? const <Circle>[]) c.id: c,
          };
          return TreePicker(
            nodes: [
              for (final c in circles.values) circleNode(c),
              // Without the list, at least those picked.
              for (final id in ids)
                if (!circles.containsKey(id)) PickerNode(id: id, label: id),
            ],
            picked: ids,
            autofocus: true,
            search: search,
            searchHint: 'Search circles',
            empty: 'No circles yet.',
            onChanged: (changed) => setState(() => ids = changed),
            onEdit: repository == null
                ? null
                : (node) async {
                    final c = circles[node.id];
                    if (c == null) return;
                    if (await editCircle(context, circle: c, memory: memory) ==
                        null) {
                      return;
                    }
                    setState(() => people = knownPeople(repository, memory));
                  },
            add: repository == null
                ? null
                : (
                    noun: 'circle',
                    icon: Icons.group_add_outlined,
                    onAdd: (name) async {
                      final added = await editCircle(
                        context,
                        name: name,
                        memory: memory,
                      );
                      if (added == null) return;
                      search.controller.clear();
                      setState(() {
                        people = knownPeople(repository, memory);
                        if (!ids.contains(added.id)) ids = [...ids, added.id];
                      });
                    },
                  ),
          );
        },
      ),
    ),
  );
}

/// The circles someone's in, [picked] -- of [circles], or those the app
/// has since -- as chips under [label]. Tapped, it opens the circles
/// picker ([pickCircles]), and [onChanged] gets the ids picked. [hotkey]
/// puts the keyboard on it.
class CirclesField extends StatelessWidget {
  const CirclesField({
    super.key,
    required this.circles,
    required this.picked,
    required this.onChanged,
    this.label = 'Circles',
    this.hotkey,
  });

  final List<Circle> circles;
  final List<String> picked;
  final ValueChanged<List<String>> onChanged;
  final String label;
  final String? hotkey;

  Future<void> _pick(BuildContext context) async {
    final ids = await pickCircles(
      context,
      title: label,
      circles: circles,
      picked: picked,
    );
    if (ids != null) onChanged(ids);
  }

  @override
  Widget build(BuildContext context) {
    final byId = {
      for (final c in PlanMemoryScope.of(context)?.people?.circles ?? circles)
        c.id: c,
      for (final c in circles) c.id: c,
    };
    final field = InkWell(
      borderRadius: BorderRadius.circular(4),
      onTap: () => _pick(context),
      child: InputDecorator(
        isEmpty: picked.isEmpty,
        decoration: InputDecoration(
          labelText: label,
          hintText: 'In none',
          isDense: true,
          border: const OutlineInputBorder(),
          suffixIcon: const Icon(Icons.arrow_drop_down),
        ),
        child: picked.isEmpty
            ? null
            : Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final id in picked)
                    InputChip(
                      avatar: const Icon(Icons.groups_outlined, size: 18),
                      label: Text(switch (byId[id]) {
                        final c? => circleName(c),
                        null => id,
                      }),
                      deleteButtonTooltipMessage: 'Remove',
                      onDeleted: () => onChanged([
                        for (final other in picked)
                          if (other != id) other,
                      ]),
                    ),
                ],
              ),
      ),
    );
    return switch (hotkey) {
      final key? => FieldHotkey(key, child: field),
      null => field,
    };
  }
}
