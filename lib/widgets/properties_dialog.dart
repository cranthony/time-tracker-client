import 'package:flutter/material.dart';

import 'package:flutter/foundation.dart';

import '../models/goal.dart';
import '../models/measure.dart';
import '../models/note.dart';
import '../services/mcp_client.dart';
import 'color_picker.dart';
import 'durations.dart';
import 'measure_editor.dart';

/// How a property is shown and edited.
enum PropertyKind {
  text,
  multiline,

  /// An ISO 8601 timestamp, shown and picked in local time.
  time,

  /// A goal's id, picked by name.
  goal,

  /// A list of goals' ids, picked by name; the first is the primary goal.
  goals,

  /// One of a fixed set of values, given by the dialog's `choices`.
  choice,

  /// An ISO 8601 date, e.g. "2026-12-31".
  date,
  integer,
  flag,

  /// True, false, or not set.
  optionalFlag,

  /// An ISO 8601 duration, typed as "1h 30m".
  duration,

  /// "#rrggbb".
  color,

  /// A goal's measure (see models/measure.dart); a weighted rollup weighs
  /// the sub-goals of the goal with the dialog's "id".
  measure,

  /// A list of text lines, edited one per line.
  lines,
}

/// A property's value shown as a link that [open]s something else, such as
/// another dialog, rather than being edited in place.
class PropertyLink {
  const PropertyLink({required this.label, required this.open});

  /// What the link says, in place of the value.
  final String label;

  /// Opens it; true if that changed something, which closes the dialog.
  final Future<bool> Function() open;
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
/// nothing was saved. [goals] lists the goals a [PropertyKind.goal] or
/// [PropertyKind.goals] can be; [choices] gives each [PropertyKind.choice]
/// property's values, and how each is shown; [links] shows those keys'
/// values as links instead. [confirmSave] is asked before each save, with
/// the changes; false calls the save off, keeping the dialog open.
/// [inferred] marks values that were guessed rather than set, by key, with
/// a note shown after them (e.g. "from its label"): keeping one, even
/// unchanged, counts as a change, so saving confirms it. [changes] opens
/// it with those changes already made, e.g. ones that couldn't be saved
/// before; closing it without changing them more doesn't ask first.
Future<R?> showPropertiesDialog<R>(
  BuildContext context, {
  required String Function(Map<String, Object?> values) title,
  required Map<String, Object?> properties,
  Map<String, PropertyKind> kinds = const {},
  Future<R> Function(Map<String, Object?> changes)? save,
  Future<bool> Function(Map<String, Object?> changes)? confirmSave,
  String? Function(Map<String, Object?> values)? validate,
  Set<String> required = const {},
  Map<String, String> hints = const {},
  Future<List<Goal>> Function()? goals,
  Map<String, Map<String, String>> choices = const {},
  Map<String, PropertyLink> links = const {},
  Map<String, String> inferred = const {},
  Map<String, Object?> changes = const {},
  OneWayAction? oneWayAction,
  String signInHint = 'Sign in again, then try again.',
}) => showDialog<R>(
  context: context,
  builder: (context) => _PropertiesDialog<R>(
    title: title,
    properties: properties,
    kinds: kinds,
    save: save,
    confirmSave: confirmSave,
    validate: validate,
    required: required,
    hints: hints,
    goals: goals,
    choices: choices,
    links: links,
    inferred: inferred,
    changes: changes,
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
    required this.confirmSave,
    required this.validate,
    required this.required,
    required this.hints,
    required this.goals,
    required this.choices,
    required this.links,
    required this.inferred,
    required this.changes,
    required this.oneWayAction,
    required this.signInHint,
  });

  final String Function(Map<String, Object?> values) title;
  final Map<String, Object?> properties;
  final Map<String, PropertyKind> kinds;
  final Future<R> Function(Map<String, Object?> changes)? save;
  final Future<bool> Function(Map<String, Object?> changes)? confirmSave;
  final String? Function(Map<String, Object?> values)? validate;
  final Set<String> required;

  /// Said under a property's editor.
  final Map<String, String> hints;
  final Future<List<Goal>> Function()? goals;
  final Map<String, Map<String, String>> choices;
  final Map<String, PropertyLink> links;
  final Map<String, String> inferred;

