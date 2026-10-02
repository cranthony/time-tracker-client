import '../models/assessment.dart';
import '../models/event.dart';
import '../models/goal.dart';
import '../models/note.dart';
import '../services/events_repository.dart';
import '../services/goals_repository.dart';
import '../services/notes_repository.dart';

/// A realistic day of notes, events and goals, for trying the app's
/// features without a server -- `flutter run --dart-define=SAMPLE_DATA=true`
/// -- and for the visual tests in test/visual. Everything is dated relative
/// to [now], so the sample never goes stale.
///
/// The goals cover what the Goals page can show: every status, sub-goals,
/// own and inherited colors, health with a sparkline, periods gone
/// unassessed, a skipped period, and a proposed rating not yet confirmed.
class SampleData {
  SampleData(this.now);

  final DateTime now;

  DateTime get _today => DateTime(now.year, now.month, now.day);
  DateTime _at(int hour, [int minute = 0, int dayOffset = 0]) =>
      _today.add(Duration(days: dayOffset, hours: hour, minutes: minute));

  NotesRepository notesRepository() => InMemoryNotesRepository(notes);
  EventsRepository eventsRepository() => InMemoryEventsRepository(events);
  GoalsRepository goalsRepository() =>
      InMemoryGoalsRepository(goals, assessments);

  List<Note> get notes => [
    Note(timestamp: _at(7, 5), description: 'Up, a little late'),
    Note(timestamp: _at(9, 40), description: 'Started on the goals page'),
    Note(timestamp: _at(12, 15), description: 'Lunch, finally'),
  ];

  List<Event> get events => [
    _event('sleep', 'Sleep', _at(23, 0, -1), _at(7, 0), sleep: true),
    _event('morning', 'Morning routine', _at(7, 0), _at(8, 0), goals: ['wake']),
    _event(
      'work',
      'Time Tracker: goals page',
      _at(8, 0),
      _at(12, 0),
      goals: ['tracker'],
    ),
    _event('lunch', 'Lunch', _at(12, 0), _at(13, 0)),
    _event('class', 'Cooking class', _at(14, 0), _at(16, 0), goals: ['tofu']),
    _event(
      'dinner',
      'Dinner with Sam & Priya',
      _at(18, 30),
      _at(21, 0),
      goals: ['host', 'tofu'],
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
  }) => Event.fromJson({
    'id': id,
    'summary': summary,
    'start': localIsoTimestamp(start),
    'end': localIsoTimestamp(end),
    'is_cancelled': false,
    'goal_ids': goals,
    'goal_names': [for (final g in goals) _names[g]],
    if (sleep) 'is_end_of_day_sleep': true,
  });

  static const _names = {
    'tracker': 'Make a Time Tracker app',
    'wake': 'Wake up at 7am',
    'host': 'Host friends weekly',
    'cook': 'Learn vegetarian cooking',
    'tofu': 'Tofu tikka masala',
  };

  List<Goal> get goals => [
    Goal.fromJson({
      'id': 'tracker',
      'name': _names['tracker'],
      'status': 'active',
      'background_color': '#8e24aa',
      'effective_color': '#8e24aa',
      'priority': 1,
      'cadence': 'weekly',
      'measure': {'kind': 'duration', 'target_min': 600},
      ..._health('tracker'),
    }),
    Goal.fromJson({
      'id': 'wake',
      'name': _names['wake'],
      'status': 'active',
      'effective_color': '#039be5',
      'priority': 0,
      'fixed_time': true,
      'cadence': 'daily',
      'measure': {'kind': 'wake_time', 'target': '07:00', 'grace_min': 10},
      ..._health('wake', stale: 2),
    }),
    Goal.fromJson({
      'id': 'host',
      'name': _names['host'],
      'status': 'active',
      'background_color': '#f4511e',
      'effective_color': '#f4511e',
      'cadence': 'weekly',
      'measure': {'kind': 'count', 'target': 1, 'noun': 'dinners'},
      ..._health('host'),
    }),
    Goal.fromJson({
      'id': 'cook',
      'name': _names['cook'],
      'status': 'active',
      'background_color': '#33b679',
      'effective_color': '#33b679',
      'cadence': 'monthly',
      'measure': {'kind': 'rollup', 'agg': 'min'},
      ..._health('cook'),
    }),
    Goal.fromJson({
      'id': 'tofu',
      'parent_id': 'cook',
      'name': _names['tofu'],
      'status': 'active',
      'effective_color': '#33b679',
      'cadence': 'weekly',
      'measure': {'kind': 'subjective', 'prompt': 'How did it turn out?'},
      ..._health('tofu'),
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
      'cadence': 'weekly',
    }),
    Goal.fromJson({'id': '10k', 'name': 'Run a 10k', 'status': 'completed'}),
    Goal.fromJson({
      'id': 'old',
      'name': 'Old side project',
      'status': 'archived',
    }),
    Goal.fromJson({'id': 'typo', 'name': 'Typo goal', 'status': 'deleted'}),
  ];

