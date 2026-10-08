import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:time_tracker_client/models/event.dart';
import 'package:time_tracker_client/models/note.dart';
import 'package:time_tracker_client/models/proposal.dart';
import 'package:time_tracker_client/outbox/event_outbox.dart';
import 'package:time_tracker_client/outbox/outbox_store.dart';
import 'package:time_tracker_client/screens/events_screen.dart';
import 'package:time_tracker_client/services/events_repository.dart';
import 'package:time_tracker_client/services/mcp_client.dart';
import 'package:time_tracker_client/services/proposal_repository.dart';
import 'package:time_tracker_client/widgets/event_outbox_bar.dart';
import 'package:time_tracker_client/widgets/other_events.dart';
import 'package:time_tracker_client/widgets/waiting_note.dart';

final _day = DateTime(2026, 9, 30);
DateTime _at(int hour, [int minute = 0]) => DateTime(2026, 9, 30, hour, minute);

Event _event(String id, String summary, int from, int to) => Event.fromJson({
  'id': id,
  'summary': summary,
  'start': localIsoTimestamp(_at(from)),
  'end': localIsoTimestamp(_at(to)),
});

/// An in-memory calendar that records what's sent, and can refuse it.
class _Server extends InMemoryEventsRepository {
  _Server(super.events);

  final calls = <String>[];

  /// Each call is refused with this, while it's set.
  Object? refuse;

  /// What [events] returns, once, before anything else is asked: what an
  /// attempt nobody heard back from saved.
  Future<void> _check(String call) async {
    calls.add(call);
    if (refuse case final error?) throw error;
  }

  @override
  Future<List<Event>> updateEvent(
    Event event,
    Map<String, Object?> changes, {
    bool allowCompactedChanges = false,
  }) async {
    await _check(
      'update ${event.id} ${changes.keys.join(',')}'
      '${allowCompactedChanges ? ' (history)' : ''}',
    );
    return super.updateEvent(event, changes);
  }

  @override
  Future<List<Event>> deleteEvent(
    Event event, {
    bool countsAgainstFollowThrough = false,
    bool allowCompactedChanges = false,
  }) async {
    await _check('cancel ${event.id}');
    return super.deleteEvent(
      event,
      countsAgainstFollowThrough: countsAgainstFollowThrough,
    );
  }

  @override
  Future<List<Event>> createEvent(Map<String, Object?> fields) async {
    await _check('create ${fields['summary']}');
    return super.createEvent(fields);
  }

  @override
  Future<List<Event>> makeRoom(
    Overwrite over, {
    bool allowCompactedChanges = false,
  }) async {
    await _check('makeRoom ${over.count}');
    return super.makeRoom(over);
  }
}

EventOutbox _outbox(_Server server, {ProposalRepository? proposals}) =>
    EventOutbox(
      store: InMemoryOutboxStore(),
      events: server,
      proposals: proposals,
    );