  /// The changes it opens with.
  final Map<String, Object?> changes;
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

  Future<List<Goal>>? _goals;

  /// Goal names by id, once [_goals] has them.
  Map<String?, String> _goalNames = const {};

  /// Goal paths from the top ("Cooking › Tofu") by id, likewise.
  Map<String?, String> _goalPaths = const {};
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
        PropertyKind.goals => [...(value as List? ?? const []).cast<String>()],
        PropertyKind.measure => switch (value) {
          final Map measure => Map<String, Object?>.of(measure.cast()),
          _ => null,
        },
        PropertyKind.date => switch (value) {
          final String iso => DateTime.tryParse(iso),
          _ => null,
        },
        _ => value,
      };
      _text.text = switch (kind) {
        PropertyKind.duration => switch (value) {
          final String iso => formatDuration(parseIsoDuration(iso)) ?? iso,
          _ => '',
        },
        PropertyKind.goals => (value as List? ?? const []).join(', '),
        PropertyKind.lines => (value as List? ?? const []).join('\n'),
        _ => value == null ? '' : '$value',
      };
    });
  }

  /// Whether [_changes] differ from those it opened with: closing then
  /// asks first.
  bool get _changedHere =>
      _changes.length != widget.changes.length ||
      _changes.entries.any(
        (e) =>
            !widget.changes.containsKey(e.key) ||
            e.value != widget.changes[e.key],
      );

  @override
  void initState() {
    super.initState();
    _changes.addAll(widget.changes);
    // Goals are shown by name, so they're needed before anything opens.
    if (widget.kinds.values.any(
      (kind) =>
          kind == PropertyKind.goal ||
          kind == PropertyKind.goals ||
          kind == PropertyKind.measure,
    )) {
      _goals = widget.goals?.call()
        ?..then((goals) {
          if (!mounted) return;
          setState(() {
            _goalNames = {for (final g in goals) g.id: goalName(g)};
            _goalPaths = {for (final g in goals) g.id: g.path ?? goalName(g)};
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
      case PropertyKind.lines:
        final lines = [
          for (final line in text.split('\n'))
            if (line.trim().isNotEmpty) line.trim(),
        ];
        value = lines.isEmpty ? null : lines;
      case PropertyKind.time:
        value = localIsoTimestamp(_draft as DateTime);
      case PropertyKind.flag ||
          PropertyKind.optionalFlag ||
          PropertyKind.goal ||
          PropertyKind.choice:
        value = _draft;
      case PropertyKind.goals:
        value = [...(_draft as List<String>)];
      case PropertyKind.date:
        value = switch (_draft) {
          final DateTime day =>
            '${day.year.toString().padLeft(4, '0')}-'
                '${day.month.toString().padLeft(2, '0')}-'
                '${day.day.toString().padLeft(2, '0')}',
          _ => null,
        };
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
      case PropertyKind.measure:
        value = _draft;
        final problem = value is Measure ? measureProblem(value) : null;
        if (problem != null) {
          setState(() => _draftError = problem);
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
      // An inferred value, kept, is confirmed: a change even if the same.
      if (_same(key, value, _original[key]) &&
          !widget.inferred.containsKey(key)) {
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
    PropertyKind.measure when a is Map && b is Map => mapEquals(
      a.cast<String, Object?>(),
      b.cast<String, Object?>(),
    ),
    PropertyKind.lines => listEquals(
      (a as List? ?? const []).cast<String>(),
      (b as List? ?? const []).cast<String>(),
    ),
    PropertyKind.goals => listEquals(
      (a as List? ?? const []).cast<String>(),
      (b as List? ?? const []).cast<String>(),
    ),
    _ => a == b,
  };

  Future<void> _save([Map<String, Object?>? changes]) async {
    if (changes == null && !_confirmEdit()) return;
    changes ??= Map.of(_changes);
    if (widget.validate?.call({..._original, ...changes}) case final error?) {
      setState(() => _error = error);
      return;
    }
    if (widget.confirmSave case final confirm?) {
      if (!await confirm(changes) || !mounted) return;
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
      canPop: !_changedHere && !_saving,
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
    if (widget.links[key] case final link? when value != null) {
      return PropertyRow(
        name: key,
        child: InkWell(
          onTap: _saving
              ? null
              : () async {
                  final navigator = Navigator.of(context);
                  if (await link.open() && mounted) navigator.pop();
                },
          borderRadius: BorderRadius.circular(6),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(
              children: [
                Flexible(
                  child: Text(
                    link.label,
                    style: TextStyle(
                      color: theme.colorScheme.primary,
                      decoration: TextDecoration.underline,
                      decorationColor: theme.colorScheme.primary,
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                Icon(
                  Icons.chevron_right,
                  size: 18,
                  color: theme.colorScheme.primary,
                ),
              ],
            ),
          ),
        ),
      );
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
    final note = _changes.containsKey(key) ? null : widget.inferred[key];
    final Widget label = note == null
        ? (selectable ? SelectableText(text) : Text(text))
        : Text.rich(
            TextSpan(
              text: text,
              children: [
                TextSpan(
                  text: ' ($note)',
                  style: TextStyle(color: Theme.of(context).hintColor),
                ),
              ],
            ),
          );
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
      PropertyKind.lines ||
      PropertyKind.integer ||
      PropertyKind.duration => TextField(
        controller: _text,
        autofocus: true,
        minLines: kind == PropertyKind.multiline || kind == PropertyKind.lines
            ? 2
            : 1,
        maxLines: kind == PropertyKind.multiline || kind == PropertyKind.lines
            ? 6
            : 1,
        keyboardType: switch (kind) {
          PropertyKind.integer => TextInputType.number,
          PropertyKind.multiline ||
          PropertyKind.lines => TextInputType.multiline,
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
        onSubmitted:
            kind == PropertyKind.multiline || kind == PropertyKind.lines
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
      PropertyKind.goal => _goalPicker(context),
      PropertyKind.goals => _goalsPicker(context),
      PropertyKind.choice => DropdownButton<String?>(
        isExpanded: true,
        value: _draft as String?,
        items: [
          const DropdownMenuItem(value: null, child: Text('(none)')),
          for (final MapEntry(:key, :value)
              in (widget.choices[key] ?? const {}).entries)
            DropdownMenuItem(value: key, child: Text(value)),
        ],
        onChanged: (picked) => setState(() => _draft = picked),
      ),
      PropertyKind.date => Wrap(
        spacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          ActionChip(
            avatar: const Icon(Icons.calendar_today),
            label: Text(switch (_draft) {
              final DateTime day => strings.formatMediumDate(day),
              _ => 'Pick a date',
            }),
            onPressed: _pickDay,
          ),
          if (_draft != null)
            TextButton(
              onPressed: () => setState(() => _draft = null),
              child: const Text('Clear'),
            ),
        ],
      ),
      PropertyKind.measure => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          MeasureEditor(
            measure: _draft as Measure?,
            goalId: _values['id'] as String?,
            goals: _goals,
            onChanged: (measure) => _draft = measure,
          ),
          if (_draftError case final error?)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                error,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
        ],
      ),
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
    // The color picker, the three-way choice, the goals list and the
    // measure's fields need the dialog's whole width.
    if (kind == PropertyKind.color ||
        kind == PropertyKind.optionalFlag ||
        kind == PropertyKind.goals ||
        kind == PropertyKind.measure) {
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

  /// [build]s with the goals, once [_goals] has them; a message if they
  /// couldn't be loaded, and a progress bar until then.
  Widget _withGoals(
    BuildContext context,
    Widget Function(List<Goal> goals) build,
  ) => FutureBuilder(
    future: _goals,
    builder: (context, snapshot) {
      if (snapshot.hasError) {
        return Text(
          "Couldn't load goals. ${switch (snapshot.error) {
            McpException(:final message) => message,
            final e => '$e',
          }}",
          style: TextStyle(color: Theme.of(context).colorScheme.error),
        );
      }
      final list = snapshot.data;
      if (list == null) return const LinearProgressIndicator();
      // Not a goal that can be a parent, or be given to an event.
      return build([
        for (final goal in list)
          if (!goal.isOverall) goal,
      ]);
    },
  );

  /// [goal] by name, after its color, indented under its parent -- or,
  /// with [path], by its whole path from the top, wrapping as it needs to,
  /// for a goal shown out of its tree. Without [indent], for a list that
  /// indents it already.
  Widget _goalLabel(Goal goal, {bool path = false, bool indent = true}) =>
      Padding(
        padding: EdgeInsetsDirectional.only(
          start: path || !indent ? 0 : 16.0 * goal.depth,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (parseColor(goal.backgroundColor ?? goal.effectiveColor)
                case final c?) ...[
              ColorDot(color: c, size: 12),
              const SizedBox(width: 8),
            ],
            Flexible(
              child: Text(
                path ? goal.path ?? goalName(goal) : goalName(goal),
                style: goal.active
                    ? null
                    : TextStyle(color: Theme.of(context).hintColor),
              ),
            ),
          ],
        ),
      );

  Widget _goalPicker(BuildContext context) {
    if (_goals == null) {
      // Nowhere to list goals from: take an id.
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
    return _withGoals(context, (goals) {
      final ids = {for (final goal in goals) goal.id};
      final picked = [
        null,
        for (final goal in goals)
          if (goal.id != null) goal,
      ];
      return DropdownButton<String?>(
        isExpanded: true,
        // Tall enough for a long path, which wraps.
        itemHeight: null,
        value: ids.contains(_draft) ? _draft as String? : null,
        // The list shows the tree, by name; the pick, its whole path.
        items: [
          for (final goal in picked)
            DropdownMenuItem(
              value: goal?.id,
              child: goal == null ? const Text('(none)') : _goalLabel(goal),
            ),
        ],
        selectedItemBuilder: (context) => [
          for (final goal in picked)
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: goal == null
                  ? const Text('(none)')
                  : _goalLabel(goal, path: true),
            ),
        ],
        onChanged: (id) => setState(() => _draft = id),
      );
    });
  }

  /// Ticks for every active goal (and any inactive one already picked), in
  /// tree order; the goals are kept in the order they were ticked, so the
  /// first stays the primary goal.
  Widget _goalsPicker(BuildContext context) {
    final picked = _draft as List<String>;
    if (_goals == null) {
      // Nowhere to list goals from: take ids, separated by commas.
      return TextField(
        controller: _text,
        autofocus: true,
        decoration: const InputDecoration(
          isDense: true,
          border: OutlineInputBorder(),
          hintText: 'Goal ids, separated by commas',
        ),
        onChanged: (text) => _draft = [
          for (final id in text.split(','))
            if (id.trim().isNotEmpty) id.trim(),
        ],
      );
    }
    return _withGoals(context, (goals) {
      final shown = [
        for (final goal in goals)
          if (goal.id != null && (goal.active || picked.contains(goal.id)))
            goal,
      ];
      if (shown.isEmpty) return const Text('No active goals.');
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final goal in shown)
            CheckboxListTile(
              dense: true,
              contentPadding: EdgeInsetsDirectional.only(
                start: 16.0 * goal.depth,
              ),
              controlAffinity: ListTileControlAffinity.leading,
              value: picked.contains(goal.id),
              title: _goalLabel(goal, indent: false),
              subtitle: picked.isNotEmpty && picked.first == goal.id
                  ? const Text('Primary goal')
                  : null,
              onChanged: (on) => setState(() {
                picked.remove(goal.id);
                if (on == true) picked.add(goal.id!);
              }),
            ),
        ],
      );
    });
  }

  Future<void> _pickDay() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _draft as DateTime? ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked == null) return;
    setState(() => _draft = picked);
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
      case PropertyKind.goal:
        // Its name, once the goals are loaded.
        return _goalPaths[value] ?? '$value';
      case PropertyKind.lines when value is List:
        return value.join('\n');
      case PropertyKind.goals when value is List:
        if (value.isEmpty) return '(none)';
        return [for (final id in value) _goalNames[id] ?? '$id'].join(', ');
      case PropertyKind.choice:
        return widget.choices[key]?[value] ?? '$value';
      case PropertyKind.measure when value is Map:
        return describeMeasure(value.cast(), full: true, goalNames: _goalNames);
      case PropertyKind.date when value is String:
        return switch (DateTime.tryParse(value)) {
          final day? => MaterialLocalizations.of(context).formatMediumDate(day),
          null => value,
        };
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
