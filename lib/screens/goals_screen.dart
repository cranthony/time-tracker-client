import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/goal.dart';
import '../models/measure.dart';
import '../outbox/goal_outbox.dart';
import '../outbox/pending_goal_save.dart';
import '../outbox/save_error.dart';
import '../services/goals_repository.dart';
import '../services/mcp_client.dart';
import '../services/traits_repository.dart';
import 'goal_history_screen.dart';
import 'goal_traits_screen.dart';
import 'traits_screen.dart';
import '../widgets/app_menu.dart';
import '../widgets/color_picker.dart';
import '../widgets/goal_summary_dialog.dart';
import '../widgets/goals_time_summary.dart';
import '../widgets/priority_chip.dart';
import '../widgets/goal_dialog.dart';
import '../widgets/health.dart';
import '../widgets/measure_dialog.dart';
import '../widgets/refreshing_bar.dart';
import '../widgets/status_message.dart';

/// The overall goal at the top -- its rating, and the time spent on goals
/// of the statuses shown in the last 24 hours and 7 days, each event once
/// -- then every other goal, as a tree: each one's color, name, status,
/// priority (as a chip, like the Events page's) and measure, the time spent on it (and its sub-goals) in the last 24 hours
/// and 7 days up to the last compaction, which is noted at the top, and
/// its last 8 days' ratings, with its sub-goals indented under it. A goal
/// with sub-goals starts collapsed, saying how many it has; tapping its
/// arrow or its flag expands it. Pressing and holding a goal starts
/// reordering: each goal can be dragged among its siblings, its sub-goals
/// going with it, until "Done". The filter at the top right picks which
/// statuses are shown: proposed, active and inactive goals to start with.
/// The menu beside it picks what each goal shows under its name: its
/// time spent or its measure ([GoalSummary]), kept on the device. Its
/// time spent is in durations or as a share of each window, as the time
/// summary's toggle says.
/// Only active goals take up a calendar label; the others keep their
/// history. Tapping a goal shows its priority, its measure and how it's
/// doing by it, and its color, from which each can be edited
/// ([showGoalSummaryDialog]); tapping its ratings shows its
/// history; its menu adds a sub-goal, or shows its measure, history or
/// details: all its properties, which can be changed, its status included
/// -- and, for a goal rated by traits, its traits page
/// ([GoalTraitsScreen]). "+" adds a top-level goal. With a [TraitsScope],
/// the app bar opens the traits ([TraitsScreen]).
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
  /// The goals as the server last listed them.
  GoalList? _fromServer;

  /// The goals shown: [_fromServer], with the saves made since it was
  /// fetched, here or by the background task, then those waiting in the
  /// outbox, or that failed, made to them.
  GoalList? get _goals => switch (_fromServer) {
    final goals? => _withSaves(
      _withSaved(goals, widget.outbox.justSaved),
      widget.outbox.saves,
    ),
    null => null,
  };

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

  /// Whether the time summary under the heading is folded away.
  bool _timeSummaryCollapsed = false;

  /// Whether time is shown as durations, rather than as percentages:
  /// in the time summary, and under each goal.
  bool _durations = true;

  @override
  void initState() {
    super.initState();
    widget.outbox.addListener(_outboxChanged);
    _saveEvents = widget.outbox.events.listen(_onSaveEvent);
    _showCached();
    _load();
    _loadSummary();
    _loadTimeSummaryCollapsed();
  }

  /// The [GoalSummary] picked last time, if one was, and whether time
  /// was in durations. Best effort, like the response cache: without
  /// them, it's [GoalSummary.time], in durations. Time picked as a
  /// percentage, when that was a [GoalSummary] of its own, is still.
  Future<void> _loadSummary() async {
    try {
      final preferences = SharedPreferencesAsync();
      final name = await preferences.getString(_summaryKey);
      final durations = await preferences.getBool(_durationsKey);
      if (!mounted) return;
      setState(() {
        _summary = GoalSummary.values.asNameMap()[name] ?? _summary;
        _durations = durations ?? name != _percentSummary;
      });
    } catch (_) {
      // Nowhere to keep it: the default it is.
    }
  }

  void _setDurations(bool durations) {
    setState(() => _durations = durations);
    try {
      SharedPreferencesAsync()
          .setBool(_durationsKey, durations)
          .catchError((_) {});
    } catch (_) {
      // Nowhere to keep it: it lasts until the app closes.
    }
  }

  /// Whether the time summary was folded away last time. Best effort,
  /// as [_loadSummary].
  Future<void> _loadTimeSummaryCollapsed() async {
    try {
      final collapsed = await SharedPreferencesAsync().getBool(
        _timeSummaryCollapsedKey,
      );
      if (!mounted || collapsed == null) return;
      setState(() => _timeSummaryCollapsed = collapsed);
    } catch (_) {
      // Nowhere to keep it: it's open.
    }
  }

  void _setTimeSummaryCollapsed(bool collapsed) {
    setState(() => _timeSummaryCollapsed = collapsed);
    try {
      SharedPreferencesAsync()
          .setBool(_timeSummaryCollapsedKey, collapsed)
          .catchError((_) {});
    } catch (_) {
      // Nowhere to keep it: it lasts until the app closes.
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
    // Once, after the last of a round is answered, rather than after each.
    if (widget.outbox.wantsFetch) _load();
    setState(() {});
  }

  void _onSaveEvent(GoalSaveEvent event) {
    if (!mounted) return;
    switch (event) {
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
    }
  }

  Future<void> _load() async {
    final fetched = widget.outbox.fetching();
    try {
      final goals = await widget.repository.goals();
      if (!mounted) return;
      widget.outbox.reconcile(goals);
      setState(() {
        // Saves made while these were fetched are still made to them.
        _fromServer = goals;
        _stale = false;
        _error = null;
        _needsSignIn = false;
      });
      fetched();
    } on SignInRequiredException {
      if (!mounted) return;
      setState(() {
        _fromServer = null;
        _stale = false;
        _needsSignIn = true;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        // Signed in: without that it's SignInRequiredException.
        _needsSignIn = false;
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
  void _discard(String id) => widget.outbox.discard(id);

  /// The save that failed for the goal shown as [id], if one did.
  PendingGoalSave? _failed(String? id) =>
      widget.outbox.saves.where((s) => s.goalId == id && s.failed).lastOrNull;

  /// Whether the goal shown as [id] is new, and the server hasn't made it
  /// yet: it can't be opened until then.
  bool _unmade(String? id) =>
      widget.outbox.saves.any((s) => s.goalId == id && s.isNew) ||
      // Made by the background task, which didn't say its id.
      widget.outbox.justSaved.any(
        (s) => s.item.goalId == id && s.item.isNew && s.result == null,
      );

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

  /// Shows [goal]'s priority, measure, how it's doing and color, from
  /// which each can be edited, and its history or details opened.
  Future<void> _show(Goal goal) => showGoalSummaryDialog(
    context,
    goal,
    goals: _goals?.goals ?? const [],
    goalNames: {
      for (final goal in _goals?.goals ?? const <Goal>[])
        goal.id: goalName(goal),
    },
    save: _update,
    onEditMeasure: (goal) =>
        showEditMeasureDialog(context, goal, save: _update, goals: _allGoals),
    onHistory: _history,
    onDetails: _open,
  );

  void _history(Goal goal) => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) =>
          GoalHistoryScreen(goal: goal, repository: widget.repository),
    ),
  );

  Map<String?, String> get _goalNames => {
    for (final goal in _goals?.goals ?? const <Goal>[]) goal.id: goalName(goal),
  };

  /// [goal]'s traits page, for a goal rated by traits; null without a
  /// [TraitsScope], or for any other goal.
  VoidCallback? _traitsOf(Goal goal) {
    final traits = TraitsScope.of(context);
    if (traits == null ||
        goal.measure?['kind'] != 'traits' ||
        goal.id == null) {
      return null;
    }
    return () => Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => GoalTraitsScreen(
          goal: goal,
          repository: traits,
          goalNames: _goalNames,
        ),
      ),
    );
  }

  void _openTraits(TraitsRepository traits) => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => TraitsScreen(repository: traits, goalNames: _goalNames),
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
                  if (TraitsScope.of(context) case final traits? when ready)
                    IconButton(
                      tooltip: 'Traits',
                      icon: const Icon(Icons.psychology_outlined),
                      onPressed: () => _openTraits(traits),
                    ),
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
    // Each goal's ancestors, from the top, whose bands it carries.
    List<Goal> ancestorsOf(Goal goal) {
      final chain = <Goal>[];
      for (
        var parent = byId[goal.parentId];
        parent != null && !chain.contains(parent);
        parent = byId[parent.parentId]
      ) {
        chain.insert(0, parent);
      }
      return chain;
    }

    final ancestors = [for (final goal in shown) ancestorsOf(goal)];
    // The divider above the [i]th goal leaves the bands it shares with the
    // goal above it unbroken.
    int sharedAbove(int i) {
      if (i == 0) return 0;
      final above = [...ancestors[i - 1], shown[i - 1]];
      var shared = 0;
      while (shared < ancestors[i].length &&
          shared < above.length &&
          ancestors[i][shared] == above[shared]) {
        shared++;
      }
      return shared;
    }

    Widget divider(int i) =>
        Divider(height: 1, indent: sharedAbove(i) * goalBandWidth);

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
            if (i > 0) divider(i),
            _GoalTile(
              goal: shown[i],
              ancestors: ancestors[i],
              joined: sharedAbove(i),
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
    final list = ListView(
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
          durations: _durations,
          goalNames: names,
          onTap: overall == null ? null : () => _show(overall),
          onHistory: overall == null ? null : () => _history(overall),
        ),
        if (shown.isEmpty)
          const StatusMessage(
            icon: Icons.flag_outlined,
            text: 'No goals with these statuses.',
          ),
        for (final (i, goal) in shown.indexed) ...[
          if (i > 0) divider(i),
          _GoalTile(
            goal: goal,
            ancestors: ancestors[i],
            joined: sharedAbove(i),
            goalNames: names,
            shownStatuses: _shown,
            summary: _summary,
            durations: _durations,
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
                ? () => _show(goal)
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
            onTraits: _traitsOf(goal),
          ),
        ],
      ],
    );
    final onGoals = overall?.timeFor(_shown) ?? goals.timeFor(_shown);
    if (onGoals == null) return list;
    // Under the heading, still as the goals scroll.
    return Column(
      children: [
        GoalsTimeSummary(
          visible: shown,
          byId: byId,
          statuses: _shown,
          onGoals: onGoals,
          byPriority: goals.minutesByPriority,
          collapsed: _timeSummaryCollapsed,
          onCollapsed: _setTimeSummaryCollapsed,
          durations: _durations,
          onDurations: _setDurations,
        ),
        Expanded(child: list),
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
  /// days: "9h in 24h · 10h in 7d", or as shares of each window, "37.5%
  /// of 24h · 6% of 7d", as the time summary's toggle says.
  time('Time spent'),

  /// What its measure rates: "10h per 7 days".
  measure('Measure');

  const GoalSummary(this.label);

  /// How [_SummaryPicker] offers it.
  final String label;
}

/// Where the [GoalSummary] picked is kept.
const _summaryKey = 'goal_summary';

/// What [_summaryKey] held for time as a percentage, before that was the
/// time summary's toggle.
const _percentSummary = 'percent';

/// Where whether time is shown as durations is kept.
const _durationsKey = 'goal_time_durations';

/// Where whether the time summary is folded away is kept.
const _timeSummaryCollapsedKey = 'goal_time_summary_collapsed';

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

/// How wide each goal's band is, down the left of the Goals page: also
/// how far each level of sub-goals is indented, its band beside its
/// parent's.
const goalBandWidth = 6.0;

/// How long each dash of a dashed band is, and each gap between.
const _dash = 5.0;

/// How far a goal's band juts out to say it has sub-goals: as an arrow,
/// collapsed. (Expanded, it widens down over its sub-goals' bands.)
const _bandTip = 8.0;

class _GoalTile extends StatelessWidget {
  const _GoalTile({
    required this.goal,
    this.ancestors = const [],
    this.joined = 0,
    this.goalNames = const {},
    this.shownStatuses,
    this.summary = GoalSummary.time,
    this.durations = true,
    required this.subGoals,
    required this.expanded,
    required this.onToggle,
    required this.onTap,
    required this.onDetails,
    this.onLongPress,
    this.dragIndex,
    required this.onAddSubGoal,
    required this.onHistory,
    this.onTraits,
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

  /// Its ancestors, from the top: their bands run down beside its own.
  final List<Goal> ancestors;

  /// How many of [ancestors]' bands it shares with the row above, which
  /// run on up over the divider between them.
  final int joined;

  /// Every goal's name, by id, to say whose events it's measured by.
  final Map<String?, String> goalNames;

  /// The statuses the Goals page shows: its time is through goals with
  /// these. Null for all its time.
  final Set<String>? shownStatuses;

  /// What it shows under its name, above its other details.
  final GoalSummary summary;

  /// Whether its time is in durations, rather than percentages.
  final bool durations;

  /// How many sub-goals it has (of those shown); none, and it has no arrow.
  final int subGoals;

  /// Whether its sub-goals are shown.
  final bool expanded;

  /// Shows or hides its sub-goals: swiping it right does this.
  final VoidCallback onToggle;

  /// Opens it, to see and edit its priority, measure and color: tapping
  /// it, or "Edit" in its menu.
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

  /// Shows its traits page, for a goal rated by traits: "Traits" in its
  /// menu. Null for any other goal.
  final VoidCallback? onTraits;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final faded = goal.active ? null : TextStyle(color: theme.hintColor);
    final details = [
      if (!goal.active) goalStatuses[goal.status] ?? goal.status,
      if (goal.staleDays case final stale? when stale > 0)
        '$stale day${stale == 1 ? '' : 's'} unrated',
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
      _ => switch (filtered ?? (goal.minutes24h, goal.minutes7d)) {
        (final int day, final int week) => describeTime(
          day,
          week,
          skipZero: true,
          asPercent: !durations,
        ),
        _ => null,
      },
    };
    // Its own priority, filled; else the one it inherits, outlined. Only
    // an active goal's events take one.
    final priority = goal.active ? goal.effectivePriority : null;
    final bands = [
      for (final goal in [...ancestors, goal]) _bandOf(context, goal),
    ];
    final listTile = ListTile(
      contentPadding: const EdgeInsetsDirectional.only(start: 8, end: 4),
      // Its priority after its name, as the Events page puts it after an
      // event's summary.
      title: Text.rich(
        TextSpan(
          text: goalName(goal),
          children: [
            if (priority != null) ...[
              const TextSpan(text: ' '),
              WidgetSpan(
                alignment: PlaceholderAlignment.middle,
                child: PriorityChip(
                  priority: priority,
                  own: goal.priority != null,
                ),
              ),
            ],
          ],
        ),
        style: faded,
      ),
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
                'traits' => onTraits?.call(),
                'measure' => onTap?.call(),
                _ => onDetails(),
              },
              itemBuilder: (context) => [
                const PopupMenuItem(value: 'sub', child: Text('Add sub-goal')),
                const PopupMenuItem(value: 'measure', child: Text('Edit')),
                const PopupMenuItem(value: 'history', child: Text('History')),
                if (onTraits != null)
                  const PopupMenuItem(value: 'traits', child: Text('Traits')),
                const PopupMenuItem(value: 'details', child: Text('Details')),
              ],
            ),
        ],
      ),
    );
    final parent = subGoals > 0;
    final bandsWidth = goalBandWidth * bands.length + _bandTip;
    final tile = InkWell(
      onTap: saving ? null : onTap,
      onLongPress: saving ? null : onLongPress,
      // The row is as tall as its text; the bands are drawn down beside it.
      child: Stack(
        children: [
          Padding(
            padding: EdgeInsetsDirectional.only(start: bandsWidth),
            child: listTile,
          ),
          PositionedDirectional(
            start: 0,
            top: 0,
            bottom: 0,
            width: bandsWidth,
            // Not a tooltip: on a phone, one opens on the long press that
            // starts reordering.
            child: Semantics(
              label: parent
                  ? '${expanded ? 'Expanded' : 'Collapsed'}: swipe right to '
                        '${expanded ? 'collapse' : 'expand'}'
                  : null,
              child: GoalBands(
                bands: bands,
                joined: joined,
                shape: !parent
                    ? GoalBandShape.plain
                    : expanded
                    ? GoalBandShape.expanded
                    : GoalBandShape.collapsed,
              ),
            ),
          ),
        ],
      ),
    );
    // Swiping it right shows or hides its sub-goals, if it has any.
    return parent && !saving && dragIndex == null
        ? _SwipeRight(onSwipe: onToggle, child: tile)
        : tile;
  }

  /// [goal]'s band: its own color, solid, or the one it inherits, dashed.
  /// Only an active goal's is in color.
  static GoalBand _bandOf(BuildContext context, Goal goal) {
    final own = parseColor(goal.backgroundColor);
    final color = goal.active ? own ?? parseColor(goal.effectiveColor) : null;
    return GoalBand(
      color: color ?? Theme.of(context).colorScheme.outlineVariant,
      dashed: own == null || !goal.active,
    );
  }
}

