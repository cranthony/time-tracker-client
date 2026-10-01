import 'package:flutter/material.dart';

import '../models/event_label.dart';
import 'properties_dialog.dart';

/// Shows every property of [label], as the server sent it, under its name.
Future<void> showEventLabelDialog(BuildContext context, EventLabel label) =>
    showPropertiesDialog(
      context,
      title: labelName(label),
      // The typed fields first, for a label made without the server's.
      properties: {
        'id': label.id,
        'name': label.name,
        'background_color': label.backgroundColor,
        'priority': label.priority,
        'fixed_time': label.fixedTime,
        ...label.properties,
      },
    );

/// [label]'s name, or "(no name)".
String labelName(EventLabel label) {
  final name = label.name;
  return name == null || name.isEmpty ? '(no name)' : name;
}
