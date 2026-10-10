import 'dart:convert';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../models/event.dart';
import '../models/habit.dart';
import '../models/plan_action.dart';
import '../models/note.dart';
import '../models/person.dart';
import '../models/time_split.dart';
import '../models/trait.dart';
import '../models/trait_scores.dart';
import '../outbox/actions_shown.dart';
import '../outbox/action_outbox.dart';
import 'event_store.dart';
import 'focus_store.dart';
import 'actions_repository.dart';
import 'habits_repository.dart';
import 'notes_repository.dart';
import 'people_repository.dart';
import 'traits_repository.dart';
import 'client_health.dart';
import 'work_timing.dart';

/// What the app has loaded, kept while it runs -- above every route
/// ([PlanMemoryScope]), across switching between Notes, Events and Plan
/// -- once for every page, so each comes back as it was, not empty, while
/// it asks the server again: the actions, traits, people, habits and
/// locations, the notes not yet compacted and when notes were last compacted, and
/// the events (in [eventStore]). What the repositories kept from the
/// app's last run fills in what this run hasn't loaded yet ([loadKept]). The Events page fills in its people, locations and traits too
/// ([prefetchNames]), for an event's dialogs to name them at once.
///
/// It holds the app's [eventStore] too, and the traits' [scores], worked
/// out from it: [warmScores], as the app opens, loads what they need.
/// Listeners hear whenever anything it holds changes.
///
/// Each visit loads everything at once (see [load]): a pane opened while
/// its load is still under way waits for that one, rather than asking
/// again.
class PlanMemory extends ChangeNotifier {
  PlanMemory({EventStore? eventStore, FocusStore? focus})
    : focus = focus ?? FocusStore(persist: false) {
    if (eventStore != null) useEvents(eventStore);
    this.focus.addListener(notifyListeners);
  }

  /// The habits focused on and people prioritized, kept on the device.
  final FocusStore focus;

  /// The actions as the server last listed them.
  ActionList? actions;

  /// [actions] as they're shown: with the saves the action outbox made
  /// since they were fetched, or is still to make, made to them (see
  /// [useActionOutbox]) -- an action renamed shows its new name on every
  /// page at once, not once they're fetched again.
  ActionList? get shownActions {
    final actions = this.actions, outbox = _actionOutbox;
    if (actions == null || outbox == null) return actions;
    if (_shown case (final from, final shown) when identical(from, actions)) {
      return shown;
    }
    final shown = actionsShown(actions, outbox);
    _shown = (actions, shown);
    return shown;
  }

  (ActionList, ActionList)? _shown;
  ActionOutbox? _actionOutbox;

  /// Shows [outbox]'s saves in [shownActions], and tells listeners as they
  /// change.
  void useActionOutbox(ActionOutbox outbox) {
    if (_actionOutbox != null) return;
    _actionOutbox = outbox..addListener(_actionsSaved);
  }

  void _actionsSaved() {
    _shown = null;
    notifyListeners();
  }

  List<Trait>? traits;
  PeopleList? people;
  List<Location>? locations;

  /// Self's habits, whatever their status; null until they're loaded, or
  /// if the server has none to give (see [loadHabits]).
  List<Habit>? habits;

  /// The calendar's events, kept day by day, that the traits are scored
  /// from; null until there's somewhere to load them from.
  EventStore? get eventStore => _eventStore;
  EventStore? _eventStore;

  /// Scores the traits from [store]'s events, unless it has a store
  /// already.
  void useEvents(EventStore store) {
    if (_eventStore != null) return;
    _eventStore = store..addListener(notifyListeners);
  }

  /// How many of the days before today the traits are scored for.
  static const scoredDays = 7;

  /// Everyone's traits scored for each of the last [scoredDays] days, from
  /// [eventStore]'s events -- Self's habits' too, once they're loaded --
  /// null until the traits and people are loaded, and they've been worked
  /// out once. Worked out again only when what they're from changes --
  /// not just as it's loaded again, alike -- by [runScores], off the UI
  /// thread: until then, as they were, with [rescoring] saying so, and
  /// listeners told once they're in.
  TraitScores? get scores {
    final traits = this.traits, people = this.people, store = _eventStore;
    if (traits == null || people == null || store == null) return null;
    final now = DateTime.now();
    final key = (
      store.version,
      _signature(traits, _traitsSignature),
      _signature(people, _peopleSignature),
      _signature(actions, _actionsSignature),
      DateTime(now.year, now.month, now.day),
      _signature(habits, _habitsSignature),
    );
    if (_scores case (final kept, final scores) when kept == key) return scores;
    if (_rescoring == null && _failed != key) {
      _rescore(key, traits, people, store);
    }
    return _scores?.$2;
  }

