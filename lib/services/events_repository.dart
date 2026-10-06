import '../models/event.dart';
import '../models/note.dart';
import '../models/recurrence.dart';
import '../models/repeat.dart';
import 'mcp_client.dart';
import 'response_cache.dart';

/// The fields `update_event` and `update_recurrence` can remove, by
/// listing them in `clear_fields` (time-tracking-google-calendar-mcp#119).
/// Sent as null, any other field is kept as it was, so a change to null
/// clears one of these and is ignored for the rest. Not summary, start or
/// end, which every event has, nor action_ids, whose [] means no
/// actions. facts are what compaction established about it, and judgments
/// the assistant's ratings of it against people's traits.
const clearableFields = {
  'facts',
  'judgments',
  'priority',
  'description',
  'location',
};

/// [changes]' fields to clear: those changed to null that can be.
List<String> _cleared(Map<String, Object?> changes) => [
  for (final MapEntry(:key, :value) in changes.entries)
    if (value == null && clearableFields.contains(key)) key,
];

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
  /// [event]. Returns the events the server changed: [event]. The server
  /// moves nothing else to make room, and refuses a change that would
  /// overlap another event -- or, without [allowCompactedChanges] (only
  /// once the user has approved changing history), one to an event
  /// compaction settled.
  Future<List<Event>> updateEvent(
    Event event,
    Map<String, Object?> changes, {
    bool allowCompactedChanges = false,
  });

  /// Creates an event with [fields], keyed and encoded as `create_event`
  /// takes them; those that are null are left out. Returns the events the
  /// server changed: the new one. It's refused if it would overlap
  /// another event.
  Future<List<Event>> createEvent(Map<String, Object?> fields);

  /// Cancels [event], with `delete_event` -- the one way the server
  /// cancels an event (`update_event` won't). With
  /// [countsAgainstFollowThrough], the server records it against the
  /// follow-through of everyone a follow-through trait tracks it for: a
  /// commitment dropped, not just a change of plan. Returns the events the
  /// server changed, [event] (cancelled) included.
  Future<List<Event>> deleteEvent(
    Event event, {
    bool countsAgainstFollowThrough = false,
    bool allowCompactedChanges = false,
  });

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

  /// Deletes [recurrence]'s events from [startingAt] (one of its events'
  /// ids) on, ending the series just before it; the events before it are
  /// kept. Returns what's left of the series: nothing if [startingAt] was
  /// its first event, else the series, now ending before it.
  ///
  /// There's deliberately no way here to delete a series whole. The
  /// server's `delete_recurrence` can, but that cancels every one of its
  /// events, past ones included: each then counts against its goals'
  /// follow-through as a cancellation, and its time no longer counts as
  /// spent. Someone deleting a series almost always means it won't happen
  /// any more, not that it never should have, which is what deleting from
  /// an event on says; deleting from its first event deletes it all.
  Future<List<Recurrence>> deleteRecurrence(
    Recurrence recurrence, {
    required String startingAt,
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
    final cleared = _cleared(changes);
    // The server keeps whatever is left out, but clear_fields.
    final result = await _client.callTool('update_recurrence', {
      'recurrence': {
        'id': recurrence.id,
        for (final MapEntry(:key, :value) in changes.entries) key: ?value,
        // Goals sent are set, not inferred from a label.
        if (changes.containsKey('action_ids')) 'actions_from_label': false,
      },
      'starting_at_event_id': ?startingAt,
      if (cleared.isNotEmpty) 'clear_fields': cleared,
    });
    return [
      for (final r in result as List)
        Recurrence.fromJson((r as Map).cast<String, dynamic>()),
    ];
  }

  @override
  Future<List<Recurrence>> deleteRecurrence(
    Recurrence recurrence, {
    required String startingAt,
  }) async {
    final result = await _client.callTool('delete_recurrence', {
      'id': recurrence.id,
      'starting_at_event_id': startingAt,
    });
    return [
      for (final r in result as List)
        Recurrence.fromJson((r as Map).cast<String, dynamic>()),
    ];
  }

  @override
  Future<List<Event>> createEvent(Map<String, Object?> fields) async {
    final result = await _client.callTool('create_event', {
      'events': [
        {for (final MapEntry(:key, :value) in fields.entries) key: ?value},
      ],
    });
    return _changed(result);
  }

  @override
  Future<List<Event>> deleteEvent(
    Event event, {
    bool countsAgainstFollowThrough = false,
    bool allowCompactedChanges = false,
  }) async {
    final result = await _client.callTool('delete_event', {
      'cancels': [
        {
          'event_id': event.id,
          'counts_against_follow_through': countsAgainstFollowThrough,
        },
      ],
      if (allowCompactedChanges) 'allow_compacted_changes': true,
    });
    return _changed(result);
  }

  @override
  Future<List<Event>> updateEvent(
    Event event,
    Map<String, Object?> changes, {
    bool allowCompactedChanges = false,
  }) async {
    final result = await _client.callTool('update_event', {
      'updates': [
        {
          'event': {
            ...event.toJson(),
            ...changes,
            // Goals sent are set, not inferred from a label; left alone,
            // the server keeps inferred ones inferred.
            if (changes.containsKey('action_ids')) 'actions_from_label': false,
          },
          // The event's fields sent as null are kept; these are removed.
          if (_cleared(changes) case final cleared when cleared.isNotEmpty)
            'clear_fields': cleared,
        },
      ],
      if (allowCompactedChanges) 'allow_compacted_changes': true,
    });
    return _changed(result);
  }
}

