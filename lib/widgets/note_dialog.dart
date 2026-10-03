import 'dart:math';

import 'package:flutter/material.dart';

import '../models/note.dart';

/// Asks for a new note's description and time (defaulting to [time], or
/// now), in a sheet over the bottom of the screen. Returns the note, or
/// null if dismissed.
Future<Note?> showAddNoteDialog(BuildContext context, {DateTime? time}) async {
  final result = await _showSheet(context, _NoteDialog(time: time));
  return result is SaveNote ? result.note : null;
}

/// Lets the user change [note]'s description and time, or delete it, in
/// the same sheet. Returns what they chose, or null if dismissed.
Future<NoteDialogResult?> showEditNoteDialog(BuildContext context, Note note) =>
    _showSheet(context, _NoteDialog(note: note));

/// Dismissed by swiping it down, tapping above it, or Back.
Future<NoteDialogResult?> _showSheet(BuildContext context, Widget sheet) =>
    showModalBottomSheet<NoteDialogResult>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => sheet,
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

  static const _dense = VisualDensity(horizontal: -4);

  void _nudge(Duration by) => setState(() => _time = _time.add(by));

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
    final theme = Theme.of(context);
    final time = MaterialLocalizations.of(context)
        .formatTimeOfDay(TimeOfDay.fromDateTime(_time));
    final media = MediaQuery.of(context);
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        // Above the keyboard, or else the gesture bar.
        bottom: max(media.viewInsets.bottom, media.viewPadding.bottom) + 12,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  _editing ? 'Edit note' : 'New note',
                  style: theme.textTheme.titleLarge,
                ),
              ),
              if (_editing)
                IconButton(
                  icon: const Icon(Icons.delete_outline),
                  color: theme.colorScheme.error,
                  tooltip: 'Delete note',
                  onPressed: () => Navigator.of(context).pop(DeleteNote()),
                ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _description,
            // Only for a new note: an edit may be just to the time.
            autofocus: !_editing,
            minLines: 4,
            maxLines: 8,
            // Wraps onto several lines, but Enter adds the note rather
            // than a new line.
            keyboardType: TextInputType.text,
            textInputAction: TextInputAction.done,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              hintText: 'What are you doing? (optional)',
              filled: true,
              border: OutlineInputBorder(borderSide: BorderSide.none),
            ),
            onSubmitted: (_) => _submit(),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              // Wraps "Now" under the time on a narrow screen.
              Expanded(
                child: Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.remove),
                      tooltip: 'A minute earlier',
                      visualDensity: _dense,
                      onPressed: () => _nudge(const Duration(minutes: -1)),
                    ),
                    ActionChip(
                      avatar: const Icon(Icons.schedule),
                      label: Text(time),
                      onPressed: _pickTime,
                    ),
                    IconButton(
                      icon: const Icon(Icons.add),
                      tooltip: 'A minute later',
                      visualDensity: _dense,
                      onPressed: () => _nudge(const Duration(minutes: 1)),
                    ),
                    TextButton(
                      style: TextButton.styleFrom(visualDensity: _dense),
                      onPressed: () => setState(() => _time = DateTime.now()),
                      child: const Text('Now'),
                    ),
                  ],
                ),
              ),
              FilledButton(
                onPressed: _submit,
                child: Text(_editing ? 'Save' : 'Add'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
