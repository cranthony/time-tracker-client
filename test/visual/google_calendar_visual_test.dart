import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:time_tracker_client/demo/google_calendar_sample.dart';
import 'package:time_tracker_client/demo/sample_data.dart';
import 'package:time_tracker_client/screens/events_screen.dart';
import 'package:time_tracker_client/screens/settings_screen.dart';
import 'package:time_tracker_client/services/app_settings.dart';
import 'package:time_tracker_client/services/google_calendars.dart';
import 'package:time_tracker_client/services/people_repository.dart';
import 'package:time_tracker_client/theme.dart';
import 'package:time_tracker_client/widgets/day_timeline.dart';
import 'package:time_tracker_client/widgets/google_event_sheet.dart';

/// A fixed moment, so every run renders the same thing: a Friday.
final _now = DateTime(2026, 10, 2, 13, 30);

/// A typical phone's screen, in logical pixels.
const _phone = Size(390, 844);

void main() {
  final sample = SampleData(_now);

  for (final brightness in Brightness.values) {
    final mode = brightness.name;

    Future<void> render(
      WidgetTester tester,
      String name,
      Widget screen, {
      Future<void> Function()? then,
    }) async {
      tester.view.physicalSize = _phone * 2;
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      debugDisableShadows = false;
      final settings = AppSettings(persist: false);
      final calendars = GoogleCalendars(
        source: SampleGoogleCalendarSource(_now),
        persist: false,
        enabled: true,
        selected: const {'personal', 'family', 'birthdays', 'work'},
      );
      // Loaded, as they would be by the time the page is looked at.
      await calendars.enable();
      try {
        await tester.pumpWidget(
          PeopleScope(
            repository: sample.peopleRepository(),
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: appTheme(brightness),
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context).copyWith(disableAnimations: true),
                child: AppSettingsScope(
                  settings: settings,
                  child: GoogleCalendarsScope(
                    calendars: calendars,
                    child: child!,
                  ),
                ),
              ),
              home: screen is SettingsScreen
                  ? SettingsScreen(settings: settings)
                  : screen,
            ),
          ),
        );
        await tester.pumpAndSettle();
        await then?.call();
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile('${name}_$mode.png'),
        );
      } finally {
        debugDisableShadows = true;
      }
    }

    Widget events() => EventsScreen(
      repository: sample.eventsRepository(),
      notesRepository: sample.notesRepository(),
      actionsRepository: sample.actionsRepository(),
      serverLabel: 'sample',
      clock: () => _now,
    );

    /// Scrolls the timeline so [hour] is near the top.
    Future<void> scrollTo(WidgetTester tester, double hour) async {
      final scrollable = find
          .ancestor(
            of: find.byType(DayTimeline).first,
            matching: find.byWidgetPredicate(
              (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
            ),
          )
          .first;
      final state = tester.state<ScrollableState>(scrollable);
      state.position.jumpTo(hour * 60 * defaultTimelineScale);
      await tester.pumpAndSettle();
    }

    for (final (name, hour) in [
      ('gcal_morning', 7.5),
      ('gcal_afternoon', 11.5),
      ('gcal_evening', 15.5),
    ]) {
      testWidgets('$name ($mode)', (tester) async {
        await render(
          tester,
          name,
          events(),
          then: () => scrollTo(tester, hour),
        );
      });
    }

    // Dinner pressed and held, to move: drawn faintly where it was, still
    // hiding Book club, behind it.
    testWidgets('gcal_moving ($mode)', (tester) async {
      await render(
        tester,
        'gcal_moving',
        events(),
        then: () async {
          await scrollTo(tester, 15.5);
          await tester.longPress(find.textContaining('Dinner with Sam'));
          await tester.pumpAndSettle();
        },
      );
    });

    // Brought over the user's own events, from the button by "now".
    testWidgets('gcal_on_top ($mode)', (tester) async {
      await render(
        tester,
        'gcal_on_top',
        events(),
        then: () async {
          await scrollTo(tester, 7.5);
          await tester.tap(find.byTooltip('Bring calendar events over yours'));
          await tester.pumpAndSettle();
        },
      );
    });

    testWidgets('gcal_all_day_collapsed ($mode)', (tester) async {
      await render(
        tester,
        'gcal_all_day_collapsed',
        events(),
        then: () async {
          await scrollTo(tester, 7.5);
          await tester.tap(find.byTooltip('Hide all-day events'));
          await tester.pumpAndSettle();
        },
      );
    });

    testWidgets('gcal_all_day_sheet ($mode)', (tester) async {
      await render(
        tester,
        'gcal_all_day_sheet',
        events(),
        then: () async {
          await scrollTo(tester, 7.5);
          await tester.tap(find.bySemanticsLabel(RegExp('^Out of office')));
          await tester.pumpAndSettle();
        },
      );
    });

    testWidgets('gcal_sheet ($mode)', (tester) async {
      await render(
        tester,
        'gcal_sheet',
        events(),
        then: () async {
          await scrollTo(tester, 15.5);
          await tester.tap(find.bySemanticsLabel(RegExp('^Dentist')));
          await tester.pumpAndSettle();
        },
      );
    });

    // Under the user's own events, so opened directly, not tapped.
    for (final (name, id, more) in [
      ('gcal_html_sheet', 'review', false),
      ('gcal_long_sheet', 'book', false),
      ('gcal_long_sheet_more', 'book', true),
    ]) {
      testWidgets('$name ($mode)', (tester) async {
        await render(
          tester,
          name,
          events(),
          then: () async {
            final day = DateTime(_now.year, _now.month, _now.day);
            final all = await SampleGoogleCalendarSource(_now)
                .events(day, day.add(const Duration(days: 1)), const [
                  SampleGoogleCalendarSource.personal,
                  SampleGoogleCalendarSource.work,
                ]);
            final event = all.firstWhere((e) => e.id.startsWith(id));
            showGoogleEventSheet(
              tester.element(find.byType(EventsScreen)),
              event,
            );
            await tester.pumpAndSettle();
            if (more) {
              await tester.tap(find.text('More'));
              await tester.pumpAndSettle();
            }
          },
        );
      });
    }

    // Dentist logged: the box up across its times, then the new event's
    // dialog, its title, description and map location filled in; then
    // its location's sheet, and the sheet's Map location page.
    for (final (name, step) in [
      ('gcal_logged', 0),
      ('gcal_location_sheet', 1),
      ('gcal_map_location', 2),
    ]) {
      testWidgets('$name ($mode)', (tester) async {
        await render(
          tester,
          name,
          events(),
          then: () async {
            await scrollTo(tester, 15.5);
            await tester.tap(find.bySemanticsLabel(RegExp('^Dentist')));
            await tester.pumpAndSettle();
            await tester.tap(find.text('Log this'));
            await tester.pumpAndSettle();
            await tester.tap(find.byTooltip('Continue'));
            await tester.pumpAndSettle();
            if (step == 0) return;
            await tester.tap(find.text('Bright Smile Dental'));
            await tester.pumpAndSettle();
            if (step == 1) return;
            await tester.tap(find.text('Map location'));
            await tester.pumpAndSettle();
          },
        );
      });
    }

    testWidgets('gcal_settings ($mode)', (tester) async {
      await render(
        tester,
        'gcal_settings',
        SettingsScreen(settings: AppSettings(persist: false)),
        then: () async {
          await tester.drag(find.byType(ListView), const Offset(0, -2000));
          await tester.pumpAndSettle();
        },
      );
    });
  }
}
