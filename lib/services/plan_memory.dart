import 'package:flutter/widgets.dart';

import '../models/event.dart';
import '../models/goal.dart';
import '../models/person.dart';
import '../models/time_split.dart';
import '../models/trait.dart';
import '../models/trait_scores.dart';
import 'event_store.dart';
import 'events_repository.dart';
import 'goals_repository.dart';
import 'people_repository.dart';
import 'traits_repository.dart';

/// What the Plan page last showed, kept while the app runs -- above every
/// route ([PlanMemoryScope]), across switching to Notes or Events and
/// back -- so it comes back as it was, not empty, while it asks the server
/// again. The Events page fills in its people, locations and traits too
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
  PlanMemory({EventStore? eventStore}) {
    if (eventStore != null) useEvents(eventStore);
  }

  GoalList? actions;
  List<Trait>? traits;
  PeopleList? people;
  List<Location>? locations;

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
  /// [eventStore]'s events; null until the traits and people are loaded.
  /// Worked out again only when something it's from changes.
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
    );
    if (_scores case (final kept, final scores) when _same(kept, key)) {
      return scores;
    }
    final parents = {
      for (final g in actions?.goals ?? const <Goal>[])
        if (g.id != null) g.id!: g.parentId,
    };
    final today = key.$5;
    final span = store.span;
    final scores = TraitScores.compute(
      traits: traits,
      people: people.withSelf,
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
      a.$5 == b.$5;

  /// When notes were last compacted, which the summaries measure from by
  /// default; null if they never have been, or it isn't known yet.
  DateTime? lastCompaction;

  /// How many days from [lastCompaction] the summaries measure from, and
  /// whether they look on from there rather than back.
  int dayOffset = 0;
  bool forward = false;

  /// The events of each window the summaries have measured, by
  /// [eventsKey].
  final events = <String, List<Event>>{};

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

  /// The key [events] keeps [window]'s events under: the week it spans.
  static String eventsKey(SummaryWindow window) {
    final (from, to) = window.week;
    return '${from.toIso8601String()}/${to.toIso8601String()}';
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

  /// Loads every location, this visit; [again] asks again.
  Future<void> loadLocations(
    PeopleRepository repository, {
    bool again = false,
  }) => load('locations', () async {
    locations = await repository.locations();
  }, again: again);

  /// Loads [window]'s events, this visit; [again] asks again.
  Future<void> loadEvents(
    EventsRepository repository,
    SummaryWindow window, {
    bool again = false,
  }) {
    final key = eventsKey(window);
    return load('events:$key', () async {
      final (from, to) = window.week;
      events[key] = await repository.events(from, to);
    }, again: again);
  }

  /// Loads everyone, every location and every trait -- from what was kept
  /// from the app's last run, then afresh -- for what names them: an
  /// event's people, location and judgments. Best effort; [onLoaded] is
  /// called as each comes in.
  Future<void> prefetchNames({
    TraitsRepository? traits,
    PeopleRepository? people,
    VoidCallback? onLoaded,
  }) async {
    await loadKept(traits: traits, people: people);
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
    ]);
  }

  /// Loads every action and group, this visit, for the groups a trait's
  /// part can count; [again] asks again.
  Future<void> loadActions(GoalsRepository repository, {bool again = false}) =>
      load('actions', () async {
        actions = await repository.goals();
      }, again: again);

  /// Loads what the traits' [scores] are worked out from, as the app opens:
  /// the traits, everyone and every action, then the events, as far back
  /// and ahead as the traits' parts read from each day scored -- the week
  /// either side of today afresh, and only what isn't kept from further
  /// out. Best effort: what can't be loaded is scored without.
  Future<void> warmScores({
    TraitsRepository? traits,
    PeopleRepository? people,
    GoalsRepository? goals,
  }) => load('scores', () async {
    await loadKept(traits: traits, people: people, goals: goals);
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
      quietly(goals == null ? null : loadActions(goals)),
    ]);
    final store = _eventStore;
    if (store == null) return;
    final reached = reach([
      for (final t in this.traits ?? const <Trait>[])
        if (t.status == 'active') ...t.parts,
      for (final p in this.people?.withSelf ?? const <Person>[])
        for (final parts in p.traits.parts.values) ...parts,
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
    GoalsRepository? goals,
  }) async {
    try {
      this.traits ??= await traits?.cachedTraits(
        statuses: [...traitStatuses.keys],
      );
      this.people ??= await people?.cachedPeople();
      locations ??= await people?.cachedLocations();
      actions ??= await goals?.cachedGoals();
      await _eventStore?.restored();
    } catch (_) {
      // Then nothing's kept.
    }
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

typedef _ScoresKey = (int, List<Trait>, PeopleList, GoalList?, DateTime);