void main() {
  group('EventOutbox', () {
    test("shows what's waiting as made: changed, cancelled, created", () async {
      final server = _Server([
        _event('lunch', 'Lunch', 12, 13),
        _event('call', 'Call', 15, 16),
      ]);
      final outbox = _outbox(server);
      final events = await server.events(_day, _at(24));

      await outbox.update(events[0], {'summary': 'Long lunch'});
      await outbox.cancel(events[1]);
      await outbox.create({
        'summary': 'Tea',
        'start': localIsoTimestamp(_at(17)),
        'end': localIsoTimestamp(_at(18)),
      });

      final shown = outbox.project(events, _day, _at(24));
      expect([for (final e in shown) e.summary], ['Long lunch', 'Call', 'Tea']);
      expect(shown[1].isCancelled, isTrue);
      expect(PendingEventWrite.isPendingId(shown[2].id), isTrue);
      // Nothing's sent till it's started.
      expect(server.calls, isEmpty);
    });

    test('a move to another day shows there, and not where it was', () async {
      final server = _Server([_event('lunch', 'Lunch', 12, 13)]);
      final outbox = _outbox(server);
      final lunch = (await server.events(_day, _at(24))).single;

      final tomorrow = DateTime(2026, 10, 1, 12);
      await outbox.update(lunch, {
        'start': localIsoTimestamp(tomorrow),
        'end': localIsoTimestamp(tomorrow.add(const Duration(hours: 1))),
      });

      expect(outbox.project([lunch], _day, _at(24)), isEmpty);
      expect(
        outbox
            .project(const [], DateTime(2026, 10, 1), DateTime(2026, 10, 2))
            .single
            .summary,
        'Lunch',
      );
    });

    test('what a write changes waits for it: the same field, or a cancelled '
        'or new event, all of it', () async {
      final server = _Server([_event('lunch', 'Lunch', 12, 13)]);
      final outbox = _outbox(server);
      final lunch = (await server.events(_day, _at(24))).single;

      await outbox.update(lunch, {'summary': 'Long lunch'});
      expect(outbox.locked('lunch'), {'summary'});
      expect(outbox.isLocked('lunch', 'summary'), isTrue);
      expect(outbox.isLocked('lunch', 'description'), isFalse);

      // Another field: fine.
      await outbox.update(lunch, {'description': 'With Sam'});
      expect(outbox.locked('lunch'), {'summary', 'description'});
      // The same one, or cancelling it: not till it's saved.
      await expectLater(
        outbox.update(lunch, {'summary': 'Short lunch'}),
        throwsA(
          isA<WaitingForWrite>().having(
            (w) => w.toString(),
            'message',
            contains(
              "Can't change its title yet: “Change “Lunch”” is "
              'waiting to save',
            ),
          ),
        ),
      );
      await expectLater(outbox.cancel(lunch), throwsA(isA<WaitingForWrite>()));
      expect(outbox.pending, hasLength(2));
    });

    test('a cancelled event waits whole, and so does a new one', () async {
      final server = _Server([_event('lunch', 'Lunch', 12, 13)]);
      final outbox = _outbox(server);
      final lunch = (await server.events(_day, _at(24))).single;

      await outbox.cancel(lunch);
      await outbox.create({
        'summary': 'Tea',
        'start': localIsoTimestamp(_at(17)),
        'end': localIsoTimestamp(_at(18)),
      });

      expect(outbox.isWhollyLocked('lunch'), isTrue);
      await expectLater(
        outbox.update(lunch, {'description': 'x'}),
        throwsA(isA<WaitingForWrite>()),
      );
      final tea = outbox.pending.last.pendingId();
      expect(outbox.isWhollyLocked(tea), isTrue);
    });

    test('a move locks the times of the events it makes room in', () async {
      final server = _Server([
        _event('lunch', 'Lunch', 12, 13),
        _event('call', 'Call', 13, 14),
      ]);
      final outbox = _outbox(server);
      final [lunch, call] = await server.events(_day, _at(24));

      await outbox.makeRoom(
        Overwrite(
          updates: [
            (
              lunch,
              {
                'start': localIsoTimestamp(_at(12, 30)),
                'end': localIsoTimestamp(_at(13, 30)),
              },
            ),
            (call, {'start': localIsoTimestamp(_at(13, 30))}),
          ],
        ),
      );

      expect(outbox.locked('lunch'), {'start', 'end'});
      expect(outbox.locked('call'), {'start'});
      // Its time can't move again; its title can change.
      await expectLater(
        outbox.update(call, {'end': localIsoTimestamp(_at(15))}),
        throwsA(isA<WaitingForWrite>()),
      );
      await outbox.update(call, {'summary': 'Phone call'});
    });

    test('sends them in order, saying what each saved', () async {
      final server = _Server([_event('lunch', 'Lunch', 12, 13)]);
      final outbox = _outbox(server);
      final lunch = (await server.events(_day, _at(24))).single;
      final saved = <String?>[];
      outbox.saved.listen((s) {
        if (s.$2 case final List<Event> events) {
          saved.addAll(events.map((e) => e.summary));
        }
      });

      await outbox.update(lunch, {'summary': 'Long lunch'});
      await outbox.create({
        'summary': 'Tea',
        'start': localIsoTimestamp(_at(17)),
        'end': localIsoTimestamp(_at(18)),
      });
      final result = await outbox.flush(ignoreBackoff: true);
      await Future<void>.delayed(Duration.zero);

      expect(result.remaining, 0);
      expect(server.calls, ['update lunch summary', 'create Tea']);
      expect(saved, ['Long lunch', 'Tea']);
      expect(outbox.pending, isEmpty);
      // Nothing waits any more.
      expect(outbox.locked('lunch'), isEmpty);
    });

    test('one the server refuses stops the queue there, till it is dropped, '
        'or tried again', () async {
      final server = _Server([
        _event('lunch', 'Lunch', 12, 13),
        _event('call', 'Call', 15, 16),
      ]);
      final outbox = _outbox(server);
      final [lunch, call] = await server.events(_day, _at(24));

      await outbox.update(lunch, {'end': localIsoTimestamp(_at(15, 30))});
      await outbox.update(call, {'summary': 'Phone call'});
      server.refuse = McpException('update_event: it would overlap “Call”');
      final first = await outbox.flush();

      expect(first.blocked, isTrue);
      expect(server.calls, ['update lunch end']);
      expect(outbox.pending.first.refused, isTrue);
      expect(outbox.pending.first.lastError, contains('overlap'));
      // Nothing after it is sent, even once the server would take it.
      server.refuse = null;
      await outbox.flush();
      expect(server.calls, ['update lunch end']);

      await outbox.drop(outbox.pending.first);
      await outbox.flush();
      expect(server.calls, ['update lunch end', 'update call summary']);
      expect(outbox.pending, isEmpty);
    });

    test(
      "one that couldn't be sent is tried again, later, by itself",
      () async {
        var now = _at(9);
        final server = _Server([_event('lunch', 'Lunch', 12, 13)]);
        final outbox = EventOutbox(
          store: InMemoryOutboxStore(),
          events: server,
          clock: () => now,
        );
        final lunch = (await server.events(_day, _at(24))).single;

        await outbox.update(lunch, {'summary': 'Long lunch'});
        server.refuse = http.ClientException('Connection reset by peer');
        await outbox.flush();

        final waiting = outbox.pending.single;
        expect(waiting.refused, isFalse);
        expect(waiting.attempts, 1);
        expect(waiting.nextAttemptAt, now.add(const Duration(seconds: 5)));

        server.refuse = null;
        now = now.add(const Duration(seconds: 6));
        await outbox.flush();
        expect(outbox.pending, isEmpty);
      },
    );

    test('paused, nothing is sent till it is resumed', () async {
      final server = _Server([_event('lunch', 'Lunch', 12, 13)]);
      final outbox = _outbox(server);
      final lunch = (await server.events(_day, _at(24))).single;

      outbox.setPaused(true);
      await outbox.update(lunch, {'summary': 'Long lunch'});
      await outbox.flush(ignoreBackoff: true);
      expect(server.calls, isEmpty);

      outbox.setPaused(false);
      await outbox.flush();
      expect(server.calls, ['update lunch summary']);
    });

    test('a write refused as changing history is sent again once '
        'approved', () async {
      final server = _Server([_event('lunch', 'Lunch', 12, 13)]);
      final outbox = _outbox(server);
      final lunch = (await server.events(_day, _at(24))).single;

      await outbox.update(lunch, {'summary': 'Long lunch'});
      server.refuse = McpException(
        'update_event: that is history; set allow_compacted_changes',
      );
      await outbox.flush();
      expect(outbox.pending.single.refusedAsHistory, isTrue);

      server.refuse = null;
      await outbox.approveHistory(outbox.pending.single);
      expect(server.calls.last, 'update lunch summary (history)');
      expect(outbox.pending, isEmpty);
    });

    test('an edit of one waiting replaces it, in its place', () async {
      final server = _Server([_event('lunch', 'Lunch', 12, 13)]);
      final outbox = _outbox(server);
      final lunch = (await server.events(_day, _at(24))).single;

      await outbox.update(lunch, {'summary': 'Long lunch'});
      final write = outbox.pending.single;
      await outbox.edit(
        write,
        write.copyWith(changes: {'summary': 'Lunch with Sam'}),
      );

      expect(
        outbox.project([lunch], _day, _at(24)).single.summary,
        'Lunch with Sam',
      );
      await outbox.flush();
      expect(server.calls, ['update lunch summary']);
      expect(
        (await server.events(_day, _at(24))).single.summary,
        'Lunch with Sam',
      );
    });

    test("a new event isn't made twice when an attempt nobody heard back "
        'from made it', () async {
      final server = _Server(const []);
      final fields = {
        'summary': 'Tea',
        'start': localIsoTimestamp(_at(17)),
        'end': localIsoTimestamp(_at(18)),
      };
      // Made, but the answer was lost: tried once already.
      await server.createEvent(fields);
      server.calls.clear();
      final outbox = EventOutbox(
        store: InMemoryOutboxStore()
          ..items = [
            PendingEventWrite(
              id: 'tea',
              kind: EventWriteKind.create,
              label: 'Add “Tea”',
              made: _at(9),
              fields: fields,
              attempts: 1,
            ),
          ],
        events: server,
      );

      await outbox.flush();

      expect(server.calls, isEmpty);
      expect(await server.events(_day, _at(24)), hasLength(1));
    });

    test('is kept as it was, every kind', () async {
      final lunch = _event('lunch', 'Lunch', 12, 13);
      final writes = [
        PendingEventWrite(
          id: 'a',
          kind: EventWriteKind.makeRoom,
          label: 'Move “Lunch”',
          made: _at(9),
          over: Overwrite(
            updates: [
              (lunch, {'start': localIsoTimestamp(_at(12, 30))}),
            ],
            cancels: [_event('call', 'Call', 13, 14)],
            creates: [
              {'summary': 'Rest of it'},
            ],
          ),
          allowHistory: true,
          attempts: 2,
          lastError: 'Connection reset',
          nextAttemptAt: _at(9, 1),
        ),
        PendingEventWrite(
          id: 'b',
          kind: EventWriteKind.amend,
          label: 'Change what happened',
          made: _at(9),
          proposalId: 'p1',
          revision: 3,
          edits: const ProposalEdits(
            updates: [
              {
                'event': {'id': 'lunch', 'summary': 'Brunch'},
              },
            ],
            cancels: [(eventId: 'call', countsAgainstFollowThrough: true)],
            asPlanned: ['tea'],
          ),
          refused: true,
        ),
      ];
      for (final write in writes) {
        final kept = PendingEventWrite.fromJson(write.toJson());
        expect(kept.toJson(), write.toJson());
        expect(kept.locks, write.locks);
      }
    });

    test('an edit of the proposal behind another is made on the revision '
        'that one makes', () async {
      final server = _Server(const []);
      final proposals = _Proposals();
      final outbox = _outbox(server, proposals: proposals);
      final proposal = _proposal();

      await outbox.amend(
        proposal,
        const ProposalEdits(
          updates: [
            {
              'event': {'id': 'lunch', 'summary': 'Brunch'},
            },
          ],
        ),
      );
      final shown = await outbox.amend(
        proposal,
        const ProposalEdits(
          cancels: [(eventId: 'call', countsAgainstFollowThrough: false)],
        ),
      );

      // Shown as both leave it.
      expect(shown.event('lunch')!.summary, 'Brunch');
      expect(shown.event('call')!.live, isFalse);
      await outbox.flush(ignoreBackoff: true);
      expect(proposals.revisions, [3, 4]);
    });
  });

  group('On the Events page', () {
    Future<(EventOutbox, _Server)> pump(WidgetTester tester) async {
      final server = _Server([_event('lunch', 'Lunch', 12, 13)]);
      final outbox = _outbox(server)..setPaused(true);
      addTearDown(outbox.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: EventsScreen(
              repository: server,
              serverLabel: 'test',
              eventOutbox: outbox,
              clock: () => _at(9),
            ),
            bottomNavigationBar: EventOutboxBar(outbox: outbox),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return (outbox, server);
    }

    Finder inDialog(Finder f) =>
        find.descendant(of: find.byType(AlertDialog), matching: f);

    Future<void> rename(WidgetTester tester, String from, String to) async {
      await tester.ensureVisible(find.text(from).first);
      await tester.tap(find.text(from).first);
      await tester.pumpAndSettle();
      await tester.tap(inDialog(find.text(from)));
      await tester.pumpAndSettle();
      await tester.enterText(inDialog(find.byType(TextField)), to);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
    }

    testWidgets('a change is shown at once, waiting to save, and the bar '
        'says so', (tester) async {
      final (outbox, server) = await pump(tester);

      await rename(tester, 'Lunch', 'Long lunch');

      expect(find.byType(AlertDialog), findsNothing);
      expect(find.text('Long lunch'), findsOneWidget);
      expect(find.textContaining('Waiting to save'), findsWidgets);
      expect(find.text('Paused: 1 change waiting to save'), findsOneWidget);
      expect(server.calls, isEmpty);
      expect(outbox.pending.single.label, 'Change “Lunch”');
    });

    testWidgets("what's waiting can't change, and says so", (tester) async {
      await pump(tester);
      await rename(tester, 'Lunch', 'Long lunch');

      await tester.ensureVisible(find.text('Long lunch').first);
      await tester.tap(find.text('Long lunch').first);
      await tester.pumpAndSettle();

      expect(find.byType(WaitingNote), findsOneWidget);
      expect(
        find.text("Its title is waiting to save, and can't change until then."),
        findsOneWidget,
      );
      // The title doesn't open; nor can it be cancelled.
      await tester.tap(inDialog(find.text('Long lunch')));
      await tester.pumpAndSettle();
      expect(inDialog(find.byType(TextField)), findsNothing);
      expect(find.byTooltip('Cancel event'), findsNothing);
    });

    testWidgets('the bar slides up the changes, to resume, or drop one', (
      tester,
    ) async {
      final (outbox, server) = await pump(tester);
      await rename(tester, 'Lunch', 'Long lunch');

      await tester.tap(find.text('Paused: 1 change waiting to save'));
      await tester.pumpAndSettle();
      expect(find.text('Changes waiting to save'), findsOneWidget);
      expect(find.text('Change “Lunch”'), findsOneWidget);

      await tester.tap(find.text('Drop'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Drop it'));
      await tester.pumpAndSettle();
      expect(
        find.text('Nothing waiting: everything is saved.'),
        findsOneWidget,
      );
      expect(outbox.pending, isEmpty);
      // Back as the server has it.
      Navigator.of(tester.element(find.byType(EventsScreen))).pop();
      await tester.pumpAndSettle();
      expect(find.text('Lunch'), findsOneWidget);
      expect(server.calls, isEmpty);
    });

    testWidgets('resumed, it saves, and the change stays', (tester) async {
      final (outbox, server) = await pump(tester);
      await rename(tester, 'Lunch', 'Long lunch');

      await tester.tap(find.text('Paused: 1 change waiting to save'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Resume'));
      unawaited(outbox.flush());
      await tester.pumpAndSettle();

      expect(server.calls, ['update lunch summary']);
      expect(
        find.text('Nothing waiting: everything is saved.'),
        findsOneWidget,
      );
      Navigator.of(tester.element(find.byType(EventsScreen))).pop();
      await tester.pumpAndSettle();
      expect(find.text('Long lunch'), findsOneWidget);
      expect(find.textContaining('Waiting to save'), findsNothing);
    });

    testWidgets('one refused stops the queue, and the bar says what to fix', (
      tester,
    ) async {
      final (outbox, server) = await pump(tester);
      await rename(tester, 'Lunch', 'Long lunch');
      server.refuse = McpException('update_event: it would overlap “Call”');
      outbox.setPaused(false);
      unawaited(outbox.flush());
      await tester.pumpAndSettle();

      expect(
        find.text("Couldn't save Change “Lunch”: tap to fix it"),
        findsOneWidget,
      );
      await tester.tap(
        find.text("Couldn't save Change “Lunch”: tap to fix it"),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('it would overlap “Call”'), findsOneWidget);
      expect(find.text('Try again'), findsOneWidget);
      expect(find.text('Edit'), findsOneWidget);
    });

    testWidgets('a refusal names the events it mentions, each to show', (
      tester,
    ) async {
      const id = 'lunch0123456789abcdefgh';
      final server = _Server([_event(id, 'Lunch', 12, 13)]);
      final outbox = _outbox(server)..setPaused(true);
      addTearDown(outbox.dispose);
      final shown = <Event>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: EventsScreen(
              repository: server,
              serverLabel: 'test',
              eventOutbox: outbox,
              clock: () => _at(9),
            ),
            bottomNavigationBar: EventOutboxBar(
              outbox: outbox,
              onShow: shown.add,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await rename(tester, 'Lunch', 'Long lunch');
      server.refuse = McpException(
        "update_event: '$id' would overlap 2k2j75c3mjlhqr3e8sibgrfjpq",
      );
      outbox.setPaused(false);
      unawaited(outbox.flush());
      await tester.pumpAndSettle();
      await tester.tap(find.byType(EventOutboxBar));
      await tester.pumpAndSettle();

      // On its day, not being today.
      expect(
        find.textContaining(
          'update_event: “Lunch” (Sep 30, 12:00 PM) would overlap an event.',
        ),
        findsOneWidget,
      );
      expect(find.textContaining(id), findsNothing);
      await tester.tap(find.text('Show “Lunch”'));
      await tester.pumpAndSettle();
      expect(shown.single.id, id);
      // The sheet's closed, to see it.
      expect(find.text('Changes waiting to save'), findsNothing);
    });
  });
}

/// A proposal of lunch and a call, at revision 3.
Proposal _proposal() => Proposal(
  id: 'p1',
  revision: 3,
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
    ProposalEvent(
      id: 'call',
      start: _at(13),
      end: _at(14),
      status: ProposalEventStatus.onSchedule,
      summary: 'Call',
    ),
  ],
);

/// Records the revision each amend is made on, each making the next.
class _Proposals implements ProposalRepository {
  final revisions = <int>[];

  @override
  Future<Proposal> amend(Proposal proposal, ProposalEdits edits) async {
    revisions.add(proposal.revision);
    return Proposal(
      id: proposal.id,
      revision: proposal.revision + 1,
      state: ProposalState.awaitingReview,
      windowStart: proposal.windowStart,
      through: proposal.through,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
