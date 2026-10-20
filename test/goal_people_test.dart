// Goals' people -- who each is done with and for -- and the goals a
// compaction proposal adds, from what the notes say the user means to do.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:time_tracker_client/models/goal.dart';
import 'package:time_tracker_client/models/proposal.dart';
import 'package:time_tracker_client/services/goals_repository.dart';
import 'package:time_tracker_client/services/mcp_client.dart';
import 'package:time_tracker_client/services/proposal_repository.dart';
import 'package:time_tracker_client/widgets/goal_editor.dart';
import 'package:time_tracker_client/widgets/proposal_review.dart';

void main() {
  test("a goal's people are read, and sent only when there are some", () {
    final goal = Goal.fromJson({
      'id': 'g1',
      'title': 'Help Sam move',
      'with_ids': ['ana'],
      'for_ids': ['sam'],
    });
    expect(goal.withIds, ['ana']);
    expect(goal.forIds, ['sam']);
    expect(goal.involves('sam'), isTrue);
    expect(goal.involves('bo'), isFalse);
    expect(goal.toJson()['with_ids'], ['ana']);
    final alone = Goal.fromJson({'id': 'g2', 'title': 'Read more'}).toJson();
    expect(alone.containsKey('with_ids'), isFalse);
    expect(alone.containsKey('for_ids'), isFalse);
  });

  test('says who a goal is with and for, by name', () {
    String name(String id) => {'ana': 'Ana', 'sam': 'Sam'}[id] ?? id;
    expect(goalPeopleLabel(['ana'], ['sam'], name), 'With Ana · For Sam');
    expect(goalPeopleLabel([], ['sam', 'bo'], name), 'For Sam, bo');
    expect(goalPeopleLabel([], [], name), isNull);
  });

  ProposalAddition goalAddition() => ProposalAddition.allFrom({
    'people': [
      {'ref': 'new:alex', 'name': 'Alex'},
    ],
    'goals': [
      {
        'ref': 'new:help-sam',
        'title': 'Help Sam move',
        'deadline': '2026-11-01',
        'with_ids': ['new:alex'],
        'for_ids': ['sam'],
      },
    ],
  }).last;

  test('reads a goal a proposal adds: named by its title, with its '
      'deadline and people', () {
    final goal = goalAddition();
    expect(
      (goal.kind, goal.ref, goal.name),
      (AdditionKind.goal, 'new:help-sam', 'Help Sam move'),
    );
    expect(goal.detail, isNull);
    expect(goal.deadline, '2026-11-01');
    expect(goal.withIds, ['new:alex']);
    expect(goal.forIds, ['sam']);
  });

  testWidgets("a new goal's strip says when it's due and who it's with and "
      'for, not the events it is at', (tester) async {
    var activated = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ProposalAdditionStrip(
            addition: goalAddition(),
            index: 0,
            count: 1,
            about: 'Due Nov 1, 2026 · With Alex (new) · For Sam',
            onActivate: () => activated++,
          ),
        ),
      ),
    );
    expect(find.textContaining('New goal'), findsOneWidget);
    expect(find.textContaining('Help Sam move'), findsOneWidget);
    expect(find.textContaining('With Alex (new) · For Sam'), findsOneWidget);
    expect(find.textContaining('Not used at any event'), findsNothing);
    await tester.tap(find.byTooltip('Make it an active goal'));
    expect(activated, 1);
  });

  group('settling a new goal', () {
    late InMemoryGoalsRepository goals;
    late InMemoryProposalRepository proposals;

    setUp(() {
      goals = InMemoryGoalsRepository();
      proposals = InMemoryProposalRepository(
        Proposal.fromJson({
          'id': 'abc123def456',
          'revision': 1,
          'state': 'awaiting_review',
          'window_start': '2026-09-30T08:00:00',
          'through': '2026-09-30T12:00:00',
          'events': <Object>[],
          'additions': {
            'people': [
              {'ref': 'new:alex', 'name': 'Alex'},
            ],
            'goals': [
              {
                'ref': 'new:help-sam',
                'title': 'Help Sam move',
                'deadline': '2026-11-01',
                'with_ids': ['new:alex'],
                'for_ids': ['sam'],
              },
            ],
          },
        }),
        goals: goals,
      );
    });

    ProposalEdits settling(
      String ref,
      AdditionUse use,
      AdditionKind kind, {
      String? deadline,
    }) => ProposalEdits(
      additions: [
        (
          ref: ref,
          use: use,
          id: null,
          name: null,
          detail: null,
          kind: kind,
          deadline: deadline,
          fields: null,
        ),
      ],
    );

    test('made active, it is sent with its deadline', () {
      final edits = settling(
        'new:help-sam',
        AdditionUse.create,
        AdditionKind.goal,
        deadline: '2026-11-08',
      );
      final json = edits.toJson();
      expect(json['additions'], [
        {
          'ref': 'new:help-sam',
          'use': 'create',
          'status': 'active',
          'deadline': '2026-11-08',
        },
      ]);
      expect(
        ProposalEdits.fromJson(json).additions.single.deadline,
        '2026-11-08',
      );
    });

    test('waits for the new people it names', () async {
      await expectLater(
        proposals.amend(
          proposals.proposal!,
          settling('new:help-sam', AdditionUse.create, AdditionKind.goal),
        ),
        throwsA(isA<McpException>()),
      );
      expect(await goals.goals(), isEmpty);
    });

    test('is made naming them by their ids, once they are settled -- those '
        'dropped left out', () async {
      await proposals.amend(
        proposals.proposal!,
        settling('new:alex', AdditionUse.drop, AdditionKind.person),
      );
      final amended = await proposals.amend(
        proposals.proposal!,
        settling('new:help-sam', AdditionUse.create, AdditionKind.goal),
      );
      final made = (await goals.goals()).single;
      expect(made.title, 'Help Sam move');
      expect(made.withIds, isEmpty);
      expect(made.forIds, ['sam']);
      expect(made.status, 'inactive');
      expect(
        amended.settledAdditions
            .where((s) => s.ref == 'new:help-sam')
            .single
            .id,
        made.id,
      );
    });

    test('made active from the strip, it is due when the user said', () async {
      await proposals.amend(
        proposals.proposal!,
        settling('new:alex', AdditionUse.create, AdditionKind.person),
      );
      await proposals.amend(
        proposals.proposal!,
        settling(
          'new:help-sam',
          AdditionUse.create,
          AdditionKind.goal,
          deadline: '2026-11-08',
        ),
      );
      final made = (await goals.goals()).single;
      expect((made.status, made.deadline), ('active', '2026-11-08'));
    });
  });
}
