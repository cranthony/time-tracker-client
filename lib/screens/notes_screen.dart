import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/note.dart';
import '../outbox/note_outbox.dart';
import '../outbox/pending_note.dart';
import '../services/mcp_client.dart';
import '../services/note_drafts.dart';
import '../widgets/hotkeys.dart';
import '../services/notes_repository.dart';
import '../services/plan_memory.dart';
import '../widgets/error_sheet.dart';
import '../widgets/load_status.dart';
import '../widgets/app_menu.dart';
import '../widgets/day_header.dart';
import '../widgets/note_dialog.dart';
import '../widgets/refreshing_bar.dart';
import '../widgets/status_message.dart';

/// All the uncompacted notes, plus any not saved yet, by day, with a "+"
/// to add another, under the latest note compacted and a dashed line for
/// when notes were last compacted into the calendar. Tapping a saved note
/// edits or deletes it. Edits and deletions wait in the [outbox] too, shown
/// on their notes until they're saved; notes being written, [drafts], are
/// shown at their times, dashed, to finish.
class NotesScreen extends StatefulWidget {
  const NotesScreen({
    super.key,
    required this.repository,
    required this.outbox,
    this.onSignIn,
    this.onSignOut,
    this.addNoteRequests,
    this.onAddNoteFieldFocused,
    this.version,
    this.memory,
    this.loads,
    this.drafts,
    DateTime Function()? clock,
  }) : clock = clock ?? DateTime.now;

  final NotesRepository repository;

  /// Where new notes, and edits and deletions, go until they're saved.
  final NoteOutbox outbox;

  /// Notes being written, kept as they're typed: the app's, or else the
  /// page's own.
  final NoteDrafts? drafts;

  /// Runs the interactive sign-in; null when the backend needs none.
  final Future<void> Function()? onSignIn;
  final Future<void> Function()? onSignOut;

  /// Each event opens the New note dialog, timed at the event's time: taps
  /// on the home screen "+" widget.
  final Stream<DateTime>? addNoteRequests;

  /// Called when the New note dialog opened for one of [addNoteRequests]
  /// has its field focused.
  final VoidCallback? onAddNoteFieldFocused;

  /// The app's version, for the About dialog; null until it's known.
  final String? version;

  /// What the app has loaded, the notes among it, for every page to
  /// share: by default, the [PlanMemoryScope]'s.
  final PlanMemory? memory;

  /// How loading the notes is going, for the status bar: the app's, or
  /// else one of the page's own.
  final LoadStatus? loads;

  /// Now, for the "Today" and "Yesterday" headings.
  final DateTime Function() clock;

  @override
  State<NotesScreen> createState() => _NotesScreenState();
}

class _NotesScreenState extends State<NotesScreen> {
  /// What the app has loaded, for every page: here, the notes not yet
  /// compacted and when notes were last compacted. The app's, or else one
  /// of its own.
  late final PlanMemory _memory =
      widget.memory ?? PlanMemoryScope.of(context) ?? PlanMemory();

  List<Note>? get _notes => _memory.notes;
  set _notes(List<Note>? notes) => _memory.notes = notes;

  /// When notes were last compacted; null until known, or from a server
  /// too old to say.
  CompactionStatus? get _status => _memory.compaction;

  /// [_notes] are the ones kept from last time; the server hasn't
  /// answered since.
  bool _stale = false;
  bool _needsSignIn = false;
  bool _signingIn = false;

  /// How loading the notes is going: a failure is tried again by itself.
  late final LoadStatus _loads = widget.loads ?? LoadStatus('notes');
  Object? get _error => _loads.error;

  /// One dialog at a time, e.g. if the home screen "+" is tapped twice.
  bool _dialogOpen = false;

  late final NoteDrafts _drafts = widget.drafts ?? NoteDrafts.inMemory();

  StreamSubscription<DateTime>? _addNoteRequests;

  @override
  void initState() {
    super.initState();
    widget.outbox.addListener(_outboxChanged);
    _addNoteRequests = widget.addNoteRequests?.listen(
      (at) => _addNote(at: at, onFieldFocused: widget.onAddNoteFieldFocused),
    );
    _loads.bind(_load);
    _showCached();
    _load();
  }

