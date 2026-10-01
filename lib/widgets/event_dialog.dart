import 'package:flutter/material.dart';

import '../models/event.dart';
import '../models/event_label.dart';
import '../models/note.dart';
import '../services/mcp_client.dart';
import 'event_label_dialog.dart';
import 'properties_dialog.dart';

/// Shows every property of [event], as the server sent it, under its
/// summary. Start and end are in local time; the rest are as sent.
///
/// Tapping a value the server lets one change opens it for editing, in
/// place; "Save" sends every change with [save]. Returns what [save]
/// returned (the events the server changed), or null if nothing was saved.
/// Without [save], or for an event with no id, nothing can be edited.
Future<List<Event>?> showEventDialog(
  BuildContext context,
  Event event, {
  Future<List<Event>> Function(Event event, Map<String, Object?> changes)? save,
  Future<List<EventLabel>> Function()? labels,
}) => showDialog<List<Event>>(
  context: context,
  builder: (context) => _EventDialog(event: event, save: save, labels: labels),
);

/// How a property is edited.
enum _Kind { text, multiline, time, label, integer, flag, duration }

const _kinds = {
  'summary': _Kind.text,
  'start': _Kind.time,
  'end': _Kind.time,
  'description': _Kind.multiline,
  'location': _Kind.text,
  'event_label_id': _Kind.label,
  'priority': _Kind.integer,
  'is_fixed_time': _Kind.flag,
  'is_fixed_duration': _Kind.flag,
  'min_duration': _Kind.duration,
};

class _EventDialog extends StatefulWidget {
  const _EventDialog({required this.event, this.save, this.labels});

  final Event event;
  final Future<List<Event>> Function(Event, Map<String, Object?>)? save;
  final Future<List<EventLabel>> Function()? labels;

  @override
  State<_EventDialog> createState() => _EventDialogState();
}

class _EventDialogState extends State<_EventDialog> {
  /// The event as the server sent it, times in local time.
  late final Map<String, Object?> _original = widget.event.toJson();

  /// Values the user changed, as `update_event` takes them.
  final _changes = <String, Object?>{};

  /// The property open for editing, and its value so far.
  String? _editing;
  Object? _draft;
  String? _draftError;
  final _text = TextEditingController();

  Future<List<EventLabel>>? _labels;

  /// Label names by id, once [_labels] has them.
  Map<String?, String> _labelNames = const {};
  bool _saving = false;

  /// Why the last save failed.
  String? _error;

  bool get _editable => widget.save != null && widget.event.id != null;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Object? _value(String key) =>
      _changes.containsKey(key) ? _changes[key] : _original[key];

  void _open(String key) {
    final value = _value(key);
    setState(() {
      _editing = key;
      _draftError = null;
      _draft = switch (_kinds[key]!) {
        _Kind.time => DateTime.parse(value as String).toLocal(),
        _Kind.flag => value == true,
        _ => value,
      };
      _text.text = switch (_kinds[key]!) {
        _Kind.duration => switch (value) {
          final String iso => formatDuration(parseIsoDuration(iso)) ?? iso,
          _ => '',
        },
        _ => value == null ? '' : '$value',
      };
    });
    if (_kinds[key] == _Kind.label && _labels == null) {
      _labels = widget.labels?.call()
        ?..then((labels) {
          if (!mounted) return;
          setState(() {
            _labelNames = {for (final l in labels) l.id: labelName(l)};
          });
        }, onError: (_) {});
    }
  }

  void _cancelEdit() => setState(() {
    _editing = null;
    _draftError = null;
  });

  /// Keeps the open property's new value; false if it isn't valid.
  bool _confirmEdit() {
    final key = _editing;
    if (key == null) return true;
    final text = _text.text.trim();
    final Object? value;
    switch (_kinds[key]!) {
      case _Kind.text || _Kind.multiline:
        value = text.isEmpty ? null : text;
      case _Kind.time:
        value = localIsoTimestamp(_draft as DateTime);
      case _Kind.flag || _Kind.label:
        value = _draft;
      case _Kind.integer:
        value = text.isEmpty ? null : int.tryParse(text);
        if (text.isNotEmpty && value == null) {
          setState(() => _draftError = 'Enter a whole number.');
          return false;
        }
      case _Kind.duration:
        final duration = text.isEmpty ? null : parseDuration(text);
        if (text.isNotEmpty && duration == null) {
          setState(() => _draftError = 'Enter a duration, like 1h 30m.');
          return false;
        }
        value = duration == null ? null : isoDuration(duration);
    }
    setState(() {
      if (_same(key, value, _original[key])) {
        _changes.remove(key);
      } else {
        _changes[key] = value;
      }
      _editing = null;
      _draftError = null;
    });
    return true;
  }

