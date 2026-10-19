import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:time_tracker_client/models/server_health.dart';
import 'package:time_tracker_client/screens/sheet_warnings_screen.dart';
import 'package:time_tracker_client/services/diagnostics_repository.dart';
import 'package:time_tracker_client/services/mcp_client.dart';
import 'package:time_tracker_client/services/server_client.dart';
import 'package:time_tracker_client/services/sheet_warnings.dart';
import 'package:time_tracker_client/widgets/sheet_warnings_banner.dart';

final _now = DateTime.utc(2026, 10, 18, 12);

/// The flag, as the server sends it: two warnings, the last 3 hours ago.
const _flag = {'recent': 2, 'latest': '2026-10-18T09:00:00.000Z'};

/// The flag with no time said.
const _said = SheetWarningsFlag(recent: 2);

/// A server that answers the handshake with [handshake] and each tool
/// call with the next of [results] (the last, once they run out); [calls]
/// gets each tool call's name and arguments. With [toolStatus], each tool
/// call fails with that HTTP status instead.
MockClient _server({
  int? toolStatus,
  Map<String, Object?> handshake = const {'protocolVersion': '2025-06-18'},
  List<Map<String, Object?>> results = const [
    {
      'content': [
        {'type': 'text', 'text': '[]'},
      ],
    },
  ],
  List<(String, Object?)>? calls,
}) {
  var next = 0;
  return MockClient((request) async {
    final body = jsonDecode(request.body) as Map<String, dynamic>;
    if (body['method'] == 'notifications/initialized') {
      return http.Response('', 202);
    }
    final Object? result;
    if (body['method'] == 'initialize') {
      result = handshake;
    } else if (toolStatus != null) {
      return http.Response('', toolStatus);
    } else {
      final params = body['params'] as Map;
      calls?.add((params['name'] as String, params['arguments']));
      result = results[next < results.length ? next++ : results.length - 1];
    }
    return http.Response(
      jsonEncode({'jsonrpc': '2.0', 'id': body['id'], 'result': result}),
      200,
      headers: {'content-type': 'application/json', 'mcp-session-id': 's'},
    );
  });
}

Map<String, Object?> _result({
  Map<String, Object?>? flag,
  bool error = false,
}) => {
  'content': [
    {'type': 'text', 'text': error ? 'no such goal' : '[]'},
  ],
  'isError': ?(error ? true : null),
  if (flag != null) '_meta': {sheetWarningsMetaKey: flag},
};

/// get_health's answer with `samples: false`, as the server gives it.
const _health = {
  'tools': [
    {'tool': 'get_notes', 'count': 3, 'errors': 0},
  ],
  'restarts': ['2026-10-17T09:00:00.000Z'],
  'auth': 'oauth',
  'sheet_warnings': [
    {
      'at': '2026-10-16T12:00:00.000Z',
      'kind': 'edited',
      'tab': 'People',
      'cells': [
        {'cell': 'B2', 'found': 'p-2 renamed', 'kept': 'p-2'},
        {'cell': 'C2', 'found': '', 'kept': 'x'},
      ],
      'cell_count': 25,
      'restored': true,
    },
    {
      'at': '2026-10-17T12:00:00.000Z',
      'kind': 'deleted',
      'tab': 'Locations',
      'cells': <Object>[],
      'cell_count': 0,
      'restored': true,
    },
    {
      'at': '2026-10-18T09:00:00.000Z',
      'kind': 'calendar',
      'tab': null,
      'cells': [
        {'cell': 'ev1', 'found': 'Lunch (cancelled)', 'kept': ''},
      ],
      'cell_count': 1,
      'restored': false,
    },
  ],
};

