import '../models/assessment.dart';
import '../models/event.dart';
import '../models/goal.dart';
import '../models/note.dart';
import '../models/recurrence.dart';
import '../models/trait.dart';
import '../services/events_repository.dart';
import '../services/goals_repository.dart';
import '../services/notes_repository.dart';
import '../services/traits_repository.dart';

/// A realistic day of notes, events and goals, for trying the app's
/// features without a server -- `flutter run --dart-define=SAMPLE_DATA=true`
/// -- and for the visual tests in test/visual. Everything is dated relative
/// to [now], so the sample never goes stale.
///
/// The goals cover what the Goals page can show: every status, sub-goals,
/// own and inherited colors, health with a sparkline, days gone unrated,
/// a skipped day, a proposed rating not yet confirmed, and the time spent
/// on each up to the last compaction. Two friends are rated by traits --
/// one with cadences of their own -- with what happened at their events,
/// their histories, what matters to them, and a week of trait scores.
class SampleData {
  SampleData(this.now);

  final DateTime now;

  DateTime get _today => DateTime(now.year, now.month, now.day);
  DateTime _at(int hour, [int minute = 0, int dayOffset = 0]) =>
      _today.add(Duration(days: dayOffset, hours: hour, minutes: minute));

  NotesRepository notesRepository() => InMemoryNotesRepository(
    notes,
    CompactionStatus(
      lastCompaction: lastCompaction,
      latestCompacted: latestCompacted,
    ),
  );
  EventsRepository eventsRepository() =>
      InMemoryEventsRepository(events, recurrences);
  GoalsRepository goalsRepository() => InMemoryGoalsRepository(
    goals,
    assessments,
    lastCompaction,
    minutesByStatuses,
    minutesByPriority,
  );

  /// The five starting traits, as a new calendar's Traits tab has them; a
  /// week of their scores across the two friends; and each friend's
  /// latest rating, part by part, history and what matters to them.
  TraitsRepository traitsRepository() => InMemoryTraitsRepository(
    traits: traits,
    history: [
      for (final (i, trait) in traits.indexed)
        for (var back = 7; back >= 1; back--)
          TraitDay(
            traitId: trait.id!,
            name: trait.name,
            day: _day(_today.subtract(Duration(days: back))),
            score:
                ((_traitScores['sam']![i] + _traitScores['priya']![i]) / 2 -
                        back * (i + 1))
                    .round()
                    .clamp(0, 100),
            goals: {
              'sam': (_traitScores['sam']![i] - back * (i + 1)).clamp(0, 100),
              'priya': (_traitScores['priya']![i] - back).clamp(0, 100),
            },
          ),
    ],
    ratings: {
      for (final id in ['sam', 'priya']) id: _traitsRating(id),
    },
    digests: {
      for (final id in ['sam', 'priya']) id: _digest(id),
    },
    descriptions: {
      'sam':
          'Friend from the dance class.\n\n## What matters to them\n\n'
          '- ${_day(_today.subtract(const Duration(days: 40)))}: training '
          'for a half marathon in the spring\n'
          '- ${_day(_today.subtract(const Duration(days: 12)))}: starts a new '
          'job next month',
      'priya':
          '## What matters to them\n\n'
          '- ${_day(_today.subtract(const Duration(days: 20)))}: loves jazz, '
          'and trying new restaurants',
    },
  );

  /// Each friend's latest score for each of [traits], in order.
  static const _traitScores = {
    'sam': [50, 95, 70, 100, 85],
    'priya': [80, 60, 0, 50, 75],
  };

  /// Sam's own Reliable parts: a cadence of visits, and of dance.
  static const _samsReliable = [
    {'kind': 'continuity', 'last_within_days': 7, 'next_within_days': 7},
    {'kind': 'follow_through'},
    {'kind': 'count', 'target': 1, 'interval_days': 14, 'activity': 'visit'},
    {'kind': 'count', 'target': 1, 'interval_days': 7, 'activity': 'dance'},
  ];

