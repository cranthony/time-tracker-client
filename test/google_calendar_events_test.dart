import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:time_tracker_client/demo/google_calendar_sample.dart';
import 'package:time_tracker_client/models/event.dart';
import 'package:time_tracker_client/models/google_calendar.dart';
import 'package:time_tracker_client/screens/events_screen.dart';
import 'package:time_tracker_client/screens/settings_screen.dart';
import 'package:time_tracker_client/services/app_settings.dart';
import 'package:time_tracker_client/services/events_repository.dart';
import 'package:time_tracker_client/services/google_calendars.dart';
import 'package:time_tracker_client/widgets/day_timeline.dart';
import 'package:time_tracker_client/widgets/event_summary_dialog.dart';

/// A Friday, so the sample's work meetings are on.
final _now = DateTime(2026, 10, 2, 13, 30);

/// The sample's calendars, allowed to read them as [permission] says.
class _Source extends SampleGoogleCalendarSource {
  _Source({this.permitted = CalendarPermission.granted}) : super(_now);

  CalendarPermission permitted;
  var settingsOpened = 0;
  final opened = <GoogleEvent>[];

  @override
  Future<CalendarPermission> permission() async => permitted;

  @override
  Future<CalendarPermission> requestPermission() async => permitted;

  @override
  Future<bool> open(GoogleEvent event) async {
    opened.add(event);
    return true;
  }

  @override
  Future<void> openSettings() async => settingsOpened++;
}

