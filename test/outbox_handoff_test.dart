// Handing changes off between the app's outboxes and its Android background
// task's: each has its own, sharing what's kept on the device, and either
// may be sending while the other changes it. No change may be lost, and
// none should be sent twice -- even when a sender is killed mid-request.
//
// The background task's own isolate, and WorkManager, are exercised on an
// emulator (integration_test/outbox_handoff_test.dart); here, two outboxes
// in one isolate stand for the app's and the task's, which is enough to
// interleave their changes to what's kept every which way.

import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';
import 'dart:ui' show IsolateNameServer;

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:time_tracker_client/models/event.dart';
import 'package:time_tracker_client/models/note.dart';
import 'package:time_tracker_client/models/proposal.dart';
import 'package:time_tracker_client/outbox/event_outbox.dart';
import 'package:time_tracker_client/outbox/note_outbox.dart';
import 'package:time_tracker_client/outbox/outbox.dart';
import 'package:time_tracker_client/outbox/outbox_store.dart';
import 'package:time_tracker_client/outbox/store_lock.dart';
import 'package:time_tracker_client/services/events_repository.dart';
import 'package:time_tracker_client/services/mcp_client.dart';
import 'package:time_tracker_client/services/notes_repository.dart';
import 'package:time_tracker_client/services/proposal_repository.dart';
import 'package:time_tracker_client/widgets/other_events.dart';

final _random = Random(7);

/// A moment's wait, now and then: so the two senders' requests, and
/// changes to what's kept, interleave.
Future<void> _jitter() => Future<void>.delayed(
  Duration(microseconds: _random.nextInt(3) == 0 ? 0 : _random.nextInt(4000)),
);

DateTime _at(int minutes) =>
    DateTime(2026, 10, 9, 8).add(Duration(minutes: minutes));

/// The server's notes: each it was asked to save, by who asked.
class _NotesServer extends InMemoryNotesRepository {
  final saved = <String>[];

  /// How many it's saving now, and the most it ever was at once.
  int _inFlight = 0;
  int mostAtOnce = 0;

  /// While set, each note is saved, then this is waited for before
  /// answering: a sender killed mid-request never hears back.
  Completer<void>? hang;

  @override
  Future<Note> addNote(Note note) async {
    mostAtOnce = max(mostAtOnce, ++_inFlight);
    try {
      await _jitter();
      saved.add(note.description!);
      final added = await super.addNote(note);
      if (hang case final h?) await h.future;
      await _jitter();
      return added;
    } finally {
      _inFlight--;
    }
  }

  @override
  Future<List<Note>> uncompactedNotes() async {
    await _jitter();
    return super.uncompactedNotes();
  }
}

/// The server's events: each it was asked to create or cancel; refusing
/// to cancel one again, as the server does.
class _EventsServer extends InMemoryEventsRepository {
  _EventsServer([super.events = const []]);

  final created = <String>[];
  final cancelled = <String>[];
  Completer<void>? hang;

  @override
  Future<List<Event>> createEvent(Map<String, Object?> fields) async {
    await _jitter();
    created.add('${fields['summary']}');
    final made = await super.createEvent(fields);
    if (hang case final h?) await h.future;
    await _jitter();
    return made;
  }

  @override
  Future<List<Event>> deleteEvent(
    Event event, {
    bool countsAgainstFollowThrough = false,
    bool allowCompactedChanges = false,
  }) async {
    await _jitter();
    final there = (await super.events(
      event.start,
      event.end,
    )).any((e) => e.id == event.id);
    if (!there) {
      throw McpException(
        'delete_event: event ${event.id} (${event.summary}) is cancelled '
        'already',
      );
    }
    cancelled.add(event.id!);
    final result = await super.deleteEvent(event);
    if (hang case final h?) await h.future;
    return result;
  }
}

/// A clock both senders share, to move past a claim's timeout.
class _Clock {
  DateTime now = DateTime(2026, 10, 9, 12);
  DateTime call() => now;
  void pass(Duration d) => now = now.add(d);
}

