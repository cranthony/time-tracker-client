import 'package:flutter/material.dart';

import '../models/event_label.dart';
import 'properties_dialog.dart';

/// Shows every property of [label], as the server sent it, under its name.
///
/// Tapping any of its values but its id opens it for editing, in place;
/// "Save" sends every change with [save]. Returns what [save] returned
/// (every label, as the server has them now), or null if nothing was
/// saved. Without [save], or for a label with no id, nothing can be edited.
/// A name can be changed but not emptied.
Future<List<EventLabel>?> showEventLabelDialog(
  BuildContext context,
  EventLabel label, {
  Future<List<EventLabel>> Function(
    EventLabel label,
    Map<String, Object?> changes,
  )?
  save,
}) => showPropertiesDialog<List<EventLabel>>(
  context,
  title: (values) => switch (values['name']) {
    final String name when name.isNotEmpty => name,
    _ => '(no name)',
  },
  // The typed fields first, for a label made without the server's.
  properties: {
    'id': label.id,
    'name': label.name,
    'background_color': label.backgroundColor,
    'priority': label.priority,
    'fixed_time': label.fixedTime,
    'note': label.note,
    ...label.properties,
  },
  // Everything update_event_label changes; each can be cleared.
  kinds: const {
    'name': PropertyKind.text,
    'background_color': PropertyKind.color,
    'priority': PropertyKind.integer,
    'fixed_time': PropertyKind.optionalFlag,
    'note': PropertyKind.multiline,
  },
  required: const {'name'},
  hints: const {
    'background_color': "With no color, the label takes its priority's color.",
  },
  save: save == null || label.id == null
      ? null
      : (changes) => save(label, changes),
  signInHint: 'Sign in again from the Labels page, then try again.',
);
