import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/goal.dart';
import '../models/measure.dart';
import '../outbox/goal_outbox.dart';
import '../outbox/pending_goal_save.dart';
import '../outbox/save_error.dart';
import '../services/goals_repository.dart';
import '../services/mcp_client.dart';
import 'goal_history_screen.dart';
import '../widgets/app_menu.dart';
import '../widgets/color_picker.dart';
import '../widgets/goal_dialog.dart';
import '../widgets/health.dart';
import '../widgets/measure_dialog.dart';
import '../widgets/refreshing_bar.dart';
import '../widgets/status_message.dart';

/// The overall goal at the top -- its rating, and the time spent on goals
/// of the statuses shown in the last 24 hours and 7 days, each event once
/// -- then every other goal, as a tree: each one's color, name, status,
/// priority and
/// measure, the time spent on it (and its sub-goals) in the last 24 hours
/// and 7 days up to the last compaction, which is noted at the top, and
/// its last 8 days' ratings, with its sub-goals indented under it. A goal
/// with sub-goals starts collapsed, saying how many it has; tapping its
/// arrow or its flag expands it. Pressing and holding a goal starts
/// reordering: each goal can be dragged among its siblings, its sub-goals
/// going with it, until "Done". The filter at the top right picks which
/// statuses are shown: proposed, active and inactive goals to start with.
/// The menu beside it picks what each goal shows under its name: its
/// time spent, its measure, its time as a share of each window, or its
/// events' priority and fixed time ([GoalSummary]), kept on the device.
/// Only active goals take up a calendar label; the others keep their
/// history. Tapping a goal shows its measure and how it's doing by it, and
/// lets one edit it ([showMeasureDialog]); tapping its ratings shows its
/// history; its menu adds a sub-goal, or shows its measure, history or
/// details: all its properties, which can be changed, its status included.
/// "+" adds a top-level goal.
class GoalsScreen extends StatefulWidget {
  const GoalsScreen({
    super.key,
    required this.repository,
    required this.outbox,
    required this.serverLabel,
    this.onSignIn,
    this.onSignOut,
    this.version,
  });

  final GoalsRepository repository;

  /// Where saves go, to be sent in the background: the dialogs close at
  /// once, as notes' do.
  final GoalOutbox outbox;

  /// Which server this build talks to, for the About dialog.
  final String serverLabel;

  /// Runs the interactive sign-in; null when the backend needs none.
  final Future<void> Function()? onSignIn;
  final Future<void> Function()? onSignOut;

  /// The app's version, for the About dialog; null until it's known.
  final String? version;

  @override
  State<GoalsScreen> createState() => _GoalsScreenState();
}

class _GoalsScreenState extends State<GoalsScreen> {
  /// The goals as the server last listed them, with the saves it's
  /// answered since made to them.
  GoalList? _fromServer;

  /// The goals shown: [_fromServer], with the saves waiting in the
  /// outbox, or that failed, made to them; or [_held].
  GoalList? get _goals => _lastShown =
      _held ??
      switch (_fromServer) {
        final goals? => _withSaves(goals, widget.outbox.saves),
        null => null,
      };
  GoalList? _lastShown;

  /// The goals shown until they're fetched again, when saves were made
  /// elsewhere (by the background task) that these don't have.
  GoalList? _held;

  /// The saves in the outbox, by id, when it last changed.
  var _known = <String>{};

  /// The saves heard saved here, by id, as they leave the outbox.
  final _heard = <String>{};

  StreamSubscription<GoalSaveEvent>? _saveEvents;

  /// [_fromServer] are the ones kept from last time; the server hasn't
  /// answered since.
  bool _stale = false;
  Object? _error;
  bool _needsSignIn = false;
  bool _signingIn = false;

  /// The statuses shown.
  final _shown = {...defaultGoalStatuses};

  /// The goals whose sub-goals are shown; every other goal is collapsed.
  final _expanded = <String>{};

  /// Whether goals are being dragged into a new order.
  bool _reordering = false;

  /// What each goal shows under its name.
  GoalSummary _summary = GoalSummary.time;

  @override
  void initState() {
    super.initState();
    widget.outbox.addListener(_outboxChanged);
    _known = {for (final save in widget.outbox.saves) save.id};
    _saveEvents = widget.outbox.events.listen(_onSaveEvent);
    _showCached();
    _load();
    _loadSummary();
  }

  /// The [GoalSummary] picked last time, if one was. Best effort, like
  /// the response cache: without one, it's [GoalSummary.time].
  Future<void> _loadSummary() async {
    try {
      final name = await SharedPreferencesAsync().getString(_summaryKey);
      final summary = GoalSummary.values.asNameMap()[name];
      if (!mounted || summary == null) return;
      setState(() => _summary = summary);
    } catch (_) {
      // Nowhere to keep it: the default it is.
    }
  }

  void _setSummary(GoalSummary summary) {
    setState(() => _summary = summary);
    try {
      SharedPreferencesAsync()
          .setString(_summaryKey, summary.name)
          .catchError((_) {});
    } catch (_) {
      // Nowhere to keep it: it lasts until the app closes.
    }
  }