  /// Shows the notes and compaction status the app has -- loaded on
  /// another page, or kept from last time -- unless the server answered
  /// first.
  Future<void> _showCached() async {
    final answered = _answered;
    await _memory.loadKept(notes: widget.repository);
    if (!mounted || _answered != answered || _notes == null) return;
    if (_needsSignIn || _error != null) return;
    setState(() => _stale = true);
  }

  /// How many times the server has answered for the notes here.
  int _answered = 0;

  @override
  void dispose() {
    widget.outbox.removeListener(_outboxChanged);
    _addNoteRequests?.cancel();
    _loads.unbind();
    if (widget.loads == null) _loads.dispose();
    if (widget.drafts == null) _drafts.dispose();
    super.dispose();
  }

  /// Fetches the notes again once notes are saved, here or by the
  /// background task, so they're shown as the server has them.
  void _outboxChanged() {
    if (mounted && widget.outbox.wantsFetch) _load();
  }

  Future<void> _load() async {
    unawaited(_loadStatus());
    final fetched = widget.outbox.fetching();
    try {
      await _memory.loadNotes(widget.repository, again: true);
      _answered++;
      if (!mounted) return;
      _loads.loaded();
      setState(() {
        _stale = false;
        _needsSignIn = false;
      });
      fetched();
    } on SignInRequiredException {
      if (!mounted) return;
      _loads.reset();
      setState(() {
        _notes = null;
        _stale = false;
        _needsSignIn = true;
      });
    } catch (e) {
      if (!mounted) return;
      // Tried again by itself; with notes shown, the status bar says so.
      _loads.failed(e, hasData: _notes != null);
      setState(() {
        // Signed in: without that it's SignInRequiredException.
        _needsSignIn = false;
      });
    }
  }

  /// Loads [_status]; a failure just leaves the last one shown.
  Future<void> _loadStatus() async {
    try {
      await _memory.loadCompaction(widget.repository, again: true);
      if (mounted) setState(() {});
    } catch (_) {}
  }

  Future<void> _refresh() async {
    unawaited(widget.outbox.retryNow());
    await _load();
  }

  Future<void> _addNote({
    DateTime? at,
    VoidCallback? onFieldFocused,
    NoteDraft? draft,
  }) async {
    if (_dialogOpen) return;
    _dialogOpen = true;
    // The sheet queues the note itself, so it's kept even if this page
    // is gone by the time Add is tapped -- switched to Events by a tap on
    // the home screen calendar, say.
    final outbox = widget.outbox;
    try {
      await showAddNoteDialog(
        context,
        keep: outbox.add,
        drafts: _drafts,
        draft: draft,
        time: at,
        onFieldFocused: onFieldFocused,
      );
    } finally {
      _dialogOpen = false;
    }
  }