  /// Whether [scores] are being worked out again: they're as they were
  /// till then.
  bool get rescoring => _rescoring != null;

  (_ScoresKey, TraitScores)? _scores;
  Future<void>? _rescoring;

  /// What they couldn't be worked out from: not tried again till it
  /// changes.
  _ScoresKey? _failed;

  /// Runs the scores' working out, off the UI thread: on another isolate,
  /// or on the web, which has none, in a task of its own. Tests set one
  /// that runs it there and then.
  static Future<TraitScores> Function(TraitScores Function() work) runScores =
      _offThread;

  static Future<TraitScores> _offThread(TraitScores Function() work) =>
      kIsWeb ? Future(work) : Isolate.run(work);

  /// Works the scores out for [key], then has them shown -- and worked
  /// out again, if what they're from changed meanwhile.
  void _rescore(
    _ScoresKey key,
    List<Trait> traits,
    PeopleList people,
    EventStore store,
  ) {
    final today = key.$5;
    final span = store.span;
    final work = _scoring(
      traits: traits,
      people: people.withSelf,
      habits: habits ?? const [],
      events: store.between(
        span?.$1 ?? today,
        span == null ? today : span.$2.add(const Duration(days: 1)),
      ),
      today: today,
      parents: {
        for (final g in actions?.actions ?? const <PlanAction>[])
          if (g.id != null) g.id!: g.parentId,
      },
      windowDays: span == null ? 0 : today.difference(span.$1).inDays,
    );
    final why = _why(_scores?.$1, key);
    final watch = Stopwatch()..start();
    // Done there and then -- as in tests -- it's shown now, not told of.
    var now = true, done = false;
    final rescoring = runScores(work)
        .then(
          (scores) {
            recordWork(
              WorkKind.traitScores,
              watch.elapsedMicroseconds,
              why: why,
              blocking: now,
            );
            _scores = (key, scores);
            _failed = null;
          },
          onError: (Object e, StackTrace stack) {
            // Kept as they were; worked out again when something changes.
            _failed = key;
            workRecorder?.recordError(e, stack: stack);
          },
        )
        .whenComplete(() {
          done = true;
          _rescoring = null;
          if (!now) notifyListeners();
        });
    if (!done) _rescoring = rescoring;
    now = false;
  }

  /// The scores' working out, from these alone: what's sent off the UI
  /// thread holds nothing more.
  static TraitScores Function() _scoring({
    required List<Trait> traits,
    required List<Person> people,
    required List<Habit> habits,
    required List<Event> events,
    required DateTime today,
    required Map<String, String?> parents,
    required int windowDays,
  }) =>
      () => TraitScores.compute(
        traits: traits,
        people: people,
        habits: habits,
        events: events,
        today: today,
        parentOf: (id) => parents[id],
        days: scoredDays,
        windowDays: windowDays,
      );

  /// What changed from [was] to [now], that the scores are worked out
  /// again for: "first", with none before.
  static String _why(_ScoresKey? was, _ScoresKey now) {
    if (was == null) return 'first';
    return [
      if (was.$1 != now.$1) 'events',
      if (was.$2 != now.$2) 'traits',
      if (was.$3 != now.$3) 'people',
      if (was.$4 != now.$4) 'actions',
      if (was.$5 != now.$5) 'day',
      if (was.$6 != now.$6) 'habits',
    ].join(', ');
  }

  /// [of]'s [signature]: worked out again only when [of] is another
  /// object, so loading it again, alike, changes nothing.
  String? _signature<T extends Object>(T? of, String Function(T) signature) {
    if (of == null) return null;
    final kept = _signatures[T];
    if (kept != null && identical(kept.$1, of)) return kept.$2;
    final made = signature(of);
    _signatures[T] = (of, made);
    return made;
  }

  final _signatures = <Type, (Object, String)>{};

  /// What of the traits the scores are from: all of each.
  static String _traitsSignature(List<Trait> traits) =>
      jsonEncode([for (final t in traits) t.toJson()]);

  /// What of the people the scores are from: each, with what they
  /// cancelled.
  static String _peopleSignature(PeopleList people) => jsonEncode([
    for (final p in people.withSelf)
      [
        p.toJson(),
        for (final c in p.cancelledEvents)
          [
            c.eventId,
            c.summary,
            c.start.toIso8601String(),
            c.end.toIso8601String(),
            c.actionIds,
            c.engagement,
            c.parts,
            c.cancelledAt?.toIso8601String(),
            c.source,
          ],
      ],
  ]);

  /// What of the actions the scores are from: what each is in.
  static String _actionsSignature(ActionList actions) => jsonEncode([
    for (final a in actions.actions) [a.id, a.parentId],
  ]);