  static bool _same(String key, Object? a, Object? b) => switch (_kinds[key]) {
    _Kind.time when a is String && b is String => DateTime.parse(
      a,
    ).isAtSameMomentAs(DateTime.parse(b)),
    _Kind.duration when a is String && b is String =>
      parseIsoDuration(a) != null && parseIsoDuration(a) == parseIsoDuration(b),
    _ => a == b,
  };

  Future<void> _save([Map<String, Object?>? changes]) async {
    if (changes == null && !_confirmEdit()) return;
    changes ??= Map.of(_changes);
    final start = DateTime.parse(
      (changes['start'] ?? _original['start']) as String,
    );
    final end = DateTime.parse((changes['end'] ?? _original['end']) as String);
    if (!end.isAfter(start)) {
      setState(() => _error = 'The end has to be after the start.');
      return;
    }
    final navigator = Navigator.of(context);
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final updated = await widget.save!(widget.event, changes);
      navigator.pop(updated);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = switch (e) {
          SignInRequiredException() =>
            'You were signed out. Sign in again '
                'from the Events page, then try again.',
          McpException(:final message) => message,
          _ => '$e',
        };
      });
    }
  }

  Future<void> _cancelEvent() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cancel this event?'),
        content: const Text(
          "This can't be undone. The event stays in the list, struck "
          'through.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Keep event'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('Cancel event'),
          ),
        ],
      ),
    );
    if (confirmed == true) await _save({'is_cancelled': true});
  }

  Future<void> _confirmDiscard() async {
    final discard = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Discard changes?'),
        content: Text(
          'You changed ${_changes.keys.join(', ')}. Closing now throws '
          '${_changes.length == 1 ? 'that' : 'those'} away.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Keep editing'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Discard'),
          ),
        ],
      ),
    );
    if (discard == true && mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final summary = _value('summary') as String?;
    // The typed fields first, for an event made without the server's.
    final keys = {
      'id',
      'summary',
      'start',
      'end',
      'is_cancelled',
      ...widget.event.properties.keys,
    };
    final count = _changes.length;
    return PopScope(
      canPop: _changes.isEmpty && !_saving,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && !_saving) _confirmDiscard();
      },
      child: AlertDialog(
        title: Text(
          summary == null || summary.isEmpty ? '(no summary)' : summary,
        ),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_error case final error?)
                Container(
                  margin: const EdgeInsets.only(bottom: 16),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.errorContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.error_outline,
                        color: theme.colorScheme.onErrorContainer,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: SelectableText(
                          "Couldn't save. $error",
                          style: TextStyle(
                            color: theme.colorScheme.onErrorContainer,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              for (final key in keys) _row(context, key),
            ],
          ),
        ),
        actions: [
          if (_editable && count == 0 && !widget.event.isCancelled)
            TextButton(
              onPressed: _saving ? null : _cancelEvent,
              style: TextButton.styleFrom(
                foregroundColor: theme.colorScheme.error,
              ),
              child: const Text('Cancel event'),
            ),
          if (count > 0)
            TextButton(
              onPressed: _saving
                  ? null
                  : () => setState(() {
                      _changes.clear();
                      _error = null;
                    }),
              child: const Text('Revert'),
            ),
          TextButton(
            onPressed: _saving ? null : () => Navigator.of(context).maybePop(),
            child: const Text('Close'),
          ),
          if (count > 0 || _editing != null)
            FilledButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(
                      count == 0
                          ? 'Save'
                          : 'Save $count change${count == 1 ? '' : 's'}',
                    ),
            ),
        ],
      ),
    );
  }

  Widget _row(BuildContext context, String key) {
    final theme = Theme.of(context);
    final editable = _editable && _kinds.containsKey(key);
    final changed = _changes.containsKey(key);
    final value = _value(key);
    if (_editing == key) {
      return PropertyRow(name: key, child: _editor(context, key));
    }
    final shown = value == null
        ? Text('(none)', style: TextStyle(color: theme.hintColor))
        : editable
        ? Text(_format(context, key, value))
        : SelectableText(_format(context, key, value));
    return PropertyRow(
      name: key,
      marker: changed
          ? Tooltip(
              message: 'Changed',
              child: Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  color: theme.colorScheme.tertiary,
                  shape: BoxShape.circle,
                ),
              ),
            )
          : null,
      child: !editable
          ? shown
          : InkWell(
              onTap: _saving
                  ? null
                  : () {
                      if (_confirmEdit()) _open(key);
                    },
              borderRadius: BorderRadius.circular(6),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(width: double.infinity, child: shown),
                    if (changed)
                      Text(
                        _original[key] == null
                            ? '(none)'
                            : _format(context, key, _original[key]!),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.hintColor,
                          decoration: TextDecoration.lineThrough,
                        ),
                      ),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _editor(BuildContext context, String key) {
    final strings = MaterialLocalizations.of(context);
    final kind = _kinds[key]!;
    final Widget control = switch (kind) {
      _Kind.text ||
      _Kind.multiline ||
      _Kind.integer ||
      _Kind.duration => TextField(
        controller: _text,
        autofocus: true,
        minLines: kind == _Kind.multiline ? 2 : 1,
        maxLines: kind == _Kind.multiline ? 6 : 1,
        keyboardType: switch (kind) {
          _Kind.integer => TextInputType.number,
          _Kind.multiline => TextInputType.multiline,
          _ => TextInputType.text,
        },
        textCapitalization: kind == _Kind.text || kind == _Kind.multiline
            ? TextCapitalization.sentences
            : TextCapitalization.none,
        decoration: InputDecoration(
          isDense: true,
          border: const OutlineInputBorder(),
          hintText: kind == _Kind.duration ? 'e.g. 1h 30m' : null,
          errorText: _draftError,
        ),
        onSubmitted: kind == _Kind.multiline ? null : (_) => _confirmEdit(),
      ),
      _Kind.time => Wrap(
        spacing: 8,
        children: [
          ActionChip(
            avatar: const Icon(Icons.calendar_today),
            label: Text(strings.formatMediumDate(_draft as DateTime)),
            onPressed: _pickDate,
          ),
          ActionChip(
            avatar: const Icon(Icons.schedule),
            label: Text(
              strings.formatTimeOfDay(
                TimeOfDay.fromDateTime(_draft as DateTime),
              ),
            ),
            onPressed: _pickTime,
          ),
        ],
      ),
      _Kind.flag => Align(
        alignment: AlignmentDirectional.centerStart,
        child: Switch(
          value: _draft == true,
          onChanged: (on) => setState(() => _draft = on),
        ),
      ),
      _Kind.label => _labelPicker(context),
    };
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: control),
        IconButton(
          icon: const Icon(Icons.close),
          tooltip: 'Cancel edit',
          onPressed: _cancelEdit,
        ),
        IconButton(
          icon: const Icon(Icons.check),
          tooltip: 'Keep edit',
          color: Theme.of(context).colorScheme.primary,
          onPressed: _confirmEdit,
        ),
      ],
    );
  }

  Widget _labelPicker(BuildContext context) {
    final labels = _labels;
    if (labels == null) {
      // Nowhere to list labels from: take an id.
      return TextField(
        controller: _text,
        autofocus: true,
        decoration: const InputDecoration(
          isDense: true,
          border: OutlineInputBorder(),
        ),
        onChanged: (text) => _draft = text.trim().isEmpty ? null : text.trim(),
      );
    }
    return FutureBuilder(
      future: labels,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Text(
            "Couldn't load labels. ${switch (snapshot.error) {
              McpException(:final message) => message,
              final e => '$e',
            }}",
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          );
        }
        final list = snapshot.data;
        if (list == null) return const LinearProgressIndicator();
        final ids = {for (final label in list) label.id};
        return DropdownButton<String?>(
          isExpanded: true,
          value: ids.contains(_draft) ? _draft as String? : null,
          items: [
            const DropdownMenuItem(value: null, child: Text('(none)')),
            for (final label in list)
              if (label.id != null)
                DropdownMenuItem(
                  value: label.id,
                  child: Text(labelName(label)),
                ),
          ],
          onChanged: (id) => setState(() => _draft = id),
        );
      },
    );
  }

  Future<void> _pickDate() async {
    final current = _draft as DateTime;
    final picked = await showDatePicker(
      context: context,
      initialDate: current,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked == null) return;
    setState(() {
      _draft = DateTime(
        picked.year,
        picked.month,
        picked.day,
        current.hour,
        current.minute,
      );
    });
  }

  Future<void> _pickTime() async {
    final current = _draft as DateTime;
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(current),
    );
    if (picked == null) return;
    setState(() {
      _draft = DateTime(
        current.year,
        current.month,
        current.day,
        picked.hour,
        picked.minute,
      );
    });
  }

  String _format(BuildContext context, String key, Object value) {
    switch (_kinds[key]) {
      case _Kind.time:
        final local = DateTime.parse(value as String).toLocal();
        final strings = MaterialLocalizations.of(context);
        return '${strings.formatFullDate(local)}, '
            '${strings.formatTimeOfDay(TimeOfDay.fromDateTime(local))}';
      case _Kind.duration when value is String:
        return formatDuration(parseIsoDuration(value)) ?? value;
      case _Kind.label:
        // Its name, once the labels are loaded.
        return _labelNames[value] ?? '$value';
      default:
        return '$value';
    }
  }
}