  /// Shows the goals kept from last time, unless the server answered
  /// first.
  Future<void> _showCached() async {
    final goals = await widget.repository.cachedGoals();
    if (!mounted || goals == null) return;
    if (_fromServer != null || _needsSignIn || _error != null) return;
    setState(() {
      _fromServer = goals;
      _stale = true;
    });
  }

  @override
  void dispose() {
    widget.outbox.removeListener(_outboxChanged);
    _saveEvents?.cancel();
    super.dispose();
  }

  void _outboxChanged() {
    if (!mounted) return;
    final ids = {for (final save in widget.outbox.saves) save.id};
    final gone = _known.difference(ids);
    _known = ids;
    // Gone without a word: saved elsewhere. Shown as they were until
    // the goals are fetched with them.
    if (gone.difference(_heard).isNotEmpty && _held == null) {
      _held = _lastShown;
      _load();
    }
    _heard.removeAll(gone);
    setState(() {});
  }

  void _onSaveEvent(GoalSaveEvent event) {
    if (!mounted) return;
    switch (event) {
      case GoalSaved(:final save, :final createdId):
        _heard.add(save.id);
        final goals = _fromServer;
        if (goals == null) return;
        // So it doesn't go missing until the goals are fetched again.
        setState(() {
          _fromServer = switch ((save.isNew, createdId)) {
            (false, _) => _withChanged(goals, save.goalId, save.changes),
            (true, final id?) => _inTree(goals, [
              ...goals.goals,
              Goal.fromJson({...save.goal.toJson(), 'id': id}),
            ]),
            (true, null) => goals,
          };
        });
      // Said once, not again each time it's tried again by itself.
      case GoalSaveFailed(:final save) when save.refused || save.attempts <= 1:
        final name = save.isNew
            ? save.goal.name
            : _goals?.goals.where((g) => g.id == save.goalId).firstOrNull?.name;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              "Couldn't save ${name ?? 'a goal'}. ${save.lastError}"
              "${save.refused ? '' : ' Trying again soon.'}",
            ),
            action: SnackBarAction(
              label: 'Retry',
              onPressed: () => widget.outbox.retry(save.goalId),
            ),
          ),
        );
      case GoalSaveFailed():
        break;
      case GoalSavesDone():
        _load();
    }
  }

  Future<void> _load() async {
    try {
      final goals = await widget.repository.goals();
      if (!mounted) return;
      _heard.addAll(widget.outbox.reconcile(goals).map((save) => save.id));
      setState(() {
        // While saves are being sent these may be behind them: they're
        // fetched again once the last is answered.
        if (_fromServer == null || _held != null || !widget.outbox.busy) {
          _fromServer = goals;
        }
        _held = null;
        _stale = false;
        _error = null;
        _needsSignIn = false;
      });
    } on SignInRequiredException {
      if (!mounted) return;
      setState(() {
        _fromServer = null;
        _held = null;
        _stale = false;
        _needsSignIn = true;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _held = null;
        _error = e;
      });
    }
  }

  /// Moves the goal at [oldIndex] of [shown] to [newIndex] (as
  /// ReorderableListView.onReorderItem gives it) among its siblings, shows the new
  /// order at once, and saves it.
  Future<void> _reorder(List<Goal> shown, int oldIndex, int newIndex) async {
    final goals = _fromServer;
    if (goals == null) return;
    final moved = shown[oldIndex];
    final order = [...shown]
      ..removeAt(oldIndex)
      ..insert(newIndex, moved);
    final ids = [
      for (final goal in order)
        if (goal.parentId == moved.parentId) goal.id!,
    ];
    final before = [
      for (final goal in shown)
        if (goal.parentId == moved.parentId) goal.id!,
    ];
    if (ids.join(',') == before.join(',')) return;
    setState(() => _fromServer = _withSiblingOrder(goals, ids));
    final messenger = ScaffoldMessenger.of(context);
    try {
      final saved = await widget.repository.reorderGoals(ids);
      if (mounted) setState(() => _fromServer = saved);
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text("Couldn't save the new order. ${describeSaveError(e)}"),
        ),
      );
      await _load();
    }
  }

  /// Every goal, for the dialogs' goal pickers.
  Future<List<Goal>> _allGoals() async =>
      (await widget.repository.goals()).goals;

  /// Saves [changes] to [goal] in the background. Returns the goals as
  /// they're shown now, with them.
  Future<GoalList> _update(Goal goal, Map<String, Object?> changes) async {
    widget.outbox.update(goal.id!, changes);
    return _goals!;
  }

  /// Creates a goal from [fields] in the background. Returns the goals as
  /// they're shown now, with it.
  Future<GoalList> _create(Map<String, Object?> fields) async {
    widget.outbox.create(fields);
    return _goals!;
  }

  /// Drops the saves that failed for the goal shown as [id].
  void _discard(String id) {
    _heard.addAll([
      for (final save in widget.outbox.saves)
        if (save.goalId == id) save.id,
    ]);
    widget.outbox.discard(id);
  }

  /// The save that failed for the goal shown as [id], if one did.
  PendingGoalSave? _failed(String? id) =>
      widget.outbox.saves.where((s) => s.goalId == id && s.failed).lastOrNull;

  /// Whether the goal shown as [id] is new, and the server hasn't made it
  /// yet: it can't be opened until then.
  bool _unmade(String? id) =>
      widget.outbox.saves.any((s) => s.goalId == id && s.isNew);

  /// Shows [goal]'s details to edit; one whose save failed opens with the
  /// changes that weren't saved, to save again.
  Future<void> _open(Goal goal) async {
    final id = goal.id!;
    switch (_failed(id)) {
      case PendingGoalSave(isNew: true, :final changes):
        await showNewGoalDialog(
          context,
          create: (fields) async {
            widget.outbox.update(id, fields, replace: true);
            return _goals!;
          },
          parentId: changes['parent_id'] as String?,
          fields: changes,
          goals: _allGoals,
        );
      case final failed:
        // As the server has it, with what wasn't saved as changes.
        final saved = failed == null
            ? goal
            : _fromServer?.goals.where((g) => g.id == id).firstOrNull ?? goal;
        await showGoalDialog(
          context,
          saved,
          changes: failed?.changes ?? const {},
          // What wasn't saved is among the changes, as they stand now.
          save: failed == null
              ? _update
              : (goal, changes) async {
                  widget.outbox.update(id, changes, replace: true);
                  return _goals!;
                },
          confirmSave: (changes) => switch (changes['status']) {
            final String status when status != saved.status => _confirmStatus(
              saved,
              status,
            ),
            _ => Future.value(true),
          },
          goals: _allGoals,
        );
    }
  }

  /// Shows [goal]'s measure, from which it can be edited, and its
  /// history or details opened.
  Future<void> _measure(Goal goal) => showMeasureDialog(
    context,
    goal,
    goalNames: {
      for (final goal in _goals?.goals ?? const <Goal>[])
        goal.id: goalName(goal),
    },
    save: _update,
    goals: _allGoals,
    onHistory: _history,
    onDetails: _open,
  );

  void _history(Goal goal) => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) =>
          GoalHistoryScreen(goal: goal, repository: widget.repository),
    ),
  );

  Future<void> _add({String? parentId}) async {
    // So the new sub-goal can be seen.
    if (parentId != null) setState(() => _expanded.add(parentId));
    await _addGoal(parentId: parentId);
  }

  Future<void> _addGoal({String? parentId}) => showNewGoalDialog(
    context,
    create: _create,
    parentId: parentId,
    goals: _allGoals,
  );

  /// Whether to move [goal] to [status]: freeing its label, or deleting it,
  /// is worth a second look.
  Future<bool> _confirmStatus(Goal goal, String status) async {
    final name = goalName(goal);
    // Freeing a label, or deleting, is worth a second look.
    final (String, String, String)? check = switch (status) {
      'deleted' => (
        'Delete $name?',
        "Its history is kept, and events that have it keep it, but no event "
            "can be given it again. It's hidden unless you show deleted goals.",
        'Delete',
      ),
      _ when goal.active => (
        'Move $name to ${goalStatuses[status]?.toLowerCase()}?',
        "It stops taking up one of the calendar's event labels, and its "
            "events lose its color until it's active again. Its history is "
            'kept.',
        goalStatuses[status] ?? status,
      ),
      _ => null,
    };
    if (check case (final question, final explanation, final confirm)) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(question),
          content: Text(explanation),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Keep it'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(confirm),
            ),
          ],
        ),
      );
      return confirmed == true;
    }
    return true;
  }

  Future<void> _signIn() async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _signingIn = true);
    try {
      await widget.onSignIn!();
      unawaited(widget.outbox.retryNow());
      await _load();
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Sign-in failed: $e')));
    } finally {
      if (mounted) setState(() => _signingIn = false);
    }
  }

  Future<void> _signOut() async {
    await widget.onSignOut!();
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final ready = _goals != null && !_needsSignIn;
    final reordering = _reordering && ready;
    return PopScope(
      canPop: !reordering,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) setState(() => _reordering = false);
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(reordering ? 'Reorder goals' : 'Goals'),
          actions: reordering
              ? [
                  TextButton(
                    onPressed: () => setState(() => _reordering = false),
                    child: const Text('Done'),
                  ),
                ]
              : [
                  if (ready)
                    _StatusFilter(
                      shown: _shown,
                      onChanged: (status, on) => setState(
                        () => on ? _shown.add(status) : _shown.remove(status),
                      ),
                    ),
                  if (ready)
                    _SummaryPicker(summary: _summary, onChanged: _setSummary),
                  AppMenu(
                    serverLabel: widget.serverLabel,
                    version: widget.version,
                    onSignOut: widget.onSignOut == null || _needsSignIn
                        ? null
                        : _signOut,
                  ),
                ],
        ),
        floatingActionButton: ready && !reordering
            ? FloatingActionButton(
                onPressed: _add,
                tooltip: 'Add goal',
                child: const Icon(Icons.add),
              )
            : null,
        body: RefreshingBar(
          refreshing:
              (_stale && _error == null && !_needsSignIn) || widget.outbox.busy,
          child: RefreshIndicator(onRefresh: _load, child: _buildBody(context)),
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    final goals = _goals;
    if (_needsSignIn) {
      return FillViewport(
        child: StatusMessage(
          icon: Icons.lock_outline,
          text: 'Sign in to see your goals.',
          action: widget.onSignIn == null
              ? null
              : FilledButton(
                  onPressed: _signingIn ? null : _signIn,
                  child: Text(_signingIn ? 'Waiting for browser…' : 'Sign in'),
                ),
        ),
      );
    }
    if (_error != null && (goals == null || goals.goals.isEmpty)) {
      return FillViewport(
        child: StatusMessage(
          icon: Icons.cloud_off,
          text: 'Could not load goals.\n$_error',
        ),
      );
    }
    if (goals == null) return const Center(child: CircularProgressIndicator());
    // The overall goal has a card of its own, above the tree.
    final overall = goals.overall;
    final all = [
      for (final goal in goals.goals)
        if (!goal.isOverall) goal,
    ];
    if (all.isEmpty) {
      return const FillViewport(
        child: StatusMessage(
          icon: Icons.flag_outlined,
          text: 'No goals yet.\nTap + to add one.',
        ),
      );
    }
    final byId = {for (final goal in all) goal.id: goal};
    final names = {for (final goal in goals.goals) goal.id: goalName(goal)};
    final withStatus = [
      for (final goal in all)
        if (_shown.contains(goal.status)) goal,
    ];
    // How many sub-goals each goal has, of those with the statuses shown.
    final subGoals = <String?, int>{};
    for (final goal in withStatus) {
      subGoals.update(goal.parentId, (n) => n + 1, ifAbsent: () => 1);
    }
    // A goal is hidden under any collapsed ancestor that's shown. One whose
    // parent's status is filtered out still shows, where it always has.
    bool underCollapsed(Goal goal) {
      for (
        var parent = byId[goal.parentId];
        parent != null;
        parent = byId[parent.parentId]
      ) {
        if (_shown.contains(parent.status) && !_expanded.contains(parent.id)) {
          return true;
        }
      }
      return false;
    }

    final shown = [
      for (final goal in withStatus)
        if (!underCollapsed(goal)) goal,
    ];
    if (_reordering) {
      return ReorderableListView.builder(
        buildDefaultDragHandles: false,
        padding: const EdgeInsets.only(bottom: 24),
        header: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: Text(
            'Drag a goal by its handle to move it among the goals it sits '
            'with; its sub-goals go with it.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
        itemCount: shown.length,
        onReorderItem: (from, to) => _reorder(shown, from, to),
        itemBuilder: (context, i) => Column(
          key: ValueKey(shown[i].id),
          mainAxisSize: MainAxisSize.min,
          children: [
            if (i > 0) const Divider(height: 1),
            _GoalTile(
              goal: shown[i],
              goalNames: names,
              subGoals: subGoals[shown[i].id] ?? 0,
              expanded: _expanded.contains(shown[i].id),
              dragIndex: i,
              onToggle: () => setState(() {
                if (!_expanded.remove(shown[i].id)) _expanded.add(shown[i].id!);
              }),
              onTap: null,
              onDetails: () {},
              onAddSubGoal: () {},
              onHistory: () {},
            ),
          ],
        ),
      );
    }
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.only(bottom: 88), // Clear of the "+".
      children: [
        // The last goals loaded, or kept from last time, are still shown.
        if (_error != null)
          StatusMessage(
            icon: Icons.cloud_off,
            text: 'Could not load goals. These may be out of date.\n$_error',
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: Wrap(
            spacing: 16,
            runSpacing: 4,
            children: [
              Tooltip(
                message:
                    'Time spent is counted up to when notes were last '
                    'compacted into the calendar.',
                child: Text(switch (goals.asOf) {
                  final asOf? =>
                    'Last compacted ${formatTimestamp(context, asOf)}',
                  null => 'Notes not compacted yet',
                }, style: Theme.of(context).textTheme.bodySmall),
              ),
              Tooltip(
                message:
                    'Each active goal takes one of the calendar\'s event '
                    'labels, as do its own default colors.',
                child: Text(
                  '${goals.labelSlotsUsed} of ${goals.labelSlotsTotal} labels '
                  'in use',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ],
          ),
        ),
        _OverallCard(
          goal: overall,
          time: overall?.timeFor(_shown) ?? goals.timeFor(_shown),
          summary: _summary,
          goalNames: names,
          onTap: overall == null ? null : () => _measure(overall),
          onHistory: overall == null ? null : () => _history(overall),
        ),
        if (shown.isEmpty)
          const StatusMessage(
            icon: Icons.flag_outlined,
            text: 'No goals with these statuses.',
          ),
        for (final (i, goal) in shown.indexed) ...[
          if (i > 0) const Divider(height: 1),
          _GoalTile(
            goal: goal,
            goalNames: names,
            shownStatuses: _shown,
            summary: _summary,
            subGoals: subGoals[goal.id] ?? 0,
            expanded: _expanded.contains(goal.id),
            onToggle: () => setState(() {
              if (!_expanded.remove(goal.id)) _expanded.add(goal.id!);
            }),
            // One the server hasn't made yet has nothing to open, and
            // nothing is reordered under changes still being saved, or
            // around a goal that couldn't be made.
            saving: _unmade(goal.id) && _failed(goal.id) == null,
            failed: switch (_failed(goal.id)) {
              null => null,
              final save when save.refused => save.lastError,
              final save => '${save.lastError}. Trying again soon',
            },
            onTap: _failed(goal.id) == null
                ? () => _measure(goal)
                : () => _open(goal),
            onDetails: () => _open(goal),
            onRetry: () => widget.outbox.retry(goal.id!),
            onDiscard: () => _discard(goal.id!),
            onLongPress:
                widget.outbox.busy || widget.outbox.saves.any((s) => s.isNew)
                ? null
                : () => setState(() => _reordering = true),
            onAddSubGoal: () => _add(parentId: goal.id),
            onHistory: () => _history(goal),
          ),
        ],
      ],
    );
  }
}

/// The app bar's filter: a drop-down of every status, each with a check
/// box, which stays open while they're ticked. A dot on its icon says
/// it's showing something other than [defaultGoalStatuses].
class _StatusFilter extends StatelessWidget {
  const _StatusFilter({required this.shown, required this.onChanged});

  final Set<String> shown;
  final void Function(String status, bool on) onChanged;

  @override
  Widget build(BuildContext context) {
    final changed =
        shown.length != defaultGoalStatuses.length ||
        !shown.containsAll(defaultGoalStatuses);
    return MenuAnchor(
      menuChildren: [
        for (final MapEntry(key: status, value: label) in goalStatuses.entries)
          CheckboxMenuButton(
            value: shown.contains(status),
            closeOnActivate: false,
            onChanged: (on) => onChanged(status, on ?? false),
            child: Text(label),
          ),
      ],
      builder: (context, controller, _) => IconButton(
        tooltip: 'Show goals that are…',
        icon: Badge(
          isLabelVisible: changed,
          child: const Icon(Icons.filter_list),
        ),
        onPressed: () =>
            controller.isOpen ? controller.close() : controller.open(),
      ),
    );
  }
}

/// What each goal on the Goals page shows under its name.
enum GoalSummary {
  /// The time spent on it and its sub-goals in the last 24 hours and 7
  /// days: "9h in 24h · 10h in 7d".
  time('Time spent'),

  /// What its measure rates: "10h per 7 days".
  measure('Measure'),

  /// Its time as a share of each window: "37.5% of 24h · 6% of 7d".
  percent('Time as a percentage'),

  /// What it gives its events: "Priority 2 · Fixed time".
  eventProperties('Event properties');

  const GoalSummary(this.label);

  /// How [_SummaryPicker] offers it.
  final String label;
}

/// Where the [GoalSummary] picked is kept.
const _summaryKey = 'goal_summary';

/// The app bar's pick of what each goal shows under its name: a drop-down
/// of every [GoalSummary], the one shown ticked.
class _SummaryPicker extends StatelessWidget {
  const _SummaryPicker({required this.summary, required this.onChanged});

  final GoalSummary summary;
  final ValueChanged<GoalSummary> onChanged;

  @override
  Widget build(BuildContext context) {
    return MenuAnchor(
      menuChildren: [
        for (final option in GoalSummary.values)
          RadioMenuButton<GoalSummary>(
            value: option,
            groupValue: summary,
            onChanged: (picked) => onChanged(picked ?? option),
            child: Text(option.label),
          ),
      ],
      builder: (context, controller, _) => IconButton(
        tooltip: 'Show under each goal…',
        icon: const Icon(Icons.short_text),
        onPressed: () =>
            controller.isOpen ? controller.close() : controller.open(),
      ),
    );
  }
}

/// An active goal's flag: solid in its own color if it has one; otherwise
/// an outline in the color it inherits, from its parent or its priority.
class GoalFlag extends StatelessWidget {
  const GoalFlag({super.key, required this.goal});

  final Goal goal;

  @override
  Widget build(BuildContext context) {
    if (parseColor(goal.backgroundColor) case final own?) {
      return Icon(Icons.flag, color: own);
    }
    return Icon(
      Icons.outlined_flag,
      color: parseColor(goal.effectiveColor) ?? Theme.of(context).hintColor,
    );
  }
}

/// Each status's icon.
const _statusIcons = {
  'proposed': Icons.lightbulb_outline,
  'active': Icons.flag,
  'inactive': Icons.pause_circle_outline,
  'completed': Icons.check_circle_outline,
  'archived': Icons.inventory_2_outlined,
  'deleted': Icons.delete_outline,
};

/// The width of the expand arrow before a goal's flag.
const _arrowWidth = 32.0;

class _GoalTile extends StatelessWidget {
  const _GoalTile({
    required this.goal,
    this.goalNames = const {},
    this.shownStatuses,
    this.summary = GoalSummary.time,
    required this.subGoals,
    required this.expanded,
    required this.onToggle,
    required this.onTap,
    required this.onDetails,
    this.onLongPress,
    this.dragIndex,
    required this.onAddSubGoal,
    required this.onHistory,
    this.saving = false,
    this.failed,
    this.onRetry,
    this.onDiscard,
  });

  final Goal goal;

  /// Whether it's still being added: it shows that it's saving instead
  /// of its menu, and can't be tapped.
  final bool saving;

  /// Why its last save failed, if it did: it shows an error instead of
  /// its menu, which offers [onRetry], [onDetails] (to edit what wasn't
  /// saved) and [onDiscard].
  final String? failed;
  final VoidCallback? onRetry;
  final VoidCallback? onDiscard;

  /// Every goal's name, by id, to say whose events it's measured by.
  final Map<String?, String> goalNames;

  /// The statuses the Goals page shows: its time is through goals with
  /// these. Null for all its time.
  final Set<String>? shownStatuses;

  /// What it shows under its name, above its other details.
  final GoalSummary summary;

  /// How many sub-goals it has (of those shown); none, and it has no arrow.
  final int subGoals;

  /// Whether its sub-goals are shown.
  final bool expanded;

  /// Shows or hides its sub-goals: its arrow and its flag do this.
  final VoidCallback onToggle;

  /// Shows its measure: tapping it, or "Measure" in its menu.
  final VoidCallback? onTap;

  /// Shows its details: "Details" in its menu.
  final VoidCallback onDetails;
  final VoidCallback? onLongPress;

  /// While reordering, its index in the list, for its drag handle; null
  /// otherwise, when it has its menu instead.
  final int? dragIndex;
  final VoidCallback onAddSubGoal;

  /// Shows its history: tapping its ratings, or "History" in its menu.
  final VoidCallback onHistory;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final faded = goal.active ? null : TextStyle(color: theme.hintColor);
    final details = [
      if (!goal.active) goalStatuses[goal.status] ?? goal.status,
      if (goal.staleDays case final stale? when stale > 0)
        '$stale day${stale == 1 ? '' : 's'} unrated',
      if (subGoals > 0 && !expanded)
        '$subGoals sub-goal${subGoals == 1 ? '' : 's'}',
    ].nonNulls.join(' · ');
    final rated =
        goal.active &&
        (goal.staleDays != null ||
            goal.health != null ||
            goal.healthTrend.isNotEmpty);
    // Through the sub-goals shown, if the server says; else all of it.
    final filtered = switch (shownStatuses) {
      final shown? => goal.timeFor(shown),
      null => null,
    };
    final shown = switch ((summary, goal.measure)) {
      (GoalSummary.measure, final measure?) => describeMeasure(
        measure,
        goalNames: goalNames,
      ),
      (GoalSummary.measure, null) => null,
      (GoalSummary.eventProperties, _) => describeEventProperties(goal),
      _ => switch (filtered ?? (goal.minutes24h, goal.minutes7d)) {
        (final int day, final int week) => describeTime(
          day,
          week,
          skipZero: true,
          asPercent: summary == GoalSummary.percent,
        ),
        _ => null,
      },
    };
    final flag = Tooltip(
      message: goalStatuses[goal.status] ?? goal.status,
      child: goal.active
          ? GoalFlag(goal: goal)
          : Icon(
              _statusIcons[goal.status] ?? Icons.outlined_flag,
              color: theme.hintColor,
            ),
    );
    return ListTile(
      contentPadding: EdgeInsetsDirectional.only(
        start: 4.0 + 24.0 * goal.depth,
        end: 4,
      ),
      leading: subGoals > 0
          // The arrow and the flag together show or hide its sub-goals.
          ? Tooltip(
              message: '${expanded ? 'Collapse' : 'Expand'} ${goalName(goal)}',
              child: InkWell(
                borderRadius: BorderRadius.circular(20),
                onTap: onToggle,
                child: SizedBox(
                  height: 40,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: _arrowWidth,
                        child: Icon(
                          expanded ? Icons.expand_more : Icons.chevron_right,
                        ),
                      ),
                      flag,
                      const SizedBox(width: 4),
                    ],
                  ),
                ),
              ),
            )
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Lines up with the arrows' flags.
                const SizedBox(width: _arrowWidth),
                flag,
                const SizedBox(width: 4),
              ],
            ),
      title: Text(goalName(goal), style: faded),
      subtitle: details.isEmpty && shown == null
          ? null
          : Text(
              [?shown, if (details.isNotEmpty) details].join('\n'),
              style: faded,
            ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (rated)
            Tooltip(
              message: 'History of ${goalName(goal)}',
              child: InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: dragIndex == null ? onHistory : null,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 8,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (goal.healthTrend.isNotEmpty) ...[
                        TrendSparkline(trend: goal.healthTrend),
                        const SizedBox(width: 8),
                      ],
                      HealthDot(rating: goal.health),
                    ],
                  ),
                ),
              ),
            ),
          if (failed case final why?)
            PopupMenuButton<String>(
              tooltip: 'Not saved: $why',
              icon: Icon(Icons.error_outline, color: theme.colorScheme.error),
              onSelected: (choice) => switch (choice) {
                'retry' => onRetry?.call(),
                'discard' => onDiscard?.call(),
                _ => onDetails(),
              },
              itemBuilder: (context) => [
                PopupMenuItem(
                  enabled: false,
                  child: Text("Couldn't save: $why"),
                ),
                const PopupMenuItem(value: 'retry', child: Text('Try again')),
                const PopupMenuItem(value: 'edit', child: Text('Edit')),
                const PopupMenuItem(value: 'discard', child: Text('Discard')),
              ],
            )
          else if (saving)
            const Tooltip(
              message: 'Saving…',
              child: Padding(
                padding: EdgeInsets.all(14),
                child: SizedBox.square(
                  dimension: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            )
          else if (dragIndex case final index?)
            ReorderableDragStartListener(
              index: index,
              child: Tooltip(
                message: 'Drag to move ${goalName(goal)}',
                child: const Padding(
                  padding: EdgeInsets.all(12),
                  child: Icon(Icons.drag_handle),
                ),
              ),
            )
          else
            PopupMenuButton<String>(
              tooltip: 'More for ${goalName(goal)}',
              onSelected: (choice) => switch (choice) {
                'sub' => onAddSubGoal(),
                'history' => onHistory(),
                'measure' => onTap?.call(),
                _ => onDetails(),
              },
              itemBuilder: (context) => const [
                PopupMenuItem(value: 'sub', child: Text('Add sub-goal')),
                PopupMenuItem(value: 'measure', child: Text('Measure')),
                PopupMenuItem(value: 'history', child: Text('History')),
                PopupMenuItem(value: 'details', child: Text('Details')),
              ],
            ),
        ],
      ),
      onTap: saving ? null : onTap,
      onLongPress: saving ? null : onLongPress,
    );
  }
}