  /// Each assessed goal's ratings over its last 8 periods, oldest first;
  /// null is a skipped period. The last is proposed, not yet confirmed.
  static const _ratings = {
    'tracker': [55, 62, null, 70, 78, 74, 88, 82],
    'wake': [100, 92, 60, 30, 100, 84, 64, 50],
    'host': [100, 0, 100, 100, 0, 100, 100, 100],
    'cook': [40, 45, 52, 58, 61, 66, 72, 75],
    'tofu': [20, 35, 50, 45, 60, 70, 65, 80],
  };

  static const _cadences = {
    'tracker': 'weekly',
    'wake': 'daily',
    'host': 'weekly',
    'cook': 'monthly',
    'tofu': 'weekly',
  };

  /// The cache columns the server keeps: the latest confirmed rating, its
  /// period, and the trend.
  Map<String, Object?> _health(String id, {int stale = 0}) {
    final ratings = _ratings[id]!;
    final periods = _periods(_cadences[id]!, ratings.length);
    final confirmed = ratings.sublist(0, ratings.length - 1); // last: proposed
    return {
      'health': confirmed.lastWhere((r) => r != null),
      'health_period': periods[confirmed.length - 1],
      'health_trend': [
        ...confirmed.map((r) => r?.toString() ?? '-'),
        '-',
      ].join(','),
      'stale_periods': stale,
    };
  }

  Map<String, List<Assessment>> get assessments => {
    for (final MapEntry(key: id, value: ratings) in _ratings.entries)
      id: [
        for (final (i, period) in _periods(
          _cadences[id]!,
          ratings.length,
        ).indexed)
          Assessment(
            goalId: id,
            cadence: _cadences[id],
            period: period,
            rating: ratings[i],
            method: id == 'tofu' ? 'subjective' : 'metric',
            status: i == ratings.length - 1 ? 'proposed' : 'confirmed',
            explanation: ratings[i] == null || id == 'tofu'
                ? null
                : _explanation(id, ratings[i]!),
            rationale: ratings[i] == null ? 'Away at a conference' : null,
          ),
      ],
  };

  String _explanation(String id, int rating) => switch (id) {
    'tracker' => '${rating * 6 ~/ 60}h of 10h target → $rating',
    'wake' =>
      rating == 100
          ? 'Woke 06:55; target 07:00 with 10 min grace → 100'
          : 'Woke later than 07:10 → $rating',
    'host' => '${rating ~/ 100} of 1 dinners → $rating',
    _ => 'Min of its sub-goals → $rating',
  };

  /// The ids of the [count] periods of [cadence] that ended most recently,
  /// oldest first.
  List<String> _periods(String cadence, int count) {
    String day(DateTime d) =>
        '${d.year.toString().padLeft(4, '0')}-'
        '${d.month.toString().padLeft(2, '0')}-'
        '${d.day.toString().padLeft(2, '0')}';
    final ids = <String>[];
    for (var back = count; back >= 1; back--) {
      ids.add(switch (cadence) {
        'daily' => day(_today.subtract(Duration(days: back))),
        'weekly' => 'week-${day(_sunday.subtract(Duration(days: 7 * back)))}',
        _ => () {
          final month = DateTime(_today.year, _today.month - back);
          return '${month.year}-${month.month.toString().padLeft(2, '0')}';
        }(),
      });
    }
    return ids;
  }

  /// The Sunday this week started on.
  DateTime get _sunday => _today.subtract(Duration(days: _today.weekday % 7));
}
