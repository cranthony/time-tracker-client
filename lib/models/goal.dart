import 'event.dart';
import 'note.dart';

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
    this.expectedMinutes,
    this.deadline,
    this.status = 'active',
    this.history = const [],
    this.description,
    this.definitionOfDone,
    this.attributionHints,
    this.path = const [],
    this.version,
  });

  final String id;
  final String title;

  /// The goal it's a piece of; null for a top-level goal.
  final String? parentId;

  /// Whether its parent needs it done to be done.
  final bool required;

  /// How long it's expected to take: a guide for estimating, compared
  /// with the time spent, never enforced.
  final int? expectedMinutes;

  /// When it's due, as the server keeps it: a date ("2026-11-01", due at
  /// the end of that day) or a date and time ("2026-11-01T17:00"), local.
  /// Needed while it's active.
  final String? deadline;

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

  /// Its parents' titles, outermost first, as the server last said. Not
  /// sent back.
  final List<String> path;

  final int? version;

  bool get active => status == 'active';
  bool get inactive => status == 'inactive';

  /// Done or obsolete: nothing more to do for it.
  bool get closed => status == 'done' || status == 'obsolete';

  /// Inactive or active.
  bool get open => !closed;

  /// When it first became active, if it has.
  DateTime? get startedAt =>
      history.where((c) => c.status == 'active').firstOrNull?.at;

  /// When it was done or made obsolete, if it is.
  DateTime? get closedAt => closed ? history.lastOrNull?.at : null;

  /// When it falls due, local: a date's at the midnight after it.
  DateTime? get due => deadlineEnd(deadline);

  factory Goal.fromJson(Map<String, dynamic> json) => Goal(
    id: json['id'] as String,
    title: json['title'] as String? ?? '',
    parentId: _text(json['parent_id']),
    required: json['required'] == true,
    expectedMinutes: (json['expected_minutes'] as num?)?.toInt(),
    deadline: _text(json['deadline']),
    status: json['status'] as String? ?? 'active',
    history: [
      for (final c in json['history'] as List? ?? const [])
        ?StatusChange.fromJson(c),
    ],
    description: _text(json['description']),
    definitionOfDone: _text(json['definition_of_done']),
    attributionHints: _text(json['attribution_hints']),
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
    'expected_minutes': ?expectedMinutes,
    'deadline': ?deadline,
    'status': status,
    if (history.isNotEmpty) 'history': [for (final c in history) c.toJson()],
    'description': ?description,
    'definition_of_done': ?definitionOfDone,
    'attribution_hints': ?attributionHints,
    'version': ?version,
  };

  static String? _text(Object? value) => switch (value) {
    final String text when text.trim().isNotEmpty => text,
    _ => null,
  };
}

/// One change of a goal's status: what it became, and when.
class StatusChange {
  const StatusChange(this.status, this.at);

  final String status;
  final DateTime at;

  static StatusChange? fromJson(Object? json) => switch (json) {
    {'status': final String status, 'at': final String at} =>
      switch (DateTime.tryParse(at)) {
        final moment? => StatusChange(status, moment),
        null => null,
      },
    _ => null,
  };

  Map<String, Object?> toJson() => {
    'status': status,
    'at': localIsoTimestamp(at),
  };
}

/// The statuses a goal can have, as the server names them, and as the
/// app shows them.
const goalStatuses = {
  'inactive': 'Inactive',
  'active': 'Active',
  'done': 'Done',
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
}

/// [goals] as the Goals pane lists them: soonest due first, those with
/// no deadline last, then by title.
List<Goal> byDeadline(Iterable<Goal> goals) => [...goals]
  ..sort((a, b) {
    final (x, y) = (a.due, b.due);
    if (x != null && y != null && x != y) return x.compareTo(y);
    if (x != null && y == null) return -1;
    if (x == null && y != null) return 1;
    return a.title.toLowerCase().compareTo(b.title.toLowerCase());
  });

// -- Events' goal shares ----------------------------------------------------

/// One goal an event is tagged with, and how much of the event it takes:
/// [minutes] (a fixed share), [percent] (of what the fixed shares leave),
/// or neither -- the whole event.
class GoalShare {
  const GoalShare(this.goalId, {this.minutes, this.percent});

  final String goalId;
  final int? minutes;
  final int? percent;

  /// Whether it takes the whole event.
  bool get whole => minutes == null && percent == null;

  static GoalShare? fromJson(Object? json) => switch (json) {
    {'goal_id': final String id} when id.isNotEmpty => GoalShare(
      id,
      minutes: ((json as Map)['minutes'] as num?)?.toInt(),
      percent: (json['percent'] as num?)?.toInt(),
    ),
    _ => null,
  };

