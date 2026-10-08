import 'package:flutter/material.dart';

import '../outbox/event_outbox.dart';

/// Whether [key] of an event waits for a change to be saved, by
/// [waiting]: those fields, or, with [allWaiting], all of it. Its start
/// and end wait together, as its time.
bool waitsFor(Set<String> waiting, String key) =>
    waiting.contains('*') ||
    waiting.contains(key) ||
    ({'start', 'end'}.contains(key) &&
        (waiting.contains('start') || waiting.contains('end')));

/// Says, over an event's dialog, what of it is [waiting] to be saved, and
/// so can't change till it is: all of it, or the fields named.
class WaitingNote extends StatelessWidget {
  const WaitingNote({super.key, required this.waiting});

  final Set<String> waiting;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final names = {
      for (final f in waiting)
        if (f != '*') WaitingForWrite.fieldName(f),
    }.toList();
    final text = waiting.contains('*') || names.isEmpty
        ? "Waiting to save: it can't change until it's saved. The changes "
              'waiting are at the foot of the screen.'
        : 'Its ${names.length == 1 ? names.single : '${names.sublist(0, names.length - 1).join(', ')} and ${names.last}'}'
              " ${names.length == 1 ? 'is' : 'are'} waiting to save, and "
              "can't change until then.";
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.cloud_upload_outlined,
            color: theme.colorScheme.onSecondaryContainer,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: TextStyle(color: theme.colorScheme.onSecondaryContainer),
            ),
          ),
        ],
      ),
    );
  }
}

/// Marks a field that's waiting to be saved, beside it.
class WaitingMark extends StatelessWidget {
  const WaitingMark({super.key});

  @override
  Widget build(BuildContext context) => Tooltip(
    message: 'Waiting to save',
    child: Icon(
      Icons.cloud_upload_outlined,
      size: 18,
      color: Theme.of(context).colorScheme.secondary,
    ),
  );
}
