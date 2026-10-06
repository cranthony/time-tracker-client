import '../models/event.dart';
import '../models/facts.dart';
import '../models/goal.dart';
import '../models/note.dart';
import '../models/person.dart';
import '../models/recurrence.dart';
import '../models/trait.dart';
import '../services/events_repository.dart';
import '../services/goals_repository.dart';
import '../services/notes_repository.dart';
import '../services/people_repository.dart';
import '../services/traits_repository.dart';

/// A realistic day of notes, events and a plan -- traits, people and
/// actions -- for trying the app's features without a server (`flutter
/// run --dart-define=SAMPLE_DATA=true`) and for the visual tests in
/// test/visual. Everything is dated relative to [now], so the sample never
/// goes stale.
///
/// The actions are a tree of groups (Sleep-related, Food-related, Social,
/// Creative › Guitar...) with actions as its leaves: own and inherited
/// colors and priorities, actions Claude proposed and an archived one.
/// Besides today's events, the week around it has a routine (sleep,
/// work, meals, TV) and the events with people that their histories
/// tell of, with the plans to come, for the summaries to measure. The people are Self and six others in five
/// circles, from healthy to disconnected (and one archived), each rated by
/// five traits made of judgments and cadences -- Self by four, Sam with a
/// cadence of their own -- with Claude's judgments of their recent events
/// behind each score; and the locations those events were at.
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
      InMemoryEventsRepository([...events, ...week], recurrences);
  GoalsRepository goalsRepository() => InMemoryGoalsRepository(goals);
  PeopleRepository peopleRepository() => InMemoryPeopleRepository(
    people: people,
    circles: circles,
    locations: locations,
  );

  /// The traits; a week of their scores across everyone; and each
  /// person's latest rating, part by part, and their history.
  TraitsRepository traitsRepository() => InMemoryTraitsRepository(
    traits: traits,
    history: [
      for (final trait in traits)
        if (trait.status == 'active')
          for (var back = 7; back >= 1; back--)
            () {
              final scores = {
                for (final id in _ratedPeople)
                  if (_traitScore(id, trait.id!) case final score?)
                    id: (score - (back - 1) * _drift(id, trait.id!)).clamp(
                      0,
                      100,
                    ),
              };
              return TraitDay(
                traitId: trait.id!,
                name: trait.name,
                day: _day(_today.subtract(Duration(days: back))),
                score: scores.isEmpty
                    ? 0
                    : (scores.values.reduce((a, b) => a + b) / scores.length)
                          .round(),
                people: scores,
              );
            }(),
    ],
    ratings: {for (final id in _ratedPeople) id: _rating(id)},
    digests: {for (final id in _ratedPeople) id: _digest(id)},
  );

  // ---------------------------------------------------------------- Traits

  /// The ratings of Adventurous's judgment, as the server seeds it.
  static const _novelty = {
    '0': 'The activity and place were routine',
    '1': 'There was a twist on the activity or place',
    '2': 'The activity or the place were new',
    '3':
        'Both the activity and place were new, or the event was otherwise '
        'adventurous',
  };

  /// The traits: four made of judgments -- one with continuity beside
  /// it -- one of a cadence and follow-through, and one turned off.
  List<Trait> get traits => const [
    Trait(
      id: 'adventurous',
      name: 'Adventurous',
      definition: 'Try new things and new places, together.',
      parts: [
        {
          'kind': 'judgment',
          'rubric': 'Was this activity or place new?',
          'ratings': _novelty,
          'facts': [
            'action',
            {'fact': 'action_history', 'lookback_days': 90},
            'location',
            {'fact': 'location_history', 'lookback_days': 180},
          ],
        },
      ],
    ),
    Trait(
      id: 'thoughtful',
      name: 'Thoughtful',
      definition: 'Remember what matters to them, and act on it.',
      parts: [
        {
          'kind': 'judgment',
          'engagement_type': 'for',
          'rubric': 'Did this reflect what matters to them?',
          'ratings': {
            '0': 'Nothing about it was for them in particular',
            '1': 'It took them into account',
            '2': 'It was shaped around what matters to them',
            '3': 'It showed specific, remembered care for them',
          },
          'facts': ['action', 'general_notes', 'person_notes'],
        },
        {'kind': 'continuity', 'last_within_days': 14, 'next_within_days': 14},
      ],
    ),
    Trait(
      id: 'creative',
      name: 'Creative',
      definition: 'Make things, alone and together.',
      parts: [
        {
          'kind': 'judgment',
          'rubric': 'Was something made?',
          'ratings': {
            '0': 'Nothing was made',
            '1': 'We riffed on something that already existed',
            '2': 'We made something',
            '3': "We made something new, that neither could've alone",
          },
          'facts': ['action', 'general_notes'],
        },
      ],
    ),
    Trait(
      id: 'present',
      name: 'Present',
      definition: 'Give them my full attention.',
      parts: [
        {
          'kind': 'judgment',
          'rubric': 'How present was I?',
          'ratings': {
            '0': 'Distracted, or on my phone',
            '1': 'Partly there',
            '2': 'Mostly attentive',
            '3': 'Fully present, listening closely',
          },
          'facts': ['general_notes', 'person_notes'],
        },
      ],
    ),
    Trait(
      id: 'reliable',
      name: 'Reliable',
      definition: 'Keep in touch, and do what I said I would.',
      parts: [
        {'kind': 'count', 'action': 'social', 'target': 1, 'interval_days': 7},
        {'kind': 'follow_through'},
      ],
    ),
    Trait(
      id: 'generous',
      name: 'Generous',
      status: 'off',
      definition: 'Make an effort for them beyond showing up.',
      parts: [
        {
          'kind': 'judgment',
          'engagement_type': 'for',
          'rubric': 'How much effort did I make for them?',
          'ratings': {
            '0': 'Showed up',
            '1': 'Some effort',
            '2': 'Prepared, cooked, hosted or traveled',
          },
          'facts': ['action', 'general_notes'],
        },
      ],
    ),
  ];

  // ---------------------------------------------------------------- People

  List<Circle> get circles => [
    for (final (id, name, note) in const [
      ('family', 'Family', null),
      ('close', 'Close friends', 'The ones I call first'),
      ('dance', 'Dance friends', 'From the Thursday salsa class'),
      ('college', 'College', null),
      ('work', 'Work', null),
    ])
      Circle.fromJson({
        'id': id,
        'name': name,
        'note': note,
        ..._healthOf([
          for (final p in _peopleSpec)
            if (p.circles.contains(id) && p.status == 'active') p.id,
        ]),
      }),
  ];

  /// Where events happen.
  List<Location> get locations => const [
    Location(id: 'home', name: 'Home', hint: "the apartment; 'my place'"),
    Location(id: 'hall', name: 'The hall', hint: 'the salsa social, Thursdays'),
    Location(id: 'noodles', name: 'The noodle bar', hint: 'on Fifth'),
    Location(id: 'cellar', name: 'The Cellar', hint: 'the jazz club'),
    Location(id: 'school', name: 'The culinary school'),
    Location(id: 'ramen', name: 'Ramen Ya'),
    Location(id: 'trail', name: 'The river trail'),
    Location(id: 'cafe', name: 'The café', hint: 'by the office'),
    Location(id: 'jordans', name: "Jordan's place"),
  ];

  static const _peopleSpec = [
    (
      id: selfPersonId,
      name: 'Self',
      context: null,
      circles: <String>[],
      status: 'active',
      whatMatters:
          '- Wants more time making things, and less on screens\n'
          '- Learning to sing harmonies',
    ),
    (
      id: 'sam',
      name: 'Sam',
      context: 'from salsa',
      circles: ['close', 'dance'],
      status: 'active',
      whatMatters:
          '- Training for a half marathon in the spring\n'
          '- Starts a new job next month',
    ),
    (
      id: 'priya',
      name: 'Priya',
      context: null,
      circles: ['close', 'college'],
      status: 'active',
      whatMatters: '- Loves jazz, and trying new restaurants',
    ),
    (
      id: 'mom',
      name: 'Mom',
      context: null,
      circles: ['family'],
      status: 'active',
      whatMatters: '- Knee surgery on the 20th: call after',
    ),
    (
      id: 'dad',
      name: 'Dad',
      context: null,
      circles: ['family'],
      status: 'active',
      whatMatters: '- Restoring an old sailboat',
    ),
    (
      id: 'alex',
      name: 'Alex',
      context: 'design team',
      circles: ['work'],
      status: 'active',
      whatMatters: '',
    ),
    (
      id: 'jordan',
      name: 'Jordan',
      context: null,
      circles: ['dance'],
      status: 'active',
      whatMatters: '- Moved across town in the summer',
    ),
    (
      id: 'casey',
      name: 'Casey',
      context: 'old roommate',
      circles: ['college'],
      status: 'archived',
      whatMatters: '',
    ),
  ];

  /// Everyone rated by the traits: the active people.
  static final _ratedPeople = [
    for (final p in _peopleSpec)
      if (p.status == 'active') p.id,
  ];

  /// Which traits apply to each person who isn't rated as everyone is:
  /// Self isn't held to Reliable, and Sam has a cadence of their own -- a
  /// call or more every two weeks.
  static const _personTraits = {
    selfPersonId: PersonTraits(
      select: ['adventurous', 'thoughtful', 'creative', 'present'],
    ),
    'sam': PersonTraits(
      parts: {
        'reliable': [
          {
            'kind': 'count',
            'action': 'call',
            'target': 1,
            'interval_days': 14,
            'noun': 'calls',
          },
          {'kind': 'follow_through'},
        ],
      },
    ),
  };

  List<Person> get people => [
    for (final p in _peopleSpec)
      Person.fromJson({
        'id': p.id,
        'name': p.name,
        'context': p.context,
        'status': p.status,
        'circles': p.circles,
        'what_matters': p.whatMatters,
        'traits': _personTraits[p.id]?.toJson(),
        if (p.status == 'active') ..._healthOf([p.id]),
      }),
  ];

  /// The health of [ids] together, as a person's or a circle's: their
  /// mean rating, and their last 8 days.
  Map<String, Object?> _healthOf(List<String> ids) {
    final rated = [
      for (final id in ids)
        if (_rating(id).rating case final r?) (id, r),
    ];
    if (rated.isEmpty) return const {};
    final health =
        (rated.map((r) => r.$2).reduce((a, b) => a + b) / rated.length).round();
    // Drifting toward today: up for those doing better, down for the rest.
    final slope = rated.length == 1 ? _drift(rated.single.$1, 'present') : 1;
    return {
      'health': health,
      'health_trend': [
        for (var back = 7; back >= 0; back--)
          back == 4 && ids.length == 1 && ids.single == 'dad'
              ? '-'
              : '${(health - back * slope).clamp(0, 100)}',
      ].join(','),
    };
  }

  /// How fast [id]'s score of [traitId] has been changing, a day: those
  /// drifting apart, down.
  static int _drift(String id, String traitId) => switch (id) {
    'jordan' || 'dad' => -3,
    'alex' => -1,
    _ => (traitId.length % 3) + 1,
  };

  // ------------------------------------------------------- Ratings, digests

  /// The past events: what was done (action ids), who was there and who
  /// it was for, where, the notes on each person, and Claude's judgments
  /// by trait id, of everyone it judged.
  late final List<_PastEvent> _past = [
    _PastEvent(
      'jazz',
      'Jazz night',
      9,
      20,
      actions: ['listen_music'],
      withIds: ['sam', 'priya'],
      location: 'cellar',
      notes: {
        selfPersonId: 'First time at a jazz club, for all three of us',
        'priya': 'Lit up at the trumpet solo',
      },
      judgments: {
        'adventurous': (3, 'A new kind of night out, somewhere new'),
        'present': (3, 'Phones away all night'),
      },
    ),
    _PastEvent(
      'gift',
      'Wrap a birthday present',
      6,
      18,
      actions: ['wrap_gift'],
      forIds: ['sam'],
      location: 'home',
      notes: {selfPersonId: 'The running watch Sam mentioned in the spring'},
      judgments: {
        'thoughtful': (3, 'Remembered the half marathon, months later'),
      },
    ),
    _PastEvent(
      'dumplings',
      'Cook dumplings',
      4,
      18,
      actions: ['cook_lunch_dinner', 'deep_talk'],
      withIds: ['sam'],
      location: 'home',
      notes: {
        selfPersonId: 'Folded them together; talked about the new job',
        'sam': 'Nervous about the new team',
      },
      judgments: {
        'creative': (2, 'Made dinner together from scratch'),
        'present': (3, 'Long, unhurried talk'),
        'adventurous': (1, 'A new recipe, in the usual kitchen'),
      },
    ),
    _PastEvent(
      'salsa',
      'Salsa social',
      1,
      20,
      actions: ['dance_class', 'shallow_talk'],
      withIds: ['sam'],
      location: 'hall',
      judgments: {
        'adventurous': (0, 'The usual social, at the usual hall'),
        'present': (2, 'Danced with everyone, chatted between'),
      },
    ),
    _PastEvent(
      'class',
      'Cooking class',
      2,
      14,
      actions: ['cooking_class'],
      withIds: ['priya'],
      location: 'school',
      notes: {selfPersonId: 'Knife skills; the first class there for both'},
      judgments: {
        'adventurous': (2, 'A new place for both'),
        'creative': (1, "Followed the chef's recipe"),
        'present': (2, 'Mostly focused on the onions'),
      },
    ),
    _PastEvent(
      'ramen',
      'Ramen at the new place',
      11,
      19,
      actions: ['eat_meal', 'shallow_talk'],
      withIds: ['priya'],
      location: 'ramen',
      notes: {selfPersonId: 'Checked my phone a few times'},
      judgments: {
        'adventurous': (1, 'A new restaurant, but a usual dinner'),
        'present': (1, 'Checked phone a few times'),
      },
    ),
    _PastEvent(
      'mom_call',
      'Call Mom',
      3,
      13,
      actions: ['call'],
      withIds: ['mom'],
      notes: {'mom': 'Worried about the knee surgery'},
      judgments: {'present': (2, 'Listened, while making lunch')},
    ),
    _PastEvent(
      'parents_video',
      'Video call with Mom and Dad',
      12,
      19,
      actions: ['video_call'],
      withIds: ['mom', 'dad'],
      notes: {'dad': 'Showed the sailboat'},
      judgments: {'present': (3, 'Gave the whole hour')},
    ),
    _PastEvent(
      'guitar',
      'Practice guitar',
      1,
      21,
      actions: ['practice_guitar'],
      location: 'home',
      notes: {selfPersonId: 'Wrote a new chord progression'},
      judgments: {
        'creative': (3, 'Something new of my own'),
        'present': (3, 'An hour without the phone'),
      },
    ),
    _PastEvent(
      'trail',
      'Walk a new trail',
      2,
      7,
      actions: ['walk'],
      location: 'trail',
      judgments: {
        'adventurous': (2, 'A trail never walked before'),
        'present': (2, 'Listened to a podcast half the way'),
      },
    ),
    _PastEvent(
      'singing',
      'Sing for fun',
      5,
      20,
      actions: ['sing_for_fun'],
      location: 'home',
      judgments: {
        'creative': (1, 'Sang along to old favorites'),
        'adventurous': (0, 'Routine'),
      },
    ),
    _PastEvent(
      'party',
      "Jordan's housewarming",
      28,
      19,
      actions: ['shallow_talk'],
      withIds: ['jordan'],
      location: 'jordans',
      notes: {'jordan': 'Hard to talk; left early'},
      judgments: {
        'present': (1, 'Small talk across a crowded room'),
        'adventurous': (0, 'A party like any other'),
      },
    ),
    _PastEvent(
      'coffee',
      'Coffee with Alex',
      25,
      10,
      actions: ['shallow_talk'],
      withIds: ['alex'],
      location: 'cafe',
      judgments: {
        'present': (2, 'A good chat'),
        'adventurous': (0, 'The usual cafe'),
      },
    ),
  ];

  /// [id]'s events, oldest first: Self is at every one.
  List<_PastEvent> _eventsOf(String id) => [
    for (final e in _past)
      if (id == selfPersonId || e.withIds.contains(id) || e.forIds.contains(id))
        e,
  ]..sort((a, b) => b.daysAgo.compareTo(a.daysAgo));

  /// [id]'s parts for [trait]: their own, or the trait's.
  List<Part> _partsOf(String id, Trait trait) =>
      _personTraits[id]?.parts[trait.id] ?? trait.parts;

  /// [id]'s score of [trait], part by part, as the server would work it
  /// out; null if no part has anything to rate it by.
  TraitScore? _traitScoreOf(String id, Trait trait) {
    final events = _eventsOf(id);
    final parts = <PartScore>[];
    final keys = <String, int>{};
    for (final part in _partsOf(id, trait)) {
      final kind = part['kind'] as String;
      final n = keys.update(kind, (n) => n + 1, ifAbsent: () => 1);
      final key = n == 1 ? kind : '$kind#$n';
      switch (kind) {
        case 'judgment':
          final top = judgmentRatings(part).last.score;
          // Self is judged for everything they're at; others by whether
          // they were there, or had it done for them.
          final engaged = part['engagement_type'] == 'for'
              ? (_PastEvent e) => e.forIds.contains(id)
              : (_PastEvent e) => id == selfPersonId || e.withIds.contains(id);
          final judged = [
            for (final e in events)
              if (e.daysAgo <= 30 && engaged(e))
                if (e.judgments[trait.id] case (final rating, final why))
                  Judgment(
                    eventId: '$id-${e.key}',
                    personId: id,
                    traitId: trait.id!,
                    part: key,
                    rating: rating,
                    scale: top,
                    reasoning: why,
                  ),
          ];
          final mean = judged.isEmpty
              ? null
              : judged.map((j) => j.rating).reduce((a, b) => a + b) /
                    judged.length;
          parts.add(
            PartScore(
              key: key,
              kind: kind,
              rubric: part['rubric'] as String?,
              score: mean == null ? null : (mean / top * 100).round(),
              said: mean == null
                  ? 'Nothing to rate in the last 30 days'
                  : 'Mean rating ${mean.toStringAsFixed(1)} of $top over '
                        '${judged.length} event${judged.length == 1 ? '' : 's'} '
                        'in the last 30 days',
              eventIds: [for (final j in judged) j.eventId!],
              judgments: judged,
            ),
          );
        case 'count':
          final days = (part['interval_days'] as num?) ?? 30;
          final action = part['action'];
          // A group counts the actions in it.
          final counts = action == null
              ? null
              : {
                  action,
                  for (final row in _tree)
                    if (row.$3 == action) row.$1,
                };
          final counted = [
            for (final e in events)
              if (e.daysAgo < days &&
                  (counts == null || e.actions.any(counts.contains)))
                e,
          ];
          final target = part['target'] as num;
          parts.add(
            PartScore(
              key: key,
              kind: kind,
              score: (counted.length / target * 100).clamp(0, 100).round(),
              said:
                  '${counted.length} of $target '
                  '${part['noun'] ?? (_names[action] ?? 'event').toLowerCase()} '
                  'in the last $days days',
              eventIds: [for (final e in counted) '$id-${e.key}'],
            ),
          );
        case 'continuity':
          final last = events.isEmpty ? null : events.last.daysAgo;
          final within = (part['last_within_days'] as num?) ?? 14;
          final recent = last != null && last <= within;
          parts.add(
            PartScore(
              key: key,
              kind: kind,
              score: recent ? 50 : 0,
              said: [
                last == null ? 'No event yet' : 'Last $last days ago',
                'nothing planned',
                '(within $within days)',
              ].join('; '),
              eventIds: [if (recent) '$id-${events.last.key}'],
            ),
          );
        case 'follow_through':
          parts.add(
            PartScore(
              key: key,
              kind: kind,
              score: id == 'dad' ? 75 : 100,
              said: id == 'dad'
                  ? '1 cancelled in the last 30 days, from 100'
                  : 'Nothing cancelled in the last 30 days',
            ),
          );
      }
    }
    final scored = [
      for (final p in parts)
        if (p.score != null) p,
    ];
    return TraitScore(
      traitId: trait.id!,
      name: trait.name,
      score: scored.isEmpty
          ? null
          : (scored.map((p) => p.score!).reduce((a, b) => a + b) /
                    scored.length)
                .round(),
      parts: parts,
    );
  }

  /// Whether [traitId] applies to [id].
  static bool _applies(String id, String traitId) =>
      _personTraits[id]?.applies(traitId) ?? true;

  int? _traitScore(String id, String traitId) => _applies(id, traitId)
      ? _traitScoreOf(id, traits.firstWhere((t) => t.id == traitId))?.score
      : null;

  TraitsRating _rating(String id) {
    final scores = [
      for (final trait in traits)
        if (trait.status == 'active' && _applies(id, trait.id!))
          ?_traitScoreOf(id, trait),
    ];
    final rated = [
      for (final s in scores)
        if (s.score != null) s.score!,
    ];
    final mean = rated.isEmpty
        ? null
        : (rated.reduce((a, b) => a + b) / rated.length).round();
    return TraitsRating(
      rating: mean,
      day: _day(_today.subtract(const Duration(days: 1))),
      explanation:
          'Traits (${scores.map((t) => '${t.name} ${t.score}').join(', ')}) '
          '→ $mean',
      traits: scores,
      leftOut: [
        for (final trait in traits)
          if (trait.status != 'active' || !_applies(id, trait.id!)) trait.name,
      ],
    );
  }

  PersonDigest _digest(String id) {
    final events = _eventsOf(id);
    List<DigestEntry> entries(Iterable<(String, int)> seen) {
      final byLabel = <String, List<int>>{};
      for (final (label, daysAgo) in seen) {
        (byLabel[label] ??= []).add(daysAgo);
      }
      return [
        for (final MapEntry(key: label, value: days) in byLabel.entries)
          DigestEntry(
            label: label,
            count: days.length,
            first: _day(_today.subtract(Duration(days: days.reduce(_max)))),
            last: _day(_today.subtract(Duration(days: days.reduce(_min)))),
          ),
      ]..sort((a, b) => b.count.compareTo(a.count));
    }

    return PersonDigest(
      personId: id,
      eventsCounted: events.length,
      actions: entries([
        for (final e in events)
          for (final a in e.actions) (a, e.daysAgo),
      ]),
      locations: entries([
        for (final e in events)
          if (e.location case final where?) (where, e.daysAgo),
      ]),
      events: [
        for (final e in events)
          {
            'id': '$id-${e.key}',
            'summary': e.summary,
            'start': localIsoTimestamp(_at(e.hour, 0, -e.daysAgo)),
            'end': localIsoTimestamp(_at(e.hour + 1, 0, -e.daysAgo)),
            'action_ids': e.actions,
            'facts': e.facts.toJson(),
          },
      ],
    );
  }

  static int _max(int a, int b) => a > b ? a : b;
  static int _min(int a, int b) => a < b ? a : b;

  static String _day(DateTime day) =>
      '${day.year}-${day.month.toString().padLeft(2, '0')}-'
      '${day.day.toString().padLeft(2, '0')}';

  // ---------------------------------------------------------------- Actions

  List<Note> get notes => [
    Note(timestamp: _at(7, 50), description: 'Running a little late'),
    Note(timestamp: _at(9, 40), description: 'Started on the plan page'),
    Note(timestamp: _at(12, 15), description: 'Lunch with Sam, finally'),
  ];

  /// The weeks before and after today, other than today itself: a
  /// routine each day, then the events with people their histories have,
  /// and some plans.
  List<Event> get week => [
    for (var day = -8; day <= 7; day++)
      if (day != 0) ...[
        // Tonight's sleep is today's last event; last night's, its first.
        if (day != -1)
          _event(
            'sleep$day',
            'Sleep',
            _at(23, 0, day),
            _at(7, 0, day + 1),
            actions: ['sleep'],
            sleep: true,
            priority: 3,
          ),
        _event(
          'up$day',
          'Get up and get ready',
          _at(7, 0, day),
          _at(7, 45, day),
          actions: ['get_up'],
          priority: 0,
        ),
        if (_today.add(Duration(days: day)).weekday <= DateTime.friday)
          _event(
            'work$day',
            'Work',
            _at(8, 30, day),
            _at(17, 0, day),
            actions: ['work'],
            priority: 1,
          ),
        _event(
          'dinner$day',
          'Dinner',
          _at(19, 0, day),
          _at(19, 45, day),
          actions: ['cook_lunch_dinner', 'eat_meal'],
          priority: 2,
        ),
        _event(
          'tv$day',
          'TV',
          _at(21, 30, day),
          _at(22, 30, day),
          actions: ['watch_tv'],
        ),
      ],
    for (final e in _past)
      if (e.daysAgo > 0)
        _event(
          'past-${e.key}',
          e.summary,
          _at(e.hour, 0, -e.daysAgo),
          _at(e.hour + 1, 0, -e.daysAgo),
          actions: e.actions,
          facts: e.facts,
        ),
    _event(
      'next-salsa',
      'Salsa social',
      _at(20, 0, 3),
      _at(22, 0, 3),
      actions: ['dance_class'],
      priority: 2,
      facts: const Facts(withIds: ['sam', 'jordan'], locationId: 'hall'),
    ),
    _event(
      'next-ramen',
      'Dinner with Priya',
      _at(18, 30, 2),
      _at(20, 0, 2),
      actions: ['eat_meal', 'deep_talk'],
      priority: 2,
      facts: const Facts(withIds: ['priya'], locationId: 'ramen'),
    ),
    _event(
      'next-parents',
      'Video call with Mom and Dad',
      _at(10, 0, 5),
      _at(11, 0, 5),
      actions: ['video_call'],
      priority: 2,
      facts: const Facts(withIds: ['mom', 'dad']),
    ),
  ];

  List<Event> get events => [
    _event(
      'sleep',
      'Sleep',
      _at(23, 0, -1),
      _at(7, 0),
      actions: ['sleep'],
      sleep: true,
      priority: 3,
    ),
    _event(
      'morning_today',
      'Get up and get ready',
      _at(7, 0),
      _at(7, 45),
      actions: ['get_up'],
      series: 'morning',
      priority: 0,
    ),
    _event(
      'breakfast',
      'Breakfast',
      _at(7, 45),
      _at(8, 15),
      actions: ['cook_breakfast', 'eat_meal'],
      priority: 2,
    ),
    _event(
      'work',
      'Time Tracker: plan page',
      _at(8, 15),
      _at(12, 0),
      actions: ['work'],
      priority: 1,
    ),
    _event(
      'lunch',
      'Lunch with Sam',
      _at(12, 0),
      _at(13, 0),
      actions: ['eat_meal', 'deep_talk'],
      priority: 2,
      facts: const Facts(
        withIds: ['sam'],
        locationId: 'noodles',
        notes: {
          selfPersonId: 'Talked through the job offer; phones away',
          'sam': 'Excited, and a little anxious',
        },
      ),
    ),
    // Too short for their text: drawn taller, and pushed down.
    _event(
      'call',
      'Call Mom',
      _at(13, 0),
      _at(13, 5),
      actions: ['call'],
      priority: 2,
      facts: const Facts(withIds: ['mom']),
    ),
    _event('texts', 'Texts', _at(13, 5), _at(13, 15), actions: ['text']),
    // In the same color as the one before: a seam divides them.
    _event(
      'scroll',
      'Doomscroll',
      _at(13, 15),
      _at(13, 35),
      actions: ['doomscroll'],
    ),
    // Never given actions: its action is inferred from its label.
    _event(
      'class',
      'Cooking class',
      _at(14, 0),
      _at(16, 0),
      actions: ['cooking_class'],
      fromLabel: true,
      priority: 2,
    ),
    _event(
      'dinner',
      'Dinner with Sam & Priya',
      _at(18, 30),
      _at(21, 0),
      actions: ['cook_lunch_dinner', 'eat_meal', 'deep_talk'],
      priority: 2,
      facts: const Facts(
        withIds: ['sam', 'priya'],
        locationId: 'home',
        notes: {selfPersonId: 'Made dal and naan from scratch'},
      ),
    ),
    _event(
      'guitar',
      'Guitar',
      _at(21, 0),
      _at(22, 0),
      actions: ['practice_guitar'],
      facts: const Facts(locationId: 'home'),
    ),
    _event(
      'bed',
      'Get ready for bed',
      _at(22, 0),
      _at(22, 30),
      actions: ['get_ready_for_bed'],
    ),
  ];

  Event _event(
    String id,
    String summary,
    DateTime start,
    DateTime end, {
    List<String> actions = const [],
    bool sleep = false,
    String? series,
    bool fromLabel = false,
    int? priority,
    Facts? facts,
  }) => Event.fromJson({
    'id': id,
    'summary': summary,
    'start': localIsoTimestamp(start),
    'end': localIsoTimestamp(end),
    'is_cancelled': false,
    'action_ids': actions,
    'action_names': [for (final a in actions) _names[a]],
    if (sleep) 'is_end_of_day_sleep': true,
    'recurring_event_id': ?series,
    if (fromLabel) 'actions_from_label': true,
    'effective_priority': ?priority,
    'facts': ?facts?.toJson(),
  });

  /// The series "Get up and get ready" is part of: every weekday since a
  /// month ago.
  List<Recurrence> get recurrences => [
    Recurrence.fromJson({
      'id': 'morning',
      'summary': 'Get up and get ready',
      'start': localIsoTimestamp(_at(7, 0, -28)),
      'end': localIsoTimestamp(_at(7, 45, -28)),
      'time_zone': 'America/New_York',
      'repeat': {
        'every': 'week',
        'weekdays': ['mon', 'tue', 'wed', 'thu', 'fri'],
      },
      'schedule': 'Every week on Mon, Tue, Wed, Thu, Fri',
      'action_ids': ['get_up'],
      'action_names': [_names['get_up']],
      'is_fixed_time': true,
    }),
  ];

  /// When notes were last compacted, which actions' recent time is
  /// counted up to.
  DateTime get lastCompaction => _at(7, 30);

  /// The last compacted note: before [notes], which aren't yet.
  Note get latestCompacted => Note(
    timestamp: _at(22, 40, -1),
    description: 'Lights out',
    compactionId: 'sample',
  );

  /// The tree: (id, name, parent, whether it's a group, and the rest of
  /// its fields), parents first. Groups are names that roll up what's in
  /// them; actions, its leaves, are what events are given.
  static const _tree = <(String, String, String?, bool, Map<String, Object?>)>[
    (
      'sleep_related',
      'Sleep-related',
      null,
      true,
      {'background_color': '#3f51b5', 'priority': 3},
    ),
    ('get_ready_for_bed', 'Get ready for bed', 'sleep_related', false, {}),
    ('sleep', 'Sleep', 'sleep_related', false, {}),
    ('get_up', 'Get up and get ready', 'sleep_related', false, {'priority': 0}),
    (
      'work',
      'Work',
      null,
      false,
      {'background_color': '#8e24aa', 'priority': 1},
    ),
    ('food', 'Food-related', null, true, {'background_color': '#33b679'}),
    ('eat_meal', 'Eat a meal', 'food', false, {}),
    ('eat_snack', 'Eat a snack', 'food', false, {}),
    ('drink_water', 'Drink water', 'food', false, {}),
    ('walk', 'Walk', null, false, {'background_color': '#0b8043'}),
    (
      'screens',
      'Screen logistics',
      null,
      true,
      {'background_color': '#616161'},
    ),
    ('text', 'Text', 'screens', false, {}),
    ('email', 'Email', 'screens', false, {}),
    ('doomscroll', 'Doomscroll', 'screens', false, {}),
    (
      'social',
      'Social',
      null,
      true,
      {'background_color': '#7986cb', 'priority': 2},
    ),
    ('shallow_talk', 'Shallow talk', 'social', false, {}),
    ('deep_talk', 'Deep talk', 'social', false, {}),
    ('call', 'Call', 'social', false, {}),
    ('video_call', 'Video call', 'social', false, {}),
    ('dance_class', 'Take a dance class', 'social', false, {}),
    (
      'creative',
      'Creative',
      null,
      true,
      {'background_color': '#f4511e', 'priority': 2},
    ),
    ('guitar', 'Guitar', 'creative', true, {}),
    ('play_guitar', 'Play guitar', 'guitar', false, {}),
    ('practice_guitar', 'Practice guitar', 'guitar', false, {}),
    ('singing', 'Singing', 'creative', true, {}),
    ('sing_for_fun', 'Sing for fun', 'singing', false, {}),
    ('practice_singing', 'Practice singing', 'singing', false, {}),
    ('cooking', 'Cooking', 'creative', true, {}),
    ('cook_breakfast', 'Cook breakfast', 'cooking', false, {}),
    ('cook_lunch_dinner', 'Cook lunch or dinner', 'cooking', false, {}),
    ('cooking_class', 'Take a cooking class', 'cooking', false, {}),
    (
      'entertainment',
      'Entertainment',
      null,
      true,
      {'background_color': '#e67c73', 'priority': 3},
    ),
    ('watch_tv', 'Watch TV', 'entertainment', false, {}),
    ('watch_movies', 'Watch movies', 'entertainment', false, {}),
    ('listen_music', 'Listen to music', 'entertainment', false, {}),
    // Made by Claude, for a gift it couldn't match: not reviewed yet.
    ('wrap_gift', 'Wrap a gift', null, false, {'status': 'proposed'}),
    ('read', 'Read a book', 'entertainment', false, {'status': 'proposed'}),
    ('commute', 'Commute', null, false, {'status': 'archived'}),
    ('typo', 'Tpyo', null, false, {'status': 'deleted'}),
  ];

  static final _names = {for (final (id, name, _, _, _) in _tree) id: name};

  List<Goal> get goals {
    final byId = {for (final row in _tree) row.$1: row};
    String? inherited(String? id, String field) {
      for (var at = id; at != null; at = byId[at]!.$3) {
        if (byId[at]!.$5[field] case final value?) return '$value';
      }
      return null;
    }

    return [
      for (final (id, name, parent, group, fields) in _tree)
        Goal.fromJson({
          'id': id,
          'name': name,
          'parent_id': parent,
          'status': 'active',
          if (group) 'kind': 'group',
          ...fields,
          'effective_color': inherited(id, 'background_color'),
          'effective_priority': switch (inherited(id, 'priority')) {
            final p? => int.parse(p),
            null => null,
          },
        }),
    ];
  }
}

/// A past event in someone's history: what was done (action ids), who
/// was there and who it was for, where, the notes on each person, and
/// Claude's judgments of it by trait id.
class _PastEvent {
  _PastEvent(
    this.key,
    this.summary,
    this.daysAgo,
    this.hour, {
    required this.actions,
    this.withIds = const [],
    this.forIds = const [],
    this.location,
    this.notes = const {},
    this.judgments = const {},
  });

  final String key;
  final String summary;
  final int daysAgo;
  final int hour;
  final List<String> actions;
  final List<String> withIds;
  final List<String> forIds;

  /// A location's id.
  final String? location;
  final Map<String, String> notes;
  final Map<String, (int, String)> judgments;

  Facts get facts => Facts(
    locationId: location,
    withIds: withIds,
    forIds: forIds,
    notes: notes,
  );
}
