import 'package:flutter/material.dart';

/// What a new or moved event's anchor -- the cursor it was started from
/// -- does with the event it's inside of.
enum AnchorMode {
  keep(
    'Keep',
    'The event it would be inside of is left as it is: the anchor stays '
        'out of every event.',
    Icons.lock_outline,
  ),
  trim(
    'Trim',
    'The event it is inside of is cut short at the anchor.',
    Icons.content_cut,
  ),
  cancel(
    'Cancel',
    'The event it is inside of is cancelled, whole.',
    Icons.event_busy,
  ),
  splitPush(
    'Split and push',
    'The event it is inside of is split at the anchor, and the rest of it '
        'goes right after the new event, pushing along what it runs into.',
    Icons.call_split,
  );

  const AnchorMode(this.label, this.description, this.icon);

  final String label;
  final String description;
  final IconData icon;

  /// Whether it changes the event it's inside of.
  bool get changes => this != keep;
}

/// What a new or moved event's end -- the cursor away from its anchor --
/// does with the events the box reaches.
enum EndMode {
  keep(
    'Keep',
    "The box doesn't go into other events: it stops where the next one "
        'starts.',
    Icons.lock_outline,
  ),
  trim(
    'Trim',
    'The box goes into other events, and takes their time: they are cut '
        'short, or split around it; one it covers whole is cancelled.',
    Icons.content_cut,
  ),
  cancel(
    'Cancel',
    'Every event the box touches is cancelled, whole -- but the one the '
        'anchor is inside of, which the anchor says what to do with.',
    Icons.event_busy,
  ),
  push(
    'Push',
    'The events the box reaches are pushed along, out of its way, into '
        'free time -- as far as the day has room.',
    Icons.keyboard_double_arrow_down,
  );

  const EndMode(this.label, this.description, this.icon);

  final String label;
  final String description;
  final IconData icon;
}
