import 'package:flutter/material.dart';

import '../models/people_times.dart';
import '../models/person.dart';
import '../models/trait_scores.dart';
import '../services/plan_memory.dart';
import '../widgets/health.dart';
import '../widgets/plan_pane.dart';

/// Everyone, as the People pane listed them before it kept only Self and
/// those prioritized in front: Self first, then everyone else, each with
/// their circles, health, time with the user and when they were last
/// seen -- or will next be (see [tile]). Above them, the circles, each
/// with its own health: tapping one shows only the people in it, and
/// "Edit" beside it edits it. Archived people are shown only when asked
/// for. The search finds people by name, context, circle and what
/// matters to them. Sorted as listed, or either way by relationship
/// health, when last (or next) seen, or time in the summary's 24 hours
/// or 7 days -- those with nothing to sort by last. "+" adds a person or
/// a circle. It shows what [memory] has, as it changes.
class AllPeopleScreen extends StatefulWidget {
  const AllPeopleScreen({
    super.key,
    required this.memory,
    required this.tile,
    required this.times,
    this.forward = false,
    this.onAddPerson,
    this.onEditCircle,
    this.onReload,
  });

  final PlanMemory memory;

  /// How each person is shown, with their menu.
  final Widget Function(BuildContext context, Person person) tile;

  /// Each person's time and last or next event, to sort by.
  final PeopleTimes? Function() times;

  /// Whether the summary looks on, for "Next seen".
  final bool forward;
  final VoidCallback? onAddPerson;

  /// Adds a circle (with none) or edits one.
  final void Function(Circle? circle)? onEditCircle;
  final Future<void> Function()? onReload;

  @override
  State<AllPeopleScreen> createState() => _AllPeopleScreenState();
}

class _AllPeopleScreenState extends State<AllPeopleScreen> {
  final _search = TextEditingController();
  String _query = '';
  bool _archived = false;
  String? _circle;
  PeopleSort _sort = PeopleSort.listed;
  bool _ascending = false;

  PeopleList? get _people => widget.memory.people;
  TraitScores? get _scores => widget.memory.scores;

  @override
  void initState() {
    super.initState();
    widget.memory.addListener(_changed);
  }

  @override
  void dispose() {
    widget.memory.removeListener(_changed);
    _search.dispose();
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
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
      PeopleSort.seen => widget.forward,
      _ => false,
    };
  });

  int? _circleHealth(Circle c) =>
      _scores?.groupHealth(_people?.inCircle(c.id).map((p) => p.id) ?? []);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final people = _people;
    return Scaffold(
      appBar: AppBar(
        title: const Text('People'),
        actions: [
          PopupMenuButton<PeopleSort>(
            tooltip: 'Sort people',
            icon: const Icon(Icons.sort),
            onSelected: _sortBy,
            itemBuilder: (_) => [
              for (final sort in PeopleSort.values)
                CheckedPopupMenuItem(
                  value: sort,
                  checked: sort == _sort,
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(sort.labelFor(forward: widget.forward)),
                      ),
                      if (sort == _sort && sort != PeopleSort.listed)
                        Icon(
                          _ascending
                              ? Icons.arrow_upward
                              : Icons.arrow_downward,
                          size: 18,
                          semanticLabel: _ascending
                              ? 'Ascending'
                              : 'Descending',
                        ),
                    ],
                  ),
                ),
            ],
          ),
          IconButton(
            tooltip: _archived
                ? 'Hide archived people'
                : 'Show archived people',
            icon: Icon(
              _archived ? Icons.inventory_2 : Icons.inventory_2_outlined,
            ),
            onPressed: () => setState(() => _archived = !_archived),
          ),
          PopupMenuButton<String>(
            tooltip: 'Add a person or circle',
            icon: const Icon(Icons.add),
            onSelected: (choice) => choice == 'circle'
                ? widget.onEditCircle?.call(null)
                : widget.onAddPerson?.call(),
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'person', child: Text('New person')),
              PopupMenuItem(value: 'circle', child: Text('New circle')),
            ],
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: TextField(
              controller: _search,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: 'Search people',
                prefixIcon: const Icon(Icons.search),
                isDense: true,
                filled: true,
                fillColor: theme.colorScheme.surfaceContainerHighest,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: BorderSide.none,
                ),
              ),
              onChanged: (text) => setState(() => _query = text),
            ),
          ),
          if (_sort != PeopleSort.listed)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
              child: Text(
                'By ${_sort.labelFor(forward: widget.forward).toLowerCase()}, '
                '${_ascending ? 'ascending' : 'descending'}',
                style: theme.textTheme.bodySmall,
              ),
            ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: widget.onReload ?? () async {},
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.only(bottom: 24),
                children: people == null
                    ? const [LinearProgressIndicator()]
                    : _list(context, people),
              ),
            ),
          ),
        ],
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
            person.whatMatters,
            if (person.isSelf) 'you',
            for (final id in person.circleIds) circleName(id),
          ]))
            person,
      ],
      _sort,
      ascending: _ascending,
      health: (id) => _scores?.health(id),
      times: widget.times(),
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
              if (circle != null && widget.onEditCircle != null)
                TextButton.icon(
                  onPressed: () => widget.onEditCircle!(circle),
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
      for (final person in shown) widget.tile(context, person),
      if (inCircle.isEmpty)
        const Padding(
          padding: EdgeInsets.all(16),
          child: Text('No one in this circle yet.'),
        )
      else if (shown.isEmpty)
        NoMatches(query: _query),
    ];
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
