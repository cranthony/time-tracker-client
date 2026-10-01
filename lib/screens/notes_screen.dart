import 'dart:async';

import 'package:flutter/material.dart';

import '../models/note.dart';
import '../outbox/note_outbox.dart';
import '../outbox/pending_note.dart';
import '../services/mcp_client.dart';
import '../services/notes_repository.dart';
import '../widgets/app_menu.dart';
import '../widgets/day_header.dart';
import '../widgets/note_dialog.dart';
import '../widgets/status_message.dart';

/// All the uncompacted notes, plus any not saved yet, by day, with a "+"
/// to add another. Tapping a saved note edits or deletes it.
class NotesScreen extends StatefulWidget {
  const NotesScreen({
    super.key,
    required this.repository,
    required this.outbox,
    this.onSignIn,
    this.onSignOut,
    this.addNoteRequests,
    this.version,
    DateTime Function()? clock,
  }) : clock = clock ?? DateTime.now;

  final NotesRepository repository;

  /// Where new notes go until they're saved.
  final NoteOutbox outbox;

  /// Runs the interactive sign-in; null when the backend needs none.
  final Future<void> Function()? onSignIn;
  final Future<void> Function()? onSignOut;

  /// Each event opens the New note dialog, timed at the event's time: taps
  /// on the home screen "+" widget.
  final Stream<DateTime>? addNoteRequests;

  /// The app's version, for the About dialog; null until it's known.
  final String? version;

  /// Now, for the "Today" and "Yesterday" headings.
  final DateTime Function() clock;

  @override
  State<NotesScreen> createState() => _NotesScreenState();
}

class _NotesScreenState extends State<NotesScreen> {
  List<Note>? _notes;
  Object? _error;
  bool _needsSignIn = false;
  bool _signingIn = false;

  /// One dialog at a time, e.g. if the home screen "+" is tapped twice.
  bool _dialogOpen = false;

  /// Notes being edited or deleted on the server, by id.
  final _changing = <String>{};
  StreamSubscription<DateTime>? _addNoteRequests;

  @override
  void initState() {
    super.initState();
    widget.outbox.onSaved = _load;
    _addNoteRequests = widget.addNoteRequests?.listen((at) => _addNote(at: at));
    _load();
  }

  @override
  void dispose() {
    widget.outbox.onSaved = null;
    _addNoteRequests?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final notes = await widget.repository.uncompactedNotes();
      if (!mounted) return;
      setState(() {
        _notes = notes;
        _error = null;
        _needsSignIn = false;
      });
    } on SignInRequiredException {
      if (!mounted) return;
      setState(() {
        _notes = null;
        _needsSignIn = true;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e);
    }
  }

  Future<void> _refresh() async {
    unawaited(widget.outbox.retryNow());
    await _load();
  }