/// [iso], an ISO 8601 duration such as "PT1H30M", or null if it isn't one.
Duration? parseIsoDuration(String iso) {
  final match = RegExp(
    r'^P(?:(\d+)D)?(?:T(?:(\d+)H)?(?:(\d+)M)?(?:(\d+(?:\.\d+)?)S)?)?$',
  ).firstMatch(iso.trim());
  if (match == null || iso.trim() == 'P' || iso.trim().endsWith('T')) {
    return null;
  }
  int part(int i) => int.parse(match[i] ?? '0');
  return Duration(
    days: part(1),
    hours: part(2),
    minutes: part(3),
    microseconds: (double.parse(match[4] ?? '0') * 1e6).round(),
  );
}

/// [duration] as `update_event` takes it, e.g. "PT1H30M".
String isoDuration(Duration duration) {
  final hours = duration.inHours;
  final minutes = duration.inMinutes % 60;
  final seconds = duration.inSeconds % 60;
  if (duration == Duration.zero) return 'PT0S';
  return 'PT${hours > 0 ? '${hours}H' : ''}'
      '${minutes > 0 ? '${minutes}M' : ''}'
      '${seconds > 0 ? '${seconds}S' : ''}';
}

/// [duration] as one would write it, e.g. "1h 30m"; null for null.
String? formatDuration(Duration? duration) {
  if (duration == null) return null;
  final hours = duration.inHours;
  final minutes = duration.inMinutes % 60;
  final seconds = duration.inSeconds % 60;
  final parts = [
    if (hours > 0) '${hours}h',
    if (minutes > 0) '${minutes}m',
    if (seconds > 0) '${seconds}s',
  ];
  return parts.isEmpty ? '0m' : parts.join(' ');
}

/// A duration as one would type it: "1h 30m", "1h", "90m", "90" (minutes),
/// "1:30", or ISO 8601 ("PT1H30M"). Null if [text] is none of those.
Duration? parseDuration(String text) {
  final t = text.trim().toLowerCase();
  if (t.startsWith('p')) return parseIsoDuration(t.toUpperCase());
  final clock = RegExp(r'^(\d+):([0-5]\d)$').firstMatch(t);
  if (clock != null) {
    return Duration(hours: int.parse(clock[1]!), minutes: int.parse(clock[2]!));
  }
  final minutes = int.tryParse(t);
  if (minutes != null) return Duration(minutes: minutes);
  final match = RegExp(
    r'^(?:(\d+)\s*h(?:ours?|rs?)?)?\s*(?:(\d+)\s*m(?:in(?:ute)?s?)?)?$',
  ).firstMatch(t);
  if (match == null || (match[1] == null && match[2] == null)) return null;
  return Duration(
    hours: int.parse(match[1] ?? '0'),
    minutes: int.parse(match[2] ?? '0'),
  );
}