  TraitsRating _traitsRating(String id) {
    final scores = _traitScores[id]!;
    final parts = <String, List<PartScore>>{
      'thoughtful': [
        PartScore(
          key: 'prep',
          kind: 'prep',
          score: scores[0],
          said: '1 of 2 prep events in the last 30 days',
          eventIds: ['$id-gift'],
        ),
        const PartScore(
          key: 'judgment',
          kind: 'judgment',
          said: 'To be judged in the reflection',
          rubric: 'Did the events and notes reflect what matters to them?',
        ),
      ],
      'reliable': [
        PartScore(
          key: 'continuity',
          kind: 'continuity',
          score: scores[1],
          said: 'Last 1 day ago; next in 5 days (within 7 and 7 days)',
          eventIds: ['$id-dance'],
        ),
        const PartScore(
          key: 'follow_through',
          kind: 'follow_through',
          score: 100,
          said: 'Nothing cancelled or kept that day, from 100',
        ),
        // Sam's own cadences: see _samsReliable.
        if (id == 'sam') ...[
          PartScore(
            key: 'count',
            kind: 'count',
            score: 0,
            said: '0 of 1 visit in the last 14 days',
          ),
          PartScore(
            key: 'count#2',
            kind: 'count',
            score: 100,
            said: '1 of 1 dance in the last 7 days',
            eventIds: ['$id-dance'],
          ),
        ],
      ],
      'creative': [
        PartScore(
          key: 'together_creative',
          kind: 'together_creative',
          score: scores[2],
          said:
              '${scores[2] == 0 ? 0 : 1} of 1 events making something '
              'together in the last 30 days',
          eventIds: [if (scores[2] > 0) '$id-cook'],
        ),
      ],
      'adventurous': [
        PartScore(
          key: 'novelty',
          kind: 'novelty',
          score: scores[3],
          said: '${scores[3] ~/ 50} of 2 new experiences in the last 30 days',
          eventIds: ['$id-jazz'],
        ),
      ],
      'generous': [
        PartScore(
          key: 'effort_paid',
          kind: 'effort_paid',
          score: scores[4],
          said: '${scores[4] * 6} of 600 effort-minutes in the last 30 days',
          eventIds: ['$id-cook', '$id-gift'],
        ),
        const PartScore(
          key: 'attention',
          kind: 'attention',
          score: 100,
          said: 'Mean attention 3.0 of 3 over 2 events in the last 30 days',
        ),
      ],
    };
    // Each trait the mean of its parts that have a score, and the rating
    // the mean of the traits', as the server works them out.
    int? mean(Iterable<int?> values) {
      final scored = values.nonNulls.toList();
      return scored.isEmpty
          ? null
          : (scored.reduce((a, b) => a + b) / scored.length).round();
    }

    final traitScores = [
      for (final trait in traits)
        TraitScore(
          traitId: trait.id!,
          name: trait.name,
          score: mean(parts[trait.id]!.map((p) => p.score)),
          parts: parts[trait.id]!,
        ),
    ];
    final rated = mean(traitScores.map((t) => t.score));
    return TraitsRating(
      rating: rated,
      day: _day(_today.subtract(const Duration(days: 1))),
      explanation:
          'Traits (${traitScores.map((t) => '${t.name} ${t.score}').join(', ')}) → $rated',
      traits: traitScores,
    );
  }

  GoalDigest _digest(String id) {
    final events = [
      _past(
        id,
        'jazz',
        'Jazz night',
        9,
        20,
        facets: {
          'with_goal_ids': [id],
          'activity': 'jazz club',
          'place': 'the cellar',
          'new': 'both',
          'attention': 3,
          'why': 'first time at a jazz club together',
        },
      ),
      _past(
        id,
        'gift',
        'Wrap a birthday present',
        6,
        18,
        goal: 'neighbor',
        facets: {
          'for_goal_ids': [id],
          'activity': 'gift',
          'effort': 2,
        },
      ),
      _past(
        id,
        'cook',
        'Cook dumplings',
        4,
        18,
        facets: {
          'with_goal_ids': [id],
          'activity': 'cook',
          'place': 'home',
          'creative': 2,
          'effort': 2,
          'attention': 3,
          'why': 'folded them together; talked about the new job',
        },
      ),
      _past(
        id,
        'dance',
        'Salsa social',
        1,
        20,
        facets: {
          'with_goal_ids': [id],
          'activity': 'dance',
          'place': 'the hall',
          'new': 'none',
          'attention': 2,
        },
      ),
    ];
    return GoalDigest(
      goalId: id,
      eventsCounted: events.length,
      withFacets: events.length,
      activities: [
        for (final (label, count, back) in [
          ('dance', 6, 1),
          ('cook', 2, 4),
          ('gift', 1, 6),
          ('jazz club', 1, 9),
        ])
          DigestEntry(
            label: label,
            count: count,
            first: _day(
              _today.subtract(Duration(days: back + 20 * (count - 1))),
            ),
            last: _day(_today.subtract(Duration(days: back))),
          ),
      ],
      places: [
        DigestEntry(
          label: 'the hall',
          count: 6,
          first: _day(_today.subtract(const Duration(days: 101))),
          last: _day(_today.subtract(const Duration(days: 1))),
        ),
        DigestEntry(
          label: 'home',
          count: 2,
          first: _day(_today.subtract(const Duration(days: 24))),
          last: _day(_today.subtract(const Duration(days: 4))),
        ),
      ],
      whatMatters: id == 'sam'
          ? '- ${_day(_today.subtract(const Duration(days: 40)))}: training '
                'for a half marathon in the spring\n'
                '- ${_day(_today.subtract(const Duration(days: 12)))}: starts '
                'a new job next month'
          : '- ${_day(_today.subtract(const Duration(days: 20)))}: loves '
                'jazz, and trying new restaurants',
      events: events,
    );
  }

