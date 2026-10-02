import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:time_tracker_client/models/event.dart';
import 'package:time_tracker_client/models/event_label.dart';
import 'package:time_tracker_client/models/note.dart';
import 'package:time_tracker_client/outbox/note_outbox.dart';
import 'package:time_tracker_client/outbox/outbox_store.dart';
import 'package:time_tracker_client/screens/event_labels_screen.dart';
import 'package:time_tracker_client/screens/events_screen.dart';
import 'package:time_tracker_client/screens/notes_screen.dart';
import 'package:time_tracker_client/services/event_labels_repository.dart';
import 'package:time_tracker_client/services/events_repository.dart';
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

    test('keep list_events only when asked, for one day', () async {
      final cache = InMemoryResponseCache();
      final day = DateTime(2026, 9, 30);
      final next = DateTime(2026, 10, 1);
      final event = Event(
        start: DateTime(2026, 9, 30, 9),
        end: DateTime(2026, 9, 30, 10),
        summary: 'Work',
      );
      final repo = McpEventsRepository(
        _FakeClient([event.toJson()]),
        cache: cache,
      );
      await repo.events(day, next);
      expect(await repo.cachedEvents(day, next), isNull);

      await repo.events(day, next, keep: true);
      expect((await repo.cachedEvents(day, next))!.single.summary, 'Work');
      // Another day isn't kept, and doesn't replace the one that is.
      await repo.events(next, DateTime(2026, 10, 2));
      expect(await repo.cachedEvents(next, DateTime(2026, 10, 2)), isNull);
      expect(await repo.cachedEvents(day, next), isNotNull);
    });

    test('keep the labels a save returns', () async {
      final cache = InMemoryResponseCache();
      final repo = McpEventLabelsRepository(
        _FakeClient([
          {'id': '1', 'name': 'Sleep'},
        ]),
        cache: cache,
      );
      await repo.updateLabel(const EventLabel(id: '1'), {'name': 'Sleep'});
      expect((await repo.cachedLabels())!.single.name, 'Sleep');
    });

    test('ignore a cached value they can\'t read', () async {
      final cache = InMemoryResponseCache();
      await cache.write('get_notes', 'not a list');
      final repo = McpNotesRepository(_FakeClient(null), cache: cache);
      expect(await repo.cachedUncompactedNotes(), isNull);
    });
  });

  group('screens', () {
    final now = DateTime(2026, 9, 30, 12);
    Finder refreshing() => find.bySemanticsLabel('Refreshing');

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
      final repo = _GatedEventsRepository(
        cached: {
          day: [
            Event(
              start: DateTime(2026, 9, 30, 9),
              end: DateTime(2026, 9, 30, 10),
              summary: 'Old',
            ),
          ],
        },
      );
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
      final repo = _GatedEventsRepository(cached: {});
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
      expect(find.text('No events.'), findsOneWidget);
    });

    testWidgets('Events shows kept events only for the first day', (
      tester,
    ) async {
      final day = DateTime(2026, 9, 30);
      final kept = [
        Event(
          start: DateTime(2026, 9, 30, 9),
          end: DateTime(2026, 9, 30, 10),
          summary: 'Old',
        ),
      ];
      final repo = _GatedEventsRepository(
        cached: {day: kept, DateTime(2026, 10, 1): kept},
      );
      await tester.pumpWidget(
        MaterialApp(
          home: EventsScreen(
            repository: repo,
            serverLabel: 'test',
            clock: () => now,
          ),
        ),
      );
      repo.gate.complete();
      await tester.pumpAndSettle();
      expect(repo.kept, [day]);

      await tester.tap(find.byTooltip('Next day'));
      await tester.pump();
      expect(find.text('Old'), findsNothing);
      await tester.pumpAndSettle();
      expect(repo.kept, [day]);
    });

    testWidgets('Labels asks to sign in, rather than show kept labels', (
      tester,
    ) async {
      final repo = _GatedLabelsRepository(
        cached: [const EventLabel(id: '1', name: 'Old')],
      );
      await tester.pumpWidget(
        MaterialApp(
          home: EventLabelsScreen(repository: repo, serverLabel: 'test'),
        ),
      );
      await tester.pump();
      expect(find.text('Old'), findsOneWidget);
      expect(refreshing(), findsOneWidget);

      repo.gate.completeError(SignInRequiredException());
      await tester.pumpAndSettle();
      expect(find.text('Old'), findsNothing);
      expect(find.text('Sign in to see your event labels.'), findsOneWidget);
      expect(refreshing(), findsNothing);
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

/// Has [cached] notes kept, and answers with [fresh] once [gate] opens.
class _GatedNotesRepository extends InMemoryNotesRepository {
  _GatedNotesRepository({required this.cached, required List<Note> fresh})
    : super(fresh);

  final List<Note> cached;
  final gate = Completer<void>();

  @override
  Future<List<Note>?> cachedUncompactedNotes() async => cached;

  @override
  Future<List<Note>> uncompactedNotes() async {
    await gate.future;
    return super.uncompactedNotes();
  }
}

/// Has [cached] events kept, by day, and answers once [gate] opens.
class _GatedEventsRepository extends InMemoryEventsRepository {
  _GatedEventsRepository({required this.cached});

  final Map<DateTime, List<Event>> cached;
  final gate = Completer<void>();

  @override
  Future<List<Event>?> cachedEvents(DateTime from, DateTime to) async =>
      cached[from];

  /// The days [events] was asked to keep.
  final kept = <DateTime>[];

  @override
  Future<List<Event>> events(
    DateTime from,
    DateTime to, {
    bool keep = false,
  }) async {
    await gate.future;
    if (keep) kept.add(from);
    return super.events(from, to);
  }
}

/// Has [cached] labels kept, and answers once [gate] opens.
class _GatedLabelsRepository extends InMemoryEventLabelsRepository {
  _GatedLabelsRepository({required this.cached});

  final List<EventLabel> cached;
  final gate = Completer<void>();

  @override
  Future<List<EventLabel>?> cachedLabels() async => cached;

  @override
  Future<List<EventLabel>> labels() async {
    await gate.future;
    return super.labels();
  }
}
