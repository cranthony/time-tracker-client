/// How a goal's health is rated in each day's reflection, mirroring the
/// MCP server's measure specs (its utilities/goal_measures.py): a JSON
/// object with a "kind" and that kind's fields. Every active goal is
/// reflected on daily; one without a measure is rated as the average of
/// its sub-goals'.
///
/// | kind         | fields                                                 |
/// | ------------ | ------------------------------------------------------ |
/// | `duration`   | `target_min`: minutes per interval                     |
/// | `count`      | `target`: events per interval; optional `noun`         |
/// | (both)       | optional `interval_days` (default 1), `zero_at_days`   |
/// |              | (rated by how long ago the target was last met,        |
/// |              | reaching 0 then)                                       |
/// | `time_       | `edge` ("start" of the day's first event, or "end" of  |
/// | constraint`  | its last), `target` "HH:MM"; optional `when` ("by" or  |
/// |              | "after"), `grace_min`, `zero_at_min`                   |
/// | `time_       | `from` and `to` "HH:MM": whether one of the day's      |
/// | window`      | events falls in the window; optional `grace_min`,      |
/// |              | `zero_at_min`. A day without any is rated 0            |
/// | `follow_     | optional `penalty` (default 25) lost per cancelled     |
/// | through`     | event, `recovery` (default 25) regained per day with a |
/// |              | kept one, from 100 `look_back_days` (default 30) back  |
/// | (all five)   | optional `events_of`, a goal whose events count as     |
/// |              | though they were its own goal's, and                   |
/// |              | `include_sub_goals`                                    |
/// | `subjective` | `prompt`, asked in a reflection every `interval_days`  |
/// |              | (default 1), carried over from the day before between  |
/// | `llm`        | `rubric` Claude rates the day against                  |
/// | `rollup`     | optional `agg`: "mean" (default), "weighted" (with     |
/// |              | `weights`) or "percentile" (with `percentile`); a      |
/// |              | weight is a number or a temporary one (see             |
/// |              | [isTemporaryWeight])                                   |
/// | `traits`     | `traits`: trait ids, or "all" active ones; optional    |
/// |              | `weights` ({trait id: weight}, default 1) and          |
/// |              | `window_days` (default 30)                             |
/// | (any)        | optional `only_if`: {`events_of`, `include_sub_goals`},|
/// |              | both optional ({} is the goal itself): rated only on   |
/// |              | days with such an event, and skipped on the rest       |
typedef Measure = Map<String, Object?>;

/// The kinds of measure, as the server names them, and as the app shows
/// them.
const measureKinds = {
  'duration': 'Time spent',
  'count': 'Number of events',
  'time_constraint': 'Time of day',
  'time_window': 'Time window',
  'follow_through': 'Follow-through',
  'subjective': 'Your rating',
  'llm': "Claude's judgement",
  'rollup': 'From sub-goals',
  'traits': 'Traits',
};

/// What each kind of measure rates, said under its picker.
const measureKindHints = {
  'duration':
      "The time spent on its events (and its sub-goals') over the last "
      'few days, against a target.',
  'count':
      "How many of its events (and its sub-goals') there were over the last "
      'few days, against a target.',
  'time_constraint':
      "When the day's first event starts, or its last ends: full marks by "
      'the time (or not before it), within the grace, falling to none at '
      '"zero at" minutes off. Up by 7, in by 9:30, out by 5:30.',
  'time_window':
      "Whether one of the day's events falls between two times: full marks "
      'for one that overlaps them at all, within the grace, falling to none '
      'at "zero at" minutes out. A day without any is rated 0. Lunch between '
      '11:30 and 1:30.',
  'follow_through':
      "Keeping your word: each of its events that's cancelled (pushed off, "
      "or cancelled in a compaction) costs points, and they're won back on "
      'days with one that happened. Low ratings carry over until then.',
  'subjective':
      "You're asked in a reflection every few days; on the days between, "
      "the day before's rating carries over. Rating it any time starts the "
      'count again.',
  'llm':
      'Claude rates the day against your rubric, reading its events, notes '
      "and sub-goals' ratings, for you to confirm in a reflection.",
  'rollup': "Its sub-goals' ratings that day, combined.",
  'traits':
      'Its traits -- Thoughtful, Reliable, Creative... -- each scored from '
      "parts computed over its events (and its sub-goals') and what "
      'happened at them, over a window of days, then combined. You confirm '
      'it in a reflection. For people, and for keeping your word to '
      'yourself.',
};

