/// A recurring goal's sub-goal templates ([RecurringGoal.subGoals]), as
/// the server takes them: maps, each `{key, title, deadline?: {days |
/// minutes} before its goal's, activate_when?: {after: [{goal_closed:
/// another's key} | {before_parent: {days | minutes}}], delay?,
/// hold_while?}, required?, priority?, expected_minutes?, ...}`. These
/// read and change them as maps, so a field the app doesn't know is kept.
library;

/// The longest a sub-goal's key can be, as the server has it.
const maxSubGoalKeyLength = 40;

/// How many minutes an offset (`{days: 2}` or `{minutes: 150}`) is: none
/// for no offset.
int offsetMinutes(Object? offset) => switch (offset) {
  {'days': final num d} => (d * Duration.minutesPerDay).round(),
  {'minutes': final num m} => m.round(),
  _ => 0,
};

/// [minutes] as an offset, as the server takes one: days, if it's whole
/// days, else minutes.
Map<String, Object?> offsetOf(int minutes) =>
    minutes > 0 && minutes % Duration.minutesPerDay == 0
    ? {'days': minutes ~/ Duration.minutesPerDay}
    : {'minutes': minutes};

/// [sub]'s key, if it has one.
String? subGoalKey(Map sub) => switch (sub['key']) {
  final String key when key.isNotEmpty => key,
  _ => null,
};

/// [sub]'s title, or its key while it has none.
String subGoalTitle(Map sub) => switch (sub['title']) {
  final String title when title.trim().isNotEmpty => title,
  _ => subGoalKey(sub) ?? 'Untitled',
};

/// How long before its goal's deadline [sub] is due, in minutes: 0 if
/// it's due with it.
int dueBeforeMinutes(Map sub) => offsetMinutes(sub['deadline']);

/// How long before its goal's deadline [sub] waits for, in minutes, if it
/// waits for a time ([beforeParent]).
int? startsBeforeMinutes(Map sub) => switch (beforeParent(sub)) {
  final offset? => offsetMinutes(offset),
  null => null,
};

/// The time before its goal's deadline that [sub] waits for, if it waits
/// for one: its offset.
Map? beforeParent(Map sub) {
  for (final t in _after(sub)) {
    if (t case {'before_parent': final Map offset}) return offset;
  }
  return null;
}

/// The keys of the other sub-goals [sub] waits to close.
List<String> waitsForKeys(Map sub) => [
  for (final t in _after(sub))
    if (t case {'goal_closed': final String key}) key,
];

List<Object?> _after(Map sub) => switch (sub['activate_when']) {
  {'after': final List after} => after,
  _ => const [],
};

/// [subs] in the order they come due: the soonest due first, and of those
/// due together, the soonest to start -- as they're listed in the
/// template otherwise.
List<Map<String, Object?>> chainOrder(List<Map<String, Object?>> subs) {
  int starts(Map s) => startsBeforeMinutes(s) ?? -1;
  final indexed = [...subs.indexed]
    ..sort((a, b) {
      final due = dueBeforeMinutes(b.$2).compareTo(dueBeforeMinutes(a.$2));
      if (due != 0) return due;
      final start = starts(b.$2).compareTo(starts(a.$2));
      return start != 0 ? start : a.$1.compareTo(b.$1);
    });
  return [for (final (_, s) in indexed) s];
}

/// A key for a new sub-goal titled [title], unlike any of [taken]: its
/// words, lowercase, joined by "-" -- "buy-groceries" -- a number after
/// it if that's taken.
String newSubGoalKey(String title, Iterable<String> taken) {
  final words = title
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');
  var base = words.isEmpty ? 'step' : words;
  if (base.length > maxSubGoalKeyLength - 3) {
    base = base
        .substring(0, maxSubGoalKeyLength - 3)
        .replaceAll(RegExp(r'-+$'), '');
  }
  final keys = taken.toSet();
  if (!keys.contains(base)) return base;
  for (var n = 2; ; n++) {
    if (!keys.contains('$base-$n')) return '$base-$n';
  }
}

/// [subs] without the one at [index], and without what the others waited
/// for of it: one left waiting for nothing waits no longer.
List<Map<String, Object?>> withoutSubGoal(
  List<Map<String, Object?>> subs,
  int index,
) {
  final key = subGoalKey(subs[index]);
  return [
    for (final (i, s) in subs.indexed)
      if (i != index) _notWaitingFor(s, key),
  ];
}

Map<String, Object?> _notWaitingFor(Map<String, Object?> sub, String? key) {
  final when = sub['activate_when'];
  if (key == null || when is! Map || !waitsForKeys(sub).contains(key)) {
    return sub;
  }
  final after = [
    for (final t in _after(sub))
      if (t is! Map || t['goal_closed'] != key) t,
  ];
  final rest = {
    for (final MapEntry(:key, :value) in when.entries)
      if (key != 'after') key as String: value,
  };
  // A delay after nothing waits for nothing; a hold still holds it.
  final next = after.isNotEmpty
      ? {...rest, 'after': after}
      : {'hold_while': ?rest['hold_while']};
  return {
    for (final MapEntry(:key, :value) in sub.entries)
      if (key != 'activate_when') key: value,
    if (next.isNotEmpty) 'activate_when': next,
  };
}

/// What's wrong with [subs], a habit's chain, as the server would say,
/// before it's asked: a sub-goal with no title, two with one key, one
/// waiting for a sub-goal there isn't, a chain waiting for itself, or one
/// expected to take longer than its goal ([goalMinutes]).
List<String> chainProblems(
  List<Map<String, Object?>> subs, {
  int? goalMinutes,
}) {
  final problems = <String>[];
  final byKey = <String, Map>{};
  for (final s in subs) {
    final key = subGoalKey(s);
    if (key == null) continue;
    if (byKey.containsKey(key)) {
      problems.add('Two sub-goals are keyed “$key”.');
    }
    byKey[key] = s;
  }
  for (final s in subs) {
    if (s['title'] is! String || (s['title'] as String).trim().isEmpty) {
      problems.add('A sub-goal needs a title.');
    }
    for (final key in waitsForKeys(s)) {
      if (!byKey.containsKey(key)) {
        problems.add('“${subGoalTitle(s)}” waits for a sub-goal there isn’t.');
      }
    }
    if ((s['expected_minutes'] as num?)?.toInt() case final m?
        when goalMinutes != null && m > goalMinutes) {
      problems.add(
        '“${subGoalTitle(s)}” is expected to take longer than its goal.',
      );
    }
  }
  // A chain waiting for itself never starts.
  final looped = <String>{};
  for (final start in byKey.keys) {
    final seen = <String>{};
    final stack = [start];
    while (stack.isNotEmpty) {
      final at = stack.removeLast();
      for (final next in waitsForKeys(byKey[at] ?? const {})) {
        if (next == start) looped.add(start);
        if (seen.add(next)) stack.add(next);
      }
    }
  }
  if (looped.isNotEmpty) {
    problems.add(
      '${[for (final k in looped) '“${subGoalTitle(byKey[k]!)}”'].join(', ')} '
      'wait for each other, so none would start.',
    );
  }
  return problems;
}