/// [child], which follows a finger dragging it right, a little, and springs
/// back; dragged far enough, or flicked, it calls [onSwipe].
class _SwipeRight extends StatefulWidget {
  const _SwipeRight({required this.onSwipe, required this.child});

  final VoidCallback onSwipe;
  final Widget child;

  @override
  State<_SwipeRight> createState() => _SwipeRightState();
}

class _SwipeRightState extends State<_SwipeRight> {
  /// How far it's been dragged right, up to [_far].
  double _dx = 0;

  /// How far a drag has to go to count, and as far as the row follows it.
  static const _far = 48.0;

  @override
  Widget build(BuildContext context) => GestureDetector(
    onHorizontalDragUpdate: (details) =>
        setState(() => _dx = (_dx + details.delta.dx).clamp(0, _far)),
    onHorizontalDragEnd: (details) {
      if (_dx >= _far || (details.primaryVelocity ?? 0) > 600) {
        widget.onSwipe();
      }
      setState(() => _dx = 0);
    },
    onHorizontalDragCancel: () => setState(() => _dx = 0),
    child: AnimatedContainer(
      duration: _dx == 0 ? const Duration(milliseconds: 150) : Duration.zero,
      transform: Matrix4.translationValues(_dx, 0, 0),
      child: widget.child,
    ),
  );
}

