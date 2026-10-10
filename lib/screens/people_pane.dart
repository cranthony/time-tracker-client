import 'package:flutter/material.dart';

import '../models/habit.dart';
import '../models/people_times.dart';
import '../models/person.dart';
import '../models/plan_action.dart';
import '../models/trait.dart';
import '../models/trait_scores.dart';
import '../widgets/status_message.dart';
import '../services/focus_store.dart';
import '../services/habits_repository.dart';
import '../services/people_repository.dart';
import '../services/plan_memory.dart';
import '../services/traits_repository.dart';
import '../widgets/error_sheet.dart';
import '../widgets/habit_dialog.dart';
import '../widgets/health.dart';
import '../widgets/person_dialog.dart';
import '../widgets/person_tile.dart';
import '../widgets/plan_pane.dart';
import '../widgets/plan_summaries.dart';
import 'all_people_screen.dart';
import 'habit_screen.dart';
import 'person_screen.dart';
import '../services/client_health.dart';
import '../services/work_timing.dart';
import '../widgets/refreshing_bar.dart';
import '../models/time_split.dart';

/// The Plan page's People pane -- who the user wants to be with -- in two
/// sections, one over the other, each folded away by tapping its head:
///
/// * **Self**, with their relationship health and its last 8 days in its
///   head, and under it the two habits they focus on, each with its
///   health; "All habits and scores" opens their page ([PersonScreen]).
/// * **People**, the three the user prioritizes, each with
///   their health, their time with the user in the summary's 24 hours and
///   7 days, and the last event with them -- or, with the summary looking
///   on, the next ([PersonTile]); "All people and circles" opens everyone
///   ([AllPeopleScreen]), to sort, search and edit.
///
/// Habits are focused on from their page, and people prioritized from
/// their menu, on this device only (see [PlanMemory.focus]). Tapping a
/// person opens their page; their menu edits, prioritizes or archives
/// them. There's no search here, with so few: everyone's is on their own
/// page. "+", in People's head, adds a person or a circle. Above it all, with a
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

  /// Whether each section is open.
  bool _selfOpen = true;
  bool _prioritizedOpen = true;

  /// Every trait, by id, to name those that apply to a habit.
  Map<String, Trait> _traitList = const {};

  @override
  void initState() {
    super.initState();
    widget.memory.addListener(_changed);
    _settle(widget.memory.loadPeople(widget.repository));
    if (widget.habits case final habits?) widget.memory.loadHabits(habits);
    _loadTraitList();
  }

  @override
  void dispose() {
    widget.memory.removeListener(_changed);
    super.dispose();
  }

  /// Shows what changed: the scores, as they're worked out again, or
  /// who's prioritized.
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

  /// Loads everyone afresh, Self's habits, and the events around today
  /// they're scored from.
  Future<void> reload() => Future.wait([
    _settle(widget.memory.loadPeople(widget.repository, again: true)),
    if (widget.habits case final habits?)
      widget.memory.loadHabits(habits, again: true),
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

  /// The traits that could apply to someone: active, and off.
  Future<List<Trait>> _traits() async {
    try {
      return await widget.traits?.traits() ?? const [];
    } catch (_) {
      return const []; // Which apply can wait.
    }
  }

  Future<void> _loadTraitList() async {
    try {
      final traits = await widget.traits?.traits(
        statuses: [...traitStatuses.keys],
      );
      if (!mounted || traits == null) return;
      setState(
        () => _traitList = {
          for (final t in traits)
            if (t.id != null) t.id!: t,
        },
      );
    } catch (_) {
      // Named by id, then.
    }
  }

  Future<void> _editPerson(Person? person) async {
    final traits = await _traits();
    if (!mounted) return;
    final repository = widget.repository;
    final saved = await showPersonEditor(
      context,
      person: person,
      focus: widget.memory.focus,
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

  Map<String?, String> get _personNames => {
    for (final p in _people?.withSelf ?? const <Person>[]) p.id: personName(p),
  };

  void _open(Person person) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PersonScreen(
          person: person,
          traits: widget.traits,
          memory: widget.memory,
          circles: _people?.circles ?? const [],
          personNames: _personNames,
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

  void _openHabit(Habit habit) {
    final repository = widget.habits;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => HabitScreen(
          habit: habit,
          actions: widget.actionList,
          traits: _traitList,
          memory: widget.memory,
          personNames: _personNames,
          locationNames: widget.locationNames,
          onEdit: repository == null
              ? null
              : (habit) async {
                  final saved = await showHabitEditor(
                    context,
                    habit: habit,
                    focus: widget.memory.focus,
                    actions: widget.actionList,
                    traits: [..._traitList.values],
                    save: (fields) => repository.updateHabit(habit.id, fields),
                  );
                  if (saved != null) {
                    await widget.memory.loadHabits(repository, again: true);
                  }
                  return saved;
                },
        ),
      ),
    );
  }

  void _openAll() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => AllPeopleScreen(
          memory: widget.memory,
          tile: _tile,
          times: () => _times,
          forward: widget.summary?.window.forward ?? false,
          onAddPerson: () => _editPerson(null),
          onEditCircle: _editCircle,
          onReload: reload,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
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
      // Health as it was, while it's worked out again.
      child: RefreshingBar(
        refreshing: widget.memory.rescoring,
        child: RefreshIndicator(
          onRefresh: reload,
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
                ..._selfSection(context, people.self),
                ..._prioritizedSection(context, people),
              ],
            },
          ),
        ),
      ),
    );
  }

  /// Self, and the habits they focus on.
  List<Widget> _selfSection(BuildContext context, Person self) {
    final theme = Theme.of(context);
    final focus = widget.memory.focus;
    final habits = {
      for (final h in widget.memory.habits ?? const <Habit>[])
        if (h.status != 'deleted') h.id: h,
    };
    final focused = [for (final id in focus.habits) ?habits[id]];
    final health = _scores?.health(self.id);
    final trend = _scores?.healthTrend(self.id) ?? const <int?>[];
    return [
      _SectionHead(
        title: 'Self',
        open: _selfOpen,
        onTap: () => setState(() => _selfOpen = !_selfOpen),
        trailing: [
          if (trend.nonNulls.isNotEmpty) ...[
            TrendSparkline(trend: trend, scale: HealthScale.relationship),
            const SizedBox(width: 8),
          ],
          if (health != null)
            HealthDot(rating: health, scale: HealthScale.relationship),
        ],
      ),
      if (_selfOpen) ...[
        if (widget.habits != null && widget.memory.habits != null) ...[
          for (final habit in focused) _habitTile(context, habit),
          if (focused.isEmpty)
            _hint(
              theme,
              habits.isEmpty
                  ? 'No habits yet: add one from your page.'
                  : 'Star up to ${FocusStore.maxHabits} habits on their '
                        'pages to focus on them here.',
            ),
        ],
        _button(
          context,
          'All habits and scores',
          Icons.person_outline,
          () => _open(self),
        ),
      ],
    ];
  }

  Widget _habitTile(BuildContext context, Habit habit) {
    final action = widget.actionList
        .where((a) => a.id == habit.actionId)
        .firstOrNull;
    final health = _scores?.health(habit.subject);
    final trend = _scores?.healthTrend(habit.subject) ?? const <int?>[];
    return ListTile(
      leading: SizedBox(
        width: 40,
        child: Center(child: actionDot(action, size: 16)),
      ),
      title: Text(habitName(habit)),
      subtitle: Text(
        [
          action?.path ??
              habit.actionPath ??
              (action == null ? habit.actionId : actionName(action)),
          if (health != null) healthBand(health),
        ].join(' · '),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (trend.nonNulls.isNotEmpty) ...[
            TrendSparkline(trend: trend),
            const SizedBox(width: 8),
          ],
          if (health != null) HealthDot(rating: health),
        ],
      ),
      onTap: () => _openHabit(habit),
    );
  }

  /// The people prioritized.
  List<Widget> _prioritizedSection(BuildContext context, PeopleList people) {
    final theme = Theme.of(context);
    final byId = {
      for (final p in people.people)
        if (!p.isSelf && p.status != 'deleted') p.id: p,
    };
    final picked = [for (final id in widget.memory.focus.people) ?byId[id]];
    return [
      _SectionHead(
        title: 'People',
        open: _prioritizedOpen,
        onTap: () => setState(() => _prioritizedOpen = !_prioritizedOpen),
        trailing: [
          PopupMenuButton<String>(
            tooltip: 'Add a person or circle',
            icon: const Icon(Icons.add),
            onSelected: (choice) =>
                choice == 'circle' ? _editCircle(null) : _editPerson(null),
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'person', child: Text('New person')),
              PopupMenuItem(value: 'circle', child: Text('New circle')),
            ],
          ),
        ],
      ),
      if (_prioritizedOpen) ...[
        for (final person in picked) _tile(context, person),
        if (picked.isEmpty)
          _hint(
            theme,
            byId.isEmpty
                ? 'Tap + to add the people you want to spend time with.'
                : 'Prioritize up to ${FocusStore.maxPeople} people from '
                      'their menu, in All people, to keep them here.',
          ),
        _button(
          context,
          'All people and circles',
          Icons.groups_outlined,
          _openAll,
        ),
      ],
    ];
  }

  Widget _hint(ThemeData theme, String text) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
    child: Text(text, style: theme.textTheme.bodySmall),
  );

  Widget _button(
    BuildContext context,
    String label,
    IconData icon,
    VoidCallback onPressed,
  ) => Align(
    alignment: AlignmentDirectional.centerStart,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: TextButton.icon(
        onPressed: onPressed,
        icon: Icon(icon),
        label: Text(label),
      ),
    ),
  );

  /// [person], with their time and last or next event, and their menu:
  /// edit, prioritize, archive.
  Widget _tile(BuildContext context, Person person) {
    final focus = widget.memory.focus;
    final prioritized = focus.isPrioritized(person.id);
    final circles = [
      for (final c in _people?.circles ?? const <Circle>[])
        if (person.circleIds.contains(c.id)) c.name,
    ];
    return PersonTile(
      person: person,
      circles: circles,
      health: _scores?.health(person.id),
      trend: _scores?.healthTrend(person.id) ?? const [],
      times: _times,
      durations: widget.summary?.durations ?? true,
      prioritized: prioritized,
      onTap: () => _open(person),
      menu: PopupMenuButton<String>(
        tooltip: 'More for ${personName(person)}',
        onSelected: (choice) => switch (choice) {
          'edit' => _editPerson(person),
          'prioritize' => focus.setPrioritized(person.id, !prioritized),
          final status => _setStatus(person, status),
        },
        itemBuilder: (_) => [
          const PopupMenuItem(value: 'edit', child: Text('Edit')),
          if (!person.isSelf)
            PopupMenuItem(
              value: 'prioritize',
              enabled: prioritized || !focus.peopleFull,
              child: Text(switch ((prioritized, focus.peopleFull)) {
                (true, _) => "Don't prioritize",
                (false, false) => 'Prioritize',
                (false, true) => 'Prioritize (${FocusStore.maxPeople} already)',
              }),
            ),
          if (!person.isSelf)
            person.active
                ? const PopupMenuItem(value: 'archived', child: Text('Archive'))
                : const PopupMenuItem(value: 'active', child: Text('Restore')),
        ],
      ),
    );
  }
}

/// A section's head: its [title], what's [trailing] it, and an arrow
/// that says whether it's [open]; tapping it opens or folds it.
class _SectionHead extends StatelessWidget {
  const _SectionHead({
    required this.title,
    required this.open,
    required this.onTap,
    this.trailing = const [],
  });

  final String title;
  final bool open;
  final VoidCallback onTap;
  final List<Widget> trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surfaceContainer,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 12, 10),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: theme.textTheme.titleMedium,
                  semanticsLabel: '$title, ${open ? 'open' : 'folded away'}',
                ),
              ),
              ...trailing,
              const SizedBox(width: 4),
              Icon(
                open ? Icons.expand_less : Icons.expand_more,
                semanticLabel: open ? 'Fold away $title' : 'Open $title',
              ),
            ],
          ),
        ),
      ),
    );
  }
}
