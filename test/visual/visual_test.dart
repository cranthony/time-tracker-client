// Renders the app's main screens with the sample data (lib/demo), in light
// and dark, at a phone's size, and writes them to build/screenshots/. See
// flutter_test_config.dart, and "Visual tests" in README.md.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:time_tracker_client/services/actions_repository.dart';
import 'package:time_tracker_client/outbox/action_outbox.dart';
import 'package:time_tracker_client/demo/sample_data.dart';
import 'package:time_tracker_client/models/person.dart';
import 'package:time_tracker_client/outbox/note_outbox.dart';
import 'package:time_tracker_client/outbox/outbox_store.dart';
import 'package:time_tracker_client/screens/events_screen.dart';
import 'package:time_tracker_client/screens/person_screen.dart';
import 'package:time_tracker_client/screens/plan_screen.dart';
import 'package:time_tracker_client/screens/notes_screen.dart';
import 'package:time_tracker_client/services/people_repository.dart';
import 'package:time_tracker_client/services/traits_repository.dart';
import 'package:time_tracker_client/theme.dart';
import 'package:time_tracker_client/services/event_store.dart';
import 'package:time_tracker_client/services/plan_memory.dart';
import 'package:time_tracker_client/services/proposal_repository.dart';
import 'package:time_tracker_client/widgets/day_summary.dart';
import 'package:time_tracker_client/widgets/time_summary.dart';
import 'package:time_tracker_client/widgets/day_timeline.dart';
import 'package:time_tracker_client/widgets/actions_picker.dart';

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
      outbox: _idleActionOutbox(),
      repository: sample.actionsRepository(),
      eventsRepository: sample.eventsRepository(),
      notesRepository: sample.notesRepository(),
      serverLabel: 'sample',
    );

    /// Swipes the Plan page to its [pane], by tapping its tab.
    Future<void> openPane(WidgetTester tester, String pane) async {
      await tester.tap(find.widgetWithText(Tab, pane));
      await tester.pumpAndSettle();
    }

    // The page as it opens: its tabs, over the Actions pane.
    testWidgets('plan ($mode)', (tester) async {
      await render(tester, 'plan', plan(), scoped: true);
    });

    for (final (name, pane) in [
      ('plan_traits', 'Traits'),
      ('plan_people', 'People'),
      ('plan_locations', 'Locations'),
    ]) {
      testWidgets('$name ($mode)', (tester) async {
        await render(
          tester,
          name,
          plan(),
          scoped: true,
          then: () => openPane(tester, pane),
        );
      });
    }

    // One circle's people.
    testWidgets('plan circle ($mode)', (tester) async {
      await render(
        tester,
        'plan_circle',
        plan(),
        scoped: true,
        then: () async {
          await openPane(tester, 'People');
          await tester.tap(find.widgetWithText(FilterChip, 'Dance friends'));
          await tester.pumpAndSettle();
        },
      );
    });

    // Searching people, and actions.
    for (final (name, pane, query) in [
      ('plan_people_search', 'People', 'salsa'),
      ('actions_search', null, 'guitar'),
    ]) {
      testWidgets('$name ($mode)', (tester) async {
        await render(
          tester,
          name,
          plan(),
          scoped: true,
          then: () async {
            if (pane != null) await openPane(tester, pane);
            await tester.enterText(
              find.byType(TextField).hitTestable().first,
              query,
            );
            await tester.pumpAndSettle();
          },
        );
      });
    }

    // A trait as tapping it opens it, and open for editing from its
    // pencil: its judgment's rubric, ratings and facts.
    for (final (name, edit) in [('trait', false), ('trait_dialog', true)]) {
      testWidgets('$name ($mode)', (tester) async {
        await render(
          tester,
          name,
          plan(),
          scoped: true,
          then: () async {
            await openPane(tester, 'Traits');
            await tester.tap(find.text('Adventurous'));
            await tester.pumpAndSettle();
            if (edit) {
              await tester.tap(find.byTooltip('Edit Adventurous'));
              await tester.pumpAndSettle();
            }
          },
        );
      });
    }

    // A person's page as it opens, and scrolled to what was cancelled.
    for (final (name, scrolled) in [
      ('person', false),
      ('person_cancelled', true),
    ]) {
      testWidgets('$name ($mode)', (tester) async {
        final people = (await tester.runAsync(
          sample.peopleRepository().people,
        ))!;
        // Scored from the sample's events, as the app does.
        final memory = PlanMemory(
          eventStore: EventStore(repository: sample.eventsRepository()),
        );
        await tester.runAsync(
          () => memory.warmScores(
            traits: sample.traitsRepository(),
            people: sample.peopleRepository(),
            actions: sample.actionsRepository(),
          ),
        );
        await render(
          tester,
          name,
          PersonScreen(
            person: people.people.firstWhere((p) => p.id == 'sam'),
            traits: sample.traitsRepository(),
            memory: memory,
            circles: people.circles,
            personNames: {for (final p in people.withSelf) p.id: personName(p)},
            actionNames: {for (final g in sample.actions) g.id: g.name ?? ''},
          ),
          then: scrolled
              ? () async {
                  await tester.scrollUntilVisible(
                    find.text('Coffee with Sam'),
                    300,
                    scrollable: find.byType(Scrollable).first,
                  );
                  await tester.pumpAndSettle();
                }
              : null,
        );
      });
    }

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

    // Groups expanded, by tapping them: three levels of bands.
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
            await tester.tap(group);
            await tester.pumpAndSettle();
          }
          await tester.scrollUntilVisible(
            find.textContaining('Practice guitar', findRichText: true),
            200,
            scrollable: _list,
          );
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
          await tester.scrollUntilVisible(
            find.textContaining('Tpyo', findRichText: true),
            200,
            scrollable: _list,
          );
          await tester.pumpAndSettle();
        },
      );
    });

    // A group in a group, edited from its menu: its priority, inherited,
    // and its color.
    testWidgets('action dialog ($mode)', (tester) async {
      await render(
        tester,
        'action_dialog',
        plan(),
        then: () async {
          await tester.tap(_tile('Creative'));
          await tester.pumpAndSettle();
          await tester.scrollUntilVisible(
            find.textContaining('Guitar', findRichText: true),
            200,
            scrollable: _list,
          );
          await tester.pumpAndSettle();
          await tester.tap(find.byTooltip('More for Guitar'));
          await tester.pumpAndSettle();
          await tester.tap(find.text('Edit'));
          await tester.pumpAndSettle();
        },
      );
    });

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
          await tester.tap(_tile('Creative'));
          await tester.pumpAndSettle();
          await tester.scrollUntilVisible(
            find.textContaining('Guitar', findRichText: true),
            200,
            scrollable: _list,
          );
          await tester.pumpAndSettle();
          await tester.tap(find.byTooltip('More for Guitar'));
          await tester.pumpAndSettle();
          await tester.tap(find.text('Edit'));
          await tester.pumpAndSettle();
          await tester.tap(find.text('Details'));
          await tester.pumpAndSettle();
          await tester.tap(find.text('Creative').last);
          await tester.pumpAndSettle();
          await tester.tap(find.byType(ActionField));
          await tester.pumpAndSettle();
        },
      );
    });

    Widget events() => EventsScreen(
      repository: sample.eventsRepository(),
      notesRepository: sample.notesRepository(),
      actionsRepository: sample.actionsRepository(),
      serverLabel: 'sample',
      clock: () => _now,
    );

    testWidgets('events ($mode)', (tester) async {
      await render(tester, 'events', events());
    });

    // A compaction proposal open: what happened, to confirm, in a band
    // ending at its through, each change marked -- those since the
    // revision last seen highlighted -- under the bar to confirm it; the
    // band's start, gone to from the bar; its notes, with Claude's reply
    // beside the one it answers; and a note left, waiting for Claude.
    Widget reviewing() => EventsScreen(
      repository: sample.eventsRepository(),
      notesRepository: sample.notesRepository(),
      actionsRepository: sample.actionsRepository(),
      proposals: sample.proposalRepository(),
      proposalSeen: ProposalSeenStore(
        persist: false,
        seen: {SampleData.proposalId: 2},
      ),
      serverLabel: 'sample',
      clock: () => _now,
    );

    for (final (name, then) in <(String, Future<void> Function(WidgetTester))>[
      ('events_proposal', (_) async {}),
      (
        'events_proposal_start',
        (tester) async {
          await tester.tap(find.text('What happened — to confirm').first);
          await tester.pumpAndSettle();
        },
      ),
      (
        'events_proposal_note',
        (tester) async {
          // To the third note: one Claude left out.
          for (var i = 0; i < 2; i++) {
            await tester.tap(find.byTooltip('Next note'));
            await tester.pumpAndSettle();
          }
        },
      ),
      (
        'events_proposal_compacted',
        (tester) async {
          // Back from the first note to review to the one compacted last
          // time, there as context.
          await tester.tap(find.byTooltip('Previous note'));
          await tester.pumpAndSettle();
        },
      ),
      (
        'events_proposal_note_use',
        (tester) async {
          // What the first note, which sets breakfast's start, is for.
          await tester.tap(find.byTooltip('What this note is for'));
          await tester.pumpAndSettle();
        },
      ),
      (
        'events_proposal_notes',
        (tester) async {
          await tester.tap(find.text('Notes (1)'));
          await tester.pumpAndSettle();
        },
      ),
      (
        'events_proposal_waiting',
        (tester) async {
          await tester.tap(find.text('Note for Claude'));
          await tester.pumpAndSettle();
          await tester.enterText(
            find.byType(TextField),
            'The email was before breakfast',
          );
          await tester.pumpAndSettle();
          await tester.tap(find.text('Leave note'));
          await tester.pumpAndSettle();
          // The snack bar gone.
          await tester.pump(const Duration(seconds: 5));
          await tester.pumpAndSettle();
        },
      ),
    ]) {
      testWidgets('$name ($mode)', (tester) async {
        await render(tester, name, reviewing(), then: () => then(tester));
      });
    }

    // Making an event: the cursor at now, from "+"; dragged out over
    // events, keeping them -- fitted into the free time there; moved to a
    // free stretch, and dragged out there; overwriting and trimming,
    // tinged red; overwriting and cancelling, the shadow stretched over
    // the events it cancels whole; the choice between them; the new
    // event, overwriting, with its trash to clear the time instead; and,
    // keeping events, the arrow from where the box was put to where it
    // was moved, part way through; and trimming and pushing, pushing, and
    // splitting and pushing, the events pushed outlined where they go.
    for (final (name, overwrite, move, drag, dialog, open, arrow) in [
      ('events_new_cursor', null, 0, 0, false, false, false),
      ('events_new_dragged', null, 0, 150, false, false, false),
      ('events_new_kept', null, 180, 60, false, false, false),
      (
        'events_new_overwrite',
        'Overwrite and trim',
        0,
        150,
        false,
        false,
        false,
      ),
      (
        'events_new_cancel',
        'Overwrite and cancel',
        0,
        150,
        false,
        false,
        false,
      ),
      ('events_new_modes', null, 0, 0, true, false, false),
      ('events_new_clear', 'Overwrite and trim', 0, 150, false, true, false),
      ('events_new_moved', null, 0, 150, false, false, true),
      ('events_new_trim_push', 'Trim and push', 0, 150, false, false, false),
      ('events_new_push', 'Push', 0, 150, false, false, false),
      ('events_new_split_push', 'Split and push', 0, 150, false, false, false),
    ]) {
      testWidgets('$name ($mode)', (tester) async {
        await render(
          tester,
          name,
          events(),
          then: () async {
            Future<void> settle() async {
              for (var i = 0; i < 12; i++) {
                await tester.pump(const Duration(milliseconds: 100));
              }
            }

            await tester.tap(find.byTooltip('New event'));
            await tester.pumpAndSettle();
            if (overwrite != null || dialog) {
              await tester.tap(find.byTooltip('Keep events: tap to change'));
              await tester.pumpAndSettle();
            }
            if (overwrite != null) {
              await tester.ensureVisible(find.text(overwrite));
              await settle();
              await tester.tap(find.text(overwrite));
              await tester.pump();
              await tester.tap(find.text('Done'));
              await settle();
            }
            if (move != 0) {
              await tester.drag(
                find.byTooltip('Drag to move the cursor'),
                Offset(0, move * defaultTimelineScale),
                warnIfMissed: false,
              );
              await settle();
            }
            if (drag != 0) {
              final start = find.byTooltip(
                'An hour later: tap to stretch it down, or drag its foot',
              );
              await tester.drag(
                start,
                Offset(0, drag * defaultTimelineScale),
                warnIfMissed: false,
              );
              await settle();
            }
            if (arrow) {
              // Moved whole, by its handle, into the events above.
              await tester.drag(
                find.byTooltip('Drag to move the event'),
                Offset(0, -90 * defaultTimelineScale),
                warnIfMissed: false,
              );
              // Its first frame, and part way through.
              await tester.pump();
              await tester.pump(const Duration(milliseconds: 500));
            }
            if (open) {
              await tester.tap(find.byTooltip('Continue'));
              await settle();
            }
          },
        );
      });
    }

    // Across midnight: while the box is up, the days either side are
    // stacked above and below the day shown, shaded, and the box can run
    // on into them.
    testWidgets('events_new_midnight ($mode)', (tester) async {
      await render(
        tester,
        'events_new_midnight',
        events(),
        then: () async {
          await tester.tap(find.byTooltip('New event'));
          await tester.pumpAndSettle();
          // The cursor on to 11:30 PM; then two hours, past midnight.
          await tester.drag(
            find.byTooltip('Drag to move the cursor'),
            Offset(0, 600 * defaultTimelineScale),
            warnIfMissed: false,
          );
          await tester.pumpAndSettle();
          final later = find.byTooltip(
            'An hour later: tap to stretch it down, or drag its foot',
          );
          for (var i = 0; i < 2; i++) {
            await tester.ensureVisible(later);
            await tester.pumpAndSettle();
            await tester.tap(later);
            await tester.pumpAndSettle();
          }
          await tester.tap(find.byTooltip('Go to the new event'));
          await tester.pumpAndSettle();
        },
      );
    });

    // Moving an event, pressed and held: the box around it, pushing, and
    // saying, by the cursor, which it's moving; the event faint where it
    // was; and the cursors switched, the box turned around.
    for (final switched in [false, true]) {
      testWidgets('events_moving${switched ? '_switched' : ''} ($mode)', (
        tester,
      ) async {
        await render(
          tester,
          'events_moving${switched ? '_switched' : ''}',
          events(),
          then: () async {
            await tester.longPress(find.text('Cooking class'));
            await tester.pumpAndSettle();
            // Up an hour, onto the call and what's after it: they're
            // pushed along after it.
            await tester.drag(
              find.byTooltip('Drag to move the event'),
              Offset(0, -60 * defaultTimelineScale),
              warnIfMissed: false,
            );
            await tester.pumpAndSettle();
            if (switched) {
              // Keeping events -- pushing, there's no room earlier in the
              // day -- and turned around, part way through pointing to
              // where the cursor's gone.
              await tester.tap(find.byTooltip('Push: tap to change'));
              await tester.pumpAndSettle();
              await tester.tap(find.text('Keep events'));
              await tester.pumpAndSettle();
              await tester.tap(find.text('Done'));
              await tester.pumpAndSettle();
              await tester.tap(find.byTooltip('Switch the cursors'));
              await tester.pump();
              await tester.pump(const Duration(milliseconds: 450));
            }
          },
        );
      });
    }

    // The day's summary swiped once, to its actions, and twice, to its
    // top-level ones.
    for (final (name, swipes) in [
      ('events_summary_actions', 1),
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
    // Pinched out past the least zoom, and in to three times as tall.
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
            if (zoom < 0) {
              await _pinch(tester, 200, 40);
            } else {
              await _pinch(tester, 50, 100);
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
    testWidgets('event facts ($mode)', (tester) async {
      await render(
        tester,
        'event_facts',
        events(),
        scoped: true,
        then: () async {
          await tester.ensureVisible(find.text('Lunch with Sam'));
          await tester.pumpAndSettle();
          await tester.tap(find.text('Lunch with Sam'));
          await tester.pumpAndSettle();
          final facts = find.text('With Sam · @ The noodle bar');
          await tester.ensureVisible(facts);
          await tester.pumpAndSettle();
          await tester.tap(facts);
          await tester.pumpAndSettle();
        },
      );
    });

    // An event's actions open for editing: the tree, then a search.
    for (final (name, search) in [
      ('event_actions', null),
      ('event_actions_search', 'soc call'),
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
ActionOutbox _idleActionOutbox() => ActionOutbox(
  store: InMemoryOutboxStore(),
  repository: InMemoryActionsRepository(),
);

/// The list a pane scrolls: not its search field, which scrolls too.
final _list = find
    .descendant(of: find.byType(ListView), matching: find.byType(Scrollable))
    .first;

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
