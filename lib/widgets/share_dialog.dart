import 'package:flutter/material.dart';

import '../models/share.dart';
import 'durations.dart';
import 'hotkeys.dart';

/// How much of an event, [eventMinutes] long, what [share] is of -- a
/// [kind] of thing ("goal"), called [title] -- takes: the rest (what the
/// others' minutes and percents leave, as [rest] explains), a duration,
/// or a percentage of what the durations leave; and with either of
/// those, the rest as well. [make] makes the share as set. Gives
/// it, or null if it's called off.
Future<S?> showShareDialog<S extends Share>(
  BuildContext context, {
  required String title,
  required S share,
  required int eventMinutes,
  required String kind,
  required String rest,
  required S Function(int? minutes, int? percent, bool remaining) make,
}) => showDialog<S>(
  context: context,
  builder: (context) => _ShareDialog<S>(
    title: title,
    share: share,
    eventMinutes: eventMinutes,
    kind: kind,
    rest: rest,
    make: make,
  ),
);

enum _Kind { rest, minutes, percent }

class _ShareDialog<S extends Share> extends StatefulWidget {
  const _ShareDialog({
    required this.title,
    required this.share,
    required this.eventMinutes,
    required this.kind,
    required this.rest,
    required this.make,
  });

  final String title;
  final S share;
  final int eventMinutes;
  final String kind;
  final String rest;
  final S Function(int? minutes, int? percent, bool remaining) make;

  @override
  State<_ShareDialog<S>> createState() => _ShareDialogState<S>();
}

class _ShareDialogState<S extends Share> extends State<_ShareDialog<S>> {
  late var _kind = widget.share.minutes != null
      ? _Kind.minutes
      : widget.share.percent != null
      ? _Kind.percent
      : _Kind.rest;
  late var _plusRest = widget.share.plusRemaining;
  late final _minutes = TextEditingController(
    text: '${widget.share.minutes ?? widget.eventMinutes}',
  );
  late final _percent = TextEditingController(
    text: '${widget.share.percent ?? 50}',
  );

  @override
  void dispose() {
    _minutes.dispose();
    _percent.dispose();
    super.dispose();
  }

  S? get _share => switch (_kind) {
    _Kind.rest => widget.make(null, null, false),
    _Kind.minutes => switch (int.tryParse(_minutes.text.trim())) {
      final m? when m > 0 && m <= widget.eventMinutes => widget.make(
        m,
        null,
        _plusRest,
      ),
      _ => null,
    },
    _Kind.percent => switch (int.tryParse(_percent.text.trim())) {
      final p? when p >= 1 && p <= 100 => widget.make(null, p, _plusRest),
      _ => null,
    },
  };

  @override
  Widget build(BuildContext context) {
    final share = _share;
    final save = share == null ? null : () => Navigator.of(context).pop(share);
    return SaveHotkey(
      onSave: save,
      child: AlertDialog(
        title: Text(widget.title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'How much of this ${formatMinutes(widget.eventMinutes)} event is '
              'for it?',
            ),
            const SizedBox(height: 12),
            SegmentedButton<_Kind>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: _Kind.rest, label: Text('The rest')),
                ButtonSegment(value: _Kind.minutes, label: Text('Minutes')),
                ButtonSegment(value: _Kind.percent, label: Text('Percent')),
              ],
              selected: {_kind},
              onSelectionChanged: (picked) =>
                  setState(() => _kind = picked.single),
            ),
            const SizedBox(height: 12),
            switch (_kind) {
              _Kind.rest => Text(widget.rest),
              _Kind.minutes => TextField(
                controller: _minutes,
                autofocus: true,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: 'Minutes',
                  helperText: 'At most ${widget.eventMinutes}',
                ),
                onChanged: (_) => setState(() {}),
              ),
              _Kind.percent => TextField(
                controller: _percent,
                autofocus: true,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: 'Percent',
                  suffixText: '%',
                  helperText:
                      "Of what the ${widget.kind}s given minutes don't take",
                ),
                onChanged: (_) => setState(() {}),
              ),
            },
            if (_kind != _Kind.rest)
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                value: _plusRest,
                title: const Text('And the rest too'),
                subtitle: Text(
                  'Also counts the time left over, as a ${widget.kind} given '
                  'neither does',
                ),
                onChanged: (on) => setState(() => _plusRest = on ?? false),
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(onPressed: save, child: const Text('Set')),
        ],
      ),
    );
  }
}
