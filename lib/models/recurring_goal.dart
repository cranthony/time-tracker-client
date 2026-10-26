import 'goal.dart';

/// A habit's recurring goal, mirroring the Time Tracker MCP server's
/// `RecurringGoal`: the goal the server makes for each of its periods on
/// the calendar -- a day, a week (Sunday to Saturday), a month, a quarter
/// (from January, April, July or October) or a year -- as
/// each begins, once the one before is done or obsolete, and tries again
/// through the next period when it's missed. Its goals are the habit's
/// ([Goal.habitId]); the habit is scored by its [goalRate].
class RecurringGoal {
  const RecurringGoal({
    this.period = 'week',
    this.title,
    this.priority,
    this.expectedMinutes,
    this.description,
    this.definitionOfDone,
    this.attributionHints,
    this.withIds = const [],
    this.forIds = const [],
    this.ratePeriods,
  });

  /// One of [goalPeriods]' keys.
  final String period;

  /// Its goals' title; null, the habit's name.
  final String? title;

  final int? priority;
  final int? expectedMinutes;
  final String? description;
  final String? definitionOfDone;
  final String? attributionHints;
  final List<String> withIds;
  final List<String> forIds;

  /// How many periods its goal rate counts back; null, its period's
  /// default ([defaultRatePeriods]).
  final int? ratePeriods;

  int get ratedPeriods => ratePeriods ?? defaultRatePeriods(period);

  static RecurringGoal? fromJson(Object? json) => switch (json) {
    final Map json => RecurringGoal(
      period: switch (json['period']) {
        final String p when goalPeriods.containsKey(p) => p,
        _ => 'week',
      },
      title: _text(json['title']),
      priority: (json['priority'] as num?)?.toInt(),
      expectedMinutes: (json['expected_minutes'] as num?)?.toInt(),
      description: _text(json['description']),
      definitionOfDone: _text(json['definition_of_done']),
      attributionHints: _text(json['attribution_hints']),
      withIds: [for (final id in json['with_ids'] as List? ?? const []) '$id'],
      forIds: [for (final id in json['for_ids'] as List? ?? const []) '$id'],
      ratePeriods: (json['rate_periods'] as num?)?.toInt(),
    ),
    _ => null,
  };

  Map<String, Object?> toJson() => {
    'period': period,
    'title': ?title,
    'priority': ?priority,
    'expected_minutes': ?expectedMinutes,
    'description': ?description,
    'definition_of_done': ?definitionOfDone,
    'attribution_hints': ?attributionHints,
    if (withIds.isNotEmpty) 'with_ids': withIds,
    if (forIds.isNotEmpty) 'for_ids': forIds,
    'rate_periods': ?ratePeriods,
  };

  static String? _text(Object? value) => switch (value) {
    final String text when text.trim().isNotEmpty => text,
    _ => null,
  };
}

/// The periods a recurring goal can have, as the server names them, and
/// as the app shows them: each, and many of them.
const goalPeriods = {
  'day': ('Day', 'days'),
  'week': ('Week', 'weeks'),
  'month': ('Month', 'months'),
  'quarter': ('Quarter', 'quarters'),
  'year': ('Year', 'years'),
};

/// "A goal each week", for [recurring].
String goalEachLabel(RecurringGoal recurring) =>
    'A goal each ${(goalPeriods[recurring.period]?.$1 ?? 'period').toLowerCase()}';

/// How many [period]s a goal rate counts back unless its habit says:
/// fewer of the longer ones -- a week of days, a year of months.
int defaultRatePeriods(String period) => switch (period) {
  'day' => 7,
  'month' || 'quarter' => 4,
  'year' => 2,
  _ => 6,
};

/// The habit a goal's [id] says it's from -- `<habit id>_2026-11-01` --
/// if it's one made from a habit: no other goal's id has a "_".
String? habitOfGoalId(String id) {
  final at = id.indexOf('_');
  if (at <= 0) return null;
  return DateTime.tryParse(id.substring(at + 1)) == null
      ? null
      : id.substring(0, at);
}

/// The first day of the [period] [day] falls in, and the first of the
/// one after: weeks start on Sunday.
(DateTime, DateTime) periodOf(DateTime day, String period) {
  final d = DateTime(day.year, day.month, day.day);
  return switch (period) {
    'day' => (d, DateTime(d.year, d.month, d.day + 1)),
    'month' => (DateTime(d.year, d.month), DateTime(d.year, d.month + 1)),
    'quarter' => () {
      final first = d.month - (d.month - 1) % 3;
      return (DateTime(d.year, first), DateTime(d.year, first + 3));
    }(),
    'year' => (DateTime(d.year), DateTime(d.year + 1)),
    _ => () {
      final start = DateTime(d.year, d.month, d.day - d.weekday % 7);
      return (start, DateTime(start.year, start.month, start.day + 7));
    }(),
  };
}

/// A habit's goal rate as of a day: of the periods before the one it
/// falls in -- [RecurringGoal.ratedPeriods] of them, or as many as there
/// have been since its first goal -- how many had a goal done in them.
class GoalRate {
  const GoalRate({
    required this.done,
    required this.counted,
    required this.period,
    this.goalIds = const [],
  });

  final int done;
  final int counted;

  /// One of [goalPeriods]' keys.
  final String period;

  /// The goals done in them, by id.
  final List<String> goalIds;

  /// 0-100; null with no period to count.
  int? get score => counted == 0 ? null : (100 * done / counted).round();

  /// "3 of 6 weeks done".
  String get said {
    final (one, many) = goalPeriods[period] ?? ('period', 'periods');
    return counted == 0
        ? 'No ${one.toLowerCase()} over yet'
        : '$done of $counted ${counted == 1 ? one.toLowerCase() : many} done';
  }
}

/// Habit [habitId]'s goal rate as of the day before [end] (a midnight),
/// from [goals] -- each one's done counting toward the period it was done
/// in, a missed one tried again and done in the next counting there.
GoalRate goalRate(
  String habitId,
  RecurringGoal recurring,
  List<Goal> goals,
  DateTime end,
) {
  final period = recurring.period;
  final theirs = [
    for (final g in goals)
      if (g.habitId == habitId) g,
  ];
  // The periods since its first goal's.
  DateTime? first;
  for (final g in theirs) {
    final start = DateTime.tryParse(g.id.substring(g.id.indexOf('_') + 1));
    if (start != null && (first == null || start.isBefore(first))) {
      first = start;
    }
  }
  final (current, _) = periodOf(
    end.subtract(const Duration(hours: 12)),
    period,
  );
  final counted = <(DateTime, DateTime)>[];
  for (var at = current; counted.length < recurring.ratedPeriods;) {
    final before = periodOf(at.subtract(const Duration(hours: 12)), period);
    if (first == null || before.$1.isBefore(periodOf(first, period).$1)) break;
    counted.add(before);
    at = before.$1;
  }
  final doneIn = <(DateTime, DateTime)>{};
  final ids = <String>[];
  for (final g in theirs) {
    if (g.status != 'done') continue;
    final at = g.closedAt?.toLocal();
    if (at == null) continue;
    for (final p in counted) {
      if (!at.isBefore(p.$1) && at.isBefore(p.$2)) {
        doneIn.add(p);
        ids.add(g.id);
      }
    }
  }
  return GoalRate(
    done: doneIn.length,
    counted: counted.length,
    period: period,
    goalIds: ids,
  );
}
