// A compaction proposal's details, under its bar on the Events page: its
// cancels, and whether each counts against follow-through; and the people,
// actions and locations it adds, settled there.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:time_tracker_client/models/event.dart';
import 'package:time_tracker_client/models/note.dart';
import 'package:time_tracker_client/models/person.dart';
import 'package:time_tracker_client/models/proposal.dart';
import 'package:time_tracker_client/screens/events_screen.dart';
import 'package:time_tracker_client/services/events_repository.dart';
import 'package:time_tracker_client/services/mcp_client.dart';
import 'package:time_tracker_client/services/people_repository.dart';
import 'package:time_tracker_client/services/plan_memory.dart';
import 'package:time_tracker_client/services/proposal_repository.dart';
import 'package:time_tracker_client/widgets/day_timeline.dart';
import 'package:time_tracker_client/widgets/recap_markdown.dart';

void main() {
  final now = DateTime(2026, 9, 30, 12);
  DateTime at(int hour, [int minute = 0]) =>
      DateTime(2026, 9, 30, hour, minute);
  String iso(int hour, [int minute = 0]) => localIsoTimestamp(at(hour, minute));

  List<Event> calendar() => [
    Event(id: 'tea', start: at(9), end: at(10), summary: 'Tea'),
    Event(id: 'call', start: at(10), end: at(10, 30), summary: 'Call Mom'),
    Event(id: 'walk', start: at(11), end: at(11, 30), summary: 'Walk'),
  ];

  /// From 8 to noon: tea with someone new, at somewhere new, doing
  /// something new; the call to Mom dropped, counting against her
  /// follow-through; the walk just a change of plan.
  Map<String, Object?> proposalJson() => {
    'id': 'abc123def456',
    'revision': 2,
    'state': 'awaiting_review',
    'window_start': iso(8),
    'through': iso(12),
    'events': [
      {
        'id': 'tea',
        'summary': 'Tea',
        'start': iso(9),
        'end': iso(10),
        'status': 'adjusted',
        'action_ids': ['drink', 'new:matcha'],
        'facts': {
          'with_ids': ['sam', 'new:jo'],
          'location_ids': ['new:teahouse'],
        },
        'planned_start': iso(9),
        'planned_end': iso(10),
        'decided_by': 'claude',
      },
      {
        'id': 'call',
        'summary': 'Call Mom',
        'start': iso(10),
        'end': iso(10, 30),
        'status': 'cancelled',
        'decided_by': 'claude',
        'counts_against_follow_through': true,
        'follow_through': ['Mom (Reliable)'],
      },
      {
        'id': 'walk',
        'summary': 'Walk',
        'start': iso(11),
        'end': iso(11, 30),
        'status': 'cancelled',
        'decided_by': 'claude',
        'counts_against_follow_through': false,
        'follow_through': <String>[],
      },
    ],
    'additions': {
      'people': [
        {'ref': 'new:jo', 'name': 'Jo', 'context': "Sam's friend"},
      ],
      'actions': [
        {'ref': 'new:matcha', 'name': 'Make matcha'},
      ],
      'locations': [
        {'ref': 'new:teahouse', 'name': 'The teahouse', 'hint': 'on Elm'},
      ],
    },
  };

  test('reads whether each cancel counts, and against whom; and what it '
      'adds, and what the user settled', () {
    final proposal = Proposal.fromJson({
      ...proposalJson(),
      'settled_additions': [
        {'ref': 'new:old', 'use': 'existing', 'id': 'p1'},
        {'ref': 'new:gone', 'use': 'drop'},
      ],
    });
    expect([for (final e in proposal.cancels) e.id], ['call', 'walk']);
    final call = proposal.event('call')!;
    expect(call.countsAgainstFollowThrough, isTrue);
    expect(call.followThrough, ['Mom (Reliable)']);
    expect(proposal.event('walk')!.countsAgainstFollowThrough, isFalse);
    expect(
      [for (final a in proposal.additions) (a.kind, a.ref, a.name, a.detail)],
      [
        (AdditionKind.person, 'new:jo', 'Jo', "Sam's friend"),
        (AdditionKind.action, 'new:matcha', 'Make matcha', null),
        (AdditionKind.location, 'new:teahouse', 'The teahouse', 'on Elm'),
      ],
    );
    expect(
      [for (final s in proposal.settledAdditions) (s.ref, s.use, s.id)],
      [
        ('new:old', AdditionUse.existing, 'p1'),
        ('new:gone', AdditionUse.drop, null),
      ],
    );
    // A new action is named, on the event, by its ref.
    final tea = proposal.event('tea')!.toEvent(null, proposal.addedNames);
    expect(tea.actionNames, [null, 'Make matcha']);
  });

  test("reads Claude's recap: each point's kind, text, events and notes; "
      'and which events the user changed since', () {
    final proposal = Proposal.fromJson({
      ...proposalJson(),
      'recap': {
        ...recapJson(),
        'did': [
          {
            'text': 'Kept tea',
            'event_ids': ['tea'],
            'note_ids': ['n1'],
          },
          {'text': '  '},
        ],
      },
      'recap_revision': 1,
      'user_edits': [
        {
          'id': 'abc123def456u1',
          'event_id': 'tea',
          'edit': {'action': 'keep', 'event_id': 'tea'},
          'status': 'active',
          'base_revision': 1,
        },
        {
          'id': 'abc123def456u2',
          'event_id': 'walk',
          'edit': {'action': 'keep', 'event_id': 'walk'},
          'status': 'replaced',
          'base_revision': 1,
        },
        {
          'id': 'abc123def456u3',
          'edit': {'action': 'create', 'summary': 'Nap'},
          'status': 'active',
          'base_revision': 2,
        },
      ],
    });
    final recap = proposal.recap!;
    expect(recap.revision, 1);
    expect(
      [
        for (final p in recap.points)
          (p.kind, p.text, p.eventIds.join(','), p.noteIds.join(',')),
      ],
      [
        (RecapKind.overview, 'A **quiet** morning', '', ''),
        (RecapKind.did, 'Kept tea', 'tea', 'n1'),
        (
          RecapKind.unsure,
          'Whether the call counts against follow-through',
          'call',
          '',
        ),
      ],
    );
    expect(proposal.editedSinceRecap, {'tea', 'abc123def456u3'});
    // Kept by the app's own revisions.
    expect(proposal.copyWith(revision: 3).recap, same(recap));
    expect(Proposal.fromJson(proposalJson()).recap, isNull);
  });

  test("Claude's Markdown, as a line or two: bold and italics kept, list "
      'items each on a line with its bullet', () {
    final span = recapSpan('**Lunch** ran *late*:\n- one\n1. two');
    expect(span.toPlainText(), 'Lunch ran late:\n• one\n1. two');
    final bold = <String>[];
    void walk(InlineSpan s) {
      if (s is! TextSpan) return;
      if (s.style?.fontWeight == FontWeight.w700) bold.add(s.toPlainText());
      s.children?.forEach(walk);
    }

    walk(span);
    expect(bold, ['Lunch']);
  });

  test('settling additions, in amend_proposal', () {
    const edits = ProposalEdits(
      additions: [
        (
          ref: 'new:jo',
          use: AdditionUse.create,
          id: null,
          name: 'Jo B.',
          detail: 'from work',
          kind: AdditionKind.person,
          deadline: null,
          fields: null,
        ),
        (
          ref: 'new:teahouse',
          use: AdditionUse.existing,
          id: 'cafe',
          name: null,
          detail: null,
          kind: AdditionKind.location,
          deadline: null,
          fields: null,
        ),
        (
          ref: 'new:matcha',
          use: AdditionUse.drop,
          id: null,
          name: null,
          detail: null,
          kind: AdditionKind.action,
          deadline: null,
          fields: null,
        ),
      ],
      asPlanned: ['new:old'],
    );
    expect(edits.toJson(), {
      'as_planned': ['new:old'],
      'additions': [
        {
          'ref': 'new:jo',
          'use': 'create',
          'name': 'Jo B.',
          'context': 'from work',
        },
        {'ref': 'new:teahouse', 'use': 'existing', 'id': 'cafe'},
        {'ref': 'new:matcha', 'use': 'drop'},
      ],
    });
  });

  group('on the Events page', () {
    late InMemoryEventsRepository events;
    late _Proposals proposals;
    late InMemoryPeopleRepository people;

    Future<void> open(
      WidgetTester tester, {
      Map<String, Object?> extra = const {},
    }) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      events = InMemoryEventsRepository(calendar());
      people = InMemoryPeopleRepository(
        people: [
          const Person(id: 'sam', name: 'Sam'),
          const Person(id: 'joanne', name: 'Joanne', context: 'from work'),
        ],
        locations: [const Location(id: 'cafe', name: 'The café')],
        locationGroups: [const LocationGroup(id: 'elm', name: 'Elm St')],
      );
      proposals = _Proposals(
        Proposal.fromJson({...proposalJson(), ...extra}),
        events: events,
        people: people,
      );
      await tester.pumpWidget(
        PeopleScope(
          repository: people,
          child: PlanMemoryScope(
            memory: PlanMemory(),
            child: MaterialApp(
              home: EventsScreen(
                repository: events,
                serverLabel: 'offline demo',
                proposals: proposals,
                proposalSeen: ProposalSeenStore(persist: false),
                clock: () => now,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    /// Turns the details to [title]'s page.
    Future<void> page(WidgetTester tester, String title) async {
      await tester.tap(find.text(title));
      await tester.pumpAndSettle();
    }

    Set<String> outlined(WidgetTester tester) => {
      for (final MapEntry(:key, :value)
          in tester.widget<DayTimeline>(find.byType(DayTimeline)).marks.entries)
        if (value.selected) key,
    };

    testWidgets('turned to, the follow-through and added pages scroll the '
        'timeline to the cancel shown, and where what is added is used', (
      tester,
    ) async {
      await open(tester);
      final scrollable = find
          .descendant(
            of: find.byType(ListView),
            matching: find.byWidgetPredicate(
              (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
            ),
          )
          .first;
      final position = tester.state<ScrollableState>(scrollable).position;
      final today = find.byKey(ValueKey(('shown', at(0))));
      // Where [time] is on screen, from the middle of the timeline's view.
      double fromMiddle(DateTime time) =>
          tester.getTopLeft(today).dy +
          timelineOffset(
            time,
            day: at(0),
            dayEnd: DateTime(2026, 10, 1),
            scale: defaultTimelineScale,
          ) -
          tester.getRect(scrollable).center.dy;

      // It opens on the follow-through page: turned from it and back.
      position.jumpTo(position.maxScrollExtent);
      await tester.pumpAndSettle();
      await page(tester, 'Added (3)');
      expect(outlined(tester), {'tea'});
      expect(fromMiddle(at(9)), moreOrLessEquals(0, epsilon: 16));

      position.jumpTo(position.maxScrollExtent);
      await tester.pumpAndSettle();
      await page(tester, 'Follow-through (1 of 2)');
      expect(outlined(tester), {'call'});
      expect(fromMiddle(at(10)), moreOrLessEquals(0, epsilon: 16));
    });

    testWidgets('under the bar, pages of how many cancels count against '
        'follow-through, and what it adds; folded away and back', (
      tester,
    ) async {
      await open(tester);
      expect(find.text('Follow-through (1 of 2)'), findsOneWidget);
      expect(find.text('Added (3)'), findsOneWidget);

      await tester.tap(
        find.byTooltip(
          'Hide Claude’s recap, notes, follow-through and additions',
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Added (3)'), findsNothing);
      await tester.tap(
        find.byTooltip(
          'Show Claude’s recap, notes, follow-through and additions',
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Added (3)'), findsOneWidget);
    });

    testWidgets('steps through the cancels, the one shown outlined; its '
        'switch says whether it counts', (tester) async {
      await open(tester);
      await page(tester, 'Follow-through (1 of 2)');
      expect(find.textContaining('Call Mom'), findsWidgets);
      expect(
        find.text('Counts against Mom (Reliable) · Claude'),
        findsOneWidget,
      );
      expect(outlined(tester), {'call'});

      await tester.tap(find.byTooltip('Next cancel'));
      await tester.pumpAndSettle();
      expect(
        find.text('A change of plan: no one’s follow-through · Claude'),
        findsOneWidget,
      );
      expect(outlined(tester), {'walk'});

      // It does count, after all.
      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();
      expect(proposals.amends.single.toJson(), {
        'cancels': [
          {'event_id': 'walk', 'counts_against_follow_through': true},
        ],
      });
      expect(find.text('Follow-through (2 of 2)'), findsOneWidget);
    });

    testWidgets('tapping a cancel shows it in full: when, who said so, and '
        'who it counts against; its switch saves, staying open; and putting '
        'it back', (tester) async {
      await open(tester);
      expect(
        find.text('Cancelled, counts against Mom (Reliable) · Claude'),
        findsOneWidget,
      );
      await tester.ensureVisible(find.text('Call Mom').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Call Mom').last);
      await tester.pumpAndSettle();
      expect(find.text("“Call Mom” didn't happen"), findsOneWidget);
      expect(
        find.text('10:00 AM – 10:30 AM · Cancelled by Claude'),
        findsOneWidget,
      );
      expect(find.text('It counts against:'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text('Mom (Reliable)'),
        ),
        findsOneWidget,
      );

      // A change of plan, after all: saved, the dialog still open, saying
      // so.
      await tester.tap(find.byType(SwitchListTile));
      await tester.pumpAndSettle();
      expect(proposals.amends.last.toJson(), {
        'cancels': [
          {'event_id': 'call', 'counts_against_follow_through': false},
        ],
      });
      expect(find.text("“Call Mom” didn't happen"), findsOneWidget);
      expect(
        find.text('A change of plan: no one’s follow-through'),
        findsOneWidget,
      );
      expect(find.text('It counts against:'), findsNothing);
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      expect(find.text('Follow-through (0 of 2)'), findsOneWidget);

      // Put back as planned.
      await tester.tap(find.text('Call Mom').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Put it back'));
      await tester.pumpAndSettle();
      expect(proposals.amends.last.asPlanned, ['call']);
    });

    testWidgets("a change the server refuses is said in the error sheet, "
        "and the switch stays as it was", (tester) async {
      await open(tester);
      proposals.error = McpException('amend_proposal: the call is history');
      await tester.ensureVisible(find.text('Call Mom').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Call Mom').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byType(SwitchListTile));
      await tester.pumpAndSettle();
      expect(find.text("Couldn't change it"), findsOneWidget);
      expect(find.text('amend_proposal: the call is history'), findsOneWidget);
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
        isTrue,
      );
    });

    testWidgets('what it adds is named, not by its ref; and settled: made '
        'now, corrected, one already here, dropped, or put back', (
      tester,
    ) async {
      await open(tester);
      // On its event, and in the day's summary of actions.
      expect(find.text('Make matcha'), findsWidgets);
      expect(find.textContaining('new:matcha'), findsNothing);
      await page(tester, 'Added (3)');
      expect(find.textContaining('Jo'), findsWidgets);
      expect(find.textContaining("Sam's friend"), findsOneWidget);
      expect(outlined(tester), {'tea'});

      Future<void> settle(String choice) async {
        await tester.tap(find.byTooltip('Settle it').first);
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(
          find.text(choice),
          100,
          scrollable: find
              .descendant(
                of: find.byType(BottomSheet),
                matching: find.byType(Scrollable),
              )
              .first,
        );
        await tester.tap(find.text(choice));
        await tester.pumpAndSettle();
      }

      // Jo, made now, corrected, in the New person sheet.
      await settle('Make it now');
      expect(find.text('New person'), findsOneWidget);
      await tester.enterText(
        find
            .descendant(
              of: find.byType(BottomSheet),
              matching: find.byType(TextField),
            )
            .first,
        'Jo B.',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add'));
      await tester.pumpAndSettle();
      expect(proposals.amends.last.toJson(), {
        'additions': [
          {
            'ref': 'new:jo',
            'use': 'create',
            'name': 'Jo B.',
            'fields': {'context': "Sam's friend"},
          },
        ],
      });
      expect(
        (await people.people()).people.map((p) => p.name),
        contains('Jo B.'),
      );
      expect(find.textContaining('Made now · you'), findsOneWidget);
      // Tea names them by their id now.
      final tea = proposals.proposal!.event('tea')!;
      expect(tea.facts!['with_ids'], ['sam', isNot('new:jo')]);

      // Put back, to settle later.
      await tester.tap(find.byTooltip('Change how it’s settled'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Put it back as Claude proposed it'));
      await tester.pumpAndSettle();
      expect(proposals.amends.last.asPlanned, ['new:jo']);
      expect(proposals.proposal!.event('tea')!.facts!['with_ids'], [
        'sam',
        'new:jo',
      ]);

      // Jo's someone already here: Joanne.
      await settle('Joanne');
      expect(proposals.amends.last.toJson(), {
        'additions': [
          {'ref': 'new:jo', 'use': 'existing', 'id': 'joanne'},
        ],
      });
      expect(find.textContaining('Already here: Joanne · you'), findsOneWidget);

      // The new action isn't real.
      await tester.tap(find.byTooltip('Next addition'));
      await tester.pumpAndSettle();
      await settle('Drop it');
      expect(proposals.amends.last.toJson(), {
        'additions': [
          {'ref': 'new:matcha', 'use': 'drop'},
        ],
      });
      expect(proposals.proposal!.event('tea')!.actionIds, ['drink']);
      expect(find.textContaining('Dropped: not real'), findsOneWidget);
    });

    testWidgets('a location made now is put in the group picked in its '
        'sheet, with its hint as Claude has it', (tester) async {
      await open(tester);
      await page(tester, 'Added (3)');
      for (var i = 0; i < 2; i++) {
        await tester.tap(find.byTooltip('Next addition'));
        await tester.pumpAndSettle();
      }
      await tester.tap(find.byTooltip('Settle it').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Make it now'));
      await tester.pumpAndSettle();
      expect(find.text('New location'), findsOneWidget);
      expect(find.text('on Elm'), findsOneWidget);

      await tester.tap(find.text('Group (optional)'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Elm St').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add'));
      await tester.pumpAndSettle();

      expect(proposals.amends.last.toJson(), {
        'additions': [
          {
            'ref': 'new:teahouse',
            'use': 'create',
            'name': 'The teahouse',
            'fields': {'hint': 'on Elm', 'group_id': 'elm'},
          },
        ],
      });
      final made = (await people.locations()).singleWhere(
        (l) => l.name == 'The teahouse',
      );
      expect((made.hint, made.groupId), ('on Elm', 'elm'));
      expect(find.text('New location'), findsNothing);
    });

    testWidgets('asks Claude about what it adds, in a note naming it by its '
        'ref', (tester) async {
      await open(tester);
      await page(tester, 'Added (3)');
      await tester.tap(find.byTooltip('Settle it'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Ask Claude about it'));
      await tester.pumpAndSettle();
      expect(find.text('About the new person “Jo”'), findsOneWidget);
      await tester.enterText(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.byType(TextField),
        ),
        "That's Joanne",
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Leave note'));
      await tester.pumpAndSettle();
      final asked = proposals.proposal!.feedback.last;
      expect((asked.text, asked.eventId), ("That's Joanne", 'new:jo'));
    });

    testWidgets("an event's dialogs name what's added, marked new", (
      tester,
    ) async {
      await open(tester);
      await tester.ensureVisible(find.text('Tea'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Tea'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Jo (new)'), findsOneWidget);
      expect(find.textContaining('The teahouse (new)'), findsOneWidget);
      expect(find.textContaining('new:'), findsNothing);
    });

    /// Opens Tea, and its dialog's facts: the location shown by [name],
    /// not by its id, nor as new.
    Future<void> expectTeaAt(WidgetTester tester, String name) async {
      final id = (await people.locations())
          .singleWhere((l) => l.name == name)
          .id;
      await tester.ensureVisible(find.text('Tea').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Tea').first);
      await tester.pumpAndSettle();
      expect(find.textContaining(name), findsWidgets);
      expect(find.textContaining('$name (new)'), findsNothing);
      expect(find.textContaining(id), findsNothing);
    }

    testWidgets("a location made elsewhere -- Claude settling what it adds "
        "-- is named once a revision naming it is shown", (tester) async {
      await open(tester);
      await proposals.amend(
        proposals.proposal!,
        const ProposalEdits(
          additions: [
            (
              ref: 'new:teahouse',
              use: AdditionUse.create,
              id: null,
              name: null,
              detail: null,
              kind: AdditionKind.location,
              deadline: null,
              fields: null,
            ),
          ],
        ),
      );
      // Any change here shows the revision that names it by its id.
      await page(tester, 'Follow-through (1 of 2)');
      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();
      await expectTeaAt(tester, 'The teahouse');
    });

    testWidgets('a location made as the proposal is applied is named on its '
        'event, not by its id', (tester) async {
      await open(tester);
      proposals.onConfirm = (proposal) async {
        // Made as it's applied, and the event moved onto it.
        final made = await people.createLocation(
          const Location(id: '', name: 'The teahouse'),
        );
        await events.updateEvent(Event(id: 'tea', start: at(9), end: at(10)), {
          'summary': 'Tea',
          'facts': {
            'location_ids': [made.id],
          },
        });
        return ProposalOutcome(
          status: ProposalOutcomeStatus.applied,
          proposal: proposal.copyWith(state: ProposalState.applied),
        );
      };
      await tester.tap(find.widgetWithText(FilledButton, 'Confirm'));
      await tester.pumpAndSettle();
      expect(proposals.calls, contains('confirm_proposal'));
      await expectTeaAt(tester, 'The teahouse');
    });

    group("Claude's recap", () {
      Future<void> openRecap(
        WidgetTester tester, {
        Map<String, Object?> extra = const {},
      }) => open(tester, extra: {'recap': recapJson(), ...extra});

      testWidgets('is the page shown first, stepped through point by point, '
          'the events each names outlined', (tester) async {
        await openRecap(tester);
        expect(find.text('Claude (1 unsure)'), findsOneWidget);
        expect(find.textContaining('A quiet morning'), findsOneWidget);
        expect(outlined(tester), isEmpty);

        await tester.tap(find.byTooltip('Next point'));
        await tester.pumpAndSettle();
        expect(find.textContaining('Kept tea as planned'), findsOneWidget);
        expect(find.text('Tea, Walk'), findsOneWidget);
        expect(outlined(tester), {'tea', 'walk'});

        await tester.tap(find.byTooltip('Next point'));
        await tester.pumpAndSettle();
        expect(find.textContaining('Whether the call'), findsOneWidget);
        expect(outlined(tester), {'call'});
        expect(find.byTooltip('Next point'), findsOneWidget);
        expect(
          tester
              .widget<IconButton>(
                find.widgetWithIcon(IconButton, Icons.keyboard_arrow_down),
              )
              .onPressed,
          isNull,
        );
      });

      testWidgets('tapping a point opens it in full, its points in Markdown '
          'under what Claude did and what it isn’t sure of; a chip goes to its '
          'event', (tester) async {
        await openRecap(tester);
        // The point itself opens it: there's no button beside it.
        expect(find.byIcon(Icons.open_in_full), findsNothing);
        await tester.tap(find.textContaining('A quiet morning'));
        await tester.pumpAndSettle();
        expect(find.text('What Claude did'), findsOneWidget);
        expect(find.text('What Claude isn’t sure of'), findsOneWidget);
        // Its list, item by item, each with its bullet.
        expect(find.text('•'), findsNWidgets(2));
        expect(find.text('the walk was short'), findsOneWidget);

        await tester.tap(find.widgetWithText(ActionChip, 'Walk, 11:00 AM'));
        await tester.pumpAndSettle();
        expect(find.text('What Claude did'), findsNothing);
        expect(find.textContaining('Kept tea as planned'), findsOneWidget);
        expect(outlined(tester), {'tea', 'walk'});
      });

      testWidgets('answers a point Claude is unsure of, in a note about its '
          'event quoting it; shown under it, waiting for Claude, in the strip '
          'and in full', (tester) async {
        await openRecap(tester);
        await tester.tap(find.textContaining('A quiet morning'));
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(ActionChip, 'Answer Claude'));
        await tester.pumpAndSettle();
        expect(
          find.text(
            'Answering Claude: “Whether the call counts against '
            'follow-through”',
          ),
          findsOneWidget,
        );
        await tester.enterText(
          find.descendant(
            of: find.byType(AlertDialog),
            matching: find.byType(TextField),
          ),
          'It counts',
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Leave note'));
        await tester.pumpAndSettle();
        final asked = proposals.proposal!.feedback.last;
        expect(
          (asked.text, asked.eventId),
          (
            'Re: “Whether the call counts against follow-through”\n\nIt counts',
            'call',
          ),
        );
        expect(
          (asked.quoted, asked.body),
          ('Whether the call counts against follow-through', 'It counts'),
        );

        // The page counts it; the point says so.
        expect(find.text('Claude (1 waiting · 1 unsure)'), findsOneWidget);
        await tester.tap(find.byTooltip('Next point'));
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('Next point'));
        await tester.pumpAndSettle();
        expect(
          find.text('Call Mom · you answered: waiting for Claude'),
          findsOneWidget,
        );
        // In full, under the point it answers -- not among the other notes.
        await tester.tap(find.textContaining('Whether the call'));
        await tester.pumpAndSettle();
        expect(find.text('You answered · waiting for Claude'), findsOneWidget);
        expect(find.text('It counts'), findsOneWidget);
        expect(find.text('Notes for Claude'), findsNothing);
      });

      testWidgets("a note for Claude that answers no point shows after the "
          "recap's points, with Claude's reply", (tester) async {
        await openRecap(
          tester,
          extra: {
            'feedback': [
              {
                'id': 'abc123def456f1',
                'text': 'Tea ran long',
                'event_id': 'tea',
                'status': 'answered',
                'reply': 'Moved its end to 10.',
                'answered_in': 2,
              },
              {
                'id': 'abc123def456f2',
                'text': 'Re: “Something Claude no longer says”\n\nYes',
                'status': 'answered',
                'reply': 'Thanks.',
                'answered_in': 2,
              },
            ],
          },
        );
        await tester.tap(find.textContaining('A quiet morning'));
        await tester.pumpAndSettle();
        await tester.drag(find.text('What Claude did'), const Offset(0, -400));
        await tester.pumpAndSettle();
        expect(find.text('Notes for Claude'), findsOneWidget);
        expect(find.text('Tea ran long'), findsOneWidget);
        expect(find.text('Moved its end to 10.'), findsOneWidget);
        // Its point's gone: the quote says what it answered.
        expect(
          find.text('Answering Claude: “Something Claude no longer says”'),
          findsOneWidget,
        );
        expect(find.text('Yes'), findsOneWidget);
      });

      testWidgets('says when the user has changed what a point is about '
          'since Claude wrote it', (tester) async {
        await openRecap(
          tester,
          extra: {
            'recap_revision': 1,
            'user_edits': [
              {
                'id': 'abc123def456u1',
                'event_id': 'walk',
                'edit': {'action': 'keep', 'event_id': 'walk'},
                'status': 'active',
                'base_revision': 1,
              },
            ],
          },
        );
        await tester.tap(find.byTooltip('Next point'));
        await tester.pumpAndSettle();
        expect(
          find.text('Tea, Walk · you’ve changed it since'),
          findsOneWidget,
        );
        await tester.tap(find.textContaining('Kept tea as planned'));
        await tester.pumpAndSettle();
        expect(find.textContaining('Written for revision 1'), findsOneWidget);
        expect(
          find.text('You’ve changed what it’s about since'),
          findsOneWidget,
        );
      });

      testWidgets('without one, the details open on the notes as before', (
        tester,
      ) async {
        await open(tester);
        expect(find.textContaining('Claude ('), findsNothing);
      });
    });
  });
}

/// Claude's recap of [proposalJson]: an overview, what it did -- a list
/// in it -- and what it's unsure of.
Map<String, Object?> recapJson() => {
  'overview': 'A **quiet** morning',
  'did': [
    {
      'text': 'Kept tea as planned:\n- *Sam* came\n- the walk was short',
      'event_ids': ['tea', 'walk'],
    },
  ],
  'unsure': [
    {
      'text': 'Whether the call counts against follow-through',
      'event_ids': ['call'],
    },
  ],
};

/// An in-memory proposal that records the edits made to it.
class _Proposals extends InMemoryProposalRepository {
  _Proposals(super.proposal, {super.events, super.people});

  final amends = <ProposalEdits>[];
  Object? error;

  @override
  Future<Proposal> amend(
    Proposal proposal,
    ProposalEdits edits, {
    bool allowHistory = false,
  }) async {
    if (error case final error?) throw error;
    final amended = await super.amend(proposal, edits);
    amends.add(edits);
    return amended;
  }
}
