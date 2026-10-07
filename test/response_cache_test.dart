import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:time_tracker_client/outbox/action_outbox.dart';
import 'package:time_tracker_client/models/event.dart';
import 'package:time_tracker_client/models/plan_action.dart';
import 'package:time_tracker_client/models/note.dart';
import 'package:time_tracker_client/outbox/note_outbox.dart';
import 'package:time_tracker_client/outbox/outbox_store.dart';
import 'package:time_tracker_client/screens/events_screen.dart';
import 'package:time_tracker_client/screens/plan_screen.dart';
import 'package:time_tracker_client/screens/notes_screen.dart';
import 'package:time_tracker_client/services/event_store.dart';
import 'package:time_tracker_client/services/plan_memory.dart';
import 'package:time_tracker_client/services/events_repository.dart';
import 'package:time_tracker_client/widgets/day_timeline.dart';
import 'package:time_tracker_client/services/actions_repository.dart';
import 'package:time_tracker_client/services/mcp_client.dart';
import 'package:time_tracker_client/services/notes_repository.dart';
import 'package:time_tracker_client/services/response_cache.dart';

void main() {
  group('PrefsResponseCache', () {
    setUp(() {
      SharedPreferencesAsyncPlatform.instance =
          InMemorySharedPreferencesAsync.empty();
    });

    test('keeps entries across instances', () async {
      await PrefsResponseCache().write('a', [
        {'x': 1},
      ]);
      expect(await PrefsResponseCache().read('a'), [
        {'x': 1},
      ]);
      expect(await PrefsResponseCache().read('b'), isNull);
    });

    test('clear forgets everything', () async {
      final cache = PrefsResponseCache();
      await cache.write('a', 1);
      await cache.clear();
      expect(await cache.read('a'), isNull);
      expect(await PrefsResponseCache().read('a'), isNull);
    });
  });

  group('MCP repositories', () {
    test('keep what get_notes returned', () async {
      final cache = InMemoryResponseCache();
      final note = Note(timestamp: DateTime(2026, 9, 30, 9), description: 'a');
      final repo = McpNotesRepository(
        _FakeClient([note.toJson()]),
        cache: cache,
      );
      expect(await repo.cachedUncompactedNotes(), isNull);

      await repo.uncompactedNotes();
      final cached = await McpNotesRepository(
        _FakeClient(null),
        cache: cache,
      ).cachedUncompactedNotes();
      expect(cached!.single.description, 'a');
    });

    test('keep what get_compaction_status returned', () async {
      final cache = InMemoryResponseCache();
      final repo = McpNotesRepository(
        _FakeClient({
          'last_compaction': '2026-10-02T21:05:00-04:00',
          'latest_compacted_note': {
            'timestamp': '2026-10-02T20:30:00-04:00',
            'description': 'Done with dinner',
            'compaction_id': 'c1',
          },
        }),
        cache: cache,
      );
      expect(await repo.cachedCompactionStatus(), isNull);

      await repo.compactionStatus();
      final cached = await McpNotesRepository(
        _FakeClient(null),
        cache: cache,
      ).cachedCompactionStatus();
      expect(cached!.lastCompaction, DateTime.utc(2026, 10, 3, 1, 5));
      expect(cached.latestCompacted?.description, 'Done with dinner');
    });

    test('ignore a cached value they can\'t read', () async {
      final cache = InMemoryResponseCache();
      await cache.write('get_notes', 'not a list');
      await cache.write('get_compaction_status', 'not a map');
      final repo = McpNotesRepository(_FakeClient(null), cache: cache);
      expect(await repo.cachedUncompactedNotes(), isNull);
      expect(await repo.cachedCompactionStatus(), isNull);
    });
  });

  group('screens', () {
    final now = DateTime(2026, 9, 30, 12);
    Finder refreshing() => find.bySemanticsLabel('Refreshing');

    /// The app's memory as it opens, with the days [kept] from its last
    /// run, events from [repo], kept in [cache].
    Future<PlanMemory> keptMemory(
      EventsRepository repo,
      Map<DateTime, List<Event>> kept, {
      ResponseCache? cache,
    }) async {
      cache ??= InMemoryResponseCache();
      final last = EventStore(repository: repo, cache: cache, clock: () => now);
      for (final MapEntry(:key, :value) in kept.entries) {
        last.putDay(key, value);
      }
      await last.save();
      return PlanMemory(
        eventStore: EventStore(
          repository: repo,
          cache: cache,
          clock: () => now,
        ),
      );
    }

    testWidgets('Notes shows kept notes while it refreshes', (tester) async {
      final repo = _GatedNotesRepository(
        cached: [Note(timestamp: now, description: 'Old')],
        fresh: [Note(timestamp: now, description: 'New')],
      );
      final outbox = NoteOutbox(store: InMemoryOutboxStore(), repository: repo);
      await tester.pumpWidget(
        MaterialApp(
          home: NotesScreen(repository: repo, outbox: outbox),
        ),
      );
      await tester.pump();
      expect(find.text('Old'), findsOneWidget);
      expect(refreshing(), findsOneWidget);

      repo.gate.complete();
      await tester.pumpAndSettle();
      expect(find.text('New'), findsOneWidget);
      expect(find.text('Old'), findsNothing);
      expect(refreshing(), findsNothing);
      outbox.stop();
    });

    testWidgets('Events keeps kept events when the refresh fails', (
      tester,
    ) async {
      final day = DateTime(2026, 9, 30);
      final repo = _GatedEventsRepository();
      final memory = await keptMemory(repo, {
        day: [
          Event(
            start: DateTime(2026, 9, 30, 9),
            end: DateTime(2026, 9, 30, 10),
            summary: 'Old',
          ),
        ],
      });
      await tester.pumpWidget(
        MaterialApp(
          home: EventsScreen(
            repository: repo,
            serverLabel: 'test',
            memory: memory,
            clock: () => now,
          ),
        ),
      );
      await tester.pump();
      expect(find.text('Old'), findsOneWidget);
      expect(refreshing(), findsOneWidget);

      repo.gate.completeError(McpException('offline'));
      await tester.pumpAndSettle();
      expect(find.text('Old'), findsOneWidget);
      expect(
        find.textContaining('Could not load events. These may be out of date.'),
        findsOneWidget,
      );
      expect(refreshing(), findsNothing);
    });

    testWidgets('Events shows the spinner for a day with nothing kept', (
      tester,
    ) async {
      final repo = _GatedEventsRepository();
      await tester.pumpWidget(
        MaterialApp(
          home: EventsScreen(
            repository: repo,
            serverLabel: 'test',
            clock: () => now,
          ),
        ),
      );
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(refreshing(), findsNothing);
      repo.gate.complete();
      await tester.pumpAndSettle();
      // Nothing that day: its empty timeline.
      expect(find.text('No events.\nTap + to add one.'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('Events keeps each day it loads for next time', (tester) async {
      final cache = InMemoryResponseCache();
      final repo = _GatedEventsRepository();
      final memory = await keptMemory(repo, {}, cache: cache);
      await tester.pumpWidget(
        MaterialApp(
          home: EventsScreen(
            repository: repo,
            serverLabel: 'test',
            memory: memory,
            clock: () => now,
          ),
        ),
      );
      repo.gate.complete();
      await tester.pumpAndSettle();
      await memory.eventStore!.save();

      // The day shown, and those either side, ready to slide in.
      expect((await cache.read('event_days') as Map).keys, {
        '2026-09-29',
        '2026-09-30',
        '2026-10-01',
      });
    });

    test(
      'what two pages keep at once is kept, not lost to the other',
      () async {
        final memory = PlanMemory();
        final actions = _GatedActionsRepository(
          cached: const ActionList(
            actions: [PlanAction(id: '1', name: 'Old')],
          ),
        );
        // One page asks for what's kept of the actions, another not, at once.
        await Future.wait([
          memory.loadKept(),
          memory.loadKept(actions: actions),
        ]);
        expect(memory.actions?.actions.single.name, 'Old');
      },
    );

    testWidgets('Events shows when notes were last compacted from the '
        'Notes page, without asking again first', (tester) async {
      final memory = PlanMemory();
      final compacted = DateTime(2026, 9, 30, 9);
      final notes = InMemoryNotesRepository(
        [],
        CompactionStatus(lastCompaction: compacted),
      );
      final outbox = NoteOutbox(
        store: InMemoryOutboxStore(),
        repository: notes,
      );
      await tester.pumpWidget(
        MaterialApp(
          home: NotesScreen(repository: notes, outbox: outbox, memory: memory),
        ),
      );
      await tester.pumpAndSettle();
      expect(memory.lastCompaction, compacted);

      // The Events page, while the server's slow to say.
      final slow = _GatedNotesRepository(cached: const [], fresh: const []);
      await tester.pumpWidget(
        MaterialApp(
          home: EventsScreen(
            repository: InMemoryEventsRepository(),
            notesRepository: slow,
            serverLabel: 'test',
            memory: memory,
            clock: () => now,
          ),
        ),
      );
      await tester.pump();
      expect(
        tester.widget<DayTimeline>(find.byType(DayTimeline)).lastCompaction,
        compacted,
      );
      slow.gate.complete();
      await tester.pumpAndSettle();
      outbox.stop();
    });

    testWidgets('Plan asks to sign in, rather than show kept actions', (
      tester,
    ) async {
      final repo = _GatedActionsRepository(
        cached: const ActionList(
          actions: [PlanAction(id: '1', name: 'Old', path: 'Old')],
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: PlanScreen(
            outbox: _idleActionOutbox(),
            repository: repo,
            serverLabel: 'test',
          ),
        ),
      );
      await tester.pump();
      expect(find.text('Old'), findsOneWidget);
      expect(refreshing(), findsOneWidget);

      repo.gate.completeError(SignInRequiredException());
      await tester.pumpAndSettle();
      expect(find.text('Old'), findsNothing);
      expect(find.text('Sign in to see your plan.'), findsOneWidget);
      expect(refreshing(), findsNothing);
    });

    testWidgets('Notes shows the kept compaction status while it refreshes', (
      tester,
    ) async {
      final repo = _GatedNotesRepository(
        cached: [],
        fresh: [],
        cachedStatus: CompactionStatus(
          lastCompaction: DateTime(2026, 9, 30, 7, 30),
          latestCompacted: Note(
            timestamp: DateTime(2026, 9, 29, 22, 40),
            description: 'Lights out',
            compactionId: 'c1',
          ),
        ),
        freshStatus: CompactionStatus(
          lastCompaction: DateTime(2026, 9, 30, 11, 0),
          latestCompacted: Note(
            timestamp: DateTime(2026, 9, 30, 10, 0),
            description: 'Coffee',
            compactionId: 'c2',
          ),
        ),
      );
      final outbox = NoteOutbox(store: InMemoryOutboxStore(), repository: repo);
      await tester.pumpWidget(
        MaterialApp(
          home: NotesScreen(repository: repo, outbox: outbox),
        ),
      );
      await tester.pump();
      expect(find.text('Lights out'), findsOneWidget);
      expect(find.text('Last compacted Sep 30, 2026, 7:30 AM'), findsOneWidget);

      repo.gate.complete();
      await tester.pumpAndSettle();
      expect(find.text('Coffee'), findsOneWidget);
      expect(find.text('Lights out'), findsNothing);
    });
  });
}

/// Answers every tool call with [result].
class _FakeClient extends McpClient {
  _FakeClient(this.result) : super(endpoint: Uri.parse('http://test'));

  final Object? result;

  @override
  Future<Object?> callTool(
    String name, [
    Map<String, Object?> arguments = const {},
  ]) async => result;
}

/// Has [cached] notes and [cachedStatus] kept, and answers with [fresh]
/// and [freshStatus] once [gate] opens.
class _GatedNotesRepository extends InMemoryNotesRepository {
  _GatedNotesRepository({
    required this.cached,
    required List<Note> fresh,
    this.cachedStatus,
    CompactionStatus freshStatus = const CompactionStatus(),
  }) : super(fresh, freshStatus);

  final List<Note> cached;
  final CompactionStatus? cachedStatus;
  final gate = Completer<void>();

  @override
  Future<List<Note>?> cachedUncompactedNotes() async => cached;

  @override
  Future<CompactionStatus?> cachedCompactionStatus() async => cachedStatus;

  @override
  Future<CompactionStatus> compactionStatus() async {
    await gate.future;
    return super.compactionStatus();
  }

  @override
  Future<List<Note>> uncompactedNotes() async {
    await gate.future;
    return super.uncompactedNotes();
  }
}

/// Answers once [gate] opens.
class _GatedEventsRepository extends InMemoryEventsRepository {
  final gate = Completer<void>();

  @override
  Future<List<Event>> events(DateTime from, DateTime to) async {
    await gate.future;
    return super.events(from, to);
  }
}

/// Has [cached] actions kept, and answers once [gate] opens.
class _GatedActionsRepository extends InMemoryActionsRepository {
  _GatedActionsRepository({required this.cached});

  final ActionList cached;
  final gate = Completer<void>();

  @override
  Future<ActionList?> cachedActions() async => cached;

  @override
  Future<ActionList> actions() async {
    await gate.future;
    return super.actions();
  }
}

/// For a Actions page that saves nothing.
ActionOutbox _idleActionOutbox() => ActionOutbox(
  store: InMemoryOutboxStore(),
  repository: InMemoryActionsRepository(),
);