  /// Edits [shown] -- [base], the note on the server, as it's shown: with
  /// an edit of it waiting, say, or [draft], a draft edit of it. The sheet
  /// queues the edit, or the deletion, itself, as it does a new note.
  Future<void> _editNote(Note shown, Note base, {NoteDraft? draft}) async {
    if (base.id == null || _dialogOpen) return;
    _dialogOpen = true;
    final outbox = widget.outbox;
    final messenger = ScaffoldMessenger.of(context);
    PendingNote? deletion;
    final NoteDialogResult? result;
    try {
      result = await showEditNoteDialog(
        context,
        shown,
        drafts: _drafts,
        draft: draft,
        keepEdit: (edited) => outbox.edit(base, edited),
        keepDelete: () async => deletion = await outbox.delete(base),
      );
    } finally {
      _dialogOpen = false;
    }
    if (result is! DeleteNote) return;
    final deleted = deletion;
    if (deleted == null) return;
    messenger.showSnackBar(
      SnackBar(
        content: const Text('Note deleted'),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () => _undoDelete(outbox, deleted),
        ),
      ),
    );
  }

  /// Takes back [deletion]: dropped while it waits; once it's done, the
  /// note's saved again as a new one, through the outbox, so it isn't
  /// lost if that fails too.
  static Future<void> _undoDelete(
    NoteOutbox outbox,
    PendingNote deletion,
  ) async {
    if (outbox.pending.any((p) => p.id == deletion.id) &&
        await outbox.cancel(deletion)) {
      return;
    }
    final note = deletion.note;
    await outbox.add(
      Note(timestamp: note.timestamp, description: note.description),
    );
  }

  Future<void> _cancel(PendingNote note) async {
    final messenger = ScaffoldMessenger.of(context);
    if (!await widget.outbox.cancel(note)) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Already saving; it can’t be cancelled')),
      );
      return;
    }
    messenger.showSnackBar(
      SnackBar(
        content: Text(switch (note.change) {
          NoteChange.add => 'Note cancelled',
          NoteChange.edit => 'Change cancelled',
          NoteChange.delete => 'Deletion cancelled',
        }),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () => widget.outbox.restore(note),
        ),
      ),
    );
  }

  Future<void> _signIn() async {
    setState(() => _signingIn = true);
    Object? error;
    try {
      await widget.onSignIn!();
      unawaited(widget.outbox.retryNow());
      await _load();
    } catch (e) {
      error = e;
    } finally {
      if (mounted) setState(() => _signingIn = false);
    }
    if (error != null && mounted) {
      await showErrorSheet(
        context,
        title: "Couldn't sign in",
        error: error,
        onRetry: _signIn,
      );
    }
  }

  Future<void> _signOut() async {
    await widget.onSignOut!();
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([widget.outbox, _drafts]),
      builder: (context, _) {
        final needsSignIn = _needsSignIn || widget.outbox.needsSignIn;
        return Scaffold(
          appBar: AppBar(
            title: const Text('Notes'),
            actions: [
              AppMenu(
                serverLabel: widget.repository.label,
                version: widget.version,
                onSignOut: widget.onSignOut == null || needsSignIn
                    ? null
                    : _signOut,
              ),
            ],
          ),
          body: RefreshingBar(
            refreshing: _stale && _error == null && !needsSignIn,
            child: RefreshIndicator(
              onRefresh: _refresh,
              child: _buildBody(context, needsSignIn),
            ),
          ),
          // Always available: notes wait in the outbox until they can be
          // saved, even while signed out or offline.
          floatingActionButton: HotkeyHint(
            Hotkey.newNote,
            child: FloatingActionButton(
              onPressed: () => _addNote(),
              tooltip: 'Add note',
              child: const Icon(Icons.add),
            ),
          ),
        );
      },
    );
  }

  Widget _buildBody(BuildContext context, bool needsSignIn) {
    final notes = _notes;
    final pending = widget.outbox.pending;
    final adds = [
      for (final p in pending)
        if (p.change == NoteChange.add) p,
    ];
    // Each note's edit or deletion waiting, by its id: a deletion over an
    // edit still being sent.
    final changes = <String, PendingNote>{
      for (final p in pending)
        if (p.change == NoteChange.edit) p.noteId!: p,
      for (final p in pending)
        if (p.change == NoteChange.delete) p.noteId!: p,
    };
    final drafts = _drafts.drafts;
    final editDrafts = {
      for (final d in drafts)
        if (d.isEdit) d.original!.id: d,
    };
    final saved = [
      for (final (:item, result: _) in widget.outbox.justSaved) item,
    ];
    // Saved since the notes were fetched: shown as they'll be until
    // they're fetched with them.
    final savedEdits = {
      for (final p in saved)
        if (p.change == NoteChange.edit) p.noteId!: p.note,
    };
    final savedDeletions = {
      for (final p in saved)
        if (p.change == NoteChange.delete) p.noteId!,
    };

    Widget pendingTile(PendingNote p, {VoidCallback? onTap}) =>
        _PendingNoteTile(
          pending: p,
          sending: widget.outbox.isSending(p),
          sendingBy: widget.outbox.sendingBy(p),
          needsSignIn: needsSignIn,
          onCancel: () => _cancel(p),
          onRetry: widget.outbox.retryNow,
          onTap: onTap,
        );
    Widget draftTile(NoteDraft d, VoidCallback onTap) =>
        _DraftTile(draft: d, onTap: onTap);

    final rows = <({DateTime at, Widget tile})>[
      for (final note in notes ?? const <Note>[])
        if (note.id case final id?
            when changes[id]?.change == NoteChange.delete)
          (at: note.timestamp, tile: pendingTile(changes[id]!))
        else if (note.id case final id? when editDrafts[id] != null)
          (
            at: editDrafts[id]!.timestamp,
            tile: draftTile(
              editDrafts[id]!,
              () => _editNote(
                editDrafts[id]!.original!,
                note,
                draft: editDrafts[id],
              ),
            ),
          )
        else if (note.id case final id? when changes[id] != null)
          (
            at: changes[id]!.note.timestamp,
            tile: pendingTile(
              changes[id]!,
              onTap: () => _editNote(changes[id]!.note, note),
            ),
          )
        else if (!savedDeletions.contains(note.id))
          () {
            final shown = savedEdits[note.id] ?? note;
            return (
              at: shown.timestamp,
              tile: _NoteTile(
                note: shown,
                // Without an id (from an older server) it can't be changed.
                onTap: note.id == null ? null : () => _editNote(shown, note),
              ),
            );
          }(),
      for (final p in saved)
        if (p.change == NoteChange.add &&
            !NoteOutbox.savedIn(p.note, notes ?? const []))
          (at: p.note.timestamp, tile: _NoteTile(note: p.note)),
      for (final p in adds) (at: p.note.timestamp, tile: pendingTile(p)),
      // Of notes not listed: compacted since, say.
      for (final p in changes.values)
        if (!(notes ?? const <Note>[]).any((n) => n.id == p.noteId))
          (at: p.note.timestamp, tile: pendingTile(p)),
      for (final d in drafts)
        if (!d.isEdit)
          (at: d.timestamp, tile: draftTile(d, () => _addNote(draft: d)))
        else if (!(notes ?? const <Note>[]).any((n) => n.id == d.original!.id))
          (
            at: d.timestamp,
            tile: draftTile(
              d,
              () => _editNote(d.original!, d.original!, draft: d),
            ),
          ),
    ]..sort((a, b) => a.at.compareTo(b.at));

    final Widget? banner;
    if (needsSignIn) {
      banner = StatusMessage(
        icon: Icons.lock_outline,
        text: pending.isEmpty
            ? 'Sign in to see your notes.'
            : 'Sign in to see your notes and save the ones below.',
        action: widget.onSignIn == null
            ? null
            : FilledButton(
                onPressed: _signingIn ? null : _signIn,
                child: Text(_signingIn ? 'Waiting for browser…' : 'Sign in'),
              ),
      );
    } else if (_error != null && notes == null) {
      banner = LoadError(
        what: 'notes',
        error: _error!,
        retryingAt: _loads.nextAttemptAt,
        onRetry: _refresh,
      );
    } else if (notes == null && rows.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    } else if (rows.isEmpty) {
      banner = const StatusMessage(
        icon: Icons.edit_note,
        text: 'No uncompacted notes.\nTap + to add one.',
      );
    } else {
      banner = null;
    }

    // The latest note compacted, over a dashed line for the compaction,
    // above the notes since.
    final status = needsSignIn ? null : _status;
    final latest = status?.latestCompacted;
    final compaction = <Widget>[
      if (latest != null) ...[
        DayHeader(day: latest.timestamp, today: widget.clock()),
        _CompactedNoteTile(note: latest),
      ],
      if (status != null)
        _CompactionLine(
          at: status.lastCompaction,
          judging: status.judgmentsPending != null,
        ),
    ];
    if (rows.isEmpty) {
      return CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverList.list(children: compaction),
          SliverFillRemaining(
            hasScrollBody: false,
            child: Center(child: banner),
          ),
        ],
      );
    }
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.only(bottom: 88), // clear the FAB
      children: [
        ...compaction,
        ?banner,
        for (final (i, row) in rows.indexed) ...[
          // The compacted note's day isn't headed twice.
          if (i == 0
              ? latest == null || !sameDay(latest.timestamp, row.at)
              : !sameDay(rows[i - 1].at, row.at))
            DayHeader(day: row.at, today: widget.clock())
          else if (i > 0)
            const Divider(height: 1),
          row.tile,
        ],
      ],
    );
  }
}