/// The events a batch of changes (`create_event`, `update_event`,
/// `delete_event`) changed.
List<Event> _changed(Object? result) => [
  for (final e in (result as Map)['events'] as List)
    Event.fromJson((e as Map).cast<String, dynamic>()),
];

/// Whether [error] is the server refusing to change history -- an event
/// compaction settled -- without the user's approval.
bool isHistoryRefusal(Object error) =>
    error is McpException && error.message.contains('allow_compacted_changes');

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
      for (final MapEntry(:key, :value) in changes.entries)
        if (value != null || clearableFields.contains(key)) key: value,
      if (changes['repeat'] case final Map repeat)
        'schedule': Repeat.fromJson(repeat.cast()).describe(),
    });
    _recurrences[recurrence.id] = updated;
    return [updated];
  }

  /// Drops the series' events from [startingAt]'s start on. The series is
  /// dropped too if none are left before it; otherwise it's kept as it
  /// was, since in memory its events aren't generated from it.
  @override
  Future<List<Recurrence>> deleteRecurrence(
    Recurrence recurrence, {
    required String startingAt,
  }) async {
    bool inSeries(Event e) =>
        e.properties['recurring_event_id'] == recurrence.id;
    final from = _events.firstWhere((e) => e.id == startingAt).start;
    _events.removeWhere((e) => inSeries(e) && !e.start.isBefore(from));
    if (from.isAfter(recurrence.start) && _events.any(inSeries)) {
      return [recurrence];
    }
    _recurrences.remove(recurrence.id);
    return [];
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

  /// The ids [createEvent] has given, to give the next a new one.
  int _created = 0;

  @override
  Future<List<Event>> createEvent(Map<String, Object?> fields) async {
    final created = Event.fromJson({
      for (final MapEntry(:key, :value) in fields.entries) key: ?value,
      'id': 'new-${++_created}',
    });
    _events.add(created);
    return [created];
  }

  /// Each event [deleteEvent] cancelled, by id, with whether it counted
  /// against follow-through.
  final deleted = <(String?, bool)>[];

  @override
  Future<List<Event>> deleteEvent(
    Event event, {
    bool countsAgainstFollowThrough = false,
    bool allowCompactedChanges = false,
  }) async {
    final i = _events.indexWhere((e) => e.id == event.id);
    if (i < 0) throw StateError('No event ${event.id}');
    deleted.add((event.id, countsAgainstFollowThrough));
    final cancelled = Event.fromJson({
      ..._events[i].toJson(),
      'is_cancelled': true,
    });
    _events[i] = cancelled;
    return [cancelled];
  }

  @override
  Future<List<Event>> updateEvent(
    Event event,
    Map<String, Object?> changes, {
    bool allowCompactedChanges = false,
  }) async {
    final i = _events.indexWhere((e) => e.id == event.id);
    if (i < 0) throw StateError('No event ${event.id}');
    final updated = Event.fromJson({
      ..._events[i].toJson(),
      ...changes,
      if (changes.containsKey('action_ids')) 'actions_from_label': false,
    });
    _events[i] = updated;
    return [updated];
  }
}
