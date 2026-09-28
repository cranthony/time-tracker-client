import 'package:flutter/material.dart';

import '../models/note.dart';

/// Asks for a new note's description and time (defaulting to now). Returns
/// the note, or null if cancelled.
Future<Note?> showAddNoteDialog(BuildContext context) =>
    showDialog<Note>(context: context, builder: (_) => const _AddNoteDialog());

class _AddNoteDialog extends StatefulWidget {
  const _AddNoteDialog();

  @override
  State<_AddNoteDialog> createState() => _AddNoteDialogState();
}

class _AddNoteDialogState extends State<_AddNoteDialog> {
  final _description = TextEditingController();
  DateTime _time = DateTime.now();

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
    Navigator.of(context)
        .pop(Note(timestamp: _time, description: text.isEmpty ? null : text));
  }

  @override
  Widget build(BuildContext context) {
    final time = MaterialLocalizations.of(context)
        .formatTimeOfDay(TimeOfDay.fromDateTime(_time));
    return AlertDialog(
      title: const Text('New note'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _description,
            autofocus: true,
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
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Add')),
      ],
    );
  }
}
