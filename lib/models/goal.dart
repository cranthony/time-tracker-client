import 'event.dart';
import 'note.dart';
import 'share.dart';

export 'share.dart';

/// A goal of the user's, mirroring the Time Tracker MCP server's
/// `ListedGoal`: an outcome they mean to reach and can mark done --
/// shipping the Goals pane, say. (Something with no "done", like working
/// 40 hours a week, is a habit.) A goal can sit under another, to any
/// depth: a sub-goal is a piece of reaching its parent. Events are
/// tagged with goals ([Event.goals]) apart from their actions.
class Goal {
  const Goal({
    required this.id,
    required this.title,
    this.parentId,
    this.required = false,
    this.priority,
    this.sortOrder,
    this.expectedMinutes,
    this.deadline,
    this.deadlineOffsetMinutes,
    this.deadlineRule,
    this.activateWhen,
    this.expectedStart,
    this.status = 'active',
    this.history = const [],
    this.description,
    this.definitionOfDone,
    this.attributionHints,
    this.withIds = const [],
    this.forIds = const [],
    this.path = const [],
    this.version,
  });

  final String id;
  final String title;

  /// The goal it's a piece of; null for a top-level goal.
  final String? parentId;

  /// Whether its parent needs it done to be done.
  final bool required;

  /// How much it matters, 0 the most, as actions' priorities; null, it
  /// takes its nearest parent's ([GoalTree.priorityOf]).
  final int? priority;

  /// Where it's listed among goals that otherwise list alike -- the same
  /// priority, due the same day ([GoalTree.listAlike]): the lowest first,
  /// those with none after them. Set by dragging it.
  final int? sortOrder;

  /// How long it's expected to take: a guide for estimating, compared
  /// with the time spent, never enforced.
  final int? expectedMinutes;

  /// When it's due, as the server works it out (its `due`): a date
  /// ("2026-11-01", due at the end of that day) or a date and time
  /// ("2026-11-01T17:00"), local. Needed while it's active; null while it
  /// waits on a start ([deadlineRule]'s `after_start`).
  final String? deadline;

  /// Set, [deadline] follows its parent's: this many minutes before it
  /// (0, the same), kept so by the server whenever the parent's changes,
  /// while it's open. A deadline set without it unties it; so does a move
  /// to the top level.
  final int? deadlineOffsetMinutes;

  /// What its deadline is measured from, when it's neither a date given
  /// nor its parent's ([deadlineOffsetMinutes]): `{after_start: {days |
  /// minutes}}` or `{after_goal: {id, days | minutes}}`, as the server
  /// takes it. Kept so by the server while it's open.
  final Map<String, Object?>? deadlineRule;

  /// What it waits for before the server activates it, while it's
  /// inactive: `{after: [{goal_closed} | {at}], delay, hold_while}`, as
  /// the server takes it.
  final Map<String, Object?>? activateWhen;

  /// Waiting to be activated, when it's expected to be, as the server
  /// says: a date, from its start, or a date and time. Not sent back.
  final String? expectedStart;

  /// One of [goalStatuses]' keys.
  final String status;

  /// Each change of its status, oldest first.
  final List<StatusChange> history;

  /// What it is, as HTML.
  final String? description;

  /// What being done looks like, as HTML.
  final String? definitionOfDone;

  /// A guide, for Claude, to telling which events are for it.
  final String? attributionHints;

  /// The people the user does it with, by id.
  final List<String> withIds;

  /// The people it's done for, who aren't part of doing it -- a promise
  /// to them, a favor -- by id. No one is in both [withIds] and this.
  final List<String> forIds;

  /// Whether it's done with or for [personId].
  bool involves(String personId) =>
      withIds.contains(personId) || forIds.contains(personId);

  /// Its parents' titles, outermost first, as the server last said. Not
  /// sent back.
  final List<String> path;

  final int? version;

  bool get active => status == 'active';
  bool get inactive => status == 'inactive';

  /// Done, missed or obsolete: nothing more to do for it.
  bool get closed =>
      status == 'done' || status == 'missed' || status == 'obsolete';

