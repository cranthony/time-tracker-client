import 'package:flutter/material.dart';

import '../models/goal.dart';
import 'properties_dialog.dart';

/// What a goal's properties are edited as; everything `update_goal` can
/// change but its status, which the Goals page changes itself.
const _kinds = {
  'name': PropertyKind.text,
  'parent_id': PropertyKind.goal,
  'background_color': PropertyKind.color,
  'priority': PropertyKind.integer,
  'fixed_time': PropertyKind.optionalFlag,
  'cadence': PropertyKind.choice,
  'target': PropertyKind.text,
  'deadline': PropertyKind.date,
  'note': PropertyKind.multiline,
};

const _hints = {
  'parent_id': 'The goal this is part of; none for a top-level goal.',
  'background_color': "With no color, the goal takes its priority's color.",
  'priority':
      'Events and sub-goals with no priority of their own take this one.',
  'fixed_time': 'Events and sub-goals that say nothing take this.',
  'cadence': 'How often its health is assessed.',
};

String? _needsName(Map<String, Object?> values) => switch (values['name']) {
  final String name when name.trim().isNotEmpty => null,
  _ => 'A goal needs a name.',
};

/// Shows every property of [goal], as the server sent it, under its name.
///
/// Tapping one of its editable values opens it for editing, in place;
/// "Save" sends every change with [save]. Returns what [save] returned
/// (every goal, as the server has them now), or null if nothing was
/// saved. Without [save], or for a goal with no id, nothing can be edited.
/// [goals] lists the goals its parent can be.
Future<GoalList?> showGoalDialog(
  BuildContext context,
  Goal goal, {
  Future<GoalList> Function(Goal goal, Map<String, Object?> changes)? save,
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
    'status': goalStatuses[goal.status] ?? goal.status,
    'parent_id': goal.parentId,
    'background_color': goal.backgroundColor,
    'priority': goal.priority,
    'fixed_time': goal.fixedTime,
    'cadence': goal.cadence,
    ...goal.properties,
  },
  kinds: _kinds,
  choices: const {'cadence': cadences},
  required: const {'name'},
  hints: _hints,
  goals: goals,
  validate: _needsName,
  save: save == null || goal.id == null
      ? null
      : (changes) => save(goal, changes),
  signInHint: 'Sign in again from the Goals page, then try again.',
);

/// Shows the properties a new goal can start with, under [parentId] if
/// given, and creates it with [create] on "Save". Returns what [create]
/// returned (every goal, as the server has them now), or null if nothing
/// was created.
Future<GoalList?> showNewGoalDialog(
  BuildContext context, {
  required Future<GoalList> Function(Map<String, Object?> fields) create,
  String? parentId,
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
    'cadence': null,
    'note': null,
  },
  kinds: _kinds,
  choices: const {'cadence': cadences},
  hints: _hints,
  goals: goals,
  validate: _needsName,
  save: (changes) => create({'parent_id': parentId, ...changes}),
  signInHint: 'Sign in again from the Goals page, then try again.',
);
