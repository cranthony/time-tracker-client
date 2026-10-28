import 'package:flutter/material.dart';

import '../models/people_times.dart';
import '../models/person.dart';
import '../models/plan_action.dart';
import '../models/trait.dart';
import '../services/people_repository.dart';
import '../services/plan_memory.dart';
import '../services/traits_repository.dart';
import '../widgets/person_dialog.dart';
import '../widgets/picker_edits.dart' as edits;
import '../widgets/quick_add_sheet.dart';
import 'circle_screen.dart';
import 'person_screen.dart';

/// Opens people's pages ([PersonScreen]) and circles' ([CircleScreen]),
/// and edits them, for the panes that show people -- People, Traits with
/// Self, and Habits: whom [memory] has, saved with [repository]. [onSaved] is told once someone is, to load
/// everyone afresh.
class PersonPages {
  const PersonPages({
    required this.repository,
    required this.memory,
    this.traits,
    this.actionNames = const {},
    this.actions = const {},
    this.locationNames = const {},
    this.onSaved,
  });

  /// Its pages as [context] has them, for whom [memory] has, loading
  /// everyone again once someone's saved; null with no people to save to.
  static PersonPages? of(BuildContext context, PlanMemory memory) {
    final repository = PeopleScope.of(context);
    if (repository == null) return null;
    final actions = memory.shownActions?.actions ?? const <PlanAction>[];
    return PersonPages(
      repository: repository,
      memory: memory,
      traits: TraitsScope.of(context),
      actionNames: {for (final a in actions) a.id: actionName(a)},
      actions: {
        for (final a in actions)
          if (a.id != null && a.status != 'deleted')
            a.id!: a.path ?? actionName(a),
      },
      locationNames: {
        for (final l in memory.locations ?? const []) l.id: l.name,
      },
      onSaved: () => memory.loadPeople(repository, again: true),
    );
  }

  final PeopleRepository repository;
  final PlanMemory memory;

  /// The traits that could apply to someone, offered as they're edited.
  final TraitsRepository? traits;

  /// Names actions by id, for a person's history.
  final Map<String?, String> actionNames;

  /// The actions and groups a person's own parts can count, by id.
  final Map<String, String> actions;

  /// Names locations by id, for where a person's events were.
  final Map<String?, String> locationNames;
  final Future<void> Function()? onSaved;

  List<Circle> get _circles => memory.people?.circles ?? const [];

  /// Everyone's names, by id, Self among them, and every circle's.
  Map<String?, String> get personNames => {...?memory.people?.names};

  /// The traits that could apply to someone: active, and off.
  Future<List<Trait>> _traits() async {
    try {
      return await traits?.traits() ?? const [];
    } catch (_) {
      return const []; // Which apply can wait.
    }
  }

  /// Adds someone (with no [person]) -- in the quick sheet first, its
  /// More the page -- or edits [person], on a page of its own.
  Future<void> edit(BuildContext context, Person? person) async {
    final traits = await _traits();
    if (!context.mounted) return;
    Future<Person> create(Map<String, Object?> fields) =>
        repository.createPerson(Person.fromJson({'id': '', ...fields}));
    Future<Person?> page(Map<String, Object?> fields) => showPersonEditor(
      context,
      person: person,
      fields: fields,
      circles: _circles,
      traits: traits,
      actions: actions,
      scoreParts: memory.scoreDraftParts,
      save: (fields) => person == null
          ? create(fields)
          : repository.updatePerson(person.id, fields),
    );
    final saved = person == null
        ? await showAddPersonSheet<Person>(
            context,
            circles: _circles,
            save: create,
            more: page,
          )
        : await page(const {});
    if (saved != null) await onSaved?.call();
  }

  /// Adds a circle (with no [circle]) or edits [circle], in its dialog.
  Future<void> editCircle(BuildContext context, Circle? circle) async {
    final saved = await edits.editCircle(
      context,
      circle: circle,
      repository: repository,
      memory: memory,
      traits: traits,
    );
    if (saved != null) await onSaved?.call();
  }

  /// Opens [circle]'s page: with [times], its time together, as
  /// [durations] says.
  void openCircle(
    BuildContext context,
    Circle circle, {
    PeopleTimes? times,
    bool durations = true,
  }) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (pageContext) => CircleScreen(
          circle: circle,
          memory: memory,
          times: times,
          durations: durations,
          traits: traits,
          personNames: personNames,
          actionNames: actionNames,
          locationNames: locationNames,
          onOpenPerson: (person) => open(pageContext, person),
          onEdit: (circle) => editCircle(pageContext, circle),
        ),
      ),
    );
  }

  /// Opens [person]'s page.
  void open(BuildContext context, Person person) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (pageContext) => PersonScreen(
          person: person,
          traits: traits,
          memory: memory,
          circles: _circles,
          personNames: personNames,
          actionNames: actionNames,
          locationNames: locationNames,
          onEdit: () async {
            await edit(pageContext, person);
            return memory.people?.withSelf
                .where((p) => p.id == person.id)
                .firstOrNull;
          },
        ),
      ),
    );
  }
}