/// One goal's band: its color, and whether it's dashed, for one inherited.
class GoalBand {
  const GoalBand({required this.color, required this.dashed});

  final Color color;
  final bool dashed;

  @override
  bool operator ==(Object other) =>
      other is GoalBand && other.color == color && other.dashed == dashed;

  @override
  int get hashCode => Object.hash(color, dashed);
}

/// How a goal's own band ends: plainly, with no sub-goals; as an arrow
/// pointing right, its sub-goals hidden; or slanting down to them, shown.
enum GoalBandShape { plain, collapsed, expanded }

/// A goal's [bands] side by side down the left of its row: its
/// ancestors', then its own, shaped as [shape] says. The first [joined]
/// run on up over the divider above, which they share with the row there.
///
/// Dashes are laid out from the top of the list, not of the row, so a
/// dashed band runs evenly down every row it's in.
class GoalBands extends LeafRenderObjectWidget {
  const GoalBands({
    super.key,
    required this.bands,
    required this.shape,
    required this.joined,
  });

  final List<GoalBand> bands;
  final GoalBandShape shape;
  final int joined;

  @override
  RenderGoalBands createRenderObject(BuildContext context) => RenderGoalBands(
    bands: bands,
    shape: shape,
    joined: joined,
    scroll: Scrollable.maybeOf(context)?.position,
  );

