import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:time_tracker_client/models/server_health.dart';
import 'package:time_tracker_client/screens/diagnostics_screen.dart';
import 'package:time_tracker_client/services/client_health.dart';
import 'package:time_tracker_client/services/diagnostics_repository.dart';
import 'package:time_tracker_client/services/mcp_client.dart';
import 'package:time_tracker_client/services/work_timing.dart';

final _now = DateTime.utc(2026, 10, 9, 12);

/// Keeps the thread busy for [ms].
void _busy(int ms) {
  final watch = Stopwatch()..start();
  while (watch.elapsedMilliseconds < ms) {}
}

/// A clock that moves on a second each time it's read.
DateTime Function() _ticking([DateTime? from]) {
  var t = from ?? _now.subtract(const Duration(hours: 1));
  return () => t = t.add(const Duration(seconds: 1));
}

ClientHealthRecorder _recorder({
  CallOrigin origin = CallOrigin.app,
  ClientHealthStore? store,
}) => ClientHealthRecorder(
  origin: origin,
  store: store ?? InMemoryClientHealthStore(),
  clock: _ticking(),
  flushDelay: const Duration(hours: 1),
);

/// A server whose every tool call [respond]s.
http.Client _server(Map<String, Object?> Function(String tool) respond) =>
    MockClient((request) async {
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      return switch (body['method']) {
        'initialize' => http.Response(
          jsonEncode({
            'jsonrpc': '2.0',
            'id': body['id'],
            'result': {'protocolVersion': '2025-06-18'},
          }),
          200,
          headers: {'content-type': 'application/json'},
        ),
        'notifications/initialized' => http.Response('', 202),
        _ => http.Response(
          jsonEncode({
            'jsonrpc': '2.0',
            'id': body['id'],
            'result': respond(body['params']['name'] as String),
          }),
          200,
          headers: {'content-type': 'application/json'},
        ),
      };
    });

