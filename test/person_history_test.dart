import 'package:flutter_test/flutter_test.dart';
import 'package:time_tracker_client/models/event.dart';
import 'package:time_tracker_client/models/facts.dart';
import 'package:time_tracker_client/models/note.dart';
import 'package:time_tracker_client/screens/person_history.dart';
import 'package:time_tracker_client/services/events_repository.dart';
import 'package:time_tracker_client/services/mcp_client.dart';

void main() {
  final from = DateTime(2016, 10, 19), to = DateTime(2026, 10, 19);

  test(
    "a person's events are asked of list_events by person_id, sorted",
    () async {
      final client = _Client([
        _event('b', DateTime(2024, 5, 1)).toJson(),
        _event('a', DateTime(2019, 2, 1)).toJson(),
      ]);

      final events = await McpEventsRepository(client)
          .personEvents('sam', from, to);

      expect(client.calls.single.$1, 'list_events');
      expect(client.calls.single.$2, {
        'min_time': localIsoTimestamp(from),
        'max_time': localIsoTimestamp(to),
        'person_id': 'sam',
      });
      expect([for (final e in events) e.id], ['a', 'b']);
    },
  );

  test('in memory, those whose facts name them: with, for or noted', () async {
    final events = await InMemoryEventsRepository([
      _event('with', DateTime(2020, 1, 1), const Facts(withIds: ['sam'])),
      _event('for', DateTime(2021, 1, 1), const Facts(forIds: ['sam'])),
      _event('noted', DateTime(2022, 1, 1), const Facts(notes: {'sam': 'Hi'})),
      _event('alex', DateTime(2023, 1, 1), const Facts(withIds: ['alex'])),
      _event('none', DateTime(2023, 2, 1)),
      _event('old', DateTime(2010, 1, 1), const Facts(withIds: ['sam'])),
    ]).personEvents('sam', from, to);

    expect([for (final e in events) e.id], ['with', 'for', 'noted']);
  });

  test('their history goes back 10 years from now, newest first', () async {
    final client = _Client([
      _event('a', DateTime(2019, 2, 1)).toJson(),
      _event('b', DateTime(2024, 5, 1)).toJson(),
    ]);

    final history = await loadPersonHistory(
      McpEventsRepository(client),
      'sam',
      now: to,
    );

    expect(client.calls.single.$2['min_time'], localIsoTimestamp(from));
    expect(client.calls.single.$2['max_time'], localIsoTimestamp(to));
    expect([for (final e in history) e.id], ['b', 'a']);
  });
}

Event _event(String id, DateTime start, [Facts? facts]) => Event.fromJson({
  'id': id,
  'summary': id,
  'start': localIsoTimestamp(start),
  'end': localIsoTimestamp(start.add(const Duration(hours: 1))),
  'facts': ?facts?.toJson(),
});

class _Client extends McpClient {
  _Client(this.result) : super(endpoint: Uri.parse('http://test'));

  final Object? result;
  final calls = <(String, Map<String, Object?>)>[];

  @override
  Future<Object?> callTool(
    String name, [
    Map<String, Object?> arguments = const {},
    String? writeId,
  ]) async {
    calls.add((name, arguments));
    return result;
  }
}
