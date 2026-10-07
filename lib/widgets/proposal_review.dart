import 'package:flutter/material.dart';

import '../models/event.dart';
import '../models/facts.dart';
import '../models/proposal.dart';
import 'error_sheet.dart';
import 'day_timeline.dart';
import 'time_summary.dart';

/// [start] to [end] in a few words: "7:30 AM – 1:30 PM" in a day, or
/// with their dates, "Oct 1, 9:00 PM – Oct 2, 1:30 PM", across days.
String windowLabel(BuildContext context, DateTime start, DateTime end) {
  final strings = MaterialLocalizations.of(context);
  String time(DateTime t) =>
      strings.formatTimeOfDay(TimeOfDay.fromDateTime(t.toLocal()));
  final (from, to) = (start.toLocal(), end.toLocal());
  if (from.year == to.year && from.month == to.month && from.day == to.day) {
    return '${time(from)} – ${time(to)}';
  }
  return '${strings.formatShortMonthDay(from)}, ${time(from)} – '
      '${strings.formatShortMonthDay(to)}, ${time(to)}';
}

/// What [event] says the proposal does to it, as its [EventMark]: moved
/// (and from where), renamed, its actions or facts set, new, cancelled or
/// merged -- and by whom -- against [calendar], the calendar's own event,
/// if it has one; nothing for one as planned. [changed] since the user
/// last looked.
EventMark proposalMark(
  ProposalEvent event, {
  Event? calendar,
  bool changed = false,
  bool selected = false,
  required String Function(DateTime) time,
}) {
  final by = switch (event.decidedBy) {
    DecidedBy.claude => 'Claude',
    DecidedBy.user => 'you',
    null => null,
  };
  final what = switch (event.status) {
    ProposalEventStatus.created => ['New'],
    ProposalEventStatus.cancelled => [
      if (!(event.countsAgainstFollowThrough ?? true))
        'Cancelled, a change of plan'
      else if (event.followThrough.isEmpty)
        'Cancelled, counts against follow-through'
      else
        'Cancelled, counts against ${event.followThrough.join(', ')}',
    ],
    ProposalEventStatus.merged => ['Merged'],
    ProposalEventStatus.adjusted => [
      if (event.moved)
        'Moved, was ${time(event.plannedStart ?? event.start)}–'
            '${time(event.plannedEnd ?? event.end)}',
      if (calendar != null && calendar.summary != event.summary) 'Renamed',
      if (calendar != null && !_same(calendar.actionIds, event.actionIds))
        'New actions',
      if (calendar != null &&
          Facts.fromJson(calendar.properties['facts']) !=
              Facts.fromJson(event.facts))
        'New facts',
      if (calendar == null && !event.moved) 'Changed',
    ],
    ProposalEventStatus.onSchedule ||
    ProposalEventStatus.planned => [if (changed) 'As planned'],
  };
  if (what.isEmpty) return EventMark(changed: changed, selected: selected);
  return EventMark(
    label: [what.join(' · '), ?by].join(' · '),
    icon: switch (event.status) {
      ProposalEventStatus.cancelled ||
      ProposalEventStatus.merged => Icons.close,
      ProposalEventStatus.created => Icons.add,
      _ => null,
    },
    changed: changed,
    selected: selected,
  );
}

bool _same(List<String> a, List<String> b) =>
    a.length == b.length &&
    [for (var i = 0; i < a.length; i++) a[i] == b[i]].every((same) => same);

/// The bar over the Events page while a compaction proposal is open:
/// what happened from its window's start to its `through`, to confirm.
/// "Confirm ... happened as shown" calls [onConfirm]; "Note for Claude",
/// [onNote]; the notes' button, [onNotes]. While a note is open it's
/// waiting for Claude, and can't be confirmed. One whose apply stopped
/// partway offers to [onRetry]. Tapping its heading calls [onGoTo];
/// its menu offers to [onAbandon] it. [changes] events changed since the
/// user last looked. While [busy], nothing can be tapped.
class ProposalBar extends StatelessWidget {
  const ProposalBar({
    super.key,
    required this.proposal,
    this.busy = false,
    this.changes = 0,
    this.onConfirm,
    this.onNote,
    this.onNotes,
    this.onRetry,
    this.onGoTo,
    this.onAbandon,
  });

