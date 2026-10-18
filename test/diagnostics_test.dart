import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:time_tracker_client/models/server_health.dart';
import 'package:time_tracker_client/screens/diagnostics_screen.dart';
import 'package:time_tracker_client/services/diagnostics.dart';
import 'package:time_tracker_client/services/diagnostics_repository.dart';
import 'package:time_tracker_client/services/mcp_client.dart';
import 'package:time_tracker_client/services/response_cache.dart';
import 'package:time_tracker_client/widgets/app_menu.dart';
import 'package:time_tracker_client/widgets/hotkeys.dart';

final _now = DateTime.utc(2026, 10, 9, 12);

DateTime _ago(Duration d) => _now.subtract(d);

ToolCall _call(
  String tool,
  Duration ago, {
  int work = 100,
  int? total = 150,
  bool ok = true,
}) => ToolCall(tool: tool, at: _ago(ago), workMs: work, totalMs: total, ok: ok);

/// get_health's answer, as the server gives it.
const _json = {
  'tools': [
    {
      'tool': 'list_events',
      'count': 2,
      'errors': 1,
      'calls': [
        {
          'at': '2026-10-09T11:00:00.000Z',
          'work_ms': 300,
          'total_ms': 380,
          'overhead_ms': 80,
          'ok': true,
        },
        {'at': '2026-10-09T11:30:00.000Z', 'work_ms': 20, 'ok': false},
      ],
    },
  ],
  'memory': [
    {'at': '2026-10-09T11:00:00.000Z', 'rss_mib': 201.5},
  ],
  'memory_latest_mib': 201.5,
  'restarts': ['2026-10-09T09:00:00.000Z'],
};

class _Client extends McpClient {
  _Client(this.result) : super(endpoint: Uri.parse('http://test'));

  final Object? result;
  final called = <(String, Map<String, Object?>)>[];

  @override
  Future<Object?> callTool(
    String name, [
    Map<String, Object?> arguments = const {},
    String? writeId,
  ]) async {
    called.add((name, arguments));
    if (result is Exception) throw result as Exception;
    return result;
  }
}

ServerHealth _health() => ServerHealth(
  tools: [
    ToolCalls(
      tool: 'list_events',
      calls: [
        _call('list_events', const Duration(hours: 3), work: 200, total: 260),
        _call('list_events', const Duration(hours: 2), work: 400, total: 500),
      ],
    ),
    ToolCalls(
      tool: 'note',
      calls: [
        _call(
          'note',
          const Duration(hours: 1),
          work: 900,
          total: 1000,
          ok: false,
        ),
        _call('note', const Duration(days: 3), work: 50, total: 60),
      ],
    ),
  ],
  memory: [
    MemorySample(at: _ago(const Duration(hours: 2)), mib: 190),
    MemorySample(at: _ago(const Duration(hours: 1)), mib: 210),
  ],
  restarts: [_ago(const Duration(hours: 5))],
);

