// A compaction proposal's changes to goals there are -- done, missed or
// obsolete -- shown under its bar on the Events page, and settled there:
// applied now, dropped, changed, or missed and tried again.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:time_tracker_client/models/event.dart';
import 'package:time_tracker_client/models/goal.dart';
import 'package:time_tracker_client/models/note.dart';
import 'package:time_tracker_client/models/proposal.dart';
import 'package:time_tracker_client/screens/events_screen.dart';
import 'package:time_tracker_client/services/events_repository.dart';
import 'package:time_tracker_client/services/goals_repository.dart';
import 'package:time_tracker_client/services/plan_memory.dart';
import 'package:time_tracker_client/services/proposal_repository.dart';

void main() {
  final now = DateTime(2026, 9, 30, 12);
  DateTime at(int hour, [int minute = 0]) =>
      DateTime(2026, 9, 30, hour, minute);
  String iso(int hour, [int minute = 0]) => localIsoTimestamp(at(hour, minute));

  List<Goal> goals() => [
    Goal.fromJson({
      'id': 'recipe',
      'title': 'Recipe sent to Kopal',
      'status': 'active',
      'deadline': '2026-10-05',
      'parent_id': 'kitchen',
      'history': [
        {'status': 'active', 'at': '2026-09-20T09:00:00'},
      ],
    }),
    Goal.fromJson({
      'id': 'kitchen',
      'title': 'Kitchen',
      'status': 'active',
      'deadline': '2026-12-31',
      'history': [
        {'status': 'active', 'at': '2026-09-01T09:00:00'},
      ],
    }),
    Goal.fromJson({
      'id': 'fence',
      'title': 'Fence fixed',
      'status': 'inactive',
      'deadline': '2026-09-29',
      'history': [
        {'status': 'inactive', 'at': '2026-09-01T09:00:00'},
      ],
    }),
  ];

  /// From 8 to noon: tea, and a note at 10:30 saying the recipe went;
  /// Claude marks that goal done from the note, and the fence missed, its
  /// deadline having passed.
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
        'status': 'on_schedule',
      },
    ],
    'notes': [
      {
        'id': 'n1#1',
        'timestamp': iso(10, 30),
        'description': 'Sent Kopal the recipe',
        'use': 'unused',
      },
    ],
    'goal_changes': [
      {
        'goal_id': 'recipe',
        'title': 'Recipe sent to Kopal',
        'path': ['Kitchen'],
        'status': 'done',
        'at': iso(10, 30),
        'note_ids': ['n1#1'],
        'retry_deadline': null,
        'decided_by': 'claude',
      },
      {
        'goal_id': 'fence',
        'title': 'Fence fixed',
        'path': <String>[],
        'status': 'missed',
        'at': iso(12),
        'note_ids': <String>[],
        'retry_deadline': null,
        'decided_by': 'claude',
      },
    ],
    'recap': {
      'overview': 'Kopal has the recipe',
      'did': [
        {
          'text': 'Marked the recipe done, from the note',
          'goal_ids': ['recipe'],
          'note_ids': ['n1#1'],
        },
      ],
    },
  };

  group('InMemoryProposalRepository', () {
    test(
      'applies a goal change now, as one change of the goal; keeps one '
      'changed as the user’s; drops one; refuses what the server would',
      () async {
        final store = InMemoryGoalsRepository(goals(), () => now);
        final proposals = InMemoryProposalRepository(
          Proposal.fromJson(proposalJson()),
          goals: store,
        );
        GoalChangeEdit edit(
          String goalId,
          GoalChangeUse use, {
          String? status,
          String? retryDeadline,
        }) => (
          goalId: goalId,
          use: use,
          status: status,
          at: null,
          retryDeadline: retryDeadline,
        );
        var proposal = await proposals.amend(
          proposals.proposal!,
          ProposalEdits(goalChanges: [edit('recipe', GoalChangeUse.apply)]),
        );
        final recipe = (await store.goals()).singleWhere(
          (g) => g.id == 'recipe',
        );
        expect(recipe.status, 'done');
        expect(recipe.history.map((h) => h.status), ['active', 'done']);
        expect(recipe.history.last.at.isAtSameMomentAs(at(10, 30)), isTrue);
        expect(recipe.history.last.deadline, '2026-10-05');
        expect([for (final c in proposal.goalChanges) c.goalId], ['fence']);
        expect(
          (
            proposal.settledGoalChanges.single.goalId,
            proposal.settledGoalChanges.single.use,
            proposal.settledGoalChanges.single.status,
          ),
          ('recipe', GoalChangeUse.apply, 'done'),
        );

        // Changed: missed and tried again, kept in the proposal as the user's.
        proposal = await proposals.amend(
          proposal,
          ProposalEdits(
            goalChanges: [
              edit(
                'fence',
                GoalChangeUse.change,
                status: 'missed',
                retryDeadline: '2026-10-05',
              ),
            ],
          ),
        );
        final fence = proposal.goalChange('fence')!;
        expect(
          (fence.status, fence.retryDeadline, fence.decidedBy, fence.title),
          ('missed', '2026-10-05', DecidedBy.user, 'Fence fixed'),
        );
        expect(proposal.settledGoalChanges.last.use, GoalChangeUse.change);
        // Still inactive: made when it's confirmed.
        expect(
          (await store.goals()).singleWhere((g) => g.id == 'fence').status,
          'inactive',
        );

        // Applied as a retry: the goal stays open, due by the new day.
        proposal = await proposals.amend(
          proposal,
          ProposalEdits(goalChanges: [edit('fence', GoalChangeUse.apply)]),
        );
        final retried = (await store.goals()).singleWhere(
          (g) => g.id == 'fence',
        );
        expect(retried.status, 'inactive');
        expect(retried.deadline, '2026-10-05');
        expect(retried.history.map((h) => h.status), [
          'inactive',
          'missed',
          'inactive',
        ]);
        expect(retried.history[1].deadline, '2026-09-29');
        expect(proposal.goalChanges, isEmpty);

        // A change of a goal the proposal doesn't change needs a status; a
        // drop needs a change to drop.
        await expectLater(
          proposals.amend(
            proposal,
            ProposalEdits(goalChanges: [edit('kitchen', GoalChangeUse.change)]),
          ),
          throwsA(isA<Exception>()),
        );
        await expectLater(
          proposals.amend(
            proposal,
            ProposalEdits(goalChanges: [edit('kitchen', GoalChangeUse.drop)]),
          ),
          throwsA(isA<Exception>()),
        );
        proposal = await proposals.amend(
          proposal,
          ProposalEdits(
            goalChanges: [
              edit('kitchen', GoalChangeUse.change, status: 'obsolete'),
            ],
          ),
        );
        expect(proposal.goalChange('kitchen')?.title, 'Kitchen');
        proposal = await proposals.amend(
          proposal,
          ProposalEdits(goalChanges: [edit('kitchen', GoalChangeUse.drop)]),
        );
        expect(proposal.goalChanges, isEmpty);
        expect(proposal.settledGoalChanges.last.use, GoalChangeUse.drop);
      },
    );
  });

  group('on the Events page', () {
    late InMemoryGoalsRepository store;
    late _Proposals proposals;

    Future<void> open(
      WidgetTester tester, {
      Map<String, Object?> extra = const {},
    }) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      store = InMemoryGoalsRepository(goals(), () => now);
      proposals = _Proposals(
        Proposal.fromJson({...proposalJson(), ...extra}),
        events: InMemoryEventsRepository([
          Event(id: 'tea', start: at(9), end: at(10), summary: 'Tea'),
        ]),
        goals: store,
      );
      await tester.pumpWidget(
        PlanMemoryScope(
          memory: PlanMemory()..goals = goals(),
          child: GoalsScope(
            repository: store,
            child: MaterialApp(
              home: EventsScreen(
                repository: proposals.events!,
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

    /// Opens the goal change shown, and picks [choice] in its sheet.
    Future<void> settle(WidgetTester tester, String choice) async {
      await tester.tap(
        find.byTooltip(RegExp(r'^(Settle it|Change how it’s settled)$')),
      );
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

    Map<String, Object?> lastSent() => proposals.amends.last.toJson();

    testWidgets('lists each goal change, with the goal, what it marks it, '
        'where it sits and the note it came from, stepped through', (
      tester,
    ) async {
      await open(tester);
      await page(tester, 'Goals (2)');
      expect(
        find.text('Goal  Recipe sent to Kopal · mark done', findRichText: true),
        findsOneWidget,
      );
      expect(
        find.text(
          'Kitchen · from the 10:30 AM note · To settle: made when it’s '
          'confirmed',
        ),
        findsOneWidget,
      );
      await tester.tap(find.byTooltip('Next goal change'));
      await tester.pumpAndSettle();
      expect(
        find.text('Goal  Fence fixed · missed', findRichText: true),
        findsOneWidget,
      );
      expect(find.text('To settle: made when it’s confirmed'), findsOneWidget);
      expect(find.byTooltip('Next goal change'), findsOneWidget);
      expect(
        tester
            .widget<IconButton>(
              find.widgetWithIcon(IconButton, Icons.keyboard_arrow_down),
            )
            .onPressed,
        isNull,
      );
    });

    testWidgets('applies one now, from its button: the goal is changed, and '
        'the change marked applied', (tester) async {
      await open(tester);
      await page(tester, 'Goals (2)');
      await tester.tap(find.byTooltip('Apply it now'));
      await tester.pumpAndSettle();
      expect(lastSent(), {
        'goal_changes': [
          {'goal_id': 'recipe', 'use': 'apply'},
        ],
      });
      final recipe = (await store.goals()).singleWhere((g) => g.id == 'recipe');
      expect(recipe.status, 'done');
      expect(find.textContaining('Applied now · you'), findsOneWidget);
      // Settled: it can't be applied again, or dropped.
      expect(find.byTooltip('Apply it now'), findsNothing);
      await tester.tap(find.byTooltip('Change how it’s settled'));
      await tester.pumpAndSettle();
      expect(find.text('Drop it'), findsNothing);
      expect(find.text('Put it back as Claude proposed it'), findsNothing);
      expect(find.text('Ask Claude about it'), findsOneWidget);
    });

    testWidgets('drops one, puts it back, changes it to obsolete, and to '
        'missed and tried again by a day picked', (tester) async {
      await open(tester);
      await page(tester, 'Goals (2)');
      await tester.tap(find.byTooltip('Next goal change'));
      await tester.pumpAndSettle();

      await settle(tester, 'Drop it');
      expect(lastSent(), {
        'goal_changes': [
          {'goal_id': 'fence', 'use': 'drop'},
        ],
      });
      expect(
        find.textContaining('Dropped: the goal’s left alone · you'),
        findsOneWidget,
      );
      expect(
        find.text('Goal  Fence fixed', findRichText: true),
        findsOneWidget,
      );

      // Put back: a change to what Claude proposed.
      await settle(tester, 'Put it back as Claude proposed it');
      expect(lastSent(), {
        'goal_changes': [
          {'goal_id': 'fence', 'use': 'change', 'status': 'missed'},
        ],
      });
      expect(
        find.text('Goal  Fence fixed · missed', findRichText: true),
        findsOneWidget,
      );
      expect(find.textContaining('Changed · you'), findsOneWidget);

      await settle(tester, 'Obsolete');
      expect(lastSent(), {
        'goal_changes': [
          {'goal_id': 'fence', 'use': 'change', 'status': 'obsolete'},
        ],
      });
      expect(
        find.text('Goal  Fence fixed · obsolete', findRichText: true),
        findsOneWidget,
      );

      // Missed, tried again by tomorrow (the picker's first offer).
      await settle(tester, 'Missed, try again by…');
      expect(find.text('Try again by'), findsOneWidget);
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(lastSent(), {
        'goal_changes': [
          {
            'goal_id': 'fence',
            'use': 'change',
            'status': 'missed',
            'retry_deadline': '2026-10-01',
          },
        ],
      });
      expect(
        find.text(
          'Goal  Fence fixed · missed, try again by Thu, Oct 1',
          findRichText: true,
        ),
        findsOneWidget,
      );
      // Still open where it's kept: made when it's confirmed.
      expect(
        (await store.goals()).singleWhere((g) => g.id == 'fence').status,
        'inactive',
      );
    });

    testWidgets('asks Claude about one, in a note naming the goal', (
      tester,
    ) async {
      await open(tester);
      await page(tester, 'Goals (2)');
      await settle(tester, 'Ask Claude about it');
      expect(
        find.text('About the change to the goal “Recipe sent to Kopal”'),
        findsOneWidget,
      );
      await tester.enterText(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.byType(TextField),
        ),
        'It only went as a draft',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Leave note'));
      await tester.pumpAndSettle();
      final asked = proposals.proposal!.feedback.last;
      expect(
        asked.text,
        'About the change to the goal “Recipe sent to Kopal” (recipe):\n\n'
        'It only went as a draft',
      );
      expect(asked.eventId, isNull);
    });

    testWidgets("Claude's recap cites a goal change, and its chip goes to it", (
      tester,
    ) async {
      await open(tester);
      await tester.tap(find.byTooltip('Next point'));
      await tester.pumpAndSettle();
      expect(
        find.text('10:30 AM note, Recipe sent to Kopal · mark done'),
        findsOneWidget,
      );
      await tester.tap(find.textContaining('Marked the recipe done'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.widgetWithText(ActionChip, 'Recipe sent to Kopal · mark done'),
      );
      await tester.pumpAndSettle();
      expect(find.text('What Claude did'), findsNothing);
      expect(
        find.text('Goal  Recipe sent to Kopal · mark done', findRichText: true),
        findsOneWidget,
      );
    });

    testWidgets('confirming says which goal changes the goals refused', (
      tester,
    ) async {
      await open(tester);
      proposals.onConfirm = (proposal) async => ProposalOutcome(
        status: ProposalOutcomeStatus.applied,
        proposal: proposal.copyWith(state: ProposalState.applied),
        warnings: const [
          "the goal change to fence (missed) wasn't made: it has open "
              'sub-goals. Make it with update_goals if it still applies.',
        ],
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Confirm'));
      await tester.pumpAndSettle();
      expect(find.text('Confirmed, with warnings'), findsOneWidget);
      expect(find.textContaining("fence (missed) wasn't made"), findsOneWidget);
    });
  });
}

/// An in-memory proposal that records the edits made to it.
class _Proposals extends InMemoryProposalRepository {
  _Proposals(super.proposal, {super.events, super.goals});

  final amends = <ProposalEdits>[];

  @override
  Future<Proposal> amend(
    Proposal proposal,
    ProposalEdits edits, {
    bool allowHistory = false,
  }) async {
    final amended = await super.amend(proposal, edits);
    amends.add(edits);
    return amended;
  }
}
