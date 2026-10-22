import 'package:flutter/material.dart';

import '../models/person.dart';
import '../models/plan_action.dart';
import '../models/trait.dart';
import '../services/actions_repository.dart';
import '../services/people_repository.dart';
import '../services/plan_memory.dart';
import '../services/traits_repository.dart';
import 'action_dialog.dart';
import 'person_dialog.dart';
import 'quick_add_sheet.dart';

// Adding to, and editing, what the Events page's pickers pick from --
// actions, people and locations -- from the pickers themselves, as the
// Plan page does: each added in its quick sheet (and its More, the same
// dialog or page), and edited in the same dialog or page, with what the
// app has from [ActionsScope], [PeopleScope] and [PlanMemoryScope]. One
// added is made at once, rather than in the background, so it has its id
// to be picked by.

/// Every action, as shown: with the edits still going out. None if they
/// can't be loaded: the dialog can still name one, or edit it.
Future<List<PlanAction>> _allActions(
  ActionsRepository repository,
  PlanMemory? memory,
) async {
  try {
    if (memory == null) return (await repository.actions()).actions;
    if (memory.actions == null) await memory.loadActions(repository);
    return memory.shownActions?.actions ?? const [];
  } catch (_) {
    return const [];
  }
}

/// Whether actions can be added and edited here.
bool canEditActions(BuildContext context) => ActionsScope.of(context) != null;

/// Adds an action, named [name] and in group [parentId] to start with, in
/// its quick sheet, or its More, the full dialog. It's made with [create] (by default, as
/// the actions are), given its fields as `create_action` takes them and
/// returning its id, if it knows it. Returns its id; null if it was
/// called off.
Future<String?> addAction(
  BuildContext context,
  String name, {
  String? parentId,
  Future<String?> Function(Map<String, Object?> fields)? create,
}) async {
  final scope = ActionsScope.of(context);
  if (scope == null) return null;
  final memory = PlanMemoryScope.of(context);
  String? made;
  final actions = await _allActions(scope.repository, memory);
  if (!context.mounted) return null;
  Future<ActionList> make(Map<String, Object?> fields) async {
    final id = await (create ?? scope.repository.createAction)(fields);
    final ActionList list;
    if (memory == null) {
      list = await scope.repository.actions();
    } else {
      await memory.loadActions(scope.repository, again: true);
      list = memory.shownActions!;
    }
    made =
        id ??
        list.actions
            .where((a) => a.name == fields['name'] && !a.isGroup)
            .lastOrNull
            ?.id;
    return list;
  }

  final listed = await showAddActionSheet<ActionList>(
    context,
    name: name.isEmpty ? null : name,
    parentId: parentId,
    actions: actions,
    save: make,
    more: (fields) => showNewActionDialog(
      context,
      fields: fields,
      parentId: fields['parent_id'] as String?,
      actions: actions,
      create: make,
    ),
  );
  return listed == null ? null : made;
}

/// Edits [action] -- an action or a group -- every property of it, its
/// changes going out in the background, as the Plan page's do. True if
/// any were saved.
Future<bool> editAction(BuildContext context, PlanAction action) async {
  final scope = ActionsScope.of(context);
  if (scope == null || action.id == null) return false;
  final memory = PlanMemoryScope.of(context);
  final actions = await _allActions(scope.repository, memory);
  if (!context.mounted) return false;
  final saved = await showActionDialog(
    context,
    action,
    actions: actions,
    save: (action, changes) async {
      scope.outbox.update(action.id!, changes, group: action.isGroup);
      return memory?.shownActions ?? await scope.repository.actions();
    },
  );
  return saved != null;
}

