import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/schedule_hints.dart';
import '../outbox/background_sync.dart';
import '../models/trait.dart' show traitStatuses;
import 'actions_repository.dart';
import 'event_store.dart';
import 'habits_repository.dart';
import 'mcp_client.dart';
import 'notes_repository.dart';
import 'people_repository.dart';
import 'schedule_hints_repository.dart';
import 'traits_repository.dart';

/// How long after a routine's time the app fetches: it takes a while to
/// run.
const refreshDelay = Duration(minutes: 10);

/// How long the app goes without fetching, when no routine's time comes
/// sooner.
const refreshFallback = Duration(hours: 6);

/// When the next background fetch is due, and why: [hint]'s time, plus
/// [refreshDelay] -- or, with no hint, the fallback, [refreshFallback]
/// from now.
typedef RefreshPlan = ({DateTime at, ScheduleHint? hint});

/// The next fetch after [now]: [delay] after the next of [hints]' times
/// (each daily, in the phone's local time), unless the [fallback] from
/// now comes first.
RefreshPlan nextRefresh(
  DateTime now,
  List<ScheduleHint> hints, {
  Duration delay = refreshDelay,
  Duration fallback = refreshFallback,
}) {
  RefreshPlan plan = (at: now.add(fallback), hint: null);
  for (final hint in hints) {
    var at = DateTime(
      now.year,
      now.month,
      now.day,
      hint.hour,
      hint.minute,
    ).add(delay);
    if (!at.isAfter(now)) {
      at = DateTime(
        now.year,
        now.month,
        now.day + 1,
        hint.hour,
        hint.minute,
      ).add(delay);
    }
    if (at.isBefore(plan.at)) plan = (at: at, hint: hint);
  }
  return plan;
}

/// What the last background fetch did: when, what it fetched and what it
/// couldn't, and whether it found the user signed out.
class RefreshRecord {
  const RefreshRecord({
    required this.at,
    this.fetched = const [],
    this.failed = const [],
    this.signedOut = false,
  });

  final DateTime at;
  final List<String> fetched;
  final List<String> failed;
  final bool signedOut;

  bool get ok => failed.isEmpty && !signedOut;

  static const _key = 'background_refresh_last';

