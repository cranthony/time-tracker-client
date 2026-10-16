import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:time_tracker_client/models/event.dart';
import 'package:time_tracker_client/screens/events_screen.dart';
import 'package:time_tracker_client/services/app_settings.dart';
import 'package:time_tracker_client/services/events_repository.dart';
import 'package:time_tracker_client/widgets/day_timeline.dart';
import 'package:time_tracker_client/widgets/hotkeys.dart';
import 'package:time_tracker_client/widgets/pending_event_box.dart';

void main() {
  final now = DateTime(2026, 9, 30, 12, 30);
  DateTime at(int day, int hour, [int minute = 0]) =>
      DateTime(2026, 9, day, hour, minute);

  final events = [
    Event(id: 'y-late', start: at(29, 20), end: at(29, 21), summary: 'Dinner'),
    Event(id: 'work', start: at(30, 9), end: at(30, 12), summary: 'Work'),
    Event(id: 'lunch', start: at(30, 12), end: at(30, 13), summary: 'Lunch'),
    Event(id: 'walk', start: at(30, 15), end: at(30, 16), summary: 'Walk'),
    Event(
      id: 't-early',
      start: DateTime(2026, 10, 1, 8),
      end: DateTime(2026, 10, 1, 9),
      summary: 'Breakfast',
    ),
  ];

  late Hotkeys hotkeys;
  late AppSettings settings;

  Widget app() {
    hotkeys = Hotkeys();
    // A grid of an hour, and no other stops: J and K step a cursor an
    // hour.
    settings = AppSettings(persist: false, grid: const Duration(hours: 1))
      ..setSnap(const {});
    return MaterialApp(
      navigatorObservers: [hotkeys],
      builder: (context, child) => HotkeyScope(hotkeys: hotkeys, child: child!),
      home: AppSettingsScope(
        settings: settings,
        child: EventsScreen(
          repository: InMemoryEventsRepository(events),
          serverLabel: 'offline demo',
          clock: () => now,
        ),
      ),
    );
  }

  Future<void> press(WidgetTester tester, LogicalKeyboardKey key) async {
    await tester.sendKeyEvent(key);
    await tester.pumpAndSettle();
  }

  DayTimeline timeline(WidgetTester tester, DateTime day) =>
      tester.widget<DayTimeline>(find.byKey(ValueKey(('shown', day))).first);

  PendingEventBox box(WidgetTester tester) =>
      tester.widget<PendingEventBoxView>(find.byType(PendingEventBoxView)).box;

  testWidgets('J and K step through the events, from the one happening now', (
    tester,
  ) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    final today = at(30, 0);
    expect(timeline(tester, today).keyed, isNull);

    await press(tester, LogicalKeyboardKey.keyJ);
    expect(timeline(tester, today).keyed, 'lunch');
    await press(tester, LogicalKeyboardKey.keyJ);
    expect(timeline(tester, today).keyed, 'walk');
    await press(tester, LogicalKeyboardKey.keyK);
    await press(tester, LogicalKeyboardKey.keyK);
    expect(timeline(tester, today).keyed, 'work');

    await press(tester, LogicalKeyboardKey.escape);
    expect(timeline(tester, today).keyed, isNull);
  });

  testWidgets('J past the last of the day goes onto the next; K, the day '
      'before', (tester) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await press(tester, LogicalKeyboardKey.keyJ);
    await press(tester, LogicalKeyboardKey.keyJ);
    await press(tester, LogicalKeyboardKey.keyJ);
    final tomorrow = DateTime(2026, 10, 1);
    expect(timeline(tester, tomorrow).keyed, 't-early');

    await press(tester, LogicalKeyboardKey.keyK);
    expect(timeline(tester, at(30, 0)).keyed, 'walk');
    for (var i = 0; i < 3; i++) {
      await press(tester, LogicalKeyboardKey.keyK);
    }
    expect(timeline(tester, at(29, 0)).keyed, 'y-late');
  });

  testWidgets('Enter opens the event highlighted', (tester) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await press(tester, LogicalKeyboardKey.enter);
    expect(hotkeys.dialogOpen, isFalse);

    await press(tester, LogicalKeyboardKey.keyJ);
    await press(tester, LogicalKeyboardKey.enter);
    expect(hotkeys.dialogOpen, isTrue);
    expect(find.text('Lunch'), findsWidgets);
  });

  testWidgets('H and L go a day back and on', (tester) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await press(tester, LogicalKeyboardKey.keyH);
    expect(find.byKey(ValueKey(('shown', at(29, 0)))), findsWidgets);
    await press(tester, LogicalKeyboardKey.keyL);
    await press(tester, LogicalKeyboardKey.keyL);
    expect(
      find.byKey(ValueKey(('shown', DateTime(2026, 10, 1)))),
      findsWidgets,
    );
  });

  testWidgets('the arrow keys scroll by the step in Settings', (tester) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    final scrollable = tester
        .stateList<ScrollableState>(
          find.ancestor(
            of: find.byKey(ValueKey(('shown', at(30, 0)))).first,
            matching: find.byType(Scrollable),
          ),
        )
        .firstWhere((s) => s.position.axis == Axis.vertical);
    final before = scrollable.position.pixels;
    await press(tester, LogicalKeyboardKey.arrowUp);
    final hour = before - scrollable.position.pixels;
    expect(hour, greaterThan(0));

    await settings.setKeyScroll(const Duration(minutes: 30));
    final after = scrollable.position.pixels;
    await press(tester, LogicalKeyboardKey.arrowDown);
    expect(scrollable.position.pixels - after, closeTo(hour / 2, 0.01));
  });

  testWidgets('C puts a cursor at the end of the event highlighted; J and K '
      'move it, Enter sets the start, then the end', (tester) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await press(tester, LogicalKeyboardKey.keyJ);
    await press(tester, LogicalKeyboardKey.keyC);
    expect(box(tester).cursor, at(30, 13));
    expect(box(tester).other, isNull);

    await press(tester, LogicalKeyboardKey.keyJ);
    expect(box(tester).cursor, at(30, 14));
    await press(tester, LogicalKeyboardKey.keyK);
    await press(tester, LogicalKeyboardKey.keyK);
    expect(box(tester).cursor, at(30, 12));
    await press(tester, LogicalKeyboardKey.keyJ);

    // The start set: the end, an hour on, and J moves it.
    await press(tester, LogicalKeyboardKey.enter);
    expect(box(tester).span, (at(30, 13), at(30, 14)));
    await press(tester, LogicalKeyboardKey.keyJ);
    expect(box(tester).span, (at(30, 13), at(30, 15)));

    // Esc leaves it, as ✕ does.
    await press(tester, LogicalKeyboardKey.escape);
    expect(find.byType(PendingEventBoxView), findsNothing);
  });

  testWidgets('C with nothing highlighted puts the cursor at now', (
    tester,
  ) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await press(tester, LogicalKeyboardKey.keyC);
    expect(box(tester).cursor, at(30, 13));
  });
}
