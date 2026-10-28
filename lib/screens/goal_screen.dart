import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/goal.dart';
import '../models/goal_activation.dart';
import '../models/habit.dart';
import '../models/recurring_goal.dart';
import '../services/goals_repository.dart';
import '../services/plan_memory.dart';
import '../widgets/app_menu.dart' show RefreshButton;
import '../widgets/circle_icon.dart';
import '../widgets/color_picker.dart' show ColorDot;
import '../widgets/event_description.dart';
import '../widgets/durations.dart';
import '../widgets/goal_editor.dart';
import '../widgets/goal_color.dart';
import '../widgets/goal_fields.dart';
import '../widgets/goal_flows.dart';
import '../widgets/goal_reorder_list.dart';
import '../widgets/goal_starts.dart';
import '../widgets/goal_tile.dart';
import '../widgets/hotkeys.dart';
import '../widgets/priority_chip.dart';
import 'habit_pages.dart';
import 'person_pages.dart';

/// A goal's page, the same for a goal at any depth: read only, with the
/// pencil in its bar to edit it. Its title has its path (its parents'
/// titles) under it, and lines to its left, one for each level deep it
/// is -- as its edit page's bar has them ([GoalBarTitle]). Below, its
/// fields as its edit page lays them out ([GoalField]), each said even
/// with nothing in it: its title in full, as the bar may cut it short;
/// its status, with what can change it, and when it
/// started and closed; its deadline, and how it follows its parent's;
/// its priority, its own or where it's inherited from; its expected time
/// and the time spent; whether its parent needs it; its people, each
/// tapped to open their page (a circle, its page); its description, definition of done and attribution hints. Then the goals
/// directly under it (as [byPriority] lists them, filtered by status),
/// each opening its own page, held and dragged to reorder it
/// ([GoalReorderList]), with "+" to add one; and its history, each
/// change's time tapped to change it, its note added or changed, or
/// deleted. D marks it done, M missed, and T missed to try again,
/// whenever it can be -- each close asking for a note to keep with it.
class GoalScreen extends StatefulWidget {
  const GoalScreen({
    super.key,
    required this.goalId,
    required this.repository,
    required this.memory,
  });

  final String goalId;
  final GoalsRepository repository;
  final PlanMemory memory;

  @override
  State<GoalScreen> createState() => _GoalScreenState();
}

class _GoalScreenState extends State<GoalScreen> {
  var _statuses = const {'inactive', 'active'};

  /// The pull-to-refresh, which the refresh button pulls down.
  final _refresher = GlobalKey<RefreshIndicatorState>();

  GoalActions get _actions => GoalActions(
    context: context,
    repository: widget.repository,
    memory: widget.memory,
  );

  @override
  void initState() {
    super.initState();
    widget.memory.addListener(_changed);
  }

