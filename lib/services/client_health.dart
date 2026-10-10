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

/// Work the app does on the device that can hold up the screen, timed
/// as it's done (see `timed` in work_timing.dart).
enum WorkKind {
  traitScores('Trait scores'),
  actionTime('Action time'),
  peopleTime('People time'),
  planRebuild('Plan rebuild');

  const WorkKind(this.label);
  final String label;
}

/// One run of [kind]'s work: when it ended, how long it took, and -- for
/// work done again only when what it's from changes -- [why].
class WorkSample {
  const WorkSample({
    required this.kind,
    required this.at,
    required this.us,
    this.why,
  });

  final WorkKind kind;
  final DateTime at;

  /// How long it took, in microseconds.
  final int us;
  final String? why;

  double get ms => us / 1000;

  List<Object> toJson() => [at.millisecondsSinceEpoch, us, ?why];

  static WorkSample? fromJson(WorkKind kind, Object? json) {
    if (json is! List || json.length < 2) return null;
    final [at, us, ...rest] = json;
    if (at is! int || us is! int) return null;
    final why = rest.firstOrNull;
    return WorkSample(
      kind: kind,
      at: DateTime.fromMillisecondsSinceEpoch(at, isUtc: true),
      us: us,
      why: why is String ? why : null,
    );
  }
}

/// A frame that took longer than [SlowFrame.budget] to build and draw:
/// when, how long in all and in each, and whether Plan was open.
class SlowFrame {
  const SlowFrame({
    required this.at,
    required this.us,
    this.buildUs = 0,
    this.rasterUs = 0,
    this.plan = false,
  });

  /// A frame's time at 60 frames a second.
  static const budget = Duration(microseconds: 16667);

  final DateTime at;

  /// From the frame's start to its drawing's end, in microseconds.
  final int us;
  final int buildUs;
  final int rasterUs;
  final bool plan;

  double get ms => us / 1000;

  List<int> toJson() => [
    at.millisecondsSinceEpoch,
    us,
    buildUs,
    rasterUs,
    plan ? 1 : 0,
  ];

  static SlowFrame? fromJson(Object? json) {
    if (json is! List || json.length < 5 || json.any((v) => v is! int)) {
      return null;
    }
    final [at, us, build, raster, plan, ...] = json.cast<int>();
    return SlowFrame(
      at: DateTime.fromMillisecondsSinceEpoch(at, isUtc: true),
      us: us,
      buildUs: build,
      rasterUs: raster,
      plan: plan == 1,
    );
  }
}

/// A visit to Plan, from opening it to everything loaded: how long in
/// all, and the device's own [work] in it, by kind, each kind's time its
/// own (none of it twice, though one kind's done inside another's). The
/// rest is waiting, on the server mostly.
class PlanVisit {
  const PlanVisit({required this.at, required this.us, this.work = const {}});

  /// When it began.
  final DateTime at;
  final int us;
  final Map<WorkKind, int> work;

  double get ms => us / 1000;
  double msOf(WorkKind kind) => (work[kind] ?? 0) / 1000;

  /// What wasn't the device's own work, in ms.
  double get waitingMs =>
      max(0, us - work.values.fold(0, (a, b) => a + b)) / 1000;

  List<int> toJson() => [
    at.millisecondsSinceEpoch,
    us,
    for (final kind in WorkKind.values) work[kind] ?? 0,
  ];

  static PlanVisit? fromJson(Object? json) {
    if (json is! List || json.length < 2 || json.any((v) => v is! int)) {
      return null;
    }
    final values = json.cast<int>();
    return PlanVisit(
      at: DateTime.fromMillisecondsSinceEpoch(values[0], isUtc: true),
      us: values[1],
      work: {
        for (final (i, kind) in WorkKind.values.indexed)
          if (i + 2 < values.length && values[i + 2] > 0) kind: values[i + 2],
      },
    );
  }
}

/// The app's own health: each tool's last calls, the last errors, how
/// long the outboxes' queues were, over time, and how long its own work
/// took -- each kind's last runs, its slow frames, and its visits to Plan.
class ClientHealth {
  const ClientHealth({
    this.calls = const {},
    this.errors = const [],
    this.queue = const [],
    this.work = const {},
    this.frames = const [],
    this.visits = const [],
  });

  /// By tool, oldest first: the last [ClientHealthRecorder.keepCalls] of
  /// each.
  final Map<String, List<ClientCall>> calls;

  /// Oldest first: the last [ClientHealthRecorder.keepErrors].
  final List<ClientError> errors;

  /// Oldest first: the last [ClientHealthRecorder.keepQueue] changes.
  final List<QueueSample> queue;

  /// By kind, oldest first: the last [ClientHealthRecorder.keepWork] of
  /// each.
  final Map<WorkKind, List<WorkSample>> work;

  /// Oldest first: the last [ClientHealthRecorder.keepFrames].
  final List<SlowFrame> frames;

  /// Oldest first: the last [ClientHealthRecorder.keepVisits].
  final List<PlanVisit> visits;

  bool get isEmpty =>
      calls.isEmpty &&
      errors.isEmpty &&
      queue.isEmpty &&
      work.isEmpty &&
      frames.isEmpty &&
      visits.isEmpty;

  Map<String, Object?> toJson() => {
    'calls': {
      for (final MapEntry(:key, :value) in calls.entries)
        key: [for (final c in value) c.toJson()],
    },
    'errors': [for (final e in errors) e.toJson()],
    'queue': [for (final q in queue) q.toJson()],
    if (work.isNotEmpty)
      'work': {
        for (final MapEntry(:key, :value) in work.entries)
          key.name: [for (final w in value) w.toJson()],
      },
    if (frames.isNotEmpty) 'frames': [for (final f in frames) f.toJson()],
    if (visits.isNotEmpty) 'visits': [for (final v in visits) v.toJson()],
  };

  factory ClientHealth.fromJson(Object? json) {
    if (json is! Map) return const ClientHealth();
    final calls = json['calls'];
    final work = json['work'];
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
      work: {
        if (work is Map)
          for (final kind in WorkKind.values)
            if (work[kind.name] case final List samples)
              kind: [for (final w in samples) ?WorkSample.fromJson(kind, w)],
      },
      frames: [
        for (final f in json['frames'] as List? ?? const [])
          ?SlowFrame.fromJson(f),
      ],
      visits: [
        for (final v in json['visits'] as List? ?? const [])
          ?PlanVisit.fromJson(v),
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
      work: {
        for (final kind in {...work.keys, ...more.work.keys})
          kind: latest(
            work[kind] ?? const [],
            more.work[kind] ?? const [],
            ClientHealthRecorder.keepWork,
          ),
      },
      frames: latest(frames, more.frames, ClientHealthRecorder.keepFrames),
      visits: latest(visits, more.visits, ClientHealthRecorder.keepVisits),
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
  static const keepWork = 100;
  static const keepFrames = 300;
  static const keepVisits = 50;

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

  /// A run of [kind]'s work that took [us] microseconds, done for [why].
  void recordWork(WorkKind kind, int us, {String? why}) => _add(
    ClientHealth(
      work: {
        kind: [WorkSample(kind: kind, at: _now(), us: us, why: why)],
      },
    ),
  );

  /// A frame slower than [SlowFrame.budget].
  void recordFrame(SlowFrame frame) => _add(ClientHealth(frames: [frame]));

  /// A visit to Plan, settled.
  void recordVisit(PlanVisit visit) => _add(ClientHealth(visits: [visit]));

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
