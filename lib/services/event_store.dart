import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../models/event.dart';
import 'events_repository.dart';
import 'response_cache.dart';

/// The calendar's events, day by day, kept while the app runs and from
/// run to run, for everything that reads more than a day at a time: the
/// traits' scores, worked out from them, and the Events page, which shows
/// a day from here at once while it asks again.
///
/// [warm] asks for the week either side of today every time the app
/// opens, since those days still change, and for any day further out it
/// needs only if it isn't kept already: a day long past changes little,
/// so it isn't asked for again each time.
class EventStore extends ChangeNotifier {
  EventStore({
    required this.repository,
    this.cache,
    DateTime Function()? clock,
    this.saveDelay = const Duration(seconds: 1),
  }) : clock = clock ?? DateTime.now;

  final EventsRepository repository;

  /// Where the days are kept from run to run; without it, only while the
  /// app runs.
  final ResponseCache? cache;
  final DateTime Function() clock;

  /// How long after a change the days are kept, so a run of changes is
  /// kept once.
  final Duration saveDelay;

  /// How many days either side of today [warm] always asks for.
  static const nearDays = 7;

  static const _cacheKey = 'event_days';

  /// Each day's events, by its date ("2026-10-05"), with when they were
  /// asked for: an event across midnight is in each day it's in.
  final _days = <String, ({DateTime at, List<Event> events})>{};

  /// Counts the changes, for what's worked out from the events to know
  /// when to work it out again.
  int get version => _version;
  int _version = 0;

  late final Future<void> _restored = _restore();
  Future<void>? _warming;
  Timer? _saveTimer;

  static String dayKey(DateTime day) =>
      '${day.year.toString().padLeft(4, '0')}-'
      '${day.month.toString().padLeft(2, '0')}-'
      '${day.day.toString().padLeft(2, '0')}';

  static DateTime _midnight(DateTime t) => DateTime(t.year, t.month, t.day);
  static DateTime _plusDays(DateTime day, int n) =>
      DateTime(day.year, day.month, day.day + n);

  /// Whether [day]'s events are here.
  bool has(DateTime day) => _days.containsKey(dayKey(day));

  /// [day]'s events, if they're here.
  List<Event>? day(DateTime day) => _days[dayKey(day)]?.events;

  /// Every event here that overlaps [from] to [to], each once, by start:
  /// as last asked for, where days disagree.
  List<Event> between(DateTime from, DateTime to) {
    final byId = <Object, ({DateTime at, Event event})>{};
    for (var d = _midnight(from); d.isBefore(to); d = _plusDays(d, 1)) {
      final kept = _days[dayKey(d)];
      if (kept == null) continue;
      for (final e in kept.events) {
        if (!e.start.isBefore(to) || !e.end.isAfter(from)) continue;
        final id = e.id ?? e;
        final had = byId[id];
        if (had == null || kept.at.isAfter(had.at)) {
          byId[id] = (at: kept.at, event: e);
        }
      }
    }
    return [for (final kept in byId.values) kept.event]
      ..sort((a, b) => a.start.compareTo(b.start));
  }

  /// The event here with [id], as last asked for; null if it isn't here.
  Event? event(String id) {
    ({DateTime at, Event event})? found;
    for (final kept in _days.values) {
      for (final e in kept.events) {
        if (e.id == id && (found == null || kept.at.isAfter(found.at))) {
          found = (at: kept.at, event: e);
        }
      }
    }
    return found?.event;
  }

  /// The first and last days here, if any are.
  (DateTime, DateTime)? get span {
    if (_days.isEmpty) return null;
    final keys = _days.keys.toList()..sort();
    return (DateTime.parse(keys.first), DateTime.parse(keys.last));
  }

  /// Whether every day from [from]'s to the one [to] falls in is here.
  bool hasAll(DateTime from, DateTime to) {
    for (var d = _midnight(from); d.isBefore(to); d = _plusDays(d, 1)) {
      if (!has(d)) return false;
    }
    return true;
  }

  /// Asks for every day from [from]'s to the one [to] falls in again.
  Future<void> refresh(DateTime from, DateTime to) async {
    await _restored;
    final last = _midnight(to) == to ? to : _plusDays(_midnight(to), 1);
    _changed(await _fetch(_midnight(from), last));
  }

  /// Keeps [events] as [day]'s, as just asked for.
  void putDay(DateTime day, List<Event> events) {
    _changed(_put(_midnight(day), _plusDays(_midnight(day), 1), events));
  }

  /// Keeps [events] as every day's from [from] to [to] (midnights).
  /// Keeps [events] as the days' from [from] to [to]; returns whether
  /// any day's are new, or differ from what it had.
  bool _put(DateTime from, DateTime to, List<Event> events) {
    final at = clock();
    var changed = false;
    for (var d = from; d.isBefore(to); d = _plusDays(d, 1)) {
      final next = _plusDays(d, 1);
      final key = dayKey(d);
      final day = [
        for (final e in events)
          if (e.start.isBefore(next) && e.end.isAfter(d)) e,
      ];
      if (!changed && !_sameEvents(_days[key]?.events, day)) changed = true;
      _days[key] = (at: at, events: day);
    }
    return changed;
  }

