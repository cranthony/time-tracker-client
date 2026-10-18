import 'package:flutter_test/flutter_test.dart';
import 'package:time_tracker_client/models/event.dart';
import 'package:time_tracker_client/models/facts.dart';
import 'package:time_tracker_client/models/people_times.dart';
import 'package:time_tracker_client/models/person.dart';
import 'package:time_tracker_client/models/share.dart';
import 'package:time_tracker_client/models/time_split.dart';
import 'package:time_tracker_client/widgets/plan_summaries.dart';
import 'package:time_tracker_client/widgets/time_summary.dart';

final _asOf = DateTime(2026, 10, 18, 12);

/// An hour ending at [_asOf], with [facts].
Event _event(Map<String, Object?> facts, {int minutes = 60}) => Event(
  start: _asOf.subtract(Duration(minutes: minutes)),
  end: _asOf,
  properties: {'facts': facts},
);

Map<String, double> _hours(List<SummarySlice> slices) => {
  for (final s in slices)
    if (s.label != 'Unscheduled') s.label: s.time.inMinutes / 60,
};

void main() {
  group("an event's facts", () {
    test('read bare ids as they always were, and shares beside them', () {
      final facts = Facts.fromJson({
        'location_ids': [
          'home',
          {'location_id': 'park', 'minutes': 20},
        ],
        'with_ids': [
          {'person_id': 'sam', 'percent': 50, 'remaining': true},
          'kim',
        ],
        'for_ids': ['mom'],
      })!;

      expect(facts.locationIds, ['home', 'park']);
      expect(facts.withIds, ['sam', 'kim']);
      expect(facts.forIds, ['mom']);
      expect(facts.withShares, const [
        PersonShare('sam', percent: 50, remaining: true),
        PersonShare('kim'),
      ]);
      expect(facts.locationSplits, {
        'park': const LocationShare('park', minutes: 20),
      });
      expect(Facts.fromJson(facts.toJson()), facts);
      expect(facts.toJson()['for_ids'], ['mom']);
    });

    test('keep their shares when who and where are picked again', () {
      final facts = Facts.fromJson({
        'with_ids': [
          {'person_id': 'sam', 'minutes': 10},
          'kim',
        ],
      })!;

      final kept = facts.copyWith(withIds: ['sam', 'priya']);
      expect(kept.withShares, const [
        PersonShare('sam', minutes: 10),
        PersonShare('priya'),
      ]);
      expect(facts.copyWith(withIds: ['kim']).withSplits, isEmpty);
      expect(
        Facts.withSplit(facts.withSplits, const PersonShare('sam')),
        isEmpty,
      );
    });
  });

  group('people', () {
    final hour = _event({
      'with_ids': [
        {'person_id': 'sam', 'minutes': 20},
        'kim',
        'priya',
      ],
    });

    test('each given neither take all the time the others leave', () {
      expect(hour.withFractions['sam'], closeTo(20 / 60, 1e-9));
      expect(hour.withFractions['kim'], closeTo(40 / 60, 1e-9));
      expect(hour.withFractions['priya'], closeTo(40 / 60, 1e-9));
    });

    test("count their own time on the People pane", () {
      final times = PeopleTimes.compute(
        window: SummaryWindow(asOf: _asOf),
        windowEvents: [hour],
        known: [hour],
      );
      expect(times.day('sam'), const Duration(minutes: 20));
      expect(times.day('kim'), const Duration(minutes: 40));
    });

    test('split the summary no more than whole', () {
      final (day, _) = personTime(
        [hour],
        SummaryWindow(asOf: _asOf),
        const PeopleList(),
      );
      // 20, 40 and 40 minutes, scaled down to the hour: 12, 24 and 24.
      expect(_hours(day), {'sam': 0.2, 'kim': 0.4, 'priya': 0.4});
    });
  });

  test('places given neither share what the others leave evenly', () {
    final hour = _event({
      'location_ids': [
        {'location_id': 'home', 'minutes': 30},
        'park',
        'cafe',
      ],
    });

    final (day, _) = locationTime([hour], SummaryWindow(asOf: _asOf), const {});
    expect(_hours(day), {'home': 0.5, 'park': 0.25, 'cafe': 0.25});
  });
}
