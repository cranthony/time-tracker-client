import 'package:flutter/material.dart';

import '../models/habit.dart';
import '../models/habit_graph.dart';
import '../models/person.dart';
import '../models/plan_action.dart';
import '../models/trait.dart';
import '../models/trait_scores.dart';
import '../services/habits_repository.dart';
import '../services/people_repository.dart';
import '../services/plan_memory.dart';
import '../services/traits_repository.dart';
import '../widgets/color_picker.dart';
import '../widgets/error_sheet.dart';
import '../widgets/foundations_field.dart';
import '../widgets/habit_dialog.dart';
import '../widgets/health.dart';
import '../widgets/hotkeys.dart';
import '../widgets/plan_pane.dart';
import '../widgets/plan_summaries.dart';
import '../widgets/refreshing_bar.dart';
import 'habit_screen.dart';
import 'person_screen.dart';

/// The Plan page's Habits pane -- what the user builds: Self's habits,
/// and the people they've put here, as a graph in layers by what each is
/// built on ([HabitGraph]). Layer 0, at the bottom, has those built on
/// nothing; each layer above, those built on the ones below. Each layer
/// has its own trend: each day, its habits' and people's ratings
/// combined as the scoring defaults' habit layers say -- by default, the
/// lowest.
///
/// Each habit or person is a chip: a habit's in its action's color, a
/// person's plain, with a person by its name. It has their name, their
/// trend (a person's too in a habit's red, yellow and green, as they're
/// rated alongside habits here), how many days in a row they've been healthy (see
/// [consistencyLabel]). Each layer is sorted by name. Tapping one opens their
/// page; holding it offers what it's built on, archiving a habit, or
/// taking a person off the graph. "+" adds a habit; the person button
/// puts people on the graph.
///
/// By default only what's unlocked is shown: those built on nothing, and
/// those whose every foundation is shown and on track (or not rated
/// yet); "Show all" shows the rest. The search looks within what's
/// shown, by name, action and note, and shows what matches -- the match
/// marked -- with everything it's built on. It opens scrolled to the
/// highest layer that's on track with every layer below it.
///
/// Archived habits and people are shown only when asked for; deleted
/// ones never. Above it all, with a [summary] to measure, the time in its
/// window on the active habits' events: by habit, and by each one's
/// health, those of no habit together as "No habit". It shows what
/// [memory] has, while it loads afresh. [actions] names and colors each
/// habit's action, and gives the groups an event's actions are in;
/// [personNames] and [locationNames] name who a habit's events were
/// with, and where.
class HabitsPane extends StatefulWidget {
  const HabitsPane({
    super.key,
    required this.repository,
    required this.memory,
    this.summary,
    this.actions = const [],
    this.personNames = const {},
    this.locationNames = const {},
  });

  final HabitsRepository repository;
  final PlanMemory memory;

  /// What the summary measures, and how it's shown; null for none.
  final SummaryView? summary;

  /// Every action and group.
  final List<PlanAction> actions;
  final Map<String?, String> personNames;
  final Map<String?, String> locationNames;

  @override
  State<HabitsPane> createState() => HabitsPaneState();
}

class HabitsPaneState extends State<HabitsPane> {
  bool _archived = false;

  /// Whether what isn't unlocked yet is shown too.
  bool _showAll = false;

  /// Whether they've been asked for, this visit, and couldn't be had.
  bool _failed = false;

  /// What the search has in it.
  String _query = '';

  /// Whether it's been scrolled to where it opens, once there was
  /// something to scroll.
  bool _scrolled = false;

  /// Each layer shown, by number, to scroll to.
  final _layerKeys = <int, GlobalKey>{};

  List<Habit>? get _habits => widget.memory.habits;

  List<Person> get _people =>
      widget.memory.people?.withSelf ?? const <Person>[];

  /// Each habit's and person's health, worked out from the events.
  TraitScores? get _scores => widget.memory.scores;

  /// Every trait, by id, to name those that apply to a habit.
  Map<String, Trait> get _traits => {
    for (final t in widget.memory.traits ?? const <Trait>[])
      if (t.id != null) t.id!: t,
  };

  PeopleRepository? get _peopleRepository => PeopleScope.of(context);

