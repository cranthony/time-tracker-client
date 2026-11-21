import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:time_tracker_client/models/event.dart';
import 'package:time_tracker_client/models/scoring.dart';
import 'package:time_tracker_client/models/trait.dart';
import 'package:time_tracker_client/models/trait_focus.dart';
import 'package:time_tracker_client/widgets/trait_focus_chip.dart';
import 'package:time_tracker_client/widgets/trait_focus_style.dart';

const _ratings = {
  '0': 'held back',
  '1': 'nothing came up',
  '2': 'sincere',
  '3': 'opened up',
};

Trait _trait({
  Object? neutral = 1,
  Map<String, Object?> scoring = const {},
  List<Part>? parts,
}) => Trait(
  id: 'open',
  name: 'Open',
  parts:
      parts ??
      [
        {
          'id': 'p1',
          'kind': 'judgment',
          'rubric': 'Did I open up?',
          'ratings': _ratings,
          'facts': ['general_notes'],
          'neutral': ?neutral,
          'scoring': scoring,
        },
      ],
);

Map<String, Object?> _judged(int rating, {int scale = 3}) => {
  'rating': rating,
  'scale': scale,
  'reasoning': 'r',
};

Event _event(
  Map<String, Map<String, Object?>> byPerson, {
  int hour = 9,
  int minutes = 60,
  bool cancelled = false,
}) {
  final start = DateTime(2026, 11, 20, hour);
  return Event(
    id: 'e$hour',
    start: start,
    end: start.add(Duration(minutes: minutes)),
    isCancelled: cancelled,
    properties: {
      'judgments': {
        for (final MapEntry(key: person, value: parts) in byPerson.entries)
          person: {'open': parts},
      },
    },
  );
}