  static String _habitsSignature(List<Habit> habits) =>
      jsonEncode([for (final h in habits) h.toJson()]);

  /// The saved notes not yet compacted; null until they're loaded.
  List<Note>? notes;

  /// When notes were last compacted, and what's been compacted; null
  /// until it's known.
  CompactionStatus? compaction;

  /// When notes were last compacted, which the summaries measure from by
  /// default; null if they never have been, or it isn't known yet.
  DateTime? get lastCompaction => compaction?.lastCompaction;

  /// How many days from [lastCompaction] the summaries measure from, and
  /// whether they look on from there rather than back.
  int dayOffset = 0;
  bool forward = false;

  /// This visit's loads, by what they load.
  final _loads = <String, Future<void>>{};

  /// Runs [fetch] for [what], unless it's run already this visit -- then
  /// its future, done or not -- or [again] says to run it again.
  Future<void> load(
    String what,
    Future<void> Function() fetch, {
    bool again = false,
  }) {
    final loading = _loads[what];
    if (loading != null && !again) return loading;
    return _loads[what] = fetch().then((_) => notifyListeners());
  }

  /// Forgets this visit's loads, so the next visit loads afresh.
  void newVisit() {
    _loads.clear();
    _visited = null;
  }

  /// When this visit's window was first asked for: "now", for a window
  /// with no compaction to measure from, held still through the visit.
  DateTime? _visited;

  /// The summaries' window: [dayOffset] days from [lastCompaction] (or
  /// from this visit's first [now], if notes were never compacted), back
  /// or on from there.
  SummaryWindow window(DateTime now) => SummaryWindow(
    asOf: (lastCompaction ?? (_visited ??= now)).add(Duration(days: dayOffset)),
    forward: forward,
  );

  /// [window]'s events, from [eventStore], once it has every day of it;
  /// null until then.
  List<Event>? windowEvents(SummaryWindow window) {
    final (from, to) = window.week;
    final store = _eventStore;
    if (store == null || !store.hasAll(from, to)) return null;
    return store.between(from, to);
  }

  /// Loads every trait and their scores, this visit; [again] asks again.
  Future<void> loadTraits(TraitsRepository repository, {bool again = false}) =>
      load('traits', () async {
        traits = await repository.traits(statuses: [...traitStatuses.keys]);
      }, again: again);

  /// Loads everyone and their circles, this visit; [again] asks again.
  Future<void> loadPeople(PeopleRepository repository, {bool again = false}) =>
      load('people', () async {
        people = await repository.people();
      }, again: again);

  /// Loads Self's habits, this visit; [again] asks again. Best effort:
  /// a server without habits, or one that can't give them, leaves them
  /// as they were -- habits are never what stops a page.
  Future<void> loadHabits(HabitsRepository repository, {bool again = false}) =>
      load('habits', () async {
        try {
          habits = await repository.habits();
        } catch (_) {
          // None, or what's kept.
        }
      }, again: again);

  /// Loads every location, this visit; [again] asks again.
  Future<void> loadLocations(
    PeopleRepository repository, {
    bool again = false,
  }) => load('locations', () async {
    locations = await repository.locations();
  }, again: again);

  /// Loads [window]'s events into [eventStore], this visit; [again] asks
  /// again.
  Future<void> loadEvents(SummaryWindow window, {bool again = false}) {
    final store = _eventStore;
    if (store == null) return Future.value();
    final (from, to) = window.week;
    return load(
      'events:${from.toIso8601String()}/${to.toIso8601String()}',
      () => store.refresh(from, to),
      again: again,
    );
  }

  /// Loads everyone, every location, every trait and Self's habits --
  /// from what was kept from the app's last run, then afresh -- for what
  /// names them: an event's people, location and judgments. Best effort;
  /// [onLoaded] is called as each comes in.
  Future<void> prefetchNames({
    TraitsRepository? traits,
    PeopleRepository? people,
    HabitsRepository? habits,
    VoidCallback? onLoaded,
  }) async {
    await loadKept(traits: traits, people: people, habits: habits);
    onLoaded?.call();
    Future<void> quietly(Future<void>? loading) async {
      try {
        await loading;
        onLoaded?.call();
      } catch (_) {
        // Named by what's kept, or by id.
      }
    }

    await Future.wait([
      quietly(traits == null ? null : loadTraits(traits)),
      quietly(people == null ? null : loadPeople(people)),
      quietly(people == null ? null : loadLocations(people)),
      quietly(habits == null ? null : loadHabits(habits)),
    ]);
  }