/// A trait's id as a name, until the trait's own is known: "reliable" as
/// "Reliable".
String traitLabel(String id, [Map<String, String> traitNames = const {}]) =>
    traitNames[id] ??
    (id.isEmpty
        ? id
        : '${id[0].toUpperCase()}${id.substring(1)}'.replaceAll('-', ' '));

/// How a rollup combines its sub-goals' ratings, as the server names them,
/// and as the app shows them.
const rollupAggregates = {
  'mean': 'Average',
  'weighted': 'Weighted',
  'percentile': 'Percentile',
};

/// Whole numbers as ints, so 600.0 and 600 compare equal.
num _tidy(num n) => n == n.roundToDouble() ? n.round() : n;

num? _number(Object? value) => value is num ? _tidy(value) : null;

/// [days] as "day", "7 days".
String _days(num days) => days == 1 ? 'day' : '$days days';

/// [minutes] as "10h", "45m" or "1h 30m".
String formatMinutes(num minutes) {
  final total = minutes.round();
  final (hours, rest) = (total ~/ 60, total % 60);
  if (hours == 0) return '${rest}m';
  return rest == 0 ? '${hours}h' : '${hours}h ${rest}m';
}

/// [n] as "1st", "2nd", "50th".
String _ordinal(num n) {
  final whole = n.round();
  if (whole != n) return '${n}th';
  final teen = whole % 100 >= 11 && whole % 100 <= 13;
  return '$whole${switch (whole % 10) {
    1 when !teen => 'st',
    2 when !teen => 'nd',
    3 when !teen => 'rd',
    _ => 'th',
  }}';
}

/// A line saying what [measure] rates: "10h per 7 days", "1 visit per 60
/// days, 0 at 90", "Up by 07:00". With [full], a wake-up time's grace is
/// said too, and a subjective measure's prompt and an llm one's rubric
/// follow on lines of their own. A measure of other goals' events names
/// them, from [goalNames] if it has them: "10h per day, of Cooking,
/// Hosting".
String describeMeasure(
  Measure measure, {
  bool full = false,
  Map<String?, String> goalNames = const {},
}) {
  final described = _describe(measure, full: full, goalNames: goalNames);
  final onlyIf = switch (_onlyIfOf(measure, goalNames)) {
    final days? => ', only on days with $days',
    null => '',
  };
  if (onlyIf.isEmpty) return described;
  // On the first line, before a prompt or rubric.
  final end = described.indexOf('\n');
  return end < 0
      ? '$described$onlyIf'
      : '${described.substring(0, end)}$onlyIf${described.substring(end)}';
}

/// Whose events [measure]'s `only_if` asks for, if it has one: "its
/// events", "events of Practice", "its own events" (not its sub-goals').
String? _onlyIfOf(Measure measure, Map<String?, String> goalNames) {
  final onlyIf = measure['only_if'];
  if (onlyIf is! Map) return null;
  final subGoals = onlyIf['include_sub_goals'] != false;
  return switch (onlyIf['events_of']) {
    final String id =>
      'events of ${goalNames[id] ?? 'another goal'}'
          '${subGoals ? '' : ' (not sub-goals)'}',
    _ => subGoals ? 'its events' : 'its own events',
  };
}