void main() {
  group('judgmentLean', () {
    test('leans from -1 at 0 through 0 at neutral to 1 at the top', () {
      expect(judgmentLean(0, 3, 1), -1);
      expect(judgmentLean(1, 3, 1), 0);
      expect(judgmentLean(2, 3, 1), 0.5);
      expect(judgmentLean(3, 3, 1), 1);
    });

    test('a neutral at either end leans only the other way', () {
      expect(judgmentLean(0, 3, 0), 0);
      expect(judgmentLean(3, 3, 0), 1);
      expect(judgmentLean(3, 3, 3), 0);
      expect(judgmentLean(0, 3, 3), -1);
    });
  });

  test('without a neutral, the middle of the scale is', () {
    expect(judgmentNeutral({'neutral': 1}, 3), 1);
    expect(judgmentNeutral({}, 3), 1.5);
    expect(judgmentNeutral({'neutral': 9}, 3), 1.5);
    expect(judgmentNeutral(null, 4), 2);
  });

  group('eventTraitReading', () {
    test('reads its judgment by the part\'s neutral', () {
      final trait = _trait();
      expect(
        eventTraitReading(
          trait,
          _event({
            'self': {'p1': _judged(1)},
          }),
        ),
        const TraitReading(score: 33, lean: 0),
      );
      expect(
        eventTraitReading(
          trait,
          _event({
            'self': {'p1': _judged(0)},
          }),
        ),
        const TraitReading(score: 0, lean: -1),
      );
    });

    test('is the mean of the people it was about', () {
      final reading = eventTraitReading(
        _trait(),
        _event({
          'self': {'p1': _judged(3)},
          'sam': {'p1': _judged(0)},
        }),
      );
      expect(reading, const TraitReading(score: 50, lean: 0));
    });

    test('leaves out habits and other traits, and is null with none', () {
      final event = Event(
        start: DateTime(2026, 11, 20, 9),
        end: DateTime(2026, 11, 20, 10),
        properties: {
          'judgments': {
            'habit:h1': {
              'open': {'p1': _judged(3)},
            },
            'self': {
              'present': {'judgment': _judged(3)},
            },
          },
        },
      );
      expect(eventTraitReading(_trait(), event), isNull);
    });
  });

  group('dayTraitReading', () {
    final day = DateTime(2026, 11, 20);

    test('combines its events as its part scores them: each once', () {
      final reading = dayTraitReading(_trait(), [
        _event({
          'self': {'p1': _judged(3)},
        }, hour: 9),
        _event(
          {
            'self': {'p1': _judged(1)},
          },
          hour: 11,
          minutes: 180,
        ),
      ], day);
      expect(reading!.score, 67);
      expect(reading.lean, 0.5);
    });

    test('or by their time', () {
      final reading = dayTraitReading(
        _trait(scoring: {'weight_by': 'duration'}),
        [
          _event({
            'self': {'p1': _judged(3)},
          }, hour: 9),
          _event(
            {
              'self': {'p1': _judged(1)},
            },
            hour: 11,
            minutes: 180,
          ),
        ],
        day,
      );
      expect(reading!.score, 50);
      expect(reading.lean, 0.26);
    });

    test('leaves out cancelled events and those of other days', () {
      final reading = dayTraitReading(_trait(), [
        _event({
          'self': {'p1': _judged(0)},
        }, cancelled: true),
        _event({
          'self': {'p1': _judged(3)},
        }, hour: 10),
        Event(
          start: DateTime(2026, 11, 21, 9),
          end: DateTime(2026, 11, 21, 10),
          properties: _event({
            'self': {'p1': _judged(0)},
          }).properties,
        ),
      ], day);
      expect(reading, const TraitReading(score: 100, lean: 1));
    });

    test('combines its parts as its scoring weighs them', () {
      final trait = Trait(
        id: 'open',
        name: 'Open',
        scoring: Aggregation.fromJson({
          'weights': {'p1': 3, 'p2': 1},
        }),
        parts: [
          for (final id in ['p1', 'p2'])
            {
              'id': id,
              'kind': 'judgment',
              'rubric': 'R',
              'ratings': _ratings,
              'facts': ['general_notes'],
            },
        ],
      );
      final reading = dayTraitReading(trait, [
        _event({
          'self': {'p1': _judged(3), 'p2': _judged(0)},
        }),
      ], day);
      expect(reading!.score, 75);
    });

    test('is null for a day nothing rated', () {
      expect(dayTraitReading(_trait(), const [], day), isNull);
    });
  });

  test('a lean is red below neutral, grey at it, green above it', () {
    final low = traitLeanColor(-1);
    final none = traitLeanColor(0);
    final some = traitLeanColor(0.5);
    final high = traitLeanColor(1);
    expect(low.r, greaterThan(low.g));
    expect(high.g, greaterThan(high.r));
    expect(none.a, lessThan(high.a));
    expect(some, isNot(high));
    expect(some.g, greaterThan(some.r));
    expect(traitLeanColor(2), high);
    expect(traitLeanColor(-0.5), isA<Color>());
  });

  test('a neutral rating must be one of its ratings', () {
    Part judging(Object? neutral) => _trait(neutral: neutral).parts.single;
    expect(partProblem(judging(1)), isNull);
    expect(partProblem(judging(null)), isNull);
    expect(
      partProblem(judging(7)),
      'its neutral rating must be one of its ratings.',
    );
    expect(
      partProblem(judging('x')),
      'its neutral rating must be one of its ratings.',
    );
  });

  group('TraitFocusChip', () {
    final traits = [_trait(), const Trait(id: 'present', name: 'Present')];

    Future<List<String?>> pump(
      WidgetTester tester, {
      Trait? focus,
      TraitReading? reading,
    }) async {
      final picked = <String?>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TraitFocusChip(
              traits: traits,
              focus: focus,
              reading: reading,
              onFocus: picked.add,
            ),
          ),
        ),
      );
      return picked;
    }

    testWidgets("shows its name and the day's score", (tester) async {
      await pump(
        tester,
        focus: traits.first,
        reading: const TraitReading(score: 67, lean: 0.5),
      );
      expect(find.text('Open'), findsOneWidget);
      expect(find.text('67'), findsOneWidget);
    });

    testWidgets('a dash where nothing was rated', (tester) async {
      await pump(tester, focus: traits.first);
      expect(find.text('–'), findsOneWidget);
    });

    testWidgets('picks another trait, or none', (tester) async {
      final picked = await pump(tester, focus: traits.first);
      await tester.tap(find.byType(TraitFocusChip));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Present'));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(TraitFocusChip));
      await tester.pumpAndSettle();
      await tester.tap(find.text('No focus'));
      await tester.pumpAndSettle();
      expect(picked, ['present', null]);
    });

    testWidgets('with none in focus, offers to pick one', (tester) async {
      final picked = await pump(tester);
      await tester.tap(find.byType(TraitFocusChip));
      await tester.pumpAndSettle();
      expect(find.text('No focus'), findsNothing);
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(picked, ['open']);
    });
  });
}
