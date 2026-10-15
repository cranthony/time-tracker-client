import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import '../models/note.dart';

/// Asks for a new note's description and time (defaulting to [time], or
/// now), in a sheet over the bottom of the screen, and hands it to [keep]
/// -- the outbox's add, which keeps it on the device until it's saved --
/// itself: so it's kept whatever happened to the page that opened it
/// meanwhile. The sheet closes once [keep] has it; if [keep] fails, it
/// stays open, saying so, to try again. Returns the note kept, or null if
/// dismissed. Calls [onFieldFocused] once its field has focus and has
/// asked for the keyboard.
Future<Note?> showAddNoteDialog(
  BuildContext context, {
  required Future<void> Function(Note note) keep,
  DateTime? time,
  VoidCallback? onFieldFocused,
}) async {
  final result = await _showSheet(
    context,
    _NoteDialog(time: time, keep: keep, onFieldFocused: onFieldFocused),
  );
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
  const _NoteDialog({this.note, this.time, this.keep, this.onFieldFocused});

  /// The note being edited; null for a new one.
  final Note? note;
  final DateTime? time;

  /// Keeps a new note, before the sheet closes.
  final Future<void> Function(Note note)? keep;
  final VoidCallback? onFieldFocused;

  @override
  State<_NoteDialog> createState() => _NoteDialogState();
}

class _NoteDialogState extends State<_NoteDialog> {
  late final _description = TextEditingController(
    text: widget.note?.description,
  );
  late DateTime _time =
      widget.note?.timestamp.toLocal() ?? widget.time ?? DateTime.now();

  final _focus = FocusNode();

  /// Whether [_NoteDialog.keep] has the note, and hasn't answered yet.
  bool _keeping = false;

  /// Why [_NoteDialog.keep] couldn't keep it, the last time.
  String? _keepError;

  bool get _editing => widget.note != null;

  @override
  void initState() {
    super.initState();
    if (widget.onFieldFocused != null) _focus.addListener(_focusChanged);
  }

  void _focusChanged() {
    if (!_focus.hasFocus) return;
    _focus.removeListener(_focusChanged);
    // After the field's own listener has asked for the keyboard.
    scheduleMicrotask(widget.onFieldFocused!);
  }

  @override
  void dispose() {
    _focus.dispose();
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

  Future<void> _submit() async {
    if (_keeping) return;
    final text = _description.text.trim();
    final note = Note(
      timestamp: _time,
      description: text.isEmpty ? null : text,
      id: widget.note?.id,
    );
    if (widget.keep case final keep?) {
      setState(() {
        _keeping = true;
        _keepError = null;
      });
      try {
        await keep(note);
      } catch (e) {
        if (mounted) {
          setState(() {
            _keeping = false;
            _keepError = "Couldn't keep the note on this device: $e";
          });
        }
        return;
      }
      // Kept, even if the sheet was dismissed meanwhile.
      if (!mounted) return;
    }
    Navigator.of(context).pop(SaveNote(note));
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
            focusNode: _focus,
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
          if (_keepError case final error?)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                error,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
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
                onPressed: _keeping ? null : _submit,
                child: Text(
                  _editing
                      ? 'Save'
                      : _keepError == null
                      ? 'Add'
                      : 'Try again',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
