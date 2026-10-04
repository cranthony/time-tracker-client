import 'package:flutter/material.dart';

import '../models/goal.dart';
import 'properties_dialog.dart';

/// What a goal's properties are edited as: everything `update_goal` can
/// change.
const _kinds = {
  'name': PropertyKind.text,
  'status': PropertyKind.choice,
  'parent_id': PropertyKind.goal,
  'background_color': PropertyKind.color,
  'priority': PropertyKind.integer,
  'fixed_time': PropertyKind.optionalFlag,
  'measure': PropertyKind.measure,
  'target': PropertyKind.text,
  'deadline': PropertyKind.date,
  'note': PropertyKind.multiline,
};

const _hints = {
  'parent_id': 'The goal this is part of; none for a top-level goal.',
  'background_color': "With no color, the goal takes its priority's color.",
  'priority':
      'Events and sub-goals with no priority of their own take this one.',
  'status':
      "Only an active goal holds one of the calendar's event labels and is "
      'rated; any other status keeps its history.',
  'fixed_time': 'Events and sub-goals that say nothing take this.',
  'measure':
      "How its health is rated each day, 0-100, confirmed in the daily "
      "reflection. With none, it's rated by its sub-goals' average.",
};

/// What the overall goal's properties are edited as: it's always active
/// and above the rest, and holds no label to color.
final _overallKinds = {
  for (final MapEntry(:key, :value) in _kinds.entries)
    if (const {'name', 'measure', 'target', 'deadline', 'note'}.contains(key))
      key: value,
};

const _overallHints = {
  'measure':
      "How everything's health is rated each day, 0-100, confirmed in the "
      "daily reflection after the rest. With none, it's the average of the "
      'top-level goals\'.',
};

String? _needsName(Map<String, Object?> values) => switch (values['name']) {
  final String name when name.trim().isNotEmpty => null,
  _ => 'A goal needs a name.',
};

/// Shows every property of [goal], as the server sent it, under its name.
///
/// Tapping one of its editable values opens it for editing, in place;
/// "Save" sends every change with [save]. Returns what [save] returned
/// (every goal, as they're to be shown now), or null if nothing was
/// saved. Without [save], or for a goal with no id, nothing can be edited.
/// [goals] lists the goals its parent can be. Tapping its status moves it
/// to another; [confirmSave] is asked first, with the changes, and can
/// call the save off. [changes] opens it with those changes already made:
/// ones that couldn't be saved before.
Future<GoalList?> showGoalDialog(
  BuildContext context,
  Goal goal, {
  Map<String, Object?> changes = const {},
  Future<GoalList> Function(Goal goal, Map<String, Object?> changes)? save,
  Future<bool> Function(Map<String, Object?> changes)? confirmSave,
  Future<List<Goal>> Function()? goals,
}) => showPropertiesDialog<GoalList>(
  context,
  title: (values) => switch (values['name']) {
    final String name when name.isNotEmpty => name,
    _ => '(no name)',
  },
  // The typed fields first, for a goal made without the server's.
  properties: {
    'name': goal.name,
    'path': goal.path,
    'status': goal.status,
    'parent_id': goal.parentId,
    'background_color': goal.backgroundColor,
    'priority': goal.priority,
    'fixed_time': goal.fixedTime,
    'measure': goal.measure,
    ...goal.properties,
  },
  kinds: goal.isOverall ? _overallKinds : _kinds,
  choices: const {'status': goalStatuses},
  required: const {'name', 'status'},
  hints: goal.isOverall ? {..._hints, ..._overallHints} : _hints,
  goals: goals,
  validate: _needsName,
  changes: changes,
  confirmSave: confirmSave,
  save: save == null || goal.id == null
      ? null
      : (changes) => save(goal, changes),
  signInHint: 'Sign in again from the Goals page, then try again.',
);

/// Shows the properties a new goal can start with, under [parentId] if
/// given, and creates it with [create] on "Save". Returns what [create]
/// returned (every goal, as they're to be shown now), or null if nothing
/// was created. [fields] opens it with those already filled in: a goal
/// that couldn't be created before.
Future<GoalList?> showNewGoalDialog(
  BuildContext context, {
  required Future<GoalList> Function(Map<String, Object?> fields) create,
  String? parentId,
  Map<String, Object?> fields = const {},
  Future<List<Goal>> Function()? goals,
}) => showPropertiesDialog<GoalList>(
  context,
  title: (values) => switch (values['name']) {
    final String name when name.isNotEmpty => name,
    _ => parentId == null ? 'New goal' : 'New sub-goal',
  },
  properties: {
    'name': null,
    'parent_id': parentId,
    'priority': null,
    'measure': null,
    'note': null,
  },
  kinds: _kinds,
  hints: _hints,
  goals: goals,
  validate: _needsName,
  changes: {
    for (final MapEntry(:key, :value) in fields.entries)
      if (key != 'parent_id' && value != null) key: value,
  },
  save: (changes) => create({'parent_id': parentId, ...changes}),
  signInHint: 'Sign in again from the Goals page, then try again.',
);
