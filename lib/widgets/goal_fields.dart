import 'package:flutter/material.dart';

import '../models/goal.dart';
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
