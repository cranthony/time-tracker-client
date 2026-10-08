import 'package:flutter_test/flutter_test.dart';
import 'package:time_tracker_client/models/event.dart';
import 'package:time_tracker_client/widgets/event_names.dart';

void main() {
  final breakfast = Event(
    id: '4dql2nnlc5bonnitfg5stcnrb9_20261008T110000Z',
    summary: 'Breakfast',
    start: DateTime(2026, 10, 8, 7),
    end: DateTime(2026, 10, 8, 7, 30),
  );
  final sleep = Event(
    id: 'cmpf8a1c3093546r10d2s015',
    summary: 'Sleep',
    start: DateTime(2026, 10, 7, 23),
    end: DateTime(2026, 10, 8, 7),
  );
  String time(DateTime t) => '${t.hour}:${t.minute.toString().padLeft(2, '0')}';
  ({String text, List<Event> events}) named(String message) => nameEvents(
    message,
    lookup: (id) => {breakfast.id: breakfast, sleep.id: sleep}[id],
    time: time,
  );

  test('names each event a refusal mentions, by its id', () {
    final result = named(
      "amend_proposal: decision 9 (keep "
      "4dql2nnlc5bonnitfg5stcnrb9_20261008T110000Z): "
      "'4dql2nnlc5bonnitfg5stcnrb9_20261008T110000Z' isn't one of this "
      "day's events; valid event ids: cmpf8a1c3093546r10d2s015",
    );
    expect(
      result.text,
      "amend_proposal: decision 9 (keep “Breakfast” (7:00)): “Breakfast” "
      "(7:00) isn't one of this day's events; its events are “Sleep” (23:00)",
    );
    expect(result.events, [breakfast, sleep]);
  });

  test("names one it doesn't know by when its id says it starts, or not "
      'at all', () {
    final result = named(
      'c9hjicr565j36b9o64pj8b9k6tij6b9p71hjcbb16oq6aphiccr34dr1cg_'
      '20261008T131500Z and 2k2j75c3mjlhqr3e8sibgrfjpq',
    );
    final start = time(DateTime.utc(2026, 10, 8, 13, 15).toLocal());
    expect(result.text, 'an event at $start and an event');
    expect(result.events, isEmpty);
  });

  test("leaves shorter ids alone: a proposal's, a revision's", () {
    const message = 'proposal cmpf8a1c3093 r10 is being applied';
    expect(named(message).text, message);
  });
}