/// [goals] with [saves] made to them, oldest first: each new goal added,
/// and each goal's changes made.
GoalList _withSaves(GoalList goals, List<PendingGoalSave> saves) {
  if (saves.isEmpty) return goals;
  var shown = goals;
  for (final save in saves) {
    shown = save.isNew
        ? _inTree(shown, [...shown.goals, save.goal])
        : _withChanged(shown, save.goalId, save.changes);
  }
  return shown;
}

/// [goals] with [changes], keyed as `update_goal` takes them, made to the
/// goal with [id]: moved, if it's given another parent, and renamed in
/// its sub-goals' paths.
GoalList _withChanged(
  GoalList goals,
  String? id,
  Map<String, Object?> changes,
) => _inTree(goals, [
  for (final goal in goals.goals)
    goal.id == id ? Goal.fromJson({...goal.toJson(), ...changes}) : goal,
]);

/// [goals] in place of [list]'s, parents first, each goal's sub-goals
/// after it in the order given, and each path made again from its
/// ancestors' names.
GoalList _inTree(GoalList list, List<Goal> goals) {
  final ids = {for (final goal in goals) goal.id};
  final children = <String?, List<Goal>>{};
  for (final goal in goals) {
    final parent = ids.contains(goal.parentId) ? goal.parentId : null;
    children.putIfAbsent(parent, () => []).add(goal);
  }
  final ordered = <Goal>[];
  void visit(Goal goal, String? parentPath) {
    final path = switch ((parentPath, goal.parentId)) {
      (final parent?, _) => '$parent › ${goalName(goal)}',
      (null, null) => goalName(goal),
      // Under a goal that isn't listed: only its own name can be redone.
      _ => switch (goal.path?.lastIndexOf(' › ')) {
        final end? when end >= 0 =>
          '${goal.path!.substring(0, end)} › ${goalName(goal)}',
        _ => goalName(goal),
      },
    };
    ordered.add(
      path == goal.path
          ? goal
          : Goal.fromJson({...goal.toJson(), 'path': path}),
    );
    for (final child in children[goal.id] ?? const <Goal>[]) {
      visit(child, path);
    }
  }

  children[null]?.forEach((goal) => visit(goal, null));
  return GoalList(
    goals: ordered,
    labelSlotsUsed: list.labelSlotsUsed,
    labelSlotsTotal: list.labelSlotsTotal,
    asOf: list.asOf,
    minutesByStatuses: list.minutesByStatuses,
  );
}