  /// Inactive or active.
  bool get open => !closed;

  /// When it first became active, if it has.
  DateTime? get startedAt =>
      history.where((c) => c.status == 'active').firstOrNull?.at;

  /// When it was done, missed or made obsolete, if it is.
  DateTime? get closedAt => closed ? history.lastOrNull?.at : null;

  /// Each time it was missed, oldest first: a deadline passed without it
  /// -- and, if it's open, it was tried again after each.
  List<StatusChange> get misses => [
    for (final c in history)
      if (c.status == 'missed') c,
  ];

  /// When it falls due, local: a date's at the midnight after it.
  DateTime? get due => deadlineEnd(deadline);

  /// Whether its deadline follows its parent's.
  bool get followsParent => deadlineOffsetMinutes != null;

  factory Goal.fromJson(Map<String, dynamic> json) => Goal(
    id: json['id'] as String,
    title: json['title'] as String? ?? '',
    parentId: _text(json['parent_id']),
    required: json['required'] == true,
    priority: (json['priority'] as num?)?.toInt(),
    sortOrder: (json['sort_order'] as num?)?.toInt(),
    expectedMinutes: (json['expected_minutes'] as num?)?.toInt(),
    deadline: _deadline(json),
    deadlineOffsetMinutes: switch (json['deadline']) {
      {'before_parent': final Map offset} => _minutes(offset),
      Map() => null,
      _ => (json['deadline_offset_minutes'] as num?)?.toInt(),
    },
    deadlineRule: switch (json['deadline']) {
      final Map rule
          when rule['after_start'] != null || rule['after_goal'] != null =>
        rule.cast(),
      Map() => null,
      _ => (json['deadline_rule'] as Map?)?.cast(),
    },
    activateWhen: (json['activate_when'] as Map?)?.cast(),
    expectedStart: _text(json['expected_start']),
    status: json['status'] as String? ?? 'active',
    history: [
      for (final c in json['history'] as List? ?? const [])
        ?StatusChange.fromJson(c),
    ],
    description: _text(json['description']),
    definitionOfDone: _text(json['definition_of_done']),
    attributionHints: _text(json['attribution_hints']),
    withIds: [for (final id in json['with_ids'] as List? ?? const []) '$id'],
    forIds: [for (final id in json['for_ids'] as List? ?? const []) '$id'],
    path: [for (final p in json['path'] as List? ?? const []) '$p'],
    version: (json['version'] as num?)?.toInt(),
  );

  /// As `create_goal` and `update_goal` take it: only what the server
  /// keeps.
  Map<String, Object?> toJson() => {
    'id': id,
    'title': title,
    'parent_id': ?parentId,
    if (required) 'required': true,
    'priority': ?priority,
    'sort_order': ?sortOrder,
    'expected_minutes': ?expectedMinutes,
    'deadline': ?deadline,
    'deadline_offset_minutes': ?deadlineOffsetMinutes,
    'deadline_rule': ?deadlineRule,
    'activate_when': ?activateWhen,
    'expected_start': ?expectedStart,
    'status': status,
    if (history.isNotEmpty) 'history': [for (final c in history) c.toJson()],
    'description': ?description,
    'definition_of_done': ?definitionOfDone,
    'attribution_hints': ?attributionHints,
    // Only when there are some: a server from before goals named people
    // still saves the rest.
    if (withIds.isNotEmpty) 'with_ids': withIds,
    if (forIds.isNotEmpty) 'for_ids': forIds,
    'version': ?version,
  };

  static String? _text(Object? value) => switch (value) {
    final String text when text.trim().isNotEmpty => text,
    _ => null,
  };

  /// The deadline in [json]: the server's `due`, under a `deadline` that's
  /// what it's measured from; or the app's own, a date given.
  static String? _deadline(Map<String, dynamic> json) =>
      switch (json['deadline']) {
        {'at': final String at} => _text(json['due']) ?? _text(at),
        Map() => _text(json['due']),
        final other => _text(other),
      };