  final Proposal proposal;
  final bool busy;
  final int changes;
  final VoidCallback? onConfirm;
  final VoidCallback? onNote;
  final VoidCallback? onNotes;
  final VoidCallback? onRetry;
  final VoidCallback? onGoTo;
  final VoidCallback? onAbandon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final band = reviewColors(colors);
    final window = windowLabel(context, proposal.windowStart, proposal.through);
    final open = proposal.openFeedback.length;
    final notes = [
      for (final f in proposal.feedback)
        if (f.status != FeedbackStatus.withdrawn) f,
    ].length;
    final stopped = proposal.state == ProposalState.applying;
    final muted = colors.onSurfaceVariant;
    final status = <(IconData, String, Color)>[
      if (stopped)
        (
          Icons.error_outline,
          'Applying it stopped partway. Retry to finish.',
          colors.error,
        )
      else if (open > 0)
        (
          Icons.hourglass_top,
          'Waiting for Claude: $open note${open == 1 ? '' : 's'} open. '
              'Claude picks ${open == 1 ? 'it' : 'them'} up on its next '
              'run, or ask it in a conversation.',
          colors.secondary,
        ),
      if (proposal.events == null)
        (
          Icons.report_outlined,
          proposal.problem ?? 'It no longer fits the calendar.',
          colors.error,
        ),
      if (changes > 0 && !stopped)
        (
          Icons.circle,
          '$changes event${changes == 1 ? '' : 's'} changed since you '
              'looked.',
          colors.secondary,
        ),
    ];
    return Material(
      color: Color.alphaBlend(band.tint, colors.surface),
      shape: Border(
        top: BorderSide(color: band.line, width: 2),
        bottom: BorderSide(color: band.line, width: 2),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 4, 4, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Icon(Icons.fact_check_outlined, color: band.line, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: InkWell(
                    onTap: onGoTo,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'What happened — to confirm',
                            style: theme.textTheme.titleSmall,
                          ),
                          Text(
                            '$window · revision ${proposal.revision}',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: muted,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                if (busy)
                  const Padding(
                    padding: EdgeInsets.all(12),
                    child: SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                PopupMenuButton<VoidCallback>(
                  tooltip: 'More',
                  enabled: !busy,
                  onSelected: (action) => action(),
                  itemBuilder: (context) => [
                    if (onGoTo case final goTo?)
                      PopupMenuItem(value: goTo, child: const Text('Go to it')),
                    if (onAbandon case final abandon?)
                      PopupMenuItem(
                        value: abandon,
                        child: const Text('Abandon it'),
                      ),
                  ],
                ),
              ],
            ),
            for (final (icon, text, color) in status)
              Padding(
                padding: const EdgeInsets.only(right: 8, bottom: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 1),
                      child: Icon(
                        icon,
                        size: icon == Icons.circle ? 10 : 16,
                        color: color,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        text,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: color,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Wrap(
                spacing: 8,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  if (stopped)
                    FilledButton.icon(
                      onPressed: busy ? null : onRetry,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Retry'),
                    )
                  else
                    Tooltip(
                      message: open > 0
                          ? 'Waiting for Claude to answer your notes'
                          : 'Record it as what happened',
                      child: FilledButton(
                        onPressed: busy || !proposal.confirmable
                            ? null
                            : onConfirm,
                        child: Text(
                          open > 0
                              ? 'Waiting for Claude'
                              : 'Confirm $window happened as shown',
                        ),
                      ),
                    ),
                  if (!stopped)
                    OutlinedButton.icon(
                      onPressed: busy ? null : onNote,
                      icon: const Icon(Icons.add_comment_outlined, size: 18),
                      label: const Text('Note for Claude'),
                    ),
                  if (notes > 0 || proposal.warnings.isNotEmpty)
                    TextButton.icon(
                      onPressed: busy ? null : onNotes,
                      icon: const Icon(Icons.forum_outlined, size: 18),
                      label: Text('Notes ($notes)'),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// What the notes sheet was closed to do.
sealed class NotesSheetAction {
  const NotesSheetAction();
}

/// Withdraw [feedback].
final class WithdrawNote extends NotesSheetAction {
  const WithdrawNote(this.feedback);
  final ProposalFeedback feedback;
}

/// Leave another note.
final class AddNote extends NotesSheetAction {
  const AddNote();
}

/// Shows [proposal]'s notes for Claude -- each with Claude's reply beside
/// it, once it's answered, or else a button to withdraw it -- and its
/// warnings. [names] names the events notes are about, by id, and
/// [noteNames] the time notes.
Future<NotesSheetAction?> showProposalNotesSheet(
  BuildContext context,
  Proposal proposal, {
  Map<String, String> names = const {},
  Map<String, String> noteNames = const {},
}) => showModalBottomSheet<NotesSheetAction>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  builder: (context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final notes = [
      for (final f in proposal.feedback)
        if (f.status != FeedbackStatus.withdrawn) f,
    ];
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      maxChildSize: 0.9,
      builder: (context, scroll) => ListView(
        controller: scroll,
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        children: [
          Text('Notes for Claude', style: theme.textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            "Claude revises what happened from them. While one's waiting "
            "for Claude's answer, this can't be confirmed.",
            style: theme.textTheme.bodySmall?.copyWith(
              color: colors.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          if (notes.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text('No notes yet.'),
            ),
          for (final note in notes)
            _NoteCard(
              note: note,
              about: names[note.eventId] ?? noteNames[note.noteId],
              onWithdraw: note.open && note.byUser
                  ? () => Navigator.of(context).pop(WithdrawNote(note))
                  : null,
            ),
          if (proposal.warnings.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text('Warnings', style: theme.textTheme.titleSmall),
            for (final warning in proposal.warnings)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text('• $warning'),
              ),
          ],
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: () => Navigator.of(context).pop(const AddNote()),
              icon: const Icon(Icons.add_comment_outlined, size: 18),
              label: const Text('Note for Claude'),
            ),
          ),
        ],
      ),
    );
  },
);

/// One note: who left it, on what, and Claude's reply beside it.
class _NoteCard extends StatelessWidget {
  const _NoteCard({required this.note, this.about, this.onWithdraw});

  final ProposalFeedback note;
  final String? about;
  final VoidCallback? onWithdraw;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final small = theme.textTheme.bodySmall;
    return Card.outlined(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    [
                      note.byUser ? 'You' : 'The server',
                      if (about != null) 'on “$about”',
                    ].join(', '),
                    style: small?.copyWith(color: colors.onSurfaceVariant),
                  ),
                ),
                if (note.open)
                  Text(
                    'Waiting for Claude',
                    style: small?.copyWith(color: colors.secondary),
                  ),
                if (onWithdraw != null)
                  TextButton(
                    onPressed: onWithdraw,
                    child: const Text('Withdraw'),
                  )
                else
                  const SizedBox(width: 8, height: 40),
              ],
            ),
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Text(note.text),
            ),
            if (note.reply case final reply?)
              Container(
                margin: const EdgeInsets.only(top: 8, right: 8),
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: colors.secondaryContainer,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Claude'
                      '${note.answeredIn == null ? '' : ', in revision ${note.answeredIn}'}',
                      style: small?.copyWith(
                        color: colors.onSecondaryContainer,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      reply,
                      style: TextStyle(color: colors.onSecondaryContainer),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Asks for a note for Claude, about one of [events] (by id, with its
/// name) or none, [about] to start with -- or, given a [subject], about
/// that. Returns its text and event, or null if it was called off.
Future<({String text, String? eventId})?> showProposalNoteDialog(
  BuildContext context, {
  Map<String, String> events = const {},
  String? about,
  String? subject,
}) => showDialog(
  context: context,
  builder: (context) =>
      _NoteDialog(events: events, about: about, subject: subject),
);

class _NoteDialog extends StatefulWidget {
  const _NoteDialog({required this.events, this.about, this.subject});

  final Map<String, String> events;
  final String? about;
  final String? subject;

  @override
  State<_NoteDialog> createState() => _NoteDialogState();
}

class _NoteDialogState extends State<_NoteDialog> {
  final _text = TextEditingController();
  late String? _about = widget.events.containsKey(widget.about)
      ? widget.about
      : null;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _leave() {
    final text = _text.text.trim();
    if (text.isEmpty) return;
    Navigator.of(context).pop((text: text, eventId: _about));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: const Text('Note for Claude'),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Claude revises what happened from it, on its next run -- or '
              "ask it in a conversation. Until it's answered, this can't be "
              'confirmed.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            if (widget.subject case final subject?)
              Text(subject, style: theme.textTheme.titleSmall)
            else if (widget.events.isNotEmpty)
              DropdownButtonFormField<String?>(
                initialValue: _about,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'About'),
                items: [
                  const DropdownMenuItem(value: null, child: Text('All of it')),
                  for (final MapEntry(:key, :value) in widget.events.entries)
                    DropdownMenuItem(
                      value: key,
                      child: Text(value, overflow: TextOverflow.ellipsis),
                    ),
                ],
                onChanged: (value) => setState(() => _about = value),
              ),
            const SizedBox(height: 12),
            TextField(
              controller: _text,
              autofocus: true,
              minLines: 2,
              maxLines: 6,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                hintText: 'What should Claude change?',
                border: OutlineInputBorder(),
              ),
              onChanged: (_) => setState(() {}),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _text.text.trim().isEmpty ? null : _leave,
          child: const Text('Leave note'),
        ),
      ],
    );
  }
}

/// Says the calendar changed since [proposal] was planned, so it was
/// planned again: [message], and the events that changed ([names]).
/// True to confirm it again, as it is now; else it's to be reviewed.
Future<bool> showRecheckedDialog(
  BuildContext context,
  Proposal proposal, {
  String? message,
  List<String> names = const [],
}) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('The calendar changed'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              message ??
                  'It changed since this was planned, so it was planned '
                      'again (revision ${proposal.revision}).',
            ),
            if (names.isNotEmpty) ...[
              const SizedBox(height: 12),
              const Text('What changed:'),
              for (final name in names) Text('• $name'),
            ],
            const SizedBox(height: 12),
            Text(
              'Confirm ${windowLabel(context, proposal.windowStart, proposal.through)} '
              'again as it is now, or review it first?',
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Review it'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Confirm again'),
          ),
        ],
      ),
    ) ??
    false;

