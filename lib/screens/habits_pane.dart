import 'package:flutter/material.dart';

import '../models/habit.dart';
import '../models/plan_action.dart';
import '../models/trait.dart';
import '../models/trait_scores.dart';
import '../services/habits_repository.dart';
import '../services/plan_memory.dart';
import '../widgets/error_sheet.dart';
import '../widgets/focus_buttons.dart';
import '../widgets/habit_dialog.dart';
import '../widgets/health.dart';
import '../widgets/plan_pane.dart';
import '../widgets/plan_summaries.dart';
import '../widgets/refreshing_bar.dart';
import 'habit_screen.dart';

/// The Plan page's Habits pane -- what the user practices: each of Self's
/// habits, in its action's color, with the action or group whose events
/// it's about, its status, its health and its last 8 days, and a star.
/// Those starred come first, in the order they were, then the rest by
/// name. Tapping a habit opens its page ([HabitScreen]), whose pencil
/// edits it; its menu archives or restores it; its star focuses on it,
/// on this device only (see [PlanMemory.focus]). "+" adds one. Archived
/// habits are shown only when asked for; deleted ones never. The search
/// finds them by name, action and note.
///
/// Above it all, with a [summary] to measure, the time in its window on
/// the active habits' events: by habit, and by each one's health, those
/// of no habit together as "No habit". It shows what [memory] has, while
/// it loads afresh. [actions] names and colors each habit's action, and
/// gives the groups an event's actions are in; [personNames] and
/// [locationNames] name who a habit's events were with, and where.
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

  /// Whether they've been asked for, this visit, and couldn't be had.
  bool _failed = false;

  /// What the search has in it.
  String _query = '';

  List<Habit>? get _habits => widget.memory.habits;

  /// Each habit's health, worked out from the events.
  TraitScores? get _scores => widget.memory.scores;

  /// Every trait, by id, to name those that apply to a habit.
  Map<String, Trait> get _traits => {
    for (final t in widget.memory.traits ?? const <Trait>[])
      if (t.id != null) t.id!: t,
  };

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

  /// Shows what changed: the scores, as they're worked out again, or
  /// which are starred.
  void _changed() {
    if (mounted) setState(() {});
  }

  /// Loads the habits afresh, and the events around today they're
  /// scored from.
  Future<void> reload() => Future.wait([
    _settle(widget.memory.loadHabits(widget.repository, again: true)),
    ?widget.memory.eventStore?.warm().catchError((Object _) {}),
  ]);

  /// Shows what [loading] loads, once it has. Habits are loaded best
  /// effort: none, once it has, is what says they couldn't be.
  Future<void> _settle(Future<void> loading) async {
    await loading;
    if (mounted) setState(() => _failed = _habits == null);
  }

  void _open(Habit habit) => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => HabitScreen(
        habit: habit,
        actions: widget.actions,
        traits: _traits,
        memory: widget.memory,
        personNames: widget.personNames,
        locationNames: widget.locationNames,
        onEdit: _edit,
      ),
    ),
  );

  /// Adds a habit (with no [habit]) or edits one; returns it as saved,
  /// or null if nothing was.
  Future<Habit?> _edit(Habit? habit) async {
    final repository = widget.repository;
    final saved = await showHabitEditor(
      context,
      habit: habit,
      focus: widget.memory.focus,
      actions: widget.actions,
      traits: [..._traits.values],
      save: (fields) => habit == null
          ? repository.createHabit(
              Habit.fromJson({'id': '', 'action_id': '', ...fields}),
            )
          : repository.updateHabit(habit.id, fields),
    );
    if (saved != null) await reload();
    return saved;
  }

  Future<void> _setStatus(Habit habit, String status) async {
    await runOrShowError(
      context,
      title: "Couldn't save ${habitName(habit)}",
      action: () async {
        await widget.repository.updateHabit(habit.id, {'status': status});
        await reload();
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final habits = _habits;
    final view = widget.summary;
    final byId = {for (final a in widget.actions) a.id: a};
    // Asked for first: asking is what has them worked out again.
    final scores = _scores;
    final focus = widget.memory.focus;
    final kept = [
      for (final h in habits ?? const <Habit>[])
        if (h.status != 'deleted' && (_archived || h.status != 'archived')) h,
    ];
    final starred = {for (final (i, id) in focus.habits.indexed) id: i};
    kept.sort(
      (a, b) => switch ((starred[a.id], starred[b.id])) {
        (final x?, final y?) => x.compareTo(y),
        (_?, null) => -1,
        (null, _?) => 1,
        _ => habitName(a).toLowerCase().compareTo(habitName(b).toLowerCase()),
      },
    );
    final shown = [
      for (final habit in kept)
        if (matchesSearch(_query, [habit.name, habit.note, _path(habit, byId)]))
          habit,
    ];
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
          tooltip: _archived ? 'Hide archived habits' : 'Show archived habits',
          icon: Icon(
            _archived ? Icons.inventory_2 : Icons.inventory_2_outlined,
          ),
          onPressed: () => setState(() => _archived = !_archived),
        ),
        IconButton(
          tooltip: 'New habit',
          icon: const Icon(Icons.add),
          onPressed: habits == null ? null : () => _edit(null),
        ),
      ],
      // Health as it was, while it's worked out again.
      child: RefreshingBar(
        refreshing: widget.memory.rescoring,
        child: RefreshIndicator(
          onRefresh: reload,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.only(bottom: 24),
            children: switch ((habits, _failed)) {
              (null, true) => [
                _message("Couldn't load the habits.", retry: true),
              ],
              (null, false) => const [LinearProgressIndicator()],
              _ => [
                for (final habit in shown) _tile(context, habit, byId),
                if (kept.isEmpty)
                  _message(
                    'No habits yet. Tap + to add one: your events with one '
                    'action, or any in a group, held to traits of their '
                    'own -- practicing guitar mindfully, say.',
                  )
                else if (shown.isEmpty)
                  NoMatches(query: _query),
              ],
            },
          ),
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

  /// [habit]'s action or group, under its groups.
  static String _path(Habit habit, Map<String?, PlanAction> byId) =>
      byId[habit.actionId]?.path ??
      habit.actionPath ??
      switch (byId[habit.actionId]) {
        final a? => actionName(a),
        null => habit.actionId,
      };

  Widget _tile(
    BuildContext context,
    Habit habit,
    Map<String?, PlanAction> byId,
  ) {
    final theme = Theme.of(context);
    final health = habit.active ? _scores?.health(habit.subject) : null;
    final trend = habit.active
        ? _scores?.healthTrend(habit.subject) ?? const <int?>[]
        : const <int?>[];
    return ListTile(
      leading: SizedBox(
        width: 40,
        child: Center(child: actionDot(byId[habit.actionId], size: 16)),
      ),
      title: Text(
        habitName(habit),
        style: habit.active ? null : TextStyle(color: theme.hintColor),
      ),
      // Its health on a line of its own, for the name's room.
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            [
              _path(habit, byId),
              if (!habit.active) habitStatuses[habit.status] ?? habit.status,
            ].join(' · '),
          ),
          if (health != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Row(
                children: [
                  if (trend.nonNulls.isNotEmpty) ...[
                    TrendSparkline(trend: trend),
                    const SizedBox(width: 8),
                  ],
                  HealthDot(rating: health),
                  const SizedBox(width: 8),
                  Flexible(child: Text(healthBand(health))),
                ],
              ),
            ),
        ],
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          focusHabitButton(widget.memory.focus, habit),
          PopupMenuButton<String>(
            tooltip: 'More for ${habitName(habit)}',
            onSelected: (status) => _setStatus(habit, status),
            itemBuilder: (_) => [
              habit.active
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
      onTap: () => _open(habit),
    );
  }
}
