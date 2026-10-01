import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/note.dart';

/// Asks for a new note's description and time (defaulting to [time], or
/// now). Returns the note, or null if cancelled.
Future<Note?> showAddNoteDialog(BuildContext context, {DateTime? time}) =>
    showDialog<Note>(
      context: context,
      builder: (_) => _AddNoteDialog(time: time),
    );

class _AddNoteDialog extends StatefulWidget {
  const _AddNoteDialog({this.time});

  final DateTime? time;

  @override
  State<_AddNoteDialog> createState() => _AddNoteDialogState();
}

class _AddNoteDialogState extends State<_AddNoteDialog> {
  final _description = TextEditingController();
  final _focus = FocusNode();
  late DateTime _time = widget.time ?? DateTime.now();
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    // Opened from the home screen widget, the dialog can be up before the
    // app's window has input focus, and Android won't show the keyboard
    // for a window without it. So show it again once the window has focus.
    _lifecycle = AppLifecycleListener(
      onStateChange: (state) => debugPrint('TimeTracker: dialog sees $state'),
      onResume: _showKeyboard,
    );
    _focus.addListener(
      () => debugPrint('TimeTracker: field focused: ${_focus.hasFocus}'),
    );
    debugPrint(
      'TimeTracker: dialog opened, app is '
      '${WidgetsBinding.instance.lifecycleState}',
    );
  }

  void _showKeyboard() {
    debugPrint('TimeTracker: showing the keyboard');
    if (!mounted || ModalRoute.of(context)?.isCurrent == false) return;
    if (!_focus.hasFocus) {
      _focus.requestFocus();
      return;
    }
    SystemChannels.textInput.invokeMethod<void>('TextInput.show');
  }

  @override
  void dispose() {
    _lifecycle.dispose();
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
            focusNode: _focus,
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