/// What became of [note], as the timeline marks it.
ReviewNoteKind reviewNoteKind(ProposalNote note) => switch (note.use) {
  _ when note.compacted => ReviewNoteKind.compacted,
  NoteUse.edge => ReviewNoteKind.setsEdge,
  NoteUse.annotates => ReviewNoteKind.annotated,
  NoteUse.ignored => ReviewNoteKind.ignored,
  NoteUse.unused => ReviewNoteKind.other,
};

/// What the proposal does with [note], in words, and who said so: "Sets
/// the start of Breakfast", "Added to “Work” · you", "Left out · Claude".
/// [events] names the events, by id or key.
String noteFate(ProposalNote note, {Map<String, String> events = const {}}) {
  if (note.compacted) return 'Compacted earlier';
  final event = events[note.eventId] ?? note.annotates;
  // The edge it sets, whatever else it's for.
  final edge = switch (events[note.edgeOf ?? '']) {
    _ when note.anchors.isNotEmpty =>
      'Sets the ${note.anchors.join(' and the ')}',
    final name? => 'Sets an edge of “$name”',
    _ when note.use == NoteUse.edge =>
      'Sets ${event == null ? 'an edge' : 'an edge of “$event”'}',
    _ => null,
  };
  final what = switch (note.use) {
    NoteUse.edge => null,
    NoteUse.annotates => 'Added to ${event == null ? 'an event' : '“$event”'}',
    NoteUse.ignored => 'Left out',
    NoteUse.unused => 'Not added: no event to add it to',
  };
  return [
    ?edge,
    ?what,
    ?switch (note.decidedBy) {
      DecidedBy.claude => 'Claude',
      DecidedBy.user => 'you',
      null => null,
    },
  ].join(' · ');
}

