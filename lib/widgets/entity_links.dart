/// What a description's links into the app ([EntityLink]) name, as the
/// app has them -- a goal's title, a person's name, a location's -- and
/// what tapping one does: a goal's, a habit's, a person's or a circle's
/// page opens; an action or a location, with no page of its own, opens
/// in its dialog, as its pane opens it. And the picker that links to
/// one from an editor ([pickEntityLink]).
library;

import 'package:flutter/material.dart';

import '../models/entity_link.dart';
import '../models/goal.dart';
import '../models/habit.dart';
import '../models/person.dart';
import '../models/plan_action.dart';
import '../screens/goal_screen.dart';
import '../screens/habit_pages.dart';
import '../screens/person_pages.dart';
import '../services/actions_repository.dart';
import '../services/goals_repository.dart';
import '../services/habits_repository.dart';
import '../services/people_repository.dart';
import '../services/plan_memory.dart';
import 'action_icon.dart';
import 'actions_picker.dart';
import 'circle_icon.dart';
import 'goal_icon.dart';
import 'people_picker.dart';
import 'picker_edits.dart';
import 'picker_sheet.dart';
import 'plow_icon.dart';
import 'tree_picker.dart';

/// The icon for a link to [kind], [size] across in [color]: a goal's
/// bullseye, a habit's repeat, a person's outline, a circle's ring (a
/// community's, its people, with [circle]), an action's plow (a group's
/// folder, with [action]), a location's pin.
Widget entityIcon(
  EntityKind kind, {
  required double size,
  required Color color,
  Circle? circle,
  PlanAction? action,
}) => switch (kind) {
  EntityKind.goal => GoalIcon(size: size, color: color),
  EntityKind.habit => Icon(Icons.repeat, size: size, color: color),
  EntityKind.person => Icon(Icons.person_outline, size: size, color: color),
  EntityKind.circle => Icon(
    circleIconOf(circle, outlined: true),
    size: size,
    color: color,
  ),
  EntityKind.action when action?.isGroup ?? false => Icon(
    Icons.folder_outlined,
    size: size,
    color: color,
  ),
  EntityKind.action => PlowIcon(size: size, color: color, filled: false),
  EntityKind.location => Icon(Icons.place_outlined, size: size, color: color),
};

/// Names and opens what descriptions link to, from what [memory] has
/// and the scopes [context] is in: [of] gathers them.
class EntityLinks {
  const EntityLinks({
    required this.memory,
    this.goals,
    this.habits,
    this.people,
    this.actions,
  });

  /// As [context] has them: null with no [PlanMemoryScope], where no
  /// link can be followed.
  static EntityLinks? of(BuildContext context) {
    final memory = PlanMemoryScope.of(context);
    if (memory == null) return null;
    return EntityLinks(
      memory: memory,
      goals: GoalsScope.of(context),
      habits: HabitsScope.of(context),
      people: PeopleScope.of(context),
      actions: ActionsScope.of(context)?.repository,
    );
  }

  final PlanMemory memory;
  final GoalsRepository? goals;
  final HabitsRepository? habits;
  final PeopleRepository? people;
  final ActionsRepository? actions;

  Goal? _goal(String id) => memory.goals?.where((g) => g.id == id).firstOrNull;
  Habit? _habit(String id) =>
      memory.habits?.where((h) => h.id == id).firstOrNull;
  Person? _person(String id) =>
      memory.people?.withSelf.where((p) => p.id == id).firstOrNull;
  Circle? _circle(String id) => memory.people?.circle(id);
  PlanAction? _action(String id) =>
      memory.shownActions?.actions.where((a) => a.id == id).firstOrNull;
  Location? _location(String id) =>
      memory.locations?.where((l) => l.id == id).firstOrNull;

