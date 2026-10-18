import 'package:flutter_test/flutter_test.dart';
import 'package:time_tracker_client/models/event.dart';
import 'package:time_tracker_client/models/share.dart';

Event _event(List<Object?> actions, {int minutes = 60}) => Event(
  start: DateTime(2026, 10, 18, 9),
  end: DateTime(2026, 10, 18, 9).add(Duration(minutes: minutes)),
  properties: {'action_ids': actions},
);

void main() {
  group('an action share', () {
    test('is read from a bare id, as every action was before shares', () {
      final event = _event([
        'work',
        {'action_id': 'mail', 'minutes': 20},
        {'action_id': 'calls', 'percent': 25, 'remaining': true},
      ]);

      expect(event.actionIds, ['work', 'mail', 'calls']);
      expect(event.actionShares, const [
        ActionShare('work'),
        ActionShare('mail', minutes: 20),
        ActionShare('calls', percent: 25, remaining: true),
      ]);
    });

    test('is sent as its bare id with neither minutes nor percent', () {
      expect(const ActionShare('work').toJson(), 'work');
      expect(const ActionShare('work', remaining: true).toJson(), 'work');
      expect(const ActionShare('mail', minutes: 20).toJson(), {
        'action_id': 'mail',
        'minutes': 20,
      });
      expect(
        const ActionShare('calls', percent: 25, remaining: true).toJson(),
        {'action_id': 'calls', 'percent': 25, 'remaining': true},
      );
      expect(
        const ActionShare('calls', percent: 25, remaining: true).label,
        '25%+r',
      );
    });

    test('with neither, splits what the others leave evenly', () {
      final fractions = _event([
        {'action_id': 'mail', 'minutes': 20, 'remaining': true},
        'work',
        {'action_id': 'calls', 'percent': 50},
      ]).actionFractions();

      // 20 fixed; 50% of the 40 left to calls; the 20 left, half each to
      // mail (+r) and work.
      expect(fractions['mail'], closeTo(30 / 60, 1e-9));
      expect(fractions['work'], closeTo(10 / 60, 1e-9));
      expect(fractions['calls'], closeTo(20 / 60, 1e-9));
    });

    test('splits an event without shares evenly, as before', () {
      expect(_event(['a', 'b']).actionFractions(), {'a': 0.5, 'b': 0.5});
    });

    test('counts only those asked for', () {
      expect(_event(['a', 'b']).actionFractions((id) => id == 'a'), {'a': 1.0});
    });

    test('is checked as the server checks it', () {
      expect(
        shareProblems(
          const [ActionShare('a', minutes: 40), ActionShare('b', minutes: 21)],
          60,
          kind: 'action',
        ),
        ["The actions take 1h 1m, more than the event's 1h."],
      );
    });
  });
}
