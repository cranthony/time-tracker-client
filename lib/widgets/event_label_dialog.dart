import 'package:flutter/material.dart';

import '../models/event_label.dart';
import 'properties_dialog.dart';

/// Shows every property of [label], as the server sent it, under its name.
///
/// Tapping its name, color or priority opens it for editing, in place;
/// "Save" sends every change with [save]. Returns what [save] returned
/// (every label, as the server has them now), or null if nothing was
/// saved. Without [save], or for a label with no id, nothing can be edited.
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
    ...label.properties,
  },
  // What update_event_label changes. It keeps a value that's left out, so
  // none can be emptied.
  kinds: const {
    'name': PropertyKind.text,
    'background_color': PropertyKind.color,
    'priority': PropertyKind.integer,
  },
  required: const {'name', 'background_color', 'priority'},
  save: save == null || label.id == null
      ? null
      : (changes) => save(label, changes),
  signInHint: 'Sign in again from the Labels page, then try again.',
);