  /// A past event of [id]'s, [daysAgo] days back at [hour], as the server
  /// sends it, with [facets].
  Map<String, dynamic> _past(
    String id,
    String key,
    String summary,
    int daysAgo,
    int hour, {
    String? goal,
    Map<String, Object?> facets = const {},
  }) => {
    'id': '$id-$key',
    'summary': summary,
    'start': localIsoTimestamp(_at(hour, 0, -daysAgo)),
    'end': localIsoTimestamp(_at(hour + 2, 0, -daysAgo)),
    'goal_ids': [goal ?? id],
    'facets': facets,
  };

  static String _day(DateTime day) =>
      '${day.year}-${day.month.toString().padLeft(2, '0')}-'
      '${day.day.toString().padLeft(2, '0')}';

  List<Trait> get traits => const [
    Trait(
      id: 'thoughtful',
      name: 'Thoughtful',
      definition: 'Remember what matters to them, and prepare for it.',
      parts: [
        {'kind': 'prep', 'target': 2},
        {'kind': 'prep_regularity', 'weeks': 4},
        {
          'kind': 'judgment',
          'rubric': 'Did the events and notes reflect what matters to them?',
        },
      ],
    ),
    Trait(
      id: 'reliable',
      name: 'Reliable',
      definition: 'Do what I said I would, and keep contact going.',
      parts: [
        {'kind': 'continuity', 'last_within_days': 14, 'next_within_days': 14},
        {'kind': 'follow_through'},
      ],
    ),
    Trait(
      id: 'creative',
      name: 'Creative',
      definition: 'Make something together with them.',
      parts: [
        {'kind': 'together_creative', 'target': 1, 'min_creative': 2},
      ],
    ),
    Trait(
      id: 'adventurous',
      name: 'Adventurous',
      definition: 'Share new experiences with them.',
      parts: [
        {'kind': 'novelty', 'target': 1},
      ],
    ),
    Trait(
      id: 'generous',
      name: 'Generous',
      definition: 'Make an effort for them, attention included.',
      parts: [
        {'kind': 'effort_paid', 'target': 600},
        {'kind': 'attention'},
      ],
    ),
  ];

  /// The time on goals by the statuses of the goals each event served:
  /// most on active goals, a little on the guitar, which is paused.
  List<StatusMinutes> get minutesByStatuses => const [
    StatusMinutes(statuses: {'active'}, minutes24h: 420, minutes7d: 2610),
    StatusMinutes(statuses: {'inactive'}, minutes24h: 0, minutes7d: 90),
  ];

  /// The last 24 hours and 7 days by priority: sleep's P3 the most, then
  /// the time with no event, or none with a priority.
  List<PriorityMinutes> get minutesByPriority => const [
    PriorityMinutes(priority: 0, minutes24h: 30, minutes7d: 300),
    PriorityMinutes(priority: 1, minutes24h: 240, minutes7d: 1500),
    PriorityMinutes(priority: 2, minutes24h: 225, minutes7d: 1100),
    PriorityMinutes(priority: 3, minutes24h: 480, minutes7d: 3360),
    PriorityMinutes(priority: null, minutes24h: 465, minutes7d: 3820),
  ];

  List<Note> get notes => [
    Note(timestamp: _at(7, 50), description: 'Running a little late'),
    Note(timestamp: _at(9, 40), description: 'Started on the goals page'),
    Note(timestamp: _at(12, 15), description: 'Lunch, finally'),
  ];

