import 'package:flutter/material.dart';

import '../models/event_label.dart';
import '../models/note.dart';
import '../services/mcp_client.dart';
import 'color_picker.dart';
import 'durations.dart';

/// How a property is shown and edited.
enum PropertyKind {
  text,
  multiline,

  /// An ISO 8601 timestamp, shown and picked in local time.
  time,

  /// An event label's id, picked by name.
  label,
  integer,
  flag,

  /// True, false, or not set.
  optionalFlag,

  /// An ISO 8601 duration, typed as "1h 30m".
  duration,

  /// "#rrggbb".
  color,
}

/// A change offered as a button of its own, after the user confirms it,
/// such as cancelling an event.
class OneWayAction {
  const OneWayAction({
    required this.label,
    required this.question,
    required this.explanation,
    required this.keepLabel,
    required this.changes,
  });

  /// The button's text, also the confirming button's.
  final String label;
  final String question;
  final String explanation;

  /// The button that backs out.
  final String keepLabel;

  /// What [label] saves.
  final Map<String, Object?> changes;
}

/// Shows each of [properties] under a title [title] makes from them: its
/// key, then its value, or "(none)" for null. Values are shown as their
/// [kinds] say, or as they are.
///
/// With [save], tapping a value whose key has a kind opens it for editing,
/// in place; "Save" sends every change, as [kinds] encode them, to [save].
/// [validate] can refuse the values first, giving the reason; keys in
/// [required] can't be emptied. Returns what [save] returned, or null if
/// nothing was saved. [labels] lists the labels a [PropertyKind.label]
/// can be.
Future<R?> showPropertiesDialog<R>(
  BuildContext context, {
  required String Function(Map<String, Object?> values) title,
  required Map<String, Object?> properties,
  Map<String, PropertyKind> kinds = const {},
  Future<R> Function(Map<String, Object?> changes)? save,
  String? Function(Map<String, Object?> values)? validate,
  Set<String> required = const {},
  Map<String, String> hints = const {},
  Future<List<EventLabel>> Function()? labels,
  OneWayAction? oneWayAction,
  String signInHint = 'Sign in again, then try again.',
}) => showDialog<R>(
  context: context,
  builder: (context) => _PropertiesDialog<R>(
    title: title,
    properties: properties,
    kinds: kinds,
    save: save,
    validate: validate,
    required: required,
    hints: hints,
    labels: labels,
    oneWayAction: oneWayAction,
    signInHint: signInHint,
  ),
);

class _PropertiesDialog<R> extends StatefulWidget {
  const _PropertiesDialog({
    required this.title,
    required this.properties,
    required this.kinds,
    required this.save,
    required this.validate,
    required this.required,
    required this.hints,
    required this.labels,
    required this.oneWayAction,
    required this.signInHint,
  });

  final String Function(Map<String, Object?> values) title;
  final Map<String, Object?> properties;
  final Map<String, PropertyKind> kinds;
  final Future<R> Function(Map<String, Object?> changes)? save;
  final String? Function(Map<String, Object?> values)? validate;
  final Set<String> required;

  /// Said under a property's editor.
  final Map<String, String> hints;
  final Future<List<EventLabel>> Function()? labels;
  final OneWayAction? oneWayAction;

  /// What to do when saving needs sign-in.
  final String signInHint;

  @override
  State<_PropertiesDialog<R>> createState() => _PropertiesDialogState<R>();
}

class _PropertiesDialogState<R> extends State<_PropertiesDialog<R>> {
  Map<String, Object?> get _original => widget.properties;

  /// Values the user changed, encoded as [PropertyKind]s say.
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

  bool get _editable => widget.save != null;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Map<String, Object?> get _values => {..._original, ..._changes};

  Object? _value(String key) =>
      _changes.containsKey(key) ? _changes[key] : _original[key];

