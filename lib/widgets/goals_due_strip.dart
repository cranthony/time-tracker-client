import 'package:flutter/material.dart';

import '../models/goal.dart';
import 'color_picker.dart';
import 'goal_icon.dart';
import 'goal_tile.dart';

/// The goals due on [day], from [goals]: by status -- active, inactive,
/// done, missed, then obsolete -- then each status's as [byPriority] has
/// them in [tree] (by default, [goals] themselves): the highest priority
/// first, then those due at a time, by time, then those due by its end,
/// by title.
List<Goal> goalsDueOn(Iterable<Goal> goals, DateTime day, [GoalTree? tree]) {
  final date = deadlineOf(day);
  return [
    for (final g in goals)
      if (g.deadline?.trim().split('T').first == date && g.due != null) g,
  ]..sort(_byStatus(tree ?? GoalTree(goals)));
}

/// The goals overdue on [day], from [goals]: the open ones -- active or
/// inactive -- due before it and, if [today] is given, before [today]
/// too, so a day ahead doesn't call overdue what isn't due yet. In the
/// order [goalsDueOn] gives: active ones first, then each status's as
/// [byPriority] has them in [tree] (by default, [goals] themselves), so,
/// at a priority, the longest overdue first.
List<Goal> overdueGoalsOn(
  Iterable<Goal> goals,
  DateTime day, {
  DateTime? today,
  GoalTree? tree,
}) {
  final date = [
    deadlineOf(day),
    if (today != null) deadlineOf(today),
  ].reduce((a, b) => a.compareTo(b) <= 0 ? a : b);
  return [
    for (final g in goals)
      if (g.open)
        if (dueDay(g) case final due? when due.compareTo(date) < 0) g,
  ]..sort(_byStatus(tree ?? GoalTree(goals)));
}

/// The goals missed from [day], from [goals]: each with a miss in its
/// history ([Goal.misses]) whose deadline fell on [day] -- whether it was
/// tried again since, and is open or closed now, or stayed missed. In the
/// order [goalsDueOn] gives.
List<Goal> missedOn(Iterable<Goal> goals, DateTime day, [GoalTree? tree]) {
  final date = deadlineOf(day);
  return [
    for (final g in goals)
      if (g.misses.any((m) => m.deadline?.trim().split('T').first == date)) g,
  ]..sort(_byStatus(tree ?? GoalTree(goals)));
}

/// Orders goals by status, then as [order] compares them.
Comparator<Goal> _byStatus(GoalTree order) => (a, b) {
  final byStatus = _rank(a).compareTo(_rank(b));
  return byStatus != 0 ? byStatus : order.compare(a, b);
};

const _statusOrder = ['active', 'inactive', 'done', 'missed', 'obsolete'];

/// Where [goal]'s status falls in [_statusOrder]; one it doesn't know,
/// after them.
int _rank(Goal goal) => switch (_statusOrder.indexOf(goal.status)) {
  -1 => _statusOrder.length,
  final i => i,
};

/// What a long-press (or, with a mouse, a right-click) on an overdue
/// goal's pill offers: what its page offers an overdue goal.
enum OverdueGoalAction {
  done('Mark done'),
  missed('Mark missed'),
  retry('Missed, try again…');

  const OverdueGoalAction(this.label);

  final String label;
}

/// The goals due on the day shown, above its timeline, so they're in
/// sight wherever it's scrolled to: a pill each, or, [collapsed], one
/// line naming them. An open one with an expected time says what's left
/// of it ([leftLabel]); one that's closed says so: done, missed or
/// obsolete. After them, a greyed pill for each goal [missed] from the
/// day -- struck through, saying so, and by when it's being tried again
/// if it's open. Then the [overdue] ones -- still open past their day --
/// each saying the day it was due, so they stay in sight until they're
/// done or retargeted; only on today, though, not on a past or future
/// day. Tapping a pill calls [onTap]; holding an overdue one (or
/// right-clicking it) offers [OverdueGoalAction]s, each calling
/// [onOverdueAction] -- or nothing, if that's null.
class GoalsDueStrip extends StatelessWidget {
  const GoalsDueStrip({
    super.key,
    required this.goals,
    required this.collapsed,
    required this.onCollapsed,
    this.missed = const [],
    this.overdue = const [],
    this.day,
    this.today,
    this.tree,
    this.spent,
    this.onTap,
    this.onOverdueAction,
  });

  /// The day's, as [goalsDueOn] gives them.
  final List<Goal> goals;

  /// Those missed from the day, as [missedOn] gives them. One that's
  /// among [goals] too -- tried again by the same day -- is shown once,
  /// as due.
  final List<Goal> missed;

  /// The open ones due before the day, as [overdueGoalsOn] gives them.
  final List<Goal> overdue;

  /// The day shown and today, for whether [overdue] is shown: only on
  /// today. Shown whenever either is unknown.
  final DateTime? day;
  final DateTime? today;
  final bool collapsed;
  final ValueChanged<bool> onCollapsed;

