import 'package:flutter/scheduler.dart';

import 'client_health.dart';

/// Where [timed] work, slow frames and visits to Plan are recorded; set
/// as the app starts. Without one, they're timed and not kept.
ClientHealthRecorder? workRecorder;

/// How much of the run of [timed] work going on now was spent in work
/// [timed] inside it, in microseconds: taken from its own time, so a visit
/// counts none of it twice.
int _nestedUs = 0;

/// Runs [work], timing it as [kind]'s, and records it -- with [why], if
/// it says -- and adds it to the visit to Plan under way, if one is.
T timed<T>(WorkKind kind, T Function() work, {String? Function()? why}) {
  final outer = _nestedUs;
  _nestedUs = 0;
  final watch = Stopwatch()..start();
  try {
    return work();
  } finally {
    watch.stop();
    final us = watch.elapsedMicroseconds;
    PlanVisitTimer._current?._add(kind, us - _nestedUs);
    _nestedUs = outer + us;
    workRecorder?.recordWork(kind, us, why: why?.call());
  }
}

/// Records a run of [kind]'s work, timed some other way, that took [us]:
/// done off the UI thread unless it was [blocking], when it's the visit
/// to Plan under way's too, if one is.
void recordWork(WorkKind kind, int us, {String? why, bool blocking = true}) {
  if (blocking) PlanVisitTimer._current?._add(kind, us);
  workRecorder?.recordWork(kind, us, why: why);
}

/// Times a visit to Plan, from [PlanVisitTimer.start] to [finish]: how
/// long in all, and the [timed] work in it.
class PlanVisitTimer {
  PlanVisitTimer.start() : _at = DateTime.now().toUtc() {
    _current = this;
  }

  /// The visit under way, if one is.
  static PlanVisitTimer? _current;

  /// How many Plan pages are open: frames while one is are marked so.
  static int open = 0;

  final DateTime _at;
  final _watch = Stopwatch()..start();
  final _work = <WorkKind, int>{};
  bool _done = false;

  void _add(WorkKind kind, int us) =>
      _work[kind] = (_work[kind] ?? 0) + (us < 0 ? 0 : us);

  /// Ends the visit, once, and records it.
  void finish() {
    if (_done) return;
    _done = true;
    _watch.stop();
    if (identical(_current, this)) _current = null;
    workRecorder?.recordVisit(
      PlanVisit(at: _at, us: _watch.elapsedMicroseconds, work: {..._work}),
    );
  }
}

/// How many pages showing the slow frames are open: while one is, frames
/// aren't recorded. Its own drawing of them would be, each drawn again as
/// it's recorded -- on and on.
int framesPaused = 0;

/// Records every frame slower than [SlowFrame.budget], from now on, as
/// Flutter reports their timings -- but while [framesPaused].
void watchFrames() => SchedulerBinding.instance.addTimingsCallback((timings) {
  final recorder = workRecorder;
  if (recorder == null || framesPaused > 0) return;
  // Reported in batches, soon after; their own times are on the engine's
  // clock, not the wall's.
  final now = DateTime.now().toUtc();
  for (final t in timings) {
    final total = t.totalSpan;
    if (total <= SlowFrame.budget) continue;
    recorder.recordFrame(
      SlowFrame(
        at: now,
        us: total.inMicroseconds,
        buildUs: t.buildDuration.inMicroseconds,
        rasterUs: t.rasterDuration.inMicroseconds,
        plan: PlanVisitTimer.open > 0,
      ),
    );
  }
});