  /// Loads the saved notes not yet compacted, this visit; [again] asks
  /// again.
  Future<void> loadNotes(NotesRepository repository, {bool again = false}) =>
      load('notes', () async {
        notes = await repository.uncompactedNotes();
      }, again: again);

  /// Loads when notes were last compacted, this visit; [again] asks
  /// again.
  Future<void> loadCompaction(
    NotesRepository repository, {
    bool again = false,
  }) => load('compaction', () async {
    compaction = await repository.compactionStatus();
  }, again: again);

  /// Loads every action and group, this visit, for the groups a trait's
  /// part can count; [again] asks again.
  Future<void> loadActions(
    ActionsRepository repository, {
    bool again = false,
  }) => load('actions', () async {
    actions = await repository.actions();
  }, again: again);

  /// Whether [warmScores] has been asked to load, this run.
  bool get warmed => _warmed;
  bool _warmed = false;

  /// Loads what the traits' [scores] are worked out from, as the app opens:
  /// the traits, everyone and every action, then the events, as far back
  /// and ahead as the traits' parts read from each day scored -- the week
  /// either side of today afresh, and only what isn't kept from further
  /// out. Best effort: what can't be loaded is scored without.
  /// Habits are loaded with them.
  Future<void> warmScores({
    TraitsRepository? traits,
    PeopleRepository? people,
    ActionsRepository? actions,
    HabitsRepository? habits,
  }) => load('scores', () async {
    _warmed = true;
    await loadKept(
      traits: traits,
      people: people,
      actions: actions,
      habits: habits,
    );
    notifyListeners();
    Future<void> quietly(Future<void>? loading) async {
      try {
        await loading;
      } catch (_) {
        // Scored with what's kept, or not at all.
      }
    }

    await Future.wait([
      quietly(traits == null ? null : loadTraits(traits)),
      quietly(people == null ? null : loadPeople(people)),
      quietly(actions == null ? null : loadActions(actions)),
      quietly(habits == null ? null : loadHabits(habits)),
    ]);
    final store = _eventStore;
    if (store == null) return;
    final reached = reach([
      for (final t in this.traits ?? const <Trait>[])
        if (t.status == 'active') ...t.parts,
      for (final p in this.people?.withSelf ?? const <Person>[])
        for (final parts in p.traits.parts.values) ...parts,
      for (final h in this.habits ?? const <Habit>[])
        for (final parts in h.traits.parts.values) ...parts,
    ]);
    await quietly(
      store.warm(back: scoredDays + reached.back + 1, ahead: reached.ahead),
    );
  });

  /// What was kept from the app's last run, for whatever this run hasn't
  /// loaded yet. Best effort.
  Future<void> loadKept({
    TraitsRepository? traits,
    PeopleRepository? people,
    ActionsRepository? actions,
    NotesRepository? notes,
    HabitsRepository? habits,
  }) async {
    // Each awaited first, then kept only if nothing's there yet: a load
    // finishing meanwhile, or another call, may have filled it.
    Future<void> keep<T>(Future<T?>? kept, void Function(T value) fill) async {
      try {
        if (await kept case final value?) fill(value);
      } catch (_) {
        // Then that's not kept.
      }
    }

    await Future.wait([
      keep(
        traits?.cachedTraits(statuses: [...traitStatuses.keys]),
        (v) => this.traits ??= v,
      ),
      keep(people?.cachedPeople(), (v) => this.people ??= v),
      keep(people?.cachedLocations(), (v) => locations ??= v),
      keep(habits?.cachedHabits(), (v) => this.habits ??= v),
      keep(actions?.cachedActions(), (v) => this.actions ??= v),
      keep(notes?.cachedUncompactedNotes(), (v) => this.notes ??= v),
      keep(notes?.cachedCompactionStatus(), (v) => compaction ??= v),
      keep(_eventStore?.restored().then((_) => true), (_) {}),
    ]);
  }
}

/// Makes a [PlanMemory] available to everything below it -- every route
/// and dialog, when it's above the navigator.
class PlanMemoryScope extends InheritedWidget {
  const PlanMemoryScope({
    super.key,
    required this.memory,
    required super.child,
  });

  final PlanMemory memory;

  /// The nearest [PlanMemoryScope]'s memory, or null if there's none.
  static PlanMemory? of(BuildContext context) =>
      context.getInheritedWidgetOfExactType<PlanMemoryScope>()?.memory;

  @override
  bool updateShouldNotify(PlanMemoryScope oldWidget) =>
      memory != oldWidget.memory;
}

/// What the scores are from: the events' version, the traits', people's,
/// actions' and habits' signatures, and the day.
typedef _ScoresKey = (int, String?, String?, String?, DateTime, String?);