/// [goals] with the siblings [ids] (sharing a parent) put in that order
/// among the places they hold, and the list rebuilt parents first, each
/// goal's sub-goals after it, as the server lists them.
GoalList _withSiblingOrder(GoalList goals, List<String> ids) {
  final byId = {for (final goal in goals.goals) goal.id: goal};
  final children = <String?, List<Goal>>{};
  for (final goal in goals.goals) {
    final parent = byId.containsKey(goal.parentId) ? goal.parentId : null;
    children.putIfAbsent(parent, () => []).add(goal);
  }
  final siblings = children[byId[ids.first]?.parentId] ?? [];
  final places = [
    for (final (i, goal) in siblings.indexed)
      if (ids.contains(goal.id)) i,
  ];
  for (var i = 0; i < places.length && i < ids.length; i++) {
    siblings[places[i]] = byId[ids[i]]!;
  }
  final ordered = <Goal>[];
  void visit(Goal goal) {
    ordered.add(goal);
    children[goal.id]?.forEach(visit);
  }

  children[null]?.forEach(visit);
  return GoalList(
    goals: ordered,
    labelSlotsUsed: goals.labelSlotsUsed,
    labelSlotsTotal: goals.labelSlotsTotal,
    asOf: goals.asOf,
    minutesByStatuses: goals.minutesByStatuses,
  );
}

