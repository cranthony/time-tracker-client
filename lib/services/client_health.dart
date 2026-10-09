import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../outbox/store_lock.dart';
import 'mcp_client.dart';

/// Who made a tool call: the app, or its Android background task.
enum CallOrigin {
  app('The app'),
  background('The background task');

  const CallOrigin(this.label);
  final String label;
}

/// One tool call the app made: when it ended, how long it took -- retries,
/// sign-in and the network included -- whether it succeeded, and who made
/// it.
class ClientCall {
  const ClientCall({
    required this.tool,
    required this.at,
    required this.ms,
    this.ok = true,
    this.origin = CallOrigin.app,
  });

  final String tool;
  final DateTime at;
  final int ms;
  final bool ok;
  final CallOrigin origin;

  List<Object> toJson() => [
    at.millisecondsSinceEpoch,
    ms,
    ok ? 1 : 0,
    origin.index,
  ];

  static ClientCall? fromJson(String tool, Object? json) {
    if (json is! List || json.length < 4) return null;
    final [at, ms, ok, origin, ...] = json;
    if (at is! int || ms is! int || ok is! int || origin is! int) return null;
    return ClientCall(
      tool: tool,
      at: DateTime.fromMillisecondsSinceEpoch(at, isUtc: true),
      ms: ms,
      ok: ok == 1,
      origin: CallOrigin.values[origin.clamp(0, CallOrigin.values.length - 1)],
    );
  }
}

/// An error, in full: a tool call that failed ([tool] set), or one the
/// app didn't catch, with its [stack].
class ClientError {
  const ClientError({
    required this.at,
    required this.origin,
    required this.message,
    this.tool,
    this.kind,
    this.stack,
  });

  final DateTime at;
  final CallOrigin origin;

  /// The tool whose call failed; null for an error the app didn't catch.
  final String? tool;

  /// What sort of error it was: its type -- "McpException".
  final String? kind;
  final String message;
  final String? stack;

  Map<String, Object?> toJson() => {
    'at': at.millisecondsSinceEpoch,
    'origin': origin.index,
    'message': message,
    'tool': ?tool,
    'kind': ?kind,
    'stack': ?stack,
  };

  static ClientError? fromJson(Object? json) {
    if (json is! Map) return null;
    final at = json['at'], origin = json['origin'], message = json['message'];
    if (at is! int || origin is! int || message is! String) return null;
    return ClientError(
      at: DateTime.fromMillisecondsSinceEpoch(at, isUtc: true),
      origin: CallOrigin.values[origin.clamp(0, CallOrigin.values.length - 1)],
      message: message,
      tool: json['tool'] as String?,
      kind: json['kind'] as String?,
      stack: json['stack'] as String?,
    );
  }
}

/// How many changes were waiting to save, in each outbox, at [at].
class QueueSample {
  const QueueSample({
    required this.at,
    this.notes = 0,
    this.actions = 0,
    this.events = 0,
  });

  final DateTime at;
  final int notes;
  final int actions;
  final int events;

  int get total => notes + actions + events;

  List<int> toJson() => [at.millisecondsSinceEpoch, notes, actions, events];

  static QueueSample? fromJson(Object? json) {
    if (json is! List || json.length < 4 || json.any((v) => v is! int)) {
      return null;
    }
    final [at, notes, actions, events, ...] = json.cast<int>();
    return QueueSample(
      at: DateTime.fromMillisecondsSinceEpoch(at, isUtc: true),
      notes: notes,
      actions: actions,
      events: events,
    );
  }
}

/// The app's own health: each tool's last calls, the last errors, and how
/// long the outboxes' queues were, over time.
class ClientHealth {
  const ClientHealth({
    this.calls = const {},
    this.errors = const [],
    this.queue = const [],
  });

  /// By tool, oldest first: the last [ClientHealthRecorder.keepCalls] of
  /// each.
  final Map<String, List<ClientCall>> calls;

