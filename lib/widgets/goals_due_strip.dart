import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/goal.dart';
import '../models/goal_activation.dart';
import 'goal_color.dart';
import 'goal_icon.dart';
import 'goal_tile.dart';
import 'hotkeys.dart';

/// The goals due on [day], from [goals] -- a closed one on the day it
/// closed instead, if that's sooner, so one done early shows when it was
/// done: by status -- active, inactive, done, missed, then obsolete --
/// then each status's as [byPriority] has them in [tree] (by default,
/// [goals] themselves): the highest priority first, then those due at a
/// time, by time, then those due by its end, by title.
List<Goal> goalsDueOn(Iterable<Goal> goals, DateTime day, [GoalTree? tree]) {
  final date = deadlineOf(day);
  return [
    for (final g in goals)
      if (_shownOn(g) == date) g,
  ]..sort(_byStatus(tree ?? GoalTree(goals)));
}

/// The day [goal] is among [goalsDueOn]'s: the day it's due or, if it's
/// closed, the day it closed, whichever is sooner. Null if it isn't due.
String? _shownOn(Goal goal) {
  final due = dueDay(goal);
  if (due == null) return null;
  final closed = switch (goal.closedAt) {
    final at? => deadlineOf(at.toLocal()),
    null => null,
  };
  return closed != null && closed.compareTo(due) < 0 ? closed : due;
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

/// The goals upcoming on [day], from [goals]: those active on it and due
/// after it. As of [day]: on one before [today], each as its history had
/// it at the day's end -- its status then, and the deadline in force --
/// so a past day shows what was coming up then; one that didn't exist yet
/// isn't among them. On today or a day ahead, too, each goal waiting to
/// be activated that's expected to have started by the day's end
/// ([expectedStart]) and not to be due before it -- with the deadline
/// it's expected to have, and when it's expected to start
/// ([Goal.expectedStart]); one due on the day is among them only if it's
/// the deadline it's expected to have, not one it has ([goalsDueOn] has
/// that). The highest priority first, as [GoalTree.priorityOf] has it in
/// [tree] (by default, [goals] themselves), then the soonest due
/// ([compareByDeadline]): at a time, not the user's own order.
List<Goal> upcomingGoalsOn(
  Iterable<Goal> goals,
  DateTime day, {
  DateTime? today,
  GoalTree? tree,
}) {
  final date = deadlineOf(day);
  final past = today != null && date.compareTo(deadlineOf(today)) < 0;
  final all = tree ?? GoalTree(goals);
  return [
    for (final g in goals)
      if (past ? _asOf(g, day) : g case final then?)
        if (then.active)
          if (dueDay(then) case final due? when due.compareTo(date) > 0) then,
    if (!past)
      for (final g in goals) ?_expected(g, all, day, today ?? day),
  ]..sort(_byPriorityThenDeadline(all));
}

/// [goal], waiting to be activated, as it's expected to be on [day] (as
/// of [now]): with the deadline it's expected to have, and when it's
/// expected to start -- if it's expected to have started by the day's
/// end and not to be due before it. Null otherwise.
Goal? _expected(Goal goal, GoalTree tree, DateTime day, DateTime now) {
  if (!goal.inactive || goal.activateWhen == null) return null;
  final start = expectedStart(goal, tree, now: now);
  if (start == null) return null;
  if (!start.isBefore(DateTime(day.year, day.month, day.day + 1))) return null;
  final due = expectedDeadline(goal, tree, now: now);
  final dueOn = due?.split('T').first;
  final date = deadlineOf(day);
  if (dueOn == null || dueOn.compareTo(date) < 0) return null;
  // Due on the day by a deadline of its own: the day's, not upcoming.
  if (goal.deadline != null && dueOn == date) return null;
  return Goal.fromJson({
    ...goal.toJson(),
    'deadline': due,
    'expected_start': deadlineOf(
      start,
      time: start.hour != 0 || start.minute != 0,
    ),
    'path': goal.path,
  });
}

/// The highest priority first, as [tree] has each, then the soonest due.
Comparator<Goal> _byPriorityThenDeadline(GoalTree tree) => (a, b) {
  final byPriority = tree.priorityOf(a.id).compareTo(tree.priorityOf(b.id));
  return byPriority != 0 ? byPriority : compareByDeadline(a, b);
};

/// [goal] as its history had it at the end of [day]: the status it had
/// then, with the deadline that change recorded, if it did. [goal] itself
/// if it has no history; null if it has none from by then.
Goal? _asOf(Goal goal, DateTime day) {
  if (goal.history.isEmpty) return goal;
  final end = DateTime(day.year, day.month, day.day + 1);
  final then = goal.history.where((c) => c.at.isBefore(end)).lastOrNull;
  if (then == null) return null;
  return Goal.fromJson({
    ...goal.toJson(),
    'status': then.status,
    'deadline': then.deadline ?? goal.deadline,
    'path': goal.path,
  });
}

/// How many upcoming goals get a pill each, in their order -- the highest
/// priority first, then the soonest due; the rest are counted on one
/// "+N later" pill.
const upcomingPills = 7;

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
/// day. Last, the [upcoming] ones -- active, due later -- just outlined,
/// each saying the day it's due (one only expected to have started by
/// then, waiting to be activated, in a dashed outline, with an hourglass,
/// saying when it's expected to start too): one each for the first
/// [upcomingPills], in [upcoming]'s order, then a "+N later" pill listing
/// the rest.
/// Tapping a pill calls [onTap]; holding an overdue one (or
/// right-clicking it) offers [OverdueGoalAction]s, each calling
/// [onOverdueAction] -- or nothing, if that's null. With [focus], keys
/// can go to a group's first pill ([GoalsStripFocus.focusFirst]), and
/// Tab and Shift+Tab go on from pill to pill, round all of them.
class GoalsDueStrip extends StatelessWidget {
  const GoalsDueStrip({
    super.key,
    required this.goals,
    required this.collapsed,
    required this.onCollapsed,
    this.missed = const [],
    this.overdue = const [],
    this.upcoming = const [],
    this.day,
    this.today,
    this.tree,
    this.spent,
    this.onTap,
    this.onOverdueAction,
    this.focus,
  });

  /// Where keys go into it, if they can.
  final GoalsStripFocus? focus;

  /// The day's, as [goalsDueOn] gives them.
  final List<Goal> goals;

  /// Those missed from the day, as [missedOn] gives them. One that's
  /// among [goals] too -- tried again by the same day -- is shown once,
  /// as due.
  final List<Goal> missed;

  /// The open ones due before the day, as [overdueGoalsOn] gives them.
  final List<Goal> overdue;

  /// The active ones due after the day, as [upcomingGoalsOn] gives them.
  final List<Goal> upcoming;

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

  /// [upcoming], split into the first [upcomingPills], with a pill each,
  /// and the rest.
  (List<Goal> soon, List<Goal> later) get _ahead => (
    upcoming.take(upcomingPills).toList(),
    upcoming.skip(upcomingPills).toList(),
  );

  @override
  Widget build(BuildContext context) {
    final late = _late;
    final ghosts = _ghosts;
    final (soon, later) = _ahead;
    if (goals.isEmpty && ghosts.isEmpty && late.isEmpty && upcoming.isEmpty) {
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
      if (upcoming.isNotEmpty) (upcoming.length, 'upcoming'),
    ];
    final counts = [
      for (final (i, (n, what)) in counted.indexed)
        '${i == 0 ? _count(n) : n} $what',
    ];
    _Pill pill(
      Goal g, {
      bool late = false,
      bool ghost = false,
      bool ahead = false,
    }) => _Pill(
      goal: g,
      path: tree?.pathOf(g.id) ?? g.path,
      color: colorOfGoal(g, tree: tree),
      dueDay: late ? _dueDayLabel(context, g) : null,
      upcomingDay: ahead ? _upcomingLabel(context, g) : null,
      startsOn: ahead && g.inactive && g.expectedStart != null
          ? startLabelShort(context, g.expectedStart!)
          : null,
      missed: ghost ? _missedNotes(context, g) : null,
      left: g.closed || ghost || spent == null
          ? null
          : leftLabel(g, spent![g.id]),
      onTap: onTap == null ? null : () => onTap!(g),
      onAction: late && onOverdueAction != null
          ? (action) => onOverdueAction!(g, action)
          : null,
    );
    final strip = Material(
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
                        '${[...goals, ...ghosts, ...late, ...soon].map(goalTitle).join(', ')}',
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
                              _group(
                                focus?.due,
                                Hotkey.dayGoals,
                                Wrap(
                                  spacing: 6,
                                  runSpacing: 6,
                                  children: [
                                    for (final g in goals) pill(g),
                                    for (final g in ghosts)
                                      pill(g, ghost: true),
                                  ],
                                ),
                              ),
                            if (late.isNotEmpty)
                              Padding(
                                padding: EdgeInsets.only(
                                  top: goals.isEmpty && ghosts.isEmpty ? 0 : 6,
                                ),
                                child: _group(
                                  focus?.overdue,
                                  Hotkey.overdueGoals,
                                  Wrap(
                                    spacing: 6,
                                    runSpacing: 6,
                                    crossAxisAlignment:
                                        WrapCrossAlignment.center,
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
                              ),
                            if (upcoming.isNotEmpty)
                              Padding(
                                padding: EdgeInsets.only(
                                  top:
                                      goals.isEmpty &&
                                          ghosts.isEmpty &&
                                          late.isEmpty
                                      ? 0
                                      : 6,
                                ),
                                child: _group(
                                  focus?.upcoming,
                                  Hotkey.upcomingGoals,
                                  Wrap(
                                    spacing: 6,
                                    runSpacing: 6,
                                    crossAxisAlignment:
                                        WrapCrossAlignment.center,
                                    children: [
                                      Text('Upcoming', style: muted),
                                      for (final g in soon)
                                        pill(g, ahead: true),
                                      if (later.isNotEmpty)
                                        _LaterPill(
                                          goals: later,
                                          label: (g) =>
                                              _upcomingLabel(context, g),
                                          onTap: onTap,
                                        ),
                                    ],
                                  ),
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
    final keys = focus;
    if (keys == null) return strip;
    return Focus(
      focusNode: keys.strip,
      onKeyEvent: (_, event) => keys._tab(event),
      child: strip,
    );
  }

  /// [child], a group of pills, under [node], for keys to find them by,
  /// with [hint] on it while Ctrl is held.
  static Widget _group(FocusNode? node, Hotkey hint, Widget child) =>
      node == null
      ? child
      : HotkeyHint(
          hint,
          child: Focus(focusNode: node, child: child),
        );

  static String _count(int n) => '$n goal${n == 1 ? '' : 's'}';

  /// The day [goal] was due, short: "Oct 17".
  static String _dueDayLabel(BuildContext context, Goal goal) {
    final due = goal.due!;
    final day = deadlineHasTime(goal.deadline)
        ? due
        : due.subtract(const Duration(days: 1));
    return MaterialLocalizations.of(context).formatShortMonthDay(day);
  }

  /// When [goal], upcoming, is due: "Oct 25", or "Oct 25, 9:00 AM" if at
  /// a time.
  static String _upcomingLabel(BuildContext context, Goal goal) =>
      '${_dueDayLabel(context, goal)}'
      '${deadlineHasTime(goal.deadline) ? ', ${_timeLabel(context, goal)}' : ''}';

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

/// [goal] as a pill, filled in its [color]: its title, its
/// time if it's due at one, and what's [left] of its expected time, or,
/// closed, greyed and struck through with what it came to, just outlined
/// in that color. Overdue -- [dueDay] given -- it's outlined in the error
/// color and says the day it was due instead of a time, and holding it
/// (or right-clicking it) offers the [OverdueGoalAction]s, if [onAction]
/// is given. [missed] given, it's a ghost of a goal missed from the day:
/// greyed and struck through like a closed one, saying those notes
/// instead of a time. Upcoming -- [upcomingDay] given -- it's just
/// outlined in its color, saying when it's due instead. Its
/// parents are in its tooltip.
class _Pill extends StatelessWidget {
  const _Pill({
    required this.goal,
    required this.path,
    required this.color,
    this.dueDay,
    this.upcomingDay,
    this.startsOn,
    this.missed,
    this.left,
    this.onTap,
    this.onAction,
  });

  final Goal goal;
  final List<String> path;

  /// The color it's filled, or outlined, in ([colorOfGoal]).
  final Color color;

  /// The day it was due, when it's overdue; null when it's the day's own.
  final String? dueDay;

  /// When it's due, when it's upcoming; null when it isn't.
  final String? upcomingDay;

  /// When it's expected to start, when it's upcoming only as expected --
  /// waiting to be activated; null when it isn't.
  final String? startsOn;

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
    final ahead = upcomingDay != null;
    final tint = color;
    final ink = closed
        ? colors.onSurfaceVariant
        : ahead
        ? colors.onSurface
        : Colors.black87;
    final time = !overdue && !ghost && !ahead && deadlineHasTime(goal.deadline)
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
      else if (startsOn != null)
        'due $upcomingDay, expected to start $startsOn'
      else if (ahead)
        'due $upcomingDay, upcoming'
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
        color: closed || ahead ? Colors.transparent : tint,
        shape: StadiumBorder(
          side: overdue
              ? BorderSide(color: colors.error, width: 2)
              : startsOn != null
              ? BorderSide.none
              : BorderSide(color: tint, width: ahead ? 2 : 1),
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
                if (startsOn != null) ...[
                  Icon(Icons.hourglass_top, size: 14, color: ink),
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
                        if (startsOn != null)
                          TextSpan(text: '  ·  starts $startsOn'),
                        if (ahead) TextSpan(text: '  ·  due $upcomingDay'),
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
    final drawn = startsOn == null
        ? pill
        : CustomPaint(foregroundPainter: _DashedStadium(tint), child: pill);
    return path.isEmpty
        ? drawn
        : Tooltip(message: [...path, title].join(' › '), child: drawn);
  }

  /// The [OverdueGoalAction]s, in a menu below the pill; the one picked
  /// goes to [onAction].
  Future<void> _showMenu(BuildContext context) async {
    final picked = await showMenu<OverdueGoalAction>(
      context: context,
      position: _below(context),
      items: [
        for (final action in OverdueGoalAction.values)
          PopupMenuItem(value: action, child: Text(action.label)),
      ],
    );
    if (picked != null) onAction?.call(picked);
  }
}

/// Where a menu below the widget at [context] goes.
RelativeRect _below(BuildContext context) {
  final box = context.findRenderObject()! as RenderBox;
  final overlay = Overlay.of(context).context.findRenderObject()! as RenderBox;
  final rect = Rect.fromPoints(
    box.localToGlobal(Offset.zero, ancestor: overlay),
    box.localToGlobal(box.size.bottomRight(Offset.zero), ancestor: overlay),
  );
  return RelativeRect.fromRect(rect, Offset.zero & overlay.size);
}

/// The upcoming [goals] due too far ahead for a pill each, as one
/// outlined pill counting them: "+3 later". Tapping it lists them, each
/// with when it's due as [label] says; picking one calls [onTap].
class _LaterPill extends StatelessWidget {
  const _LaterPill({required this.goals, required this.label, this.onTap});

  final List<Goal> goals;
  final String Function(Goal goal) label;
  final ValueChanged<Goal>? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final text = '+${goals.length} later';
    return Semantics(
      label: '${goals.length} more upcoming',
      button: true,
      excludeSemantics: true,
      child: Material(
        color: Colors.transparent,
        shape: StadiumBorder(side: BorderSide(color: colors.outline)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => _showList(context),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
            child: Text(
              text,
              style: theme.textTheme.labelMedium?.copyWith(
                color: colors.onSurfaceVariant,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _showList(BuildContext context) async {
    final picked = await showMenu<Goal>(
      context: context,
      position: _below(context),
      items: [
        for (final g in goals)
          PopupMenuItem(
            value: g,
            enabled: onTap != null,
            child: Text('${goalTitle(g)}  ·  due ${label(g)}'),
          ),
      ],
    );
    if (picked != null) onTap?.call(picked);
  }
}

/// When a goal waiting to be activated is expected to start, [at] as
/// [Goal.expectedStart] has it, short: "Nov 2", or "Nov 2, 9:00 AM".
String startLabelShort(BuildContext context, String at) {
  final start = startOf(at);
  if (start == null) return at;
  final strings = MaterialLocalizations.of(context);
  final day = strings.formatShortMonthDay(start);
  return at.contains('T')
      ? '$day, ${strings.formatTimeOfDay(TimeOfDay.fromDateTime(start))}'
      : day;
}

/// A stadium's outline in [color], dashed: a pill only expected to be.
class _DashedStadium extends CustomPainter {
  const _DashedStadium(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    final outline = Path()
      ..addRRect(
        RRect.fromRectAndRadius(
          (Offset.zero & size).deflate(1),
          Radius.circular(size.height / 2),
        ),
      );
    const dash = 5.0, gap = 3.0;
    for (final metric in outline.computeMetrics()) {
      for (var d = 0.0; d < metric.length; d += dash + gap) {
        canvas.drawPath(metric.extractPath(d, d + dash), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_DashedStadium old) => old.color != color;
}

/// Where keys go into a [GoalsDueStrip]: the whole of it ([strip]), and
/// each group of its pills -- the day's ([due]), the [overdue] and the
/// [upcoming] ones.
class GoalsStripFocus {
  GoalsStripFocus();

  final strip = FocusNode(
    debugLabel: 'Goals strip',
    canRequestFocus: false,
    skipTraversal: true,
  );
  final due = FocusNode(
    debugLabel: 'Goals due',
    canRequestFocus: false,
    skipTraversal: true,
  );
  final overdue = FocusNode(
    debugLabel: 'Goals overdue',
    canRequestFocus: false,
    skipTraversal: true,
  );
  final upcoming = FocusNode(
    debugLabel: 'Goals upcoming',
    canRequestFocus: false,
    skipTraversal: true,
  );

  /// Whether one of its pills has focus.
  bool get hasFocus => strip.hasFocus;

  /// Its pills, in order, round all three groups.
  List<FocusNode> get _pills => [
    for (final group in [due, overdue, upcoming]) ..._pillsIn(group),
  ];

  /// The pills in [group], in the order they're shown. Not the order of
  /// [FocusNode.traversalDescendants]: that's the order their nodes were
  /// attached in, so a pill rebuilt when the goals were re-sorted -- one
  /// that gained or lost a tooltip, say -- would come after the rest.
  static List<FocusNode> _pillsIn(FocusNode group) {
    final at = <BuildContext, int>{};
    void visit(Element e) {
      at[e] = at.length;
      e.visitChildren(visit);
    }

    group.context?.visitChildElements(visit);
    return [
      for (final node in group.traversalDescendants)
        if (node.canRequestFocus && !node.skipTraversal) node,
    ]..sort((a, b) => (at[a.context] ?? 0).compareTo(at[b.context] ?? 0));
  }

  /// Puts focus on the first pill in [group], scrolled into view:
  /// whether there was one.
  bool focusFirst(FocusNode group) {
    final first = _pillsIn(group).firstOrNull;
    if (first == null) return false;
    _focus(first);
    return true;
  }

  static void _focus(FocusNode node) {
    node.requestFocus();
    node.context?.findRenderObject()?.showOnScreen(
      duration: const Duration(milliseconds: 120),
      curve: Curves.easeOut,
    );
  }

  /// Tab, or Shift+Tab: the next pill, or the one before, round all of
  /// them -- not off out of the strip.
  KeyEventResult _tab(KeyEvent event) {
    if (event.logicalKey != LogicalKeyboardKey.tab) {
      return KeyEventResult.ignored;
    }
    if (event is KeyUpEvent) return KeyEventResult.ignored;
    final pills = _pills;
    final at = pills.indexOf(FocusManager.instance.primaryFocus!);
    if (at < 0) return KeyEventResult.ignored;
    final back = HardwareKeyboard.instance.isShiftPressed;
    _focus(pills[(at + (back ? -1 : 1)) % pills.length]);
    return KeyEventResult.handled;
  }

  void dispose() {
    strip.dispose();
    due.dispose();
    overdue.dispose();
    upcoming.dispose();
  }
}
