import 'package:flutter/material.dart';

import '../models/habit.dart';
import '../models/person.dart';
import '../services/focus_store.dart';

/// A star that focuses on [habit], keeping it in the People pane, or
/// stops; off once [FocusStore.maxHabits] are. It applies at once, on
/// this device.
Widget focusHabitButton(FocusStore focus, Habit habit) => ListenableBuilder(
  listenable: focus,
  builder: (context, _) => _star(
    context,
    on: focus.isFocusHabit(habit.id),
    full: focus.habitsFull,
    name: habitName(habit),
    turnOn: 'Focus on',
    turnOff: "Don't focus on",
    max: FocusStore.maxHabits,
    onChanged: (on) => focus.setFocusHabit(habit.id, on),
  ),
);

/// A star that prioritizes [person], keeping them in the People pane, or
/// stops; off once [FocusStore.maxPeople] are. It applies at once, on
/// this device.
Widget prioritizeButton(FocusStore focus, Person person) => ListenableBuilder(
  listenable: focus,
  builder: (context, _) => _star(
    context,
    on: focus.isPrioritized(person.id),
    full: focus.peopleFull,
    name: personName(person),
    turnOn: 'Prioritize',
    turnOff: "Don't prioritize",
    max: FocusStore.maxPeople,
    onChanged: (on) => focus.setPrioritized(person.id, on),
  ),
);

/// Filled, in the theme's color, when [on], as a prioritized person's
/// star is in their tile.
Widget _star(
  BuildContext context, {
  required bool on,
  required bool full,
  required String name,
  required String turnOn,
  required String turnOff,
  required int max,
  required ValueChanged<bool> onChanged,
}) => IconButton(
  tooltip: on
      ? '$turnOff $name'
      : full
      ? '$turnOn $name ($max already)'
      : '$turnOn $name',
  isSelected: on,
  icon: const Icon(Icons.star_border),
  selectedIcon: Icon(Icons.star, color: Theme.of(context).colorScheme.primary),
  onPressed: on || !full ? () => onChanged(!on) : null,
);