void main() {
  group('The recorder', () {
    test('records each call, keeping each tool\'s last hundred', () async {
      final recorder = _recorder();

      for (var i = 0; i < 120; i++) {
        recorder.recordCall(i.isEven ? 'get_notes' : 'note', i);
      }
      await recorder.flush();

      final kept = await recorder.store.read();
      expect(kept.calls['get_notes'], hasLength(60));
      expect(kept.calls['note'], hasLength(60));
      for (var i = 0; i < 60; i++) {
        recorder.recordCall('note', 1000 + i);
      }
      final health = await recorder.read();
      expect(health.calls['note'], hasLength(ClientHealthRecorder.keepCalls));
      expect(health.calls['note']!.last.ms, 1059);
    });

    test('records a failed call as an error too, in full', () async {
      final recorder = _recorder();

      recorder.recordCall(
        'update_event',
        900,
        error: McpException(
          'Tool update_event failed: overlap',
          serverMessage: 'it would overlap “Call Mom”',
        ),
      );
      final health = await recorder.read();

      expect(health.calls['update_event']!.single.ok, isFalse);
      final error = health.errors.single;
      expect(error.tool, 'update_event');
      expect(error.kind, 'McpException');
      expect(error.message, contains('it would overlap “Call Mom”'));
      expect(error.origin, CallOrigin.app);
    });

    test(
      'keeps the last twenty errors, and an uncaught one\'s stack',
      () async {
        final recorder = _recorder();

        for (var i = 0; i < 25; i++) {
          recorder.recordError(StateError('$i'));
        }
        recorder.recordError(StateError('last'), stack: StackTrace.current);
        final errors = (await recorder.read()).errors;

        expect(errors, hasLength(ClientHealthRecorder.keepErrors));
        expect(errors.last.message, 'Bad state: last');
        expect(errors.last.tool, isNull);
        expect(errors.last.stack, contains('client_health_test'));
      },
    );

    test('records the queues only as they change', () async {
      final recorder = _recorder();

      recorder.recordQueue(notes: 1);
      recorder.recordQueue(notes: 1);
      recorder.recordQueue(notes: 1, events: 2);
      recorder.recordQueue();

      final queue = (await recorder.read()).queue;
      expect([for (final q in queue) q.total], [1, 3, 0]);
    });

    test('the app\'s and the background task\'s both keep theirs', () async {
      final store = InMemoryClientHealthStore();
      final app = _recorder(store: store);
      final background = _recorder(store: store, origin: CallOrigin.background);

      app.recordCall('get_notes', 10);
      background.recordCall('note', 20);
      await background.flush();
      await app.flush();

      final calls = store.kept.calls;
      expect(calls['get_notes']!.single.origin, CallOrigin.app);
      expect(calls['note']!.single.origin, CallOrigin.background);
    });

    test('kept on the device, reads back as recorded', () async {
      SharedPreferencesAsyncPlatform.instance =
          InMemorySharedPreferencesAsync.empty();
      final recorder = _recorder(store: PrefsClientHealthStore());
      recorder.recordCall('note', 42, error: StateError('offline'));
      recorder.recordQueue(actions: 2);
      await recorder.flush();

      final kept = await PrefsClientHealthStore().read();

      expect(kept.calls['note']!.single.ms, 42);
      expect(kept.errors.single.message, 'Bad state: offline');
      expect(kept.queue.single.actions, 2);
    });

    test('keeps work, slow frames and visits to Plan, each to its '
        'latest', () async {
      SharedPreferencesAsyncPlatform.instance =
          InMemorySharedPreferencesAsync.empty();
      final recorder = _recorder(store: PrefsClientHealthStore());
      for (var i = 0; i < ClientHealthRecorder.keepWork + 5; i++) {
        recorder.recordWork(WorkKind.actionTime, i);
      }
      recorder.recordWork(WorkKind.traitScores, 150000, why: 'people');
      recorder.recordFrame(
        SlowFrame(at: _now, us: 40000, buildUs: 30000, plan: true),
      );
      recorder.recordVisit(
        PlanVisit(
          at: _now,
          us: 900000,
          work: {WorkKind.traitScores: 150000, WorkKind.planRebuild: 50000},
        ),
      );
      await recorder.flush();

      final kept = await PrefsClientHealthStore().read();

      final times = kept.work[WorkKind.actionTime]!;
      expect(times, hasLength(ClientHealthRecorder.keepWork));
      expect(times.first.us, 5);
      expect(kept.work[WorkKind.traitScores]!.single.why, 'people');
      expect(kept.frames.single.ms, 40);
      expect(kept.frames.single.plan, isTrue);
      final visit = kept.visits.single;
      expect(visit.msOf(WorkKind.traitScores), 150);
      expect(visit.waitingMs, 700);
    });
  });

  group('Timing work', () {
    late ClientHealthRecorder recorder;
    setUp(() {
      recorder = _recorder();
      workRecorder = recorder;
    });
    tearDown(() => workRecorder = null);

    test("records each run, and gives a visit each kind's own time, none "
        'of it twice', () async {
      final visit = PlanVisitTimer.start();
      final result = timed(WorkKind.planRebuild, () {
        // Inside the rebuild: its time is the scores', not the rebuild's.
        timed(WorkKind.traitScores, () => _busy(20), why: () => 'first');
        _busy(5);
        return 'built';
      });
      visit.finish();
      visit.finish(); // Once only.
      await recorder.flush();
      final kept = await recorder.read();

      expect(result, 'built');
      final scores = kept.work[WorkKind.traitScores]!.single;
      final rebuild = kept.work[WorkKind.planRebuild]!.single;
      expect(scores.why, 'first');
      expect(scores.ms, greaterThanOrEqualTo(20));
      // Whole, with the scores in it.
      expect(rebuild.us, greaterThanOrEqualTo(scores.us));
      final v = kept.visits.single;
      expect(v.work[WorkKind.traitScores], scores.us);
      expect(v.work[WorkKind.planRebuild], rebuild.us - scores.us);
      expect(v.us, greaterThanOrEqualTo(rebuild.us));
    });
  });

  group('McpClient', () {
    test('records each tool call: how long, and whether it failed', () async {
      final recorder = _recorder();
      final client = McpClient(
        endpoint: Uri.parse('https://example.com/mcp'),
        httpClient: _server(
          (tool) => tool == 'note'
              ? {
                  'isError': true,
                  'content': [
                    {'type': 'text', 'text': 'no room'},
                  ],
                }
              : {
                  'structuredContent': {'result': []},
                },
        ),
        health: recorder,
      );

      await client.callTool('get_notes');
      await expectLater(client.callTool('note'), throwsA(isA<McpException>()));

      final health = await recorder.read();
      expect(health.calls['get_notes']!.single.ok, isTrue);
      expect(health.calls['note']!.single.ok, isFalse);
      expect(health.errors.single.message, contains('no room'));
    });
  });

  group('The App pane', () {
    ClientHealth health() => ClientHealth(
      calls: {
        'get_notes': [
          ClientCall(
            tool: 'get_notes',
            at: _now.subtract(const Duration(hours: 3)),
            ms: 200,
          ),
          ClientCall(
            tool: 'get_notes',
            at: _now.subtract(const Duration(hours: 2)),
            ms: 400,
          ),
        ],
        'note': [
          ClientCall(
            tool: 'note',
            at: _now.subtract(const Duration(hours: 1)),
            ms: 900,
            ok: false,
            origin: CallOrigin.background,
          ),
        ],
      },
      errors: [
        ClientError(
          at: _now.subtract(const Duration(hours: 1)),
          origin: CallOrigin.background,
          tool: 'note',
          kind: 'TimeoutException',
          message: 'TimeoutException after 0:00:30.000000\nall of it',
        ),
      ],
      queue: [
        QueueSample(at: _now.subtract(const Duration(hours: 4)), notes: 2),
        QueueSample(at: _now.subtract(const Duration(hours: 3))),
      ],
      work: {
        WorkKind.traitScores: [
          WorkSample(
            kind: WorkKind.traitScores,
            at: _now.subtract(const Duration(hours: 2)),
            us: 120000,
            why: 'first',
          ),
          WorkSample(
            kind: WorkKind.traitScores,
            at: _now.subtract(const Duration(hours: 2)),
            us: 140000,
            why: 'people, events',
          ),
        ],
      },
      frames: [
        SlowFrame(
          at: _now.subtract(const Duration(hours: 2)),
          us: 150000,
          plan: true,
        ),
      ],
      visits: [
        PlanVisit(
          at: _now.subtract(const Duration(hours: 2)),
          us: 800000,
          work: {WorkKind.traitScores: 260000},
        ),
      ],
    );

    Future<ClientHealthRecorder> open(WidgetTester tester) async {
      tester.view.physicalSize = const Size(900, 2600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final client = ClientHealthRecorder(
        origin: CallOrigin.app,
        store: InMemoryClientHealthStore(health()),
        flushDelay: const Duration(hours: 1),
        clock: () => _now,
      );
      await tester.pumpWidget(
        MaterialApp(
          home: DiagnosticsScreen(
            repository: InMemoryDiagnosticsRepository(const ServerHealth()),
            client: client,
            clock: () => _now,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('App'));
      await tester.pumpAndSettle();
      return client;
    }

    testWidgets("shows the app's and the background task's calls, the "
        'queues, and the errors', (tester) async {
      await open(tester);

      expect(
        find.text(
          '3 calls in view, 1 failed: the whole call, retries '
          'and the network included',
        ),
        findsOneWidget,
      );
      expect(find.text('The background task'), findsWidgets);
      expect(find.text('Waiting to save'), findsOneWidget);
      expect(find.text('Errors'), findsOneWidget);
      expect(find.textContaining('note'), findsWidgets);
    });

    testWidgets("shows the app's slow frames, visits to Plan, and work, "
        'with why the scores were worked out again', (tester) async {
      await open(tester);

      expect(find.textContaining('1 frame in view over 17 ms'), findsOneWidget);
      // The App pane's list, not the panes'.
      await tester.scrollUntilVisible(
        find.text('Work on the device'),
        300,
        scrollable: find
            .descendant(
              of: find.byType(ListView),
              matching: find.byType(Scrollable),
            )
            .last,
      );
      expect(find.textContaining('1 visit in view'), findsOneWidget);
      expect(
        find.text(
          'Trait scores were worked out again for: first ×1, people ×1, '
          'events ×1',
        ),
        findsOneWidget,
      );
    });

    testWidgets('filters to reads', (tester) async {
      await open(tester);

      await tester.tap(find.text('All tools'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Reads').last);
      await tester.pumpAndSettle();

      expect(
        find.textContaining('2 calls in view: the whole call'),
        findsOneWidget,
      );
      // The write's error is filtered out with it.
      expect(
        find.text('None of the 1 kept are of these tools.'),
        findsOneWidget,
      );
      expect(find.textContaining('TimeoutException'), findsNothing);
    });

    testWidgets('opens an error in full, to copy', (tester) async {
      String? copied;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copied = (call.arguments as Map)['text'] as String;
          }
          return null;
        },
      );
      await open(tester);

      // On a page of their own.
      await tester.ensureVisible(find.text('See it in full'));
      await tester.tap(find.text('See it in full'));
      await tester.pumpAndSettle();
      expect(find.text('Errors (1)'), findsOneWidget);
      await tester.tap(find.textContaining('TimeoutException').first);
      await tester.pumpAndSettle();
      expect(find.textContaining('all of it'), findsOneWidget);
      await tester.tap(find.text('Copy'));
      await tester.pumpAndSettle();

      expect(copied, contains('all of it'));
      expect(copied, contains('background note TimeoutException'));
    });

    testWidgets("doesn't record frames while it's open: its own graphs' "
        'drawing would be, on and on', (tester) async {
      expect(framesPaused, 0);
      await open(tester);
      expect(framesPaused, 1);
      await tester.pumpWidget(const SizedBox());
      expect(framesPaused, 0);
    });

    testWidgets('shows what it records as it records it', (tester) async {
      final client = await open(tester);

      client.recordCall('get_notes', 50);
      await tester.pumpAndSettle();

      expect(find.textContaining('4 calls in view'), findsOneWidget);
      await client.flush();
    });
  });
}