/// The latest note compacted into the calendar: like the notes after it,
/// but smaller and muted, and not to be changed.
class _CompactedNoteTile extends StatelessWidget {
  const _CompactedNoteTile({required this.note});

  final Note note;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = TextStyle(color: theme.colorScheme.onSurfaceVariant);
    return ListTile(
      dense: true,
      leading: Text(
        _time(context, note),
        style: theme.textTheme.titleSmall?.merge(muted),
      ),
      title: Text(switch (note.description) {
        final String d when d.isNotEmpty => d,
        _ => '(no description)',
      }, style: muted),
      trailing: Tooltip(
        message: 'Compacted into the calendar',
        child: Icon(
          Icons.event_available,
          size: 18,
          color: theme.colorScheme.tertiary,
        ),
      ),
    );
  }
}

/// A dashed line, as on the Events timeline, for when notes were last
/// compacted: the note above it is in the calendar, those below aren't
/// yet.
class _CompactionLine extends StatelessWidget {
  const _CompactionLine({required this.at, this.judging = false});

  /// Null if notes have never been compacted.
  final DateTime? at;

  /// Whether that compaction's judgments are still to be made.
  final bool judging;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = theme.colorScheme.tertiary;
    final String label;
    if (at case final at?) {
      final strings = MaterialLocalizations.of(context);
      final local = at.toLocal();
      label =
          'Last compacted ${strings.formatShortDate(local)}, '
          '${strings.formatTimeOfDay(TimeOfDay.fromDateTime(local))}'
          '${judging ? ' · judgments pending' : ''}';
    } else {
      label = 'Notes not compacted yet';
    }
    final dashes = Expanded(
      child: CustomPaint(
        size: const Size.fromHeight(1.5),
        painter: _DashPainter(color),
      ),
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      child: Row(
        children: [
          dashes,
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(
              label,
              style: theme.textTheme.labelSmall?.copyWith(color: color),
            ),
          ),
          dashes,
        ],
      ),
    );
  }
}