void main() {
  group('The server health', () {
    test('is read as get_health gives it', () {
      final health = ServerHealth.fromJson(_json);

      final calls = health.tools.single.calls;
      expect(calls.first.workMs, 300);
      expect(calls.first.overheadMs, 80);
      expect(calls.last.totalMs, isNull);
      expect(calls.last.ok, isFalse);
      expect(calls.last.wholeMs, 20);
      expect(health.memory.single.mib, 201.5);
      expect(health.restarts.single, DateTime.utc(2026, 10, 9, 9));
    });

    test('is fetched with get_health, and kept for next time', () async {
      final cache = InMemoryResponseCache();
      final client = _Client(_json);

      await McpDiagnosticsRepository(client, cache: cache).serverHealth();
      final kept = await McpDiagnosticsRepository(
        _Client(null),
        cache: cache,
      ).cachedServerHealth();

      final (name, arguments) = client.called.single;
      expect(name, 'get_health');
      expect(arguments, {'samples': true});
      expect(kept!.tools.single.tool, 'list_events');
    });
  });

  group('Tools', () {
    test('are put in their areas by name', () {
      expect(areaOf('list_events'), ToolArea.events);
      expect(areaOf('split_recurrence'), ToolArea.events);
      expect(areaOf('note'), ToolArea.notes);
      expect(areaOf('get_notes'), ToolArea.notes);
      expect(areaOf('add_proposal_note'), ToolArea.proposals);
      expect(areaOf('compact_notes'), ToolArea.proposals);
      expect(areaOf('record_judgments'), ToolArea.proposals);
      expect(areaOf('prepare_habit_judgments'), ToolArea.habits);
      expect(areaOf('update_action_group'), ToolArea.actions);
      expect(areaOf('get_priority_colors'), ToolArea.actions);
      expect(areaOf('create_location'), ToolArea.people);
      expect(areaOf('update_trait'), ToolArea.people);
      expect(areaOf('get_health'), ToolArea.other);
    });

    test('are filtered by what they do, their area, or by name', () {
      const reads = ReadsOrWrites(writes: false);
      const writes = ReadsOrWrites(writes: true);

      expect(reads.includes('get_notes'), isTrue);
      expect(writes.includes('note'), isTrue);
      expect(writes.includes('get_notes'), isFalse);
      expect(
        [
          for (final f in toolFilters(['note', 'list_events', 'get_notes']))
            f.label,
        ],
        [
          'All tools',
          'Reads',
          'Writes',
          'Events',
          'Notes',
          'get_notes',
          'list_events',
          'note',
        ],
      );
    });
  });

  group('Statistics', () {
    test('are the mean, median, nearest-rank 95th percentile and max', () {
      final values = [for (var i = 1; i <= 20; i++) i * 10];

      expect(statisticOf(Statistic.mean, values), 105);
      expect(statisticOf(Statistic.median, values), 105);
      expect(statisticOf(Statistic.median, [3, 1, 2]), 2);
      expect(statisticOf(Statistic.p95, values), 190);
      expect(statisticOf(Statistic.max, values), 200);
      expect(Summary.of(const []), isNull);
    });

    test("are each the tool's whose call they fall on, but the mean", () {
      const values = [300, 100, 200, 400];
      const names = ['c', 'a', 'b', 'd'];

      expect(whoseStatistic(Statistic.mean, values, names), isNull);
      expect(whoseStatistic(Statistic.max, values, names), ['d']);
      expect(whoseStatistic(Statistic.p95, values, names), ['d']);
      // Halfway between the second and third: both theirs.
      expect(whoseStatistic(Statistic.median, values, names), ['b', 'c']);
      expect(whoseStatistic(Statistic.median, values, ['x', 'x', 'x', 'x']), [
        'x',
      ]);
      expect(whoseStatistic(Statistic.median, [3, 1, 2], ['c', 'a', 'b']), [
        'b',
      ]);
      expect(whoseStatistic(Statistic.max, const [], const []), isNull);
    });

    test('are every tool whose calls tie at them, the commonest first', () {
      // Timeouts, all alike.
      const values = [100, 30000, 30000, 30000, 30000, 30000];
      const names = ['a', 'b', 'c', 'c', 'd', 'e'];

      expect(whoseStatistic(Statistic.max, values, names), [
        'c',
        'b',
        'd',
        'e',
      ]);
      expect(whoseStatistic(Statistic.max, const [5, 5], const ['a', 'b']), [
        'a',
        'b',
      ]);
    });

    test('of each bucket of calls stack the work under the whole', () {
      final calls = [
        _call('a', const Duration(minutes: 110), work: 100, total: 150),
        _call(
          'a',
          const Duration(minutes: 100),
          work: 300,
          total: 320,
          ok: false,
        ),
        _call('a', const Duration(minutes: 5), work: 50, total: null),
      ];

      final each = latencyPoints(calls);
      final hourly = latencyPoints(
        calls,
        statistic: Statistic.max,
        bucket: BucketSize.hour,
      );

      expect([for (final p in each) p.total], [150, 320, 50]);
      expect(each[1].errors, 1);
      expect(each[2].overhead, 0);
      expect(hourly, hasLength(2));
      expect(hourly.first.work, 300);
      expect(hourly.first.total, 320);
      expect(hourly.first.count, 2);
      expect(hourly.first.errors, 1);
      expect(hourly.first.at.minute, 30);
    });

    test('of each bucket of memory', () {
      final memory = [
        MemorySample(at: _ago(const Duration(minutes: 50)), mib: 100),
        MemorySample(at: _ago(const Duration(minutes: 40)), mib: 200),
      ];

      expect(memoryPoints(memory, statistic: Statistic.mean).single.mib, 150);
      expect(memoryPoints(memory), hasLength(2));
    });
  });

  group('The Diagnostics page', () {
    Future<void> open(
      WidgetTester tester,
      DiagnosticsRepository repository, {
      double width = 900,
    }) async {
      tester.view.physicalSize = Size(width, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final hotkeys = Hotkeys();
      await tester.pumpWidget(
        MaterialApp(
          navigatorObservers: [hotkeys],
          builder: (context, child) =>
              HotkeyScope(hotkeys: hotkeys, child: child!),
          home: DiagnosticsScreen(repository: repository, clock: () => _now),
        ),
      );
      await tester.pumpAndSettle();
    }

    Future<void> press(WidgetTester tester, LogicalKeyboardKey key) async {
      await tester.sendKeyEvent(key);
      await tester.pumpAndSettle();
    }

    /// The title of the graph highlighted.
    String? highlighted() {
      final context = FocusManager.instance.primaryFocus?.context;
      if (context == null) return null;
      final titles = find
          .descendant(
            of: find.byElementPredicate((e) => e == context),
            matching: find.byType(Text),
          )
          .evaluate();
      return titles.isEmpty ? null : (titles.first.widget as Text).data;
    }

    testWidgets('J and K go from graph to graph, not to the menus over '
        'them', (tester) async {
      await open(tester, InMemoryDiagnosticsRepository(_health()));
      await press(tester, LogicalKeyboardKey.keyJ);
      final first = highlighted();
      expect(first, isNotNull);
      expect(find.byType(DropdownButton<ToolFilter>), findsOneWidget);
      await press(tester, LogicalKeyboardKey.keyJ);
      final second = highlighted();
      expect(second, isNot(first));
      await press(tester, LogicalKeyboardKey.keyK);
      expect(highlighted(), first);
    });

    testWidgets('= zooms in, and - back out', (tester) async {
      await open(tester, InMemoryDiagnosticsRepository(_health()));
      expect(find.textContaining('(zoomed in)'), findsNothing);
      await press(tester, LogicalKeyboardKey.equal);
      expect(find.textContaining('(zoomed in)'), findsOneWidget);
      await press(tester, LogicalKeyboardKey.minus);
      expect(find.textContaining('(zoomed in)'), findsNothing);
    });

    testWidgets('H and L go between the Server and App panes', (tester) async {
      await open(tester, InMemoryDiagnosticsRepository(_health()));
      final tabs = DefaultTabController.of(
        tester.element(find.byType(TabBarView)),
      );
      expect(tabs.index, 0);
      await press(tester, LogicalKeyboardKey.keyL);
      expect(tabs.index, 1);
      await press(tester, LogicalKeyboardKey.keyH);
      expect(tabs.index, 0);
    });

    testWidgets("shows the last day's calls, memory and restarts, each "
        'summed up', (tester) async {
      await open(tester, InMemoryDiagnosticsRepository(_health()));

      // The note three days ago is out of range.
      expect(find.text('3 calls in view, 1 failed'), findsOneWidget);
      expect(find.text('500 ms'), findsWidgets);
      expect(find.text('Memory'), findsWidgets);
      expect(find.text('210 MiB'), findsWidgets); // Max, and latest.
      expect(find.textContaining('1 in view'), findsOneWidget);
    });

    testWidgets('draws the calls and memory as dots, unjoined, with the '
        "mean, median, p95 and max marked, each labelled with whose call it's "
        'on, the mean with the tools shown', (tester) async {
      await open(tester, InMemoryDiagnosticsRepository(_health()));
      final [calls, memory, ...] = [
        for (final chart in tester.widgetList<LineChart>(
          find.byType(LineChart),
        ))
          chart.data,
      ];
      for (final data in [calls, memory]) {
        expect(data.lineBarsData.map((b) => b.barWidth), everyElement(0));
        expect(
          data.lineBarsData.map((b) => b.dotData.show),
          everyElement(true),
        );
      }
      List<String> labels(LineChartData data) => [
        for (final line in data.extraLinesData.horizontalLines)
          line.label.labelResolver(line),
      ];
      expect(labels(calls), [
        'Mean · All tools · 587 ms',
        'Median · list_events · 500 ms',
        // The same line: one label.
        'p95, Max · note · 1.0 s',
      ]);
      expect(labels(memory).last, 'p95, Max · 210 MiB');

      await tester.tap(find.text('All tools'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Writes').last);
      await tester.pumpAndSettle();
      final writes = tester.widget<LineChart>(find.byType(LineChart).first);
      expect(labels(writes.data).first, startsWith('Mean · Writes · '));
    });

    testWidgets('cuts short the tools a marker is on that are too many to '
        'fit across', (tester) async {
      const tools = [
        'amend_proposal',
        'confirm_proposal',
        'get_proposal',
        'list_events',
        'update_event',
      ];
      await open(
        tester,
        InMemoryDiagnosticsRepository(
          ServerHealth(
            tools: [
              for (final (i, tool) in tools.indexed)
                ToolCalls(
                  tool: tool,
                  calls: [
                    // Each timed out alike.
                    _call(tool, Duration(hours: i + 1), total: 30000),
                  ],
                ),
            ],
            memory: const [],
            restarts: const [],
          ),
        ),
        // Room, in the tests' font, for one of them.
        width: 680,
      );
      final calls = tester.widget<LineChart>(find.byType(LineChart).first);
      final max = calls.data.extraLinesData.horizontalLines.last;
      expect(
        max.label.labelResolver(max),
        // The calls are oldest first.
        'Median, p95, Max · update_event / 4 more · 30 s',
      );
    });

    testWidgets('filters to a kind of tool, and a range', (tester) async {
      await open(tester, InMemoryDiagnosticsRepository(_health()));

      await tester.tap(find.text('All tools'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Writes').last);
      await tester.pumpAndSettle();
      expect(find.text('1 call in view, 1 failed'), findsOneWidget);

      await tester.tap(find.text('Last day'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Last week').last);
      await tester.pumpAndSettle();
      expect(find.text('2 calls in view, 1 failed'), findsOneWidget);
    });

    testWidgets('shows a statistic of each bucket, sized as picked', (
      tester,
    ) async {
      await open(tester, InMemoryDiagnosticsRepository(_health()));
      expect(find.text('Per: '), findsNothing);

      await tester.tap(find.text('Each call'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Median').last);
      await tester.pumpAndSettle();

      expect(find.text('Per: '), findsOneWidget);
      await tester.tap(find.text('Hour'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Day').last);
      await tester.pumpAndSettle();
      expect(find.text('Day'), findsOneWidget);
    });

    testWidgets('zooms in keeping the latest in view, and back out', (
      tester,
    ) async {
      await open(tester, InMemoryDiagnosticsRepository(_health()));

      await tester.tap(find.byTooltip('Zoom in'));
      await tester.pumpAndSettle();
      expect(find.textContaining('(zoomed in)'), findsOneWidget);
      // The last twelve hours: the calls of the last few are still in view.
      expect(find.text('3 calls in view, 1 failed'), findsOneWidget);

      await tester.tap(find.byTooltip('Earlier'));
      await tester.pumpAndSettle();
      expect(find.text('No calls in view.'), findsOneWidget);

      await tester.tap(find.byTooltip('Later'));
      await tester.pumpAndSettle();
      expect(find.text('3 calls in view, 1 failed'), findsOneWidget);

      await tester.tap(find.byTooltip('Zoom out'));
      await tester.pumpAndSettle();
      expect(find.textContaining('(zoomed in)'), findsNothing);
    });

    testWidgets('scrolls the page with the wheel, and zooms with a pinch', (
      tester,
    ) async {
      await open(tester, InMemoryDiagnosticsRepository(_health()));
      final graph = tester.getCenter(find.text('Tool calls'));

      tester.binding.handlePointerEvent(
        PointerScrollEvent(position: graph, scrollDelta: const Offset(0, 120)),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('(zoomed in)'), findsNothing);

      tester.binding.handlePointerEvent(
        PointerScaleEvent(position: graph, scale: 2),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('(zoomed in)'), findsOneWidget);
    });

    testWidgets('says when the server has no get_health', (tester) async {
      await open(
        tester,
        McpDiagnosticsRepository(
          _Client(McpException('Unknown tool: get_health')),
        ),
      );

      expect(
        find.textContaining("doesn't report its health yet"),
        findsOneWidget,
      );
    });

    testWidgets("swipes to the app's pane, saying when the app's health "
        "isn't recorded", (tester) async {
      await open(tester, InMemoryDiagnosticsRepository(_health()));

      await tester.tap(find.text('App'));
      await tester.pumpAndSettle();

      expect(find.textContaining("isn't recorded here"), findsOneWidget);
    });

    testWidgets('opens from the app menu', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: DiagnosticsScope(
            repository: InMemoryDiagnosticsRepository(_health()),
            child: Scaffold(
              appBar: AppBar(actions: const [AppMenu(serverLabel: 'test')]),
            ),
          ),
        ),
      );

      await tester.tap(find.byType(AppMenu));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Diagnostics'));
      await tester.pumpAndSettle();

      expect(find.byType(DiagnosticsScreen), findsOneWidget);
    });
  });
}