  /// Every goal, for each one's parents; none, if null.
  final GoalTree? tree;

  /// The time spent toward each goal, by id, for what's left of each
  /// one's expected time; none is said, if null.
  final Map<String, Duration>? spent;
  final ValueChanged<Goal>? onTap;

  /// What an [OverdueGoalAction] picked for an overdue goal does; none
  /// are offered, if null.
  final void Function(Goal goal, OverdueGoalAction action)? onOverdueAction;

  /// [overdue], on today; nothing on a past or future day.
  List<Goal> get _late => switch ((day, today)) {
    (final d?, final t?) when deadlineOf(d) != deadlineOf(t) => const [],
    _ => overdue,
  };

  /// [missed], less any shown as due.
  List<Goal> get _ghosts => [
    for (final g in missed)
      if (!goals.any((d) => d.id == g.id)) g,
  ];

  @override
  Widget build(BuildContext context) {
    final late = _late;
    final ghosts = _ghosts;
    if (goals.isEmpty && ghosts.isEmpty && late.isEmpty) {
      return const SizedBox.shrink();
    }
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final muted = theme.textTheme.labelMedium?.copyWith(
      color: colors.onSurfaceVariant,
    );
    final open = goals.where((g) => g.open).length;
    final toggle = IconButton(
      visualDensity: VisualDensity.compact,
      tooltip: collapsed ? 'Show goals due' : 'Hide goals due',
      icon: Icon(collapsed ? Icons.expand_more : Icons.expand_less),
      onPressed: () => onCollapsed(!collapsed),
    );
    final counted = [
      if (goals.isNotEmpty)
        (goals.length, 'due${open < goals.length ? ' ($open open)' : ''}'),
      if (ghosts.isNotEmpty) (ghosts.length, 'missed'),
      if (late.isNotEmpty) (late.length, 'overdue'),
    ];
    final counts = [
      for (final (i, (n, what)) in counted.indexed)
        '${i == 0 ? _count(n) : n} $what',
    ];
    _Pill pill(Goal g, {bool late = false, bool ghost = false}) => _Pill(
      goal: g,
      path: tree?.pathOf(g.id) ?? g.path,
      priority: tree?.priorityOf(g.id) ?? g.priority ?? defaultGoalPriority,
      dueDay: late ? _dueDayLabel(context, g) : null,
      missed: ghost ? _missedNotes(context, g) : null,
      left: g.closed || ghost || spent == null
          ? null
          : leftLabel(g, spent![g.id]),
      onTap: onTap == null ? null : () => onTap!(g),
      onAction: late && onOverdueAction != null
          ? (action) => onOverdueAction!(g, action)
          : null,
    );
    return Material(
      color: colors.surfaceContainerLow,
      shape: Border(bottom: BorderSide(color: colors.outlineVariant)),
      child: InkWell(
        onTap: collapsed ? () => onCollapsed(false) : null,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 2, 4, 2),
          child: collapsed
              ? Row(
                  children: [
                    GoalIcon(size: 16, color: colors.primary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '${counts.join(', ')} · '
                        '${[...goals, ...ghosts, ...late].map(goalTitle).join(', ')}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: muted,
                      ),
                    ),
                    toggle,
                  ],
                )
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 12, right: 8),
                      child: GoalIcon(size: 16, color: colors.primary),
                    ),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (goals.isNotEmpty || ghosts.isNotEmpty)
                              Wrap(
                                spacing: 6,
                                runSpacing: 6,
                                children: [
                                  for (final g in goals) pill(g),
                                  for (final g in ghosts) pill(g, ghost: true),
                                ],
                              ),
                            if (late.isNotEmpty)
                              Padding(
                                padding: EdgeInsets.only(
                                  top: goals.isEmpty && ghosts.isEmpty ? 0 : 6,
                                ),
                                child: Wrap(
                                  spacing: 6,
                                  runSpacing: 6,
                                  crossAxisAlignment: WrapCrossAlignment.center,
                                  children: [
                                    Text(
                                      'Overdue',
                                      style: theme.textTheme.labelSmall
                                          ?.copyWith(color: colors.error),
                                    ),
                                    for (final g in late) pill(g, late: true),
                                  ],
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                    toggle,
                  ],
                ),
        ),
      ),
    );
  }

  static String _count(int n) => '$n goal${n == 1 ? '' : 's'}';

  /// The day [goal] was due, short: "Oct 17".
  static String _dueDayLabel(BuildContext context, Goal goal) {
    final due = goal.due!;
    final day = deadlineHasTime(goal.deadline)
        ? due
        : due.subtract(const Duration(days: 1));
    return MaterialLocalizations.of(context).formatShortMonthDay(day);
  }

  /// What a ghost of [goal], missed from the day, says after its title:
  /// that it was missed, and, if it's open, by when it's being tried
  /// again: "Oct 25", or "Oct 25, 9:00 AM" if at a time.
  static List<String> _missedNotes(BuildContext context, Goal goal) => [
    'missed',
    if (goal.open && goal.due != null)
      'tried again by ${_dueDayLabel(context, goal)}'
          '${deadlineHasTime(goal.deadline) ? ', ${_timeLabel(context, goal)}' : ''}',
  ];

  static String _timeLabel(BuildContext context, Goal goal) =>
      MaterialLocalizations.of(context)
          .formatTimeOfDay(TimeOfDay.fromDateTime(goal.due!));
}