/// The overall goal, above the rest: its rating and last 8 days, and the
/// time spent on the goals of the statuses shown. Tapping it shows its
/// measure, and from there its details; tapping its ratings, its history. Without [goal] (from an
/// older server), just the time.
class _OverallCard extends StatelessWidget {
  const _OverallCard({
    required this.goal,
    required this.time,
    this.summary = GoalSummary.time,
    required this.goalNames,
    required this.onTap,
    required this.onHistory,
  });

  final Goal? goal;

  /// Minutes on the goals shown in the last 24 hours and 7 days.
  final (int, int)? time;

  /// What it shows under its name, as every goal does. Unlike theirs, its
  /// time is shown even when there's none, and its measure, when it has
  /// none, is the average of the top-level goals'.
  final GoalSummary summary;
  final Map<String?, String> goalNames;
  final VoidCallback? onTap;
  final VoidCallback? onHistory;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final goal = this.goal;
    if (goal == null && time == null) return const SizedBox.shrink();
    final measure = switch (goal?.measure) {
      final measure? => describeMeasure(measure, goalNames: goalNames),
      _ when goal != null => "Average of the top-level goals'",
      _ => null,
    };
    final shown = switch ((summary, time)) {
      (GoalSummary.measure, _) => measure,
      (GoalSummary.eventProperties, _) =>
        goal == null ? null : describeEventProperties(goal),
      (_, (final day, final week)) =>
        '${describeTime(day, week, asPercent: summary == GoalSummary.percent)!} '
            'on the goals shown',
      _ => null,
    };
    final details = [
      shown,
      if (goal?.staleDays case final stale? when stale > 0)
        '$stale day${stale == 1 ? '' : 's'} unrated',
    ].nonNulls.where((line) => line.isNotEmpty).join('\n');
    return Card(
      margin: const EdgeInsets.fromLTRB(12, 4, 12, 8),
      color: theme.colorScheme.surfaceContainerHigh,
      child: ListTile(
        leading: Icon(Icons.all_inclusive, color: theme.colorScheme.primary),
        title: Text(goal == null ? 'All goals' : goalName(goal)),
        subtitle: details.isEmpty ? null : Text(details),
        onTap: onTap,
        trailing: goal == null
            ? null
            : Tooltip(
                message: 'History of ${goalName(goal)}',
                child: InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: onHistory,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 8,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (goal.healthTrend.isNotEmpty) ...[
                          TrendSparkline(trend: goal.healthTrend),
                          const SizedBox(width: 8),
                        ],
                        HealthDot(rating: goal.health),
                      ],
                    ),
                  ),
                ),
              ),
      ),
    );
  }
}

