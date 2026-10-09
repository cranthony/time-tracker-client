import 'package:flutter/material.dart';

import '../models/event.dart';
import '../models/plan_action.dart';
import '../outbox/event_outbox.dart';
import '../services/plan_memory.dart';
import 'event_names.dart';
import 'event_summary_dialog.dart';

/// A line at the foot of the screen while changes to events wait in
/// [outbox] to be saved: how many, and whether they're being sent,
/// paused, waiting to try again, or stopped at one the server refused.
/// Tapping it shows them ([showEventOutboxSheet]), naming the events a
/// refusal's about from [lookup], each to [onShow]. Nothing, with none.
class EventOutboxBar extends StatelessWidget {
  const EventOutboxBar({
    super.key,
    required this.outbox,
    this.lookup,
    this.onShow,
  });

  final EventOutbox outbox;

  /// The event with an id, if it's known: to name it in a refusal.
  final Event? Function(String id)? lookup;

  /// Shows an event a refusal names, on the timeline.
  final ValueChanged<Event>? onShow;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: outbox,
    builder: (context, _) {
      final pending = outbox.pending;
      if (pending.isEmpty) return const SizedBox.shrink();
      final theme = Theme.of(context);
      final first = pending.first;
      final n = pending.length;
      final changes = n == 1 ? '1 change' : '$n changes';
      final stopped = first.refused;
      final (IconData icon, String text) = switch (first) {
        _ when stopped => (
          Icons.error_outline,
          "Couldn't save ${first.label}: tap to fix it",
        ),
        _ when outbox.paused => (
          Icons.pause_circle_outline,
          'Paused: $changes waiting to save',
        ),
        _ when outbox.needsSignIn => (Icons.login, 'Sign in to save $changes'),
        _ when outbox.isSending(first) => (
          Icons.cloud_upload_outlined,
          'Saving $changes…',
        ),
        PendingEventWrite(:final nextAttemptAt?) => (
          Icons.cloud_off_outlined,
          '$changes waiting: trying again at '
              '${MaterialLocalizations.of(context).formatTimeOfDay(TimeOfDay.fromDateTime(nextAttemptAt))}',
        ),
        _ => (Icons.cloud_upload_outlined, '$changes waiting to save'),
      };
      final background = stopped
          ? theme.colorScheme.errorContainer
          : theme.colorScheme.secondaryContainer;
      final foreground = stopped
          ? theme.colorScheme.onErrorContainer
          : theme.colorScheme.onSecondaryContainer;
      return Material(
        color: background,
        child: InkWell(
          onTap: () => showEventOutboxSheet(
            context,
            outbox,
            lookup: lookup,
            onShow: onShow,
          ),
          child: SafeArea(
            top: false,
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(
                children: [
                  Icon(icon, size: 20, color: foreground),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      text,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: foreground),
                    ),
                  ),
                  Icon(Icons.expand_less, color: foreground),
                ],
              ),
            ),
          ),
        ),
      );
    },
  );
}

/// Makes the [EventOutbox] available to everything below it -- the app
/// menu, to open it ([showEventOutboxSheet]) when nothing's waiting too
/// -- with what [EventOutboxBar] names and shows events by.
class EventOutboxScope extends InheritedWidget {
  const EventOutboxScope({
    super.key,
    required this.outbox,
    this.lookup,
    this.onShow,
    required super.child,
  });

  final EventOutbox outbox;
  final Event? Function(String id)? lookup;
  final ValueChanged<Event>? onShow;

  /// The nearest one, or null if there's none.
  static EventOutboxScope? of(BuildContext context) =>
      context.getInheritedWidgetOfExactType<EventOutboxScope>();

  /// Slides up its changes ([showEventOutboxSheet]).
  Future<void> show(BuildContext context) =>
      showEventOutboxSheet(context, outbox, lookup: lookup, onShow: onShow);

  @override
  bool updateShouldNotify(EventOutboxScope oldWidget) =>
      outbox != oldWidget.outbox;
}