/// One of a run of things to review, in a [ProposalDetails] page: a
/// [badge], its [title] and what it [says], [actions] beside it, then
/// which it is -- the [index]th of [count] -- and buttons to go to the one
/// before it ([onPrevious]) and after it ([onNext]), named [what]. Tapping
/// it calls [onTap].
class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.badge,
    required this.title,
    required this.what,
    required this.index,
    required this.count,
    this.says,
    this.saysColor,
    this.actions = const [],
    this.onPrevious,
    this.onNext,
    this.onTap,
  });

  final IconData badge;
  final InlineSpan title;
  final String what;
  final int index;
  final int count;
  final String? says;
  final Color? saysColor;
  final List<Widget> actions;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Row(
      children: [
        Container(
          width: 22,
          height: 22,
          decoration: BoxDecoration(
            color: colors.primary,
            shape: BoxShape.circle,
          ),
          child: Icon(badge, size: 14, color: colors.onPrimary),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: InkWell(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text.rich(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium,
                  ),
                  if (says case final says? when says.isNotEmpty)
                    Text(
                      says,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: saysColor ?? colors.tertiary,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
        ...actions,
        Text(
          '${index + 1}/$count',
          style: theme.textTheme.labelSmall?.copyWith(
            color: colors.onSurfaceVariant,
          ),
        ),
        IconButton(
          tooltip: 'Previous $what',
          visualDensity: VisualDensity.compact,
          onPressed: onPrevious,
          icon: const Icon(Icons.keyboard_arrow_up),
        ),
        IconButton(
          tooltip: 'Next $what',
          visualDensity: VisualDensity.compact,
          onPressed: onNext,
          icon: const Icon(Icons.keyboard_arrow_down),
        ),
      ],
    );
  }
}

/// [time] as the device says times of day: "7:50 AM".
String _time(BuildContext context, DateTime time) =>
    MaterialLocalizations.of(context)
        .formatTimeOfDay(TimeOfDay.fromDateTime(time.toLocal()));

/// One of the proposal's notes -- the [index]th of [count] -- its time and
/// text, and what became of it, with buttons to go to the note before it
/// ([onPrevious]) and after it ([onNext]). Tapping it, or its pencil,
/// calls [onEdit], to say what it's for. [events] names the events, by id
/// or key.
class ProposalNoteStrip extends StatelessWidget {
  const ProposalNoteStrip({
    super.key,
    required this.note,
    required this.index,
    required this.count,
    this.events = const {},
    this.onPrevious,
    this.onNext,
    this.onEdit,
  });

  final ProposalNote note;
  final Map<String, String> events;
  final int index;
  final int count;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final kind = reviewNoteKind(note);
    return _DetailRow(
      badge: kind.icon,
      what: 'note',
      index: index,
      count: count,
      title: TextSpan(
        children: [
          TextSpan(
            text: '${_time(context, note.time)}  ',
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          TextSpan(text: note.text ?? '(no text)'),
        ],
      ),
      says: noteFate(note, events: events),
      saysColor:
          kind == ReviewNoteKind.ignored || kind == ReviewNoteKind.compacted
          ? colors.onSurfaceVariant
          : null,
      actions: [
        if (onEdit != null)
          IconButton(
            tooltip: 'What this note is for',
            visualDensity: VisualDensity.compact,
            onPressed: onEdit,
            icon: const Icon(Icons.edit_note),
          ),
      ],
      onPrevious: onPrevious,
      onNext: onNext,
      onTap: onEdit,
    );
  }
}

/// One of the proposal's cancels -- the [index]th of [count] -- the event
/// that didn't happen, and whether that counts against follow-through,
/// and whose: its switch calls [onCounts] to say otherwise. With buttons
/// to go to the cancel before it ([onPrevious]) and after it ([onNext]),
/// and tapping it, [onTap], to show it.
class ProposalCancelStrip extends StatelessWidget {
  const ProposalCancelStrip({
    super.key,
    required this.event,
    required this.index,
    required this.count,
    this.onCounts,
    this.onPrevious,
    this.onNext,
    this.onTap,
  });

  final ProposalEvent event;
  final int index;
  final int count;
  final ValueChanged<bool>? onCounts;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final counts = event.countsAgainstFollowThrough ?? true;
    return _DetailRow(
      badge: Icons.close,
      what: 'cancel',
      index: index,
      count: count,
      title: TextSpan(
        children: [
          TextSpan(
            text: '${_time(context, event.start)}  ',
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          TextSpan(
            text: switch (event.summary) {
              final s? when s.isNotEmpty => s,
              _ => '(no summary)',
            },
          ),
        ],
      ),
      says: [
        if (!counts)
          'A change of plan: no one’s follow-through'
        else if (event.followThrough.isEmpty)
          'Counts against follow-through: no one’s tracked'
        else
          'Counts against ${event.followThrough.join(', ')}',
        ?switch (event.decidedBy) {
          DecidedBy.claude => 'Claude',
          DecidedBy.user => 'you',
          null => null,
        },
      ].join(' · '),
      saysColor: counts ? colors.error : colors.onSurfaceVariant,
      actions: [
        Tooltip(
          message: 'Counts against follow-through',
          child: Switch(
            value: counts,
            onChanged: onCounts,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
        ),
        const SizedBox(width: 4),
      ],
      onPrevious: onPrevious,
      onNext: onNext,
      onTap: onTap,
    );
  }
}

/// A person, action or location the proposal adds -- the [index]th of
/// [count] -- what it's called, the events it's used at ([uses]), and,
/// once the user's [settled] it, how: made now, found among those there
/// ([settledAs] names it), or dropped. Tapping it, or its button, calls
/// [onSettle], to settle it, or say otherwise; with buttons to go to the
/// one before it ([onPrevious]) and after it ([onNext]).
class ProposalAdditionStrip extends StatelessWidget {
  const ProposalAdditionStrip({
    super.key,
    required this.addition,
    required this.index,
    required this.count,
    this.settled,
    this.settledAs,
    this.uses = const [],
    this.onSettle,
    this.onPrevious,
    this.onNext,
  });

  final ProposalAddition addition;
  final int index;
  final int count;
  final AdditionSettled? settled;
  final String? settledAs;
  final List<String> uses;
  final VoidCallback? onSettle;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final dropped = settled?.use == AdditionUse.drop;
    return _DetailRow(
      badge: dropped ? Icons.block : additionIcon(addition.kind),
      what: 'addition',
      index: index,
      count: count,
      title: TextSpan(
        children: [
          TextSpan(
            text: 'New ${addition.kind.label.toLowerCase()}  ',
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          TextSpan(
            text: addition.name,
            style: dropped
                ? const TextStyle(decoration: TextDecoration.lineThrough)
                : null,
          ),
        ],
      ),
      says: [
        ?addition.detail,
        additionState(settled, settledAs),
        if (!dropped)
          if (uses.isEmpty)
            'Not used at any event'
          else
            'At ${uses.join(', ')}',
      ].join(' · '),
      saysColor: settled == null ? colors.secondary : null,
      actions: [
        if (onSettle != null)
          IconButton(
            tooltip: settled == null ? 'Settle it' : 'Change how it’s settled',
            visualDensity: VisualDensity.compact,
            onPressed: onSettle,
            icon: const Icon(Icons.rule),
          ),
      ],
      onPrevious: onPrevious,
      onNext: onNext,
      onTap: onSettle,
    );
  }
}

/// How an addition was [settled], in words: still to settle, made now,
/// one already there ([settledAs]), or dropped.
String additionState(AdditionSettled? settled, String? settledAs) =>
    switch (settled?.use) {
      null => 'To settle: made when it’s confirmed',
      AdditionUse.create => 'Made now · you',
      AdditionUse.existing =>
        'Already here: ${settledAs ?? settled!.id ?? 'one there'} · you',
      AdditionUse.drop => 'Dropped: not real · you',
    };

/// What the user said is to become of an addition, from
/// [showAdditionSheet].
sealed class AdditionChoice {
  const AdditionChoice();
}

/// Make it now, called [name], with a person's context or a location's
/// hint, [detail].
final class CreateAddition extends AdditionChoice {
  const CreateAddition(this.name, this.detail);
  final String name;
  final String? detail;
}

/// It's [id], already there.
final class UseExisting extends AdditionChoice {
  const UseExisting(this.id);
  final String id;
}

/// It's not real.
final class DropAddition extends AdditionChoice {
  const DropAddition();
}

/// Put it back as Claude proposed it, to settle later.
final class UnsettleAddition extends AdditionChoice {
  const UnsettleAddition();
}

/// Leave a note for Claude about it.
final class AskAboutAddition extends AdditionChoice {
  const AskAboutAddition();
}

/// Asks what's to become of [addition]: made now, as Claude has it or
/// corrected; one already there, of [existing] (by id, with its name and
/// what tells it apart), searched by name; or dropped. Once it's
/// [settled], it can be put back as Claude proposed it. Either way, it can
/// be asked about, in a note for Claude.
Future<AdditionChoice?> showAdditionSheet(
  BuildContext context,
  ProposalAddition addition, {
  AdditionSettled? settled,
  String? settledAs,
  List<({String id, String name, String? detail})> existing = const [],
}) => showModalBottomSheet<AdditionChoice>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  builder: (context) => _AdditionSheet(
    addition: addition,
    settled: settled,
    settledAs: settledAs,
    existing: existing,
  ),
);

class _AdditionSheet extends StatefulWidget {
  const _AdditionSheet({
    required this.addition,
    required this.settled,
    required this.settledAs,
    required this.existing,
  });

  final ProposalAddition addition;
  final AdditionSettled? settled;
  final String? settledAs;
  final List<({String id, String name, String? detail})> existing;

  @override
  State<_AdditionSheet> createState() => _AdditionSheetState();
}

class _AdditionSheetState extends State<_AdditionSheet> {
  late final _search = TextEditingController(text: widget.addition.name);

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  /// [widget.existing] that match the search, best first: named with it,
  /// then naming any word of it.
  List<({String id, String name, String? detail})> get _matches {
    final query = _search.text.trim().toLowerCase();
    if (query.isEmpty) return widget.existing;
    final words = query.split(RegExp(r'\s+'));
    int score(String name) {
      final n = name.toLowerCase();
      if (n.startsWith(query)) return 0;
      if (n.contains(query)) return 1;
      if (words.any(n.contains)) return 2;
      return 3;
    }

    return [
      for (final e in widget.existing)
        if (score(e.name) < 3) e,
    ]..sort((a, b) => score(a.name).compareTo(score(b.name)));
  }

  Future<void> _create() async {
    final a = widget.addition;
    final made = await showDialog<CreateAddition>(
      context: context,
      builder: (context) => _CreateAdditionDialog(addition: a),
    );
    if (made != null && mounted) Navigator.of(context).pop(made);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final a = widget.addition;
    final kind = a.kind.label.toLowerCase();
    final settled = widget.settled;
    final matches = _matches;
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      maxChildSize: 0.95,
      builder: (context, scroll) => ListView(
        controller: scroll,
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
            child: Text(
              'New $kind: ${a.name}',
              style: theme.textTheme.titleMedium,
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(
              [?a.detail, additionState(settled, widget.settledAs)].join('\n'),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          if (settled == null) ...[
            ListTile(
              leading: Icon(additionIcon(a.kind)),
              title: const Text('Make it now'),
              subtitle: Text(
                'As Claude has it, or corrected. It stays, whatever becomes '
                'of the proposal.',
              ),
              onTap: _create,
            ),
            ListTile(
              leading: const Icon(Icons.block),
              title: const Text('Drop it'),
              subtitle: const Text('Not real: take it out of every event'),
              onTap: () => Navigator.of(context).pop(const DropAddition()),
            ),
          ] else
            ListTile(
              leading: const Icon(Icons.undo),
              title: const Text('Put it back as Claude proposed it'),
              subtitle: const Text('To settle later'),
              onTap: () => Navigator.of(context).pop(const UnsettleAddition()),
            ),
          ListTile(
            leading: const Icon(Icons.add_comment_outlined),
            title: const Text('Ask Claude about it'),
            subtitle: Text('Leave a note for Claude about this $kind'),
            onTap: () => Navigator.of(context).pop(const AskAboutAddition()),
          ),
          if (settled == null && widget.existing.isNotEmpty) ...[
            const Divider(),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: Text(
                'Or it’s one already here',
                style: theme.textTheme.titleSmall,
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                controller: _search,
                decoration: InputDecoration(
                  isDense: true,
                  prefixIcon: const Icon(Icons.search),
                  hintText: 'Find a $kind',
                  border: const OutlineInputBorder(),
                ),
                onChanged: (_) => setState(() {}),
              ),
            ),
            if (matches.isEmpty)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text('None by that name.'),
              ),
            for (final e in matches.take(30))
              ListTile(
                dense: true,
                title: Text(e.name),
                subtitle: e.detail == null ? null : Text(e.detail!),
                onTap: () => Navigator.of(context).pop(UseExisting(e.id)),
              ),
          ],
        ],
      ),
    );
  }
}

