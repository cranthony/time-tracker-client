import 'package:flutter_test/flutter_test.dart';
import 'package:time_tracker_client/models/note.dart' show localIsoTimestamp;
import 'package:time_tracker_client/models/proposal.dart';
import 'package:time_tracker_client/models/proposed_stories.dart';
import 'package:time_tracker_client/models/trait.dart';
import 'package:time_tracker_client/services/proposal_repository.dart';
import 'package:time_tracker_client/services/traits_repository.dart';

const _patient = Trait(
  id: 'patient',
  name: 'Patient',
  parts: [
    {
      'kind': 'judgment',
      'rubric': 'Was I patient?',
      'ratings': {'0': 'No', '1': 'Yes'},
      'facts': ['general_notes'],
    },
  ],
);

Map<String, Object?> _proposal({
  List<Map<String, Object?>> stories = const [],
  List<Map<String, Object?>> settled = const [],
}) => {
  'id': 'abc123def456',
  'revision': 1,
  'state': 'awaiting_review',
  'window_start': localIsoTimestamp(DateTime(2026, 9, 30, 8)),
  'through': localIsoTimestamp(DateTime(2026, 9, 30, 12)),
  'events': [
    {
      'id': 'tea',
      'summary': 'Tea',
      'start': localIsoTimestamp(DateTime(2026, 9, 30, 9)),
      'end': localIsoTimestamp(DateTime(2026, 9, 30, 10)),
      'status': 'on_schedule',
    },
  ],
  'trait_examples': stories,
  'settled_trait_examples': settled,
};

const _claudes = {
  'id': 's1',
  'trait_id': 'patient',
  'trait_name': 'Patient',
  'when': '2026-09-30',
  'person_id': 'p1',
  'person_name': 'Robin',
  'what': 'Waited for the kettle',
  'why': 'Let it take its time',
  'event_id': 'tea',
  'decided_by': 'claude',
};

void main() {
  test("a proposal's stories, and those settled, are read", () {
    final proposal = Proposal.fromJson(
      _proposal(
        stories: [
          _claudes,
          {
            ..._claudes,
            'id': 's3',
            'person_id': null,
            'person_name': null,
            'who': 'A cashier',
            'event_id': null,
            'decided_by': 'user',
          },
        ],
        settled: [
          {'id': 's2', 'use': 'drop', 'clear_fields': <String>[]},
          {
            'id': 's3',
            'use': 'change',
            'who': 'A cashier',
            'clear_fields': ['person_id', 'event_id'],
          },
        ],
      ),
    );
    final [claudes, users] = proposal.traitExamples;
    expect(claudes.example.eventId, 'tea');
    expect(claudes.personName, 'Robin');
    expect(claudes.decidedBy, DecidedBy.claude);
    expect(users.example.who, 'A cashier');
    expect(users.decidedBy, DecidedBy.user);
    expect(proposal.settledTraitExamples.first.use, StoryEditUse.drop);
    expect(proposal.settledTraitExamples.last.cleared, [
      'person_id',
      'event_id',
    ]);
    // A server from before them.
    expect(
      Proposal.fromJson(_proposal()..remove('trait_examples')).traitExamples,
      isEmpty,
    );
  });

  test('edits are sent as amend_proposal takes them, and only with some', () {
    final edits = ProposalEdits(
      traitExamples: [
        const StoryEdit(id: 's1', use: StoryEditUse.drop),
        StoryEdit.change('s2', {'what': 'Again', 'event_id': null}),
      ],
    );
    expect(edits.toJson()['trait_examples'], [
      {'id': 's1', 'use': 'drop'},
      {
        'id': 's2',
        'use': 'change',
        'what': 'Again',
        'clear_fields': ['event_id'],
      },
    ]);
    expect(ProposalEdits.fromJson(edits.toJson()).toJson(), edits.toJson());
    expect(
      const ProposalEdits().toJson().containsKey('trait_examples'),
      isFalse,
    );
    expect(edits.isEmpty, isFalse);
  });

  test('settling: a drop leaves, a change is laid over it as the user\'s, '
      'and a new id adds a whole one', () {
    final claudes = ProposedStory.fromJson(_claudes)!;
    final (stories, settled) = settleStories(
      [claudes],
      const [],
      [
        StoryEdit.change('s1', {'why': 'Unhurried', 'event_id': null}),
        StoryEdit.change('s9', {
          'trait_id': 'patient',
          'when': '2026-09-29',
          'who': 'A bus driver',
          'what': 'Waited for a runner',
          'why': 'Had time for them',
        }),
        // Missing what a story needs: not added.
        StoryEdit.change('s10', {'what': 'Half a story'}),
      ],
    );
    expect([for (final s in stories) s.id], ['s1', 's9']);
    expect(stories.first.example.why, 'Unhurried');
    expect(stories.first.example.what, 'Waited for the kettle');
    expect(stories.first.example.eventId, isNull);
    expect(stories.first.decidedBy, DecidedBy.user);
    expect(settled, hasLength(3));

    final (left, _) = settleStories(stories, settled, const [
      StoryEdit(id: 's1', use: StoryEditUse.drop),
    ]);
    expect([for (final s in left) s.id], ['s9']);
  });

  test('confirmed, the in-memory proposal makes its stories', () async {
    final traits = InMemoryTraitsRepository(traits: const [_patient]);
    final repository = InMemoryProposalRepository(
      Proposal.fromJson(_proposal(stories: [_claudes])),
      traits: traits,
    );
    final amended = await repository.amend(
      (await repository.current())!,
      ProposalEdits(
        traitExamples: [
          StoryEdit.change('s1', {'who': 'Robin, next door'}),
        ],
      ),
    );
    expect(amended.traitExamples.single.example.who, 'Robin, next door');
    await repository.confirm(amended);
    final made = (await traits.examples()).single;
    expect(made.what, 'Waited for the kettle');
    expect(made.who, 'Robin, next door');
    expect(made.eventId, 'tea');
  });
}
