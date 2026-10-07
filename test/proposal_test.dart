// Compaction proposals: the model, the server's tools, and reviewing one
// on the Events page -- the band of what happened, edits to it, notes for
// Claude and confirming it.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:time_tracker_client/models/event.dart';
import 'package:time_tracker_client/models/note.dart';
import 'package:time_tracker_client/models/proposal.dart';
import 'package:time_tracker_client/screens/events_screen.dart';
import 'package:time_tracker_client/services/events_repository.dart';
import 'package:time_tracker_client/services/mcp_client.dart';
import 'package:time_tracker_client/services/proposal_repository.dart';
import 'package:time_tracker_client/widgets/day_timeline.dart';
import 'package:time_tracker_client/widgets/other_events.dart';

void main() {
  final now = DateTime(2026, 9, 30, 12);
  DateTime at(int hour, [int minute = 0]) =>
      DateTime(2026, 9, 30, hour, minute);
  String iso(int hour, [int minute = 0]) => localIsoTimestamp(at(hour, minute));

  /// The calendar: tea, work and a walk this morning, a talk this
  /// afternoon.
  List<Event> calendar() => [
    Event(id: 'tea', start: at(9), end: at(10), summary: 'Tea'),
    Event(id: 'work', start: at(10), end: at(11), summary: 'Work'),
    Event(id: 'walk', start: at(11), end: at(11, 30), summary: 'Walk'),
    Event(id: 'talk', start: at(14), end: at(15), summary: 'Talk'),
  ];

  /// What Claude says happened from 8 to noon: tea started late, the
  /// walk didn't happen, and an email did.
  Map<String, Object?> proposalJson({
    String state = 'awaiting_review',
    List<Map<String, Object?>> feedback = const [],
  }) => {
    'id': 'abc123def456',
    'revision': 2,
    'state': state,
    'window_start': iso(8),
    'through': iso(12),
    'events': [
      {
        'id': 'tea',
        'summary': 'Tea',
        'start': iso(9, 15),
        'end': iso(10),
        'status': 'adjusted',
        'planned_start': iso(9),
        'planned_end': iso(10),
        'decided_by': 'claude',
      },
      {
        'id': 'work',
        'summary': 'Work',
        'start': iso(10),
        'end': iso(11),
        'status': 'on_schedule',
      },
      {
        'id': 'walk',
        'summary': 'Walk',
        'start': iso(11),
        'end': iso(11, 30),
        'status': 'cancelled',
        'decided_by': 'claude',
      },
      {
        'id': 'abc123def456c1',
        'summary': 'Email',
        'start': iso(11, 30),
        'end': iso(11, 45),
        'status': 'new',
        'decided_by': 'claude',
      },
      {
        'id': 'talk',
        'summary': 'Talk',
        'start': iso(14),
        'end': iso(15),
        'status': 'planned',
      },
    ],
    'feedback': feedback,
    // What each note is for: an edge, added to an event, left out.
    'notes': [
      {'id': 'n0#0', 'timestamp': iso(7), 'description': 'Up', 'use': 'unused'},
      {
        'id': 'n1#1',
        'timestamp': iso(9, 15),
        'description': 'Tea at last',
        'use': 'edge',
        'event_id': 'tea',
        'edge_of': 'tea',
      },
      {
        'id': 'n3#3',
        'timestamp': iso(11, 10),
        'description': 'Rain',
        'use': 'ignored',
        'decided_by': 'claude',
      },
      {
        'id': 'n2#2',
        'timestamp': iso(10, 30),
        'description': 'Bugs',
        'use': 'annotates',
        'event_id': 'work',
      },
    ],
    // As a server before notes said what they're for has them too.
    'timeline': {
      'text': '09:15 Tea',
      'notes': [
        {'id': 'n0#0', 'time': iso(7), 'text': 'Up', 'compacted': true},
        {
          'id': 'n1#1',
          'time': iso(9, 15),
          'text': 'Tea at last',
          'anchors': ['start of Tea'],
        },
        {'id': 'n3#3', 'time': iso(11, 10), 'text': 'Rain', 'ignored': true},
        {
          'id': 'n2#2',
          'time': iso(10, 30),
          'text': 'Bugs',
          'annotates': 'Work',
        },
      ],
    },
  };

  group('Proposal', () {
    test('reads get_proposal', () {
      final proposal = Proposal.fromJson({
        ...proposalJson(
          feedback: [
            {
              'id': 'abc123def456f1',
              'text': 'Tea was later',
              'event_id': 'tea',
              'by': 'user',
              'status': 'answered',
              'reply': 'Moved it to 9:15.',
              'answered_in': 2,
            },
            {
              'id': 'abc123def456f2',
              'text': "Couldn't apply",
              'by': 'server',
              'status': 'open',
            },
          ],
        ),
        'changed_since': ['tea'],
      });
      expect(proposal.revision, 2);
      expect(proposal.state, ProposalState.awaitingReview);
      expect(proposal.windowStart.isAtSameMomentAs(at(8)), isTrue);
      expect(proposal.through.isAtSameMomentAs(at(12)), isTrue);
      expect(proposal.timeline, '09:15 Tea');
      expect(proposal.changedSince, {'tea'});
      expect(
        [for (final e in proposal.reviewed) e.id],
        ['tea', 'work', 'walk', 'abc123def456c1'],
      );
      final tea = proposal.event('tea')!;
      expect(tea.moved, isTrue);
      expect(tea.decidedBy, DecidedBy.claude);
      expect(proposal.event('walk')!.live, isFalse);
      expect(proposal.event('talk')!.reviewed, isFalse);
      expect(proposal.feedback.first.reply, 'Moved it to 9:15.');
      expect(proposal.feedback.last.byUser, isFalse);
      // A note open: waiting for Claude.
      expect(proposal.openFeedback, hasLength(1));
      expect(proposal.confirmable, isFalse);
    });

    test('its notes, by time, each saying what it is for and who said '
        "so -- with the timeline's words for the edges it sets -- but those "
        'already compacted', () {
      final notes = Proposal.fromJson(proposalJson()).notes;
      expect(
        [for (final n in notes) (n.id, n.use, n.eventId, n.decidedBy)],
        [
          ('n1#1', NoteUse.edge, 'tea', null),
          ('n2#2', NoteUse.annotates, 'work', null),
          ('n3#3', NoteUse.ignored, null, DecidedBy.claude),
        ],
      );
      expect(notes[0].anchors, ['start of Tea']);
      expect(notes[0].edgeOf, 'tea');
      // From a server that doesn't say what each is for: the timeline.
      final older = Proposal.fromJson({...proposalJson(), 'notes': null}).notes;
      expect(
        [for (final n in older) (n.id, n.use)],
        [
          ('n1#1', NoteUse.edge),
          ('n2#2', NoteUse.annotates),
          ('n3#3', NoteUse.ignored),
        ],
      );
      // Without a timeline either, just its notes.
      final plain = Proposal.fromJson({
        ...proposalJson(),
        'timeline': null,
        'notes': [
          {'id': 'n1#1', 'timestamp': iso(9, 15), 'description': 'Tea'},
        ],
      }).notes;
      expect([for (final n in plain) (n.id, n.text)], [('n1#1', 'Tea')]);
    });

    test("an event without times of its own is where the calendar has it; "
        'without either, left out', () {
      final proposal = Proposal.fromJson({
        ...proposalJson(),
        'events': [
          {
            'id': 'walk',
            'start': null,
            'end': null,
            'planned_start': iso(11),
            'planned_end': iso(11, 30),
            'status': 'merged',
          },
          {'id': 'gone', 'status': 'cancelled'},
        ],
      });
      expect([for (final e in proposal.events!) e.id], ['walk']);
      expect(proposal.event('walk')!.start.isAtSameMomentAs(at(11)), isTrue);
    });

    test('an event shown is cancelled if the proposal cancels it, over '
        "the calendar's own", () {
      final proposal = Proposal.fromJson(proposalJson());
      final walk = proposal
          .event('walk')!
          .toEvent(
            Event.fromJson({
              'id': 'walk',
              'start': iso(11),
              'end': iso(11, 30),
              'effective_priority': 1,
            }),
          );
      expect(walk.isCancelled, isTrue);
      expect(walk.effectivePriority, 1);
      expect(walk.properties.containsKey('status'), isFalse);
    });
  });

  group('edits', () {
    final tea = Event.fromJson({
      'id': 'tea',
      'start': iso(9),
      'end': iso(10),
      'description': 'Green',
    });

    test('an update sets summary, times, actions and facts', () {
      expect(
        proposalUpdate(tea, {
          'summary': 'Chai',
          'start': iso(9, 15),
          'action_ids': ['drink'],
          'facts': null,
        }),
        {
          'event_id': 'tea',
          'summary': 'Chai',
          'start': iso(9, 15),
          'action_ids': ['drink'],
          // Empty facts remove them.
          'facts': const <String, Object?>{},
        },
      );
    });

    test('a description can only be added to: the addition is annotated', () {
      expect(proposalUpdate(tea, {'description': 'Green\nwith honey'}), {
        'event_id': 'tea',
        'annotate': 'with honey',
      });
      expect(
        () => proposalUpdate(tea, {'description': 'Black'}),
        throwsA(isA<ProposalEditException>()),
      );
    });

    test("what a proposal doesn't set is refused", () {
      expect(
        () => proposalUpdate(tea, {'priority': 1}),
        throwsA(
          isA<ProposalEditException>().having(
            (e) => e.message,
            'message',
            contains("Its priority can't be changed"),
          ),
        ),
      );
      expect(
        () => proposalCreate({'summary': 'Tea', 'location': 'Cafe'}),
        throwsA(isA<ProposalEditException>()),
      );
    });

    test("the events in a new one's way: trimmed, cancelled as changes of "
        'plan, and the rest of one split, as creates', () {
      final work = Event.fromJson({
        'id': 'work',
        'start': iso(10),
        'end': iso(11),
        'summary': 'Work',
        'location': 'Office',
        'action_ids': ['w'],
      });
      final edits = ProposalEdits.over(
        Overwrite(
          updates: [
            (tea, {'end': iso(9, 30)}),
          ],
          cancels: [work],
          creates: [
            {
              'summary': 'Work',
              'location': 'Office',
              'start': iso(10, 30),
              'end': iso(11),
            },
          ],
        ),
        creates: [
          {'summary': 'Email', 'start': iso(9, 30), 'end': iso(10)},
        ],
      );
      expect(edits.toJson(), {
        'updates': [
          {'event_id': 'tea', 'end': iso(9, 30)},
        ],
        'creates': [
          {'summary': 'Email', 'start': iso(9, 30), 'end': iso(10)},
          // Where the split one was is its; its location the calendar's.
          {'summary': 'Work', 'start': iso(10, 30), 'end': iso(11)},
        ],
        'cancels': [
          {'event_id': 'work', 'counts_against_follow_through': false},
        ],
      });
      expect(edits.eventIds, {'tea', 'work'});
    });
  });

  group('McpProposalRepository', () {
    test('asks for the open proposal, with what changed since a revision; '
        'none when none is open', () async {
      var open = true;
      final client = _Client(
        (name, _) => switch (name) {
          'get_compaction_status' => {
            'last_compaction': iso(8),
            'proposal': open
                ? {'id': 'abc123def456', 'revision': 2, 'open_feedback': 0}
                : null,
          },
          'get_proposal' => {
            ...proposalJson(),
            'changed_since': ['tea'],
          },
          _ => null,
        },
      );
      final repository = McpProposalRepository(client);
      final proposal = await repository.current(sinceRevision: 1);
      expect(_calls(client), [
        ['get_compaction_status', <String, Object?>{}],
        [
          'get_proposal',
          {'proposal_id': 'abc123def456', 'since_revision': 1},
        ],
      ]);
      expect(proposal!.changedSince, {'tea'});

      open = false;
      expect(await repository.current(), isNull);
    });

    test('amends, from the revision shown; a refusal throws', () async {
      final client = _Client(
        (name, args) => args['revision'] == 1
            ? {
                ...proposalJson(),
                'refused': ['tea: overlaps Work'],
              }
            : {
                ...proposalJson(),
                'revision': 3,
                'replaced': ['tea'],
              },
      );
      final repository = McpProposalRepository(client);
      final proposal = Proposal.fromJson(proposalJson());
      final amended = await repository.amend(
        proposal,
        const ProposalEdits(
          cancels: [(eventId: 'work', countsAgainstFollowThrough: true)],
          asPlanned: ['tea', 'n1#1'],
          notes: [
            (noteId: 'n2#2', ignore: true, eventId: null),
            (noteId: 'n3#3', ignore: false, eventId: 'tea'),
          ],
        ),
      );
      expect(_calls(client), [
        [
          'amend_proposal',
          {
            'proposal_id': 'abc123def456',
            'revision': 2,
            'cancels': [
              {'event_id': 'work', 'counts_against_follow_through': true},
            ],
            'as_planned': ['tea', 'n1#1'],
            'notes': [
              {'note_id': 'n2#2', 'use': 'ignore'},
              {'note_id': 'n3#3', 'use': 'annotate', 'event_id': 'tea'},
            ],
          },
        ],
      ]);
      expect(amended.revision, 3);
      expect(amended.replaced, ['tea']);

      await expectLater(
        repository.amend(
          Proposal.fromJson({...proposalJson(), 'revision': 1}),
          const ProposalEdits(asPlanned: ['tea']),
        ),
        throwsA(
          isA<McpException>().having(
            (e) => e.message,
            'message',
            contains('tea: overlaps Work'),
          ),
        ),
      );
    });

    test(
      'leaves and withdraws notes; confirms, finishes and abandons',
      () async {
        final client = _Client(
          (name, _) => switch (name) {
            'add_proposal_note' => {
              'id': 'abc123def456f1',
              'text': 'Tea was later',
              'event_id': 'tea',
              'status': 'open',
            },
            'confirm_proposal' => {
              'status': 'rechecked',
              'message': 'The calendar changed.',
              'proposal': {...proposalJson(), 'revision': 3},
            },
            'finish_proposal' => {'status': 'rebuilt'},
            _ => null,
          },
        );
        final repository = McpProposalRepository(client);
        final proposal = Proposal.fromJson(proposalJson());
        final note = await repository.addNote(
          proposal,
          'Tea was later',
          eventId: 'tea',
        );
        expect(note.open, isTrue);
        await repository.addNote(proposal, 'Not rain: snow', noteId: 'n3#3');
        await repository.withdrawNote(note.id);
        final confirmed = await repository.confirm(proposal);
        expect(confirmed.status, ProposalOutcomeStatus.rechecked);
        expect(confirmed.proposal!.revision, 3);
        expect(
          (await repository.finish(proposal)).status,
          ProposalOutcomeStatus.rebuilt,
        );
        await repository.abandon(proposal);
        expect(_calls(client), [
          [
            'add_proposal_note',
            {
              'proposal_id': 'abc123def456',
              'text': 'Tea was later',
              'event_id': 'tea',
            },
          ],
          [
            'add_proposal_note',
            {
              'proposal_id': 'abc123def456',
              'text': 'Not rain: snow',
              'note_id': 'n3#3',
            },
          ],
          [
            'withdraw_proposal_note',
            {'feedback_id': 'abc123def456f1'},
          ],
          [
            'confirm_proposal',
            {'proposal_id': 'abc123def456', 'revision': 2},
          ],
          [
            'finish_proposal',
            {'proposal_id': 'abc123def456'},
          ],
          [
            'abandon_compaction',
            {'proposal_id': 'abc123def456'},
          ],
        ]);
      },
    );
  });

  group('reviewing on the Events page', () {
    Finder inDialog(Finder f) =>
        find.descendant(of: find.byType(AlertDialog), matching: f);

    late InMemoryEventsRepository events;
    late _Proposals proposals;

    Future<void> open(
      WidgetTester tester, {
      Map<String, Object?>? json,
      Map<String, int>? seen,
      Map<int, Set<String>> changed = const {},
    }) async {
      events = InMemoryEventsRepository(calendar());
      proposals = _Proposals(
        Proposal.fromJson(json ?? proposalJson()),
        events: events,
        changed: changed,
      );
      await tester.pumpWidget(
        MaterialApp(
          home: EventsScreen(
            repository: events,
            serverLabel: 'offline demo',
            proposals: proposals,
            proposalSeen: ProposalSeenStore(persist: false, seen: seen),
            clock: () => now,
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    final confirmButton = find.widgetWithText(
      FilledButton,
      'Confirm 8:00 AM – 12:00 PM happened as shown',
    );

    Future<void> tap(WidgetTester tester, Finder finder) async {
      await tester.ensureVisible(finder);
      await tester.pumpAndSettle();
      await tester.tap(finder);
      await tester.pumpAndSettle();
    }

    double y(DateTime time) => timelineOffset(
      time,
      day: at(0),
      dayEnd: DateTime(2026, 10, 1),
      scale: defaultTimelineScale,
    );

    /// Taps the timeline, away from the times, at [time].
    /// Today's timeline: while the box is up, the days either side are
    /// stacked with it.
    final today = find.byKey(ValueKey(('shown', at(0))));

    Future<void> tapAt(WidgetTester tester, DateTime time) async {
      await tester.tapAt(
        tester.getTopLeft(today) +
            Offset(tester.getSize(today).width / 2, y(time)),
      );
      await tester.pumpAndSettle();
    }

    /// Scrolls today's timeline so 7, the band's start just below it, is
    /// at the top of the view.
    Future<void> toBand(WidgetTester tester) async {
      final scrollable = find
          .byWidgetPredicate(
            (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
          )
          .first;
      final position = tester.state<ScrollableState>(scrollable).position;
      final top = tester.getTopLeft(scrollable).dy;
      position.jumpTo(
        position.pixels + tester.getTopLeft(today).dy + y(at(7)) - top,
      );
      await tester.pumpAndSettle();
    }

    Future<Event> onCalendar(String id) async => (await events.events(
      at(0),
      DateTime(2026, 10, 1),
    )).firstWhere((e) => e.id == id);

    testWidgets('shows what happened in a band, each change marked, under '
        'a bar to confirm it', (tester) async {
      await open(tester);
      final timeline = tester.widget<DayTimeline>(find.byType(DayTimeline));
      expect(timeline.review!.from.isAtSameMomentAs(at(8)), isTrue);
      expect(timeline.review!.through.isAtSameMomentAs(at(12)), isTrue);
      // The bar, and the band's tab where it starts; its foot.
      expect(find.text('What happened — to confirm'), findsNWidgets(2));
      expect(find.text('through 12:00 PM'), findsOneWidget);
      expect(find.text('Moved, was 9:00 AM–10:00 AM · Claude'), findsOneWidget);
      expect(find.text('New · Claude'), findsOneWidget);
      expect(find.text('Cancelled · Claude'), findsOneWidget);
      // As the proposal has it, not the calendar.
      final tea = timeline.events.firstWhere((e) => e.id == 'tea');
      expect(tea.start.isAtSameMomentAs(at(9, 15)), isTrue);
      expect(
        timeline.events.firstWhere((e) => e.id == 'walk').isCancelled,
        isTrue,
      );
      // Work's as planned: plain.
      expect(timeline.marks['work']!.label, isNull);
      expect(timeline.marks.containsKey('talk'), isFalse);
      expect(tester.widget<FilledButton>(confirmButton).onPressed, isNotNull);
    });

    testWidgets('shows a note under the bar, highlighted on the timeline, '
        'with what became of it; the arrows go from note to note', (
      tester,
    ) async {
      await open(tester);
      List<(ReviewNoteKind, bool)> drawn() => [
        for (final n
            in tester.widget<DayTimeline>(find.byType(DayTimeline)).reviewNotes)
          (n.kind, n.selected),
      ];
      expect(find.textContaining('Tea at last'), findsOneWidget);
      expect(find.text('Sets the start of Tea'), findsOneWidget);
      expect(find.text('1/3'), findsOneWidget);
      expect(drawn(), [
        (ReviewNoteKind.setsEdge, true),
        (ReviewNoteKind.annotated, false),
        (ReviewNoteKind.ignored, false),
      ]);
      IconButton arrow(String tooltip) => tester.widget<IconButton>(
        find.widgetWithIcon(
          IconButton,
          tooltip == 'Previous note'
              ? Icons.keyboard_arrow_up
              : Icons.keyboard_arrow_down,
        ),
      );
      expect(arrow('Previous note').onPressed, isNull);

      await tester.tap(find.byTooltip('Next note'));
      await tester.pumpAndSettle();
      expect(find.text('Added to “Work”'), findsOneWidget);
      expect(drawn()[1], (ReviewNoteKind.annotated, true));
      await tester.tap(find.byTooltip('Next note'));
      await tester.pumpAndSettle();
      expect(find.text('Left out · Claude'), findsOneWidget);
      expect(find.text('3/3'), findsOneWidget);
      expect(arrow('Next note').onPressed, isNull);
      await tester.tap(find.byTooltip('Previous note'));
      await tester.pumpAndSettle();
      expect(find.text('2/3'), findsOneWidget);
    });

    testWidgets("says what a note is for: left out -- still setting its "
        "edge -- put back as Claude had it, added to the event whose edge "
        'it sets, or to another', (tester) async {
      await open(tester);
      Future<void> choose(String choice) async {
        await tester.tap(find.byTooltip('What this note is for'));
        await tester.pumpAndSettle();
        expect(find.text("What's this note for?"), findsOneWidget);
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
        await tap(tester, find.text(choice));
      }

      await choose('Leave it out');
      expect(proposals.amends.last.toJson(), {
        'notes': [
          {'note_id': 'n1#1', 'use': 'ignore'},
        ],
      });
      expect(
        find.text('Sets the start of Tea · Left out · you'),
        findsOneWidget,
      );
      expect(
        tester
            .widget<DayTimeline>(find.byType(DayTimeline))
            .reviewNotes
            .first
            .kind,
        ReviewNoteKind.ignored,
      );

      await choose('Put it back as Claude had it');
      expect(proposals.amends.last.asPlanned, ['n1#1']);
      expect(find.text('Sets the start of Tea'), findsOneWidget);

      // Naming no event: the one whose edge it sets.
      await choose('Add it to “Tea, 9:15 AM”');
      expect(proposals.amends.last.toJson(), {
        'notes': [
          {'note_id': 'n1#1', 'use': 'annotate'},
        ],
      });
      expect(
        find.text('Sets the start of Tea · Added to “Tea” · you'),
        findsOneWidget,
      );

      await choose('Work, 10:00 AM');
      expect(proposals.amends.last.toJson(), {
        'notes': [
          {'note_id': 'n1#1', 'use': 'annotate', 'event_id': 'work'},
        ],
      });
      expect(
        find.text('Sets the start of Tea · Added to “Work” · you'),
        findsOneWidget,
      );
    });

    testWidgets('asks Claude about a note, in a note for Claude naming it', (
      tester,
    ) async {
      await open(tester);
      await tester.tap(find.byTooltip('What this note is for'));
      await tester.pumpAndSettle();
      await tap(tester, find.text('Ask Claude about it'));
      expect(
        find.text('About the 9:15 AM note, “Tea at last”'),
        findsOneWidget,
      );
      await tester.enterText(inDialog(find.byType(TextField)), 'Tea at 9');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Leave note'));
      await tester.pumpAndSettle();
      final asked = proposals.proposal!.feedback.last;
      expect(
        (asked.text, asked.noteId, asked.eventId),
        ('Tea at 9', 'n1#1', null),
      );
      expect(
        find.widgetWithText(FilledButton, 'Waiting for Claude'),
        findsOneWidget,
      );
    });

    testWidgets("highlights what's changed since the revision last seen", (
      tester,
    ) async {
      await open(
        tester,
        seen: {'abc123def456': 1},
        changed: {
          2: {'tea'},
        },
      );
      final marks = tester.widget<DayTimeline>(find.byType(DayTimeline)).marks;
      expect(marks['tea']!.changed, isTrue);
      expect(marks['work']!.changed, isFalse);
      expect(find.text('1 event changed since you looked.'), findsOneWidget);
    });

    testWidgets('an edit to an event in the band edits the proposal, not '
        'the calendar', (tester) async {
      await open(tester);
      await tap(tester, find.text('Work'));
      // The summary's row, not the title.
      await tap(tester, inDialog(find.text('Work')).last);
      await tester.enterText(find.byType(TextField), 'Admin');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(proposals.amends.single.toJson(), {
        'updates': [
          {'event_id': 'work', 'summary': 'Admin'},
        ],
      });
      expect(proposals.proposal!.event('work')!.summary, 'Admin');
      expect(proposals.proposal!.event('work')!.decidedBy, DecidedBy.user);
      expect((await onCalendar('work')).summary, 'Work');
      expect(
        find.text('Changed in what happened, to confirm.'),
        findsOneWidget,
      );
      expect(find.text('Admin'), findsOneWidget);
      expect(find.text('Renamed · you'), findsOneWidget);
    });

    testWidgets('an edit the proposal refuses stays in the dialog, and the '
        'proposal is loaded again', (tester) async {
      await open(tester);
      proposals.error = McpException(
        'Tool amend_proposal failed: "Admin" and "Walk" would overlap',
      );
      await tap(tester, find.text('Work'));
      await tap(tester, inDialog(find.text('Work')).last);
      await tester.enterText(find.byType(TextField), 'Admin');
      await tester.pumpAndSettle();
      final loads = proposals.calls.where((c) => c == 'get_proposal').length;
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('"Admin" and "Walk" would overlap'),
        findsOneWidget,
      );
      // Still there to fix and save again.
      expect(find.text('Save'), findsOneWidget);
      expect(
        proposals.calls.where((c) => c == 'get_proposal').length,
        loads + 1,
      );
    });

    testWidgets('cancelling one in the band cancels it in the proposal; a '
        'cancelled one can be put back as planned', (tester) async {
      await open(tester);
      await tap(tester, find.text('Walk'));
      expect(find.text('“Walk” didn\'t happen'), findsOneWidget);
      await tester.tap(find.text('Put it back'));
      await tester.pumpAndSettle();
      expect(proposals.amends.single.asPlanned, ['walk']);
      expect(proposals.proposal!.event('walk')!.live, isTrue);
      expect(find.text('Put back as planned.'), findsOneWidget);
    });

    testWidgets('moving an event in the band moves it in the proposal', (
      tester,
    ) async {
      await open(tester);
      await toBand(tester);
      await tester.longPress(find.text('Tea'));
      await tester.pumpAndSettle();
      await tapAt(tester, at(8));
      await tester.tap(find.byTooltip('Move it here'));
      await tester.pumpAndSettle();

      final update = proposals.amends.single.updates.single;
      expect(update['event_id'], 'tea');
      expect(
        DateTime.parse(update['start'] as String).isAtSameMomentAs(at(8)),
        isTrue,
      );
      expect(
        DateTime.parse(update['end'] as String).isAtSameMomentAs(at(8, 45)),
        isTrue,
      );
      expect((await onCalendar('tea')).start, at(9));
      expect(find.text('Moved in what happened, to confirm.'), findsOneWidget);
    });

    testWidgets('a new event in the band is made in the proposal', (
      tester,
    ) async {
      await open(tester);
      await tester.tap(find.byTooltip('New event'));
      await tester.pumpAndSettle();
      final startHere = find.byTooltip(
        'An hour later: tap to move the other end, or drag it',
      );
      await tap(tester, startHere);
      // Moved whole, to 8.
      await toBand(tester);
      await tapAt(tester, at(8));
      await tester.tap(find.byTooltip('Continue'));
      await tester.pumpAndSettle();
      await tester.enterText(inDialog(find.byType(TextField)), 'Stretch');
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Create'));
      await tester.pumpAndSettle();

      final create = proposals.amends.single.creates.single;
      expect(create['summary'], 'Stretch');
      expect(
        DateTime.parse(create['start'] as String).isAtSameMomentAs(at(8)),
        isTrue,
      );
      expect(
        await events.events(at(0), DateTime(2026, 10, 1)),
        hasLength(calendar().length),
      );
      expect(find.text('Added to what happened, to confirm.'), findsOneWidget);
      expect(find.text('New · you'), findsOneWidget);
    });

    testWidgets('an event after the band is the plan: changed on the '
        'calendar', (tester) async {
      await open(tester);
      await tap(tester, find.text('Talk'));
      await tap(tester, inDialog(find.text('Talk')).last);
      await tester.enterText(find.byType(TextField), 'Call');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(proposals.amends, isEmpty);
      expect((await onCalendar('talk')).summary, 'Call');
    });

    testWidgets('a note for Claude waits for Claude: it can\'t be confirmed '
        "until it's answered, or withdrawn", (tester) async {
      await open(
        tester,
        json: proposalJson(
          feedback: [
            {
              'id': 'abc123def456f1',
              'text': 'Tea was later',
              'event_id': 'tea',
              'status': 'answered',
              'reply': 'Moved it to 9:15.',
              'answered_in': 2,
            },
          ],
        ),
      );
      await tap(tester, find.text('Note for Claude'));
      await tester.tap(find.text('All of it'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Email, 11:30 AM').last);
      await tester.pumpAndSettle();
      await tester.enterText(inDialog(find.byType(TextField)), 'No email');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Leave note'));
      await tester.pumpAndSettle();

      final note = proposals.proposal!.feedback.last;
      expect((note.text, note.eventId), ('No email', 'abc123def456c1'));
      final waiting = find.widgetWithText(FilledButton, 'Waiting for Claude');
      expect(tester.widget<FilledButton>(waiting).onPressed, isNull);
      expect(find.textContaining('1 note open'), findsOneWidget);

      // Claude's reply beside the note it answers; the open one withdrawn.
      await tap(tester, find.text('Notes (2)'));
      expect(find.text('Moved it to 9:15.'), findsOneWidget);
      expect(find.text('You, on “Tea, 9:15 AM”'), findsOneWidget);
      await tester.tap(find.text('Withdraw'));
      await tester.pumpAndSettle();
      expect(proposals.calls, contains('withdraw_proposal_note'));
      expect(tester.widget<FilledButton>(confirmButton).onPressed, isNotNull);
    });

    testWidgets('confirming applies it: the band goes, the calendar is as '
        'it said', (tester) async {
      await open(tester);
      await tap(tester, confirmButton);
      expect(proposals.calls, contains('confirm_proposal'));
      expect(
        find.text('Confirmed: what happened 8:00 AM – 12:00 PM is recorded.'),
        findsOneWidget,
      );
      expect(find.text('What happened — to confirm'), findsNothing);
      expect(
        (await onCalendar('tea')).start.isAtSameMomentAs(at(9, 15)),
        isTrue,
      );
      expect(events.deleted, [('walk', false)]);
    });

    testWidgets('rechecked: says what changed, and confirms again', (
      tester,
    ) async {
      await open(tester);
      proposals.onConfirm = (proposal) async {
        proposals.onConfirm = null;
        // The calendar changed: work ends later.
        await proposals.amend(
          proposal,
          ProposalEdits(
            updates: [
              {'event_id': 'work', 'end': iso(11)},
            ],
          ),
        );
        return ProposalOutcome(
          status: ProposalOutcomeStatus.rechecked,
          message: 'The calendar changed since this was planned.',
          proposal: proposals.proposal,
        );
      };
      await tap(tester, confirmButton);
      expect(find.text('The calendar changed'), findsOneWidget);
      expect(inDialog(find.text('• Work')), findsOneWidget);
      await tester.tap(find.text('Confirm again'));
      await tester.pumpAndSettle();
      expect(
        proposals.calls.where((c) => c == 'confirm_proposal'),
        hasLength(2),
      );
      expect(find.text('What happened — to confirm'), findsNothing);
    });

    testWidgets('confirming a revision no longer current loads the current '
        'one, to review', (tester) async {
      await open(tester);
      // Claude revised it meanwhile.
      await proposals.amend(
        proposals.proposal!,
        const ProposalEdits(asPlanned: ['walk']),
      );
      await tap(tester, confirmButton);
      expect(
        find.text(
          'It changed since you looked: this is revision 3. Review it, '
          'then try again.',
        ),
        findsOneWidget,
      );
      expect(find.text('Cancelled · Claude'), findsNothing);
      expect(find.text('What happened — to confirm'), findsNWidgets(2));
    });

    testWidgets('handed to Claude when it no longer plans', (tester) async {
      await open(tester);
      proposals.onConfirm = (proposal) async => ProposalOutcome(
        status: ProposalOutcomeStatus.needsClaude,
        message: 'Work was deleted from the calendar.',
        proposal: proposal,
      );
      await tap(tester, confirmButton);
      expect(find.text('Claude needs to look at it'), findsOneWidget);
      expect(find.text('Work was deleted from the calendar.'), findsOneWidget);
    });

    testWidgets('an apply that stopped partway is retried', (tester) async {
      await open(tester, json: proposalJson(state: 'applying'));
      expect(find.textContaining('stopped partway'), findsOneWidget);
      expect(confirmButton, findsNothing);
      await tap(tester, find.text('Retry'));
      expect(proposals.calls, contains('finish_proposal'));
      expect(find.text('What happened — to confirm'), findsNothing);
    });
  });
}

/// An in-memory proposal that records the edits made to it, and can
/// refuse them.
class _Proposals extends InMemoryProposalRepository {
  _Proposals(super.proposal, {super.events, super.changed});

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

/// [client]'s calls, each its tool's name and arguments.
List<List<Object>> _calls(_Client client) => [
  for (final (name, arguments) in client.calls) [name, arguments],
];

class _Client extends McpClient {
  _Client(this.answer) : super(endpoint: Uri.parse('http://test'));

  final Object? Function(String name, Map<String, Object?> arguments) answer;
  final calls = <(String, Map<String, Object?>)>[];

  @override
  Future<Object?> callTool(
    String name, [
    Map<String, Object?> arguments = const {},
  ]) async {
    calls.add((name, arguments));
    return answer(name, arguments);
  }
}
