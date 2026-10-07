import 'package:flutter/material.dart';

import '../models/person.dart';
import '../models/plan_action.dart';
import '../models/trait.dart';
import '../models/trait_scores.dart';
import '../widgets/status_message.dart';
import '../services/habits_repository.dart';
import '../services/people_repository.dart';
import '../services/plan_memory.dart';
import '../services/traits_repository.dart';
import '../widgets/error_sheet.dart';
import '../widgets/color_picker.dart' show contrastingColor;
import '../widgets/health.dart';
import '../widgets/person_dialog.dart';
import '../widgets/plan_pane.dart';
import '../widgets/plan_summaries.dart';
import 'person_screen.dart';

/// The Plan page's People pane -- who the user wants to be with: Self,
/// always first, then everyone else, each with the circles they're in
/// and their relationship health, gray (disconnected) to green (healthy),
/// with its last 8 days. Above them, the circles, each with its own
/// health: tapping one shows only the people in it, and "Edit" beside it
/// edits it. Tapping a person opens their page ([PersonScreen]); their
/// menu edits or archives them; Self says how many habits they have.
/// "+" adds a person or a circle. Archived
/// people are shown only when asked for. The search finds people by
/// name, context, circle and what matters to them. Above it all, with a
/// [summary] to measure, the time with people in its window: by person,
/// and by circle, those in none together as "Individuals". It shows what
/// [memory] has, while it loads afresh. [onPeople] is told who's there
/// each time they load.
class PeoplePane extends StatefulWidget {
  const PeoplePane({
    super.key,
    required this.repository,
    required this.memory,
    this.summary,
    this.traits,
    this.onPeople,
    this.habits,
    this.actionNames = const {},
    this.actions = const {},
    this.actionList = const [],
    this.locationNames = const {},
  });

  final PeopleRepository repository;
  final PlanMemory memory;

  /// What the summary measures, and how it's shown; null for none.
  final SummaryView? summary;

  /// For each person's traits, and those their dialog offers.
  final TraitsRepository? traits;
  final ValueChanged<PeopleList>? onPeople;

  /// Self's habits, on their page.
  final HabitsRepository? habits;

  /// Names actions by id, for a person's history.
  final Map<String?, String> actionNames;

  /// The actions and groups a person's own parts can count, by id.
  final Map<String, String> actions;

  /// Every action and group, for Self's habits.
  final List<PlanAction> actionList;

  /// Names locations by id, for where a person's events were.
  final Map<String?, String> locationNames;

  @override
  State<PeoplePane> createState() => PeoplePaneState();
}

class PeoplePaneState extends State<PeoplePane> {
  PeopleList? get _people => widget.memory.people;
  Object? _error;
  bool _archived = false;

  /// What the search has in it.
  String _query = '';

  /// The circle whose people alone are shown, if one's picked.
  String? _circle;

  @override
  void initState() {
    super.initState();
    widget.memory.addListener(_scored);
    _settle(widget.memory.loadPeople(widget.repository));
  }

  @override
  void dispose() {
    widget.memory.removeListener(_scored);
    super.dispose();
  }

  /// Shows the scores again, as they're worked out again.
  void _scored() {
    if (mounted) setState(() {});
  }

  /// Each person's and circle's relationship health, worked out from
  /// their events.
  TraitScores? get _scores => widget.memory.scores;

  int? _circleHealth(Circle c) =>
      _scores?.groupHealth(_people?.inCircle(c.id).map((p) => p.id) ?? []);

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
      final people = _people!;
      setState(() {
        _error = null;
        if (!people.circles.any((c) => c.id == _circle)) _circle = null;
      });
      widget.onPeople?.call(people);
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  /// The traits that could apply to someone: active, and off.
  Future<List<Trait>> _traits() async {
    try {
      return await widget.traits?.traits() ?? const [];
    } catch (_) {
      return const []; // Which apply can wait.
    }
  }

  Future<void> _editPerson(Person? person) async {
    final traits = await _traits();
    if (!mounted) return;
    final repository = widget.repository;
    final saved = await showPersonDialog(
      context,
      person: person,
      circles: _people?.circles ?? const [],
      traits: traits,
      actions: widget.actions,
      save: (fields) => person == null
          ? repository.createPerson(Person.fromJson({'id': '', ...fields}))
          : repository.updatePerson(person.id, fields),
    );
    if (saved != null) await reload();
  }

