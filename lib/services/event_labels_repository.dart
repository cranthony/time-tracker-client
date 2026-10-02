import '../models/event_label.dart';
import 'mcp_client.dart';
import 'response_cache.dart';

/// Where event labels come from. The app talks to this rather than to MCP
/// directly so screens can be exercised without a server.
abstract class EventLabelsRepository {
  /// Every event label, by priority (labels without one last), then name.
  Future<List<EventLabel>> labels();

  /// What [labels] last returned, kept from an earlier run of the app;
  /// null if there's nothing kept.
  Future<List<EventLabel>?> cachedLabels();

  /// Saves [changes], keyed as `update_event_label` takes them, to
  /// [label]; a null clears that property. Returns every label, as
  /// [labels] does.
  Future<List<EventLabel>> updateLabel(
    EventLabel label,
    Map<String, Object?> changes,
  );
}

/// Reads event labels via the Time Tracker MCP server.
///
/// The server has no read-only way to list labels, so this calls
/// `sync_event_labels_from_sheet`, which returns them. With no sheet edits
/// pending that changes nothing; otherwise it applies them, including
/// deleting any label the sheet no longer has.
class McpEventLabelsRepository implements EventLabelsRepository {
  McpEventLabelsRepository(this._client, {this._cache});

  final McpClient _client;
  final ResponseCache? _cache;

  static const _cacheKey = 'event_labels';

  @override
  Future<List<EventLabel>> labels() async =>
      _keep(await _client.callTool('sync_event_labels_from_sheet'));

  @override
  Future<List<EventLabel>?> cachedLabels() async {
    try {
      final result = await _cache?.read(_cacheKey);
      return result == null ? null : _sorted(result);
    } catch (_) {
      return null; // From an older version of the app, perhaps.
    }
  }

  @override
  Future<List<EventLabel>> updateLabel(
    EventLabel label,
    Map<String, Object?> changes,
  ) async {
    // The server keeps whatever is left out or null, and clears what
    // clear_fields names.
    final clear = [
      for (final MapEntry(:key, :value) in changes.entries)
        if (value == null) key,
    ];
    final result = await _client.callTool('update_event_label', {
      'label': {
        'id': label.id,
        for (final MapEntry(:key, :value) in changes.entries) key: ?value,
      },
      if (clear.isNotEmpty) 'clear_fields': clear,
    });
    return _keep(result);
  }

  /// Every label, from [result], which is also cached.
  Future<List<EventLabel>> _keep(Object? result) async {
    final labels = _sorted(result);
    await _cache?.write(_cacheKey, result);
    return labels;
  }

  static List<EventLabel> _sorted(Object? result) => sortLabels(
    (result as List)
        .map((e) => EventLabel.fromJson((e as Map).cast<String, dynamic>()))
        .toList(),
  );
}

/// Keeps event labels in memory. Used when no server is configured, and in
/// tests.
class InMemoryEventLabelsRepository implements EventLabelsRepository {
  InMemoryEventLabelsRepository([List<EventLabel> labels = const []])
    : _labels = [...labels];

  final List<EventLabel> _labels;

  @override
  Future<List<EventLabel>> labels() async => sortLabels([..._labels]);

  @override
  Future<List<EventLabel>?> cachedLabels() async => null;

  @override
  Future<List<EventLabel>> updateLabel(
    EventLabel label,
    Map<String, Object?> changes,
  ) async {
    final i = _labels.indexWhere((l) => l.id == label.id);
    if (i < 0) throw StateError('No label ${label.id}');
    final old = _labels[i];
    _labels[i] = EventLabel.fromJson({
      ...old.properties,
      'id': old.id,
      'name': old.name,
      'background_color': old.backgroundColor,
      'priority': old.priority,
      'fixed_time': old.fixedTime,
      'note': old.note,
      ...changes,
    });
    return labels();
  }
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