  void _open(String key) {
    final kind = widget.kinds[key]!;
    final value = _value(key);
    setState(() {
      _editing = key;
      _draftError = null;
      _draft = switch (kind) {
        PropertyKind.time => DateTime.parse(value as String).toLocal(),
        PropertyKind.flag => value == true,
        PropertyKind.color => parseColor(value as String?),
        _ => value,
      };
      _text.text = switch (kind) {
        PropertyKind.duration => switch (value) {
          final String iso => formatDuration(parseIsoDuration(iso)) ?? iso,
          _ => '',
        },
        _ => value == null ? '' : '$value',
      };
    });
    if (kind == PropertyKind.label && _labels == null) {
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
    Object? value;
    switch (widget.kinds[key]!) {
      case PropertyKind.text || PropertyKind.multiline:
        value = text.isEmpty ? null : text;
      case PropertyKind.time:
        value = localIsoTimestamp(_draft as DateTime);
      case PropertyKind.flag || PropertyKind.optionalFlag || PropertyKind.label:
        value = _draft;
      case PropertyKind.color:
        value = switch (_draft) {
          final Color color => colorToHex(color),
          _ => null,
        };
      case PropertyKind.integer:
        value = text.isEmpty ? null : int.tryParse(text);
        if (text.isNotEmpty && value == null) {
          setState(() => _draftError = 'Enter a whole number.');
          return false;
        }
      case PropertyKind.duration:
        final duration = text.isEmpty ? null : parseDuration(text);
        if (text.isNotEmpty && duration == null) {
          setState(() => _draftError = 'Enter a duration, like 1h 30m.');
          return false;
        }
        value = duration == null ? null : isoDuration(duration);
    }
    if (value == null && widget.required.contains(key)) {
      setState(() => _draftError = "This can't be empty.");
      return false;
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

  bool _same(String key, Object? a, Object? b) => switch (widget.kinds[key]) {
    PropertyKind.time when a is String && b is String => DateTime.parse(
      a,
    ).isAtSameMomentAs(DateTime.parse(b)),
    PropertyKind.duration when a is String && b is String =>
      parseIsoDuration(a) != null && parseIsoDuration(a) == parseIsoDuration(b),
    PropertyKind.color when a is String && b is String =>
      a.toLowerCase() == b.toLowerCase(),
    _ => a == b,
  };

  Future<void> _save([Map<String, Object?>? changes]) async {
    if (changes == null && !_confirmEdit()) return;
    changes ??= Map.of(_changes);
    if (widget.validate?.call({..._original, ...changes}) case final error?) {
      setState(() => _error = error);
      return;
    }
    final navigator = Navigator.of(context);
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final saved = await widget.save!(changes);
      navigator.pop(saved);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = switch (e) {
          SignInRequiredException() =>
            'You were signed out. ${widget.signInHint}',
          McpException(:final message) => message,
          _ => '$e',
        };
      });
    }
  }