  @override
  void updateRenderObject(BuildContext context, RenderGoalBands renderObject) =>
      renderObject
        ..bands = bands
        ..shape = shape
        ..joined = joined
        ..scroll = Scrollable.maybeOf(context)?.position
        // Rows above may have grown or shrunk, moving this one without
        // repainting it, which would leave its dashes out of step.
        ..markNeedsPaint();
}

/// Lays out and paints [GoalBands].
class RenderGoalBands extends RenderBox {
  RenderGoalBands({
    required this._bands,
    required this._shape,
    required this._joined,
    required this.scroll,
  });

  /// The list's scrolling, to find where in the list the row is.
  ScrollPosition? scroll;

  List<GoalBand> _bands;
  set bands(List<GoalBand> value) {
    if (listEquals(value, _bands)) return;
    _bands = value;
    markNeedsPaint();
  }

  GoalBandShape _shape;
  set shape(GoalBandShape value) {
    if (value == _shape) return;
    _shape = value;
    markNeedsPaint();
  }

  int _joined;
  set joined(int value) {
    if (value == _joined) return;
    _joined = value;
    markNeedsPaint();
  }

  @override
  bool get sizedByParent => true;

  @override
  Size computeDryLayout(BoxConstraints constraints) => constraints.biggest;

  /// How far the row's top is from the list's: where it sits in the
  /// viewport, plus how far that's scrolled. Rows painted at different
  /// scrolls agree on it.
  double get _top {
    final viewport = RenderAbstractViewport.maybeOf(this);
    final scroll = this.scroll;
    if (viewport == null || scroll == null || !scroll.hasPixels) return 0;
    return localToGlobal(Offset.zero, ancestor: viewport).dy + scroll.pixels;
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final canvas = context.canvas;
    final h = size.height;
    final top = _top;
    canvas.save();
    canvas.translate(offset.dx, offset.dy);
    // Dashes [from] to [to] across, [y0] to [h] down, as the [column]th
    // band's: every other band's are offset by one, so dashed bands side
    // by side make a checkerboard, each level apart from the next.
    void dashes(Paint paint, int column, double from, double to, double y0) {
      const period = 2 * _dash;
      var y = -(top % period) + (column.isOdd ? _dash : 0) - period;
      for (; y < h; y += period) {
        final rect = Rect.fromLTRB(from, y, to, y + _dash);
        if (rect.bottom > y0) {
          canvas.drawRect(
            rect.intersect(Rect.fromLTRB(from, y0, to, h)),
            paint,
          );
        }
      }
    }

    for (final (i, band) in _bands.indexed) {
      final x0 = goalBandWidth * i;
      final x1 = x0 + goalBandWidth;
      // Over the divider above, if it's shared with the row there.
      final y0 = i < _joined ? -1.0 : 0.0;
      final paint = Paint()..color = band.color;
      final shape = i == _bands.length - 1 ? _shape : GoalBandShape.plain;
      if (band.dashed) {
        dashes(paint, i, x0, x1, y0);
      } else {
        canvas.drawRect(Rect.fromLTRB(x0, y0, x1, h), paint);
      }
      switch (shape) {
        case GoalBandShape.plain:
          break;
        case GoalBandShape.collapsed:
          // An arrow pointing right, as tall as the row, always solid:
          // dashed, it'd be too faint to see.
          final mid = h / 2;
          canvas.drawPath(
            Path()
              ..moveTo(x1, 0)
              ..lineTo(x1 + _bandTip, mid)
              ..lineTo(x1, h)
              ..close(),
            paint,
          );
        case GoalBandShape.expanded:
          // Widening down over where its sub-goals' bands start, dashed as
          // the next band's would be.
          final slant = Path()
            ..moveTo(x1, 0)
            ..lineTo(x1 + goalBandWidth, h)
            ..lineTo(x1, h)
            ..close();
          if (!band.dashed) {
            canvas.drawPath(slant, paint);
          } else {
            canvas.save();
            canvas.clipPath(slant);
            dashes(paint, i + 1, x1, x1 + goalBandWidth, 0);
            canvas.restore();
          }
      }
    }
    canvas.restore();
  }
}