/// 4px dashes 4px apart, across.
class _DashPainter extends CustomPainter {
  const _DashPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = size.height;
    final y = size.height / 2;
    for (var x = 0.0; x < size.width; x += 8) {
      canvas.drawLine(
        Offset(x, y),
        Offset(math.min(x + 4, size.width), y),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_DashPainter old) => old.color != color;
}

class _NoteTile extends StatelessWidget {
  const _NoteTile({required this.note, this.onTap});

  final Note note;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      leading: Text(_time(context, note), style: theme.textTheme.titleMedium),
      title: note.description == null
          ? Text('(no description)', style: TextStyle(color: theme.hintColor))
          : Text(note.description!),
      onTap: onTap,
    );
  }
}

/// A note being written, never sent: dashed round, in italics, saying
/// it's a draft. Tapping it carries on with it -- the sheet has the trash
/// can to throw it away.
class _DraftTile extends StatelessWidget {
  const _DraftTile({required this.draft, required this.onTap});

  final NoteDraft draft;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final muted = TextStyle(
      color: scheme.onSurfaceVariant,
      fontStyle: FontStyle.italic,
    );
    final note = draft.note;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: CustomPaint(
        foregroundPainter: _DashedRectPainter(scheme.outline),
        child: ListTile(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          leading: Text(
            _time(context, note),
            style: theme.textTheme.titleMedium?.merge(muted),
          ),
          title: Text(note.description ?? '(no description)', style: muted),
          subtitle: Row(
            children: [
              Icon(Icons.edit_outlined, size: 14, color: scheme.primary),
              const SizedBox(width: 6),
              Text(
                draft.isEdit ? 'Draft change · not saved' : 'Draft · not saved',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.primary,
                ),
              ),
            ],
          ),
          onTap: onTap,
        ),
      ),
    );
  }
}