String _describe(
  Measure measure, {
  required bool full,
  required Map<String?, String> goalNames,
}) {
  final kind = measure['kind'];
  final of = switch ((
    measure['events_of'],
    measure['goal_ids'],
    measure['include_sub_goals'],
  )) {
    (final String id, _, final sub) =>
      ', of ${goalNames[id] ?? 'another goal'}'
          '${sub == false ? ' (not sub-goals)' : ''}',
    // From before events_of.
    (_, final List ids, final sub) =>
      ', of ${ids.length > 3 || ids.any((id) => !goalNames.containsKey(id)) ? '${ids.length} goal${ids.length == 1 ? '' : 's'}' : ids.map((id) => goalNames[id]).join(', ')}'
          '${sub == false ? ' (not sub-goals)' : ''}',
    (_, _, false) => ', not sub-goals',
    _ => '',
  };
  final per = 'per ${_days(_number(measure['interval_days']) ?? 1)}';
  final zeroAt = switch (_number(measure['zero_at_days'])) {
    final days? => ', 0 at $days days',
    null => '',
  };
  switch (kind) {
    case 'duration':
      final target = _number(measure['target_min']);
      return target == null
          ? 'Time spent$of'
          : '${formatMinutes(target)} $per$zeroAt$of';
    case 'count':
      final target = _number(measure['target']);
      final noun = switch (measure['noun']) {
        final String noun when noun.trim().isNotEmpty => noun.trim(),
        _ => 'events',
      };
      if (target == null) return 'Number of $noun$of';
      // "1 dinner", not "1 dinners".
      final shown = target == 1 && noun.endsWith('s') && noun.length > 1
          ? noun.substring(0, noun.length - 1)
          : noun;
      return '$target $shown $per$zeroAt$of';
    case 'time_constraint':
      final grace = _number(measure['grace_min']) ?? 0;
      return '${measure['edge'] == 'end' ? 'Ends' : 'Starts'} '
          '${measure['when'] == 'after' ? 'not before' : 'by'} '
          '${measure['target'] ?? '?'}'
          '${full && grace > 0 ? ' ($grace min grace)' : ''}$of';
    case 'time_window':
      final grace = _number(measure['grace_min']) ?? 0;
      return 'Between ${measure['from'] ?? '?'} and ${measure['to'] ?? '?'}'
          '${full && grace > 0 ? ' ($grace min grace)' : ''}$of';
    case 'follow_through':
      final (penalty, recovery, lookBack) = _followThrough(measure);
      return 'Follow-through'
          '${full ? ' (−$penalty per cancellation, +$recovery per day kept, '
                    'over ${_days(lookBack)})' : ''}$of';
    case 'subjective':
      final prompt = measure['prompt'];
      final every = _number(measure['interval_days']) ?? 1;
      return 'Your rating${every == 1 ? '' : ', asked every ${_days(every)}'}'
          '${full && prompt is String ? '\n“$prompt”' : ''}';
    case 'llm':
      final rubric = measure['rubric'];
      return "Claude's judgement"
          '${full && rubric is String ? '\n$rubric' : ''}';
    case 'rollup':
      return switch (measure['agg']) {
        'weighted' => 'Weighted average of sub-goals',
        'percentile' => switch (_number(measure['percentile'])) {
          0 => 'Lowest sub-goal rating',
          100 => 'Highest sub-goal rating',
          final p? => '${_ordinal(p)} percentile of sub-goals',
          null => 'Percentile of sub-goals',
        },
        // From before percentiles.
        'min' => 'Lowest sub-goal rating',
        _ => 'Average sub-goal rating',
      };
    case 'traits':
      final weights = measure['weights'] is Map
          ? (measure['weights'] as Map).cast<String, Object?>()
          : const <String, Object?>{};
      String weighed(String id) => switch (_number(weights[id])) {
        final w? when w != 1 => '${traitLabel(id)} ×$w',
        _ => traitLabel(id),
      };
      return switch (measure['traits']) {
        'all' => 'All traits',
        final List ids => ids.map((id) => weighed('$id')).join(', '),
        _ => 'Traits',
      };
    default:
      return '$measure';
  }
}

/// A follow-through measure's penalty, recovery and look-back, with the
/// server's defaults for any it doesn't set.
(num, num, num) _followThrough(Measure measure) => (
  _number(measure['penalty']) ?? 25,
  _number(measure['recovery']) ?? 25,
  _number(measure['look_back_days']) ?? 30,
);