  /// An offset's days or minutes, in minutes.
  static int? _minutes(Map offset) => switch (offset) {
    {'days': final num days} => days.toInt() * Duration.minutesPerDay,
    {'minutes': final num minutes} => minutes.toInt(),
    _ => null,
  };
}

/// [changes] to a goal -- or a whole goal, as [Goal.toJson] gives it -- as
/// the server takes them: its deadline as what it's measured from
/// (`{before_parent}` for a [Goal.deadlineOffsetMinutes], or a
/// [Goal.deadlineRule]) or the date given (`{at}`), with null clearing
/// it; and without what the server works out.
Map<String, Object?> goalWire(Map<String, Object?> changes) {
  final out = {...changes}
    ..remove('deadline_rule')
    ..remove('deadline_offset_minutes')
    ..remove('expected_start')
    ..remove('due')
    ..remove('path');
  final offset = changes['deadline_offset_minutes'];
  if (changes['deadline_rule'] case final Map rule) {
    out['deadline'] = rule;
  } else if (offset is int) {
    out['deadline'] = {
      'before_parent': offset % Duration.minutesPerDay == 0
          ? {'days': offset ~/ Duration.minutesPerDay}
          : {'minutes': offset},
    };
  } else if (changes.containsKey('deadline')) {
    out['deadline'] = switch (changes['deadline']) {
      final String at => {'at': at},
      final Map given => given,
      _ => null,
    };
  }
  return out;
}

/// One change of a goal's status: what it became, when, and the
/// deadline it had then.
class StatusChange {
  const StatusChange(this.status, this.at, {this.deadline});

  final String status;
  final DateTime at;

  /// The goal's deadline in force at this change, as the server keeps
  /// it, if it had one and the change recorded it -- a missed entry's is
  /// the deadline it missed. Changes from before deadlines were kept
  /// have none.
  final String? deadline;

  static StatusChange? fromJson(Object? json) => switch (json) {
    {'status': final String status, 'at': final String at} =>
      switch (DateTime.tryParse(at)) {
        final moment? => StatusChange(
          status,
          moment,
          deadline: Goal._text((json as Map)['deadline']),
        ),
        null => null,
      },
    _ => null,
  };

  Map<String, Object?> toJson() => {
    'status': status,
    'at': localIsoTimestamp(at),
    // Only when there is one: a server from before history entries kept
    // deadlines still saves the rest.
    'deadline': ?deadline,
  };
}

/// The statuses a goal can have, as the server names them, and as the
/// app shows them.
const goalStatuses = {
  'inactive': 'Inactive',
  'active': 'Active',
  'done': 'Done',
  'missed': 'Missed',
  'obsolete': 'Obsolete',
};

/// [goal]'s title, or "(no title)".
String goalTitle(Goal goal) =>
    goal.title.trim().isEmpty ? '(no title)' : goal.title;

/// When [deadline] falls due, local: a date ("2026-11-01") at the
/// midnight after it, a date and time at that time; null if it's
/// neither.
DateTime? deadlineEnd(String? deadline) {
  final text = deadline?.trim();
  if (text == null || text.isEmpty) return null;
  final date = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(text);
  if (date != null) {
    return DateTime(
      int.parse(date[1]!),
      int.parse(date[2]!),
      int.parse(date[3]!) + 1,
    );
  }
  if (!text.contains('T') || text.endsWith('Z') || text.contains('+')) {
    return null;
  }
  return DateTime.tryParse(text);
}

/// [date] as a deadline: just the date, due at its end -- or with
/// [time], at that time.
String deadlineOf(DateTime date, {bool time = false}) {
  String two(int n) => n.toString().padLeft(2, '0');
  final day =
      '${date.year.toString().padLeft(4, '0')}-${two(date.month)}-'
      '${two(date.day)}';
  return time ? '${day}T${two(date.hour)}:${two(date.minute)}' : day;
}

/// Whether [deadline] has a time of day, not just a date.
bool deadlineHasTime(String? deadline) => deadline?.contains('T') ?? false;

