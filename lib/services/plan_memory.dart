import '../models/event.dart';
import '../models/goal.dart';
import '../models/person.dart';
import '../models/time_split.dart';
import '../models/trait.dart';
import 'events_repository.dart';
import 'people_repository.dart';
import 'traits_repository.dart';

/// What the Plan page last showed, kept while the app runs -- by the home
/// screen, across switching to Notes or Events and back -- so it comes
/// back as it was, not empty, while it asks the server again.
///
/// Each visit loads everything at once (see [load]): a pane opened while
/// its load is still under way waits for that one, rather than asking
/// again.
class PlanMemory {
  GoalList? actions;
  List<Trait>? traits;
  List<TraitDay> traitHistory = const [];
  PeopleList? people;
  List<Location>? locations;

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
    return _loads[what] = fetch();
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
        traitHistory = await repository.traitHistory();
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

  /// What was kept from the app's last run, for whatever this run hasn't
  /// loaded yet. Best effort.
  Future<void> loadKept({
    TraitsRepository? traits,
    PeopleRepository? people,
  }) async {
    try {
      this.traits ??= await traits?.cachedTraits(
        statuses: [...traitStatuses.keys],
      );
      this.people ??= await people?.cachedPeople();
      locations ??= await people?.cachedLocations();
    } catch (_) {
      // Then nothing's kept.
    }
  }
}