/// Slides up the changes waiting in [outbox], oldest first, as they're
/// sent: each with how it's going -- sending, next, waiting its turn, to
/// be tried again, or refused, and why -- to edit (a change to one event,
/// a new one, or a cancel), approve as changing history, or drop. Above
/// them, pausing or resuming the queue, and trying again now. Event ids
/// in why one was refused are named, from the change itself or else
/// [lookup] ([nameEvents]); those found can be shown on the timeline
/// ([onShow]), closing the sheet.
Future<void> showEventOutboxSheet(
  BuildContext context,
  EventOutbox outbox, {
  Event? Function(String id)? lookup,
  ValueChanged<Event>? onShow,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  builder: (context) => DraggableScrollableSheet(
    expand: false,
    initialChildSize: 0.6,
    builder: (context, controller) => ListenableBuilder(
      listenable: outbox,
      builder: (context, _) => _OutboxList(
        outbox: outbox,
        controller: controller,
        lookup: lookup,
        onShow: onShow,
      ),
    ),
  ),
);

class _OutboxList extends StatelessWidget {
  const _OutboxList({
    required this.outbox,
    required this.controller,
    this.lookup,
    this.onShow,
  });

  final EventOutbox outbox;
  final ScrollController controller;
  final Event? Function(String id)? lookup;
  final ValueChanged<Event>? onShow;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pending = outbox.pending;
    return ListView(
      controller: controller,
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 8, 0),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'Changes waiting to save',
                  style: theme.textTheme.titleLarge,
                ),
              ),
              TextButton.icon(
                onPressed: () => outbox.setPaused(!outbox.paused),
                icon: Icon(outbox.paused ? Icons.play_arrow : Icons.pause),
                label: Text(outbox.paused ? 'Resume' : 'Pause'),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: Text(
            outbox.paused
                ? "Paused: nothing's sent until you resume. Each change, and "
                      "what it changes, stays as it is till it's saved."
                : "Sent in order, each once the one before is saved. Each "
                      "change, and what it changes, stays as it is till it's "
                      'saved.',
            style: theme.textTheme.bodySmall,
          ),
        ),
        if (pending.isEmpty)
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              'Nothing waiting: everything is saved.',
              style: TextStyle(color: theme.hintColor),
            ),
          ),
        for (final (i, write) in pending.indexed)
          _WriteTile(
            outbox: outbox,
            write: write,
            first: i == 0,
            lookup: lookup,
            onShow: onShow,
          ),
        if (pending.isNotEmpty && !outbox.paused)
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: TextButton.icon(
                onPressed: outbox.retryNow,
                icon: const Icon(Icons.refresh),
                label: const Text('Try again now'),
              ),
            ),
          ),
      ],
    );
  }
}

class _WriteTile extends StatelessWidget {
  const _WriteTile({
    required this.outbox,
    required this.write,
    required this.first,
    this.lookup,
    this.onShow,
  });

  final EventOutbox outbox;
  final PendingEventWrite write;
  final bool first;
  final Event? Function(String id)? lookup;
  final ValueChanged<Event>? onShow;

