import 'package:flutter_test/flutter_test.dart';
import 'package:time_tracker_client/models/circadian.dart';
import 'package:time_tracker_client/services/circadian_repository.dart';
import 'package:time_tracker_client/services/mcp_client.dart';
import 'package:time_tracker_client/services/response_cache.dart';

void main() {
  final rhythm = {
    'time_zone': null,
    'windows': {
      'minimum_before_waking_minutes': 90,
      'dim_before_minutes': 300,
      'bright_after_minutes': 200,
    },
    'revisions': [
      {'id': 'a', 'date': '2026-11-02', 'time': '06:40'},
    ],
  };

  test('reads the rhythm, and keeps it for next time', () async {
    final cache = InMemoryResponseCache();
    final client = _Client((_, _) => rhythm);
    final repository = McpCircadianRepository(client, cache: cache);
    final read = await repository.rhythm();
    expect(client.calls.single.$1, 'get_circadian_rhythm');
    expect(read!.windows.dimBefore, 300);
    final kept = await McpCircadianRepository(
      _Client((_, _) => throw StateError('offline')),
      cache: cache,
    ).cachedRhythm();
    expect(kept!.revisions.single.time, '06:40');
  });

  test('a server without it has none, and nothing is kept', () async {
    final cache = InMemoryResponseCache();
    await cache.write('circadian_rhythm', rhythm);
    final repository = McpCircadianRepository(
      _Client((name, _) => throw McpException('Unknown tool: $name')),
      cache: cache,
    );
    expect(await repository.rhythm(), isNull);
    expect(await repository.cachedRhythm(), isNull);
    final circadian = Circadian(repository);
    await circadian.load();
    expect(circadian.rhythm, isNull);
  });

  test('other failures are thrown, and what was kept stays', () async {
    final cache = InMemoryResponseCache();
    await cache.write('circadian_rhythm', rhythm);
    final repository = McpCircadianRepository(
      _Client((_, _) => throw McpException('Offline')),
      cache: cache,
    );
    await expectLater(repository.rhythm(), throwsA(isA<McpException>()));
    final circadian = Circadian(repository);
    await circadian.load();
    expect(circadian.rhythm?.windows.brightAfter, 200);
  });

  test('sets a wake time and the windows as the server takes them', () async {
    final client = _Client((_, _) => rhythm);
    final repository = McpCircadianRepository(client);
    await repository.setNaturalWakeTime(
      DateTime(2026, 11, 2),
      hour: 6,
      minute: 5,
      note: 'no alarm',
    );
    await repository.setNaturalWakeTime(
      DateTime(2026, 11, 3),
      hour: 7,
      minute: 0,
    );
    await repository.setWindows(
      const CircadianWindows(
        minimumBeforeWaking: 100,
        dimBefore: 0,
        brightAfter: 1440,
      ),
    );
    expect(
      [for (final (name, _) in client.calls) name],
      [
        'set_natural_wake_time',
        'set_natural_wake_time',
        'set_circadian_windows',
      ],
    );
    expect(
      [for (final (_, arguments) in client.calls) arguments],
      [
        {'date': '2026-11-02', 'time': '06:05', 'note': 'no alarm'},
        {'date': '2026-11-03', 'time': '07:00'},
        {
          'minimum_before_waking_minutes': 100,
          'dim_before_minutes': 0,
          'bright_after_minutes': 1440,
        },
      ],
    );
  });
}

class _Client extends McpClient {
  _Client(this.answer) : super(endpoint: Uri.parse('http://test'));

  final Object? Function(String name, Map<String, Object?> arguments) answer;
  final calls = <(String, Map<String, Object?>)>[];

  @override
  Future<Object?> callTool(
    String name, [
    Map<String, Object?> arguments = const {},
    String? writeId,
  ]) async {
    calls.add((name, arguments));
    return answer(name, arguments);
  }
}
