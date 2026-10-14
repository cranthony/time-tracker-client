import 'package:flutter/material.dart';

/// A row of a tree, as the Plan page's panes list their groups and what's
/// in them: [depth] groups in, indented a step a level, after its
/// [leading] icon -- a folder, for a group.
class TreeTile extends StatelessWidget {
  const TreeTile({
    super.key,
    this.depth = 0,
    required this.leading,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.onLongPress,
    this.end = 16,
  });

  final int depth;
  final Widget leading;
  final Widget title;
  final Widget? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  /// The room after it: less, to fit a menu button there.
  final double end;

  /// How far each level is indented.
  static const indent = 24.0;

  @override
  Widget build(BuildContext context) => ListTile(
    contentPadding: EdgeInsetsDirectional.only(
      start: 16 + indent * depth,
      end: end,
    ),
    leading: leading,
    title: title,
    subtitle: subtitle,
    trailing: trailing,
    onTap: onTap,
    onLongPress: onLongPress,
  );
}
