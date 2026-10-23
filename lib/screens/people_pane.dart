import 'package:flutter/material.dart';

import '../models/people_times.dart';
import '../models/person.dart';
import '../models/scoring.dart';
import '../models/trait_scores.dart';
import '../widgets/hotkeys.dart';
import '../widgets/status_message.dart';
import '../services/people_repository.dart';
import '../services/plan_memory.dart';
import '../services/traits_repository.dart';
import '../widgets/error_sheet.dart';
import '../widgets/health.dart';
import '../widgets/person_dialog.dart';
import '../widgets/person_tile.dart';
import '../widgets/plan_pane.dart';
import '../widgets/plan_summaries.dart';
import 'person_pages.dart';
import '../services/client_health.dart';
import '../services/work_timing.dart';
import '../widgets/refreshing_bar.dart';
import '../models/time_split.dart';

/// The Plan page's People pane -- who the user wants to be with:
/// everyone, Self first, each with their circles, health, time with the
/// user in the summary's 24 hours and 7 days, and the last event with
/// them -- or, with the summary looking on, the next ([PersonTile]).
/// Above them, the circles, each with its own health: tapping one shows
/// only the people in it, and "Edit" beside it edits it. Archived people
/// are shown only when asked for. The search finds people by name,
/// context, circle and what matters to them. Sorted as listed, or either
/// way by relationship health, when last (or next) seen, or time in the
/// summary's 24 hours or 7 days -- those with nothing to sort by last.
/// "+" adds a person or a circle.
///
/// Tapping a person opens their page; their menu edits or archives
/// them. Above it all, with a [summary] to measure, the time with people
/// in its window: by person, and by circle, those in none together as
/// "Individuals". It shows what [memory] has, while it loads afresh.
/// [onPeople] is told who's there each time they load.
class PeoplePane extends StatefulWidget {
  const PeoplePane({
    super.key,
    required this.repository,
    required this.memory,
    this.summary,
    this.traits,
    this.onPeople,
    this.actionNames = const {},
    this.actions = const {},
    this.locationNames = const {},
  });

  final PeopleRepository repository;
  final PlanMemory memory;

  /// What the summary measures, and how it's shown; null for none.
  final SummaryView? summary;

  /// The traits each person's page and dialog offer.
  final TraitsRepository? traits;
  final ValueChanged<PeopleList>? onPeople;

  /// Names actions by id, for a person's history.
  final Map<String?, String> actionNames;

  /// The actions and groups a person's own parts can count, by id.
  final Map<String, String> actions;

  /// Names locations by id, for where a person's events were.
  final Map<String?, String> locationNames;

  @override
  State<PeoplePane> createState() => PeoplePaneState();
}

class PeoplePaneState extends State<PeoplePane> {
  PeopleList? get _people => widget.memory.people;
  Object? _error;

  String _query = '';
  bool _archived = false;
  String? _circle;
  PeopleSort _sort = PeopleSort.listed;
  bool _ascending = false;

  bool get _forward => widget.summary?.window.forward ?? false;

  PersonPages get _pages => PersonPages(
    repository: widget.repository,
    memory: widget.memory,
    traits: widget.traits,
    actionNames: widget.actionNames,
    actions: widget.actions,
    locationNames: widget.locationNames,
    onSaved: reload,
  );

  @override
  void initState() {
    super.initState();
    widget.memory.addListener(_changed);
    _settle(widget.memory.loadPeople(widget.repository));
  }

  @override
  void dispose() {
    widget.memory.removeListener(_changed);
    super.dispose();
  }

  /// Shows what changed: the scores, as they're worked out again.
  void _changed() {
    if (mounted) setState(() {});
  }

  /// Each person's relationship health, worked out from their events.
  TraitScores? get _scores => widget.memory.scores;

  /// Each person's time and last (or next) event, as the summary
  /// measures them; null without a summary. Measured again only when the
  /// window or the events change, not for each person shown.
  PeopleTimes? get _times {
    final view = widget.summary;
    if (view == null) return null;
    final store = widget.memory.eventStore;
    final span = store?.span;
    final key = (view.window, store?.version, view.events == null);
    if (_timesKept case (final kept, final times) when kept == key) {
      return times;
    }
    final times = timed(
      WorkKind.peopleTime,
      () => PeopleTimes.compute(
        window: view.window,
        windowEvents: view.events,
        known: span == null
            ? const []
            : store!.between(span.$1, span.$2.add(const Duration(days: 1))),
      ),
    );
    _timesKept = (key, times);
    return times;
  }

  ((SummaryWindow, int?, bool), PeopleTimes)? _timesKept;

