import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../models/goal.dart';
import '../models/measure.dart';
import '../services/mcp_client.dart';
import 'health.dart';
import 'measure_editor.dart';

/// Saves [changes] to [goal], returning every goal as they're to be shown
/// now.
typedef SaveGoal = Future<GoalList> Function(
  Goal goal,
  Map<String, Object?> changes,
);

/// The icon for each kind of measure, beside its name.
const _kindIcons = {
  'duration': Icons.timer_outlined,
  'count': Icons.tag,
  'time_constraint': Icons.schedule,
  'time_window': Icons.timelapse,
  'follow_through': Icons.handshake_outlined,
  'subjective': Icons.star_outline,
  'llm': Icons.auto_awesome_outlined,
  'rollup': Icons.account_tree_outlined,
};

/// What [goal] is rated by without a measure of its own.
String _average(Goal goal) => goal.isOverall
    ? "the average of the top-level goals' ratings"
    : "the average of the ratings of what's in it";

/// How [goal]'s health is rated: its measure in words and its settings,
/// with a button to edit it (or add one) when there's [onEdit].
/// [goalNames] names the goals a measure looks at.
class MeasureCard extends StatelessWidget {
  const MeasureCard({
    super.key,
    required this.goal,
    this.goalNames = const {},
    this.onEdit,
  });

