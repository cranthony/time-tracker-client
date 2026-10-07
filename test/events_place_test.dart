import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:time_tracker_client/models/event.dart';
import 'package:time_tracker_client/screens/events_screen.dart';
import 'package:time_tracker_client/services/events_place.dart';
import 'package:time_tracker_client/services/events_repository.dart';
import 'package:time_tracker_client/widgets/day_timeline.dart';

void main() {
  setUp(
    () => SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty(),
  );

  group('EventsPlace.keptAt', () {
    EventsPlace left(DateTime day, DateTime at) =>
        EventsPlace(day: day, top: day, scale: 1.5, leftAt: at);

    test('is kept for 30 minutes', () {
      final place = left(DateTime(2026, 9, 29), DateTime(2026, 9, 30, 12));
      expect(place.keptAt(DateTime(2026, 9, 30, 12, 29)), isTrue);
      expect(place.keptAt(DateTime(2026, 9, 30, 12, 30)), isTrue);
      expect(place.keptAt(DateTime(2026, 9, 30, 12, 31)), isFalse);
      // A clock set back.
      expect(place.keptAt(DateTime(2026, 9, 30, 11)), isFalse);
    });

    test('left on today, isn\'t kept once it\'s yesterday', () {
      final today = left(DateTime(2026, 9, 30), DateTime(2026, 9, 30, 23, 50));
      expect(today.keptAt(DateTime(2026, 9, 30, 23, 59)), isTrue);
      expect(today.keptAt(DateTime(2026, 10, 1, 0, 5)), isFalse);
      // Another day is still where it was left.
      final other = left(DateTime(2026, 9, 25), DateTime(2026, 9, 30, 23, 50));
      expect(other.keptAt(DateTime(2026, 10, 1, 0, 5)), isTrue);
    });

    test('survives JSON', () {
      final place = EventsPlace(
        day: DateTime(2026, 9, 29),
        top: DateTime(2026, 9, 29, 8, 15),
        scale: 3,
        leftAt: DateTime(2026, 9, 30, 12),
      );
      final back = EventsPlace.fromJson(place.toJson());
      expect(back.day, place.day);
      expect(back.top, place.top);
      expect(back.scale, place.scale);
      expect(back.leftAt, place.leftAt);
    });
  });

  group('the Events page', () {
    DateTime at(int day, int hour, [int minute = 0]) =>
        DateTime(2026, 9, day, hour, minute);
    late DateTime now;
    final repo = InMemoryEventsRepository([
      Event(start: at(29, 9), end: at(29, 10), summary: 'Yesterday'),
      Event(start: at(30, 9), end: at(30, 10), summary: 'Today'),
    ]);

    Widget screen(EventsPlaceStore store) => MaterialApp(
      home: EventsScreen(
        repository: repo,
        serverLabel: 'test',
        placeStore: store,
        clock: () => now,
      ),
    );

    ScrollPosition timeline(WidgetTester tester) => tester
        .state<ScrollableState>(
          find.byWidgetPredicate(
            (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
          ),
        )
        .position;

    /// Opens on today, goes to yesterday, zooms in and scrolls to 8 AM,
    /// then leaves.
    Future<void> leaveOnYesterday(
      WidgetTester tester,
      EventsPlaceStore store,
    ) async {
      now = at(30, 12);
      await tester.pumpWidget(screen(store));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Previous day'));
      await tester.pumpAndSettle();
      // 1.5 to 2.
      await _pinch(tester, 120, 160);
      timeline(tester).jumpTo(
        timelineOffset(at(29, 8), day: at(29, 0), dayEnd: at(30, 0), scale: 2),
      );
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox());
    }

    Future<void> expectBackOnYesterday(WidgetTester tester) async {
      expect(find.text('Yesterday'), findsNWidgets(2));
      final top = timelineTime(
        timeline(tester).pixels,
        day: at(29, 0),
        dayEnd: at(30, 0),
        scale: 2,
      );
      expect(top, at(29, 8));
    }

    testWidgets('goes back to where it was left, within 30 minutes', (
      tester,
    ) async {
      final store = EventsPlaceStore(persist: false);
      await leaveOnYesterday(tester, store);

      now = at(30, 12, 20);
      await tester.pumpWidget(screen(store));
      await tester.pumpAndSettle();
      await expectBackOnYesterday(tester);
    });

    testWidgets('after the app was closed', (tester) async {
      await leaveOnYesterday(tester, EventsPlaceStore());

      now = at(30, 12, 20);
      await tester.pumpWidget(screen(EventsPlaceStore()));
      await tester.pumpAndSettle();
      await expectBackOnYesterday(tester);
    });

    testWidgets('opens on today after 30 minutes', (tester) async {
      final store = EventsPlaceStore(persist: false);
      await leaveOnYesterday(tester, store);

      now = at(30, 12, 31);
      await tester.pumpWidget(screen(store));
      await tester.pumpAndSettle();
      expect(find.text('Yesterday'), findsNothing);
      expect(find.text('Today'), findsNWidgets(2));
    });
  });
}

/// Pinches the Events page's timeline from [from] to [to] pixels apart:
/// zooming by [to] / [from].
Future<void> _pinch(WidgetTester tester, double from, double to) async {
  final center = tester.getCenter(find.byType(ListView).first);
  final a = await tester.startGesture(center - Offset(from / 2, 0));
  final b = await tester.startGesture(center + Offset(from / 2, 0));
  for (var i = 1; i <= 8; i++) {
    final apart = from + (to - from) * i / 8;
    await a.moveTo(center - Offset(apart / 2, 0));
    await b.moveTo(center + Offset(apart / 2, 0));
    await tester.pump();
  }
  await a.up();
  await b.up();
  await tester.pumpAndSettle();
}
