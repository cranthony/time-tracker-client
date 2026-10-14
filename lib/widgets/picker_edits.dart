import 'package:flutter/material.dart';

import '../models/person.dart';
import '../models/plan_action.dart';
import '../models/trait.dart';
import '../services/actions_repository.dart';
import '../services/people_repository.dart';
import '../services/plan_memory.dart';
import '../services/traits_repository.dart';
import 'action_details_dialog.dart';
import 'person_dialog.dart';

// Adding to, and editing, what the Events page's pickers pick from --
// actions, people and locations -- from the pickers themselves, as the
// Plan page does: each in the same dialog, with what the app has from
// [ActionsScope], [PeopleScope] and [PlanMemoryScope]. One added is
// made at once, rather than in the background, so it has its id to be
// picked by.

/// Every action, as shown: with the edits still going out.
Future<List<PlanAction>> _allActions(
  ActionsRepository repository,
  PlanMemory? memory,
) async {
  if (memory == null) return (await repository.actions()).actions;
  if (memory.actions == null) await memory.loadActions(repository);
  return memory.shownActions?.actions ?? const [];
}

/// Whether actions can be added and edited here.
bool canEditActions(BuildContext context) => ActionsScope.of(context) != null;

/// Adds an action, named [name] to start with. Returns its id; null if
/// it was called off.
Future<String?> addAction(BuildContext context, String name) async {
  final scope = ActionsScope.of(context);
  if (scope == null) return null;
  final memory = PlanMemoryScope.of(context);
  String? made;
  final listed = await showNewActionDialog(
    context,
    fields: {if (name.isNotEmpty) 'name': name},
    actions: () => _allActions(scope.repository, memory),
    create: (fields) async {
      final id = await scope.repository.createAction(fields);
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
    },
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
  final saved = await showActionDetailsDialog(
    context,
    action,
    actions: () => _allActions(scope.repository, memory),
    save: (action, changes) async {
      scope.outbox.update(action.id!, changes, group: action.isGroup);
      return memory?.shownActions ?? await scope.repository.actions();
    },
  );
  return saved != null;
}

/// Adds someone (with no [person]), named [name] to start with, or edits
/// [person], on the page the Plan page does. Returns them as saved; null
/// if it was called off.
Future<Person?> editPerson(
  BuildContext context, {
  Person? person,
  String? name,
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
  final saved = await showPersonEditor(
    context,
    person: person,
    name: name,
    focus: memory?.focus,
    circles: memory?.people?.circles ?? const [],
    traits: traits,
    actions: {
      for (final action in memory?.actions?.actions ?? const <PlanAction>[])
        if (action.id != null && action.status != 'deleted')
          action.id!: action.path ?? actionName(action),
    },
    scoreParts: memory?.scoreDraftParts,
    save: (fields) => person == null
        ? repository.createPerson(Person.fromJson({'id': '', ...fields}))
        : repository.updatePerson(person.id, fields),
  );
  if (saved != null) {
    await _reload(() => memory?.loadPeople(repository, again: true));
  }
  return saved;
}

/// Adds a location (with no [location]), named [name] to start with, or
/// edits [location]. Returns it as saved; null if it was called off.
Future<Location?> editLocation(
  BuildContext context, {
  Location? location,
  String? name,
}) async {
  final repository = PeopleScope.of(context);
  if (repository == null) return null;
  final memory = PlanMemoryScope.of(context);
  final saved = await showLocationDialog(
    context,
    location: location,
    name: name,
    groups: memory?.locationGroups ?? const [],
    save: (fields) => location == null
        ? repository.createLocation(Location.fromJson({'id': '', ...fields}))
        : repository.updateLocation(location.id, fields),
  );
  if (saved != null) {
    await _reload(() => memory?.loadLocations(repository, again: true));
  }
  return saved;
}

/// Loads again what was just saved; best effort, since it was saved.
Future<void> _reload(Future<void>? Function() load) async {
  try {
    await load();
  } catch (_) {
    // The list as it was, till it's loaded again.
  }
}
