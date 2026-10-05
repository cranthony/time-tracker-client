// Renders the app's main screens with the sample data (lib/demo), in light
// and dark, at a phone's size, and writes them to build/screenshots/. See
// flutter_test_config.dart, and "Visual tests" in README.md.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:time_tracker_client/services/goals_repository.dart';
import 'package:time_tracker_client/outbox/goal_outbox.dart';
import 'package:time_tracker_client/demo/sample_data.dart';
import 'package:time_tracker_client/models/goal.dart';
import 'package:time_tracker_client/outbox/note_outbox.dart';
import 'package:time_tracker_client/outbox/outbox_store.dart';
import 'package:time_tracker_client/screens/events_screen.dart';
import 'package:time_tracker_client/screens/goal_history_screen.dart';
import 'package:time_tracker_client/screens/goals_screen.dart';
import 'package:time_tracker_client/screens/notes_screen.dart';
import 'package:time_tracker_client/theme.dart';
import 'package:time_tracker_client/widgets/day_summary.dart';
import 'package:time_tracker_client/widgets/day_timeline.dart';
import 'package:time_tracker_client/widgets/goals_picker.dart';
import 'package:time_tracker_client/widgets/priority_chip.dart';

/// A fixed moment, so every run renders the same thing.
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
      // flutter_test draws shadows as solid outlines; draw them for real.
      // It must be put back before the test ends.
      debugDisableShadows = false;
      try {
        await tester.pumpWidget(
          MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: appTheme(brightness),
            home: screen,
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

    testWidgets('goals ($mode)', (tester) async {
      await render(
        tester,
        'goals',
        GoalsScreen(
          outbox: _idleGoalOutbox(),
          repository: sample.goalsRepository(),
          serverLabel: 'sample',
        ),
      );
    });

    // Every goal expanded, by swiping right: three levels of bands.
    testWidgets('goals expanded ($mode)', (tester) async {
      await render(
        tester,
        'goals_expanded',
        GoalsScreen(
          outbox: _idleGoalOutbox(),
          repository: sample.goalsRepository(),
          serverLabel: 'sample',
        ),
        then: () async {
          for (final name in [
            'Learn vegetarian cooking',
            'Be a good neighbor',
            'Visit parents every 2 months',
          ]) {
            final goal = find.textContaining(name, findRichText: true);
            await tester.ensureVisible(goal);
            await tester.pumpAndSettle();
            await tester.drag(goal, const Offset(100, 0));
            await tester.pumpAndSettle();
          }
          await tester.ensureVisible(
            find.textContaining('Book the train', findRichText: true),
          );
          await tester.pumpAndSettle();
        },
      );
    });

    testWidgets('goals with every status ($mode)', (tester) async {
      await render(
        tester,
        'goals_every_status',
        GoalsScreen(
          outbox: _idleGoalOutbox(),
          repository: sample.goalsRepository(),
          serverLabel: 'sample',
        ),
        then: () async {
          // Its sub-goal shows the band of a goal that inherits its color.
          await tester.drag(
            find.textContaining('Learn vegetarian cooking', findRichText: true),
            const Offset(100, 0),
          );
          await tester.pumpAndSettle();
          await tester.tap(find.byTooltip('Show goals that are…'));
          await tester.pumpAndSettle();
          for (final status in ['Completed', 'Archived', 'Deleted']) {
            await tester.tap(find.widgetWithText(CheckboxMenuButton, status));
            await tester.pumpAndSettle();
          }
        },
      );
    });

    for (final summary in [null, ...GoalSummary.values.skip(1)]) {
      // Null: the menu open, picking one.
      final name = switch (summary) {
        null => 'goals_summary_menu',
        _ => 'goals_summary_${summary.name}',
      };
      testWidgets('$name ($mode)', (tester) async {
        await render(
          tester,
          name,
          GoalsScreen(
            outbox: _idleGoalOutbox(),
            repository: sample.goalsRepository(),
            serverLabel: 'sample',
          ),
          then: () async {
            await tester.tap(find.byTooltip('Show under each goal…'));
            await tester.pumpAndSettle();
            if (summary == null) return;
            await tester.tap(
              find.widgetWithText(RadioMenuButton<GoalSummary>, summary.label),
            );
            await tester.pumpAndSettle();
          },
        );
      });
    }

    // A goal's measure, as tapping it shows it; then being edited.
    for (final editing in [false, true]) {
      final name = editing ? 'goal_measure_edit' : 'goal_measure';
      testWidgets('$name ($mode)', (tester) async {
        await render(
          tester,
          name,
          GoalsScreen(
            outbox: _idleGoalOutbox(),
            repository: sample.goalsRepository(),
            serverLabel: 'sample',
          ),
          then: () async {
            await tester.tap(
              find.textContaining('Wake up at 7am', findRichText: true),
            );
            await tester.pumpAndSettle();
            if (!editing) return;
            await tester.tap(find.text('Edit measure'));
            await tester.pumpAndSettle();
          },
        );
      });
    }

    // A sub-goal, as tapping it shows it, its priority inherited; then its
    // priority being picked.
    for (final editing in [false, true]) {
      final name = editing ? 'goal_dialog_priority' : 'goal_dialog';
      testWidgets('$name ($mode)', (tester) async {
        await render(
          tester,
          name,
          GoalsScreen(
            outbox: _idleGoalOutbox(),
            repository: sample.goalsRepository(),
            serverLabel: 'sample',
          ),
          then: () async {
            await tester.drag(
              find.textContaining(
                'Learn vegetarian cooking',
                findRichText: true,
              ),
              const Offset(100, 0),
            );
            await tester.pumpAndSettle();
            await tester.tap(
              find.textContaining('Tofu tikka masala', findRichText: true),
            );
            await tester.pumpAndSettle();
            if (!editing) return;
            await tester.tap(
              find.descendant(
                of: find.byType(AlertDialog),
                matching: find.byType(PriorityChip),
              ),
            );
            await tester.pumpAndSettle();
            await tester.tap(find.widgetWithText(ChoiceChip, 'P1'));
            await tester.pumpAndSettle();
          },
        );
      });
    }

    testWidgets('goal measure overall ($mode)', (tester) async {
      await render(
        tester,
        'goal_measure_overall',
        GoalsScreen(
          outbox: _idleGoalOutbox(),
          repository: sample.goalsRepository(),
          serverLabel: 'sample',
        ),
        then: () async {
          await tester.tap(find.text('Overall'));
          await tester.pumpAndSettle();
        },
      );
    });

    testWidgets('goals reorder ($mode)', (tester) async {
      await render(
        tester,
        'goals_reorder',
        GoalsScreen(
          outbox: _idleGoalOutbox(),
          repository: sample.goalsRepository(),
          serverLabel: 'sample',
        ),
        then: () async {
          await tester.drag(
            find.textContaining('Learn vegetarian cooking', findRichText: true),
            const Offset(100, 0),
          );
          await tester.pumpAndSettle();
          await tester.longPress(find.text('Host friends weekly'));
          await tester.pumpAndSettle();
        },
      );
    });

    testWidgets('goal parent ($mode)', (tester) async {
      await render(
        tester,
        'goal_parent',
        GoalsScreen(
          outbox: _idleGoalOutbox(),
          repository: sample.goalsRepository(),
          serverLabel: 'sample',
        ),
        then: () async {
          await tester.drag(
            find.textContaining('Learn vegetarian cooking', findRichText: true),
            const Offset(100, 0),
          );
          await tester.pumpAndSettle();
          await tester.tap(find.byTooltip('More for Tofu tikka masala'));
          await tester.pumpAndSettle();
          await tester.tap(find.text('Details'));
          await tester.pumpAndSettle();
          await tester.tap(find.text('Learn vegetarian cooking').last);
          await tester.pumpAndSettle();
          await tester.tap(find.byType(GoalField));
          await tester.pumpAndSettle();
        },
      );
    });

    testWidgets('goal history ($mode)', (tester) async {
      final goals = sample.goalsRepository();
      final tracker = (await tester.runAsync(goals.goals))!.goals
          .firstWhere((Goal g) => g.id == 'tracker');
      await render(
        tester,
        'goal_history',
        GoalHistoryScreen(goal: tracker, repository: goals),
      );
    });

    testWidgets('events ($mode)', (tester) async {
      await render(
        tester,
        'events',
        EventsScreen(
          repository: sample.eventsRepository(),
          goalsRepository: sample.goalsRepository(),
          serverLabel: 'sample',
          clock: () => _now,
        ),
      );
    });

    // The day's summary swiped once, to its goals, and twice, to its
    // top-level goals.
    for (final (name, swipes) in [
      ('events_summary_goals', 1),
      ('events_summary_top_level', 2),
    ]) {
      testWidgets('$name ($mode)', (tester) async {
        await render(
          tester,
          name,
          EventsScreen(
            repository: sample.eventsRepository(),
            goalsRepository: sample.goalsRepository(),
            serverLabel: 'sample',
            clock: () => _now,
          ),
          then: () async {
            for (var i = 0; i < swipes; i++) {
              await tester.fling(
                find.byType(DaySummary),
                const Offset(-300, 0),
                1000,
              );
              await tester.pumpAndSettle();
            }
          },
        );
      });
    }

    // A new event, from tapping the gap before dinner.
    testWidgets('event_new ($mode)', (tester) async {
      await render(
        tester,
        'event_new',
        EventsScreen(
          repository: sample.eventsRepository(),
          goalsRepository: sample.goalsRepository(),
          serverLabel: 'sample',
          clock: () => _now,
        ),
        then: () async {
          final timeline = find.byType(DayTimeline);
          final day = DateTime(_now.year, _now.month, _now.day);
          final y = timelineOffset(
            DateTime(_now.year, _now.month, _now.day, 17),
            day: day,
            dayEnd: day.add(const Duration(days: 1)),
            scale: defaultTimelineScale,
          );
          await tester.tapAt(
            tester.getTopLeft(timeline) +
                Offset(tester.getSize(timeline).width - 20, y),
          );
          await tester.pumpAndSettle();
        },
      );
    });

    // Zoomed all the way out, the whole day; zoomed in, around the
    // events too short for their text.
    for (final (name, zoom) in [
      ('events_zoomed_out', -3),
      ('events_zoomed_in', 2),
    ]) {
      testWidgets('$name ($mode)', (tester) async {
        await render(
          tester,
          name,
          EventsScreen(
            repository: sample.eventsRepository(),
            goalsRepository: sample.goalsRepository(),
            serverLabel: 'sample',
            clock: () => _now,
          ),
          then: () async {
            final button = find.byTooltip(zoom < 0 ? 'Zoom out' : 'Zoom in');
            for (var i = 0; i < zoom.abs(); i++) {
              await tester.tap(button);
              await tester.pumpAndSettle();
            }
            if (zoom > 0) {
              await tester.ensureVisible(find.text('Call Mom'));
              await tester.pumpAndSettle();
            }
          },
        );
      });
    }

    // An event's summary; then its series', with how it repeats open
    // for editing; then the series' Details.
    for (final (name, steps) in [
      ('event', <String>[]),
      ('event_series', ['Repeats · see series']),
      (
        'event_series_repeat',
        ['Repeats · see series', 'Every week on Mon, Tue, Wed, Thu, Fri'],
      ),
      ('event_series_details', ['Repeats · see series', 'Details']),
    ]) {
      testWidgets('$name ($mode)', (tester) async {
        await render(
          tester,
          name,
          EventsScreen(
            repository: sample.eventsRepository(),
            goalsRepository: sample.goalsRepository(),
            serverLabel: 'sample',
            clock: () => _now,
          ),
          then: () async {
            await tester.ensureVisible(find.text('Morning routine'));
            await tester.pumpAndSettle();
            await tester.tap(find.text('Morning routine'));
            await tester.pumpAndSettle();
            for (final step in steps) {
              final tapped = find.text(step).last;
              await tester.ensureVisible(tapped);
              await tester.pumpAndSettle();
              await tester.tap(tapped);
              await tester.pumpAndSettle();
            }
          },
        );
      });
    }

    // An event's goals open for editing: the tree, then a search.
    for (final (name, search) in [
      ('event_goals', null),
      ('event_goals_search', 'neigh vis'),
    ]) {
      testWidgets('$name ($mode)', (tester) async {
        await render(
          tester,
          name,
          EventsScreen(
            repository: sample.eventsRepository(),
            goalsRepository: sample.goalsRepository(),
            serverLabel: 'sample',
            clock: () => _now,
          ),
          then: () async {
            await tester.ensureVisible(find.text('Morning routine'));
            await tester.pumpAndSettle();
            await tester.tap(find.text('Morning routine'));
            await tester.pumpAndSettle();
            final goals = find.text('Wake up at 7am').last;
            await tester.ensureVisible(goals);
            await tester.pumpAndSettle();
            await tester.tap(goals);
            await tester.pumpAndSettle();
            if (search != null) {
              await tester.enterText(find.byType(TextField), search);
              await tester.pumpAndSettle();
            }
          },
        );
      });
    }

    testWidgets('notes ($mode)', (tester) async {
      final notes = sample.notesRepository();
      final outbox = NoteOutbox(store: InMemoryOutboxStore(), repository: notes)
        ..start();
      addTearDown(outbox.stop);
      await render(
        tester,
        'notes',
        NotesScreen(repository: notes, outbox: outbox, clock: () => _now),
      );
    });

    testWidgets('editing a note ($mode)', (tester) async {
      final notes = sample.notesRepository();
      final outbox = NoteOutbox(store: InMemoryOutboxStore(), repository: notes)
        ..start();
      addTearDown(outbox.stop);
      await render(
        tester,
        'note_sheet',
        NotesScreen(repository: notes, outbox: outbox, clock: () => _now),
        then: () async {
          await tester.tap(find.text('Lunch, finally'));
          await tester.pumpAndSettle();
        },
      );
    });
  }
}

/// For a Goals page that saves nothing.
GoalOutbox _idleGoalOutbox() => GoalOutbox(
  store: InMemoryOutboxStore(),
  repository: InMemoryGoalsRepository(),
);