void main() {
  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });

  group('The app and its background task, sending at once,', () {
    test('send every note once: none lost, none twice', () async {
      final server = _NotesServer();
      final app = NoteOutbox(
        store: PrefsOutboxStore.notes(),
        repository: server,
      );
      final background = NoteOutbox(
        store: PrefsOutboxStore.notes(),
        repository: server,
        sender: Outbox.backgroundSender,
      );
      const count = 60;
      var done = false;
      // The task, flushing as WorkManager runs it, over and over.
      final task = () async {
        while (!done) {
          await background.flush(ignoreBackoff: true);
          await _jitter();
        }
      }();
      // The app, taking notes while it sends them, now and then going to
      // the background and back.
      app.start();
      for (var i = 0; i < count; i++) {
        await app.add(Note(timestamp: _at(i), description: 'note $i'));
        if (i % 10 == 5) app.stop();
        if (i % 10 == 8) app.start();
        await _jitter();
      }
      app.start();
      await _until(() async => (await PrefsOutboxStore.notes().load()).isEmpty);
      done = true;
      await task;
      app.dispose();

      expect(
        server.saved..sort(),
        [for (var i = 0; i < count; i++) 'note $i']..sort(),
      );
      // One at a time: neither took one while the other was sending.
      expect(server.mostAtOnce, 1);
    });

    test('send every change to events once, in order', () async {
      final server = _EventsServer();
      final app = EventOutbox(store: PrefsOutboxStore.events(), events: server);
      final background = EventOutbox(
        store: PrefsOutboxStore.events(),
        events: server,
        sender: Outbox.backgroundSender,
      );
      const count = 40;
      var done = false;
      final task = () async {
        while (!done) {
          await background.flush(ignoreBackoff: true);
          await _jitter();
        }
      }();
      app.start();
      for (var i = 0; i < count; i++) {
        await app.create({
          'summary': 'event $i',
          'start': localIsoTimestamp(_at(i * 10)),
          'end': localIsoTimestamp(_at(i * 10 + 5)),
        });
        if (i % 10 == 5) app.stop();
        if (i % 10 == 8) app.start();
        await _jitter();
      }
      app.start();
      await _until(
        () async => (await PrefsOutboxStore.events().load()).isEmpty,
      );
      done = true;
      await task;
      app.dispose();

      // Strictly in the order made, each once.
      expect(server.created, [for (var i = 0; i < count; i++) 'event $i']);
    });
  });

  group('A change sent by a sender killed mid-request', () {
    // The background task claims it and sends it, and the server saves it,
    // but the task is killed before it hears back: its claim stays. Once
    // that's timed out, the app sends it -- checking first that it wasn't
    // saved, so it's saved once.
    Future<void> handOff(
      Outbox outbox,
      Outbox killed,
      _Clock clock,
      void Function(Completer<void>?) hang, {
      required bool Function() saved,
    }) async {
      final h = Completer<void>();
      hang(h);
      unawaited(killed.flush(ignoreBackoff: true));
      // The server has it; the task's waiting to hear, and never will.
      await _until(() async => saved());
      await outbox.refresh();
      // Still claimed: the app leaves it be.
      await outbox.flush(ignoreBackoff: true);
      expect(outbox.items, hasLength(1));
      hang(null);
      clock.pass(Outbox.inFlightTimeout + const Duration(seconds: 1));
      await outbox.flush(ignoreBackoff: true);
      expect(outbox.items, isEmpty);
    }

    test('a note, is saved once', () async {
      final clock = _Clock();
      final server = _NotesServer();
      NoteOutbox outbox() => NoteOutbox(
        store: PrefsOutboxStore.notes(),
        repository: server,
        clock: clock.call,
      );
      final app = outbox(), task = outbox();
      await app.add(Note(timestamp: _at(0), description: 'Lunch'));

      await handOff(
        app,
        task,
        clock,
        (h) => server.hang = h,
        saved: () => server.saved.isNotEmpty,
      );

      expect(server.saved, ['Lunch']);
    });

    test('a new event, is made once', () async {
      final clock = _Clock();
      final server = _EventsServer();
      EventOutbox outbox() => EventOutbox(
        store: PrefsOutboxStore.events(),
        events: server,
        clock: clock.call,
      );
      final app = outbox(), task = outbox();
      await app.create({
        'summary': 'Tea',
        'start': localIsoTimestamp(_at(0)),
        'end': localIsoTimestamp(_at(30)),
      });

      await handOff(
        app,
        task,
        clock,
        (h) => server.hang = h,
        saved: () => server.created.isNotEmpty,
      );

      expect(server.created, ['Tea']);
    });

    test('a cancel, is not refused as cancelled already', () async {
      final clock = _Clock();
      final lunch = Event(id: 'lunch', start: _at(0), end: _at(60));
      final server = _EventsServer([lunch]);
      EventOutbox outbox() => EventOutbox(
        store: PrefsOutboxStore.events(),
        events: server,
        clock: clock.call,
      );
      final app = outbox(), task = outbox();
      await app.cancel(lunch);

      await handOff(
        app,
        task,
        clock,
        (h) => server.hang = h,
        saved: () => server.cancelled.isNotEmpty,
      );

      expect(server.cancelled, ['lunch']);
    });

    test('a move that splits another, makes its other part once', () async {
      final clock = _Clock();
      final work = Event(
        id: 'work',
        summary: 'Work',
        start: _at(0),
        end: _at(120),
      );
      final server = _EventsServer([work]);
      EventOutbox outbox() => EventOutbox(
        store: PrefsOutboxStore.events(),
        events: server,
        clock: clock.call,
      );
      final app = outbox(), task = outbox();
      await app.makeRoom(
        Overwrite(
          updates: [
            (work, {'end': localIsoTimestamp(_at(30))}),
          ],
          creates: [
            {
              'summary': 'Work',
              'start': localIsoTimestamp(_at(60)),
              'end': localIsoTimestamp(_at(120)),
            },
          ],
        ),
      );

      await handOff(
        app,
        task,
        clock,
        (h) => server.hang = h,
        saved: () => server.created.isNotEmpty,
      );

      expect(server.created, ['Work']);
    });

    test(
      'an edit of the proposal that creates an event, creates it once',
      () async {
        final clock = _Clock();
        final proposals = _HangingProposals(
          Proposal(
            id: 'p1',
            revision: 1,
            state: ProposalState.awaitingReview,
            windowStart: _at(0),
            through: _at(240),
            events: [
              ProposalEvent(
                id: 'lunch',
                start: _at(0),
                end: _at(60),
                status: ProposalEventStatus.onSchedule,
                summary: 'Lunch',
              ),
            ],
          ),
        );
        EventOutbox outbox() => EventOutbox(
          store: PrefsOutboxStore.events(),
          events: _EventsServer(),
          proposals: proposals,
          clock: clock.call,
        );
        final app = outbox(), task = outbox();
        await app.amend(
          proposals.proposal!,
          ProposalEdits(
            creates: [
              {
                'summary': 'Coffee',
                'start': localIsoTimestamp(_at(90)),
                'end': localIsoTimestamp(_at(100)),
              },
            ],
          ),
        );

        await handOff(
          app,
          task,
          clock,
          (h) => proposals.hang = h,
          saved: () => proposals.amended > 0,
        );

        expect([
          for (final e in proposals.proposal!.events!)
            if (e.summary == 'Coffee') e,
        ], hasLength(1));
      },
    );
  });

  test('a change being sent by the background task can\'t be dropped by '
      'the app, though the app has yet to hear it\'s being sent', () async {
    final server = _NotesServer();
    final app = NoteOutbox(store: PrefsOutboxStore.notes(), repository: server);
    final task = NoteOutbox(
      store: PrefsOutboxStore.notes(),
      repository: server,
    );
    await app.add(Note(timestamp: _at(0), description: 'Lunch'));
    final note = app.items.single;
    server.hang = Completer<void>();

    unawaited(task.flush(ignoreBackoff: true));
    await _until(() async => server.saved.isNotEmpty);

    // The app's copy says it isn't being sent; what's kept says it is.
    expect(app.isSending(note), isFalse);
    expect(await app.cancel(note), isFalse);
    server.hang!.complete();
    await _until(() async => (await PrefsOutboxStore.notes().load()).isEmpty);
    expect(server.saved, ['Lunch']);
  });

  test('while the background task sends one note, the app takes none of '
      "the rest, and says who's sending", () async {
    final server = _NotesServer();
    final app = NoteOutbox(store: PrefsOutboxStore.notes(), repository: server);
    final task = NoteOutbox(
      store: PrefsOutboxStore.notes(),
      repository: server,
      sender: Outbox.backgroundSender,
    );
    await app.add(Note(timestamp: _at(0), description: 'Lunch'));
    await app.add(Note(timestamp: _at(1), description: 'Coffee'));
    final hang = server.hang = Completer<void>();

    unawaited(task.flush(ignoreBackoff: true));
    await _until(() async => server.saved.isNotEmpty);
    await app.flush(ignoreBackoff: true);

    expect(server.saved, ['Lunch']);
    final lunch = app.items.firstWhere((n) => n.note.description == 'Lunch');
    expect(lunch.sentBy, Outbox.backgroundSender);
    expect(app.sendingBy(lunch), 'the background task');
    expect(
      app.sendingBy(
        app.items.firstWhere((n) => n.note.description == 'Coffee'),
      ),
      isNull,
    );

    server.hang = null;
    hang.complete();
    await _until(() async => server.saved.length == 2 || app.items.length < 2);
    await _until(() async {
      await app.flush(ignoreBackoff: true);
      return (await PrefsOutboxStore.notes().load()).isEmpty;
    });
    expect(server.saved, ['Lunch', 'Coffee']);
    expect(server.mostAtOnce, 1);
  });

  group('The lock on what\'s kept', () {
    test('lets one isolate change it at a time', () async {
      final dir = await Directory.systemTemp.createTemp('outbox_lock');
      final file = File('${dir.path}/count')..writeAsStringSync('0');
      const each = 40;
      final exits = [
        for (var i = 0; i < 3; i++)
          () async {
            final exit = ReceivePort();
            await Isolate.spawn(_increment, (
              file.path,
              each,
            ), onExit: exit.sendPort);
            await exit.first;
          }(),
      ];
      await Future.wait(exits);

      expect(int.parse(file.readAsStringSync()), 3 * each);
      await dir.delete(recursive: true);
    });

    test('is taken from a holder that died holding it', () async {
      const name = 'outbox_store:test-dead';
      final dead = ReceivePort();
      IsolateNameServer.registerPortWithName(dead.sendPort, name);
      dead.close();

      final ran = await const IsolateStoreLock(name)
          .hold((_) async => true, wait: const Duration(seconds: 10));

      expect(ran, isTrue);
      expect(IsolateNameServer.lookupPortByName(name), isNull);
    });

    test('is held till a write that outlived its timeout is done', () async {
      const lock = IsolateStoreLock('outbox_store:test-slow');
      final write = Completer<void>();
      final order = <String>[];

      await expectLater(
        lock.hold((keepUntil) async {
          keepUntil(write.future);
          throw TimeoutException('write');
        }),
        throwsA(isA<TimeoutException>()),
      );
      final next = lock.hold((_) async => order.add('next'));
      await Future<void>.delayed(const Duration(milliseconds: 50));
      order.add('written');
      write.complete();
      await next;

      expect(order, ['written', 'next']);
    });
  });
}