  List<Event> get events => [
    _event(
      'sleep',
      'Sleep',
      _at(23, 0, -1),
      _at(7, 0),
      sleep: true,
      priority: 3,
    ),
    _event(
      'morning_today',
      'Morning routine',
      _at(7, 0),
      _at(8, 0),
      goals: ['wake'],
      series: 'morning',
      priority: 0,
    ),
    _event(
      'work',
      'Time Tracker: goals page',
      _at(8, 0),
      _at(12, 0),
      goals: ['tracker'],
      priority: 1,
    ),
    _event(
      'lunch',
      'Lunch with Sam',
      _at(12, 0),
      _at(13, 0),
      goals: ['sam'],
      facets: {
        'with_goal_ids': ['sam'],
        'activity': 'lunch',
        'place': 'the noodle bar',
        'new': 'place',
        'attention': 3,
        'why': 'talked through the job offer; phones away',
      },
    ),
    // Too short for their text: drawn taller, and pushed down.
    _event(
      'call',
      'Call Mom',
      _at(13, 0),
      _at(13, 5),
      goals: ['parents', 'neighbor'],
      priority: 1,
    ),
    _event('plants', 'Water the plants', _at(13, 5), _at(13, 15)),
    // In the same color as the one before: a seam divides them.
    _event('cat', 'Feed the cat', _at(13, 15), _at(13, 20)),
    // Never given goals: Tofu's is inferred from its label.
    _event(
      'class',
      'Cooking class',
      _at(14, 0),
      _at(16, 0),
      goals: ['tofu'],
      fromLabel: true,
      priority: 2,
    ),
    _event(
      'dinner',
      'Dinner with Sam & Priya',
      _at(18, 30),
      _at(21, 0),
      goals: ['host', 'tofu'],
      // Tofu's, inherited from Cooking: Hosting has none.
      priority: 2,
    ),
    _event('read', 'Reading', _at(21, 0), _at(22, 30)),
  ];

  Event _event(
    String id,
    String summary,
    DateTime start,
    DateTime end, {
    List<String> goals = const [],
    bool sleep = false,
    String? series,
    bool fromLabel = false,
    int? priority,
    Map<String, Object?>? facets,
  }) => Event.fromJson({
    'id': id,
    'summary': summary,
    'start': localIsoTimestamp(start),
    'end': localIsoTimestamp(end),
    'is_cancelled': false,
    'goal_ids': goals,
    'goal_names': [for (final g in goals) _names[g]],
    if (sleep) 'is_end_of_day_sleep': true,
    'recurring_event_id': ?series,
    if (fromLabel) 'goals_from_label': true,
    'effective_priority': ?priority,
    'facets': ?facets,
  });

  /// The series "Morning routine" is part of: every weekday since a month
  /// ago.
  List<Recurrence> get recurrences => [
    Recurrence.fromJson({
      'id': 'morning',
      'summary': 'Morning routine',
      'start': localIsoTimestamp(_at(7, 0, -28)),
      'end': localIsoTimestamp(_at(8, 0, -28)),
      'time_zone': 'America/New_York',
      'repeat': {
        'every': 'week',
        'weekdays': ['mon', 'tue', 'wed', 'thu', 'fri'],
      },
      'schedule': 'Every week on Mon, Tue, Wed, Thu, Fri',
      'goal_ids': ['wake'],
      'goal_names': [_names['wake']],
      'is_fixed_time': true,
    }),
  ];

  static const _names = {
    'tracker': 'Make a Time Tracker app',
    'wake': 'Wake up at 7am',
    'host': 'Host friends weekly',
    'cook': 'Learn vegetarian cooking',
    'tofu': 'Tofu tikka masala',
    'neighbor': 'Be a good neighbor',
    'parents': 'Visit parents every 2 months',
    'trains': 'Book the train a month ahead',
    'cousins': 'Visit cousins every week',
    'friends': 'Keep up with friends',
    'sam': 'Sam',
    'priya': 'Priya',
  };

  /// When notes were last compacted, which goals' recent time is counted
  /// up to.
  DateTime get lastCompaction => _at(7, 30);

  /// The last compacted note: before [notes], which aren't yet.
  Note get latestCompacted => Note(
    timestamp: _at(22, 40, -1),
    description: 'Lights out',
    compactionId: 'sample',
  );