  Future<void> _addNote({DateTime? at}) async {
    if (_dialogOpen) return;
    _dialogOpen = true;
    final Note? note;
    try {
      note = await showAddNoteDialog(context, time: at);
    } finally {
      _dialogOpen = false;
    }
    if (note == null || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await widget.outbox.add(note);
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Could not keep the note: $e')),
      );
    }
  }

  Future<void> _editNote(Note note) async {
    final id = note.id;
    if (id == null || _dialogOpen || _changing.contains(id)) return;
    _dialogOpen = true;
    final NoteDialogResult? result;
    try {
      result = await showEditNoteDialog(context, note);
    } finally {
      _dialogOpen = false;
    }
    if (result == null || !mounted) return;
    final edited = result is SaveNote ? result.note : null;
    final retimed =
        edited != null && !edited.timestamp.isAtSameMomentAs(note.timestamp);
    final described = edited != null && edited.description != note.description;
    if (edited != null && !retimed && !described) return;

    final messenger = ScaffoldMessenger.of(context);
    setState(() => _changing.add(id));
    try {
      switch (result) {
        case SaveNote():
          await widget.repository.editNote(
            id,
            timestamp: retimed ? edited.timestamp : null,
            // An empty description clears it.
            description: described ? edited.description ?? '' : null,
          );
        case DeleteNote():
          await widget.repository.deleteNote(id);
          messenger.showSnackBar(
            SnackBar(
              content: const Text('Note deleted'),
              action: SnackBarAction(
                label: 'Undo',
                // Saved again as a new note, through the outbox, so it
                // isn't lost if this fails too.
                onPressed: () => widget.outbox.add(
                  Note(
                    timestamp: note.timestamp,
                    description: note.description,
                  ),
                ),
              ),
            ),
          );
      }
    } catch (e) {
      final action = result is DeleteNote ? 'delete' : 'change';
      messenger.showSnackBar(
        SnackBar(content: Text('Could not $action the note: ${_describe(e)}')),
      );
    } finally {
      if (mounted) setState(() => _changing.remove(id));
      await _load();
    }
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
        content: const Text('Note cancelled'),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () => widget.outbox.restore(note),
        ),
      ),
    );
  }

  Future<void> _signIn() async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _signingIn = true);
    try {
      await widget.onSignIn!();
      unawaited(widget.outbox.retryNow());
      await _load();
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Sign-in failed: $e')));
    } finally {
      if (mounted) setState(() => _signingIn = false);
    }
  }

  Future<void> _signOut() async {
    await widget.onSignOut!();
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.outbox,
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
          body: RefreshIndicator(
            onRefresh: _refresh,
            child: _buildBody(context, needsSignIn),
          ),
          // Always available: notes wait in the outbox until they can be
          // saved, even while signed out or offline.
          floatingActionButton: FloatingActionButton(
            onPressed: () => _addNote(),
            tooltip: 'Add note',
            child: const Icon(Icons.add),
          ),
        );
      },
    );
  }

  Widget _buildBody(BuildContext context, bool needsSignIn) {
    final notes = _notes;
    final pending = widget.outbox.pending;
    final rows = <({DateTime at, Widget tile})>[
      for (final note in notes ?? const <Note>[])
        (
          at: note.timestamp,
          tile: _NoteTile(
            note: note,
            changing: _changing.contains(note.id),
            // Without an id (from an older server) it can't be changed.
            onTap: note.id == null ? null : () => _editNote(note),
          ),
        ),
      for (final note in pending)
        (
          at: note.note.timestamp,
          tile: _PendingNoteTile(
            pending: note,
            sending: widget.outbox.isSending(note),
            needsSignIn: needsSignIn,
            onCancel: () => _cancel(note),
            onRetry: widget.outbox.retryNow,
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
    } else if (_error != null) {
      banner = StatusMessage(
        icon: Icons.cloud_off,
        text: 'Could not load notes.\n$_error',
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

    if (rows.isEmpty) return FillViewport(child: banner!);
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.only(bottom: 88), // clear the FAB
      children: [
        ?banner,
        for (final (i, row) in rows.indexed) ...[
          if (i == 0 || !sameDay(rows[i - 1].at, row.at))
            DayHeader(day: row.at, today: widget.clock())
          else
            const Divider(height: 1),
          row.tile,
        ],
      ],
    );
  }
}

class _NoteTile extends StatelessWidget {
  const _NoteTile({required this.note, required this.changing, this.onTap});

  final Note note;

  /// Being edited or deleted on the server.
  final bool changing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      leading: Text(_time(context, note), style: theme.textTheme.titleMedium),
      title: note.description == null
          ? Text('(no description)', style: TextStyle(color: theme.hintColor))
          : Text(note.description!),
      trailing: changing
          ? const SizedBox.square(
              dimension: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : null,
      onTap: changing ? null : onTap,
    );
  }
}

/// A note that isn't on the server yet: tinted, in italics, with its
/// status underneath and a button to cancel it.
class _PendingNoteTile extends StatelessWidget {
  const _PendingNoteTile({
    required this.pending,
    required this.sending,
    required this.needsSignIn,
    required this.onCancel,
    required this.onRetry,
  });

  final PendingNote pending;
  final bool sending;
  final bool needsSignIn;
  final VoidCallback onCancel;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final muted = TextStyle(
      color: scheme.onSurfaceVariant,
      fontStyle: FontStyle.italic,
    );
    final failed = pending.attempts > 0 && !sending;

    final Widget icon;
    final String status;
    if (sending) {
      icon = const SizedBox.square(
        dimension: 12,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
      status = 'Saving…';
    } else if (needsSignIn) {
      icon = Icon(Icons.lock_outline, size: 14, color: scheme.error);
      status = 'Not saved · sign in to save';
    } else if (failed) {
      icon = Icon(Icons.cloud_off, size: 14, color: scheme.error);
      status = 'Not saved · ${pending.lastError ?? 'failed'} · retrying';
    } else {
      icon = Icon(Icons.schedule, size: 14, color: scheme.onSurfaceVariant);
      status = 'Waiting to save';
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
        tooltip: 'Cancel note',
        onPressed: sending ? null : onCancel,
      ),
      // Skip the wait for the next retry.
      onTap: failed && !needsSignIn ? onRetry : null,
    );
  }
}

/// [e] for a person: a tool's own error message, without the wrapping.
String _describe(Object e) => switch (e) {
  SignInRequiredException() => 'sign in first',
  McpException(:final message) => message.replaceFirst(
    RegExp(r'^Tool \w+ failed: '),
    '',
  ),
  _ => '$e',
};

String _time(BuildContext context, Note note) =>
    MaterialLocalizations.of(context)
        .formatTimeOfDay(TimeOfDay.fromDateTime(note.timestamp.toLocal()));