  /// Whether [a] and [b] are the same events, alike in every way.
  static bool _sameEvents(List<Event>? a, List<Event> b) {
    if (a == null || a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!identical(a[i], b[i]) &&
          jsonEncode(a[i].toJson()) != jsonEncode(b[i].toJson())) {
        return false;
      }
    }
    return true;
  }

  /// Takes in [changed], as the server returned them after a save: each
  /// in the days it's in now, and out of those it was in before.
  void putEvents(Iterable<Event> changed) {
    final byId = {
      for (final e in changed)
        if (e.id != null) e.id!: e,
    };
    if (byId.isEmpty) return;
    for (final MapEntry(:key, :value) in _days.entries.toList()) {
      final from = DateTime.parse(key), to = _plusDays(DateTime.parse(key), 1);
      _days[key] = (
        at: value.at,
        events: [
          for (final e in value.events)
            if (!byId.containsKey(e.id)) e,
          for (final e in byId.values)
            if (!e.isCancelled && e.start.isBefore(to) && e.end.isAfter(from))
              e,
        ]..sort((a, b) => a.start.compareTo(b.start)),
      );
    }
    _changed();
  }

  /// Asks for the week either side of today, and for any day from [back]
  /// days before today to [ahead] days after it that isn't here yet. One
  /// at a time: a call while one is under way waits for that one, then
  /// asks for what it didn't.
  Future<void> warm({int back = nearDays, int ahead = nearDays}) async {
    for (var under = _warming; under != null; under = _warming) {
      try {
        await under;
      } catch (_) {
        // That call's to say so; this one asks again.
      }
    }
    final warming = _warming = _warm(back: back, ahead: ahead);
    try {
      await warming;
    } finally {
      if (identical(_warming, warming)) _warming = null;
    }
  }

  Future<void> _warm({required int back, required int ahead}) async {
    await _restored;
    final today = _midnight(clock());
    final nearFrom = _plusDays(today, -nearDays);
    final nearTo = _plusDays(today, nearDays + 1);
    final first = _plusDays(today, -math.max(back, nearDays));
    final last = _plusDays(today, math.max(ahead, nearDays) + 1);
    // What's missing beyond the week either side, in runs of days.
    final runs = <(DateTime, DateTime)>[];
    DateTime? runStart;
    for (var d = first; !d.isAfter(last); d = _plusDays(d, 1)) {
      final near = !d.isBefore(nearFrom) && d.isBefore(nearTo);
      final missing = d.isBefore(last) && !near && !has(d);
      if (missing) {
        runStart ??= d;
      } else if (runStart != null) {
        runs.add((runStart, d));
        runStart = null;
      }
    }
    final changed = await Future.wait([
      _fetch(nearFrom, nearTo),
      for (final (from, to) in runs) _fetch(from, to),
    ]);
    _changed(changed.contains(true));
  }

  /// Asks for [from] to [to]; returns whether anything in them changed.
  Future<bool> _fetch(DateTime from, DateTime to) async {
    final events = await repository.events(from, to);
    return _put(from, to, events);
  }

  /// Keeps the days a little later, as they're fetched again; and, if
  /// what's in them [changed], moves [version] on and tells listeners.
  /// Unchanged, what's worked out from them needn't be again.
  void _changed([bool changed = true]) {
    if (changed) {
      _version++;
      notifyListeners();
    }
    _saveTimer?.cancel();
    if (cache == null) return;
    _saveTimer = Timer(saveDelay, () => unawaited(_save()));
  }

  /// Keeps the days, now: those within a year of today. A background
  /// fetch waits for it, rather than the save a change sets off.
  Future<void> save() {
    _saveTimer?.cancel();
    return _save();
  }

  Future<void> _save() async {
    final oldest = dayKey(_plusDays(_midnight(clock()), -400));
    try {
      await cache?.write(_cacheKey, {
        for (final MapEntry(:key, :value) in _days.entries)
          if (key.compareTo(oldest) >= 0)
            key: {
              'at': value.at.toIso8601String(),
              'events': [for (final e in value.events) e.toJson()],
            },
      });
    } catch (_) {
      // Then they're asked for again next time.
    }
  }

  Future<void> _restore() async {
    try {
      final kept = await cache?.read(_cacheKey);
      if (kept is! Map) return;
      for (final MapEntry(:key, :value) in kept.entries) {
        if (value is! Map || _days.containsKey(key)) continue;
        _days['$key'] = (
          at: DateTime.parse(value['at'] as String),
          events: [
            for (final e in value['events'] as List)
              Event.fromJson((e as Map).cast<String, dynamic>()),
          ],
        );
      }
      if (_days.isNotEmpty) {
        _version++;
        notifyListeners();
      }
    } catch (_) {
      // From an older version of the app, perhaps: asked for again.
    }
  }

  /// Forgets every day, here and kept: on signing out, say.
  Future<void> clear() async {
    await _restored;
    _saveTimer?.cancel();
    _days.clear();
    _version++;
    notifyListeners();
    try {
      await cache?.write(_cacheKey, null);
    } catch (_) {
      // The cache is being cleared anyway.
    }
  }

  /// What was kept from the app's last run, ready.
  Future<void> restored() => _restored;

  @override
  void dispose() {
    _saveTimer?.cancel();
    super.dispose();
  }
}
