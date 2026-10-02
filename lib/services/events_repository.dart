import '../models/event.dart';
import '../models/note.dart';
import '../models/recurrence.dart';
import 'mcp_client.dart';
import 'response_cache.dart';

/// Where events come from. The app talks to this rather than to MCP
/// directly so screens can be exercised without a server.
abstract class EventsRepository {
  /// Events that overlap [from] to [to], by start time. With [keep], they
  /// replace the ones kept for [cachedEvents].
  Future<List<Event>> events(DateTime from, DateTime to, {bool keep = false});

  /// What [events] last returned, with `keep`, for [from] to [to], kept
  /// from an earlier run of the app; null if what's kept is for another
  /// time, or there's nothing kept.
  Future<List<Event>?> cachedEvents(DateTime from, DateTime to);

  /// Saves [changes], keyed and encoded as `update_event` takes them, to
  /// [event]. Returns every event the server changed to make room,
  /// [event] included.
  Future<List<Event>> updateEvent(Event event, Map<String, Object?> changes);

  /// The recurring series [id] is, or is one of the events of.
  Future<Recurrence> recurrence(String id);

  /// Saves [changes], keyed as `update_recurrence` takes them, to
  /// [recurrence]: to every event in it, or, given [startingAt] (one of its
  /// events' ids), to that event and the ones after it only. Returns the
  /// edited series, then the part before [startingAt] if it was split off.
  Future<List<Recurrence>> updateRecurrence(
    Recurrence recurrence,
    Map<String, Object?> changes, {
    String? startingAt,
  });
}

/// Reads events via the Time Tracker MCP server's `list_events` tool.
class McpEventsRepository implements EventsRepository {
  McpEventsRepository(this._client, {this._cache});

  final McpClient _client;
  final ResponseCache? _cache;

  /// Holds one call's `min_time`, `max_time` and result.
  static const _cacheKey = 'list_events';

  @override
  Future<List<Event>> events(
    DateTime from,
    DateTime to, {
    bool keep = false,
  }) async {
    final range = {
      'min_time': localIsoTimestamp(from),
      'max_time': localIsoTimestamp(to),
    };
    final result = await _client.callTool('list_events', range);
    final events = _sorted(result);
    if (keep) await _cache?.write(_cacheKey, {...range, 'result': result});
    return events;
  }

  @override
  Future<List<Event>?> cachedEvents(DateTime from, DateTime to) async {
    try {
      final kept = await _cache?.read(_cacheKey) as Map?;
      if (kept == null ||
          kept['min_time'] != localIsoTimestamp(from) ||
          kept['max_time'] != localIsoTimestamp(to)) {
        return null;
      }
      return _sorted(kept['result']);
    } catch (_) {
      return null; // From an older version of the app, perhaps.
    }
  }

  static List<Event> _sorted(Object? result) =>
      (result as List)
          .map((e) => Event.fromJson((e as Map).cast<String, dynamic>()))
          .toList()
        ..sort((a, b) => a.start.compareTo(b.start));

  @override
  Future<Recurrence> recurrence(String id) async {
    final result = await _client.callTool('get_recurrence', {'id': id});
    return Recurrence.fromJson((result as Map).cast<String, dynamic>());
  }

  @override
  Future<List<Recurrence>> updateRecurrence(
    Recurrence recurrence,
    Map<String, Object?> changes, {
    String? startingAt,
  }) async {
    // The server keeps whatever is left out.
    final result = await _client.callTool('update_recurrence', {
      'recurrence': {
        'id': recurrence.id,
        for (final MapEntry(:key, :value) in changes.entries) key: ?value,
      },
      'starting_at_event_id': ?startingAt,
    });
    return [
      for (final r in result as List)
        Recurrence.fromJson((r as Map).cast<String, dynamic>()),
    ];
  }

  @override
  Future<List<Event>> updateEvent(
    Event event,
    Map<String, Object?> changes,
  ) async {
    final result = await _client.callTool('update_event', {
      'event': {...event.toJson(), ...changes},
    });
    return (result as List)
        .map((e) => Event.fromJson((e as Map).cast<String, dynamic>()))
        .toList();
  }
}

/// Keeps events in memory. Used when no server is configured, and in tests.
class InMemoryEventsRepository implements EventsRepository {
  InMemoryEventsRepository([
    List<Event> events = const [],
    List<Recurrence> recurrences = const [],
  ]) : _events = [...events],
       _recurrences = {for (final r in recurrences) r.id: r};

  final List<Event> _events;
  final Map<String, Recurrence> _recurrences;

  /// [startingAt] of each [updateRecurrence], in order.
  final splits = <String?>[];

  @override
  Future<Recurrence> recurrence(String id) async {
    final seriesId = switch (_events.where((e) => e.id == id)) {
      final found when found.isNotEmpty =>
        found.first.properties['recurring_event_id'] as String? ?? id,
      _ => id,
    };
    return _recurrences[seriesId] ??
        (throw StateError("$id isn't part of a recurring series"));
  }

  /// Changes the series itself, without splitting it: in memory, its
  /// events aren't generated from it.
  @override
  Future<List<Recurrence>> updateRecurrence(
    Recurrence recurrence,
    Map<String, Object?> changes, {
    String? startingAt,
  }) async {
    splits.add(startingAt);
    final updated = Recurrence.fromJson({
      ...recurrence.toJson(),
      for (final MapEntry(:key, :value) in changes.entries) key: ?value,
    });
    _recurrences[recurrence.id] = updated;
    return [updated];
  }

  /// Like the server, leaves out cancelled events.
  @override
  Future<List<Event>> events(
    DateTime from,
    DateTime to, {
    bool keep = false,
  }) async =>
      _events
          .where(
            (e) =>
                !e.isCancelled && e.start.isBefore(to) && e.end.isAfter(from),
          )
          .toList()
        ..sort((a, b) => a.start.compareTo(b.start));

  @override
  Future<List<Event>?> cachedEvents(DateTime from, DateTime to) async => null;

  @override
  Future<List<Event>> updateEvent(
    Event event,
    Map<String, Object?> changes,
  ) async {
    final i = _events.indexWhere((e) => e.id == event.id);
    if (i < 0) throw StateError('No event ${event.id}');
    final updated = Event.fromJson({..._events[i].toJson(), ...changes});
    _events[i] = updated;
    return [updated];
  }
}
