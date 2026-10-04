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
          // Its sub-goal shows the flag of a goal that inherits its color.
          await tester.tap(find.byTooltip('Expand Learn vegetarian cooking'));
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
            await tester.tap(find.text('Wake up at 7am'));
            await tester.pumpAndSettle();
            if (!editing) return;
            await tester.tap(find.text('Edit measure'));
            await tester.pumpAndSettle();
          },
        );
      });
    }

    // A sub-goal's event properties, inherited, as tapping it shows them
    // under "Event properties"; then its priority being edited.
    for (final editing in [false, true]) {
      final name = editing
          ? 'goal_event_properties_edit'
          : 'goal_event_properties';
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
            await tester.tap(
              find.widgetWithText(
                RadioMenuButton<GoalSummary>,
                'Event properties',
              ),
            );
            await tester.pumpAndSettle();
            await tester.tap(find.byTooltip('Expand Learn vegetarian cooking'));
            await tester.pumpAndSettle();
            await tester.tap(find.text('Tofu tikka masala'));
            await tester.pumpAndSettle();
            if (!editing) return;
            await tester.tap(find.text('Set').first);
            await tester.pumpAndSettle();
            await tester.tap(find.widgetWithText(ChoiceChip, '1'));
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
          await tester.tap(find.byTooltip('Expand Learn vegetarian cooking'));
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
          await tester.tap(find.byTooltip('Expand Learn vegetarian cooking'));
          await tester.pumpAndSettle();
          await tester.tap(find.byTooltip('More for Tofu tikka masala'));
          await tester.pumpAndSettle();
          await tester.tap(find.text('Details'));
          await tester.pumpAndSettle();
          await tester.tap(find.text('Learn vegetarian cooking').last);
          await tester.pumpAndSettle();
          await tester.tap(find.byType(DropdownButton<String?>));
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