  Future<void> _editCircle(Circle? circle) async {
    final repository = widget.repository;
    final saved = await showCircleDialog(
      context,
      circle: circle,
      save: (fields) async => circle == null
          ? await repository.createCircle(
              Circle(
                id: '',
                name: fields['name'] as String,
                note: fields['note'] as String?,
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

  void _open(Person person) {
    final people = _people;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PersonScreen(
          person: person,
          traits: widget.traits,
          memory: widget.memory,
          circles: people?.circles ?? const [],
          personNames: {
            for (final p in people?.withSelf ?? const <Person>[])
              p.id: personName(p),
          },
          actionNames: widget.actionNames,
          locationNames: widget.locationNames,
          habits: widget.habits,
          actions: widget.actionList,
          onEdit: () async {
            await _editPerson(person);
            return _people?.withSelf
                .where((p) => p.id == person.id)
                .firstOrNull;
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final people = _people;
    final view = widget.summary;
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
        IconButton(
          tooltip: _archived ? 'Hide archived people' : 'Show archived people',
          icon: Icon(
            _archived ? Icons.inventory_2 : Icons.inventory_2_outlined,
          ),
          onPressed: () {
            setState(() => _archived = !_archived);
          },
        ),
        PopupMenuButton<String>(
          tooltip: 'Add a person or circle',
          icon: const Icon(Icons.add),
          enabled: people != null,
          onSelected: (choice) =>
              choice == 'circle' ? _editCircle(null) : _editPerson(null),
          itemBuilder: (_) => const [
            PopupMenuItem(value: 'person', child: Text('New person')),
            PopupMenuItem(value: 'circle', child: Text('New circle')),
          ],
        ),
      ],
      child: RefreshIndicator(
        onRefresh: reload,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.only(bottom: 24),
          children: switch ((people, _error)) {
            (null, final error?) => [
              LoadError(what: 'people', error: error, onRetry: reload),
              // Self is there regardless.
              _tile(context, defaultSelf, const []),
            ],
            (null, _) => const [LinearProgressIndicator()],
            (final people?, _) => _list(context, people),
          },
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
    final shown = [
      for (final person in inCircle)
        if (matchesSearch(_query, [
          person.name,
          person.context,
          person.whatMatters,
          if (person.isSelf) 'you',
          for (final id in person.circleIds) circleName(id),
        ]))
          person,
    ];
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
                    final h? => _HealthRing(health: h),
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
      for (final person in shown) _tile(context, person, people.circles),
      if (inCircle.isEmpty)
        const Padding(
          padding: EdgeInsets.all(16),
          child: Text('No one in this circle yet.'),
        )
      else if (shown.isEmpty)
        NoMatches(query: _query),
      if (people.people.where((p) => !p.isSelf).isEmpty)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: Text(
            'Tap + to add the people you want to spend time with.',
            style: theme.textTheme.bodySmall,
          ),
        ),
    ];
  }

  Widget _tile(BuildContext context, Person person, List<Circle> circles) {
    final theme = Theme.of(context);
    final names = [
      for (final c in circles)
        if (person.circleIds.contains(c.id)) c.name,
    ];
    final muted = !person.active;
    final health = _scores?.health(person.id);
    final trend = _scores?.healthTrend(person.id) ?? const <int?>[];
    return ListTile(
      onTap: () => _open(person),
      leading: CircleAvatar(
        backgroundColor: switch (health) {
          final h? => relationshipColor(h),
          null => theme.colorScheme.surfaceContainerHighest,
        },
        foregroundColor: switch (health) {
          final h? => contrastingColor(relationshipColor(h)),
          null => theme.colorScheme.onSurfaceVariant,
        },
        child: person.isSelf
            ? const Icon(Icons.person)
            : Text(person.name.isEmpty ? '?' : person.name[0].toUpperCase()),
      ),
      title: Text(
        personName(person),
        style: muted ? TextStyle(color: theme.hintColor) : null,
      ),
      subtitle: switch ([
        if (person.isSelf) 'You',
        if (person.isSelf)
          if (widget.memory.habits?.where((h) => h.active).length case final n?
              when n > 0)
            n == 1 ? '1 habit' : '$n habits',
        ?person.context,
        if (names.isNotEmpty) names.join(', '),
        if (muted) personStatuses[person.status] ?? person.status,
      ]) {
        final lines when lines.isNotEmpty => Text(lines.join(' · ')),
        _ => null,
      },
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (trend.nonNulls.isNotEmpty) ...[
            TrendSparkline(trend: trend, scale: HealthScale.relationship),
            const SizedBox(width: 8),
          ],
          if (health != null)
            HealthDot(rating: health, scale: HealthScale.relationship),
          PopupMenuButton<String>(
            tooltip: 'More for ${personName(person)}',
            onSelected: (choice) => switch (choice) {
              'edit' => _editPerson(person),
              final status => _setStatus(person, status),
            },
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'edit', child: Text('Edit')),
              if (!person.isSelf)
                person.active
                    ? const PopupMenuItem(
                        value: 'archived',
                        child: Text('Archive'),
                      )
                    : const PopupMenuItem(
                        value: 'active',
                        child: Text('Restore'),
                      ),
            ],
          ),
        ],
      ),
    );
  }
}

/// A circle's relationship health, as a ring in its color.
class _HealthRing extends StatelessWidget {
  const _HealthRing({required this.health});

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
