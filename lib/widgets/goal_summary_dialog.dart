import 'package:flutter/material.dart';

import '../models/goal.dart';
import '../services/mcp_client.dart';
import 'color_picker.dart';
import 'measure_dialog.dart';
import 'priority_chip.dart';

/// The priorities offered as buttons; "…" takes any other.
const _priorities = [0, 1, 2, 3];

/// Shows [goal]: its priority, as a chip like the Events page's, over its
/// name; how it's rated (its measure) and how it's doing by it; and its
/// label's color. The priority and color each say whether they're set
/// on the goal or where they come from: an ancestor, or for a color, the
/// priority. The overall goal has neither.
///
/// Tapping the priority or the color opens it for editing, in place; one
/// set on the goal can be cleared, so it's inherited again. "Save" sends
/// every change with [save]. Without [save], or for a goal with no id,
/// nothing can be edited. "Edit measure" (offered while nothing else is
/// changed), "History" and "Details" close it, then call
/// [onEditMeasure], [onHistory] or [onDetails] with the goal. [goals] are
/// the goals listed, to say which ancestor each inherited value comes
/// from; [goalNames] names the goals a measure looks at.
Future<void> showGoalSummaryDialog(
  BuildContext context,
  Goal goal, {
  List<Goal> goals = const [],
  Map<String?, String> goalNames = const {},
  SaveGoal? save,
  ValueChanged<Goal>? onEditMeasure,
  ValueChanged<Goal>? onHistory,
  ValueChanged<Goal>? onDetails,
}) => showDialog<void>(
  context: context,
  builder: (_) => _GoalSummaryDialog(
    goal: goal,
    goals: goals,
    goalNames: goalNames,
    save: save == null || goal.id == null ? null : save,
    onEditMeasure: onEditMeasure,
    onHistory: onHistory,
    onDetails: onDetails,
  ),
);

/// The properties the dialog edits, as `update_goal` names them.
enum _Property { priority, color }

class _GoalSummaryDialog extends StatefulWidget {
  const _GoalSummaryDialog({
    required this.goal,
    required this.goals,
    required this.goalNames,
    required this.save,
    required this.onEditMeasure,
    required this.onHistory,
    required this.onDetails,
  });

  final Goal goal;
  final List<Goal> goals;
  final Map<String?, String> goalNames;
  final SaveGoal? save;
  final ValueChanged<Goal>? onEditMeasure;
  final ValueChanged<Goal>? onHistory;
  final ValueChanged<Goal>? onDetails;

  @override
  State<_GoalSummaryDialog> createState() => _GoalSummaryDialogState();
}

class _GoalSummaryDialogState extends State<_GoalSummaryDialog> {
  /// What's been changed, keyed as `update_goal` takes it; null clears.
  final _changes = <String, Object?>{};

  /// The property open for editing, if one is.
  _Property? _editing;

  /// Whether "…" was picked, to type a priority not among [_priorities].
  bool _otherPriority = false;
  late final _otherController = TextEditingController(
    text: switch (widget.goal.priority) {
      final p? when !_priorities.contains(p) => '$p',
      _ => '',
    },
  );

  bool _saving = false;
  String? _error;

  Goal get _goal => widget.goal;
  bool get _editable => widget.save != null;

  @override
  void dispose() {
    _otherController.dispose();
    super.dispose();
  }

  /// [key]'s value as it'll be saved: changed, or as it was.
  Object? _value(String key, Object? was) =>
      _changes.containsKey(key) ? _changes[key] : was;

  int? get _priority => _value('priority', _goal.priority) as int?;
  String? get _color =>
      _value('background_color', _goal.backgroundColor) as String?;

  /// Sets [key] to [value], dropping the change if that's how it was.
  void _set(String key, Object? value, Object? was) => setState(() {
    if (value == was) {
      _changes.remove(key);
    } else {
      _changes[key] = value;
    }
  });

  /// The listed goal with [id], if it's listed.
  Goal? _byId(String? id) =>
      id == null ? null : widget.goals.where((g) => g.id == id).firstOrNull;

  /// Its ancestors, nearest first, as far as they're listed.
  late final List<Goal> _ancestors = () {
    final chain = <Goal>[];
    var parent = _byId(_goal.parentId);
    while (parent != null && !chain.contains(parent)) {
      chain.add(parent);
      parent = _byId(parent.parentId);
    }
    return chain;
  }();

  /// The nearest ancestor for which [has] is true, if one is listed.
  Goal? _nearest(bool Function(Goal) has) => _ancestors.where(has).firstOrNull;

  /// What it inherits for priority: its parent's, if it's listed;
  /// otherwise what the server said, if that was inherited.
  int? get _inheritedPriority => switch (_byId(_goal.parentId)) {
    final parent? => parent.effectivePriority,
    null => _goal.inheritsPriority ? _goal.effectivePriority : null,
  };