  final Goal goal;
  final Map<String?, String> goalNames;
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text = theme.textTheme;
    final colors = theme.colorScheme;
    final measure = goal.measure;
    final kind = measure?['kind'] as String?;
    final muted = text.bodySmall?.copyWith(color: colors.onSurfaceVariant);
    return Card.filled(
      margin: EdgeInsets.zero,
      color: colors.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  _kindIcons[kind] ?? Icons.functions,
                  size: 18,
                  color: colors.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    measureKinds[kind] ??
                        (goal.isOverall
                            ? 'Average of the top-level goals'
                            : "Average of what's in it"),
                    style: text.labelLarge?.copyWith(color: colors.primary),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              measure == null
                  ? 'No measure of its own'
                  : describeMeasure(measure, full: true, goalNames: goalNames),
              style: text.titleLarge,
            ),
            const SizedBox(height: 4),
            Text(
              measure == null
                  ? "It's rated each day as ${_average(goal)}."
                  : measureKindHints[kind] ?? '',
              style: muted,
            ),
            if (measure != null) ...[
              const SizedBox(height: 12),
              for (final (label, value) in describeMeasureSettings(
                measure,
                goalNames: goalNames,
              ))
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 84,
                        child: Text(
                          label,
                          style: text.bodyMedium?.copyWith(
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                      ),
                      Expanded(child: Text(value, style: text.bodyMedium)),
                    ],
                  ),
                ),
            ],
            if (onEdit case final onEdit?) ...[
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton.tonalIcon(
                  onPressed: onEdit,
                  icon: Icon(measure == null ? Icons.add : Icons.edit),
                  label: Text(
                    measure == null ? 'Add a measure' : 'Edit measure',
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// [goal]'s latest rating and when it was, its last 8 days, how many days
/// have gone unrated, and its recent time, if its measure is of time or
/// events (or of its sub-goals', which are).
class HowItsDoing extends StatelessWidget {
  const HowItsDoing({super.key, required this.goal});

  final Goal goal;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text = theme.textTheme;
    final colors = theme.colorScheme;
    final health = goal.health;
    final kind = goal.measure?['kind'];
    final timed = const {'duration', 'count', 'rollup', null}.contains(kind);
    final time = switch ((goal.minutes24h, goal.minutes7d)) {
      (final int day, final int week) when timed => _time(day, week),
      _ => null,
    };
    Widget line(Widget leading, String label, {TextStyle? style}) => Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Row(
        children: [
          leading,
          const SizedBox(width: 10),
          Expanded(child: Text(label, style: style ?? text.bodyMedium)),
        ],
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text("How it's doing", style: text.titleSmall),
        if (!goal.active)
          line(
            Icon(Icons.pause_circle_outline, size: 18, color: theme.hintColor),
            'Only active actions are rated.',
          )
        else ...[
          line(HealthDot(rating: health), switch ((health, goal.healthPeriod)) {
            (null, _) => 'Not rated yet',
            (final rating?, final period?) =>
              '${_capitalized(healthBand(rating))} · last rated $period',
            (final rating?, null) => _capitalized(healthBand(rating)),
          }),
          if (goal.healthTrend.isNotEmpty)
            line(
              TrendSparkline(trend: goal.healthTrend),
              'Last 8 days',
              style: text.bodySmall?.copyWith(color: colors.onSurfaceVariant),
            ),
          if (goal.staleDays case final stale? when stale > 0)
            line(
              Icon(Icons.error_outline, size: 18, color: colors.error),
              '$stale day${stale == 1 ? '' : 's'} unrated',
              style: text.bodyMedium?.copyWith(color: colors.error),
            ),
        ],
        if (time != null)
          line(
            Icon(Icons.timelapse, size: 18, color: colors.onSurfaceVariant),
            time,
          ),
      ],
    );
  }

  static String _capitalized(String s) =>
      s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';

  /// "4h in 24h · 25h in 7d spent", or "None spent in 7d".
  static String _time(int day, int week) {
    String part(int minutes, String window) =>
        '${formatMinutes(minutes)} in $window';
    if (week == 0) return 'No time spent in 7d';
    return '${[if (day > 0) part(day, '24h'), part(week, '7d')].join(' · ')}'
        ' spent';
  }
}

/// Edits [goal]'s measure, or adds one, with a [MeasureEditor]: under it,
/// how the measure reads as it stands, or what's wrong with it. "Save"
/// saves it with [save] and returns what that returned (every goal, as
/// the server has them now); "Remove", asked first, clears it. Returns
/// null if nothing was saved. [goals] lists the goals it can look at.
Future<GoalList?> showEditMeasureDialog(
  BuildContext context,
  Goal goal, {
  required SaveGoal save,
  Future<List<Goal>> Function()? goals,
}) => showDialog<GoalList>(
  context: context,
  builder: (_) => _EditMeasureDialog(goal: goal, save: save, goals: goals),
);

class _EditMeasureDialog extends StatefulWidget {
  const _EditMeasureDialog({
    required this.goal,
    required this.save,
    required this.goals,
  });

  final Goal goal;
  final SaveGoal save;
  final Future<List<Goal>> Function()? goals;

  @override
  State<_EditMeasureDialog> createState() => _EditMeasureDialogState();
}

class _EditMeasureDialogState extends State<_EditMeasureDialog> {
  late Measure? _draft = widget.goal.measure;
  late final Future<List<Goal>>? _goals = widget.goals?.call();
  bool _saving = false;
  String? _error;

  Measure? get _original => widget.goal.measure;
  bool get _changed => !mapEquals(_draft, _original);

  Future<void> _save() async {
    if (_draft == null && !await _confirmRemove()) return;
    await _send(_draft);
  }

  Future<void> _remove() async {
    if (await _confirmRemove()) await _send(null);
  }

  Future<void> _send(Measure? measure) async {
    if (!mounted) return;
    final navigator = Navigator.of(context);
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      navigator.pop(await widget.save(widget.goal, {'measure': measure}));
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

  Future<bool> _confirmRemove() async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Remove the measure?'),
          content: Text(
            '${goalName(widget.goal)} will be rated by '
            '${_average(widget.goal)} instead. Its past ratings stay.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Keep it'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Remove'),
            ),
          ],
        ),
      ) ==
      true;

  Future<void> _confirmDiscard() async {
    final discard = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Discard changes?'),
        content: const Text('Closing now throws away the changed measure.'),
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
    final text = theme.textTheme;
    final colors = theme.colorScheme;
    final adding = _original == null;
    final draft = _draft;
    final problem = _error ?? (draft == null ? null : measureProblem(draft));
    final (background, foreground) = problem == null
        ? (colors.secondaryContainer, colors.onSecondaryContainer)
        : (colors.errorContainer, colors.onErrorContainer);
    return PopScope(
      canPop: !_changed && !_saving,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && !_saving) _confirmDiscard();
      },
      child: AlertDialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              adding ? 'Add a measure' : 'Edit measure',
              style: text.labelLarge?.copyWith(color: colors.primary),
            ),
            Text(goalName(widget.goal)),
          ],
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                MeasureEditor(
                  measure: draft,
                  goalId: widget.goal.id,
                  goals: _goals,
                  onChanged: (measure) => setState(() {
                    _draft = measure;
                    _error = null;
                  }),
                ),
                const SizedBox(height: 16),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: background,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        problem == null
                            ? Icons.visibility_outlined
                            : Icons.error_outline,
                        size: 18,
                        color: foreground,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          problem ??
                              switch (draft) {
                                final draft? =>
                                  'Reads as: '
                                      '${describeMeasure(draft, full: true)}',
                                null when adding => 'Pick a kind of measure.',
                                null =>
                                  "No measure: it's rated by "
                                      '${_average(widget.goal)}.',
                              },
                          style: text.bodyMedium?.copyWith(color: foreground),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          if (!adding)
            TextButton(
              onPressed: _saving ? null : _remove,
              style: TextButton.styleFrom(foregroundColor: colors.error),
              child: const Text('Remove'),
            ),
          TextButton(
            onPressed: _saving ? null : () => Navigator.of(context).maybePop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed:
                !_saving &&
                    _changed &&
                    (draft == null || measureProblem(draft) == null)
                ? _save
                : null,
            child: _saving
                ? const SizedBox.square(
                    dimension: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Save'),
          ),
        ],
      ),
    );
  }
}
