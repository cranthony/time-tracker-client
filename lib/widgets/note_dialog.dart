import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import '../models/note.dart';
import '../services/note_drafts.dart';

/// Asks for a new note's description and time (defaulting to [time], or
/// now), in a sheet over the bottom of the screen, and hands it to [keep]
/// -- the outbox's add, which keeps it on the device until it's saved --
/// itself: so it's kept whatever happened to the page that opened it
/// meanwhile. The sheet closes once [keep] has it; if [keep] fails, it
/// stays open, saying so, to try again. Returns the note kept, or null if
/// dismissed. Calls [onFieldFocused] once its field has focus and has
/// asked for the keyboard.
///
/// What's typed is kept in [drafts] as it's typed, as a draft, until it's
/// added -- so closing the sheet, or the app, loses nothing; [draft], one
/// of them, carries on with it. Its trash can throws the draft away.
Future<Note?> showAddNoteDialog(
  BuildContext context, {
  required Future<void> Function(Note note) keep,
  NoteDrafts? drafts,
  NoteDraft? draft,
  DateTime? time,
  VoidCallback? onFieldFocused,
}) async {
  final result = await _showSheet(
    context,
    _NoteDialog(
      time: time,
      keep: keep,
      drafts: drafts,
      draft: draft,
      onFieldFocused: onFieldFocused,
    ),
  );
  return result is SaveNote ? result.note : null;
}

/// Lets the user change [note]'s description and time, or delete it, in
/// the same sheet, handing the change to [keepEdit], or the deletion to
/// [keepDelete] -- the outbox's, which keep them on the device until
/// they're saved -- before it closes; if that fails, it stays open,
/// saying so. Changes not saved yet are kept in [drafts] as a draft edit
/// of [note], as they're made; [draft], that draft, carries on with it.
/// Returns what they chose, or null if dismissed.
Future<NoteDialogResult?> showEditNoteDialog(
  BuildContext context,
  Note note, {
  required Future<void> Function(Note edited) keepEdit,
  required Future<void> Function() keepDelete,
  NoteDrafts? drafts,
  NoteDraft? draft,
}) => _showSheet(
  context,
  _NoteDialog(
    note: note,
    keepEdit: keepEdit,
    keepDelete: keepDelete,
    drafts: drafts,
    draft: draft,
  ),
);

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
  const _NoteDialog({
    this.note,
    this.time,
    this.keep,
    this.keepEdit,
    this.keepDelete,
    this.drafts,
    this.draft,
    this.onFieldFocused,
  });

  /// The note being edited; null for a new one.
  final Note? note;
  final DateTime? time;

  /// Keeps a new note, before the sheet closes.
  final Future<void> Function(Note note)? keep;

  /// Keep an edit of [note], or its deletion, before the sheet closes.
  final Future<void> Function(Note edited)? keepEdit;
  final Future<void> Function()? keepDelete;

  /// Where what's typed is kept as it's typed; [draft], one of them, is
  /// carried on with.
  final NoteDrafts? drafts;
  final NoteDraft? draft;
  final VoidCallback? onFieldFocused;

  @override
  State<_NoteDialog> createState() => _NoteDialogState();
}

class _NoteDialogState extends State<_NoteDialog> {
  late final _description = TextEditingController(
    text: widget.draft?.description ?? widget.note?.description,
  );
  late DateTime _time =
      widget.draft?.timestamp.toLocal() ??
      widget.note?.timestamp.toLocal() ??
      widget.time ??
      DateTime.now();

  final _focus = FocusNode();

  /// Whether the note, its change or its deletion is being kept, and
  /// hasn't been yet: no draft is kept meanwhile.
  bool _keeping = false;

  /// Why it couldn't be kept, the last time.
  String? _keepError;

  bool get _editing => widget.note != null;

  /// The draft's id in [_NoteDialog.drafts]: a new note's, once it's
  /// typed; an edit's, from its note's.
  late String? _draftId =
      widget.draft?.id ??
      switch (widget.note?.id) {
        final id? => NoteDraft.editId(id),
        null => null,
      };

  /// Whether there's a draft of it, to throw away.
  bool get _drafted =>
      _draftId != null && widget.drafts?.byId(_draftId!) != null;

  @override
  void initState() {
    super.initState();
    if (widget.onFieldFocused != null) _focus.addListener(_focusChanged);
    _description.addListener(_keepDraft);
  }

  /// Keeps what's typed as a draft -- or throws the draft away once
  /// there's nothing to keep: a new note with no description, or an edit
  /// back to how the note was.
  void _keepDraft() {
    final drafts = widget.drafts;
    if (drafts == null || _keeping) return;
    final text = _description.text;
    final note = widget.note;
    final unchanged = note == null
        ? text.trim().isEmpty
        : _time.isAtSameMomentAs(note.timestamp) &&
              text.trim() == (note.description ?? '');
    final was = _drafted;
    if (unchanged) {
      if (_draftId case final id?) drafts.remove(id);
    } else {
      final id = _draftId ??= '${DateTime.now().microsecondsSinceEpoch}';
      drafts.put(
        NoteDraft(id: id, timestamp: _time, description: text, original: note),
      );
    }
    if (_drafted != was && mounted) setState(() {});
  }

  /// Throws the draft away: it's been kept as a note, or isn't wanted.
  Future<void> _dropDraft() async {
    if (_draftId case final id?) await widget.drafts?.remove(id);
  }

  void _setTime(DateTime time) {
    setState(() => _time = time);
    _keepDraft();
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
    _setTime(
      DateTime(_time.year, _time.month, _time.day, picked.hour, picked.minute),
    );
  }

  static const _dense = VisualDensity(horizontal: -4);

  void _nudge(Duration by) => _setTime(_time.add(by));

  Future<void> _submit() async {
    final text = _description.text.trim();
    final note = Note(
      timestamp: _time,
      description: text.isEmpty ? null : text,
      id: widget.note?.id,
    );
    final keep = _editing ? widget.keepEdit : widget.keep;
    await _keepThen(
      keep == null ? null : () => keep(note),
      failed: _editing
          ? "Couldn't keep the change on this device"
          : "Couldn't keep the note on this device",
      result: SaveNote(note),
    );
  }

  Future<void> _delete() => _keepThen(
    widget.keepDelete,
    failed: "Couldn't keep the deletion on this device",
    result: DeleteNote(),
  );

  /// Runs [keep], and once it's kept, throws the draft away and closes
  /// with [result]; if it fails, stays open, saying it [failed], to try
  /// again.
  Future<void> _keepThen(
    Future<void> Function()? keep, {
    required String failed,
    required NoteDialogResult result,
  }) async {
    if (_keeping) return;
    setState(() {
      _keeping = true;
      _keepError = null;
    });
    try {
      await keep?.call();
    } catch (e) {
      if (mounted) {
        setState(() {
          _keeping = false;
          _keepError = '$failed: $e';
        });
      }
      return;
    }
    await _dropDraft();
    // Kept, even if the sheet was dismissed meanwhile.
    if (!mounted) return;
    Navigator.of(context).pop(result);
  }

  /// Throws the draft of a new note away, and closes.
  Future<void> _discard() async {
    await _dropDraft();
    if (mounted) Navigator.of(context).pop();
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
                  onPressed: _keeping ? null : _delete,
                )
              else if (_drafted)
                IconButton(
                  icon: const Icon(Icons.delete_outline),
                  color: theme.colorScheme.error,
                  tooltip: 'Discard draft',
                  onPressed: _keeping ? null : _discard,
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
                      onPressed: () => _setTime(DateTime.now()),
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
