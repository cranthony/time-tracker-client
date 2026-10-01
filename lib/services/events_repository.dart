import '../models/event.dart';
import '../models/note.dart';
import 'mcp_client.dart';

/// Where events come from. The app talks to this rather than to MCP
/// directly so screens can be exercised without a server.
abstract class EventsRepository {
  /// Events that overlap [from] to [to], by start time.
  Future<List<Event>> events(DateTime from, DateTime to);
}

/// Reads events via the Time Tracker MCP server's `list_events` tool.
class McpEventsRepository implements EventsRepository {
  McpEventsRepository(this._client);

  final McpClient _client;

  @override
  Future<List<Event>> events(DateTime from, DateTime to) async {
    final result = await _client.callTool('list_events', {
      'min_time': localIsoTimestamp(from),
      'max_time': localIsoTimestamp(to),
    });
    return (result as List)
        .map((e) => Event.fromJson((e as Map).cast<String, dynamic>()))
        .toList()
      ..sort((a, b) => a.start.compareTo(b.start));
  }
}

/// Keeps events in memory. Used when no server is configured, and in tests.
class InMemoryEventsRepository implements EventsRepository {
  InMemoryEventsRepository([List<Event> events = const []])
    : _events = [...events];

  final List<Event> _events;

  @override
  Future<List<Event>> events(DateTime from, DateTime to) async =>
      _events.where((e) => e.start.isBefore(to) && e.end.isAfter(from)).toList()
        ..sort((a, b) => a.start.compareTo(b.start));
}