  /// What [link] names, as the app has it now; null if it doesn't.
  String? name(EntityLink link) => switch (link.kind) {
    EntityKind.goal => switch (_goal(link.id)) {
      final g? => goalTitle(g),
      null => null,
    },
    EntityKind.habit => switch (_habit(link.id)) {
      final h? => habitName(h),
      null => null,
    },
    EntityKind.person => switch (_person(link.id)) {
      final p? => personName(p),
      null => null,
    },
    EntityKind.circle => switch (_circle(link.id)) {
      final c? => circleName(c),
      null => null,
    },
    EntityKind.action => switch (_action(link.id)) {
      final a? => actionName(a),
      null => null,
    },
    EntityKind.location => _location(link.id)?.name,
  };

  /// [link]'s icon, as [entityIcon] draws it for what it names.
  Widget icon(EntityLink link, {required double size, required Color color}) =>
      entityIcon(
        link.kind,
        size: size,
        color: color,
        circle: link.kind == EntityKind.circle ? _circle(link.id) : null,
        action: link.kind == EntityKind.action ? _action(link.id) : null,
      );

  /// Opens what [link] names, loading what it's among if the app hasn't
  /// yet (the tap may be the first thing done this run); says so if it
  /// isn't there, or the app has nowhere to open it.
  Future<void> open(BuildContext context, EntityLink link) async {
    final id = link.id;
    try {
      switch (link.kind) {
        case EntityKind.goal:
          final goals = this.goals;
          if (goals == null) return _cannot(context, link);
          if (_goal(id) == null) await memory.loadKept(goals: goals);
          if (_goal(id) == null) await memory.loadGoals(goals);
          if (!context.mounted) return;
          if (_goal(id) == null) return _missing(context, link);
          await Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) =>
                  GoalScreen(goalId: id, repository: goals, memory: memory),
            ),
          );
        case EntityKind.habit:
          final habits = this.habits;
          if (habits == null) return _cannot(context, link);
          if (_habit(id) == null) await memory.loadHabits(habits);
          if (!context.mounted) return;
          final habit = _habit(id);
          if (habit == null) return _missing(context, link);
          HabitPages.of(context, memory)?.open(context, habit);
        case EntityKind.person || EntityKind.circle:
          final people = this.people;
          if (people == null) return _cannot(context, link);
          if (memory.people == null) await memory.loadPeople(people);
          if (!context.mounted) return;
          final pages = PersonPages.of(context, memory);
          if (pages == null) return _cannot(context, link);
          if (link.kind == EntityKind.person) {
            final person = _person(id);
            if (person == null) return _missing(context, link);
            pages.open(context, person);
          } else {
            final circle = _circle(id);
            if (circle == null) return _missing(context, link);
            pages.openCircle(context, circle);
          }
        case EntityKind.action:
          final actions = this.actions;
          if (actions == null) return _cannot(context, link);
          if (memory.actions == null) await memory.loadActions(actions);
          if (!context.mounted) return;
          final action = _action(id);
          if (action == null) return _missing(context, link);
          await editAction(context, action);
        case EntityKind.location:
          final people = this.people;
          if (people == null) return _cannot(context, link);
          if (memory.locations == null) await memory.loadLocations(people);
          if (!context.mounted) return;
          final location = _location(id);
          if (location == null) return _missing(context, link);
          await editLocation(context, location: location);
      }
    } catch (e) {
      if (context.mounted) _say(context, "Couldn't open ${link.href}: $e");
    }
  }

  void _missing(BuildContext context, EntityLink link) =>
      _say(context, 'No ${link.kind.noun} “${link.id}”');

  void _cannot(BuildContext context, EntityLink link) =>
      _say(context, "Can't open ${link.href} here");

  static void _say(BuildContext context, String text) =>
      ScaffoldMessenger.maybeOf(context)
          ?.showSnackBar(SnackBar(content: Text(text)));

  /// Asks for one of [kind] to link to, in its picker -- the goals, a
  /// tree, open ones only; the habits; a person or a circle; the
  /// actions; the locations in their groups -- loading them if the app
  /// hasn't. Gives the link, and what it names now; null if it's called
  /// off, or there's nothing to pick from.
  Future<({EntityLink link, String name})?> pick(
    BuildContext context,
    EntityKind kind,
  ) async {
    ({EntityLink link, String name})? named(String? id, String? name) =>
        id == null || name == null
        ? null
        : (link: EntityLink(kind, id), name: name);
    try {
      switch (kind) {
        case EntityKind.goal:
          final goals = this.goals;
          if (goals == null) return null;
          if (memory.goals == null) await memory.loadGoals(goals);
          if (!context.mounted) return null;
          final tree = GoalTree(memory.goals ?? const []);
          final nodes = [
            for (final g in byPriority([
              for (final g in memory.goals ?? const <Goal>[])
                if (g.open) g,
            ], tree))
              PickerNode(
                id: g.id,
                label: goalTitle(g),
                parentId: g.parentId,
                path: [...tree.pathOf(g.id), goalTitle(g)].join(' › '),
                detail: g.inactive ? 'Inactive' : null,
                group: tree.childrenOf(g.id).isNotEmpty,
                faded: !g.active,
              ),
          ];
          final picked = await pickNode(
            context,
            title: 'Link to a goal',
            nodes: nodes,
            groupsPickable: true,
            marker: (_) => const GoalIcon(size: 20),
          );
          final goal = picked == null ? null : _goal(picked.id ?? '');
          return named(goal?.id, goal == null ? null : goalTitle(goal));
        case EntityKind.habit:
          final habits = this.habits;
          if (habits == null) return null;
          if (memory.habits == null) await memory.loadHabits(habits);
          if (!context.mounted) return null;
          final picked = await pickNode(
            context,
            title: 'Link to a habit',
            nodes: [
              for (final h in memory.habits ?? const <Habit>[])
                if (h.status != 'deleted')
                  PickerNode(id: h.id, label: habitName(h), faded: !h.active),
            ],
            marker: (_) => const Icon(Icons.repeat, size: 20),
          );
          final habit = picked == null ? null : _habit(picked.id ?? '');
          return named(habit?.id, habit == null ? null : habitName(habit));
        case EntityKind.person || EntityKind.circle:
          final picked = await pickPersonOrCircle(
            context,
            title: 'Link to a person or circle',
            memory: memory,
          );
          return switch (picked) {
            final Person p => (
              link: EntityLink(EntityKind.person, p.id),
              name: personName(p),
            ),
            final Circle c => (
              link: EntityLink(EntityKind.circle, c.id),
              name: circleName(c),
            ),
            _ => null,
          };
        case EntityKind.action:
          final actions = this.actions;
          if (actions == null) return null;
          if (memory.actions == null) await memory.loadActions(actions);
          if (!context.mounted) return null;
          final picked = await showActionPicker(
            context,
            title: 'Link to an action',
            actions: memory.shownActions?.actions ?? const [],
            value: null,
            marker: (a) => ActionIcon(a, size: 20),
          );
          final action = picked == null ? null : _action(picked.id ?? '');
          return named(action?.id, action == null ? null : actionName(action));
        case EntityKind.location:
          final people = this.people;
          if (people == null) return null;
          if (memory.locations == null) await memory.loadLocations(people);
          if (!context.mounted) return null;
          final picked = await pickNode(
            context,
            title: 'Link to a location',
            nodes: [
              ...locationGroupNodes(memory.locationGroups ?? const []),
              for (final l in memory.locations ?? const <Location>[])
                locationNode(l),
            ],
            marker: (n) =>
                Icon(n.group ? Icons.folder_outlined : Icons.place_outlined),
          );
          final location = picked == null ? null : _location(picked.id ?? '');
          return named(location?.id, location?.name);
      }
    } catch (e) {
      if (context.mounted) _say(context, "Couldn't load the ${kind.noun}s: $e");
      return null;
    }
  }
}
