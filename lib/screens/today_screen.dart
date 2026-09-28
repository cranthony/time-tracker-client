import 'package:flutter/material.dart';

import '../models/note.dart';
import '../services/mcp_client.dart';
import '../services/notes_repository.dart';
import '../widgets/add_note_dialog.dart';

/// Today's uncompacted notes, with a "+" to add another.
class TodayScreen extends StatefulWidget {
  const TodayScreen({
    super.key,
    required this.repository,
    this.onSignIn,
    this.onSignOut,
    DateTime Function()? clock,
  }) : clock = clock ?? DateTime.now;

  final NotesRepository repository;

  /// Runs the interactive sign-in; null when the backend needs none.
  final Future<void> Function()? onSignIn;
  final Future<void> Function()? onSignOut;
  final DateTime Function() clock;

  @override
  State<TodayScreen> createState() => _TodayScreenState();
}

class _TodayScreenState extends State<TodayScreen> {
  List<Note>? _notes;
  Object? _error;
  bool _needsSignIn = false;
  bool _signingIn = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  bool _isToday(Note note) {
    final t = note.timestamp.toLocal();
    final now = widget.clock();
    return t.year == now.year && t.month == now.month && t.day == now.day;
  }

  Future<void> _load() async {
    try {
      final notes = await widget.repository.uncompactedNotes();
      if (!mounted) return;
      setState(() {
        _notes = notes.where(_isToday).toList();
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

  Future<void> _addNote() async {
    final note = await showAddNoteDialog(context);
    if (note == null || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await widget.repository.addNote(note);
      await _load();
    } on SignInRequiredException {
      await _load();
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Could not save note: $e')),
      );
    }
  }

  Future<void> _signIn() async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _signingIn = true);
    try {
      await widget.onSignIn!();
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
    return Scaffold(
      appBar: AppBar(
        title: const Text('Today'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Center(
              child: Text(
                widget.repository.label,
                style: Theme.of(context).textTheme.labelSmall,
              ),
            ),
          ),
          if (widget.onSignOut != null && !_needsSignIn)
            PopupMenuButton<void>(
              itemBuilder: (_) => [
                PopupMenuItem(onTap: _signOut, child: const Text('Sign out')),
              ],
            ),
        ],
      ),
      body: RefreshIndicator(onRefresh: _load, child: _buildBody(context)),
      floatingActionButton: _needsSignIn
          ? null
          : FloatingActionButton(
              onPressed: _addNote,
              tooltip: 'Add note',
              child: const Icon(Icons.add),
            ),
    );
  }

  Widget _buildBody(BuildContext context) {
    final notes = _notes;
    if (_needsSignIn) {
      return _Message(
        icon: Icons.lock_outline,
        text: 'Sign in to see your notes.',
        action: widget.onSignIn == null
            ? null
            : FilledButton(
                onPressed: _signingIn ? null : _signIn,
                child: Text(_signingIn ? 'Waiting for browser…' : 'Sign in'),
              ),
      );
    }
    if (_error != null && notes == null) {
      return _Message(
        icon: Icons.cloud_off,
        text: 'Could not load notes.\n$_error',
      );
    }
    if (notes == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (notes.isEmpty) {
      return const _Message(
        icon: Icons.edit_note,
        text: 'No notes yet today.\nTap + to add one.',
      );
    }
    final localizations = MaterialLocalizations.of(context);
    return ListView.separated(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.only(bottom: 88), // clear the FAB
      itemCount: notes.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, i) {
        final note = notes[i];
        final time = localizations.formatTimeOfDay(
          TimeOfDay.fromDateTime(note.timestamp.toLocal()),
        );
        return ListTile(
          leading: Text(time, style: Theme.of(context).textTheme.titleMedium),
          title: note.description == null
              ? Text(
                  '(no description)',
                  style: TextStyle(color: Theme.of(context).hintColor),
                )
              : Text(note.description!),
        );
      },
    );
  }
}

/// A centred icon and message that still supports pull-to-refresh.
class _Message extends StatelessWidget {
  const _Message({required this.icon, required this.text, this.action});

  final IconData icon;
  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: SizedBox(
          height: constraints.maxHeight,
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 48, color: Theme.of(context).hintColor),
                  const SizedBox(height: 16),
                  Text(text, textAlign: TextAlign.center),
                  if (action != null) ...[const SizedBox(height: 24), action!],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