/// [goal] as a pill, filled in its [priority]'s color: its title, its
/// time if it's due at one, and what's [left] of its expected time, or,
/// closed, greyed and struck through with what it came to, just outlined
/// in that color. Overdue -- [dueDay] given -- it's outlined in the error
/// color and says the day it was due instead of a time, and holding it
/// (or right-clicking it) offers the [OverdueGoalAction]s, if [onAction]
/// is given. [missed] given, it's a ghost of a goal missed from the day:
/// greyed and struck through like a closed one, saying those notes
/// instead of a time. Its parents are in its tooltip.
class _Pill extends StatelessWidget {
  const _Pill({
    required this.goal,
    required this.path,
    required this.priority,
    this.dueDay,
    this.missed,
    this.left,
    this.onTap,
    this.onAction,
  });

  final Goal goal;
  final List<String> path;

  /// The priority that applies to it ([GoalTree.priorityOf]).
  final int priority;

  /// The day it was due, when it's overdue; null when it's the day's own.
  final String? dueDay;

  /// What it says as a ghost of a miss from the day; null when it isn't.
  final List<String>? missed;
  final String? left;
  final VoidCallback? onTap;
  final ValueChanged<OverdueGoalAction>? onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final ghost = missed != null;
    final closed = goal.closed || ghost;
    final done = !ghost && goal.status == 'done';
    final overdue = dueDay != null;
    final tint = priorityColor(priority);
    final ink = closed ? colors.onSurfaceVariant : Colors.black87;
    final time = !overdue && !ghost && deadlineHasTime(goal.deadline)
        ? MaterialLocalizations.of(context)
              .formatTimeOfDay(TimeOfDay.fromDateTime(goal.due!))
        : null;
    final title = goalTitle(goal);
    final status = closed && !ghost
        ? goalStatuses[goal.status]!.toLowerCase()
        : null;
    final label = [
      title,
      if (ghost)
        'missed that day'
      else if (overdue)
        'due $dueDay, overdue'
      else if (time != null)
        'due at $time'
      else
        'due by the end of the day',
      ...?missed?.skip(1),
      ?left,
      ?status,
    ].join(', ');
    final menu = onAction == null ? null : () => _showMenu(context);
    final pill = Semantics(
      label: label,
      button: onTap != null,
      onLongPress: menu,
      onLongPressHint: menu == null ? null : 'Mark done or missed',
      excludeSemantics: true,
      child: Material(
        color: closed ? Colors.transparent : tint,
        shape: StadiumBorder(
          side: overdue
              ? BorderSide(color: colors.error, width: 2)
              : BorderSide(color: tint),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          onLongPress: menu,
          onSecondaryTap: menu,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (closed) ...[
                  Icon(done ? Icons.check : Icons.close, size: 14, color: ink),
                  const SizedBox(width: 4),
                ],
                Flexible(
                  child: Text.rich(
                    TextSpan(
                      children: [
                        if (time != null) TextSpan(text: '$time  '),
                        TextSpan(
                          text: title,
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            decoration: closed
                                ? TextDecoration.lineThrough
                                : null,
                          ),
                        ),
                        if (overdue) TextSpan(text: '  ·  due $dueDay'),
                        for (final note in missed ?? const <String>[])
                          TextSpan(text: '  ·  $note'),
                        if (left != null) TextSpan(text: '  ·  $left'),
                      ],
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelMedium?.copyWith(color: ink),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    return path.isEmpty
        ? pill
        : Tooltip(message: [...path, title].join(' › '), child: pill);
  }

  /// The [OverdueGoalAction]s, in a menu below the pill; the one picked
  /// goes to [onAction].
  Future<void> _showMenu(BuildContext context) async {
    final box = context.findRenderObject()! as RenderBox;
    final overlay =
        Overlay.of(context).context.findRenderObject()! as RenderBox;
    final rect = Rect.fromPoints(
      box.localToGlobal(Offset.zero, ancestor: overlay),
      box.localToGlobal(box.size.bottomRight(Offset.zero), ancestor: overlay),
    );
    final picked = await showMenu<OverdueGoalAction>(
      context: context,
      position: RelativeRect.fromRect(rect, Offset.zero & overlay.size),
      items: [
        for (final action in OverdueGoalAction.values)
          PopupMenuItem(value: action, child: Text(action.label)),
      ],
    );
    if (picked != null) onAction?.call(picked);
  }
}
