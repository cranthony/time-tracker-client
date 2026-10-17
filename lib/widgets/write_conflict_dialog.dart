import 'dart:convert';

import 'package:flutter/material.dart';

import '../outbox/write_queue.dart';
import 'hotkeys.dart';

/// Resolves [write], a change the server refused as made to its item since
/// changed elsewhere ([PendingWrite.conflicted]), in [queue]:
///
/// * Changed elsewhere: each field both changed is shown with the server's
///   value and the user's, to pick one or type another; the rest of the
///   change is kept. Saved, it's sent again, made to the item as it is.
/// * Deleted elsewhere: put back with the change, or the change dropped.
/// * A deletion of what was changed elsewhere: what changed is shown, to
///   delete it all the same or keep it.
///
/// Gives whether it was resolved; false if called off, still waiting.
Future<bool> showWriteConflictDialog(
  BuildContext context,
  WriteQueue queue,
  PendingWrite write,
) async =>
    await showDialog<bool>(
      context: context,
      builder: (_) => _ConflictDialog(queue: queue, write: write),
    ) ??
    false;

class _ConflictDialog extends StatefulWidget {
  const _ConflictDialog({required this.queue, required this.write});

  final WriteQueue queue;
  final PendingWrite write;

  @override
  State<_ConflictDialog> createState() => _ConflictDialogState();
}

/// Which value a field both changed takes.
enum _Pick { theirs, mine, typed }

class _ConflictDialogState extends State<_ConflictDialog> {
  PendingWrite get _write => widget.write;
  Map<String, Object?> get _current => _write.current ?? const {};

  late final _clashes = WriteQueue.clashes(_write);
  late final _picks = {for (final f in _clashes) f: _Pick.mine};
  late final _typed = {for (final f in _clashes) f: TextEditingController()};

  @override
  void dispose() {
    for (final c in _typed.values) {
      c.dispose();
    }
    super.dispose();
  }

  /// [value] as one would read it.
  static String _text(Object? value) => switch (value) {
    null => '(none)',
    final String s => s,
    final List list when list.every((v) => v is String) => list.join(', '),
    _ => const JsonEncoder.withIndent('  ').convert(value),
  };

  /// [field] as one would say it: "Map location".
  static String _label(String field) {
    final words = field.replaceAll('_', ' ');
    return words.isEmpty ? field : words[0].toUpperCase() + words.substring(1);
  }

  void _close(bool resolved) => Navigator.of(context).pop(resolved);

  Future<void> _save() async {
    final changes = {..._write.changes};
    for (final field in _clashes) {
      switch (_picks[field]!) {
        case _Pick.theirs:
          // Theirs is how it is: nothing to change.
          changes.remove(field);
        case _Pick.mine:
          break;
        case _Pick.typed:
          final typed = _typed[field]!.text.trim();
          changes[field] = typed.isEmpty ? null : typed;
      }
    }
    await widget.queue.resolve(_write, changes);
    if (mounted) _close(true);
  }

  Future<void> _drop() async {
    await widget.queue.drop(_write);
    if (mounted) _close(true);
  }

  @override
  Widget build(BuildContext context) {
    final kind = WriteQueue.kindOf(_write);
    final what = widget.queue.label(_write);
    final (title, body, actions) = switch (_write) {
      PendingWrite(op: WriteOp.delete) => (
        'Delete $what?',
        _changedElsewhere(context),
        [
          TextButton(onPressed: () => _drop(), child: const Text('Keep it')),
          FilledButton(
            onPressed: () async {
              await widget.queue.overwrite(_write);
              if (mounted) _close(true);
            },
            child: const Text('Delete it'),
          ),
        ],
      ),
      PendingWrite(current: null) => (
        '${_capital(kind.noun)} deleted elsewhere',
        Text(
          '$what was deleted after you changed it here. Put it back, with '
          'your changes, or drop them?',
        ),
        [
          TextButton(
            onPressed: () => _drop(),
            child: const Text('Drop my changes'),
          ),
          FilledButton(
            onPressed: () async {
              await widget.queue.restore(_write);
              if (mounted) _close(true);
            },
            child: const Text('Put it back'),
          ),
        ],
      ),
      _ => (
        'Changed elsewhere',
        _fields(context, what),
        [
          TextButton(
            onPressed: () => _drop(),
            child: const Text('Drop my changes'),
          ),
          HotkeyHint(
            Hotkey.save,
            child: FilledButton(onPressed: _save, child: const Text('Save')),
          ),
        ],
      ),
    };
    return SaveOrDiscard(
      // Called off, it waits as it was: nothing's lost.
      changed: () => false,
      onSave: _write.op == WriteOp.update && _write.current != null
          ? _save
          : null,
      onDiscard: () => _close(false),
      child: AlertDialog(
        title: Text(title),
        content: SizedBox(
          width: 440,
          child: SingleChildScrollView(child: body),
        ),
        actions: [
          TextButton(
            onPressed: () => _close(false),
            child: const Text('Later'),
          ),
          ...actions,
        ],
      ),
    );
  }

  static String _capital(String s) =>
      s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

  /// Each field both changed: the server's value, the user's, or another.
  Widget _fields(BuildContext context, String what) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '$what was changed elsewhere after you changed it here. Pick what '
          'each field both changed is to be; the rest of your changes are '
          'kept.',
          style: theme.textTheme.bodyMedium,
        ),
        for (final field in _clashes) ...[
          const SizedBox(height: 16),
          Text(_label(field), style: theme.textTheme.titleSmall),
          RadioGroup<_Pick>(
            groupValue: _picks[field],
            onChanged: (pick) => setState(() => _picks[field] = pick!),
            child: Column(
              children: [
                RadioListTile<_Pick>(
                  value: _Pick.theirs,
                  title: Text(_text(_current[field])),
                  subtitle: const Text('As it was changed elsewhere'),
                  dense: true,
                ),
                RadioListTile<_Pick>(
                  value: _Pick.mine,
                  title: Text(_text(_write.changes[field])),
                  subtitle: const Text('Yours'),
                  dense: true,
                ),
                if (_write.changes[field] is String? &&
                    _current[field] is String?)
                  RadioListTile<_Pick>(
                    value: _Pick.typed,
                    title: TextField(
                      controller: _typed[field],
                      decoration: const InputDecoration(
                        isDense: true,
                        hintText: 'Something else',
                      ),
                      onTap: () => setState(() => _picks[field] = _Pick.typed),
                      onChanged: (_) =>
                          setState(() => _picks[field] = _Pick.typed),
                    ),
                    dense: true,
                  ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  /// What was changed elsewhere, since the deletion was asked for.
  Widget _changedElsewhere(BuildContext context) {
    final theme = Theme.of(context);
    final changed = WriteQueue.changedElsewhere(_write);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'It was changed elsewhere after you deleted it here'
          '${changed.isEmpty ? '.' : ':'}',
          style: theme.textTheme.bodyMedium,
        ),
        for (final field in changed)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: '${_label(field)}: ',
                    style: theme.textTheme.titleSmall,
                  ),
                  TextSpan(
                    text:
                        '${_text(_write.base?[field])} → '
                        '${_text(_current[field])}',
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
