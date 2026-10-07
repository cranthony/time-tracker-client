import 'package:flutter/widgets.dart';

import '../models/event.dart';
import '../models/habit.dart';
import '../models/plan_action.dart';
import '../models/note.dart';
import '../models/person.dart';
import '../models/time_split.dart';
import '../models/trait.dart';
import '../models/trait_scores.dart';
import 'event_store.dart';
import 'focus_store.dart';
import 'actions_repository.dart';
import 'habits_repository.dart';
import 'notes_repository.dart';
import 'people_repository.dart';
import 'traits_repository.dart';

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

  ActionList? actions;
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
  /// null until the traits and people are loaded. Worked out again only
  /// when something it's from changes.
  TraitScores? get scores {
    final traits = this.traits, people = this.people, store = _eventStore;
    if (traits == null || people == null || store == null) return null;
    final now = DateTime.now();
    final key = (
      store.version,
      traits,
      people,
      actions,
      DateTime(now.year, now.month, now.day),
      habits,
    );
    if (_scores case (final kept, final scores) when _same(kept, key)) {
      return scores;
    }
    final parents = {
      for (final g in actions?.actions ?? const <PlanAction>[])
        if (g.id != null) g.id!: g.parentId,
    };
    final today = key.$5;
    final span = store.span;
    final scores = TraitScores.compute(
      traits: traits,
      people: people.withSelf,
      habits: habits ?? const [],
      events: store.between(
        span?.$1 ?? today,
        span == null ? today : span.$2.add(const Duration(days: 1)),
      ),
      today: today,
      parentOf: (id) => parents[id],
      days: scoredDays,
      windowDays: span == null ? 0 : today.difference(span.$1).inDays,
    );
    _scores = (key, scores);
    return scores;
  }

  (_ScoresKey, TraitScores)? _scores;

  static bool _same(_ScoresKey a, _ScoresKey b) =>
      a.$1 == b.$1 &&
      identical(a.$2, b.$2) &&
      identical(a.$3, b.$3) &&
      identical(a.$4, b.$4) &&
      a.$5 == b.$5 &&
      identical(a.$6, b.$6);

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

typedef _ScoresKey = (
  int,
  List<Trait>,
  PeopleList,
  ActionList?,
  DateTime,
  List<Habit>?,
);
