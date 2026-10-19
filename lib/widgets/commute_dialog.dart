import 'package:flutter/material.dart';

import 'hotkeys.dart';
import 'duration_field.dart';

/// A commute as [showCommuteDialog] leaves it: its [summary], and how
/// long it takes.
typedef CommuteFields = ({String summary, Duration length});

/// Asks for a commute's summary and how long it takes, starting from
/// [summary] and [length], under [title] -- the way it's done by -- with
/// [help] above how long it takes: where it's from and to, and how long
/// that takes, as far as they're known. Null if called off. It can't be
/// saved without a summary, or taking no time.
Future<CommuteFields?> showCommuteDialog(
  BuildContext context, {
  required String title,
  required String summary,
  required Duration length,
  String? help,
}) => showDialog<CommuteFields>(
  context: context,
  builder: (_) => _CommuteDialog(
    title: title,
    summary: summary,
    length: length,
    help: help,
  ),
);

class _CommuteDialog extends StatefulWidget {
  const _CommuteDialog({
    required this.title,
    required this.summary,
    required this.length,
    this.help,
  });

  final String title;
  final String summary;
  final Duration length;
  final String? help;

  @override
  State<_CommuteDialog> createState() => _CommuteDialogState();
}

class _CommuteDialogState extends State<_CommuteDialog> {
  late final _summary = TextEditingController(text: widget.summary);
  late final _minutes = TextEditingController(
    text: '${widget.length.inMinutes}',
  );

  @override
  void dispose() {
    _summary.dispose();
    _minutes.dispose();
    super.dispose();
  }

  /// What's typed, if it can be saved.
  CommuteFields? get _fields {
    final summary = _summary.text.trim();
    final minutes = int.tryParse(_minutes.text.trim());
    if (summary.isEmpty || minutes == null || minutes <= 0) return null;
    return (summary: summary, length: Duration(minutes: minutes));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fields = _fields;
    final save = fields == null
        ? null
        : () => Navigator.of(context).pop(fields);
    return SaveHotkey(
      onSave: save,
      child: AlertDialog(
        title: Text(widget.title),
        scrollable: true,
        content: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            FieldHotkey(
              'S',
              child: TextField(
                controller: _summary,
                decoration: const InputDecoration(
                  labelText: 'Summary',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                onChanged: (_) => setState(() {}),
              ),
            ),
            const SizedBox(height: 16),
            if (widget.help case final help?)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  help,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            FieldHotkey(
              'T',
              child: DurationField(
                controller: _minutes,
                label: 'Takes',
                step: 5,
                onChanged: () => setState(() {}),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(onPressed: save, child: const Text('Save')),
        ],
      ),
    );
  }
}
