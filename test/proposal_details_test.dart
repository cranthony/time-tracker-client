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
          'location_id': 'new:teahouse',
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
        ),
        (
          ref: 'new:teahouse',
          use: AdditionUse.existing,
          id: 'cafe',
          name: null,
          detail: null,
          kind: AdditionKind.location,
        ),
        (
          ref: 'new:matcha',
          use: AdditionUse.drop,
          id: null,
          name: null,
          detail: null,
          kind: AdditionKind.action,
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

    Future<void> open(WidgetTester tester) async {
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
      );
      proposals = _Proposals(
        Proposal.fromJson(proposalJson()),
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

    testWidgets('under the bar, pages of how many cancels count against '
        'follow-through, and what it adds; folded away and back', (
      tester,
    ) async {
      await open(tester);
      expect(find.text('Follow-through (1 of 2)'), findsOneWidget);
      expect(find.text('Added (3)'), findsOneWidget);

      await tester.tap(
        find.byTooltip('Hide notes, follow-through and additions'),
      );
      await tester.pumpAndSettle();
      expect(find.text('Added (3)'), findsNothing);
      await tester.tap(
        find.byTooltip('Show notes, follow-through and additions'),
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

      // Jo, made now, corrected.
      await settle('Make it now');
      await tester.enterText(
        find
            .descendant(
              of: find.byType(AlertDialog),
              matching: find.byType(TextField),
            )
            .first,
        'Jo B.',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Make it'));
      await tester.pumpAndSettle();
      expect(proposals.amends.last.toJson(), {
        'additions': [
          {
            'ref': 'new:jo',
            'use': 'create',
            'name': 'Jo B.',
            'context': "Sam's friend",
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
  });
}

/// An in-memory proposal that records the edits made to it.
class _Proposals extends InMemoryProposalRepository {
  _Proposals(super.proposal, {super.events, super.people});

  final amends = <ProposalEdits>[];
  Object? error;

  @override
  Future<Proposal> amend(Proposal proposal, ProposalEdits edits) async {
    if (error case final error?) throw error;
    final amended = await super.amend(proposal, edits);
    amends.add(edits);
    return amended;
  }
}