/// A rounded rectangle of 4px dashes, round what it paints over.
class _DashedRectPainter extends CustomPainter {
  const _DashedRectPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    final path = Path()
      ..addRRect(
        RRect.fromRectAndRadius(
          (Offset.zero & size).deflate(0.6),
          const Radius.circular(8),
        ),
      );
    for (final metric in path.computeMetrics()) {
      for (var d = 0.0; d < metric.length; d += 8) {
        canvas.drawPath(metric.extractPath(d, d + 4), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_DashedRectPainter old) => old.color != color;
}

/// A change to the notes that isn't on the server yet -- a new note, an
/// edit (the note as it'll be), or a deletion (struck through): tinted, in
/// italics, with its status underneath and a button to cancel it.
class _PendingNoteTile extends StatelessWidget {
  const _PendingNoteTile({
    required this.pending,
    required this.sending,
    this.sendingBy,
    required this.needsSignIn,
    required this.onCancel,
    required this.onRetry,
    this.onTap,
  });

  final PendingNote pending;
  final bool sending;

  /// Who's sending it, as one would say it: "the background task".
  final String? sendingBy;
  final bool needsSignIn;
  final VoidCallback onCancel;
  final VoidCallback onRetry;

  /// Tapped, unless it's failed and can be retried: an edit, to edit it
  /// again.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final deleting = pending.change == NoteChange.delete;
    final muted = TextStyle(
      color: scheme.onSurfaceVariant,
      fontStyle: FontStyle.italic,
      decoration: deleting ? TextDecoration.lineThrough : null,
    );
    final refused = pending.refused && !sending;
    final failed = (pending.attempts > 0 || pending.refused) && !sending;
    final notDone = deleting ? 'Not deleted' : 'Not saved';

    final Widget icon;
    final String status;
    if (sending) {
      icon = const SizedBox.square(
        dimension: 12,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
      final doing = switch (pending.change) {
        NoteChange.add => 'Saving',
        NoteChange.edit => 'Saving the change',
        NoteChange.delete => 'Deleting',
      };
      status = sendingBy == null ? '$doing…' : '$doing, by $sendingBy…';
    } else if (needsSignIn) {
      icon = Icon(Icons.lock_outline, size: 14, color: scheme.error);
      status = '$notDone · sign in to save';
    } else if (refused) {
      icon = Icon(Icons.block, size: 14, color: scheme.error);
      status = '$notDone · ${pending.lastError ?? 'refused'}';
    } else if (failed) {
      icon = Icon(Icons.cloud_off, size: 14, color: scheme.error);
      status = '$notDone · ${pending.lastError ?? 'failed'} · retrying';
    } else {
      icon = Icon(Icons.schedule, size: 14, color: scheme.onSurfaceVariant);
      status = switch (pending.change) {
        NoteChange.add => 'Waiting to save',
        NoteChange.edit => 'Change waiting to save',
        NoteChange.delete => 'Waiting to delete',
      };
    }

    return ListTile(
      tileColor: scheme.secondaryContainer.withValues(alpha: 0.4),
      leading: Text(
        _time(context, pending.note),
        style: theme.textTheme.titleMedium?.merge(muted),
      ),
      title: Text(pending.note.description ?? '(no description)', style: muted),
      subtitle: Row(
        children: [
          icon,
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              status,
              style: theme.textTheme.bodySmall?.copyWith(
                color: failed || needsSignIn
                    ? scheme.error
                    : scheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
      trailing: IconButton(
        icon: const Icon(Icons.close),
        tooltip: switch (pending.change) {
          NoteChange.add => 'Cancel note',
          NoteChange.edit => 'Cancel change',
          NoteChange.delete => 'Cancel deletion',
        },
        onPressed: sending ? null : onCancel,
      ),
      // Skip the wait for the next retry.
      onTap: failed && !needsSignIn ? onRetry : onTap,
    );
  }
}

String _time(BuildContext context, Note note) =>
    MaterialLocalizations.of(context)
        .formatTimeOfDay(TimeOfDay.fromDateTime(note.timestamp.toLocal()));