/// What's wrong with [measure], in a sentence, or null if it's fine: the
/// checks the server makes, so the editor can say so before saving.
String? measureProblem(Measure measure) {
  bool positive(Object? n) => n is num && n > 0;
  bool text(Object? s) => s is String && s.trim().isNotEmpty;
  bool time(Object? t) =>
      t is String && RegExp(r'^([01]\d|2[0-3]):[0-5]\d$').hasMatch(t);
  String? graceProblem() {
    final grace = measure['grace_min'] ?? 0;
    if (grace is! num || grace < 0) {
      return 'The grace must be 0 minutes or more.';
    }
    final zeroAt = measure['zero_at_min'];
    if (zeroAt != null && (zeroAt is! num || zeroAt <= grace)) {
      return '"Zero at" must be more minutes off than the grace.';
    }
    return null;
  }

  if (measure.containsKey('events_of') && !text(measure['events_of'])) {
    return 'Choose the goal whose events count.';
  }
  if (measure.containsKey('only_if')) {
    final onlyIf = measure['only_if'];
    if (onlyIf is! Map ||
        (onlyIf.containsKey('events_of') && !text(onlyIf['events_of']))) {
      return 'Choose the goal whose events it rates the day on.';
    }
  }
  switch (measure['kind']) {
    case 'duration' || 'count':
      if (measure['kind'] == 'duration') {
        if (!positive(measure['target_min'])) {
          return 'Enter a target time, like 10h or 1h 30m.';
        }
      } else {
        if (!positive(measure['target'])) return 'Enter a target above 0.';
        if (measure.containsKey('noun') && !text(measure['noun'])) {
          return "Leave what's counted empty, or name it.";
        }
      }
      final interval = measure['interval_days'] ?? 1;
      if (!positive(interval)) return 'The days to look back must be above 0.';
      final zeroAt = measure['zero_at_days'];
      if (zeroAt != null && (zeroAt is! num || zeroAt <= (interval as num))) {
        return '"Zero at" must be more days than it looks back.';
      }
    case 'time_constraint':
      if (measure['edge'] != 'start' && measure['edge'] != 'end') {
        return "Pick the first event's start or the last one's end.";
      }
      if (!time(measure['target'])) return 'Pick a target time.';
      if (graceProblem() case final problem?) return problem;
    case 'time_window':
      if (!time(measure['from']) || !time(measure['to'])) {
        return "Pick the window's start and end.";
      }
      if (graceProblem() case final problem?) return problem;
    case 'follow_through':
      if (!positive(measure['penalty'] ?? 25)) {
        return 'The points lost per cancellation must be above 0.';
      }
      if (!positive(measure['recovery'] ?? 25)) {
        return 'The points won back per day must be above 0.';
      }
      final lookBack = measure['look_back_days'] ?? 30;
      if (lookBack is! int || lookBack < 1) {
        return 'The days to look back must be a whole number, 1 or more.';
      }
    case 'subjective':
      if (!text(measure['prompt'])) return 'Ask a question.';
      if (!positive(measure['interval_days'] ?? 1)) {
        return 'Ask it every 1 day or more.';
      }
    case 'llm':
      if (!text(measure['rubric'])) {
        return 'Say what Claude should rate the day against.';
      }
    case 'rollup':
      switch (measure['agg'] ?? 'mean') {
        case 'mean':
          break;
        case 'weighted':
          final weights = measure['weights'];
          if (weights is! Map ||
              weights.isEmpty ||
              weights.values.any(
                (w) => !isTemporaryWeight(w) && (w is! num || w < 0),
              )) {
            return 'Give at least one sub-goal a weight, 0 or more; one set '
                'aside needs a day, and a weight, 0 or more, for after it.';
          }
        case 'percentile':
          final p = measure['percentile'];
          if (p is! num || p < 0 || p > 100) {
            return 'The percentile must be from 0 (lowest) to 100 (highest).';
          }
        default:
          return 'Pick average, weighted or percentile.';
      }
    case 'traits':
      final traits = measure['traits'];
      if (traits != 'all' && (traits is! List || traits.isEmpty)) {
        return 'Pick the traits it rates by, or all of them.';
      }
      if (!positive(measure['window_days'] ?? 30)) {
        return 'The window must be 1 day or more.';
      }
      final weights = measure['weights'] ?? const {};
      if (weights is! Map || weights.values.any((w) => w is! num || w < 0)) {
        return "Each trait's weight must be 0 or more.";
      }
    default:
      return 'Pick a kind of measure.';
  }
  return null;
}

/// [measure]'s settings, one per row, as a label and its value: ("Target",
/// "10h"), ("Over", "7 days"), ("Events of", "This goal and its
/// sub-goals"). Only what it sets, besides the target, look-back and whose
/// events. Other goals are named from [goalNames] if it has them.
List<(String, String)> describeMeasureSettings(
  Measure measure, {
  Map<String?, String> goalNames = const {},
}) => [
  ..._settings(measure, goalNames),
  if (_onlyIfOf(measure, goalNames) case final days?)
    ('Only on days with', days),
];

