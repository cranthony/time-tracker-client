import 'package:flutter/material.dart';

import '../models/goal.dart';
import 'day_picker.dart';
import 'durations.dart';
import 'goal_tile.dart' show DepthBars;

/// One of a goal's fields, laid out the same on its page and its edit
/// page, so the two read alike: [label] in a column of its own at the
/// left, and [child] beside it -- what it is, on its page; what sets it,
/// on the edit page. With [onTap], the whole row is tapped to change it,
/// a pencil at its end.
class GoalField extends StatelessWidget {
  const GoalField({
    super.key,
    required this.label,
    required this.child,
    this.onTap,
  });

  final String label;
  final Widget child;
  final VoidCallback? onTap;

  /// The labels' column's width.
  static const labelWidth = 100.0;

  @override
  Widget build(BuildContext context) {
    final row = Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: labelWidth,
            child: Padding(
              padding: const EdgeInsetsDirectional.only(top: 2, end: 8),
              child: Text(label, style: Theme.of(context).textTheme.labelLarge),
            ),
          ),
          Expanded(child: child),
          if (onTap != null)
            const Padding(
              padding: EdgeInsetsDirectional.only(start: 8),
              child: Icon(Icons.edit_outlined, size: 18),
            ),
        ],
      ),
    );
    return onTap == null ? row : InkWell(onTap: onTap, child: row);
  }
}

/// What a goal's field says with nothing in it, greyed: "None", say.
class GoalFieldEmpty extends StatelessWidget {
  const GoalFieldEmpty(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) =>
      Text(text, style: TextStyle(color: Theme.of(context).hintColor));
}

/// A goal page's title in its bar, its page's and its edit page's alike:
/// [title], with [path] -- the titles of the goals it's under, outermost
/// first -- beneath it, and a [DepthBars] line before it for each.
class GoalBarTitle extends StatelessWidget {
  const GoalBarTitle({super.key, required this.title, required this.path});

  final String title;
  final List<String> path;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      DepthBars(depth: path.length, height: 36),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(title, overflow: TextOverflow.ellipsis),
            if (path.isNotEmpty)
              Text(
                path.join(' › '),
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall,
              ),
          ],
        ),
      ),
    ],
  );
}

/// How a sub-goal's deadline follows its parent's, [minutes] before it:
/// "1w before “Ship the app” is due, moving with it".
String followsLabel(String parentTitle, int minutes) => minutes <= 0
    ? 'Due with “$parentTitle”, moving with it'
    : '${formatDays(Duration(minutes: minutes))} before “$parentTitle” '
          'is due, moving with it';

/// What [goal]'s deadline is measured from, when it's its start or
/// another goal's, its goals named from [tree]: "1w after it starts", "2d
/// after “Draft” is due"; null otherwise.
String? ruleLabel(Goal goal, GoalTree tree) {
  String after(Object? offset) => switch (offset) {
    {'days': final num d} when d == 0 => 'The day',
    {'days': final num d} => '${formatDays(Duration(days: d.toInt()))} after',
    {'minutes': final num m} when m == 0 => 'When',
    {'minutes': final num m} => '${formatMinutes(m.toInt())} after',
    _ => 'After',
  };
  return switch (goal.deadlineRule) {
    {'after_start': final offset} => '${after(offset)} it starts',
    {'after_goal': {'id': final String id} && final offset} =>
      '${after(offset)} “${tree[id] == null ? id : goalTitle(tree[id]!)}” is due',
    _ => null,
  };
}

/// Whether a sub-goal's parent, [parentTitle], needs it done.
String requiredLabel(String parentTitle, bool required) => required
    ? '“$parentTitle” needs it done to be done'
    : '“$parentTitle” can be done without it';

/// Where the priority of a goal under [parentId] (the top level, if null)
/// comes from, if it has none of its own: "inherited from “Health”", or
/// "the default".
String inheritedPriorityLabel(GoalTree tree, String? parentId) {
  final from = parentId == null
      ? null
      : [
          ...tree.ancestorsOf(parentId),
          ?tree[parentId],
        ].reversed.where((g) => g.priority != null).firstOrNull;
  return from == null ? 'the default' : 'inherited from “${goalTitle(from)}”';
}

/// Asks for a deadline, from [firstDate] to [lastDate], in a
/// [showDayTimePicker], so it can be given a time of day too: [deadline]'s
/// day, and its time if it has one, to start with -- or [initialDate],
/// without it. The deadline picked, or null if it's called off.
Future<String?> pickDeadline(
  BuildContext context, {
  String? deadline,
  required DateTime initialDate,
  required DateTime firstDate,
  required DateTime lastDate,
  String? helpText,
}) async {
  final at = deadlineEnd(deadline);
  final timed = at != null && deadlineHasTime(deadline);
  final picked = await showDayTimePicker(
    context,
    initialDate: switch (at) {
      null => initialDate,
      _ when timed => at,
      _ => at.subtract(const Duration(days: 1)),
    },
    initialTime: timed ? TimeOfDay.fromDateTime(at) : null,
    firstDate: firstDate,
    lastDate: lastDate,
    helpText: helpText,
  );
  return picked == null ? null : deadlineAt(picked);
}

/// [picked] as a deadline: the day, due at its end -- or at the time
/// picked on it.
String deadlineAt(DayAndTime picked) => switch (picked) {
  (:final day, time: null) => deadlineOf(day),
  (:final day, :final time?) => deadlineOf(
    DateTime(day.year, day.month, day.day, time.hour, time.minute),
    time: true,
  ),
};
