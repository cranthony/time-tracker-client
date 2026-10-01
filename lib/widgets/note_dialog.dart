import 'package:flutter/material.dart';

import '../models/note.dart';

/// Asks for a new note's description and time (defaulting to [time], or
/// now). Returns the note, or null if cancelled.
Future<Note?> showAddNoteDialog(BuildContext context, {DateTime? time}) async {
  final result = await showDialog<NoteDialogResult>(
    context: context,
    builder: (_) => _NoteDialog(time: time),
  );
  return result is SaveNote ? result.note : null;
}

/// Lets the user change [note]'s description and time, or delete it.
/// Returns what they chose, or null if they cancelled.
Future<NoteDialogResult?> showEditNoteDialog(BuildContext context, Note note) =>
    showDialog<NoteDialogResult>(
      context: context,
      builder: (_) => _NoteDialog(note: note),
    );

sealed class NoteDialogResult {}

/// The note as the user left it: for an edit, with the original's id.
final class SaveNote extends NoteDialogResult {
  SaveNote(this.note);
  final Note note;
}

final class DeleteNote extends NoteDialogResult {}

class _NoteDialog extends StatefulWidget {
  const _NoteDialog({this.note, this.time});

  /// The note being edited; null for a new one.
  final Note? note;
  final DateTime? time;

  @override
  State<_NoteDialog> createState() => _NoteDialogState();
}

class _NoteDialogState extends State<_NoteDialog> {
  late final _description = TextEditingController(
    text: widget.note?.description,
  );
  late DateTime _time =
      widget.note?.timestamp.toLocal() ?? widget.time ?? DateTime.now();

  bool get _editing => widget.note != null;

  @override
  void dispose() {
    _description.dispose();
    super.dispose();
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_time),
    );
    if (picked == null) return;
    setState(() {
      _time = DateTime(
        _time.year,
        _time.month,
        _time.day,
        picked.hour,
        picked.minute,
      );
    });
  }

  void _submit() {
    final text = _description.text.trim();
    Navigator.of(context).pop(
      SaveNote(
        Note(
          timestamp: _time,
          description: text.isEmpty ? null : text,
          id: widget.note?.id,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final time = MaterialLocalizations.of(context)
        .formatTimeOfDay(TimeOfDay.fromDateTime(_time));
    return AlertDialog(
      title: Text(_editing ? 'Edit note' : 'New note'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _description,
            // Only for a new note: an edit may be just to the time.
            autofocus: !_editing,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'What are you doing?',
              hintText: 'Optional',
            ),
            onSubmitted: (_) => _submit(),
          ),
          const SizedBox(height: 16),
          ActionChip(
            avatar: const Icon(Icons.schedule),
            label: Text(time),
            onPressed: _pickTime,
          ),
        ],
      ),
      actions: [
        if (_editing)
          TextButton(
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () => Navigator.of(context).pop(DeleteNote()),
            child: const Text('Delete'),
          ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _submit,
          child: Text(_editing ? 'Save' : 'Add'),
        ),
      ],
    );
  }
}
