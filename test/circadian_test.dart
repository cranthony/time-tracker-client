import 'package:flutter_test/flutter_test.dart';
import 'package:time_tracker_client/models/circadian.dart';

void main() {
  final rhythm = CircadianRhythm.fromJson({
    'time_zone': 'America/New_York',
    'windows': {
      'minimum_before_waking_minutes': 120,
      'dim_before_minutes': 360,
      'bright_after_minutes': 240,
    },
    'revisions': [
      {'id': 'b', 'date': '2026-11-02', 'time': '06:40', 'note': 'no alarm'},
      {'id': 'a', 'date': '2026-10-20', 'time': '07:30'},
      {'id': 'bad', 'date': 'soon', 'time': '25:00'},
    ],
  });

  test('reads the revisions, oldest first, leaving out what isn\'t one', () {
    expect([for (final r in rhythm.revisions) r.id], ['a', 'b']);
    expect(rhythm.revisions.last.note, 'no alarm');
    expect(rhythm.revisions.last.time, '06:40');
    expect(rhythm.windows, const CircadianWindows());
    expect(rhythm.timeZone, 'America/New_York');
  });

  test('a day takes the latest revision on or before it', () {
    expect(rhythm.revisionOn(DateTime(2026, 10, 19)), isNull);
    expect(rhythm.revisionOn(DateTime(2026, 10, 25))?.id, 'a');
    expect(rhythm.revisionOn(DateTime(2026, 11, 2, 23))?.id, 'b');
    expect(rhythm.revisionOn(DateTime(2027, 1, 1))?.id, 'b');
  });

  test('works out the minimum and windows from the wake time', () {
    final day = rhythm.dayOf(DateTime(2026, 11, 3))!;
    expect(day.minimum, DateTime(2026, 11, 3, 4, 40));
    expect(day.dim.start, DateTime(2026, 11, 2, 22, 40));
    expect(day.bright.end, DateTime(2026, 11, 3, 8, 40));
  });

  test("a day's spans include the next day's dim window, cut off at "
      'midnight', () {
    final spans = rhythm.spansOn(DateTime(2026, 11, 3));
    expect(
      [for (final s in spans) (s.kind, s.start, s.end)],
      [
        (
          CircadianKind.dim,
          DateTime(2026, 11, 3),
          DateTime(2026, 11, 3, 4, 40),
        ),
        (
          CircadianKind.bright,
          DateTime(2026, 11, 3, 4, 40),
          DateTime(2026, 11, 3, 8, 40),
        ),
        (
          CircadianKind.dim,
          DateTime(2026, 11, 3, 22, 40),
          DateTime(2026, 11, 4),
        ),
      ],
    );
    expect(spans.last.minimum, DateTime(2026, 11, 4, 4, 40));
  });

  test('nothing before the first revision', () {
    expect(rhythm.spansOn(DateTime(2026, 10, 1)), isEmpty);
    expect(const CircadianRhythm().spansOn(DateTime(2026, 10, 1)), isEmpty);
  });

  test('a minimum early enough falls the evening before', () {
    final early = CircadianRhythm(
      windows: const CircadianWindows(minimumBeforeWaking: 180),
      revisions: [
        WakeRevision(date: DateTime(2026, 11, 1), hour: 1, minute: 0),
      ],
    );
    expect(
      early.dayOf(DateTime(2026, 11, 2))!.minimum,
      DateTime(2026, 11, 1, 22),
    );
  });
}