/// The deadline [minutes] before [parent], as the server works it out: a
/// date, if [parent] is one and it's whole days before; else a date and
/// time. Null if [parent] isn't a deadline.
String? deadlineBefore(String? parent, int minutes) {
  final text = parent?.trim();
  final end = deadlineEnd(text);
  if (text == null || end == null) return null;
  if (minutes == 0) return text;
  if (!deadlineHasTime(text) && minutes % Duration.minutesPerDay == 0) {
    return deadlineOf(
      DateTime(
        end.year,
        end.month,
        end.day - 1 - minutes ~/ Duration.minutesPerDay,
      ),
    );
  }
  return deadlineOf(end.subtract(Duration(minutes: minutes)), time: true);
}

/// [goals] with each open one whose deadline follows its parent's given
/// the deadline that follows from it, parents first -- and one at the
/// top level untied -- as the server keeps them.
List<Goal> followingParents(List<Goal> goals) {
  final out = [...goals];
  final at = {for (final (i, g) in out.indexed) g.id: i};
  // A pass for each level, at most.
  for (var pass = 0; pass < out.length; pass++) {
    var again = false;
    for (final (i, goal) in out.indexed) {
      if (goal.closed) continue;
      if (goal.deadlineRule != null) {
        final ruled = _ruled(goal, out, at);
        if (ruled == goal.deadline) continue;
        out[i] = Goal.fromJson({
          ...goal.toJson()..remove('deadline'),
          'deadline': ?ruled,
          'path': goal.path,
        });
        again = true;
        continue;
      }
      final minutes = goal.deadlineOffsetMinutes;
      if (minutes == null || minutes < 0) continue;
      final json = goal.toJson();
      if (goal.parentId == null) {
        json.remove('deadline_offset_minutes');
      } else {
        final parent = at[goal.parentId];
        if (parent == null) continue;
        final deadline = deadlineBefore(out[parent].deadline, minutes);
        if (deadline == null || deadline == goal.deadline) continue;
        json['deadline'] = deadline;
        again = true;
      }
      out[i] = Goal.fromJson({...json, 'path': goal.path});
    }
    if (!again) break;
  }
  return out;
}

/// The deadline [goal]'s [Goal.deadlineRule] gives, among [goals] (by
/// index [at]), as the server works it out: from its start, the last
/// time it became active (none until it is); after another goal's
/// deadline. [goal]'s own, if it can't be worked out.
String? _ruled(Goal goal, List<Goal> goals, Map<String, int> at) {
  (int?, int?) offsetOf(Object? offset) => switch (offset) {
    {'days': final num d} => (d.toInt(), null),
    {'minutes': final num m} => (null, m.toInt()),
    _ => (null, null),
  };
  switch (goal.deadlineRule) {
    case {'after_start': final Object? offset}:
      if (!goal.active) return null;
      final start = goal.history.where((c) => c.status == 'active').lastOrNull;
      if (start == null) return goal.deadline;
      return switch (offsetOf(offset)) {
        (final d?, _) => deadlineOf(
          DateTime(start.at.year, start.at.month, start.at.day + d),
        ),
        (_, final m?) => deadlineOf(
          start.at.add(Duration(minutes: m)),
          time: true,
        ),
        _ => goal.deadline,
      };
    case {'after_goal': {'id': final String id} && final Map offset}:
      final other = at[id] == null ? null : goals[at[id]!].deadline;
      final end = deadlineEnd(other);
      if (other == null || end == null) return goal.deadline;
      return switch (offsetOf(offset)) {
        (final d?, _) when !deadlineHasTime(other) => deadlineOf(
          DateTime(end.year, end.month, end.day - 1 + d),
        ),
        (final d?, _) => deadlineOf(end.add(Duration(days: d)), time: true),
        (_, 0) => other,
        (_, final m?) => deadlineOf(end.add(Duration(minutes: m)), time: true),
        _ => goal.deadline,
      };
  }
  return goal.deadline;
}

// -- Goals together --------------------------------------------------------

