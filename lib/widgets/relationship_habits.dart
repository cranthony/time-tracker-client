import 'package:flutter/material.dart';

import '../models/habit.dart';
import '../models/habit_graph.dart';
import '../models/person.dart';
import '../services/habits_repository.dart';
import '../services/plan_memory.dart';
import 'foundations_field.dart';
import 'relationship_habit_dialog.dart';

/// Adds a habit for [person] or [circle] (with no [habit]), or edits
/// [habit], theirs, in [showRelationshipHabitEditor]: on the traits that
/// apply to them, built on what's on the habit graph [memory] has. Saved
/// through [repository], then loaded again; returns it as saved, or null
/// if nothing was.
Future<Habit?> editRelationshipHabit(
  BuildContext context, {
  required PlanMemory memory,
  required HabitsRepository repository,
  Habit? habit,
  Person? person,
  Circle? circle,
}) async {
  final people = memory.people?.withSelf ?? const <Person>[];
  final circles = memory.people?.circles ?? const <Circle>[];
  person ??= people.where((p) => p.id == habit?.personId).firstOrNull;
  circle ??= circles.where((c) => c.id == habit?.circleId).firstOrNull;
  final (whose, field, id) = switch ((person, circle)) {
    (final p?, _) => (personName(p), 'person_id', p.id),
    (_, final c?) => (c.name.isEmpty ? '(no name)' : c.name, 'circle_id', c.id),
    _ => throw ArgumentError('A habit for a person or circle'),
  };
  final habits = memory.habits ?? const <Habit>[];
  final graph = HabitGraph(habits: habits, people: people);
  final saved = await showRelationshipHabitEditor(
    context,
    habit: habit,
    whose: whose,
    targetField: field,
    targetId: id,
    traits: [
      for (final t in memory.traits ?? const [])
        if (t.status == 'active' &&
            t.id != null &&
            (person?.traits.applies(t.id!) ?? true))
          t,
    ],
    foundationChoices: foundationChoices(graph, id: habit?.subject),
    foundationNames: graphNames(graph),
    save: (fields) => habit == null
        ? repository.createHabit(
            Habit.fromJson({'id': '', 'action_id': '', ...fields}),
          )
        : repository.updateHabit(habit.id, fields),
  );
  if (saved != null) await memory.loadHabits(repository, again: true);
  return saved;
}

/// Every node of [graph]'s name, by id, as foundations name them.
Map<String, String> graphNames(HabitGraph graph) => {
  for (final MapEntry(:key, :value) in graph.nodes.entries) key: value.name,
};

/// [person]'s or [circle]'s habits, not deleted, each a chip that edits
/// it, and a button adding another -- with [HabitsScope]'s repository,
/// saved there and loaded again into [memory]. Nothing without one.
class RelationshipHabits extends StatelessWidget {
  const RelationshipHabits({
    super.key,
    required this.memory,
    this.person,
    this.circle,
  });

  final PlanMemory memory;
  final Person? person;
  final Circle? circle;

  @override
  Widget build(BuildContext context) {
    final repository = HabitsScope.of(context);
    if (repository == null) return const SizedBox.shrink();
    final theirs = [
      for (final h in memory.habits ?? const <Habit>[])
        if (h.status != 'deleted' &&
            ((person != null && h.personId == person!.id) ||
                (circle != null && h.circleId == circle!.id)))
          h,
    ]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    Future<void> edit(Habit? habit) => editRelationshipHabit(
      context,
      memory: memory,
      repository: repository,
      habit: habit,
      person: person,
      circle: circle,
    );
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        for (final h in theirs)
          ActionChip(
            label: Text(habitName(h)),
            tooltip: 'Edit ${habitName(h)}',
            onPressed: () => edit(h),
          ),
        TextButton.icon(
          onPressed: memory.habits == null ? null : () => edit(null),
          icon: const Icon(Icons.add, size: 18),
          label: const Text('Add habit'),
        ),
      ],
    );
  }
}