  Map<String, Object?> toJson() => {
    'goal_id': goalId,
    'minutes': ?minutes,
    'percent': ?percent,
  };

  /// What it takes, briefly: "45m", "30%", or "" for the whole event.
  String get label => switch ((minutes, percent)) {
    (final m?, _) => formatMinutes(m),
    (null, final p?) => '$p%',
    _ => '',
  };

  GoalShare copyWith({int? Function()? minutes, int? Function()? percent}) =>
      GoalShare(
        goalId,
        minutes: minutes == null ? this.minutes : minutes(),
        percent: percent == null ? this.percent : percent(),
      );

  @override
  bool operator ==(Object other) =>
      other is GoalShare &&
      other.goalId == goalId &&
      other.minutes == minutes &&
      other.percent == percent;

  @override
  int get hashCode => Object.hash(goalId, minutes, percent);

  @override
  String toString() => 'GoalShare($goalId, $label)';
}

/// [minutes] briefly: "45m", "2h", "1h 30m".
String formatMinutes(int minutes) {
  final (h, m) = (minutes ~/ 60, minutes % 60);
  if (h == 0) return '${m}m';
  return m == 0 ? '${h}h' : '${h}h ${m}m';
}

extension EventGoals on Event {
  /// The goals it's tagged with, and how much of it each takes.
  List<GoalShare> get goals => [
    for (final g in properties['goals'] as List? ?? const [])
      ?GoalShare.fromJson(g),
  ];
}

/// What's wrong with [shares] on an event [eventMinutes] long, as the
/// server checks them; empty if nothing is.
List<String> shareProblems(List<GoalShare> shares, int eventMinutes) {
  final problems = <String>[];
  var (minutes, percent) = (0, 0);
  final seen = <String>{};
  for (final s in shares) {
    if (!seen.add(s.goalId)) problems.add('A goal is given twice.');
    if (s.minutes case final m?) {
      if (m <= 0) problems.add('Minutes must be more than 0.');
      minutes += m;
    } else if (s.percent case final p?) {
      if (p < 1 || p > 100) problems.add('A percent must be 1 to 100.');
      percent += p;
    }
  }
  if (minutes > eventMinutes) {
    problems.add(
      'The goals take ${formatMinutes(minutes)}, more than the event\'s '
      '${formatMinutes(eventMinutes)}.',
    );
  }
  if (percent > 100) {
    problems.add('The goals\' percents add up to $percent%, more than 100%.');
  }
  return problems;
}

/// How much of an event [length] long each of [shares] takes, by goal:
/// the fixed minutes first, in order (cut down to fit), then the percents
/// of what's left, then the whole event for those with neither.
Map<String, Duration> shareTimes(List<GoalShare> shares, Duration length) {
  final out = <String, Duration>{};
  var left = length;
  for (final s in shares) {
    if (s.minutes case final m? when !out.containsKey(s.goalId)) {
      final take = Duration(minutes: m) > left ? left : Duration(minutes: m);
      out[s.goalId] = take;
      left -= take;
    }
  }
  final rest = left;
  var percentLeft = 100;
  for (final s in shares) {
    if (s.percent case final p? when !out.containsKey(s.goalId)) {
      final take = p.clamp(0, percentLeft);
      percentLeft -= take;
      out[s.goalId] = rest * take ~/ 100;
    }
  }
  for (final s in shares) {
    if (s.whole) out.putIfAbsent(s.goalId, () => length);
  }
  return out;
}

/// The time an event [length] long gives each goal, with [shares]: its
/// own, and a parent's, its own and its sub-goals' at any depth together
/// -- never more than the event, and the whole event if it or any under
/// it takes the whole event. Goals [tree] doesn't have are left out.
Map<String, Duration> goalTimes(
  List<GoalShare> shares,
  Duration length,
  GoalTree tree,
) {
  final own = shareTimes([
    for (final s in shares)
      if (tree.byId.containsKey(s.goalId)) s,
  ], length);
  final whole = {
    for (final s in shares)
      if (s.whole && tree.byId.containsKey(s.goalId)) s.goalId,
  };
  final total = <String, Duration>{};
  final full = <String>{};
  for (final MapEntry(key: id, value: time) in own.entries) {
    for (final g in [tree[id]!, ...tree.ancestorsOf(id)]) {
      total[g.id] = (total[g.id] ?? Duration.zero) + time;
      if (whole.contains(id)) full.add(g.id);
    }
  }
  return {
    for (final MapEntry(key: id, value: time) in total.entries)
      id: full.contains(id) || time > length ? length : time,
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
    if (goal.active && goal.deadline == null) {
      problems.add('${name(goal)} is active, so it needs a deadline.');
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
    } else if (goal.active && parent.inactive) {
      problems.add('${name(goal)} is active, but ${name(parent)} is inactive.');
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
