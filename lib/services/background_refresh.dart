import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/note.dart';
import '../models/proposal.dart';
import '../models/schedule_hints.dart';
import '../outbox/background_sync.dart';
import '../models/trait.dart' show traitStatuses;
import 'actions_repository.dart';
import 'app_settings.dart';
import 'event_store.dart';
import 'habits_repository.dart';
import 'mcp_client.dart';
import 'notes_repository.dart';
import 'people_repository.dart';
import 'proposal_repository.dart';
import 'schedule_hints_repository.dart';
import 'traits_repository.dart';

/// How long after a routine's time the app fetches, unless it's changed
/// ([AppSettings.refreshDelay]): it takes a while to run.
const refreshDelay = AppSettings.defaultRefreshDelay;

/// How long the app goes without fetching, when no routine's time comes
/// sooner.
const refreshFallback = Duration(hours: 6);

/// How often the app fetches again while a compaction's proposal is
/// expected and hasn't come, unless it's changed
/// ([AppSettings.retryInterval]).
const retryInterval = AppSettings.defaultRetryInterval;

/// How long after a compaction's time the app keeps fetching again for
/// its proposal: then it waits for the next.
const retryWindow = Duration(hours: 3);

/// A routine expected to make a proposal (see
/// [AppSettings.expectsProposal]) whose proposal hasn't come: the
/// routine, and when it ran.
typedef AwaitedProposal = ({ScheduleHint hint, DateTime at});

/// When the next background fetch is due, and why: [hint]'s time, plus
/// the delay -- or, a [retry], [hint]'s proposal not yet come, sooner --
/// or, with no hint, the fallback, [refreshFallback] from now.
typedef RefreshPlan = ({DateTime at, ScheduleHint? hint, bool retry});

/// The next fetch after [now]: [delay] after the next of [hints]' times
/// (each daily, in the phone's local time), unless the [fallback] from
/// now comes first -- or, [awaiting] a proposal, [retry] from now, until
/// [retryWindow] after its routine ran.
RefreshPlan nextRefresh(
  DateTime now,
  List<ScheduleHint> hints, {
  Duration delay = refreshDelay,
  Duration fallback = refreshFallback,
  Duration? retry = retryInterval,
  AwaitedProposal? awaiting,
}) {
  RefreshPlan plan = (at: now.add(fallback), hint: null, retry: false);
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
    if (at.isBefore(plan.at)) plan = (at: at, hint: hint, retry: false);
  }
  if (awaiting != null && retry != null) {
    final at = now.add(retry);
    if (at.isBefore(awaiting.at.add(retryWindow)) && at.isBefore(plan.at)) {
      plan = (at: at, hint: awaiting.hint, retry: true);
    }
  }
  return plan;
}

/// The latest of [hints] that [expects] a proposal and ran in the
/// [retryWindow] before [now] -- today, or yesterday -- or null.
AwaitedProposal? expectedProposal(
  DateTime now,
  List<ScheduleHint> hints,
  bool Function(ScheduleHint hint) expects,
) {
  AwaitedProposal? latest;
  for (final hint in hints) {
    if (!expects(hint)) continue;
    for (final day in [now.day, now.day - 1]) {
      final at = DateTime(now.year, now.month, day, hint.hour, hint.minute);
      if (at.isAfter(now) || !now.isBefore(at.add(retryWindow))) continue;
      if (latest == null || at.isAfter(latest.at)) {
        latest = (hint: hint, at: at);
      }
    }
  }
  return latest;
}

/// What the last background fetch did: when, what it fetched and what it
/// couldn't, and whether it found the user signed out; and the routine
/// whose proposal it expected and didn't find ([awaiting]).
class RefreshRecord {
  const RefreshRecord({
    required this.at,
    this.fetched = const [],
    this.failed = const [],
    this.signedOut = false,
    this.awaiting,
  });

  final DateTime at;
  final List<String> fetched;
  final List<String> failed;
  final bool signedOut;
  final AwaitedProposal? awaiting;

  bool get ok => failed.isEmpty && !signedOut;

  static const _key = 'background_refresh_last';