/// [time], in local time, as "Fri, Oct 2, 9:05 PM".
String formatTimestamp(BuildContext context, DateTime time) {
  final strings = MaterialLocalizations.of(context);
  final local = time.toLocal();
  return '${strings.formatShortDate(local)}, '
      '${strings.formatTimeOfDay(TimeOfDay.fromDateTime(local))}';
}

/// The priority and fixed time [goal] gives its events: "Priority 2 ·
/// Fixed time". Null if it gives neither.
String? describeEventProperties(Goal goal) {
  final parts = [
    if (goal.priority case final priority?) 'Priority $priority',
    switch (goal.fixedTime) {
      true => 'Fixed time',
      false => 'Flexible time',
      null => null,
    },
  ].nonNulls;
  return parts.isEmpty ? null : parts.join(' · ');
}

/// [day] and [week] minutes as "9h in 24h · 10h in 7d", or with
/// [asPercent], as shares of each window: "37.5% of 24h · 6% of 7d". With
/// [skipZero], a window with no time is left out, and null is given if
/// both are.
String? describeTime(
  int day,
  int week, {
  bool skipZero = false,
  bool asPercent = false,
}) {
  String? part(int minutes, String window, int windowMinutes) {
    if (skipZero && minutes == 0) return null;
    return asPercent
        ? '${_percent(minutes, windowMinutes)} of $window'
        : '${formatMinutes(minutes)} in $window';
  }

  final parts = [
    part(day, '24h', 24 * 60),
    part(week, '7d', 7 * 24 * 60),
  ].nonNulls;
  return parts.isEmpty ? null : parts.join(' · ');
}

/// [minutes] as a share of [of] to a tenth: "37.5%", "6%", "<0.1%".
String _percent(int minutes, int of) {
  final percent = (minutes * 100 / of).toStringAsFixed(1);
  if (minutes > 0 && percent == '0.0') return '<0.1%';
  return '${percent.endsWith('.0') ? percent.substring(0, percent.length - 2) : percent}%';
}