/// Every goal, by id, with what's under each: what the Goals pane and a
/// goal's page show, and what's checked before a change, as the server
/// checks it.
class GoalTree {
  GoalTree(Iterable<Goal> goals) : byId = {for (final g in goals) g.id: g};

  final Map<String, Goal> byId;

  Goal? operator [](String? id) => id == null ? null : byId[id];

  /// The goals with no parent there.
  List<Goal> get topLevel => [
    for (final g in byId.values)
      if (g.parentId == null || !byId.containsKey(g.parentId)) g,
  ];

  /// The goals directly under [id].
  List<Goal> childrenOf(String id) => [
    for (final g in byId.values)
      if (g.parentId == id) g,
  ];

  /// Every goal under [id], at any depth, nearest first.
  List<Goal> descendantsOf(String id) {
    final out = <Goal>[];
    final seen = <String>{id};
    var level = childrenOf(id);
    while (level.isNotEmpty) {
      final next = <Goal>[];
      for (final g in level) {
        if (!seen.add(g.id)) continue;
        out.add(g);
        next.addAll(childrenOf(g.id));
      }
      level = next;
    }
    return out;
  }

  /// [id]'s parents, outermost first.
  List<Goal> ancestorsOf(String id) {
    final out = <Goal>[];
    final seen = <String>{id};
    for (
      var at = this[this[id]?.parentId];
      at != null && seen.add(at.id);
      at = this[at.parentId]
    ) {
      out.insert(0, at);
    }
    return out;
  }

  /// [id]'s top-level goal: it, or its outermost parent.
  String topOf(String id) => ancestorsOf(id).firstOrNull?.id ?? id;

  /// How deep [id] is: 0 at the top.
  int depthOf(String id) => ancestorsOf(id).length;

  /// [id]'s parents' titles, outermost first.
  List<String> pathOf(String id) => [
    for (final g in ancestorsOf(id)) goalTitle(g),
  ];

  /// Whether [id] is [ancestor], or under it.
  bool isWithin(String id, String ancestor) =>
      id == ancestor || ancestorsOf(id).any((g) => g.id == ancestor);

  /// The priority that applies to [id]: its own, or its nearest parent's
  /// that has one, or [defaultGoalPriority].
  int priorityOf(String id) =>
      this[id]?.priority ??
      ancestorsOf(id).reversed.map((g) => g.priority).nonNulls.firstOrNull ??
      defaultGoalPriority;

  /// [byPriority]'s order: the highest priority (the lowest number) first,
  /// each one's as [priorityOf] has it; then by the day it's due, soonest
  /// first, those with no deadline last; then by [Goal.sortOrder], the
  /// lowest first, those with none after; then as [compareByDeadline] has
  /// them.
  int compare(Goal a, Goal b) {
    final byPriority = priorityOf(a.id).compareTo(priorityOf(b.id));
    if (byPriority != 0) return byPriority;
    final byDay = switch ((dueDay(a), dueDay(b))) {
      (final x?, final y?) => x.compareTo(y),
      (_?, null) => -1,
      (null, _?) => 1,
      (null, null) => 0,
    };
    if (byDay != 0) return byDay;
    final byOrder = switch ((a.sortOrder, b.sortOrder)) {
      (final x?, final y?) => x.compareTo(y),
      (_?, null) => -1,
      (null, _?) => 1,
      (null, null) => 0,
    };
    return byOrder != 0 ? byOrder : compareByDeadline(a, b);
  }

  /// Whether [a] and [b] list alike but for their [Goal.sortOrder]: the
  /// same priority, due the same day (or neither due). Only such goals can
  /// be dragged past each other.
  bool listAlike(Goal a, Goal b) =>
      priorityOf(a.id) == priorityOf(b.id) && dueDay(a) == dueDay(b);
}

/// The day [goal] is due ("2026-11-01"), whatever the time; null if it has
/// no deadline.
String? dueDay(Goal goal) =>
    goal.due == null ? null : goal.deadline!.trim().split('T').first;