List<(String, String)> _settings(
  Measure measure,
  Map<String?, String> goalNames,
) {
  String days(num days) => days == 1 ? '1 day' : '$days days';
  final interval = days(_number(measure['interval_days']) ?? 1);
  final subGoals = measure['include_sub_goals'] != false;
  final of = switch ((measure['events_of'], measure['goal_ids'])) {
    (final String id, _) =>
      '${goalNames[id] ?? 'Another goal'}'
          '${subGoals ? ' and its sub-goals' : ' only'}',
    // From before events_of.
    (_, final List ids) =>
      '${ids.map((id) => goalNames[id] ?? 'another goal').join(', ')}'
          '${subGoals ? ', with sub-goals' : ' only'}',
    _ => subGoals ? 'This goal and its sub-goals' : 'This goal only',
  };
  final zeroAtDays = switch (_number(measure['zero_at_days'])) {
    final zero? => [('Zero at', days(zero))],
    null => <(String, String)>[],
  };
  switch (measure['kind']) {
    case 'duration':
      final target = _number(measure['target_min']);
      return [
        ('Target', target == null ? 'not set' : formatMinutes(target)),
        ('Over', interval),
        ...zeroAtDays,
        ('Events of', of),
      ];
    case 'count':
      final noun = switch (measure['noun']) {
        final String noun when noun.trim().isNotEmpty => noun.trim(),
        _ => 'events',
      };
      final target = _number(measure['target']);
      // "1 visit", not "1 visits".
      final shown = target == 1 && noun.endsWith('s') && noun.length > 1
          ? noun.substring(0, noun.length - 1)
          : noun;
      return [
        ('Target', '${target ?? '?'} $shown'),
        ('Over', interval),
        ...zeroAtDays,
        ('Events of', of),
      ];
    case 'time_constraint':
      return [
        (
          'When',
          '${measure['edge'] == 'end' ? 'Last event ends' : 'First event starts'} '
              '${measure['when'] == 'after' ? 'not before' : 'by'} '
              '${measure['target'] ?? '?'}',
        ),
        if (_number(measure['grace_min']) case final grace?)
          ('Grace', '$grace min'),
        if (_number(measure['zero_at_min']) case final zero?)
          ('Zero at', '$zero min off'),
        ('Events of', of),
      ];
    case 'time_window':
      return [
        ('Window', '${measure['from'] ?? '?'} to ${measure['to'] ?? '?'}'),
        if (_number(measure['grace_min']) case final grace?)
          ('Grace', '$grace min'),
        if (_number(measure['zero_at_min']) case final zero?)
          ('Zero at', '$zero min off'),
        ('Events of', of),
      ];
    case 'follow_through':
      final (penalty, recovery, lookBack) = _followThrough(measure);
      return [
        ('Per cancellation', '−$penalty'),
        ('Per day kept', '+$recovery'),
        ('Over', days(lookBack)),
        ('Events of', of),
      ];
    case 'subjective':
      return [
        if (measure['prompt'] case final String prompt) ('Question', prompt),
        ('Asked', 'every ${interval == '1 day' ? 'day' : interval}'),
      ];
    case 'llm':
      return [
        if (measure['rubric'] case final String rubric) ('Rubric', rubric),
      ];
    case 'rollup':
      final agg = measure['agg'] ?? 'mean';
      return [
        ('Combines', rollupAggregates[agg] ?? '$agg'),
        if (agg == 'percentile')
          if (_number(measure['percentile']) case final p?)
            ('Percentile', _ordinal(p)),
        if (agg == 'weighted')
          if (measure['weights'] case final Map weights)
            for (final MapEntry(:key, :value) in weights.entries)
              (
                goalNames[key] ?? '$key',
                switch (value) {
                  {'weight': final w, 'until': final until, 'then': final t} =>
                    'weight $w until $until, then $t',
                  _ => 'weight $value',
                },
              ),
      ];
    case 'traits':
      return [
        (
          'Traits',
          switch (measure['traits']) {
            'all' => 'All active traits',
            final List ids => ids.map((id) => traitLabel('$id')).join(', '),
            _ => '?',
          },
        ),
        if (measure['weights'] case final Map weights)
          for (final MapEntry(:key, :value) in weights.entries)
            (traitLabel('$key'), 'weight $value'),
        ('Over', days(_number(measure['window_days']) ?? 30)),
      ];
    default:
      return [];
  }
}

/// Whether [weight] is a weighted rollup's temporary weight,
/// `{"weight": 0, "until": "2026-11-05", "then": 1}`: it weighs `weight` on
/// days before `until` and `then` from it on -- a sub-goal set aside for a
/// while.
bool isTemporaryWeight(Object? weight) =>
    weight is Map &&
    weight.length == 3 &&
    weight['weight'] is num &&
    (weight['weight'] as num) >= 0 &&
    weight['then'] is num &&
    (weight['then'] as num) >= 0 &&
    weight['until'] is String &&
    RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(weight['until'] as String) &&
    DateTime.tryParse(weight['until'] as String) != null;