  /// The event with [id]: one this change is of, or in its way, as it
  /// was shown when it was made; or else [lookup]'s.
  Event? _event(String id) {
    for (final e in [
      ?write.event,
      ...write.over.cancels,
      for (final (e, _) in write.over.updates) e,
    ]) {
      if (e.id == id) return e;
    }
    return lookup?.call(id);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sending = outbox.isSending(write);
    final strings = MaterialLocalizations.of(context);
    String at(DateTime t) =>
        strings.formatTimeOfDay(TimeOfDay.fromDateTime(t.toLocal()));
    // Its error, the events in it named: on their day, if it's not today.
    final today = DateUtils.dateOnly(DateTime.now());
    final named = switch (write.lastError) {
      final error? => nameEvents(
        error,
        lookup: _event,
        time: (t) => DateUtils.isSameDay(t.toLocal(), today)
            ? at(t)
            : '${strings.formatShortMonthDay(t.toLocal())}, ${at(t)}',
      ),
      null => null,
    };
    final status = switch (write) {
      _ when sending => 'Sending…',
      PendingEventWrite(refused: true) =>
        "Couldn't save: ${named?.text ?? 'the server said no'}. Nothing "
            "after it is sent till it's changed, approved, or dropped.",
      PendingEventWrite(:final nextAttemptAt?) =>
        "Couldn't send it${named == null ? '' : ' (${named.text})'}: "
            'trying again at ${at(nextAttemptAt)}.',
      _ when first && outbox.paused => 'Next, once resumed.',
      _ when first => 'Next.',
      _ => 'Waiting its turn.',
    };
    return Card(
      margin: const EdgeInsets.fromLTRB(12, 4, 12, 4),
      color: write.refused ? theme.colorScheme.errorContainer : null,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(4, 4, 4, 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ListTile(
              leading: sending
                  ? const SizedBox.square(
                      dimension: 22,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Icon(
                      write.refused
                          ? Icons.error_outline
                          : Icons.cloud_upload_outlined,
                    ),
              title: Text(write.label),
              subtitle: Text(
                '$status\nMade ${strings.formatMediumDate(write.made)}, '
                '${at(write.made)}.',
              ),
              isThreeLine: true,
            ),
            if (named != null && named.events.isNotEmpty && onShow != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    for (final event in named.events)
                      ActionChip(
                        avatar: const Icon(Icons.visibility_outlined),
                        label: Text(
                          'Show ${switch (event.summary) {
                            final s? when s.trim().isNotEmpty => '“${s.trim()}”',
                            _ => 'it',
                          }}',
                        ),
                        onPressed: () {
                          Navigator.of(context).pop();
                          onShow!(event);
                        },
                      ),
                  ],
                ),
              ),
            if (!sending)
              Wrap(
                alignment: WrapAlignment.end,
                spacing: 4,
                children: [
                  if (write.refusedAsHistory)
                    TextButton(
                      onPressed: () => _approveHistory(context),
                      child: const Text('Change history'),
                    ),
                  if (write.refused && !write.refusedAsHistory)
                    TextButton(
                      onPressed: () => outbox.retryNow(),
                      child: const Text('Try again'),
                    ),
                  if (_editable(write))
                    TextButton(
                      onPressed: () => _edit(context),
                      child: const Text('Edit'),
                    ),
                  TextButton(
                    onPressed: () => _drop(context),
                    child: const Text('Drop'),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  /// Whether it can be edited here: a change to one event, a new one, or
  /// a cancel. One that moves others too is dropped and made again.
  static bool _editable(PendingEventWrite write) => switch (write.kind) {
    EventWriteKind.update ||
    EventWriteKind.create ||
    EventWriteKind.cancel => true,
    _ => false,
  };

  Future<void> _approveHistory(BuildContext context) async {
    final approved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Change history?'),
        content: const Text(
          'Compaction has already recorded this as what happened. Changing '
          'it rewrites that record.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Keep history'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Change it'),
          ),
        ],
      ),
    );
    if (approved == true) await outbox.approveHistory(write);
  }

  Future<void> _drop(BuildContext context) async {
    final sure = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Drop ${write.label}?'),
        content: const Text(
          "It won't be saved: what it changed goes back to how the server "
          'has it. A change after it that counted on it may then be '
          'refused.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Keep it'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Drop it'),
          ),
        ],
      ),
    );
    if (sure != true) return;
    if (!await outbox.drop(write) && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("It's being sent: it can't be dropped.")),
      );
    }
  }

  /// Opens what it writes as it'll be, to change: an event's fields, or a
  /// cancel's follow-through. Saving replaces it, in its place.
  Future<void> _edit(BuildContext context) async {
    if (write.kind == EventWriteKind.cancel) return _editCancel(context);
    final shown = <String, Event>{};
    write.projectEvents(shown);
    final event = switch (write.kind) {
      EventWriteKind.create => shown[write.pendingId()],
      _ => shown[write.event?.id],
    };
    if (event == null) return;
    final actions = {
      for (final a
          in PlanMemoryScope.of(context)?.actions?.actions ??
              const <PlanAction>[])
        ?a.id: a,
    };
    await showEventSummaryDialog(
      context,
      // Not yet saved: edited here, not by id.
      Event.fromJson({
        ...event.toJson(),
        'id': write.event?.id ?? write.pendingId(),
      }),
      actions: actions,
      save: (changes) async {
        await outbox.edit(
          write,
          write.kind == EventWriteKind.create
              ? write.copyWith(fields: {...write.fields, ...changes})
              : write.copyWith(changes: {...write.changes, ...changes}),
        );
        return const [];
      },
    );
  }

  Future<void> _editCancel(BuildContext context) async {
    var counts = write.countsAgainstFollowThrough;
    final save = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text(write.label),
          content: SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Count against follow-through'),
            subtitle: const Text(
              'A commitment dropped, not just a change of plan.',
            ),
            value: counts,
            onChanged: (on) => setState(() => counts = on),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    if (save == true) {
      await outbox.edit(
        write,
        write.copyWith(countsAgainstFollowThrough: counts),
      );
    }
  }
}