  /// "Inherited from Cooking", naming the nearest ancestor for which
  /// [has] is true, if it's listed.
  String _inheritedFrom(bool Function(Goal) has) => switch (_nearest(has)) {
    final from? => 'Inherited from ${goalName(from)}',
    null => 'Inherited',
  };

  Future<void> _save() async {
    final navigator = Navigator.of(context);
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.save!(_goal, Map.of(_changes));
      navigator.pop();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = switch (e) {
          SignInRequiredException() =>
            'You were signed out. Sign in again from the Goals page, then '
                'try again.',
          McpException(:final message) => message,
          _ => '$e',
        };
      });
    }
  }

  void _toggle(_Property property) =>
      setState(() => _editing = _editing == property ? null : property);

  /// Closes it, then calls [then] with the goal.
  void _leaveFor(ValueChanged<Goal> then) {
    Navigator.of(context).pop();
    then(_goal);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text = theme.textTheme;
    final colors = theme.colorScheme;
    final changed = _changes.isNotEmpty;
    // The overall goal gives its events nothing.
    final events = !_goal.isOverall;
    return AlertDialog(
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (events) _priorityHeader(),
          Text(goalName(_goal)),
          if (_goal.path case final path? when path.contains(' › '))
            Text(
              path,
              style: text.bodySmall?.copyWith(color: colors.onSurfaceVariant),
            ),
        ],
      ),
      contentPadding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      content: SizedBox(
        width: 400,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_editing == _Property.priority)
                Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    border: Border.all(color: colors.primary, width: 1.5),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: _priorityEditor(_priority, _inheritedPriority),
                ),
              MeasureCard(
                goal: _goal,
                goalNames: widget.goalNames,
                // Not while other changes wait to be saved, which leaving
                // for the measure's editor would throw away.
                onEdit: switch (widget.onEditMeasure) {
                  final edit? when _editable && !changed => () => _leaveFor(
                    edit,
                  ),
                  _ => null,
                },
              ),
              const SizedBox(height: 20),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: HowItsDoing(goal: _goal),
              ),
              if (events) ...[
                const SizedBox(height: 16),
                _colorRow(),
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 0, 4, 0),
                  child: Text(
                    'Its events, and sub-goals with nothing set, take its '
                    'priority and color.',
                    style: text.bodySmall?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
              if (_error case final error?)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(error, style: TextStyle(color: colors.error)),
                ),
            ],
          ),
        ),
      ),
      actions: changed
          ? [
              TextButton(
                onPressed: _saving ? null : () => Navigator.of(context).pop(),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: _saving ? null : _save,
                child: const Text('Save'),
              ),
            ]
          : [
              if (widget.onHistory case final onHistory?)
                TextButton(
                  onPressed: () => _leaveFor(onHistory),
                  child: const Text('History'),
                ),
              if (widget.onDetails case final onDetails?)
                TextButton(
                  onPressed: () => _leaveFor(onDetails),
                  child: const Text('Details'),
                ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Close'),
              ),
            ],
    );
  }

  /// Its priority's chip, and where it comes from; tapped, it opens for
  /// editing.
  Widget _priorityHeader() {
    final theme = Theme.of(context);
    final own = _priority;
    final inherited = _inheritedPriority;
    final source = switch ((own, inherited)) {
      (_?, _) => 'Set on this goal',
      (null, _?) => _inheritedFrom((g) => g.priority != null),
      (null, null) => 'Not set here or above',
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Tooltip(
            message: 'Priority',
            child: InkWell(
              onTap: _editable ? () => _toggle(_Property.priority) : null,
              borderRadius: BorderRadius.circular(6),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: PriorityChip(
                  priority: own ?? inherited,
                  own: own != null,
                  label: own == null && inherited == null
                      ? 'No priority'
                      : null,
                  large: true,
                ),
              ),
            ),
          ),
          if (_changes.containsKey('priority'))
            Padding(
              padding: const EdgeInsetsDirectional.only(start: 6),
              child: Tooltip(
                message: 'Changed',
                child: Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.tertiary,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              source,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _priorityEditor(int? own, int? inherited) {
    final text = Theme.of(context).textTheme;
    final colors = Theme.of(context).colorScheme;
    final other = _otherPriority || (own != null && !_priorities.contains(own));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            for (final p in _priorities)
              ChoiceChip(
                showCheckmark: false,
                label: Text('P$p'),
                selected: own == p && !other,
                onSelected: (_) {
                  _otherPriority = false;
                  _set('priority', p, _goal.priority);
                },
              ),
            ChoiceChip(
              showCheckmark: false,
              label: const Text('…'),
              tooltip: 'Another priority',
              selected: other,
              onSelected: (_) => setState(() => _otherPriority = true),
            ),
          ],
        ),
        if (other)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: TextField(
              controller: _otherController,
              autofocus: _otherController.text.isEmpty,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Priority',
                isDense: true,
              ),
              onChanged: (typed) {
                if (int.tryParse(typed.trim()) case final p?) {
                  _set('priority', p, _goal.priority);
                }
              },
            ),
          ),
        TextButton.icon(
          onPressed: own == null
              ? null
              : () {
                  _otherPriority = false;
                  _otherController.clear();
                  _set('priority', null, _goal.priority);
                },
          icon: const Icon(Icons.undo, size: 18),
          label: Text(switch (inherited) {
            final p? =>
              _nearest((g) => g.priority != null) == null
                  ? 'Inherit ($p)'
                  : 'Inherit from '
                        '${goalName(_nearest((g) => g.priority != null)!)} ($p)',
            null => 'No priority of its own',
          }),
        ),
        Text(
          '0 is the most important. Its events, and sub-goals with no '
          'priority of their own, take this one.',
          style: text.bodySmall?.copyWith(color: colors.onSurfaceVariant),
        ),
      ],
    );
  }

  Widget _colorRow() {
    final own = parseColor(_color);
    final ancestor = _nearest((g) => parseColor(g.backgroundColor) != null);
    final unchanged =
        !_changes.containsKey('background_color') &&
        !_changes.containsKey('priority');
    final shown =
        own ??
        parseColor(ancestor?.backgroundColor) ??
        (unchanged ? parseColor(_goal.effectiveColor) : null) ??
        priorityColor(_priority ?? _inheritedPriority);
    final follows = _priority ?? _inheritedPriority ?? defaultPriority;
    return _PropertyCard(
      icon: _Swatch(color: shown, inherited: own == null),
      label: 'Color',
      value: colorToHex(shown),
      source: switch ((own, ancestor)) {
        (_?, _) => 'Set on this goal',
        (null, final from?) => 'Inherited from ${goalName(from)}',
        (null, null) =>
          '${unchanged ? 'Follows' : 'Will follow'} priority $follows',
      },
      own: own != null,
      editing: _editing == _Property.color,
      onTap: _editable ? () => _toggle(_Property.color) : null,
      onClear: _editable && own != null
          ? () => _set('background_color', null, _goal.backgroundColor)
          : null,
      editor: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ColorPicker(
            color: own,
            onChanged: (color) => _set(
              'background_color',
              color == null ? null : colorToHex(color),
              _goal.backgroundColor,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            ancestor == null
                ? 'With no color, it takes its priority\'s.'
                : 'With no color, it takes ${goalName(ancestor)}\'s.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

/// One property: its icon, label, value and where the value comes from,
/// with "Set" (to edit it) or "Clear" (to inherit it again); while
/// [editing], [editor] under it.
class _PropertyCard extends StatelessWidget {
  const _PropertyCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.source,
    required this.own,
    required this.editing,
    required this.onTap,
    required this.onClear,
    required this.editor,
  });

  final Widget icon;
  final String label;
  final String value;
  final String source;

  /// Whether it's set on the goal itself, so it can be cleared.
  final bool own;
  final bool editing;
  final VoidCallback? onTap;
  final VoidCallback? onClear;
  final Widget editor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text = theme.textTheme;
    final colors = theme.colorScheme;
    final muted = text.bodySmall?.copyWith(color: colors.onSurfaceVariant);
    return Card.outlined(
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: editing ? colors.primary : colors.outlineVariant,
          width: editing ? 1.5 : 1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
              child: Row(
                children: [
                  IconTheme.merge(
                    data: IconThemeData(
                      size: 22,
                      color: editing ? colors.primary : colors.onSurfaceVariant,
                    ),
                    child: icon,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(label, style: muted),
                        Text(value, style: text.titleMedium),
                        Text(source, style: muted),
                      ],
                    ),
                  ),
                  if (!editing && onTap != null)
                    own && onClear != null
                        ? TextButton(
                            onPressed: onClear,
                            child: const Text('Clear'),
                          )
                        : TextButton(
                            onPressed: onTap,
                            child: const Text('Set'),
                          ),
                ],
              ),
            ),
          ),
          if (editing)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: editor,
            ),
        ],
      ),
    );
  }
}

/// A round swatch of [color]: a ring of it if [inherited], so it reads as
/// not the goal's own, as the Goals page's outlined flag does.
class _Swatch extends StatelessWidget {
  const _Swatch({required this.color, required this.inherited});

  final Color color;
  final bool inherited;

  @override
  Widget build(BuildContext context) => inherited
      ? Container(
          width: 22,
          height: 22,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: color, width: 4),
          ),
        )
      : ColorDot(color: color, size: 22);
}