void main() {
  tearDown(() => serverSheetWarnings.value = null);

  group('the flag', () {
    test('is read from a result\'s _meta', () {
      expect(
        SheetWarningsFlag.of({
          '_meta': {sheetWarningsMetaKey: _flag},
        }),
        SheetWarningsFlag(recent: 2, latest: DateTime.utc(2026, 10, 18, 9)),
      );
      expect(SheetWarningsFlag.of({}), isNull);
      expect(
        SheetWarningsFlag.of({
          '_meta': {'time-tracking/authDisabled': true},
        }),
        isNull,
      );
      expect(
        SheetWarningsFlag.of({
          '_meta': {sheetWarningsMetaKey: 'yes'},
        }),
        isNull,
      );
      expect(
        SheetWarningsFlag.of({
          '_meta': {
            sheetWarningsMetaKey: {'recent': 0},
          },
        }),
        isNull,
      );
    });

    test('comes with the handshake', () async {
      final client = serverClient(
        Uri.parse('https://example.com/mcp'),
        httpClient: _server(
          handshake: {
            'protocolVersion': '2025-06-18',
            '_meta': {sheetWarningsMetaKey: _flag},
          },
          // No tool result to say otherwise.
          toolStatus: 403,
        ),
      );

      await expectLater(
        client.callTool('get_notes'),
        throwsA(isA<McpException>()),
      );

      expect(serverSheetWarnings.value?.recent, 2);
      expect(serverSheetWarnings.value?.latest, DateTime.utc(2026, 10, 18, 9));
    });

    test(
      'is kept up to date by each tool result, the latest winning',
      () async {
        final seen = ValueNotifier<SheetWarningsFlag?>(null);
        final client = McpClient(
          endpoint: Uri.parse('https://example.com/mcp'),
          serverSheetWarnings: seen,
          httpClient: _server(
            results: [
              _result(flag: _flag),
              _result(flag: {'recent': 3, 'latest': '2026-10-18T11:00:00Z'}),
              _result(),
              // A tool's error carries it too.
              _result(flag: _flag, error: true),
            ],
          ),
        );

        // Connecting said nothing.
        await client.callTool('get_notes');
        expect(seen.value?.recent, 2);

        await client.callTool('get_notes');
        expect(seen.value?.recent, 3);
        expect(seen.value?.latest, DateTime.utc(2026, 10, 18, 11));

        await client.callTool('get_notes');
        expect(seen.value, isNull);

        await expectLater(
          client.callTool('get_goal', {'goal_id': 'g'}),
          throwsA(isA<McpException>()),
        );
        expect(seen.value?.recent, 2);
      },
    );
  });

  group('the banner', () {
    testWidgets(
      "the app's client turns it on, above every screen, and off again",
      (tester) async {
        final client = serverClient(
          Uri.parse('https://example.com/mcp'),
          httpClient: _server(
            results: [
              _result(flag: _flag),
              _result(),
            ],
          ),
        );
        await tester.pumpWidget(
          MaterialApp(
            builder: (context, child) =>
                SheetWarningsBanner(clock: () => _now, child: child!),
            home: const Scaffold(body: Text('Events')),
          ),
        );
        expect(find.byIcon(Icons.edit_note), findsNothing);

        await tester.runAsync(() => client.callTool('get_notes'));
        await tester.pump();

        expect(
          find.text(
            'The metadata spreadsheet or calendar was changed outside the '
            'server 2 times this week (last 3 hours ago)',
          ),
          findsOneWidget,
        );
        expect(
          tester.getTopLeft(find.byIcon(Icons.edit_note)).dy,
          lessThan(tester.getTopLeft(find.text('Events')).dy),
        );

        await tester.runAsync(() => client.callTool('get_notes'));
        await tester.pump();

        expect(find.byIcon(Icons.edit_note), findsNothing);
        expect(find.text('Events'), findsOneWidget);
      },
    );

    test('says how many times, and how long ago', () {
      expect(
        SheetWarningsBanner.text(
          SheetWarningsFlag(recent: 1, latest: _now),
          _now.add(const Duration(seconds: 20)),
        ),
        'The metadata spreadsheet or calendar was changed outside the '
        'server once this week (last just now)',
      );
      expect(
        SheetWarningsBanner.text(_said, _now),
        'The metadata spreadsheet or calendar was changed outside the '
        'server 2 times this week',
      );
      expect(
        SheetWarningsBanner.ago(const Duration(minutes: 1)),
        '1 minute ago',
      );
      expect(
        SheetWarningsBanner.ago(const Duration(hours: 23)),
        '23 hours ago',
      );
      expect(SheetWarningsBanner.ago(const Duration(days: 6)), '6 days ago');
    });

    testWidgets('tapped, opens what the changes were', (tester) async {
      final calls = <(String, Object?)>[];
      final client = McpClient(
        endpoint: Uri.parse('https://example.com/mcp'),
        httpClient: _server(
          results: [
            {
              'content': [
                {'type': 'text', 'text': jsonEncode(_health)},
              ],
            },
          ],
          calls: calls,
        ),
      );
      final navigator = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: navigator,
          builder: (context, child) => SheetWarningsBanner(
            warnings: ValueNotifier(_said),
            clock: () => _now,
            onOpen: () => navigator.currentState!.push(
              MaterialPageRoute<void>(
                builder: (_) => SheetWarningsScreen(
                  repository: McpDiagnosticsRepository(client),
                  clock: () => _now,
                ),
              ),
            ),
            child: child!,
          ),
          home: const Scaffold(body: Text('Events')),
        ),
      );

      await tester.tap(find.byIcon(Icons.edit_note));
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pumpAndSettle();

      expect(calls, hasLength(1));
      expect(calls.single.$1, 'get_health');
      expect(calls.single.$2, {'samples': false});
      expect(find.text(SheetWarningsScreen.explanation), findsOneWidget);
      expect(find.text('Cells edited by hand'), findsOneWidget);
    });
  });

  group('dismissing', () {
    final flag = SheetWarningsFlag(
      recent: 2,
      latest: DateTime.utc(2026, 10, 18, 9),
    );

    Future<SheetWarningsDismissal> show(
      WidgetTester tester,
      ValueNotifier<SheetWarningsFlag?> warnings,
    ) async {
      final dismissal = SheetWarningsDismissal(persist: false);
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => SheetWarningsBanner(
            warnings: warnings,
            dismissal: dismissal,
            clock: () => _now,
            onOpen: () {},
            child: child!,
          ),
          home: const Scaffold(body: Text('Events')),
        ),
      );
      return dismissal;
    }

    testWidgets('hides the strip, until a later warning', (tester) async {
      final warnings = ValueNotifier<SheetWarningsFlag?>(flag);
      await show(tester, warnings);
      expect(find.byIcon(Icons.edit_note), findsOneWidget);

      await tester.tap(find.byIcon(Icons.close));
      await tester.pump();
      expect(find.byIcon(Icons.edit_note), findsNothing);
      expect(find.text('Events'), findsOneWidget);

      // The server still says of the same week's warnings.
      warnings.value = SheetWarningsFlag(recent: 2, latest: flag.latest);
      await tester.pump();
      expect(find.byIcon(Icons.edit_note), findsNothing);

      warnings.value = SheetWarningsFlag(
        recent: 3,
        latest: DateTime.utc(2026, 10, 18, 11),
      );
      await tester.pump();
      expect(find.byIcon(Icons.edit_note), findsOneWidget);
    });

    testWidgets('one with no time said, only as it was', (tester) async {
      final warnings = ValueNotifier<SheetWarningsFlag?>(_said);
      await show(tester, warnings);

      await tester.tap(find.byIcon(Icons.close));
      await tester.pump();
      expect(find.byIcon(Icons.edit_note), findsNothing);

      warnings.value = const SheetWarningsFlag(recent: 3);
      await tester.pump();
      expect(find.byIcon(Icons.edit_note), findsOneWidget);
    });

    test('keeps the latest dismissed', () {
      final dismissal = SheetWarningsDismissal(persist: false)
        ..dismiss(flag)
        ..dismiss(SheetWarningsFlag(recent: 1, latest: DateTime.utc(2026)));
      expect(dismissal.hides(flag), isTrue);
      expect(
        dismissal.hides(
          SheetWarningsFlag(recent: 3, latest: DateTime.utc(2026, 10, 19)),
        ),
        isFalse,
      );
    });
  });

  group('the details', () {
    Future<void> show(WidgetTester tester, DiagnosticsRepository repo) async {
      await tester.pumpWidget(
        MaterialApp(
          home: SheetWarningsScreen(repository: repo, clock: () => _now),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('lists each warning, newest first, with its cells', (
      tester,
    ) async {
      final health = ServerHealth.fromJson(_health);
      await show(tester, InMemoryDiagnosticsRepository(health));

      final calendar = tester.getTopLeft(
        find.text('Events changed outside the server'),
      );
      final deleted = tester.getTopLeft(find.text('Tab deleted by hand'));
      final edited = tester.getTopLeft(find.text('Cells edited by hand'));
      expect(calendar.dy, lessThan(deleted.dy));
      expect(deleted.dy, lessThan(edited.dy));

      expect(find.text('Tab "People" · 25 cells · put back'), findsOneWidget);
      expect(find.text('B2: "p-2 renamed" → "p-2"'), findsOneWidget);
      expect(find.text('C2: (empty) → "x"'), findsOneWidget);
      expect(find.text('and 23 more'), findsOneWidget);
      expect(find.text('Tab "Locations" · put back'), findsOneWidget);
      expect(find.text('1 event · taken as changed'), findsOneWidget);
      expect(find.text('Lunch (cancelled) -- ev1'), findsOneWidget);
      expect(find.textContaining('(3 hours ago)'), findsOneWidget);
      expect(find.textContaining('(2 days ago)'), findsOneWidget);
    });

    testWidgets('says when there are none', (tester) async {
      await show(tester, InMemoryDiagnosticsRepository());

      expect(find.text(SheetWarningsScreen.explanation), findsOneWidget);
      expect(
        find.text('Nothing has been changed outside the server lately.'),
        findsOneWidget,
      );
    });

    testWidgets('says when they could not be loaded', (tester) async {
      await show(tester, _Failing());

      expect(find.textContaining("Couldn't load"), findsOneWidget);
    });
  });
}

class _Failing extends InMemoryDiagnosticsRepository {
  @override
  Future<List<SheetWarning>> sheetWarnings() async =>
      throw McpException('get_health: HTTP 500');
}