  @override
  void dispose() {
    widget.memory.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  /// Every goal again, from the server.
  Future<void> _reload() =>
      widget.memory.loadGoals(widget.repository, again: true);

  void _open(Goal goal) => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => GoalScreen(
        goalId: goal.id,
        repository: widget.repository,
        memory: widget.memory,
      ),
    ),
  );

  Future<void> _menu(String action, Goal goal) async {
    final actions = _actions;
    switch (action) {
      case 'move':
        await actions.move(goal);
      case 'delete':
        await actions.delete(goal);
        if (mounted &&
            widget.memory.goals?.any((g) => g.id == goal.id) != true) {
          Navigator.of(context).pop();
        }
      case 'retry':
        await actions.retry(goal);
      case 'next':
        await actions.addNext(goal);
      case 'until':
        await actions.deactivateUntil(goal);
      default:
        await actions.setStatus(goal, action);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tree = GoalTree(widget.memory.goals ?? const []);
    final goal = tree[widget.goalId];
    if (goal == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: Text('This goal is gone.')),
      );
    }
    final spent = keptGoalTime(widget.memory, tree);
    final children = tree.childrenOf(goal.id);
    final shown = byPriority([
      for (final c in children)
        if (_statuses.contains(c.status)) c,
    ], tree);
    bool can(String status) => _statusMoves(goal).any((m) => m.$1 == status);
    return HotkeyBindings(
      bindings: [
        HotkeyBinding(
          const HotkeyTrigger.key(LogicalKeyboardKey.keyD),
          () => _actions.setStatus(goal, 'done'),
          when: () => can('done'),
        ),
        HotkeyBinding(
          const HotkeyTrigger.key(LogicalKeyboardKey.keyM),
          () => _actions.setStatus(goal, 'missed'),
          when: () => can('missed'),
        ),
        HotkeyBinding(
          const HotkeyTrigger.key(LogicalKeyboardKey.keyT),
          () => _actions.retry(goal),
          when: () => _canRetry(goal),
        ),
      ],
      child: Scaffold(
        appBar: AppBar(
          titleSpacing: 0,
          title: GoalBarTitle(
            title: goalTitle(goal),
            path: tree.pathOf(goal.id),
          ),
          actions: [
            RefreshButton(
              onRefresh: () async => _refresher.currentState?.show(),
            ),
            EditHotkey(
              child: IconButton(
                tooltip: 'Edit',
                icon: const Icon(Icons.edit_outlined),
                onPressed: () => _actions.edit(goal),
              ),
            ),
            PopupMenuButton<String>(
              onSelected: (action) => _menu(action, goal),
              itemBuilder: (context) => [
                for (final (status, label) in _statusMoves(goal))
                  PopupMenuItem(value: status, child: Text(label)),
                if (_canRetry(goal))
                  const PopupMenuItem(value: 'retry', child: Text(_retryLabel)),
                if (goal.active)
                  const PopupMenuItem(value: 'until', child: Text(_untilLabel)),
                const PopupMenuDivider(),
                if (!goal.closed)
                  const PopupMenuItem(
                    value: 'next',
                    child: Text('Add next goal…'),
                  ),
                const PopupMenuItem(value: 'move', child: Text('Move…')),
                const PopupMenuItem(value: 'delete', child: Text('Delete…')),
              ],
            ),
          ],
        ),
        body: RefreshIndicator(
          key: _refresher,
          onRefresh: _reload,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.only(bottom: 24),
            children: [
              _fields(context, goal, tree, spent[goal.id]),
              if (goal.habitId case final habitId?) _fromHabit(habitId),
              const Divider(height: 24),
              Padding(
                padding: const EdgeInsetsDirectional.fromSTEB(16, 0, 4, 0),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Sub-goals',
                        style: theme.textTheme.titleMedium,
                      ),
                    ),
                    GoalStatusFilter(
                      statuses: _statuses,
                      onChanged: (picked) => setState(() => _statuses = picked),
                    ),
                    NewHotkey(
                      child: IconButton(
                        tooltip: 'New sub-goal',
                        icon: const Icon(Icons.add),
                        onPressed: goal.closed
                            ? null
                            : () => _actions.add(parent: goal),
                      ),
                    ),
                  ],
                ),
              ),
              if (children.isEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                  child: Text(
                    goal.closed
                        ? 'Nothing under it.'
                        : 'Nothing under it yet. Tap + to add a piece of it.',
                    style: TextStyle(color: theme.hintColor),
                  ),
                )
              else if (shown.isEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                  child: Text(
                    'None with the statuses shown.',
                    style: TextStyle(color: theme.hintColor),
                  ),
                ),
              // What J and K go down and up: not the buttons over them, nor
              // the history under them.
              HotkeyItems(
                child: GoalReorderList(
                  goals: shown,
                  tree: tree,
                  scrolls: false,
                  onMove: _actions.reorder,
                  tile: (child) => GoalTile(
                    goal: child,
                    spent: spent[child.id],
                    subGoals: tree.childrenOf(child.id).length,
                    priority: tree.priorityOf(child.id),
                    tree: tree,
                    onTap: () => _open(child),
                    onEdit: () => _actions.edit(child),
                  ),
                ),
              ),
              const Divider(height: 24),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text('History', style: theme.textTheme.titleMedium),
              ),
              for (final (i, change) in goal.history.indexed.toList().reversed)
                ListTile(
                  dense: true,
                  leading: const Icon(Icons.history, size: 20),
                  title: Text(goalStatuses[change.status] ?? change.status),
                  subtitle: Text(
                    [
                      change.deadline == null
                          ? _when(context, change.at)
                          : '${_when(context, change.at)} · '
                                'due ${deadlineLabel(context, change.deadline)}',
                      ?change.note,
                    ].join('\n'),
                  ),
                  isThreeLine: change.note != null,
                  onTap: () => _actions.retime(goal, i),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: change.note == null
                            ? 'Add a note'
                            : 'Change the note',
                        icon: const Icon(Icons.edit_note, size: 20),
                        onPressed: () => _actions.annotate(goal, i),
                      ),
                      if (goal.history.length >= 2)
                        IconButton(
                          tooltip: 'Delete this change',
                          icon: const Icon(Icons.delete_outline, size: 20),
                          onPressed: () => _actions.forget(goal, i),
                        ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// That it's one of habit [habitId]'s recurring goal's goals; tapped,
  /// it opens the habit's page.
  Widget _fromHabit(String habitId) {
    final habit = widget.memory.habits
        ?.where((h) => h.id == habitId)
        .firstOrNull;
    final period = goalPeriods[habit?.recurringGoal?.period]?.$1;
    final pages = habit == null ? null : HabitPages.of(context, widget.memory);
    return ListTile(
      leading: const Icon(Icons.repeat),
      title: Text(
        'From the habit ${habit == null ? habitId : habitName(habit)}',
      ),
      subtitle: Text(
        period == null
            ? 'One of its goals, one each period'
            : 'One of its goals: one each ${period.toLowerCase()}, the next '
                  'made once this one is done',
      ),
      trailing: pages == null ? null : const Icon(Icons.chevron_right),
      onTap: pages == null ? null : () => pages.open(context, habit!),
    );
  }

  /// What [goal]'s status can change to, with what each's called.
  static List<(String, String)> _statusMoves(Goal goal) =>
      switch (goal.status) {
        'active' => const [
          ('done', 'Mark done'),
          ('missed', 'Mark missed'),
          ('obsolete', 'Mark obsolete'),
          ('inactive', 'Deactivate'),
        ],
        'inactive' => const [
          ('active', 'Activate'),
          ('obsolete', 'Mark obsolete'),
          ('missed', 'Mark missed'),
        ],
        _ => const [('active', 'Reopen'), ('inactive', 'Reopen as inactive')],
      };

  static const _retryLabel = 'Missed, try again…';

  static const _untilLabel = 'Deactivate until…';

  /// Whether [goal] can be marked missed and tried again: open, with a
  /// deadline -- passed or not.
  static bool _canRetry(Goal goal) => goal.open && goal.due != null;

  /// [goal]'s status, with the first two it can change to, trying it
  /// again if it can be, and, active, deactivating it until something
  /// comes.
  Widget _status(Goal goal) => Wrap(
    spacing: 8,
    runSpacing: 4,
    crossAxisAlignment: WrapCrossAlignment.center,
    children: [
      Chip(
        avatar: Icon(
          Icons.flag_outlined,
          size: 16,
          color: goalColor(context, goal),
        ),
        label: Text(goalStatuses[goal.status] ?? goal.status),
      ),
      for (final (status, label) in _statusMoves(goal).take(2))
        _hinted(
          _statusHotkeys[status],
          OutlinedButton(
            onPressed: () => _actions.setStatus(goal, status),
            child: Text(label),
          ),
        ),
      if (_canRetry(goal))
        HotkeyHint(
          Hotkey.retry,
          child: OutlinedButton(
            onPressed: () => _actions.retry(goal),
            child: const Text(_retryLabel),
          ),
        ),
      if (goal.active)
        OutlinedButton(
          onPressed: () => _actions.deactivateUntil(goal),
          child: const Text(_untilLabel),
        ),
    ],
  );

  /// The keys that change a goal's status to each one that has one: D
  /// done, M missed -- whenever it can be, its button shown or not.
  static const _statusHotkeys = {
    'done': Hotkey.markDone,
    'missed': Hotkey.markMissed,
  };

  /// [button], with [hotkey]'s letter on it while Ctrl is held, if any.
  static Widget _hinted(Hotkey? hotkey, Widget button) =>
      hotkey == null ? button : HotkeyHint(hotkey, child: button);

  /// [goal]'s fields, in the order its edit page has them and under the
  /// same labels ([GoalField]), each said even with nothing in it; its
  /// title first, in full, and after its status, when it started and closed, and how often it's been
  /// missed.
  Widget _fields(
    BuildContext context,
    Goal goal,
    GoalTree tree,
    Duration? spent,
  ) {
    final theme = Theme.of(context);
    final parent = tree[goal.parentId];
    final minutes = spent?.inMinutes ?? 0;
    final spentText = minutes > 0 ? ' · ${formatMinutes(minutes)} spent' : '';
    Widget html(String? text) => text == null
        ? const GoalFieldEmpty('None')
        : EventDescription(text, maxLines: null, selectable: true);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // In full, wrapping as it needs: the bar's is often cut short.
          GoalField(label: 'Title', child: Text(goalTitle(goal))),
          GoalField(label: 'Status', child: _status(goal)),
          if (goal.startedAt case final at?)
            GoalField(label: 'Started', child: Text(_when(context, at))),
          if (goal.closedAt case final at?)
            GoalField(
              label: goalStatuses[goal.status] ?? goal.status,
              child: Text(switch (goal.history.last.note) {
                null => _when(context, at),
                final note => '${_when(context, at)}\n$note',
              }),
            ),
          if (goal.misses case [..., final last] && final misses when goal.open)
            GoalField(
              label: 'Missed',
              child: Text(
                '${timesLabel(misses.length)}'
                '${last.deadline == null ? '' : ', last due ${deadlineLabel(context, last.deadline)}'}',
              ),
            ),
          GoalField(
            label: 'Deadline',
            child: goal.deadline == null && goal.deadlineRule == null
                ? const GoalFieldEmpty('None')
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (goal.deadline != null)
                        Text(deadlineLabel(context, goal.deadline))
                      else if (expectedDeadline(goal, tree, now: DateTime.now())
                          case final expected?)
                        Text('Expected ${deadlineLabel(context, expected)}'),
                      if ((parent, goal.deadlineOffsetMinutes) case (
                        final parent?,
                        final minutes?,
                      ))
                        Text(
                          followsLabel(goalTitle(parent), minutes),
                          style: theme.textTheme.bodySmall,
                        ),
                      if (ruleLabel(goal, tree) case final rule?)
                        Text(rule, style: theme.textTheme.bodySmall),
                    ],
                  ),
          ),
          if (goal.inactive && goal.activateWhen != null)
            GoalField(
              label: 'Starts',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final line in startsLines(context, goal, tree))
                    Text(line),
                  Text(switch (expectedStart(goal, tree, now: DateTime.now())) {
                    final at? => 'Expected to start ${_when(context, at)}',
                    null when isHeld(goal, tree) =>
                      'Held back for now: ready, with too many active',
                    null =>
                      'Not expected yet: what it waits for has no '
                          'deadline',
                  }, style: theme.textTheme.bodySmall),
                ],
              ),
            ),
          if (waitingOn(tree.byId.values, goal.id) case final next
              when next.isNotEmpty)
            GoalField(
              label: 'Starts after it',
              child: Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  for (final g in next)
                    ActionChip(
                      avatar: const Icon(Icons.hourglass_top, size: 16),
                      label: Text(goalTitle(g)),
                      onPressed: () => _open(g),
                    ),
                ],
              ),
            ),
          GoalField(
            label: 'Priority',
            child: Wrap(
              spacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                PriorityChip(
                  priority: tree.priorityOf(goal.id),
                  own: goal.priority != null,
                  large: true,
                ),
                if (goal.priority == null)
                  Text(
                    inheritedPriorityLabel(tree, goal.parentId),
                    style: theme.textTheme.bodySmall,
                  ),
              ],
            ),
          ),
          GoalField(
            label: 'Color',
            child: Row(
              children: [
                ColorDot(color: colorOfGoal(goal, tree: tree)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    goalColorSource(tree, goal),
                    style: theme.textTheme.bodySmall,
                  ),
                ),
              ],
            ),
          ),
          GoalField(
            label: 'Expected time',
            child: switch (goal.expectedMinutes) {
              final expected? => Text('${formatMinutes(expected)}$spentText'),
              null when minutes > 0 => Text('None set$spentText'),
              null => const GoalFieldEmpty('None'),
            },
          ),
          if (parent != null)
            GoalField(
              label: 'Required',
              child: Text(requiredLabel(goalTitle(parent), goal.required)),
            ),
          GoalField(
            label: 'People',
            child: goal.withWhom.isEmpty && goal.forWhom.isEmpty
                ? const GoalFieldEmpty('No one')
                : _people(context, goal),
          ),
          GoalField(label: 'Description', child: html(goal.description)),
          GoalField(
            label: 'Definition of done',
            child: html(goal.definitionOfDone),
          ),
          GoalField(
            label: 'Attribution hints',
            child: switch (goal.attributionHints) {
              final text? => SelectableText(text),
              null => const GoalFieldEmpty('None'),
            },
          ),
        ],
      ),
    );
  }

  /// Who [goal] is done with, and for, a chip each: a person's tapped to
  /// open their page, a circle's its page -- one the app doesn't know,
  /// or with no people to open, just named.
  Widget _people(BuildContext context, Goal goal) {
    final pages = PersonPages.of(context, widget.memory);
    final people = widget.memory.people;
    final names = goalPeopleNames(widget.memory);
    Widget chip(Named named) {
      final person = people?.withSelf
          .where((p) => p.id == named.id)
          .firstOrNull;
      final circle = people?.circle(named.id);
      final avatar = Icon(
        circle == null
            ? Icons.person_outline
            : circleIcon(circle.kind, outlined: true),
        size: 16,
      );
      final label = Text(namedLabel(named, names));
      final open = switch ((pages, person, circle)) {
        (final pages?, final p?, _) => () => pages.open(context, p),
        (final pages?, _, final c?) => () => pages.openCircle(context, c),
        _ => null,
      };
      return open == null
          ? Chip(avatar: avatar, label: label)
          : ActionChip(avatar: avatar, label: label, onPressed: open);
    }

    Widget line(String title, List<Named> named) => Wrap(
      spacing: 8,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [Text(title), for (final n in named) chip(n)],
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 4,
      children: [
        if (goal.withWhom.isNotEmpty) line('With', goal.withWhom),
        if (goal.forWhom.isNotEmpty) line('For', goal.forWhom),
      ],
    );
  }

  static String _when(BuildContext context, DateTime at) {
    final strings = MaterialLocalizations.of(context);
    final local = at.toLocal();
    return '${strings.formatMediumDate(local)}, '
        '${strings.formatTimeOfDay(TimeOfDay.fromDateTime(local))}';
  }
}
