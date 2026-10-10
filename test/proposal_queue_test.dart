import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:time_tracker_client/models/proposal.dart';
import 'package:time_tracker_client/outbox/event_outbox.dart';
import 'package:time_tracker_client/outbox/outbox_store.dart';
import 'package:time_tracker_client/services/events_repository.dart';
import 'package:time_tracker_client/models/note.dart';
import 'package:time_tracker_client/services/mcp_client.dart';
import 'package:time_tracker_client/services/proposal_repository.dart';
import 'package:time_tracker_client/widgets/proposal_review.dart';

DateTime _at(int hour) => DateTime(2026, 9, 30, hour);

Proposal _proposal({int revision = 3}) => Proposal(
  id: 'p1',
  revision: revision,
  state: ProposalState.awaitingReview,
  windowStart: _at(12),
  through: _at(14),
  events: [
    ProposalEvent(
      id: 'lunch',
      start: _at(12),
      end: _at(13),
      status: ProposalEventStatus.onSchedule,
      summary: 'Lunch',
    ),
  ],
);

/// The server's side of proposals, as the queue sees it: what each call
/// was asked, and what it's to answer.
class _Proposals implements ProposalRepository {
  Proposal? open = _proposal();
  final calls = <String>[];

  /// Whether each amend was sent with the user's approval to change
  /// history.
  final allowed = <bool>[];

  /// The events an amend says it replaced Claude's newer changes to.
  List<String> replaced = const [];
  ProposalOutcome confirmed = const ProposalOutcome(
    status: ProposalOutcomeStatus.applied,
  );

  /// Thrown by the next confirm, or finish, while set.
  Object? confirmError;
  Object? finishError;

  @override
  Future<Proposal?> current({int? sinceRevision}) async {
    calls.add('current');
    return open;
  }

  @override
  Future<Proposal?> cachedCurrent() async => null;

  @override
  Future<Proposal> amend(
    Proposal proposal,
    ProposalEdits edits, {
    bool allowHistory = false,
  }) async {
    calls.add('amend from ${proposal.revision}');
    allowed.add(allowHistory);
    return open = open!.copyWith(
      revision: open!.revision + 1,
      replaced: replaced,
    );
  }

  @override
  Future<ProposalFeedback> addNote(
    Proposal proposal,
    String text, {
    String? eventId,
    DateTime? at,
    String? noteId,
  }) async {
    calls.add('note $text');
    final note = ProposalFeedback(id: 'p1f1', text: text, eventId: eventId);
    open = open!.copyWith(
      feedback: [...open!.feedback, note],
      state: ProposalState.awaitingClaude,
    );
    return note;
  }

  @override
  Future<void> withdrawNote(String feedbackId) async =>
      calls.add('withdraw $feedbackId');

  @override
  Future<ProposalOutcome> confirm(Proposal proposal) async {
    calls.add('confirm ${proposal.revision}');
    if (confirmError case final e?) {
      confirmError = null;
      throw e;
    }
    return confirmed;
  }

  @override
  Future<ProposalOutcome> finish(Proposal proposal) async {
    calls.add('finish');
    if (finishError case final e?) {
      finishError = null;
      throw e;
    }
    return const ProposalOutcome(status: ProposalOutcomeStatus.applied);
  }

  @override
  Future<void> abandon(Proposal proposal) async {
    calls.add('abandon');
    open = null;
  }
}

/// Does what each is asked -- but, while [timeOut] is set, once, times
/// out after, unheard.
class _Flaky extends _Proposals {
  bool timeOut = false;

  Future<T> _unheard<T>(T result) async {
    if (timeOut) {
      timeOut = false;
      throw Exception('timed out');
    }
    return result;
  }

  @override
  Future<ProposalOutcome> confirm(Proposal proposal) async =>
      _unheard(await super.confirm(proposal));

  @override
  Future<ProposalFeedback> addNote(
    Proposal proposal,
    String text, {
    String? eventId,
    DateTime? at,
    String? noteId,
  }) async => _unheard(
    await super.addNote(
      proposal,
      text,
      eventId: eventId,
      at: at,
      noteId: noteId,
    ),
  );

  @override
  Future<void> abandon(Proposal proposal) async {
    await super.abandon(proposal);
    await _unheard(null);
  }
}

EventOutbox _outbox(_Proposals proposals, {ProposalNotices? notices}) =>
    EventOutbox(
      store: InMemoryOutboxStore(),
      events: InMemoryEventsRepository(const []),
      proposals: proposals,
      notices: notices ?? ProposalNotices(persist: false),
    );

const _edit = ProposalEdits(
  updates: [
    {
      'event': {'id': 'lunch', 'summary': 'Brunch'},
    },
  ],
);