/// Read, add one, and write back, [each] times, holding the lock.
Future<void> _increment((String, int) args) async {
  final (path, each) = args;
  final file = File(path);
  const lock = IsolateStoreLock('outbox_store:test-count');
  for (var i = 0; i < each; i++) {
    await lock.hold((_) async {
      final n = int.parse(await file.readAsString());
      await Future<void>.delayed(Duration(microseconds: Random().nextInt(500)));
      await file.writeAsString('${n + 1}', flush: true);
    });
  }
}

/// Proposals whose amend, while [hang] is set, is made, then never
/// answered.
class _HangingProposals extends InMemoryProposalRepository {
  _HangingProposals(super.proposal);

  Completer<void>? hang;

  /// How many amends were made.
  int amended = 0;

  @override
  Future<Proposal> amend(
    Proposal proposal,
    ProposalEdits edits, {
    bool allowHistory = false,
  }) async {
    final amended = await super.amend(proposal, edits);
    this.amended++;
    if (hang case final h?) await h.future;
    return amended;
  }
}

/// Waits for [done], checking every few milliseconds, for up to a minute.
Future<void> _until(Future<bool> Function() done) async {
  final deadline = DateTime.now().add(const Duration(minutes: 1));
  while (!await done()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('Timed out waiting.');
    }
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}