  /// Oldest first: the last [ClientHealthRecorder.keepErrors].
  final List<ClientError> errors;

  /// Oldest first: the last [ClientHealthRecorder.keepQueue] changes.
  final List<QueueSample> queue;

  bool get isEmpty => calls.isEmpty && errors.isEmpty && queue.isEmpty;

  Map<String, Object?> toJson() => {
    'calls': {
      for (final MapEntry(:key, :value) in calls.entries)
        key: [for (final c in value) c.toJson()],
    },
    'errors': [for (final e in errors) e.toJson()],
    'queue': [for (final q in queue) q.toJson()],
  };

  factory ClientHealth.fromJson(Object? json) {
    if (json is! Map) return const ClientHealth();
    final calls = json['calls'];
    return ClientHealth(
      calls: {
        if (calls is Map)
          for (final MapEntry(:key, :value) in calls.entries)
            '$key': [
              if (value is List)
                for (final c in value) ?ClientCall.fromJson('$key', c),
            ],
      },
      errors: [
        for (final e in json['errors'] as List? ?? const [])
          ?ClientError.fromJson(e),
      ],
      queue: [
        for (final q in json['queue'] as List? ?? const [])
          ?QueueSample.fromJson(q),
      ],
    );
  }

  /// This, with [more] after it, each kept to its latest.
  ClientHealth plus(ClientHealth more) {
    List<T> latest<T>(List<T> a, List<T> b, int keep) {
      final all = [...a, ...b];
      return all.sublist(max(0, all.length - keep));
    }

    return ClientHealth(
      calls: {
        for (final tool in {...calls.keys, ...more.calls.keys})
          tool: latest(
            calls[tool] ?? const [],
            more.calls[tool] ?? const [],
            ClientHealthRecorder.keepCalls,
          ),
      },
      errors: latest(errors, more.errors, ClientHealthRecorder.keepErrors),
      queue: latest(queue, more.queue, ClientHealthRecorder.keepQueue),
    );
  }
}

/// Where [ClientHealth] is kept: read, changed and written back whole,
/// with no other change in between -- the app's and its background task's
/// recorders both write it.
abstract class ClientHealthStore {
  Future<ClientHealth> read();

  /// Applies [change] to what's kept, and keeps what it gives.
  Future<void> update(ClientHealth Function(ClientHealth kept) change);
}

/// Kept in SharedPreferences, shared by the app and its background task
/// (which runs in another isolate of the app's process), each change
/// holding a lock both share.
class PrefsClientHealthStore implements ClientHealthStore {
  PrefsClientHealthStore({SharedPreferencesAsync? prefs})
    : _prefs = prefs ?? SharedPreferencesAsync();

  final SharedPreferencesAsync _prefs;
  static const _key = 'client_health';
  final StoreLock _lock = IsolateStoreLock.forKey(_key);

  @override
  Future<ClientHealth> read() async {
    try {
      final json = await _prefs.getString(_key);
      return json == null
          ? const ClientHealth()
          : ClientHealth.fromJson(jsonDecode(json));
    } catch (_) {
      return const ClientHealth(); // Unreadable: start again.
    }
  }

  @override
  Future<void> update(ClientHealth Function(ClientHealth kept) change) =>
      _lock.hold((keepUntil) async {
        final next = change(await read());
        final saving = _prefs.setString(_key, jsonEncode(next.toJson()));
        keepUntil(saving);
        await saving;
      }, wait: const Duration(seconds: 10));
}

/// Kept in memory: for the offline demo, and tests.
class InMemoryClientHealthStore implements ClientHealthStore {
  InMemoryClientHealthStore([this.kept = const ClientHealth()]);

  ClientHealth kept;

  @override
  Future<ClientHealth> read() async => kept;

  @override
  Future<void> update(ClientHealth Function(ClientHealth kept) change) async =>
      kept = change(kept);
}