/// Asks what a new [addition] is to be made as: its name, and a person's
/// context or a location's hint, as Claude has them to start with.
class _CreateAdditionDialog extends StatefulWidget {
  const _CreateAdditionDialog({required this.addition});

  final ProposalAddition addition;

  @override
  State<_CreateAdditionDialog> createState() => _CreateAdditionDialogState();
}

class _CreateAdditionDialogState extends State<_CreateAdditionDialog> {
  late final _name = TextEditingController(text: widget.addition.name);
  late final _detail = TextEditingController(text: widget.addition.detail);

  @override
  void dispose() {
    _name.dispose();
    _detail.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final a = widget.addition;
    final detail = switch (a.kind) {
      AdditionKind.person => 'Context: what tells them apart',
      AdditionKind.location => 'Hint: other names, an address',
      AdditionKind.action => null,
    };
    return AlertDialog(
      title: Text('Make the ${a.kind.label.toLowerCase()} now'),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _name,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Name'),
              onChanged: (_) => setState(() {}),
            ),
            if (detail != null)
              TextField(
                controller: _detail,
                decoration: InputDecoration(labelText: detail),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _name.text.trim().isEmpty
              ? null
              : () => Navigator.of(context).pop(
                  CreateAddition(
                    _name.text.trim(),
                    detail == null || _detail.text.trim().isEmpty
                        ? null
                        : _detail.text.trim(),
                  ),
                ),
          child: const Text('Make it'),
        ),
      ],
    );
  }
}