  /// Loads everyone afresh, and the events around today they're scored
  /// from.
  Future<void> reload() => Future.wait([
    _settle(widget.memory.loadPeople(widget.repository, again: true)),
    ?widget.memory.eventStore?.warm().catchError((Object _) {}),
  ]);

  /// Shows who [loading] loads, once it has, or why it couldn't.
  Future<void> _settle(Future<void> loading) async {
    try {
      await loading;
      if (!mounted) return;
      setState(() => _error = null);
      widget.onPeople?.call(_people!);
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _editCircle(Circle? circle) async {
    final repository = widget.repository;
    final saved = await showCircleDialog(
      context,
      circle: circle,
      members: {
        if (circle != null)
          for (final p
              in widget.memory.people?.inCircle(circle.id) ?? <Person>[])
            p.id: personName(p),
      },
      defaultScoring: widget.memory.scoringDefaults.circles,
      save: (fields) async => circle == null
          ? await repository.createCircle(
              Circle(
                id: '',
                name: fields['name'] as String,
                note: fields['note'] as String?,
                scoring: Aggregation.fromJson(fields['scoring']),
              ),
            )
          : await repository.updateCircle(circle.id, fields),
      delete: circle == null ? null : () => repository.deleteCircle(circle.id),
    );
    if (saved) await reload();
  }

  Future<void> _setStatus(Person person, String status) async {
    await runOrShowError(
      context,
      title: "Couldn't save ${person.name}",
      action: () async {
        await widget.repository.updatePerson(person.id, {'status': status});
        await reload();
      },
    );
  }

  /// Sorts by [sort], each its natural way first: the least healthy, the
  /// most recently seen (or soonest next), the most time.
  void _sortBy(PeopleSort sort) => setState(() {
    if (sort == _sort) {
      _ascending = !_ascending;
      return;
    }
    _sort = sort;
    _ascending = switch (sort) {
      PeopleSort.health => true,
      PeopleSort.seen => _forward,
      _ => false,
    };
  });

  int? _circleHealth(Circle c) => _scores?.groupHealth(
    _people?.inCircle(c.id).map((p) => p.id) ?? [],
    scoring: c.scoring,
  );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final people = _people;
    final view = widget.summary;
    // Asked for first: asking is what has them worked out again.
    widget.memory.scores;
    return PlanPane(
      summary: view == null || people == null
          ? null
          : PlanSummary(
              view: view,
              titles: const ['By person', 'By circle'],
              pages: (events) => [
                personTime(events, view.window, people),
                circleTime(events, view.window, people),
              ],
            ),
      searchHint: 'Search people',
      onSearch: (query) => setState(() => _query = query),
      actions: [
        PopupMenuButton<PeopleSort>(
          tooltip: 'Sort people',
          icon: const Icon(Icons.swap_vert),
          onSelected: _sortBy,
          itemBuilder: (_) => [
            for (final sort in PeopleSort.values)
              CheckedPopupMenuItem(
                value: sort,
                checked: sort == _sort,
                child: Row(
                  children: [
                    Expanded(child: Text(sort.labelFor(forward: _forward))),
                    if (sort == _sort && sort != PeopleSort.listed)
                      Icon(
                        _ascending ? Icons.arrow_upward : Icons.arrow_downward,
                        size: 18,
                        semanticLabel: _ascending ? 'Ascending' : 'Descending',
                      ),
                  ],
                ),
              ),
          ],
        ),
        IconButton(
          tooltip: _archived ? 'Hide archived people' : 'Show archived people',
          icon: Icon(
            _archived ? Icons.inventory_2 : Icons.inventory_2_outlined,
          ),
          onPressed: () => setState(() => _archived = !_archived),
        ),
        NewHotkey(
          child: PopupMenuButton<String>(
            tooltip: 'Add a person or circle',
            icon: const Icon(Icons.add),
            onSelected: (choice) => choice == 'circle'
                ? _editCircle(null)
                : _pages.edit(context, null),
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'person', child: Text('New person')),
              PopupMenuItem(value: 'circle', child: Text('New circle')),
            ],
          ),
        ),
      ],
      // Health as it was, while it's worked out again.
      child: RefreshingBar(
        refreshing: widget.memory.rescoring,
        child: RefreshIndicator(
          onRefresh: reload,
          child: HotkeyItems(
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.only(bottom: 24),
              children: switch ((people, _error)) {
                (null, final error?) => [
                  LoadError(what: 'people', error: error, onRetry: reload),
                  // Self is there regardless.
                  _tile(context, defaultSelf),
                ],
                (null, _) => const [LinearProgressIndicator()],
                (final people?, _) => [
                  if (_sort != PeopleSort.listed)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                      child: Text(
                        'By ${_sort.labelFor(forward: _forward).toLowerCase()}, '
                        '${_ascending ? 'ascending' : 'descending'}',
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                  ..._list(context, people),
                ],
              },
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _list(BuildContext context, PeopleList people) {
    final theme = Theme.of(context);
    final circle = people.circles.where((c) => c.id == _circle).firstOrNull;
    String? circleName(String id) =>
        people.circles.where((c) => c.id == id).firstOrNull?.name;
    final inCircle = [
      for (final person in people.withSelf)
        if ((_archived || person.active) &&
            (circle == null || person.circleIds.contains(circle.id)))
          person,
    ];
    final shown = sortPeople(
      [
        for (final person in inCircle)
          if (matchesSearch(_query, [
            person.name,
            person.context,
            for (final byFact in person.facts.values) ...byFact.values,
            if (person.isSelf) 'you',
            for (final id in person.circleIds) circleName(id),
          ]))
            person,
      ],
      _sort,
      ascending: _ascending,
      health: (id) => _scores?.health(id),
      times: _times,
    );
    return [
      if (people.circles.isNotEmpty)
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          child: Wrap(
            spacing: 6,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              for (final c in people.circles)
                FilterChip(
                  avatar: switch (_circleHealth(c)) {
                    final h? => HealthRing(health: h),
                    null => null,
                  },
                  label: Text(c.name),
                  tooltip: switch (_circleHealth(c)) {
                    final h? => '${c.name}: health $h, ${relationshipBand(h)}',
                    null => c.note ?? c.name,
                  },
                  selected: _circle == c.id,
                  showCheckmark: false,
                  onSelected: (on) =>
                      setState(() => _circle = on ? c.id : null),
                ),
              if (circle != null)
                TextButton.icon(
                  onPressed: () => _editCircle(circle),
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  label: Text('Edit ${circle.name}'),
                ),
            ],
          ),
        ),
      if (circle != null)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  '${circle.name}: ${people.inCircle(circle.id).length} '
                  '${people.inCircle(circle.id).length == 1 ? 'person' : 'people'}',
                  style: theme.textTheme.bodySmall,
                ),
              ),
              if (_scores?.groupTrend(
                    people.inCircle(circle.id).map((p) => p.id),
                    scoring: circle.scoring,
                  )
                  case final trend? when trend.nonNulls.isNotEmpty) ...[
                TrendSparkline(trend: trend, scale: HealthScale.relationship),
                const SizedBox(width: 8),
              ],
              if (_circleHealth(circle) case final health?)
                HealthDot(rating: health, scale: HealthScale.relationship),
            ],
          ),
        ),
      for (final person in shown) _tile(context, person),
      if (circle != null && inCircle.isEmpty)
        const Padding(
          padding: EdgeInsets.all(16),
          child: Text('No one in this circle yet.'),
        )
      else if (shown.isEmpty)
        NoMatches(query: _query)
      else if (shown.length == 1 && shown.single.isSelf && _query.isEmpty)
        const Padding(
          padding: EdgeInsets.all(16),
          child: Text('Tap + to add the people you want to spend time with.'),
        ),
    ];
  }

  /// [person], with their time and last or next event, and their menu:
  /// edit, archive.
  Widget _tile(BuildContext context, Person person) {
    final circles = [
      for (final c in _people?.circles ?? const <Circle>[])
        if (person.circleIds.contains(c.id)) c.name,
    ];
    return PersonTile(
      person: person,
      circles: circles,
      health: _scores?.health(person.id),
      trend: _scores?.healthTrend(person.id) ?? const [],
      consistency: _scores?.consistency(person.id) ?? 0,
      times: _times,
      durations: widget.summary?.durations ?? true,
      onTap: () => _pages.open(context, person),
      menu: PopupMenuButton<String>(
        tooltip: 'More for ${personName(person)}',
        onSelected: (choice) => switch (choice) {
          'edit' => _pages.edit(context, person),
          final status => _setStatus(person, status),
        },
        itemBuilder: (_) => [
          const PopupMenuItem(value: 'edit', child: Text('Edit')),
          if (!person.isSelf)
            person.active
                ? const PopupMenuItem(value: 'archived', child: Text('Archive'))
                : const PopupMenuItem(value: 'active', child: Text('Restore')),
        ],
      ),
    );
  }
}

/// A circle's relationship health, as a ring in its color.
class HealthRing extends StatelessWidget {
  const HealthRing({super.key, required this.health});

  final int health;

  @override
  Widget build(BuildContext context) => Container(
    width: 14,
    height: 14,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      border: Border.all(color: relationshipColor(health), width: 3),
    ),
  );
}
