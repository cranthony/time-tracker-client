import 'package:flutter/material.dart';

import '../models/event.dart';
import '../models/facts.dart';
import '../models/proposal.dart';
import 'day_timeline.dart';

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
  required String Function(DateTime) time,
}) {
  final by = switch (event.decidedBy) {
    DecidedBy.claude => 'Claude',
    DecidedBy.user => 'you',
    null => null,
  };
  final what = switch (event.status) {
    ProposalEventStatus.created => ['New'],
    ProposalEventStatus.cancelled => ['Cancelled'],
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
  if (what.isEmpty) return EventMark(changed: changed);
  return EventMark(
    label: [what.join(' · '), ?by].join(' · '),
    icon: switch (event.status) {
      ProposalEventStatus.cancelled ||
      ProposalEventStatus.merged => Icons.close,
      ProposalEventStatus.created => Icons.add,
      _ => null,
    },
    changed: changed,
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

/// Under the [ProposalBar], one of the proposal's notes -- the [index]th
/// of [count] -- its time and text, and what became of it, with buttons to
/// go to the note before it ([onPrevious]) and after it ([onNext]).
/// Tapping it, or its pencil, calls [onEdit], to say what it's for.
/// [events] names the events, by id or key.
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
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final kind = reviewNoteKind(note);
    final time = MaterialLocalizations.of(context)
        .formatTimeOfDay(TimeOfDay.fromDateTime(note.time.toLocal()));
    final fate = noteFate(note, events: events);
    return Material(
      color: Color.alphaBlend(
        reviewColors(colors).tint,
        colors.surfaceContainerLow,
      ),
      shape: Border(
        bottom: BorderSide(color: reviewColors(colors).line, width: 2),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 2, 4, 2),
        child: Row(
          children: [
            Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                color: colors.primary,
                shape: BoxShape.circle,
              ),
              child: Icon(kind.icon, size: 14, color: colors.onPrimary),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: InkWell(
                onTap: onEdit,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(
                              text: '$time  ',
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            TextSpan(text: note.text ?? '(no text)'),
                          ],
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium,
                      ),
                      if (fate.isNotEmpty)
                        Text(
                          fate,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color:
                                kind == ReviewNoteKind.ignored ||
                                    kind == ReviewNoteKind.compacted
                                ? colors.onSurfaceVariant
                                : colors.tertiary,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            if (onEdit != null)
              IconButton(
                tooltip: 'What this note is for',
                visualDensity: VisualDensity.compact,
                onPressed: onEdit,
                icon: const Icon(Icons.edit_note),
              ),
            Text(
              '${index + 1}/$count',
              style: theme.textTheme.labelSmall?.copyWith(
                color: colors.onSurfaceVariant,
              ),
            ),
            IconButton(
              tooltip: 'Previous note',
              visualDensity: VisualDensity.compact,
              onPressed: onPrevious,
              icon: const Icon(Icons.keyboard_arrow_up),
            ),
            IconButton(
              tooltip: 'Next note',
              visualDensity: VisualDensity.compact,
              onPressed: onNext,
              icon: const Icon(Icons.keyboard_arrow_down),
            ),
          ],
        ),
      ),
    );
  }
}

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