/// [goals] with [saved], saves the server has answered, made to them, as
/// far as they don't have them yet: each new goal added, with the id the
/// server gave it if that's known, and each goal's changes made.
GoalList _withSaved(
  GoalList goals,
  List<({PendingGoalSave item, String? result})> saved,
) {
  var shown = goals;
  for (final (:item, :result) in saved) {
    if (!item.isNew) {
      shown = _withChanged(shown, item.goalId, item.changes);
    } else if (item.madeIn(shown) == null &&
        !shown.goals.any((g) => result != null && g.id == result)) {
      shown = _inTree(shown, [
        ...shown.goals,
        Goal.fromJson({...item.goal.toJson(), 'id': result ?? item.goalId}),
      ]);
    }
  }
  return shown;
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
/// ancestors' names, and the priority each inherits from them.
GoalList _inTree(GoalList list, List<Goal> goals) {
  final ids = {for (final goal in goals) goal.id};
  final children = <String?, List<Goal>>{};
  for (final goal in goals) {
    final parent = ids.contains(goal.parentId) ? goal.parentId : null;
    children.putIfAbsent(parent, () => []).add(goal);
  }
  final ordered = <Goal>[];
  void visit(Goal goal, Goal? parent, String? parentPath) {
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
    // Under a goal that isn't listed, what it inherits is as it was.
    final priority =
        goal.priority ??
        (parent != null
            ? parent.effectivePriority
            : goal.parentId == null
            ? null
            : goal.effectivePriority);
    final shown = path == goal.path && priority == goal.effectivePriority
        ? goal
        : Goal.fromJson({
            ...goal.toJson(),
            'path': path,
            'effective_priority': priority,
          });
    ordered.add(shown);
    for (final child in children[goal.id] ?? const <Goal>[]) {
      visit(child, shown, path);
    }
  }

  children[null]?.forEach((goal) => visit(goal, null, null));
  return GoalList(
    goals: ordered,
    labelSlotsUsed: list.labelSlotsUsed,
    labelSlotsTotal: list.labelSlotsTotal,
    asOf: list.asOf,
    minutesByStatuses: list.minutesByStatuses,
    minutesByPriority: list.minutesByPriority,
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
    minutesByPriority: goals.minutesByPriority,
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
    this.durations = true,
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

  /// Whether its time is in durations, rather than percentages.
  final bool durations;
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
      (_, (final day, final week)) =>
        '${describeTime(day, week, asPercent: !durations)!} '
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