  List<Goal> get goals => [
    Goal.fromJson({
      'id': overallGoalId,
      'name': 'Overall',
      'status': 'active',
      ..._health('overall'),
      ..._time(420, 2610),
    }),
    Goal.fromJson({
      'id': 'tracker',
      'name': _names['tracker'],
      'status': 'active',
      'background_color': '#8e24aa',
      'effective_color': '#8e24aa',
      'priority': 1,
      'measure': {'kind': 'duration', 'target_min': 600, 'interval_days': 7},
      ..._health('tracker'),
      ..._time(240, 1500),
    }),
    Goal.fromJson({
      'id': 'wake',
      'name': _names['wake'],
      'status': 'active',
      'effective_color': '#039be5',
      'priority': 0,
      'measure': {
        'kind': 'time_constraint',
        'edge': 'start',
        'target': '07:00',
        'grace_min': 10,
      },
      ..._health('wake', stale: 2),
      ..._time(60, 420),
    }),
    Goal.fromJson({
      'id': 'host',
      'name': _names['host'],
      'status': 'active',
      'background_color': '#f4511e',
      'effective_color': '#f4511e',
      'measure': {
        'kind': 'count',
        'target': 1,
        'noun': 'dinners',
        'interval_days': 7,
        'zero_at_days': 14,
      },
      ..._health('host'),
      ..._time(0, 150),
    }),
    Goal.fromJson({
      'id': 'cook',
      'name': _names['cook'],
      'status': 'active',
      'background_color': '#33b679',
      'effective_color': '#33b679',
      'priority': 2,
      'measure': {'kind': 'rollup', 'agg': 'percentile', 'percentile': 0},
      ..._health('cook'),
      ..._time(120, 270),
    }),
    Goal.fromJson({
      'id': 'tofu',
      'parent_id': 'cook',
      'name': _names['tofu'],
      'status': 'active',
      'effective_color': '#33b679',
      'measure': {
        'kind': 'subjective',
        'prompt': 'How did it turn out?',
        'interval_days': 7,
      },
      ..._health('tofu'),
      ..._time(120, 270),
    }),
    Goal.fromJson({
      'id': 'neighbor',
      'name': _names['neighbor'],
      'status': 'active',
      'background_color': '#f6bf26',
      'effective_color': '#f6bf26',
      ..._health('neighbor'),
      ..._time(0, 180),
    }),
    Goal.fromJson({
      'id': 'parents',
      'parent_id': 'neighbor',
      'name': _names['parents'],
      'status': 'active',
      'effective_color': '#f6bf26',
      'measure': {
        'kind': 'count',
        'target': 1,
        'noun': 'visits',
        'interval_days': 60,
        'zero_at_days': 90,
      },
      ..._health('parents'),
      ..._time(0, 0),
    }),
    // A third level down, its color inherited like its parent's.
    Goal.fromJson({
      'id': 'trains',
      'parent_id': 'parents',
      'name': _names['trains'],
      'status': 'active',
      'effective_color': '#f6bf26',
      'priority': 3,
      ..._time(0, 0),
    }),
    Goal.fromJson({
      'id': 'cousins',
      'parent_id': 'neighbor',
      'name': _names['cousins'],
      'status': 'active',
      'effective_color': '#f6bf26',
      'measure': {
        'kind': 'count',
        'target': 1,
        'noun': 'visits',
        'interval_days': 7,
        'zero_at_days': 14,
      },
      ..._health('cousins'),
      ..._time(0, 180),
    }),
    Goal.fromJson({
      'id': 'friends',
      'name': _names['friends'],
      'status': 'active',
      'background_color': '#7986cb',
      'effective_color': '#7986cb',
      'priority': 2,
      ..._health('friends'),
      ..._time(60, 420),
    }),
    // Rated by traits, with cadences of its own.
    Goal.fromJson({
      'id': 'sam',
      'parent_id': 'friends',
      'name': _names['sam'],
      'status': 'active',
      'effective_color': '#7986cb',
      'measure': {
        'kind': 'traits',
        'traits': 'all',
        'parts': {'reliable': _samsReliable},
      },
      ..._health('sam'),
      ..._time(60, 300),
    }),
    // Rated by traits, as the Traits tab has them.
    Goal.fromJson({
      'id': 'priya',
      'parent_id': 'friends',
      'name': _names['priya'],
      'status': 'active',
      'effective_color': '#7986cb',
      'measure': {
        'kind': 'traits',
        'traits': 'all',
        'weights': {'creative': 2},
      },
      ..._health('priya'),
      ..._time(0, 120),
    }),
    Goal.fromJson({
      'id': 'book',
      'name': 'Write a book about time',
      'status': 'proposed',
    }),
    Goal.fromJson({
      'id': 'guitar',
      'name': 'Learn the guitar',
      'status': 'inactive',
    }),
    Goal.fromJson({'id': '10k', 'name': 'Run a 10k', 'status': 'completed'}),
    Goal.fromJson({
      'id': 'old',
      'name': 'Old side project',
      'status': 'archived',
    }),
    Goal.fromJson({'id': 'typo', 'name': 'Typo goal', 'status': 'deleted'}),
  ];

