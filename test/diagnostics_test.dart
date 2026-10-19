import 'dart:async';

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
import 'package:time_tracker_client/widgets/status_message.dart';

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

/// [health], its memory sampled every [interval].
ServerHealth _every(Duration interval, ServerHealth health) => ServerHealth(
  tools: health.tools,
  memory: health.memory,
  memoryInterval: interval,
  restarts: health.restarts,
);

/// Gives its health, counting each time it's fetched; while [hold] is
/// set, not until it completes, and with [failing], fails.
class _Counting extends InMemoryDiagnosticsRepository {
  _Counting(super.health);

  var fetched = 0;
  Completer<void>? hold;
  bool failing = false;

  @override
  Future<ServerHealth> serverHealth() async {
    fetched++;
    await hold?.future;
    if (failing) throw Exception('offline');
    return health;
  }
}

/// [_health], with its memory broken down, and [tabs] sheet tabs kept.
ServerHealth _brokenDown({int tabs = 2}) {
  List<MemoryPart> parts(double total, double sheets, double calendar) => [
    for (var i = 0; i < tabs; i++)
      MemoryPart(name: 'Sheet: Tab $i', mib: sheets * (i + 1)),
    MemoryPart(name: 'Calendar', mib: calendar),
    MemoryPart(
      name: 'Rest of server',
      mib: total - calendar - sheets * tabs * (tabs + 1) / 2,
    ),
  ];
  return ServerHealth(
    tools: _health().tools,
    memory: [
      MemorySample(
        at: _ago(const Duration(hours: 2)),
        mib: 190,
        parts: parts(190, 1, 4),
      ),
      MemorySample(
        at: _ago(const Duration(hours: 1, minutes: 55)),
        mib: 200,
        parts: parts(200, 2, 5),
      ),
      MemorySample(
        at: _ago(const Duration(hours: 1, minutes: 50)),
        mib: 210,
        parts: parts(210, 3, 7),
      ),
    ],
    restarts: _health().restarts,
  );
}

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

    test('reads how far apart its memory samples are, a second from a '
        'server too old to say', () {
      expect(
        ServerHealth.fromJson({..._json, 'memory_interval_seconds': 60})
            .memoryInterval,
        const Duration(minutes: 1),
      );
      expect(
        ServerHealth.fromJson(_json).memoryInterval,
        const Duration(seconds: 1),
      );
      expect(
        ServerHealth.fromJson({..._json, 'memory_interval_seconds': 0})
            .memoryInterval,
        const Duration(seconds: 1),
      );
    });

    test("reads what the server's memory is made of, when it says", () {
      final health = ServerHealth.fromJson({
        'memory': [
          {'at': '2026-10-09T10:00:00.000Z', 'rss_mib': 180.0, 'parts': null},
          {'at': '2026-10-09T10:00:01.000Z', 'rss_mib': 181.0},
          {
            'at': '2026-10-09T11:00:00.000Z',
            'rss_mib': 201.5,
            'parts': [
              {'name': 'Sheet: Actions', 'mib': 1.5},
              {'name': 'Calendar', 'mib': 4},
              {'name': 'Rest of server', 'mib': 196},
            ],
          },
        ],
        'memory_latest_mib': 201.5,
        'memory_min_mib': 180.0,
        'memory_max_mib': 201.5,
      });

      final [old, older, broken] = health.memory;
      expect(old.parts, isNull);
      expect(older.parts, isNull);
      expect(broken.parts, const [
        MemoryPart(name: 'Sheet: Actions', mib: 1.5),
        MemoryPart(name: 'Calendar', mib: 4),
        MemoryPart(name: 'Rest of server', mib: 196),
      ]);
      expect(broken.parts!.first.isSheet, isTrue);
      expect(broken.parts!.last.isSheet, isFalse);
    });

    test('reads how many threads the server ran, when it says', () {
      final health = ServerHealth.fromJson({
        'memory': [
          {'at': '2026-10-09T10:00:00.000Z', 'rss_mib': 180.0},
          {'at': '2026-10-09T10:01:00.000Z', 'rss_mib': 181.0, 'threads': null},
          {
            'at': '2026-10-09T10:02:00.000Z',
            'rss_mib': 220.8,
            'parts': [
              {'name': 'Heap in use (untracked)', 'mib': 7.0},
              {'name': 'Allocator: free but held', 'mib': 185.3},
              {'name': 'Rest of server', 'mib': 28.5},
            ],
            'threads': 14,
          },
        ],
        'memory_latest_mib': 220.8,
      });

      expect([for (final m in health.memory) m.threads], [null, null, 14]);
      expect(health.memory.last.parts!.map((p) => p.name), [
        MemoryPart.heapUntracked,
        MemoryPart.allocatorFree,
        MemoryPart.rest,
      ]);
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

  group("The server's memory interval", () {
    test('is said in words', () {
      expect(eachInterval(const Duration(seconds: 1)), 'each second');
      expect(eachInterval(const Duration(minutes: 1)), 'each minute');
      expect(eachInterval(const Duration(minutes: 5)), 'every 5 minutes');
      expect(eachInterval(const Duration(seconds: 90)), 'every 90 seconds');
      expect(eachInterval(const Duration(hours: 1)), 'each hour');
    });

    test('leaves out buckets finer than it', () {
      expect(BucketSize.atLeast(const Duration(seconds: 1)), BucketSize.values);
      expect(BucketSize.atLeast(const Duration(minutes: 1)), BucketSize.values);
      expect(BucketSize.atLeast(const Duration(minutes: 30)), [
        BucketSize.hour,
        BucketSize.sixHours,
        BucketSize.day,
      ]);
      expect(BucketSize.atLeast(const Duration(days: 2)), [BucketSize.day]);
    });

    test('joins samples one after another, however far apart', () {
      expect(
        memoryJoinWithin(const Duration(seconds: 1)),
        const Duration(minutes: 15),
      );
      expect(
        memoryJoinWithin(const Duration(minutes: 1)),
        const Duration(minutes: 15),
      );
      expect(
        memoryJoinWithin(const Duration(hours: 1)),
        const Duration(minutes: 90),
      );
      expect(
        memoryJoinWithin(
          const Duration(minutes: 1),
          statistic: Statistic.median,
          bucket: BucketSize.quarterHour,
        ),
        const Duration(minutes: 22, seconds: 30),
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

    test("of each bucket of memory's parts: the mean of each, or the parts "
        'of the sample the statistic falls on', () {
      final memory = [
        MemorySample(
          at: _ago(const Duration(minutes: 50)),
          mib: 100,
          parts: const [
            MemoryPart(name: 'Calendar', mib: 4),
            MemoryPart(name: 'Rest of server', mib: 96),
          ],
        ),
        MemorySample(
          at: _ago(const Duration(minutes: 45)),
          mib: 200,
          parts: const [
            MemoryPart(name: 'Sheet: Actions', mib: 2),
            MemoryPart(name: 'Calendar', mib: 6),
            MemoryPart(name: 'Rest of server', mib: 192),
          ],
        ),
        // From before the server broke it down: all the rest of it.
        MemorySample(at: _ago(const Duration(minutes: 40)), mib: 120),
      ];

      final mean = memoryPoints(memory, statistic: Statistic.mean).single;
      expect(mean.mib, 140);
      expect(mean.parts, const [
        MemoryPart(name: 'Calendar', mib: 10 / 3),
        MemoryPart(name: 'Sheet: Actions', mib: 2 / 3),
        MemoryPart(name: 'Rest of server', mib: 136),
      ]);
      final top = memoryPoints(memory, statistic: Statistic.max).single;
      expect(top.parts, memory[1].parts);
      final median = memoryPoints(memory, statistic: Statistic.median).single;
      expect(median.mib, 120);
      expect(median.parts, isNull);
      expect(
        memoryPoints([memory.last], statistic: Statistic.mean).single.parts,
        isNull,
      );
    });

    test("of each bucket's threads: the mean of those counted, or the "
        'count of the sample the statistic falls on', () {
      final memory = [
        MemorySample(
          at: _ago(const Duration(minutes: 50)),
          mib: 100,
          threads: 7,
        ),
        MemorySample(
          at: _ago(const Duration(minutes: 45)),
          mib: 200,
          threads: 14,
        ),
        // From before the server counted them.
        MemorySample(at: _ago(const Duration(minutes: 40)), mib: 120),
      ];

      expect(memoryPoints(memory).map((p) => p.threads), [7, 14, null]);
      expect(
        memoryPoints(memory, statistic: Statistic.mean).single.threads,
        11, // 10.5, rounded.
      );
      expect(memoryPoints(memory, statistic: Statistic.max).single.threads, 14);
      expect(
        memoryPoints(memory, statistic: Statistic.median).single.threads,
        isNull,
      );
    });

    test('of memory, stacked: the rest of the server at the foot, the '
        'calendar, then the sheet tabs, as the server first named them, or '
        'all of them as one', () {
      final points = [
        MemoryPoint(at: _ago(const Duration(hours: 3)), mib: 150),
        MemoryPoint(
          at: _ago(const Duration(hours: 2)),
          mib: 190,
          parts: const [
            MemoryPart(name: 'Sheet: Actions', mib: 1.5),
            MemoryPart(name: 'Calendar', mib: 4),
            MemoryPart(name: 'Rest of server', mib: 184.5),
          ],
        ),
        MemoryPoint(
          at: _ago(const Duration(hours: 1)),
          mib: 210,
          parts: const [
            MemoryPart(name: 'Sheet: Actions', mib: 2),
            MemoryPart(name: 'Sheet: People', mib: 1),
            MemoryPart(name: 'Calendar', mib: 5),
            MemoryPart(name: 'Rest of server', mib: 202),
          ],
        ),
      ];

      final layers = memoryLayers(points);
      expect(
        [for (final l in layers) l.name],
        ['Rest of server', 'Calendar', 'Sheet: Actions', 'Sheet: People'],
      );
      expect(
        [for (final l in layers) l.values],
        [
          [150, 184.5, 202],
          [0, 4, 5],
          [0, 1.5, 2],
          [0, 0, 1],
        ],
      );
      expect([for (final l in layers) l.isSheet], [false, false, true, true]);

      final grouped = memoryLayers(points, groupSheets: true);
      expect(
        [for (final l in grouped) l.name],
        ['Rest of server', 'Calendar', 'Sheets'],
      );
      expect(grouped.last.values, [0, 1.5, 3]);
      expect(grouped.last.isSheet, isTrue);
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

    testWidgets('draws the calls as dots, unjoined, and both them and the '
        "memory with the mean, median, p95 and max marked, each labelled with "
        "whose call it's on, the mean with the tools shown", (tester) async {
      await open(tester, InMemoryDiagnosticsRepository(_health()));
      final [calls, memory, ...] = [
        for (final chart in tester.widgetList<LineChart>(
          find.byType(LineChart),
        ))
          chart.data,
      ];
      expect(calls.lineBarsData.map((b) => b.barWidth), everyElement(0));
      expect(calls.lineBarsData.map((b) => b.dotData.show), everyElement(true));
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

    testWidgets('offers no bucket finer than the server samples its memory', (
      tester,
    ) async {
      await open(
        tester,
        InMemoryDiagnosticsRepository(
          _every(const Duration(minutes: 30), _health()),
        ),
      );
      await tester.tap(find.text('Each call'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Median').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Hour'));
      await tester.pumpAndSettle();

      expect(find.text('15 minutes'), findsNothing);
      expect(find.text('6 hours'), findsWidgets);
    });

    testWidgets('offers every bucket when the server samples its memory '
        'each minute', (tester) async {
      await open(
        tester,
        InMemoryDiagnosticsRepository(
          _every(const Duration(minutes: 1), _health()),
        ),
      );
      await tester.tap(find.text('Each call'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Median').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Hour'));
      await tester.pumpAndSettle();

      expect(find.text('15 minutes'), findsWidgets);
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

    /// Taps [finder] in a graph's card, past the wait for a double tap,
    /// which zooms back out.
    Future<void> tapGraph(WidgetTester tester, Finder finder) async {
      await tester.tap(finder);
      await tester.pump(kDoubleTapTimeout);
      await tester.pumpAndSettle();
    }

    LineChartData memoryChart(WidgetTester tester) =>
        tester.widgetList<LineChart>(find.byType(LineChart)).elementAt(1).data;

    /// Each point's top, in each layer shown, bottom up, with the layers'
    /// colors.
    List<List<double>> stacked(WidgetTester tester) => [
      for (final bar in memoryChart(tester).lineBarsData.skip(1))
        [
          for (final s in bar.spots)
            if (!s.isNull()) s.y,
        ],
    ];

    testWidgets("stacks what the server's memory is made of, the rest of it "
        'at the foot', (tester) async {
      await open(tester, InMemoryDiagnosticsRepository(_brokenDown()));

      final data = memoryChart(tester);
      expect(data.minY, 0);
      expect(stacked(tester), [
        [183, 189, 194], // The rest of the server.
        [187, 194, 201], // The calendar.
        [188, 196, 204], // Tab 0.
        [190, 200, 210], // Tab 1, the whole.
      ]);
      // Each layer filled from the one under it.
      expect(
        [for (final b in data.betweenBarsData) (b.fromIndex, b.toIndex)],
        [(0, 1), (1, 2), (2, 3), (3, 4)],
      );
      expect(data.betweenBarsData.map((b) => b.color).toSet(), hasLength(4));
      for (final name in ['Rest of server', 'Calendar', 'Tab 0', 'Tab 1']) {
        expect(find.widgetWithText(InputChip, name), findsOneWidget);
      }
    });

    testWidgets('shows a layer alone, tapped in the legend, and all again '
        'when it is tapped again, or All', (tester) async {
      await open(tester, InMemoryDiagnosticsRepository(_brokenDown()));

      await tapGraph(tester, find.widgetWithText(InputChip, 'Calendar'));
      expect(stacked(tester), [
        [4, 5, 7],
      ]);
      expect(memoryChart(tester).betweenBarsData, hasLength(1));
      // Summed up alone, too.
      expect(find.text('Calendar'), findsWidgets);
      expect(find.text('7.0 MiB'), findsWidgets);

      await tapGraph(tester, find.widgetWithText(InputChip, 'Calendar'));
      expect(stacked(tester), hasLength(4));
      expect(find.widgetWithText(ActionChip, 'All'), findsNothing);

      await tapGraph(tester, find.widgetWithText(InputChip, 'Tab 1'));
      expect(stacked(tester), [
        [2, 4, 6],
      ]);
      await tapGraph(tester, find.widgetWithText(ActionChip, 'All'));
      expect(stacked(tester), hasLength(4));
    });

    testWidgets('makes many sheet tabs one layer, opened out into each and '
        'shown alone together', (tester) async {
      await open(tester, InMemoryDiagnosticsRepository(_brokenDown(tabs: 5)));

      expect(stacked(tester), hasLength(3));
      expect(stacked(tester).last, [190, 200, 210]);
      expect(find.widgetWithText(InputChip, 'Tab 0'), findsNothing);

      await tapGraph(tester, find.byTooltip('Show each tab'));
      expect(stacked(tester), hasLength(7));
      expect(find.widgetWithText(InputChip, 'Tab 4'), findsOneWidget);

      await tapGraph(tester, find.widgetWithText(InputChip, 'Sheets (5)'));
      expect(stacked(tester), hasLength(5)); // Each tab, alone together.
      expect(stacked(tester).last, [15, 30, 45]);

      await tapGraph(tester, find.byTooltip('Show the tabs as one'));
      expect(stacked(tester), [
        [15, 30, 45],
      ]);
    });

    testWidgets('says what a point is made of, largest first: the latest, '
        'and what is tapped', (tester) async {
      await open(tester, InMemoryDiagnosticsRepository(_brokenDown()));

      List<String> said() => [
        for (final t in tester.widgetList<Text>(
          find.descendant(
            of: find.byWidgetPredicate(
              (w) => w.runtimeType.toString() == '_MemoryBreakdown',
            ),
            matching: find.byType(Text),
          ),
        ))
          t.data!,
      ];
      expect(said().first, startsWith('Latest · '));
      expect(said().first, endsWith(' · 210 MiB'));
      expect(said().skip(1), [
        'Rest of server', '194 MiB', //
        'Calendar', '7.0 MiB',
        'Sheet: Tab 1', '6.0 MiB',
        'Sheet: Tab 0', '3.0 MiB',
      ]);

      // The first point, at the left.
      final chart = tester.getRect(find.byType(LineChart).at(1));
      final from = _now.subtract(const Duration(days: 1));
      final across =
          _ago(const Duration(hours: 2)).difference(from).inMilliseconds /
          const Duration(days: 1).inMilliseconds;
      await tester.tapAt(
        Offset(chart.left + 60 + (chart.width - 60) * across, chart.center.dy),
      );
      await tester.pumpAndSettle();
      expect(said().first, isNot(startsWith('Latest')));
      expect(said().first, endsWith(' · 190 MiB'));
      expect(said()[1], 'Rest of server');
      expect(said()[2], '183 MiB');
      expect(
        memoryChart(tester).extraLinesData.verticalLines.single.x,
        _ago(const Duration(hours: 2)).millisecondsSinceEpoch.toDouble(),
      );
    });

    /// What the memory graph's point says first: when it is, and its total.
    String pointSaid(WidgetTester tester) => tester
        .widgetList<Text>(
          find.descendant(
            of: find.byWidgetPredicate(
              (w) => w.runtimeType.toString() == '_MemoryBreakdown',
            ),
            matching: find.byType(Text),
          ),
        )
        .first
        .data!;

    final toTheSecond = RegExp(r'\d:\d\d:\d\d');

    testWidgets("colors the allocator's parts apart, and says how many "
        'threads the server ran', (tester) async {
      final health = _brokenDown();
      await open(
        tester,
        InMemoryDiagnosticsRepository(
          ServerHealth(
            tools: health.tools,
            memory: [
              for (final (i, m) in health.memory.indexed)
                MemorySample(
                  at: m.at,
                  mib: m.mib + 30,
                  parts: [
                    ...m.parts!.take(m.parts!.length - 1),
                    const MemoryPart(name: MemoryPart.heapUntracked, mib: 6),
                    const MemoryPart(name: MemoryPart.allocatorFree, mib: 20),
                    const MemoryPart(name: 'Something new', mib: 4),
                    m.parts!.last,
                  ],
                  threads: 7 + i,
                ),
            ],
            restarts: health.restarts,
          ),
        ),
      );

      expect(memoryChart(tester).betweenBarsData, hasLength(7));
      expect(
        memoryChart(tester).betweenBarsData.map((b) => b.color).toSet(),
        hasLength(7),
      );
      expect(pointSaid(tester), endsWith(' · 240 MiB · 9 threads'));
    });

    testWidgets("says nothing of threads from a server that doesn't count "
        'them', (tester) async {
      await open(tester, InMemoryDiagnosticsRepository(_brokenDown()));

      expect(pointSaid(tester), endsWith(' · 210 MiB'));
    });

    testWidgets("says an older server's memory is the most of each second, "
        'and its points to the second', (tester) async {
      await open(tester, InMemoryDiagnosticsRepository(_brokenDown()));

      expect(
        find.textContaining('the most of each second after a call'),
        findsOneWidget,
      );
      expect(pointSaid(tester), contains(toTheSecond));
    });

    testWidgets('says memory sampled each minute is the most of each minute, '
        'and its points to the minute', (tester) async {
      await open(
        tester,
        InMemoryDiagnosticsRepository(
          _every(const Duration(minutes: 1), _brokenDown()),
        ),
      );

      expect(
        find.textContaining('the most of each minute after a call'),
        findsOneWidget,
      );
      expect(find.textContaining('each second'), findsNothing);
      expect(pointSaid(tester), isNot(contains(toTheSecond)));
      expect(pointSaid(tester), endsWith(' · 210 MiB'));
    });

    testWidgets('the refresh button refreshes as pulling the page down '
        'does, with its indicator', (tester) async {
      final repository = _Counting(_health());
      await open(tester, repository);
      expect(repository.fetched, 1);

      // Pulled down, far enough on a page this tall.
      await tester.fling(find.text('Tools: '), const Offset(0, 1200), 1000);
      await tester.pumpAndSettle();
      expect(repository.fetched, 2);

      // The button: the same indicator, until it's done.
      repository.hold = Completer();
      await tester.tap(find.byTooltip('Refresh'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(repository.fetched, 3);
      expect(find.byType(RefreshProgressIndicator), findsOneWidget);
      repository.hold!.complete();
      await tester.pumpAndSettle();
      expect(find.byType(RefreshProgressIndicator), findsNothing);
      expect(find.byType(LoadError), findsNothing);

      // And its error, as pulling down's.
      repository.hold = null;
      repository.failing = true;
      await tester.tap(find.byTooltip('Refresh'));
      await tester.pumpAndSettle();
      expect(repository.fetched, 4);
      expect(find.byType(LoadError), findsOneWidget);
      expect(find.text('Memory'), findsWidgets); // What it had, still.
    });

    testWidgets("the refresh button leaves the server be on the app's pane", (
      tester,
    ) async {
      final repository = _Counting(_health());
      await open(tester, repository);
      await tester.tap(find.text('App'));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Refresh'));
      await tester.pumpAndSettle();

      expect(repository.fetched, 1);
      expect(tester.takeException(), isNull);
    });

    testWidgets("draws an older server's memory, not broken down, as one "
        'layer', (tester) async {
      await open(tester, InMemoryDiagnosticsRepository(_health()));

      expect(stacked(tester), [
        [190, 210],
      ]);
      expect(find.byType(InputChip), findsNothing);
      expect(find.text('Not broken down by the server'), findsOneWidget);
      expect(find.text('210 MiB'), findsWidgets); // Max, and latest.
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