void main() {
  group('Queued, an edit of the proposal', () {
    test('that replaced Claude\'s newer changes says so', () async {
      final proposals = _Proposals()..replaced = ['lunch'];
      final outbox = _outbox(proposals);

      await outbox.amend(_proposal(), _edit);
      await outbox.flush(ignoreBackoff: true);

      final notice = outbox.notices!.notices.single;
      expect(notice.kind, ProposalNoticeKind.replaced);
      expect(notice.eventIds, ['lunch']);
      expect(notice.text, contains('“Lunch”'));
    });

    test('says nothing when it replaced nothing', () async {
      final outbox = _outbox(_Proposals());

      await outbox.amend(_proposal(), _edit);
      await outbox.flush(ignoreBackoff: true);

      expect(outbox.notices!.notices, isEmpty);
    });
  });

  group('Changing history', () {
    // The last compaction ran at 12:30, as lunch, from 12, was going on.
    Proposal settled() => Proposal(
      id: 'p1',
      revision: 3,
      state: ProposalState.awaitingReview,
      windowStart: _at(12).add(const Duration(minutes: 30)),
      through: _at(14),
      events: [
        ProposalEvent(
          id: 'lunch',
          start: _at(12),
          end: _at(13),
          plannedStart: _at(12),
          plannedEnd: _at(13),
          status: ProposalEventStatus.onSchedule,
          summary: 'Lunch',
        ),
        ProposalEvent(
          id: 'call',
          start: _at(13),
          end: _at(14),
          status: ProposalEventStatus.onSchedule,
          summary: 'Call',
        ),
      ],
    );
    ProposalEdits update(String id, Map<String, Object?> fields) =>
        ProposalEdits(
          updates: [
            {
              'event': {'id': id, ...fields},
            },
          ],
        );

    test('is moving the start of, ending earlier, or cancelling an event '
        'an earlier compaction recorded', () {
      final proposal = settled();
      String at(int h, [int m = 0]) =>
          localIsoTimestamp(_at(h).add(Duration(minutes: m)));

      expect(
        changesHistory(update('lunch', {'start': at(12, 10)}), proposal),
        isTrue,
      );
      expect(
        changesHistory(update('lunch', {'end': at(12, 20)}), proposal),
        isTrue,
      );
      expect(
        changesHistory(
          const ProposalEdits(
            cancels: [(eventId: 'lunch', countsAgainstFollowThrough: false)],
          ),
          proposal,
        ),
        isTrue,
      );
      // Running on, or renamed, it keeps to what was recorded.
      expect(
        changesHistory(update('lunch', {'end': at(13, 30)}), proposal),
        isFalse,
      );
      expect(
        changesHistory(update('lunch', {'start': at(12)}), proposal),
        isFalse,
      );
      expect(
        changesHistory(update('lunch', {'summary': 'Brunch'}), proposal),
        isFalse,
      );
      // One after it isn't history.
      expect(
        changesHistory(update('call', {'start': at(13, 15)}), proposal),
        isFalse,
      );
    });

    test('approved, is kept with the edit waiting, and sent with it', () async {
      final proposals = _Proposals();
      final outbox = _outbox(proposals);

      await outbox.amend(_proposal(), _edit, allowHistory: true);
      expect(outbox.pending.single.allowHistory, isTrue);
      await outbox.flush(ignoreBackoff: true);

      expect(proposals.allowed, [true]);
    });

    test('approved, is sent to the server so', () async {
      final client = _Client();
      await McpProposalRepository(client)
          .amend(_proposal(), _edit, allowHistory: true);

      expect(client.arguments['allow_compacted_changes'], isTrue);
    });
  });

  group('Queued, confirming', () {
    test('confirms the revision shown, and says what came of it', () async {
      final proposals = _Proposals();
      final outbox = _outbox(proposals);
      final saved = <Object?>[];
      outbox.saved.listen((s) => saved.add(s.$2));

      await outbox.confirm(_proposal());
      await outbox.flush(ignoreBackoff: true);
      await pumpEventQueue();

      expect(proposals.calls, ['confirm 3']);
      expect(outbox.pending, isEmpty);
      expect(outbox.notices!.notices.single.kind, ProposalNoticeKind.applied);
      expect(saved.single, isA<ProposalOutcome>());
    });

    test('rechecked, says so, with the new revision', () async {
      final proposals = _Proposals()
        ..confirmed = ProposalOutcome(
          status: ProposalOutcomeStatus.rechecked,
          message: 'the calendar changed',
          proposal: _proposal(revision: 4),
        );
      final outbox = _outbox(proposals);

      await outbox.confirm(_proposal());
      await outbox.flush(ignoreBackoff: true);

      final notice = outbox.notices!.notices.single;
      expect(notice.kind, ProposalNoticeKind.rechecked);
      expect(notice.revision, 4);
      expect(notice.message, 'the calendar changed');
      expect(notice.text, contains('revision 4'));
    });

    test('refused, stops the queue there', () async {
      final proposals = _Proposals()
        ..confirmError = McpException(
          "revision 3 isn't proposal p1's current one (4)",
        );
      final outbox = _outbox(proposals);

      await outbox.confirm(_proposal());
      final result = await outbox.flush(ignoreBackoff: true);

      expect(result.blocked, isTrue);
      expect(outbox.pending.single.refused, isTrue);
      expect(outbox.notices!.notices, isEmpty);
    });

    test('already being applied, finishes it', () async {
      final proposals = _Proposals()
        ..confirmError = McpException(
          'proposal p1 is already being applied: finish it with '
          'finish_proposal',
        );
      final outbox = _outbox(proposals);

      await outbox.confirm(_proposal());
      await outbox.flush(ignoreBackoff: true);

      expect(proposals.calls, ['confirm 3', 'finish']);
      expect(outbox.pending, isEmpty);
    });

    test('tried again after an attempt went unheard, finishes it first -- '
        'confirming only if it was never confirmed', () async {
      final proposals = _Flaky()..timeOut = true;
      final outbox = _outbox(proposals);

      await outbox.confirm(_proposal());
      await outbox.flush(ignoreBackoff: true);
      expect(outbox.pending.single.attempts, 1);
      proposals.finishError = McpException(
        "proposal p1 hasn't been confirmed, so there's nothing to finish",
      );
      await outbox.flush(ignoreBackoff: true);

      expect(proposals.calls, ['confirm 3', 'finish', 'confirm 3']);
      expect(outbox.pending, isEmpty);
    });

    test('waits for the edits of it first', () async {
      final outbox = _outbox(_Proposals());

      await outbox.amend(_proposal(), _edit);

      expect(
        () => outbox.confirm(_proposal()),
        throwsA(isA<ProposalEditException>()),
      );
    });

    test('takes nothing more of the proposal after it', () async {
      final outbox = _outbox(_Proposals());

      await outbox.confirm(_proposal());

      expect(outbox.closing('p1')?.kind, EventWriteKind.confirm);
      expect(
        () => outbox.amend(_proposal(), _edit),
        throwsA(isA<ProposalEditException>()),
      );
      expect(
        () => outbox.addNote(_proposal(), 'Hm'),
        throwsA(isA<ProposalEditException>()),
      );
      expect(
        () => outbox.abandon(_proposal()),
        throwsA(isA<ProposalEditException>()),
      );
    });
  });

  group('Queued, a note for Claude', () {
    test('shows as left, waiting for Claude, till it is', () async {
      final proposals = _Proposals();
      final outbox = _outbox(proposals)..setPaused(true);

      await outbox.addNote(_proposal(), 'Was it lunch?', eventId: 'lunch');
      final shown = outbox.projectProposal(_proposal())!;

      expect(shown.openFeedback.single.text, 'Was it lunch?');
      expect(shown.openFeedback.single.eventId, 'lunch');
      expect(shown.state, ProposalState.awaitingClaude);
      expect(shown.confirmable, isFalse);
      outbox.setPaused(false);
      await outbox.flush(ignoreBackoff: true);
      expect(proposals.calls, ['note Was it lunch?']);
    });

    test('withdrawn before it is left, is dropped', () async {
      final proposals = _Proposals();
      final outbox = _outbox(proposals)..setPaused(true);

      await outbox.addNote(_proposal(), 'Was it lunch?');
      final pending = outbox.projectProposal(_proposal())!.feedback.single;
      await outbox.withdrawNote(_proposal(), pending.id);

      expect(outbox.pending, isEmpty);
      expect(outbox.projectProposal(_proposal())!.feedback, isEmpty);
    });

    test('withdrawn once left, is withdrawn', () async {
      final proposals = _Proposals();
      final outbox = _outbox(proposals);

      await outbox.withdrawNote(_proposal(), 'p1f1');
      await outbox.flush(ignoreBackoff: true);

      expect(proposals.calls, ['withdraw p1f1']);
    });

    test('tried again after an attempt went unheard, is left once', () async {
      final proposals = _Flaky()..timeOut = true;
      final outbox = _outbox(proposals);

      await outbox.addNote(_proposal(), 'Was it lunch?');
      await outbox.flush(ignoreBackoff: true);
      await outbox.flush(ignoreBackoff: true);

      expect(proposals.calls, ['note Was it lunch?', 'current']);
      expect(outbox.pending, isEmpty);
    });
  });

  group('Queued, abandoning', () {
    test('abandons it, and says so', () async {
      final proposals = _Proposals();
      final outbox = _outbox(proposals);

      await outbox.abandon(_proposal());
      await outbox.flush(ignoreBackoff: true);

      expect(proposals.calls, ['abandon']);
      expect(outbox.notices!.notices.single.kind, ProposalNoticeKind.abandoned);
    });

    test('tried again after an attempt went unheard, is done once', () async {
      final proposals = _Flaky()..timeOut = true;
      final outbox = _outbox(proposals);

      await outbox.abandon(_proposal());
      await outbox.flush(ignoreBackoff: true);
      await outbox.flush(ignoreBackoff: true);

      expect(proposals.calls, ['abandon', 'current']);
      expect(outbox.pending, isEmpty);
    });
  });

  test(
    'the writes of a proposal after one are those made on top of it',
    () async {
      final outbox = _outbox(_Proposals())..setPaused(true);

      await outbox.amend(_proposal(), _edit);
      await outbox.addNote(_proposal(), 'Hm');
      final [edit, note] = outbox.pending;

      expect(outbox.after(edit), [note]);
      expect(outbox.after(note), isEmpty);
    },
  );

  test('a kept write of the proposal reads back as it was written', () {
    final write = PendingEventWrite(
      id: 'w1',
      kind: EventWriteKind.addNote,
      label: 'Note for Claude',
      made: _at(15),
      proposalId: 'p1',
      revision: 3,
      note: const {'text': 'Hm', 'event_id': 'lunch'},
    );
    final withdraw = PendingEventWrite(
      id: 'w2',
      kind: EventWriteKind.withdrawNote,
      label: 'Withdraw a note for Claude',
      made: _at(15),
      proposalId: 'p1',
      feedbackId: 'p1f1',
    );

    final again = PendingEventWrite.fromJson(write.toJson());
    expect(again.kind, EventWriteKind.addNote);
    expect(again.note, {'text': 'Hm', 'event_id': 'lunch'});
    expect(again.revision, 3);
    expect(PendingEventWrite.fromJson(withdraw.toJson()).feedbackId, 'p1f1');
  });

  group('Notices', () {
    test('are kept, the newest last, and dismissed', () async {
      final notices = ProposalNotices(persist: false);
      ProposalNotice notice(int n) => ProposalNotice(
        id: 'n$n',
        kind: ProposalNoticeKind.applied,
        proposalId: 'p1',
        at: _at(15),
      );

      for (var n = 0; n < ProposalNotices.limit + 2; n++) {
        await notices.add(notice(n));
      }
      await notices.dismiss(notices.notices.first);

      expect(notices.notices, hasLength(ProposalNotices.limit - 1));
      expect(notices.notices.last.id, 'n${ProposalNotices.limit + 1}');
    });

    test('read back as written', () {
      final notice = ProposalNotice(
        id: 'n1',
        kind: ProposalNoticeKind.replaced,
        proposalId: 'p1',
        at: _at(15),
        revision: 4,
        eventIds: const ['lunch'],
        eventNames: const ['“Lunch”'],
      );

      final again = ProposalNotice.fromJson(notice.toJson())!;

      expect(again.kind, ProposalNoticeKind.replaced);
      expect(again.revision, 4);
      expect(again.eventNames, ['“Lunch”']);
      expect(again.at, _at(15));
    });

    testWidgets('show till each is dismissed', (tester) async {
      final dismissed = <ProposalNotice>[];
      final notice = ProposalNotice(
        id: 'n1',
        kind: ProposalNoticeKind.rechecked,
        proposalId: 'p1',
        at: _at(15),
        revision: 4,
        message: 'the calendar changed since revision 3',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ProposalNoticesBanner(
              notices: [notice],
              onDismiss: dismissed.add,
            ),
          ),
        ),
      );
      await tester.tap(find.text('OK'));

      expect(find.textContaining('Your confirm came back'), findsOneWidget);
      expect(
        find.text('the calendar changed since revision 3'),
        findsOneWidget,
      );
      expect(dismissed, [notice]);
    });
  });

  testWidgets('the proposal bar says what waits to close it, and takes '
      'nothing meanwhile', (tester) async {
    var confirmed = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ProposalBar(
            proposal: _proposal(),
            closing: 'Confirm what happened',
            onConfirm: () => confirmed = true,
          ),
        ),
      ),
    );

    expect(
      find.textContaining('“Confirm what happened” is waiting to save'),
      findsOneWidget,
    );
    await tester.tap(find.byType(FilledButton));
    expect(confirmed, isFalse);
  });
}

/// A server that answers amend_proposal with a revision, keeping what it
/// was sent.
class _Client extends McpClient {
  _Client() : super(endpoint: Uri.parse('http://test'));

  Map<String, Object?> arguments = const {};

  @override
  Future<Object?> callTool(
    String name, [
    Map<String, Object?> arguments = const {},
  ]) async {
    this.arguments = arguments;
    return {
      'id': 'p1',
      'revision': 4,
      'state': 'awaiting_review',
      'window_start': '2026-09-30T12:00:00Z',
      'through': '2026-09-30T14:00:00Z',
    };
  }
}
