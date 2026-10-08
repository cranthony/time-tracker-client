import 'package:flutter_test/flutter_test.dart';
import 'package:time_tracker_client/models/event.dart';
import 'package:time_tracker_client/models/note.dart';
import 'package:time_tracker_client/widgets/cursor_modes.dart';
import 'package:time_tracker_client/widgets/other_events.dart';

void main() {
  DateTime at(int hour, [int minute = 0]) =>
      DateTime(2026, 9, 30, hour, minute);
  String t(DateTime time) => localIsoTimestamp(time);

  // A 9-11, B 11:30-12:30, C 12:30-13:30.
  final a = Event(id: 'a', start: at(9), end: at(11), summary: 'A');
  final b = Event(id: 'b', start: at(11, 30), end: at(12, 30), summary: 'B');
  final c = Event(id: 'c', start: at(12, 30), end: at(13, 30), summary: 'C');
  final day = OtherEvents([a, b, c]);

  /// [o] as ids and what changes, to compare.
  String shown(Overwrite o) => [
    [for (final e in o.cancels) e.id],
    {for (final (e, fields) in o.updates) e.id: fields},
    [for (final c in o.creates) (c['start'], c['end'])],
  ].toString();

  /// [o]'s parts, to check each.
  ({
    List<String?> cancels,
    Map<String?, Map<String, Object?>> updates,
    List<(Object?, Object?)> creates,
  })
  parts(Overwrite o) => (
    cancels: [for (final e in o.cancels) e.id],
    updates: {for (final (e, fields) in o.updates) e.id: fields},
    creates: [for (final c in o.creates) (c['start'], c['end'])],
  );

  Overwrite around(
    DateTime anchor,
    DateTime end,
    AnchorMode anchorMode,
    EndMode endMode,
  ) => day.around(
    anchor: anchor,
    end: end,
    anchorMode: anchorMode,
    endMode: endMode,
  );

  group('as the box-wide modes did', () {
    test('keep and trim: overwriting', () {
      expect(
        shown(around(at(11, 15), at(12), AnchorMode.keep, EndMode.trim)),
        shown(day.overwrite(at(11, 15), at(12))),
      );
    });

    test('keep and cancel: cancelling all it touches', () {
      expect(
        shown(around(at(11, 15), at(12, 45), AnchorMode.keep, EndMode.cancel)),
        shown(day.cancelling(at(11, 15), at(12, 45))),
      );
    });

    test('trim and push: trimming and pushing', () {
      expect(
        shown(around(at(10), at(12), AnchorMode.trim, EndMode.push)),
        shown(day.pushing(at(10), at(12), later: true)),
      );
    });

    test('split and push, and push: splitting and pushing', () {
      expect(
        shown(around(at(10), at(12), AnchorMode.splitPush, EndMode.push)),
        shown(day.pushing(at(10), at(12), later: true, inside: Inside.split)),
      );
    });

    test('pushing earlier, for a box drawn upward', () {
      expect(
        shown(around(at(12), at(10, 30), AnchorMode.trim, EndMode.push)),
        shown(day.pushing(at(10, 30), at(12), later: false)),
      );
    });
  });

  group('the anchor says what becomes of its own event', () {
    test('cancelled, while the end trims the rest', () {
      final o = parts(
        around(at(10), at(11, 45), AnchorMode.cancel, EndMode.trim),
      );
      expect(o.cancels, ['a']);
      expect(o.updates, {
        'b': {'start': t(at(11, 45))},
      });
    });

    test("cut short, while the end cancels the rest -- not the anchor's", () {
      final o = parts(
        around(at(10), at(11, 45), AnchorMode.trim, EndMode.cancel),
      );
      expect(o.cancels, ['b']);
      expect(o.updates, {
        'a': {'end': t(at(10))},
      });
    });

    test('kept: the box only trims the others', () {
      final o = parts(
        around(at(11, 15), at(11, 45), AnchorMode.keep, EndMode.trim),
      );
      expect(o.cancels, isEmpty);
      expect(o.updates, {
        'b': {'start': t(at(11, 45))},
      });
    });
  });

  group('the rest of a split puts after the box', () {
    test('pushing what it runs into outside the box, even when the box '
        'only trims', () {
      // A split at 10; the box to 11:45 trims B to 11:45-12:30; A's hour
      // left goes 11:45-12:45, pushing B to 12:45-13:30, and C on.
      final o = parts(
        around(at(10), at(11, 45), AnchorMode.splitPush, EndMode.trim),
      );
      expect(o.cancels, isEmpty);
      expect(o.creates, [(t(at(11, 45)), t(at(12, 45)))]);
      expect(o.updates, {
        'a': {'end': t(at(10))},
        'b': {'start': t(at(12, 45)), 'end': t(at(13, 30))},
        'c': {'start': t(at(13, 30)), 'end': t(at(14, 30))},
      });
    });

    test('and nothing else, when the box keeps clear', () {
      // A split at 10, the box to 11:00: A's hour goes 11-12, pushing B
      // (11:30) to 12-13, C to 13-14.
      final o = parts(
        around(at(10), at(11), AnchorMode.splitPush, EndMode.keep),
      );
      expect(o.creates, [(t(at(11)), t(at(12)))]);
      expect(o.updates, {
        'a': {'end': t(at(10))},
        'b': {'start': t(at(12)), 'end': t(at(13))},
        'c': {'start': t(at(13)), 'end': t(at(14))},
      });
    });

    test('nothing to split with the anchor outside every event', () {
      final o = parts(
        around(at(11, 15), at(11, 30), AnchorMode.splitPush, EndMode.keep),
      );
      expect(o.updates, isEmpty);
      expect(o.creates, isEmpty);
    });
  });
}