  Future<void> _oneWay(OneWayAction action) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(action.question),
        content: Text(action.explanation),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(action.keepLabel),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
            ),
            child: Text(action.label),
          ),
        ],
      ),
    );
    if (confirmed == true) await _save(action.changes);
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
    final count = _changes.length;
    final oneWay = widget.oneWayAction;
    return PopScope(
      canPop: _changes.isEmpty && !_saving,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && !_saving) _confirmDiscard();
      },
      child: AlertDialog(
        title: Text(widget.title(_values)),
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
              for (final key in _original.keys) _row(context, key),
            ],
          ),
        ),
        actions: [
          if (_editable && count == 0 && oneWay != null)
            TextButton(
              onPressed: _saving ? null : () => _oneWay(oneWay),
              style: TextButton.styleFrom(
                foregroundColor: theme.colorScheme.error,
              ),
              child: Text(oneWay.label),
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
    final editable = _editable && widget.kinds.containsKey(key);
    final changed = _changes.containsKey(key);
    final value = _value(key);
    if (_editing == key) {
      return PropertyRow(name: key, child: _editor(context, key));
    }
    final shown = value == null
        ? Text('(none)', style: TextStyle(color: theme.hintColor))
        : _shown(context, key, value, selectable: !editable);
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

  Widget _shown(
    BuildContext context,
    String key,
    Object value, {
    required bool selectable,
  }) {
    final text = _format(context, key, value);
    final Widget label = selectable ? SelectableText(text) : Text(text);
    final color = widget.kinds[key] == PropertyKind.color
        ? parseColor('$value')
        : null;
    if (color == null) return label;
    return Row(
      children: [
        ColorDot(color: color),
        const SizedBox(width: 8),
        Flexible(child: label),
      ],
    );
  }

  Widget _editor(BuildContext context, String key) {
    final strings = MaterialLocalizations.of(context);
    final kind = widget.kinds[key]!;
    final Widget control = switch (kind) {
      PropertyKind.text ||
      PropertyKind.multiline ||
      PropertyKind.integer ||
      PropertyKind.duration => TextField(
        controller: _text,
        autofocus: true,
        minLines: kind == PropertyKind.multiline ? 2 : 1,
        maxLines: kind == PropertyKind.multiline ? 6 : 1,
        keyboardType: switch (kind) {
          PropertyKind.integer => TextInputType.number,
          PropertyKind.multiline => TextInputType.multiline,
          _ => TextInputType.text,
        },
        textCapitalization:
            kind == PropertyKind.text || kind == PropertyKind.multiline
            ? TextCapitalization.sentences
            : TextCapitalization.none,
        decoration: InputDecoration(
          isDense: true,
          border: const OutlineInputBorder(),
          hintText: kind == PropertyKind.duration ? 'e.g. 1h 30m' : null,
          errorText: _draftError,
        ),
        onSubmitted: kind == PropertyKind.multiline
            ? null
            : (_) => _confirmEdit(),
      ),
      PropertyKind.time => Wrap(
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
      PropertyKind.flag => Align(
        alignment: AlignmentDirectional.centerStart,
        child: Switch(
          value: _draft == true,
          onChanged: (on) => setState(() => _draft = on),
        ),
      ),
      PropertyKind.optionalFlag => SegmentedButton<int>(
        showSelectedIcon: false,
        segments: const [
          ButtonSegment(value: 1, label: Text('Yes')),
          ButtonSegment(value: 0, label: Text('No')),
          ButtonSegment(value: -1, label: Text('Not set')),
        ],
        selected: {
          switch (_draft) {
            true => 1,
            false => 0,
            _ => -1,
          },
        },
        onSelectionChanged: (picked) => setState(
          () => _draft = switch (picked.single) {
            1 => true,
            0 => false,
            _ => null,
          },
        ),
      ),
      PropertyKind.label => _labelPicker(context),
      PropertyKind.color => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ColorPicker(
            color: _draft as Color?,
            onChanged: (color) => _draft = color,
          ),
          if (_draftError case final error?)
            Text(
              error,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
        ],
      ),
    };
    final buttons = [
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
    ];
    final hint = switch (widget.hints[key]) {
      final hint? => Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Text(
          hint,
          style: Theme.of(context).textTheme.bodySmall
              ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
      ),
      null => null,
    };
    // The color picker and the three-way choice need the dialog's whole
    // width.
    if (kind == PropertyKind.color || kind == PropertyKind.optionalFlag) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 8),
          control,
          ?hint,
          Row(mainAxisAlignment: MainAxisAlignment.end, children: buttons),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: control),
            ...buttons,
          ],
        ),
        ?hint,
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
                  child: Row(
                    children: [
                      if (parseColor(label.backgroundColor) case final c?) ...[
                        ColorDot(color: c, size: 12),
                        const SizedBox(width: 8),
                      ],
                      Flexible(child: Text(labelName(label))),
                    ],
                  ),
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
    switch (widget.kinds[key]) {
      case PropertyKind.time when value is String:
        final local = DateTime.parse(value).toLocal();
        final strings = MaterialLocalizations.of(context);
        return '${strings.formatFullDate(local)}, '
            '${strings.formatTimeOfDay(TimeOfDay.fromDateTime(local))}';
      case PropertyKind.duration when value is String:
        return formatDuration(parseIsoDuration(value)) ?? value;
      case PropertyKind.label:
        // Its name, once the labels are loaded.
        return _labelNames[value] ?? '$value';
      default:
        return '$value';
    }
  }
}

/// One property in a properties dialog: its [name] in small primary-colored
/// type, any [marker] after it, then [child], its value.
class PropertyRow extends StatelessWidget {
  const PropertyRow({
    super.key,
    required this.name,
    required this.child,
    this.marker,
  });

  final String name;
  final Widget child;
  final Widget? marker;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                name,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: theme.colorScheme.primary,
                ),
              ),
              if (marker case final marker?) ...[
                const SizedBox(width: 6),
                marker,
              ],
            ],
          ),
          child,
        ],
      ),
    );
  }
}
