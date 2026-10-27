import 'package:flutter/material.dart';

import '../models/habit.dart';
import '../models/habit_graph.dart';
import '../models/person.dart';
import '../models/plan_action.dart';
import '../models/trait.dart';
import '../services/habits_repository.dart';
import '../services/people_repository.dart';
import '../services/plan_memory.dart';
import '../services/traits_repository.dart';
import '../widgets/foundations_field.dart';
import '../widgets/habit_dialog.dart';
import '../widgets/relationship_habits.dart';
import 'habit_screen.dart';
import 'person_pages.dart';

/// Opens habits' pages ([HabitScreen]), and adds and edits habits, for
/// what shows them -- the Habits pane, and a recurring goal's goal's
/// page: those [memory] has, saved with [repository]. [actions] names and
/// colors their actions; [personNames] and [locationNames] name who their
/// events were with, and where. [onSaved] is told once one is, to load
/// them afresh -- by default, the habits.
class HabitPages {
  const HabitPages({
    required this.repository,
    required this.memory,
    this.actions = const [],
    this.personNames = const {},
    this.locationNames = const {},
    this.onSaved,
  });

  /// Its pages as [context] has them, for what [memory] has; null with
  /// no habits to save to.
  static HabitPages? of(BuildContext context, PlanMemory memory) =>
      switch (HabitsScope.of(context)) {
        final repository? => HabitPages(
          repository: repository,
          memory: memory,
          actions: memory.shownActions?.actions ?? const [],
          personNames: {...?memory.people?.names},
          locationNames: {
            for (final l in memory.locations ?? const <Location>[])
              l.id: l.name,
          },
        ),
        null => null,
      };

  final HabitsRepository repository;
  final PlanMemory memory;

  /// Every action and group.
  final List<PlanAction> actions;
  final Map<String?, String> personNames;
  final Map<String?, String> locationNames;
  final Future<void> Function()? onSaved;

  /// Every trait, by id, to name those that apply to a habit.
  Map<String, Trait> get _traits => {
    for (final t in memory.traits ?? const <Trait>[])
      if (t.id != null) t.id!: t,
  };

  HabitGraph get _graph => HabitGraph(habits: memory.habits ?? const []);

  /// Every habit's name, by id, as foundations name them.
  Map<String, String> get _names => {
    for (final h in memory.habits ?? const <Habit>[]) h.subject: habitName(h),
  };

  Future<void> _saved() =>
      onSaved?.call() ?? memory.loadHabits(repository, again: true);

  /// Opens people's pages, from their habits'; null with no people.
  PersonPages? _personPages(BuildContext context) =>
      switch (PeopleScope.of(context)) {
        final people? => PersonPages(
          repository: people,
          memory: memory,
          traits: TraitsScope.of(context),
          actionNames: {for (final a in actions) a.id: actionName(a)},
          actions: {
            for (final a in actions)
              if (a.id != null && a.status != 'deleted')
                a.id!: a.path ?? actionName(a),
          },
          locationNames: locationNames,
          onSaved: _saved,
        ),
        null => null,
      };

  /// Opens [habit]'s page.
  void open(BuildContext context, Habit habit) {
    final pages = _personPages(context);
    final page = HabitScreen(
      habit: habit,
      actions: actions,
      traits: _traits,
      memory: memory,
      personNames: personNames,
      locationNames: locationNames,
      foundationNames: _names,
      onEdit: (habit) => edit(context, habit),
      onOpenPerson: pages == null
          ? null
          : (person) => pages.open(context, person),
      onOpenCircle: pages == null
          ? null
          : (circle) => pages.openCircle(context, circle),
    );
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));
  }

  /// Adds a habit (with no [habit]) or edits one; returns it as saved,
  /// or null if nothing was.
  Future<Habit?> edit(BuildContext context, Habit? habit) async {
    if (habit != null && habit.isRelationship) {
      final saved = await editRelationshipHabit(
        context,
        memory: memory,
        repository: repository,
        habit: habit,
      );
      if (saved != null) await _saved();
      return saved;
    }
    final saved = await showHabitEditor(
      context,
      habit: habit,
      actions: actions,
      traits: [..._traits.values],
      foundationChoices: foundationChoices(_graph, id: habit?.subject),
      foundationNames: _names,
      scoreParts: memory.scoreDraftParts,
      save: (fields) => habit == null
          ? repository.createHabit(
              Habit.fromJson({'id': '', 'action_id': '', ...fields}),
            )
          : repository.updateHabit(habit.id, fields),
    );
    if (saved != null) await _saved();
    return saved;
  }
}