  /// Each rated goal's ratings over its last 8 days, oldest first; null is
  /// a skipped day. The last is proposed, not yet confirmed.
  static const _ratings = {
    'tracker': [55, 62, null, 70, 78, 74, 88, 82],
    'wake': [100, 92, 60, 30, 100, 84, 64, 50],
    'host': [100, 93, 86, 79, 71, 100, 100, 100],
    'cook': [20, 35, 45, 45, 60, 60, 65, 80],
    'tofu': [20, 35, 50, 45, 60, 70, 65, 80],
    'neighbor': [100, 100, 96, 89, 82, 100, 100, 100],
    'overall': [70, 75, 66, 62, 70, 82, 80, 82],
    'parents': [100, 100, 100, 100, 100, 100, 100, 100],
    'cousins': [100, 100, 93, 79, 64, 100, 100, 100],
    'friends': [70, 72, 68, 75, 74, 77, 76, 79],
    'sam': [72, 75, 70, 78, 76, 80, 79, 80],
    'priya': [55, 58, 60, 62, 60, 64, 63, 52],
  };

  /// The cache columns the server keeps: the latest confirmed rating, its
  /// day, and the trend.
  Map<String, Object?> _health(String id, {int stale = 0}) {
    final ratings = _ratings[id]!;
    final days = _days(ratings.length);
    final confirmed = ratings.sublist(0, ratings.length - 1); // last: proposed
    return {
      'health': confirmed.lastWhere((r) => r != null),
      'health_period': days[confirmed.length - 1],
      'health_trend': [
        ...confirmed.map((r) => r?.toString() ?? '-'),
        '-',
      ].join(','),
      'stale_days': stale,
    };
  }

  /// Minutes in the last 24 hours and 7 days, up to [lastCompaction].
  Map<String, Object?> _time(int day, int week) => {
    'minutes_24h': day,
    'minutes_7d': week,
  };

  Map<String, List<Assessment>> get assessments => {
    for (final MapEntry(key: id, value: ratings) in _ratings.entries)
      id: [
        for (final (i, day) in _days(ratings.length).indexed)
          Assessment(
            goalId: id,
            day: day,
            rating: ratings[i],
            method: switch (id) {
              'tofu' => 'subjective',
              'cook' || 'neighbor' || 'overall' || 'friends' => 'rollup',
              _ => 'metric',
            },
            status: i == ratings.length - 1 ? 'proposed' : 'confirmed',
            explanation: ratings[i] == null || id == 'tofu'
                ? null
                : _explanation(id, ratings[i]!),
            rationale: ratings[i] == null ? 'Away at a conference' : null,
          ),
      ],
  };

  String _explanation(String id, int rating) => switch (id) {
    'tracker' => '${rating * 6 ~/ 60}h of 10h in the last 7 days → $rating',
    'wake' =>
      rating == 100
          ? 'Started 06:55; by 07:00 with 10 min grace → 100'
          : 'Started later than 07:10 → $rating',
    'host' || 'parents' || 'cousins' =>
      rating == 100
          ? '1 of 1 in the last ${id == 'parents' ? 60 : 7} days → 100'
          : '0 of 1 in the last 7 days; met until a few days ago → $rating',
    'cook' => 'Lowest of 1 sub-goal → $rating',
    'sam' || 'priya' => 'Traits, part by part, over the last 30 days → $rating',
    _ => 'Mean of 2 sub-goals → $rating',
  };

  /// The [count] days that ended most recently, oldest first.
  List<String> _days(int count) => [
    for (var back = count; back >= 1; back--)
      () {
        final d = _today.subtract(Duration(days: back));
        return '${d.year.toString().padLeft(4, '0')}-'
            '${d.month.toString().padLeft(2, '0')}-'
            '${d.day.toString().padLeft(2, '0')}';
      }(),
  ];
}
