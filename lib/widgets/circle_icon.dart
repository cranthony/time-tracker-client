import 'package:flutter/material.dart';

import '../models/person.dart';

/// The icon for a circle of [kind], wherever one is shown: a plain
/// circle, a ring -- its people, drawn together; a community, three
/// people, [outlined] or filled.
IconData circleIcon(CircleKind kind, {bool outlined = false}) => switch (kind) {
  CircleKind.community => outlined ? Icons.groups_outlined : Icons.groups,
  CircleKind.circle => Icons.circle_outlined,
};

/// [circleIcon] for [circle]: a plain circle's, for one not known.
IconData circleIconOf(Circle? circle, {bool outlined = false}) =>
    circleIcon(circle?.kind ?? CircleKind.circle, outlined: outlined);