/// Records the app's health -- each tool call ([McpClient] tells it), each
/// error, and each change in how many changes wait to save -- as [origin]:
/// in memory, a few microseconds' work, then into [store] [flushDelay]
/// later, or at [flush].
class ClientHealthRecorder extends ChangeNotifier {
  ClientHealthRecorder({
    required this.origin,
    ClientHealthStore? store,
    this.flushDelay = const Duration(seconds: 3),
    DateTime Function()? clock,
  }) : store = store ?? PrefsClientHealthStore(),
       _clock = clock ?? DateTime.now;

  static const keepCalls = 100;
  static const keepErrors = 20;
  static const keepQueue = 200;

  final CallOrigin origin;
  final ClientHealthStore store;
  final Duration flushDelay;
  final DateTime Function() _clock;

  /// What's been recorded and not yet kept.
  ClientHealth _pending = const ClientHealth();
  Timer? _timer;
  Future<void> _flushing = Future.value();
  QueueSample? _lastQueue;

  DateTime _now() => _clock().toUtc();

  /// A call of [tool] that took [ms], and failed with [error] if it did.
  void recordCall(String tool, int ms, {Object? error}) {
    final call = ClientCall(
      tool: tool,
      at: _now(),
      ms: ms,
      ok: error == null,
      origin: origin,
    );
    _add(
      ClientHealth(
        calls: {
          tool: [call],
        },
      ),
    );
    if (error != null) recordError(error, tool: tool);
  }

  /// [error], in full: [tool]'s, if a call of it failed; else one the app
  /// didn't catch, with its [stack].
  void recordError(Object error, {String? tool, StackTrace? stack}) {
    final message = switch (error) {
      McpException(:final message, :final serverMessage?)
          when serverMessage != message =>
        '$message\n\n$serverMessage',
      _ => '$error',
    };
    _add(
      ClientHealth(
        errors: [
          ClientError(
            at: _now(),
            origin: origin,
            tool: tool,
            kind: error.runtimeType.toString(),
            message: message,
            stack: stack?.toString(),
          ),
        ],
      ),
    );
  }

  /// How many changes wait in each outbox now -- kept if it's changed.
  void recordQueue({int notes = 0, int actions = 0, int events = 0}) {
    final last = _lastQueue;
    if (last != null &&
        last.notes == notes &&
        last.actions == actions &&
        last.events == events) {
      return;
    }
    final sample = QueueSample(
      at: _now(),
      notes: notes,
      actions: actions,
      events: events,
    );
    _lastQueue = sample;
    _add(ClientHealth(queue: [sample]));
  }

  /// Records each outbox's length as it changes: those waiting, refused
  /// included.
  void watchQueues({
    Listenable? notes,
    int Function()? notesCount,
    Listenable? actions,
    int Function()? actionsCount,
    Listenable? events,
    int Function()? eventsCount,
  }) {
    void sample() => recordQueue(
      notes: notesCount?.call() ?? 0,
      actions: actionsCount?.call() ?? 0,
      events: eventsCount?.call() ?? 0,
    );
    for (final l in [notes, actions, events]) {
      l?.addListener(sample);
    }
  }

  void _add(ClientHealth more) {
    _pending = _pending.plus(more);
    notifyListeners();
    _timer ??= Timer(flushDelay, () {
      _timer = null;
      unawaited(flush());
    });
  }

  /// Keeps what's been recorded, in [store]. Best effort: a failure keeps
  /// it for next time.
  Future<void> flush() {
    _timer?.cancel();
    _timer = null;
    return _flushing = _flushing.then((_) async {
      final pending = _pending;
      if (pending.isEmpty) return;
      _pending = const ClientHealth();
      try {
        await store.update((kept) => kept.plus(pending));
      } catch (e) {
        debugPrint('Health not kept: $e');
        _pending = pending.plus(_pending);
      }
    });
  }

  /// What's kept, with what's yet to be: by both the app and its
  /// background task.
  Future<ClientHealth> read() async => (await store.read()).plus(_pending);

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
