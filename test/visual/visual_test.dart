// Renders the app's main screens with the sample data (lib/demo), in light
// and dark, at a phone's size, and writes them to build/screenshots/. See
// flutter_test_config.dart, and "Visual tests" in README.md.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:time_tracker_client/services/goals_repository.dart';
import 'package:time_tracker_client/outbox/goal_outbox.dart';
import 'package:time_tracker_client/demo/sample_data.dart';
import 'package:time_tracker_client/models/goal.dart';
import 'package:time_tracker_client/models/person.dart';
import 'package:time_tracker_client/outbox/note_outbox.dart';
import 'package:time_tracker_client/outbox/outbox_store.dart';
import 'package:time_tracker_client/screens/events_screen.dart';
import 'package:time_tracker_client/screens/goal_history_screen.dart';
import 'package:time_tracker_client/screens/person_screen.dart';
import 'package:time_tracker_client/screens/plan_screen.dart';
import 'package:time_tracker_client/screens/notes_screen.dart';
import 'package:time_tracker_client/services/people_repository.dart';
import 'package:time_tracker_client/services/traits_repository.dart';
import 'package:time_tracker_client/theme.dart';
import 'package:time_tracker_client/widgets/day_summary.dart';
import 'package:time_tracker_client/widgets/time_summary.dart';
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

    /// Renders [screen], with the sample's traits and people when
    /// [scoped], after [then].
    Future<void> render(
      WidgetTester tester,
      String name,
      Widget screen, {
      Future<void> Function()? then,
      bool scoped = false,
    }) async {
      tester.view.physicalSize = _phone * 2;
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      // flutter_test draws shadows as solid outlines; draw them for real.
      // It must be put back before the test ends.
      debugDisableShadows = false;
      try {
        final app = MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: appTheme(brightness),
          home: screen,
        );
        await tester.pumpWidget(
          scoped
              ? TraitsScope(
                  repository: sample.traitsRepository(),
                  child: PeopleScope(
                    repository: sample.peopleRepository(),
                    child: app,
                  ),
                )
              : app,
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

    Widget plan() => PlanScreen(
      outbox: _idleGoalOutbox(),
      repository: sample.goalsRepository(),
      serverLabel: 'sample',
    );

    // The whole page: traits, then people, then actions.
    testWidgets('plan ($mode)', (tester) async {
      await render(tester, 'plan', plan(), scoped: true);
    });

    // Scrolled down to the people, Self first.
    testWidgets('plan people ($mode)', (tester) async {
      await render(
        tester,
        'plan_people',
        plan(),
        scoped: true,
        then: () async {
          await tester.scrollUntilVisible(
            find.text('Jordan'),
            200,
            scrollable: find.byType(Scrollable).first,
          );
          await tester.pumpAndSettle();
        },
      );
    });

    // Traits folded away, and one circle's people.
    testWidgets('plan circle ($mode)', (tester) async {
      await render(
        tester,
        'plan_circle',
        plan(),
        scoped: true,
        then: () async {
          await tester.tap(find.byIcon(Icons.expand_more).first);
          await tester.pumpAndSettle();
          await tester.tap(find.widgetWithText(FilterChip, 'Dance friends'));
          await tester.pumpAndSettle();
        },
      );
    });

    // A trait open for editing: its facet's rubric, ratings and
    // primitives.
    testWidgets('trait dialog ($mode)', (tester) async {
      await render(
        tester,
        'trait_dialog',
        plan(),
        scoped: true,
        then: () async {
          await tester.tap(find.text('Adventurous'));
          await tester.pumpAndSettle();
        },
      );
    });

    testWidgets('person ($mode)', (tester) async {
      final people = (await tester.runAsync(sample.peopleRepository().people))!;
      await render(
        tester,
        'person',
        PersonScreen(
          person: people.people.firstWhere((p) => p.id == 'sam'),
          traits: sample.traitsRepository(),
          circles: people.circles,
          personNames: {for (final p in people.withSelf) p.id: personName(p)},
        ),
      );
    });

    // The Actions section alone, as the rest are when folded away.
    testWidgets('actions ($mode)', (tester) async {
      await render(tester, 'actions', plan());
    });

    // The time summary swiped to its priorities, folded away, and
    // turned to percentages.
    for (final (name, step) in [
      ('actions_summary_priorities', null),
      ('actions_summary_collapsed', 'Hide summary'),
      ('actions_percentages', 'Show percentages'),
    ]) {
      testWidgets('$name ($mode)', (tester) async {
        await render(
          tester,
          name,
          plan(),
          then: () async {
            if (step != null) {
              await tester.tap(find.byTooltip(step));
            } else {
              await tester.fling(
                find.byType(TimeSummary),
                const Offset(-300, 0),
                1000,
              );
            }
            await tester.pumpAndSettle();
          },
        );
      });
    }

    // Groups expanded, by swiping right: three levels of bands.
    testWidgets('actions expanded ($mode)', (tester) async {
      await render(
        tester,
        'actions_expanded',
        plan(),
        then: () async {
          for (final name in ['Creative', 'Guitar', 'Cooking']) {
            final group = _tile(name);
            await tester.ensureVisible(group);
            await tester.pumpAndSettle();
            await tester.drag(group, const Offset(100, 0));
            await tester.pumpAndSettle();
          }
          await tester.ensureVisible(_tile('Practice guitar'));
          await tester.pumpAndSettle();
        },
      );
    });

    testWidgets('actions with every status ($mode)', (tester) async {
      await render(
        tester,
        'actions_every_status',
        plan(),
        then: () async {
          await tester.tap(find.byTooltip('Show actions that are…'));
          await tester.pumpAndSettle();
          for (final status in ['Archived', 'Deleted']) {
            await tester.tap(find.widgetWithText(CheckboxMenuButton, status));
            await tester.pumpAndSettle();
          }
          await tester.tapAt(Offset.zero);
          await tester.pumpAndSettle();
          await tester.ensureVisible(_tile('Tpyo'));
          await tester.pumpAndSettle();
        },
      );
    });

    for (final summary in [null, ...GoalSummary.values.skip(1)]) {
      // Null: the menu open, picking one.
      final name = switch (summary) {
        null => 'actions_summary_menu',
        _ => 'actions_summary_${summary.name}',
      };
      testWidgets('$name ($mode)', (tester) async {
        await render(
          tester,
          name,
          plan(),
          then: () async {
            await tester.tap(find.byTooltip('Show under each action…'));
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

    // An action's target, as tapping it shows it; then being edited.
    for (final editing in [false, true]) {
      final name = editing ? 'action_measure_edit' : 'action_measure';
      testWidgets('$name ($mode)', (tester) async {
        await render(
          tester,
          name,
          plan(),
          then: () async {
            await tester.tap(_tile('Work'));
            await tester.pumpAndSettle();
            if (!editing) return;
            await tester.tap(find.text('Edit measure'));
            await tester.pumpAndSettle();
          },
        );
      });
    }

    // A group in a group, as tapping it shows it, its priority inherited;
    // then its priority being picked.
    for (final editing in [false, true]) {
      final name = editing ? 'action_dialog_priority' : 'action_dialog';
      testWidgets('$name ($mode)', (tester) async {
        await render(
          tester,
          name,
          plan(),
          then: () async {
            await tester.drag(_tile('Creative'), const Offset(100, 0));
            await tester.pumpAndSettle();
            await tester.ensureVisible(_tile('Guitar'));
            await tester.pumpAndSettle();
            await tester.tap(_tile('Guitar'));
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

    testWidgets('actions reorder ($mode)', (tester) async {
      await render(
        tester,
        'actions_reorder',
        plan(),
        then: () async {
          await tester.longPress(_tile('Work'));
          await tester.pumpAndSettle();
        },
      );
    });

    testWidgets('action parent ($mode)', (tester) async {
      await render(
        tester,
        'action_parent',
        plan(),
        then: () async {
          await tester.drag(_tile('Creative'), const Offset(100, 0));
          await tester.pumpAndSettle();
          await tester.ensureVisible(_tile('Guitar'));
          await tester.pumpAndSettle();
          await tester.tap(find.byTooltip('More for Guitar'));
          await tester.pumpAndSettle();
          await tester.tap(find.text('Details'));
          await tester.pumpAndSettle();
          await tester.tap(find.text('Creative').last);
          await tester.pumpAndSettle();
          await tester.tap(find.byType(GoalField));
          await tester.pumpAndSettle();
        },
      );
    });

    testWidgets('action history ($mode)', (tester) async {
      final goals = sample.goalsRepository();
      final work = (await tester.runAsync(goals.goals))!.goals
          .firstWhere((Goal g) => g.id == 'work');
      await render(
        tester,
        'action_history',
        GoalHistoryScreen(goal: work, repository: goals),
      );
    });

    Widget events() => EventsScreen(
      repository: sample.eventsRepository(),
      notesRepository: sample.notesRepository(),
      goalsRepository: sample.goalsRepository(),
      serverLabel: 'sample',
      clock: () => _now,
    );

    testWidgets('events ($mode)', (tester) async {
      await render(tester, 'events', events());
    });

    // The day's summary swiped once, to its actions, and twice, to its
    // top-level ones.
    for (final (name, swipes) in [
      ('events_summary_goals', 1),
      ('events_summary_top_level', 2),
      // Folded away.
      ('events_summary_collapsed', 0),
    ]) {
      testWidgets('$name ($mode)', (tester) async {
        await render(
          tester,
          name,
          events(),
          then: () async {
            if (swipes == 0) {
              await tester.tap(find.byTooltip('Hide summary'));
              await tester.pumpAndSettle();
            }
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
        events(),
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
    // events too short for their text and a note not yet compacted.
    for (final (name, zoom) in [
      ('events_zoomed_out', -3),
      ('events_zoomed_in', 2),
    ]) {
      testWidgets('$name ($mode)', (tester) async {
        await render(
          tester,
          name,
          events(),
          then: () async {
            final button = find.byTooltip(zoom < 0 ? 'Zoom out' : 'Zoom in');
            for (var i = 0; i < zoom.abs(); i++) {
              await tester.tap(button);
              await tester.pumpAndSettle();
            }
            if (zoom > 0) {
              await tester.ensureVisible(find.text('Lunch with Sam'));
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
          events(),
          then: () async {
            // The event, not its action, named the same.
            final event = find.text('Get up and get ready').first;
            await tester.ensureVisible(event);
            await tester.pumpAndSettle();
            await tester.tap(event);
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

    // What happened at lunch: who it was with, where, and the notes.
    testWidgets('event facets ($mode)', (tester) async {
      await render(
        tester,
        'event_facets',
        events(),
        scoped: true,
        then: () async {
          await tester.ensureVisible(find.text('Lunch with Sam'));
          await tester.pumpAndSettle();
          await tester.tap(find.text('Lunch with Sam'));
          await tester.pumpAndSettle();
          final facets = find.text('With Sam · @ the noodle bar');
          await tester.ensureVisible(facets);
          await tester.pumpAndSettle();
          await tester.tap(facets);
          await tester.pumpAndSettle();
        },
      );
    });

    // An event's actions open for editing: the tree, then a search.
    for (final (name, search) in [
      ('event_goals', null),
      ('event_goals_search', 'soc call'),
    ]) {
      testWidgets('$name ($mode)', (tester) async {
        await render(
          tester,
          name,
          events(),
          then: () async {
            await tester.ensureVisible(find.text('Lunch with Sam'));
            await tester.pumpAndSettle();
            await tester.tap(find.text('Lunch with Sam'));
            await tester.pumpAndSettle();
            final actions = find.text('Eat a meal').last;
            await tester.ensureVisible(actions);
            await tester.pumpAndSettle();
            await tester.tap(actions);
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
          await tester.tap(find.text('Lunch with Sam, finally'));
          await tester.pumpAndSettle();
        },
      );
    });
  }
}

/// An action's tile, by [name]: after the time summary's legend, which may
/// name it too.
Finder _tile(String name) => find.textContaining(name, findRichText: true).last;

/// For a Plan page that saves nothing.
GoalOutbox _idleGoalOutbox() => GoalOutbox(
  store: InMemoryOutboxStore(),
  repository: InMemoryGoalsRepository(),
);