/// The icon for a new [kind] of thing.
IconData additionIcon(AdditionKind kind) => switch (kind) {
  AdditionKind.person => Icons.person_add_alt,
  AdditionKind.action => Icons.add_task,
  AdditionKind.location => Icons.add_location_alt,
};

/// What there is to look at in a proposal, under its bar: its [notes],
/// how many of its cancels count against follow-through ([cancels], of
/// [cancelCount]), and what it [adds] -- each a page, under its title,
/// swiped or tapped between. Its chevron folds it away
/// ([onCollapsed]); [onPage] hears which page it's turned to. A page with
/// nothing on it is left out.
class ProposalDetails extends StatelessWidget {
  const ProposalDetails({
    super.key,
    this.notes,
    this.noteCount = 0,
    this.cancels,
    this.cancelCount = 0,
    this.counting = 0,
    this.adds,
    this.addCount = 0,
    this.collapsed = false,
    this.onCollapsed,
    this.initialPage = 0,
    this.onPage,
  });

  final Widget? notes;
  final int noteCount;
  final Widget? cancels;
  final int cancelCount;

  /// How many of the cancels count against follow-through.
  final int counting;
  final Widget? adds;
  final int addCount;
  final bool collapsed;
  final ValueChanged<bool>? onCollapsed;

