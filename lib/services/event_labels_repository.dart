import '../models/event_label.dart';
import 'mcp_client.dart';

/// Where event labels come from. The app talks to this rather than to MCP
/// directly so screens can be exercised without a server.
abstract class EventLabelsRepository {
  /// Every event label, by priority (labels without one last), then name.
  Future<List<EventLabel>> labels();
}

/// Reads event labels via the Time Tracker MCP server.
///
/// The server has no read-only way to list labels, so this calls
/// `sync_event_labels_from_sheet`, which returns them. With no sheet edits
/// pending that changes nothing; otherwise it applies them, including
/// deleting any label the sheet no longer has.
class McpEventLabelsRepository implements EventLabelsRepository {
  McpEventLabelsRepository(this._client);

  final McpClient _client;

  @override
  Future<List<EventLabel>> labels() async {
    final result = await _client.callTool('sync_event_labels_from_sheet');
    return sortLabels(
      (result as List)
          .map((e) => EventLabel.fromJson((e as Map).cast<String, dynamic>()))
          .toList(),
    );
  }
}

/// Keeps event labels in memory. Used when no server is configured, and in
/// tests.
class InMemoryEventLabelsRepository implements EventLabelsRepository {
  InMemoryEventLabelsRepository([List<EventLabel> labels = const []])
    : _labels = [...labels];

  final List<EventLabel> _labels;

  @override
  Future<List<EventLabel>> labels() async => sortLabels([..._labels]);
}

/// Sorts [labels] in place, as [EventLabelsRepository.labels] returns
/// them, and returns it.
List<EventLabel> sortLabels(List<EventLabel> labels) => labels
  ..sort((a, b) {
    final byPriority = switch ((a.priority, b.priority)) {
      (null, null) => 0,
      (null, _) => 1,
      (_, null) => -1,
      (final x?, final y?) => x.compareTo(y),
    };
    if (byPriority != 0) return byPriority;
    return (a.name ?? '').toLowerCase().compareTo((b.name ?? '').toLowerCase());
  });