/// The priority a goal with none, anywhere up its tree, is treated as.
const defaultGoalPriority = 3;

/// [goals] as the app lists them, as [GoalTree.compare] has them in
/// [tree] -- by default, [goals] themselves: by priority, then the day
/// due, then the user's own order, then the time due and title.
List<Goal> byPriority(Iterable<Goal> goals, [GoalTree? tree]) {
  final listed = [...goals];
  return listed..sort((tree ?? GoalTree(listed)).compare);
}

/// Soonest due first -- on one day, those due at a time, by time, then
/// those due by its end -- those with no deadline last, then by title.
int compareByDeadline(Goal a, Goal b) {
  final (x, y) = (a.due, b.due);
  if (x != null && y != null && x != y) return x.compareTo(y);
  if (x != null && y == null) return -1;
  if (x == null && y != null) return 1;
  return a.title.toLowerCase().compareTo(b.title.toLowerCase());
}

// -- Events' goal shares ----------------------------------------------------

/// One goal an event is tagged with, and how much of the event it takes
/// (see [Share]): with neither minutes nor percent, the remaining time --
/// all of it, whatever other goals take of it too.
class GoalShare extends Share {
  const GoalShare(super.id, {super.minutes, super.percent, super.remaining});

  String get goalId => id;

  static GoalShare? fromJson(Object? json) => switch (json) {
    {'goal_id': final String id} when id.isNotEmpty => GoalShare(
      id,
      minutes: ((json as Map)['minutes'] as num?)?.toInt(),
      percent: (json['percent'] as num?)?.toInt(),
      remaining: json['remaining'] == true,
    ),
    _ => null,
  };

  Map<String, Object?> toJson() => {
    'goal_id': goalId,
    'minutes': ?minutes,
    'percent': ?percent,
    if (plusRemaining) 'remaining': true,
  };

  GoalShare copyWith({
    int? Function()? minutes,
    int? Function()? percent,
    bool? remaining,
  }) => GoalShare(
    goalId,
    minutes: minutes == null ? this.minutes : minutes(),
    percent: percent == null ? this.percent : percent(),
    remaining: remaining ?? plusRemaining,
  );
}

extension EventGoals on Event {
  /// The goals it's tagged with, and how much of it each takes.
  List<GoalShare> get goals => [
    for (final g in properties['goals'] as List? ?? const [])
      ?GoalShare.fromJson(g),
  ];
}

/// The time an event [length] long gives each goal, with [shares]: its
/// own, and a parent's, its own and its sub-goals' at any depth together
/// -- each one's fixed part ([shareParts]), and the remaining time once
/// if it or any under it takes it, never more than the event. Goals
/// [tree] doesn't have are left out.
Map<String, Duration> goalTimes(
  List<GoalShare> shares,
  Duration length,
  GoalTree tree,
) {
  final (:fixed, :remaining, :takers) = shareParts([
    for (final s in shares)
      if (tree.byId.containsKey(s.goalId)) s,
  ], length);
  final total = <String, Duration>{};
  final taking = <String>{};
  for (final id in {...fixed.keys, ...takers}) {
    for (final g in [tree[id]!, ...tree.ancestorsOf(id)]) {
      total[g.id] =
          (total[g.id] ?? Duration.zero) + (fixed[id] ?? Duration.zero);
      if (takers.contains(id)) taking.add(g.id);
    }
  }
  return {
    for (final MapEntry(key: id, value: time) in total.entries)
      id: switch (time + (taking.contains(id) ? remaining : Duration.zero)) {
        final t when t > length => length,
        final t => t,
      },
  };
}

/// The time spent toward each goal in [events]: each event's
/// [goalTimes], by goal.
Map<String, Duration> timeSpent(Iterable<Event> events, GoalTree tree) {
  final out = <String, Duration>{};
  for (final event in events) {
    if (event.isCancelled) continue;
    final shares = event.goals;
    if (shares.isEmpty) continue;
    final length = event.end.difference(event.start);
    if (length <= Duration.zero) continue;
    for (final MapEntry(key: id, value: time) in goalTimes(
      shares,
      length,
      tree,
    ).entries) {
      out[id] = (out[id] ?? Duration.zero) + time;
    }
  }
  return out;
}

