import 'package:flutter/material.dart';

import '../models/event.dart';

/// A change called off by the user: nothing is saved, and the dialog it
/// was made from stays open, as it was.
class CalledOff implements Exception {
  const CalledOff();

  @override
  String toString() => 'Called off: nothing was changed.';
}

/// Asks, before a change cancels [cancels] to make room -- moving or
/// adding an event over them, or clearing their time -- whether each
/// cancellation counts against follow-through: a commitment dropped,
/// rather than a change of plan. Each starts as a change of plan. Returns
/// the ids of those that count, or null if the change was called off.
Future<Set<String>?> askFollowThrough(
  BuildContext context,
  List<Event> cancels,
) async {
  if (cancels.isEmpty) return const {};
  final counts = <String>{};
  final strings = MaterialLocalizations.of(context);
  String when(Event e) =>
      '${strings.formatMediumDate(e.start)}, '
      '${strings.formatTimeOfDay(TimeOfDay.fromDateTime(e.start))} – '
      '${strings.formatTimeOfDay(TimeOfDay.fromDateTime(e.end))}';
  final n = cancels.length;
  final go = await showDialog<bool>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: Text(
          n == 1
              ? 'Cancel an event to make room?'
              : 'Cancel $n events to make room?',
        ),
        content: SizedBox(
          width: 420,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${n == 1 ? 'It goes' : 'They go'} as a change of plan. Turn '
                  "on any that's a commitment dropped: it counts against the "
                  'follow-through of whoever a follow-through trait tracks '
                  'it for.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 8),
                for (final e in cancels)
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(switch (e.summary) {
                      final s? when s.isNotEmpty => s,
                      _ => '(no title)',
                    }),
                    subtitle: Text(
                      '${when(e)}\n'
                      '${counts.contains(e.id) ? 'Counts against follow-through' : 'A change of plan'}',
                    ),
                    isThreeLine: true,
                    value: counts.contains(e.id),
                    onChanged: e.id == null
                        ? null
                        : (on) => setState(
                            () => on ? counts.add(e.id!) : counts.remove(e.id),
                          ),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Keep them'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            child: Text(n == 1 ? 'Cancel it' : 'Cancel them'),
          ),
        ],
      ),
    ),
  );
  return go == true ? counts : null;
}