  @override
  void initState() {
    super.initState();
    widget.memory.addListener(_changed);
    _settle(widget.memory.loadHabits(widget.repository));
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

  /// Loads the habits and people afresh, and the events around today
  /// they're scored from.
  Future<void> reload() => Future.wait([
    _settle(widget.memory.loadHabits(widget.repository, again: true)),
    if (_peopleRepository case final people?)
      widget.memory.loadPeople(people, again: true).catchError((Object _) {}),
    ?widget.memory.eventStore?.warm().catchError((Object _) {}),
  ]);

  /// Shows what [loading] loads, once it has. Habits are loaded best
  /// effort: none, once it has, is what says they couldn't be.
  Future<void> _settle(Future<void> loading) async {
    await loading;
    if (mounted) setState(() => _failed = _habits == null);
  }

  HabitGraph get _graph =>
      HabitGraph(habits: _habits ?? const [], people: _people);

  /// Every habit's and person's name, by id, as foundations name them.
  Map<String, String> get _names => {
    for (final p in _people) p.id: GraphNode.person(p).name,
    for (final h in _habits ?? const <Habit>[]) h.subject: habitName(h),
  };

  void _open(GraphNode node) {
    final page = switch ((node.habit, node.person)) {
      (final habit?, _) => HabitScreen(
        habit: habit,
        actions: widget.actions,
        traits: _traits,
        memory: widget.memory,
        personNames: widget.personNames,
        locationNames: widget.locationNames,
        foundationNames: _names,
        onEdit: _edit,
      ),
      (_, final person?) => PersonScreen(
        person: person,
        traits: TraitsScope.of(context),
        memory: widget.memory,
        circles: widget.memory.people?.circles ?? const [],
        personNames: widget.personNames,
        actionNames: {
          for (final a in widget.actions) a.id: a.path ?? actionName(a),
        },
        locationNames: widget.locationNames,
      ),
      _ => null,
    };
    if (page == null) return;
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));
  }

  /// Adds a habit (with no [habit]) or edits one; returns it as saved,
  /// or null if nothing was.
  Future<Habit?> _edit(Habit? habit) async {
    final repository = widget.repository;
    final saved = await showHabitEditor(
      context,
      habit: habit,
      actions: widget.actions,
      traits: [..._traits.values],
      foundationChoices: foundationChoices(_graph, _people, id: habit?.subject),
      foundationNames: _names,
      scoreParts: widget.memory.scoreDraftParts,
      save: (fields) => habit == null
          ? repository.createHabit(
              Habit.fromJson({'id': '', 'action_id': '', ...fields}),
            )
          : repository.updateHabit(habit.id, fields),
    );
    if (saved != null) await reload();
    return saved;
  }

  /// Saves [action], saying so if it fails, then loads afresh.
  Future<void> _save(String title, Future<void> Function() action) =>
      runOrShowError(
        context,
        title: title,
        action: () async {
          await action();
          await reload();
        },
      );

  Future<void> _setStatus(Habit habit, String status) => _save(
    "Couldn't save ${habitName(habit)}",
    () => widget.repository.updateHabit(habit.id, {'status': status}),
  );

  /// Picks what [node] is built on, and saves it.
  Future<void> _pickFoundations(GraphNode node) async {
    final picked = await showFoundationsPicker(
      context,
      title: '${node.name} is built on',
      choices: foundationChoices(_graph, _people, id: node.id),
      selected: node.foundations,
    );
    if (picked == null || !mounted) return;
    await _save("Couldn't save ${node.name}", () async {
      if (node.habit case final habit?) {
        await widget.repository.updateHabit(habit.id, {
          'foundations': picked.isEmpty ? null : picked,
        });
      } else if ((node.person, _peopleRepository) case (
        final person?,
        final people?,
      )) {
        // Empty, not cleared: they stay on the graph.
        await people.updatePerson(person.id, {'foundations': picked});
      }
    });
  }

  /// Puts people picked from those not on it on the graph, built on
  /// nothing to start with.
  Future<void> _addPeople() async {
    final people = _peopleRepository;
    if (people == null) return;
    final graph = _graph;
    final picked = await showFoundationsPicker(
      context,
      title: 'Put people on the graph',
      choices: [
        for (final p in _people)
          if (p.active && !graph.nodes.containsKey(p.id)) GraphNode.person(p),
      ],
      selected: const [],
    );
    if (picked == null || picked.isEmpty || !mounted) return;
    await _save("Couldn't put them on the graph", () async {
      for (final id in picked) {
        await people.updatePerson(id, {'foundations': <String>[]});
      }
    });
  }

  Future<void> _menu(GraphNode node) async {
    final picked = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text(
                node.name,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            ListTile(
              leading: const Icon(Icons.open_in_new),
              title: const Text('Open'),
              onTap: () => Navigator.of(context).pop('open'),
            ),
            ListTile(
              leading: const Icon(Icons.account_tree_outlined),
              title: const Text('Built on…'),
              onTap: () => Navigator.of(context).pop('foundations'),
            ),
            if (node.habit case final habit?)
              ListTile(
                leading: Icon(
                  habit.active ? Icons.archive_outlined : Icons.unarchive,
                ),
                title: Text(habit.active ? 'Archive' : 'Restore'),
                onTap: () =>
                    Navigator.of(context)
                        .pop(habit.active ? 'archived' : 'active'),
              )
            else if (node.person?.onHabitGraph ?? false)
              ListTile(
                leading: const Icon(Icons.person_remove_outlined),
                title: const Text('Take off the graph'),
                onTap: () => Navigator.of(context).pop('remove'),
              ),
          ],
        ),
      ),
    );
    if (!mounted) return;
    switch (picked) {
      case 'open':
        _open(node);
      case 'foundations':
        await _pickFoundations(node);
      case 'archived' || 'active':
        await _setStatus(node.habit!, picked!);
      case 'remove':
        if ((node.person, _peopleRepository) case (final p?, final people?)) {
          await _save(
            "Couldn't take ${node.name} off the graph",
            () => people.updatePerson(p.id, {'foundations': null}),
          );
        }
    }
  }

  /// Whether [id]'s last rating is on track (or healthy, for a person),
  /// or they've none yet.
  bool _onTrack(String id) => switch (_scores?.health(id)) {
    final rating? => rating >= healthyRating,
    null => true,
  };

  /// What a search looks through, for [node].
  List<String?> _searched(GraphNode node, Map<String?, PlanAction> byId) =>
      switch ((node.habit, node.person)) {
        (final h?, _) => [node.name, h.note, _path(h, byId)],
        (_, final p?) => [node.name, p.context],
        _ => const [],
      };

  @override
  Widget build(BuildContext context) {
    final habits = _habits;
    final view = widget.summary;
    final byId = {for (final a in widget.actions) a.id: a};
    // Asked for first: asking is what has them worked out again.
    final scores = _scores;
    final graph = _graph;
    final visible = {
      for (final n in graph.nodes.values)
        if (_archived || !n.archived) n.id,
    };
    final unlocked = graph.unlocked(_onTrack, among: visible);
    final base = _showAll ? visible : unlocked;
    final shown = _query.trim().isEmpty
        ? base
        : graph
              .withFoundations([
                for (final id in base)
                  if (matchesSearch(_query, _searched(graph.nodes[id]!, byId)))
                    id,
              ])
              .intersection(base);
    final layers = <int, List<GraphNode>>{};
    for (final id in shown) {
      (layers[graph.layerOf(id)] ??= []).add(graph.nodes[id]!);
    }
    final numbers = layers.keys.toList()..sort();
    for (final members in layers.values) {
      members.sort(
        (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
      );
    }
    // Opens at the highest layer on track with every one below it.
    var opening = numbers.isEmpty ? null : numbers.first;
    for (final n in numbers) {
      if (!layers[n]!.every((m) => _onTrack(m.id))) break;
      opening = n;
    }
    if (!_scrolled && opening != null && scores != null) {
      _scrolled = true;
      final key = _layerKeys[opening] ??= GlobalKey();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final context = key.currentContext;
        final layer = context?.findRenderObject();
        // Only its own list: Scrollable.ensureVisible would also swipe
        // the Plan screen's panes back to this one.
        if (context != null && layer != null) {
          Scrollable.of(context).position.ensureVisible(layer);
        }
      });
    }
    final hidden = visible.length - unlocked.length;
    return PlanPane(
      searchHint: 'Search habits',
      onSearch: (query) => setState(() => _query = query),
      summary: view == null || habits == null
          ? null
          : PlanSummary(
              view: view,
              titles: const ['By habit', 'By health'],
              pages: (events) => [
                habitTime(events, view.window, habits, byId),
                habitHealthTime(
                  events,
                  view.window,
                  habits,
                  byId,
                  (habit) => scores?.health(habit.subject),
                ),
              ],
            ),
      actions: [
        IconButton(
          tooltip: _showAll
              ? 'Show only what its foundations unlock'
              : 'Show all habits',
          icon: Icon(_showAll ? Icons.lock_open : Icons.lock_outline),
          onPressed: () => setState(() => _showAll = !_showAll),
        ),
        IconButton(
          tooltip: _archived ? 'Hide archived habits' : 'Show archived habits',
          icon: Icon(
            _archived ? Icons.inventory_2 : Icons.inventory_2_outlined,
          ),
          onPressed: () => setState(() => _archived = !_archived),
        ),
        if (_peopleRepository != null)
          IconButton(
            tooltip: 'Put people on the graph',
            icon: const Icon(Icons.person_add_alt),
            onPressed: habits == null ? null : _addPeople,
          ),
        NewHotkey(
          child: IconButton(
            tooltip: 'New habit',
            icon: const Icon(Icons.add),
            onPressed: habits == null ? null : () => _edit(null),
          ),
        ),
      ],
      // Health as it was, while it's worked out again.
      child: RefreshingBar(
        refreshing: widget.memory.rescoring,
        child: RefreshIndicator(
          onRefresh: reload,
          child: switch ((habits, _failed)) {
            (null, true) => ListView(
              children: [_message("Couldn't load the habits.", retry: true)],
            ),
            (null, false) => ListView(
              children: const [LinearProgressIndicator()],
            ),
            _ when graph.nodes.isEmpty => ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                _message(
                  'No habits yet. Tap + to add one: your events with one '
                  'action, or any in a group, held to traits of their '
                  'own -- practicing guitar mindfully, say.',
                ),
              ],
            ),
            _ => ListView(
              // Layer 0 at the bottom, the rest above it.
              reverse: true,
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.symmetric(vertical: 12),
              children: [
                for (final n in numbers) _layer(context, n, layers[n]!, byId),
                if (shown.isEmpty && _query.trim().isNotEmpty)
                  NoMatches(query: _query),
                if (!_showAll && hidden > 0) _locked(context, hidden),
              ],
            ),
          },
        ),
      ),
    );
  }

  Widget _message(String text, {bool retry = false}) => Padding(
    padding: const EdgeInsets.all(16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(text),
        if (retry)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: OutlinedButton(
              onPressed: reload,
              child: const Text('Try again'),
            ),
          ),
      ],
    ),
  );

  /// Says how many wait on foundations not yet on track.
  Widget _locked(BuildContext context, int hidden) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 4, 8, 4),
    child: Row(
      children: [
        Icon(Icons.lock_outline, size: 16, color: Theme.of(context).hintColor),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            '$hidden more wait${hidden == 1 ? 's' : ''} on '
            'foundations not yet on track.',
            style: TextStyle(color: Theme.of(context).hintColor),
          ),
        ),
        TextButton(
          onPressed: () => setState(() => _showAll = true),
          child: const Text('Show all'),
        ),
      ],
    ),
  );

  /// [habit]'s action or group, under its groups.
  static String _path(Habit habit, Map<String?, PlanAction> byId) =>
      byId[habit.actionId]?.path ??
      habit.actionPath ??
      switch (byId[habit.actionId]) {
        final a? => actionName(a),
        null => habit.actionId,
      };

  Widget _layer(
    BuildContext context,
    int number,
    List<GraphNode> members,
    Map<String?, PlanAction> byId,
  ) {
    final theme = Theme.of(context);
    final trend =
        _scores?.layerTrend([for (final m in members) m.id]) ?? const <int?>[];
    return Padding(
      key: _layerKeys[number] ??= GlobalKey(),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('Layer $number', style: theme.textTheme.labelLarge),
              if (trend.nonNulls.isNotEmpty) ...[
                const SizedBox(width: 8),
                TrendSparkline(trend: trend),
              ],
              const SizedBox(width: 8),
              const Expanded(child: Divider()),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [for (final m in members) _chip(context, m, byId)],
          ),
        ],
      ),
    );
  }

  Widget _chip(
    BuildContext context,
    GraphNode node,
    Map<String?, PlanAction> byId,
  ) {
    final theme = Theme.of(context);
    final action = byId[node.habit?.actionId];
    final background =
        parseColor(action?.backgroundColor ?? action?.effectiveColor) ??
        theme.colorScheme.surfaceContainerHighest;
    final foreground =
        ThemeData.estimateBrightnessForColor(background) == Brightness.dark
        ? Colors.white
        : Colors.black87;
    final active = node.habit?.active ?? node.person!.active;
    final trend = active
        ? _scores?.healthTrend(node.id) ?? const <int?>[]
        : const <int?>[];
    final consistency = active ? _scores?.consistency(node.id) ?? 0 : 0;
    final style = theme.textTheme.labelLarge?.copyWith(color: foreground);
    return Opacity(
      opacity: active ? 1 : 0.6,
      child: Material(
        color: background,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => _open(node),
          onLongPress: () => _menu(node),
          onSecondaryTap: () => _menu(node),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (node.isPerson) ...[
                  Icon(Icons.person, size: 14, color: foreground),
                  const SizedBox(width: 4),
                ],
                Flexible(
                  child: Text.rich(
                    TextSpan(
                      children: highlightMatches(
                        node.name,
                        _query,
                        TextStyle(
                          backgroundColor: theme.colorScheme.tertiaryContainer,
                          color: theme.colorScheme.onTertiaryContainer,
                        ),
                      ),
                    ),
                    style: style,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (trend.nonNulls.isNotEmpty) ...[
                  const SizedBox(width: 6),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surface.withValues(alpha: 0.85),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 1,
                        vertical: 2,
                      ),
                      child: TrendSparkline(trend: trend),
                    ),
                  ),
                ],
                if (consistency > 0) ...[
                  const SizedBox(width: 6),
                  Text(
                    consistencyLabel(
                      consistency,
                      maxConsistency: maxConsistencyDays,
                    ),
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: foreground,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