/// How much of an event each top-level goal takes, as fractions adding
/// up to no more than 1 -- for splitting its time between them in a
/// summary: each top-level goal's [goalTimes], scaled down together if
/// they'd take more than the whole event.
Map<String, double> topLevelFractions(
  List<GoalShare> shares,
  Duration length,
  GoalTree tree,
) {
  if (length <= Duration.zero) return const {};
  final times = goalTimes(shares, length, tree);
  final tops = {
    for (final MapEntry(key: id, value: time) in times.entries)
      if (tree.topOf(id) == id) id: time.inMicroseconds / length.inMicroseconds,
  };
  final sum = tops.values.fold(0.0, (a, b) => a + b);
  if (sum <= 1) return tops;
  return {for (final MapEntry(key: id, value: f) in tops.entries) id: f / sum};
}

// -- The rules ----------------------------------------------------------------

/// What's wrong with [goals] together, as the server checks them, one
/// sentence each; empty if nothing is. The app checks a change against
/// these before it's queued, so a write is never refused for them.
List<String> goalProblems(List<Goal> goals) {
  final tree = GoalTree(goals);
  final problems = <String>[];
  String name(Goal g) => '“${goalTitle(g)}”';
  for (final goal in goals) {
    if (goal.title.trim().isEmpty) problems.add('A goal needs a title.');
    if (goal.expectedMinutes case final m? when m <= 0) {
      problems.add('${name(goal)} must be expected to take some time.');
    }
    if (goal.deadline != null && goal.due == null) {
      problems.add("${name(goal)}'s deadline isn't a date.");
    }
    if (goal.deadlineOffsetMinutes case final m? when m < 0) {
      problems.add("${name(goal)}'s deadline can't follow its parent's.");
    }
    if (goal.active && goal.deadline == null) {
      problems.add('${name(goal)} is active, so it needs a deadline.');
    }
    if (goal.inactive &&
        goal.deadline == null &&
        goal.deadlineOffsetMinutes == null &&
        goal.deadlineRule == null) {
      problems.add('${name(goal)} needs a deadline, to have when it starts.');
    }
    final started = goal.startedAt;
    if (started != null && goal.due != null && !started.isBefore(goal.due!)) {
      problems.add('${name(goal)} started after its deadline.');
    }
    if (goal.history.isEmpty || goal.history.last.status != goal.status) {
      problems.add("${name(goal)}'s history must end with its status.");
    }
    for (var i = 1; i < goal.history.length; i++) {
      if (goal.history[i].at.isBefore(goal.history[i - 1].at)) {
        problems.add("${name(goal)}'s history must be oldest first.");
      }
      if (goal.history[i].status == goal.history[i - 1].status) {
        problems.add("${name(goal)}'s history repeats a status.");
      }
    }
    final parentId = goal.parentId;
    if (parentId == null) continue;
    final parent = tree[parentId];
    if (parent == null) {
      problems.add("${name(goal)}'s parent isn't a goal any more.");
      continue;
    }
    if (parentId == goal.id ||
        tree.ancestorsOf(parentId).any((g) => g.id == goal.id)) {
      problems.add("${name(goal)} can't be under itself.");
      continue;
    }
    if (goal.closed) continue;
    if (parent.closed) {
      problems.add(
        '${name(goal)} is ${goal.status}, but ${name(parent)} is '
        '${parent.status}.',
      );
    }
    if ((goal.due, parent.due) case (final due?, final parentDue?)
        when due.isAfter(parentDue)) {
      problems.add('${name(goal)} is due after ${name(parent)}.');
    }
    if ((goal.expectedMinutes, parent.expectedMinutes)
        case (final m?, final pm?) when m > pm) {
      problems.add(
        '${name(goal)} is expected to take longer than ${name(parent)}.',
      );
    }
  }
  return {...problems}.toList();
}