  /// Which of [ProposalDetailPage]'s to open on.
  final int initialPage;
  final ValueChanged<ProposalDetailPage>? onPage;

  /// The pages it has, in order.
  List<ProposalDetailPage> get pages => [
    if (notes != null) ProposalDetailPage.notes,
    if (cancels != null) ProposalDetailPage.followThrough,
    if (adds != null) ProposalDetailPage.added,
  ];

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final pages = this.pages;
    if (pages.isEmpty) return const SizedBox.shrink();
    return TimeSummary(
      // Started again when what it has changes.
      key: ValueKey(pages.map((p) => p.name).join(',')),
      color: Color.alphaBlend(
        reviewColors(colors).tint,
        colors.surfaceContainerLow,
      ),
      showLabel: 'Show notes, follow-through and additions',
      hideLabel: 'Hide notes, follow-through and additions',
      collapsed: collapsed,
      onCollapsed: onCollapsed,
      initialPage: initialPage.clamp(0, pages.length - 1),
      onPage: onPage == null ? null : (i) => onPage!(pages[i]),
      titles: [
        for (final page in pages)
          switch (page) {
            ProposalDetailPage.notes => 'Notes ($noteCount)',
            ProposalDetailPage.followThrough =>
              'Follow-through ($counting of $cancelCount)',
            ProposalDetailPage.added => 'Added ($addCount)',
          },
      ],
      pages: [
        for (final page in pages)
          switch (page) {
            ProposalDetailPage.notes => notes!,
            ProposalDetailPage.followThrough => cancels!,
            ProposalDetailPage.added => adds!,
          },
      ],
    );
  }
}

/// A page of [ProposalDetails].
enum ProposalDetailPage { notes, followThrough, added }

/// What the user said a note is for, from [showNoteUseSheet].
sealed class NoteUseChoice {
  const NoteUseChoice();
}

/// Add the note to [eventId], or, without one, to the event it falls
/// within.
final class AnnotateNote extends NoteUseChoice {
  const AnnotateNote([this.eventId]);
  final String? eventId;
}

/// Leave the note out.
final class IgnoreNote extends NoteUseChoice {
  const IgnoreNote();
}

/// Put the note back as Claude had it.
final class NoteAsClaudeHadIt extends NoteUseChoice {
  const NoteAsClaudeHadIt();
}

/// Leave a note for Claude about it.
final class AskClaudeAboutNote extends NoteUseChoice {
  const AskClaudeAboutNote();
}

/// Asks what [note] is for: added to the event it falls within, or whose
/// edge it sets -- [fallsIn], if there's one -- or to another of [events] (by id or key,
/// with their names: those of its day), left out, put back as Claude had
/// it (once the user's said what it's for), or asked about, in a note for
/// Claude.
Future<NoteUseChoice?> showNoteUseSheet(
  BuildContext context,
  ProposalNote note, {
  Map<String, String> events = const {},
  String? fallsIn,
}) => showModalBottomSheet<NoteUseChoice>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  builder: (context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final time = MaterialLocalizations.of(context)
        .formatTimeOfDay(TimeOfDay.fromDateTime(note.time.toLocal()));
    Widget current(bool selected) => selected
        ? Icon(Icons.check, color: colors.primary)
        : const SizedBox(width: 24);
    final annotatedHere =
        note.use == NoteUse.annotates &&
        (note.eventId == null || note.eventId == fallsIn);
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      maxChildSize: 0.9,
      builder: (context, scroll) => ListView(
        controller: scroll,
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
            child: Text(
              "What's this note for?",
              style: theme.textTheme.titleMedium,
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(
              '$time  ${note.text ?? '(no text)'}\n'
              '${noteFate(note, events: events)}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: colors.onSurfaceVariant,
              ),
            ),
          ),
          ListTile(
            leading: Icon(ReviewNoteKind.annotated.icon),
            title: Text(switch (events[fallsIn]) {
              final name? => 'Add it to “$name”',
              null => 'Add it where it falls',
            }),
            subtitle: Text(
              note.edgeOf != null && note.edgeOf == fallsIn
                  ? 'The event whose start or end it sets'
                  : 'The event it falls within',
            ),
            trailing: current(annotatedHere),
            onTap: () => Navigator.of(context).pop(const AnnotateNote()),
          ),
          ListTile(
            leading: Icon(ReviewNoteKind.ignored.icon),
            title: const Text('Leave it out'),
            subtitle: Text(
              note.edgeOf == null
                  ? 'Add it to no event'
                  : 'Add it to no event; it still sets the edge',
            ),
            trailing: current(note.use == NoteUse.ignored),
            onTap: () => Navigator.of(context).pop(const IgnoreNote()),
          ),
          if (note.decidedBy == DecidedBy.user)
            ListTile(
              leading: const Icon(Icons.undo),
              title: const Text('Put it back as Claude had it'),
              onTap: () => Navigator.of(context).pop(const NoteAsClaudeHadIt()),
            ),
          ListTile(
            leading: const Icon(Icons.add_comment_outlined),
            title: const Text('Ask Claude about it'),
            subtitle: const Text('Leave a note for Claude about this note'),
            onTap: () => Navigator.of(context).pop(const AskClaudeAboutNote()),
          ),
          if (events.keys.any((id) => id != fallsIn)) ...[
            const Divider(),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
              child: Text(
                'Or add it to another event',
                style: theme.textTheme.titleSmall,
              ),
            ),
            for (final MapEntry(key: id, value: name) in events.entries)
              if (id != fallsIn)
                ListTile(
                  dense: true,
                  leading: const SizedBox(width: 24),
                  title: Text(name),
                  trailing: current(
                    note.use == NoteUse.annotates && note.eventId == id,
                  ),
                  onTap: () => Navigator.of(context).pop(AnnotateNote(id)),
                ),
          ],
        ],
      ),
    );
  },
);