/// Adds someone (with no [person]), named [name] and with [about] as
/// their context to start with, in the quick New person sheet -- or its
/// More, the page the Plan page edits on -- or edits [person], on that
/// page. Someone added is made with [create] (by default, as people are),
/// given their fields as `create_person` takes them. Returns them as
/// saved; null if it was called off.
Future<Person?> editPerson(
  BuildContext context, {
  Person? person,
  String? name,
  String? about,
  Future<Person> Function(Map<String, Object?> fields)? create,
}) async {
  final repository = PeopleScope.of(context);
  if (repository == null) return null;
  final memory = PlanMemoryScope.of(context);
  final traitsRepository = TraitsScope.of(context);
  var traits = const <Trait>[];
  try {
    traits = await traitsRepository?.traits() ?? const [];
  } catch (_) {
    // Which apply can wait.
  }
  if (!context.mounted) return null;
  final circles = memory?.people?.circles ?? const <Circle>[];
  final make =
      create ??
      (fields) =>
          repository.createPerson(Person.fromJson({'id': '', ...fields}));
  Future<Person?> page(Map<String, Object?> fields) => showPersonEditor(
    context,
    person: person,
    name: name,
    fields: fields,
    focus: memory?.focus,
    circles: circles,
    traits: traits,
    actions: {
      for (final action in memory?.actions?.actions ?? const <PlanAction>[])
        if (action.id != null && action.status != 'deleted')
          action.id!: action.path ?? actionName(action),
    },
    scoreParts: memory?.scoreDraftParts,
    save: (fields) => person == null
        ? make(fields)
        : repository.updatePerson(person.id, fields),
  );
  final saved = person != null
      ? await page(const {})
      : await showAddPersonSheet<Person>(
          context,
          name: name,
          about: about,
          circles: circles,
          save: make,
          more: page,
        );
  if (saved != null) {
    await _reload(() => memory?.loadPeople(repository, again: true));
  }
  return saved;
}

/// Adds a location (with no [location]), named [name] and with [hint] to
/// start with, in the quick New location sheet, or edits [location] in
/// its dialog; with [mapLocation], its map location starts as that. One
/// added is made with [create] (by default, as locations are), given its
/// fields as `create_location` takes them. A new group to put it in can
/// be added from its group picker, too. Returns it as saved; null if it
/// was called off.
Future<Location?> editLocation(
  BuildContext context, {
  Location? location,
  String? name,
  String? hint,
  String? mapLocation,
  Future<Location> Function(Map<String, Object?> fields)? create,
}) async {
  final repository = PeopleScope.of(context);
  if (repository == null) return null;
  final memory = PlanMemoryScope.of(context);
  final groups = memory?.locationGroups ?? const <LocationGroup>[];
  final addGroup = addLocationGroup(repository, memory);
  final saved = location == null
      ? await showAddLocationSheet<Location>(
          context,
          name: name,
          hint: hint,
          mapLocation: mapLocation,
          groups: groups,
          addGroup: addGroup,
          save:
              create ??
              (fields) => repository.createLocation(
                Location.fromJson({'id': '', ...fields}),
              ),
        )
      : await showLocationDialog(
          context,
          location: location,
          mapLocation: mapLocation,
          groups: groups,
          addGroup: addGroup,
          save: (fields) => repository.updateLocation(location.id, fields),
        );
  if (saved != null) {
    await _reload(() => memory?.loadLocations(repository, again: true));
  }
  return saved;
}

/// Adds a location group, given its fields as `create_location_group`
/// takes them, then loads [memory]'s locations and groups again, so it's
/// among them. Returns it as saved.
Future<LocationGroup> Function(Map<String, Object?> fields) addLocationGroup(
  PeopleRepository repository,
  PlanMemory? memory,
) => (fields) async {
  final added = await repository.createLocationGroup(
    LocationGroup.fromJson({'id': '', ...fields}),
  );
  await _reload(() => memory?.loadLocations(repository, again: true));
  return added;
};

/// Gives [location] [map] as its map location: at once, if it has none
/// (or has it already); otherwise in its dialog, [map] in place of the
/// one it has, shown under it, to save or not. Returns it as saved; null
/// if it was called off.
Future<Location?> assignMapLocation(
  BuildContext context,
  Location location,
  String map,
) async {
  final repository = PeopleScope.of(context);
  if (repository == null) return null;
  final memory = PlanMemoryScope.of(context);
  final had = location.mapLocation?.trim() ?? '';
  if (had == map) return location;
  if (had.isEmpty) {
    try {
      final saved = await repository.updateLocation(location.id, {
        'map_location': map,
      });
      await _reload(() => memory?.loadLocations(repository, again: true));
      return saved;
    } catch (_) {
      // Its dialog, then, saying why, to try again from.
    }
  }
  if (!context.mounted) return null;
  return editLocation(context, location: location, mapLocation: map);
}

/// Loads again what was just saved; best effort, since it was saved.
Future<void> _reload(Future<void>? Function() load) async {
  try {
    await load();
  } catch (_) {
    // The list as it was, till it's loaded again.
  }
}