  /// The last one, as kept on the device; null if there's been none.
  static Future<RefreshRecord?> load() async {
    try {
      final json = await SharedPreferencesAsync().getString(_key);
      if (json == null) return null;
      final map = jsonDecode(json) as Map;
      DateTime time(Object? t) => DateTime.parse(t as String).toLocal();
      return RefreshRecord(
        at: time(map['at']),
        fetched: [for (final f in map['fetched'] as List? ?? []) '$f'],
        failed: [for (final f in map['failed'] as List? ?? []) '$f'],
        signedOut: map['signed_out'] == true,
        awaiting: switch (map['awaiting']) {
          {'at': final String at, 'hint': final Object hint} =>
            switch (ScheduleHint.fromJson(hint)) {
              final hint? => (hint: hint, at: time(at)),
              null => null,
            },
          _ => null,
        },
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> save() async {
    String time(DateTime t) => t.toUtc().toIso8601String();
    try {
      await SharedPreferencesAsync().setString(
        _key,
        jsonEncode({
          'at': time(at),
          'fetched': fetched,
          'failed': failed,
          if (signedOut) 'signed_out': true,
          if (awaiting case final a?)
            'awaiting': {'at': time(a.at), 'hint': a.hint.toJson()},
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
/// last compacted, the open proposal, every action, trait, person,
/// location and habit, and the week either side of today's events. Each
/// is fetched on its own, best effort; signed out, it stops. [clock]
/// says when it ran.
///
/// After a routine that [expects] a proposal, it says if the proposal
/// hasn't come ([RefreshRecord.awaiting]), for the next fetch to come
/// sooner: none is open through a time after the routine ran -- as
/// Claude's own revision runs, not as the user extended it -- and no
/// compaction was confirmed since.
Future<RefreshRecord> refreshCaches({
  ScheduleHintsRepository? hints,
  NotesRepository? notes,
  ProposalRepository? proposals,
  ActionsRepository? actions,
  TraitsRepository? traits,
  PeopleRepository? people,
  HabitsRepository? habits,
  EventStore? events,
  bool Function(ScheduleHint hint)? expects,
  DateTime Function() clock = DateTime.now,
}) async {
  final fetched = <String>[], failed = <String>[];
  final started = clock();
  ScheduleHints? times;
  CompactionStatus? status;
  var proposalFetched = false;
  Proposal? proposal;
  final steps = <(String, Future<void> Function()?)>[
    (
      'routine times',
      hints == null ? null : () async => times = await hints.hints(),
    ),
    (
      'notes',
      notes == null
          ? null
          : () async {
              await notes.uncompactedNotes();
              status = await notes.compactionStatus();
            },
    ),
    (
      'proposal',
      proposals == null
          ? null
          : () async {
              proposal = await proposals.current();
              proposalFetched = true;
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
  final expected = proposals == null || expects == null
      ? null
      : expectedProposal(started, times?.hints ?? const [], expects);
  final came = switch (expected) {
    null => true,
    // Not found for want of asking: ask again.
    _ when !proposalFetched => false,
    (:final at, hint: _) =>
      ((proposal?.claudeThrough ?? proposal?.through)?.isAfter(at) ?? false) ||
          (status?.lastCompaction?.isAfter(at) ?? false),
  };
  return RefreshRecord(
    at: clock(),
    fetched: fetched,
    failed: failed,
    awaiting: came ? null : expected,
  );
}

/// Background updates, as the app sees them: the routines' times, read
/// from the server (or kept from before), when the next fetch is due
/// ([nextRefresh]) -- scheduled with Android's WorkManager as they load
/// -- and what the last one did. Fetching itself happens in the
/// background task ([refreshCaches]). Only Android has one: elsewhere,
/// nothing is scheduled, and [supported] says so. Best effort: a server
/// without the hints leaves them [unavailable], and the fallback stands.
/// How long after each it fetches, and how often again while a proposal
/// hasn't come, are the [settings]' -- rescheduled as they change.
class BackgroundRefresh extends ChangeNotifier {
  BackgroundRefresh({
    this.repository,
    AppSettings? settings,
    bool? supported,
    DateTime Function()? clock,
    Future<void> Function(Duration delay)? schedule,
    Future<RefreshRecord?> Function()? lastRecord,
  }) : settings = settings ?? AppSettings(persist: false),
       supported = supported ?? BackgroundSync.supported,
       _clock = clock ?? DateTime.now,
       _schedule = schedule ?? BackgroundSync.scheduleRefresh,
       _lastRecord = lastRecord ?? RefreshRecord.load {
    _planned = _planning;
    this.settings.addListener(_settingsChanged);
  }

  final ScheduleHintsRepository? repository;

  /// Where the delay after a routine, how often to fetch again, and which
  /// routines a proposal's expected after, are set.
  final AppSettings settings;

  /// What of the [settings] the next fetch is planned with.
  ({Duration delay, Duration? retry, AwaitedProposal? awaiting})
  get _planning => (
    delay: settings.refreshDelay,
    retry: settings.retryInterval,
    awaiting: _awaiting,
  );
  late ({Duration delay, Duration? retry, AwaitedProposal? awaiting}) _planned;

  /// The proposal the last fetch didn't find, if it's still expected.
  AwaitedProposal? get _awaiting => switch (last?.awaiting) {
    final a? when settings.expectsProposal(a.hint) => a,
    _ => null,
  };

  void _settingsChanged() {
    if (_planning == _planned) return;
    _planned = _planning;
    notifyListeners();
    reschedule().catchError((Object _) {});
  }

  @override
  void dispose() {
    settings.removeListener(_settingsChanged);
    super.dispose();
  }

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
  RefreshPlan get next => nextRefresh(
    _clock(),
    hints?.hints ?? const [],
    delay: settings.refreshDelay,
    retry: settings.retryInterval,
    awaiting: _awaiting,
  );

  /// Loads the times -- kept from before, then afresh -- and what the last
  /// fetch did, and schedules the next fetch.
  Future<void> load() async {
    await settings.load();
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
    _planned = _planning;
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