/// What the user did from [showCancelledDialog], that closes it.
sealed class CancelledChoice {
  const CancelledChoice();
}

/// Put it back as planned.
final class PutBack extends CancelledChoice {
  const PutBack();
}

/// Leave a note for Claude about it.
final class AskAboutCancel extends CancelledChoice {
  const AskAboutCancel();
}

/// Shows [event], which the proposal says didn't happen -- cancelled, or
/// merged into another -- when it was, who said so, and, cancelled,
/// whether that counts against follow-through, and against whom, in full.
/// Its switch says otherwise with [setCounts], staying open to show what
/// that came to -- the event as it is now -- or why it couldn't. It can be
/// put back as planned, or asked about in a note for Claude.
Future<CancelledChoice?> showCancelledDialog(
  BuildContext context,
  ProposalEvent event, {
  Future<ProposalEvent?> Function(bool counts)? setCounts,
}) => showDialog<CancelledChoice>(
  context: context,
  builder: (context) => _CancelledDialog(event: event, setCounts: setCounts),
);

class _CancelledDialog extends StatefulWidget {
  const _CancelledDialog({required this.event, this.setCounts});

  final ProposalEvent event;
  final Future<ProposalEvent?> Function(bool counts)? setCounts;

  @override
  State<_CancelledDialog> createState() => _CancelledDialogState();
}

class _CancelledDialogState extends State<_CancelledDialog> {
  /// The event as it is now: after the switch, as the proposal has it.
  late ProposalEvent _event = widget.event;
  bool _saving = false;

  Future<void> _setCounts(bool counts) async {
    final setCounts = widget.setCounts;
    if (setCounts == null) return;
    setState(() => _saving = true);
    try {
      final now = await setCounts(counts);
      if (!mounted) return;
      setState(() {
        _event = now ?? _event;
        _saving = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      await showErrorSheet(
        context,
        title: "Couldn't change it",
        error: e,
        onRetry: () => _setCounts(counts),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final event = _event;
    final name = switch (event.summary) {
      final s? when s.isNotEmpty => '“$s”',
      _ => 'This event',
    };
    final merged = event.status == ProposalEventStatus.merged;
    final counts = event.countsAgainstFollowThrough ?? true;
    final small = theme.textTheme.bodySmall?.copyWith(
      color: colors.onSurfaceVariant,
    );
    return AlertDialog(
      title: Text("$name didn't happen"),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${_time(context, event.start)} – ${_time(context, event.end)}'
              ' · ${merged ? 'Merged into another event' : 'Cancelled'}'
              '${switch (event.decidedBy) {
                DecidedBy.claude => ' by Claude',
                DecidedBy.user => ' by you',
                null => '',
              }}',
              style: small,
            ),
            if (!merged) ...[
              const SizedBox(height: 16),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Counts against follow-through'),
                subtitle: Text(
                  counts
                      ? 'A commitment dropped'
                      : 'A change of plan: no one’s follow-through',
                ),
                secondary: _saving
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : null,
                value: counts,
                onChanged: _saving || widget.setCounts == null
                    ? null
                    : _setCounts,
              ),
              if (counts) ...[
                const SizedBox(height: 4),
                Text(
                  event.followThrough.isEmpty
                      ? 'No one’s follow-through tracks it.'
                      : 'It counts against:',
                  style: theme.textTheme.titleSmall,
                ),
                for (final who in event.followThrough)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Row(
                      children: [
                        Icon(
                          Icons.person_outline,
                          size: 18,
                          color: colors.error,
                        ),
                        const SizedBox(width: 8),
                        Expanded(child: Text(who)),
                      ],
                    ),
                  ),
              ],
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving
              ? null
              : () => Navigator.of(context).pop(const AskAboutCancel()),
          child: const Text('Note for Claude'),
        ),
        TextButton(
          onPressed: _saving
              ? null
              : () => Navigator.of(context).pop(const PutBack()),
          child: const Text('Put it back'),
        ),
        FilledButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: const Text('Done'),
        ),
      ],
    );
  }
}