  /// The last one, as kept on the device; null if there's been none.
  static Future<RefreshRecord?> load() async {
    try {
      final json = await SharedPreferencesAsync().getString(_key);
      if (json == null) return null;
      final map = jsonDecode(json) as Map;
      return RefreshRecord(
        at: DateTime.parse(map['at'] as String).toLocal(),
        fetched: [for (final f in map['fetched'] as List? ?? []) '$f'],
        failed: [for (final f in map['failed'] as List? ?? []) '$f'],
        signedOut: map['signed_out'] == true,
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> save() async {
    try {
      await SharedPreferencesAsync().setString(
        _key,
        jsonEncode({
          'at': at.toUtc().toIso8601String(),
          'fetched': fetched,
          'failed': failed,
          if (signedOut) 'signed_out': true,
        }),
      );
    } catch (_) {
      // Not said, then.
    }
  }
}

/// What a background fetch reads, each into what the app keeps from run
/// to run, for it to show at once when it opens: the routines' times
/// (to plan the next), the notes not yet compacted and when notes were
/// last compacted, every action, trait, person, location and habit, and
/// the week either side of today's events. Each is fetched on its own,
/// best effort; signed out, it stops. [clock] says when it ran.
Future<RefreshRecord> refreshCaches({
  ScheduleHintsRepository? hints,
  NotesRepository? notes,
  ActionsRepository? actions,
  TraitsRepository? traits,
  PeopleRepository? people,
  HabitsRepository? habits,
  EventStore? events,
  DateTime Function() clock = DateTime.now,
}) async {
  final fetched = <String>[], failed = <String>[];
  final steps = <(String, Future<void> Function()?)>[
    ('routine times', hints == null ? null : () => hints.hints()),
    (
      'notes',
      notes == null
          ? null
          : () async {
              await notes.uncompactedNotes();
              await notes.compactionStatus();
            },
    ),
    ('actions', actions == null ? null : () => actions.actions()),
    (
      'traits',
      traits == null
          ? null
          : () => traits.traits(statuses: [...traitStatuses.keys]),
    ),
    (
      'people',
      people == null
          ? null
          : () async {
              await people.people();
              await people.locations();
            },
    ),
    ('habits', habits == null ? null : () => habits.habits()),
    (
      'events',
      events == null
          ? null
          : () async {
              await events.warm();
              await events.save();
            },
    ),
  ];
  for (final (name, step) in steps) {
    if (step == null) continue;
    try {
      await step();
      fetched.add(name);
    } on SignInRequiredException {
      return RefreshRecord(
        at: clock(),
        fetched: fetched,
        failed: failed,
        signedOut: true,
      );
    } catch (_) {
      failed.add(name);
    }
  }
  return RefreshRecord(at: clock(), fetched: fetched, failed: failed);
}

/// Background updates, as the app sees them: the routines' times, read
/// from the server (or kept from before), when the next fetch is due
/// ([nextRefresh]) -- scheduled with Android's WorkManager as they load
/// -- and what the last one did. Fetching itself happens in the
/// background task ([refreshCaches]). Only Android has one: elsewhere,
/// nothing is scheduled, and [supported] says so. Best effort: a server
/// without the hints leaves them [unavailable], and the fallback stands.
class BackgroundRefresh extends ChangeNotifier {
  BackgroundRefresh({
    this.repository,
    bool? supported,
    DateTime Function()? clock,
    Future<void> Function(Duration delay)? schedule,
    Future<RefreshRecord?> Function()? lastRecord,
  }) : supported = supported ?? BackgroundSync.supported,
       _clock = clock ?? DateTime.now,
       _schedule = schedule ?? BackgroundSync.scheduleRefresh,
       _lastRecord = lastRecord ?? RefreshRecord.load;

  final ScheduleHintsRepository? repository;

  /// Whether background fetches run here: on Android.
  final bool supported;
  final DateTime Function() _clock;
  final Future<void> Function(Duration delay) _schedule;
  final Future<RefreshRecord?> Function() _lastRecord;

  /// The routines' times; null until they're loaded, or if they can't be.
  ScheduleHints? hints;

  /// Whether the server couldn't give them: an older server, say.
  bool unavailable = false;

  /// What the last background fetch did; null if there's been none.
  RefreshRecord? last;

  /// Now, as it tells it.
  DateTime get now => _clock();

  /// When the next is due, and why.
  RefreshPlan get next => nextRefresh(_clock(), hints?.hints ?? const []);

  /// Loads the times -- kept from before, then afresh -- and what the last
  /// fetch did, and schedules the next fetch.
  Future<void> load() async {
    final repository = this.repository;
    if (repository != null) {
      hints ??= await repository.cachedHints();
      notifyListeners();
      try {
        hints = await repository.hints();
        unavailable = false;
      } catch (_) {
        unavailable = true;
      }
    }
    last = await _lastRecord();
    notifyListeners();
    await reschedule();
  }

  /// Schedules the next fetch, in place of any already scheduled.
  Future<void> reschedule() async {
    if (!supported) return;
    final delay = next.at.difference(_clock());
    await _schedule(delay.isNegative ? Duration.zero : delay);
  }

  /// The nearest [BackgroundRefreshScope]'s, or null if there's none.
  static BackgroundRefresh? of(BuildContext context) =>
      context.getInheritedWidgetOfExactType<BackgroundRefreshScope>()?.refresh;
}

/// Makes a [BackgroundRefresh] available to everything below it.
class BackgroundRefreshScope extends InheritedWidget {
  const BackgroundRefreshScope({
    super.key,
    required this.refresh,
    required super.child,
  });

  final BackgroundRefresh refresh;

  @override
  bool updateShouldNotify(BackgroundRefreshScope oldWidget) =>
      refresh != oldWidget.refresh;
}