void main() {
  setUp(
    () => SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty(),
  );

  Future<GoogleCalendars> pump(
    WidgetTester tester,
    Widget home, {
    _Source? source,
    bool enabled = true,
  }) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final calendars = GoogleCalendars(
      source: source ?? _Source(),
      persist: false,
      enabled: enabled,
      selected: const {'personal', 'family', 'birthdays', 'work'},
    );
    await tester.pumpWidget(
      MaterialApp(
        // Still: what pulses is drawn steady, so it settles.
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: true),
          child: AppSettingsScope(
            settings: AppSettings(persist: false),
            child: GoogleCalendarsScope(calendars: calendars, child: child!),
          ),
        ),
        home: home,
      ),
    );
    await tester.pumpAndSettle();
    return calendars;
  }

  EventsScreen events(EventsRepository repository) => EventsScreen(
    repository: repository,
    serverLabel: 'test',
    clock: () => _now,
  );

  /// Scrolls the timeline so [hour] is near its top.
  Future<void> scrollTo(WidgetTester tester, double hour) async {
    final scrollable = find
        .ancestor(
          of: find.byType(DayTimeline).first,
          matching: find.byWidgetPredicate(
            (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
          ),
        )
        .first;
    tester
        .state<ScrollableState>(scrollable)
        .position
        .jumpTo(hour * 60 * defaultTimelineScale);
    await tester.pumpAndSettle();
  }

  testWidgets("the day's all-day events are in a strip over the timeline, "
      'folded to a line and back', (tester) async {
    await pump(tester, events(InMemoryEventsRepository()));
    expect(find.text('Jamie: school trip'), findsOneWidget);
    expect(find.text("Sam's birthday"), findsOneWidget);

    await tester.tap(find.byTooltip('Hide all-day events'));
    await tester.pumpAndSettle();
    expect(find.text("Sam's birthday"), findsNothing);
    expect(find.textContaining('3 all day'), findsOneWidget);

    await tester.tap(find.byTooltip('Show all-day events'));
    await tester.pumpAndSettle();
    expect(find.text("Sam's birthday"), findsOneWidget);
  });

  testWidgets('a button by "now" brings calendar events over the '
      "user's own, only while the page has any", (tester) async {
    final calendars = await pump(tester, events(InMemoryEventsRepository()));
    expect(find.byTooltip('Bring calendar events over yours'), findsOneWidget);
    await tester.tap(find.byTooltip('Bring calendar events over yours'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Put calendar events behind yours'), findsOneWidget);

    calendars.disable();
    await tester.pumpAndSettle();
    expect(find.byTooltip('Put calendar events behind yours'), findsNothing);
    expect(find.byTooltip('Bring calendar events over yours'), findsNothing);
  });

  testWidgets("a calendar event logged is made with its title, description "
      'and location; opened, it goes to the calendar app', (tester) async {
    final source = _Source();
    final repository = InMemoryEventsRepository();
    await pump(tester, events(repository), source: source);
    await scrollTo(tester, 15.5);

    await tester.tap(find.bySemanticsLabel(RegExp('^Dentist')));
    await tester.pumpAndSettle();
    expect(find.text('Six-month cleaning.', findRichText: true), findsNothing);
    expect(
      find.textContaining('Six-month cleaning.', findRichText: true),
      findsOneWidget,
    );
    await tester.tap(find.text('Open in Calendar'));
    await tester.pumpAndSettle();
    expect([for (final e in source.opened) e.title], ['Dentist']);

    await tester.tap(find.bySemanticsLabel(RegExp('^Dentist')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Log this'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Continue'));
    await tester.pumpAndSettle();
    // Its map location, with the button to open it.
    expect(find.text('Bright Smile Dental'), findsOneWidget);
    expect(find.byTooltip('Open in Maps'), findsOneWidget);
    await tester.tap(find.text('Create'));
    await tester.pumpAndSettle();

    final day = DateTime(_now.year, _now.month, _now.day);
    final [created] = await repository.events(
      day,
      day.add(const Duration(days: 1)),
    );
    expect(created.summary, 'Dentist');
    expect(
      created.start.toLocal(),
      day.add(const Duration(hours: 16, minutes: 30)),
    );
    expect(
      created.end.toLocal(),
      day.add(const Duration(hours: 17, minutes: 15)),
    );
    expect(created.properties['location'], 'Bright Smile Dental');
    expect(
      created.properties['description'],
      'Six-month cleaning.\nBring the new insurance card.\n'
      'Reschedule: https://brightsmile.example/appointments',
    );
  });

  final settingsList = find
      .descendant(of: find.byType(ListView), matching: find.byType(Scrollable))
      .first;

  testWidgets("refused the calendar permission, Settings says so; refused "
      "for good, it offers the app's settings", (tester) async {
    final source = _Source(permitted: CalendarPermission.denied);
    await pump(
      tester,
      SettingsScreen(settings: AppSettings(persist: false)),
      source: source,
      enabled: false,
    );
    await tester.scrollUntilVisible(
      find.text('Show its events'),
      200,
      scrollable: settingsList,
    );
    await tester.tap(find.text('Show its events'));
    await tester.pumpAndSettle();
    expect(find.textContaining("wasn't allowed"), findsOneWidget);
    expect(find.text("Open the app's settings"), findsNothing);

    source.permitted = CalendarPermission.blocked;
    await tester.tap(find.text('Show its events'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text("Open the app's settings"),
      200,
      scrollable: settingsList,
    );
    await tester.tap(find.text("Open the app's settings"));
    expect(source.settingsOpened, 1);

    source.permitted = CalendarPermission.granted;
    await tester.tap(find.text('Show its events'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Holidays in United States'),
      200,
      scrollable: settingsList,
    );
    expect(find.text('alex@acme.example'), findsOneWidget);
  });

  testWidgets("an event's map location is edited on the location sheet's "
      'second page, and cleared there', (tester) async {
    Map<String, Object?>? created;
    await pump(
      tester,
      Builder(
        builder: (context) => TextButton(
          onPressed: () => showNewEventDialog(
            context,
            start: DateTime(2026, 10, 1, 18),
            end: DateTime(2026, 10, 1, 20),
            initial: const {'summary': 'Dinner', 'location': 'Noodle Bar'},
            create: (fields) async {
              created = fields;
              return const <Event>[];
            },
          ),
          child: const Text('Open'),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Open in Maps'), findsOneWidget);

    await tester.tap(find.text('Noodle Bar'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(Tab, 'Map location'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Noodle Bar'),
      '12 Fifth Ave, New York',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Done'));
    await tester.pumpAndSettle();
    expect(find.text('12 Fifth Ave, New York'), findsOneWidget);

    await tester.tap(find.text('12 Fifth Ave, New York'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(Tab, 'Map location'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Clear'));
    await tester.tap(find.widgetWithText(FilledButton, 'Done'));
    await tester.pumpAndSettle();
    expect(find.text('Add location'), findsOneWidget);
    expect(find.byTooltip('Open in Maps'), findsNothing);

    await tester.tap(find.text('Create'));
    await tester.pumpAndSettle();
    expect(created!['summary'], 'Dinner');
    expect(created!['location'], isNull);
  });
}
