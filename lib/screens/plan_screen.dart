import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/goal.dart';
import '../models/person.dart';
import '../outbox/goal_outbox.dart';
import '../outbox/pending_goal_save.dart';
import '../outbox/save_error.dart';
import '../services/goals_repository.dart';
import '../services/mcp_client.dart';
import '../services/people_repository.dart';
import '../services/traits_repository.dart';
import 'locations_pane.dart';
import 'people_pane.dart';
import 'traits_pane.dart';
import '../widgets/app_menu.dart';
import '../widgets/color_picker.dart';
import '../widgets/durations.dart';
import '../widgets/goals_time_summary.dart';
import '../widgets/priority_chip.dart';
import '../widgets/goal_dialog.dart';
import '../widgets/plan_pane.dart';
import '../widgets/refreshing_bar.dart';
import '../widgets/status_message.dart';

/// The Plan page: panes to swipe between, or pick from the tabs at the
/// top, each with a search of its own --
///
/// * **Actions**, what to do, leftmost: the actions, kept as goals, and
///   the groups they're in, as a tree;
/// * **Traits**, how to be ([TraitsPane]), from the [TraitsScope];
/// * **People**, who to be with, Self always among them ([PeoplePane]),
///   from the [PeopleScope];
/// * **Locations**, where ([LocationsPane]), from the [PeopleScope].
///
/// The Actions pane shows each action and group: its color, name, status,
/// priority (as a chip, like the Events page's) and, where it's known
/// (the sample data), the time spent on it in the last 24 hours and 7
/// days up to the last compaction, with what's in a group indented under
/// it. A group starts collapsed; swiping it right -- which, Actions being
/// the leftmost pane, does nothing else -- expands it. Searching shows
/// the actions and groups whose name, path or note match, in their
/// groups. Where the repository is [GoalsRepository.reorderable],
/// pressing and holding one starts reordering: each can be dragged among
/// its siblings, what's in it going with it, until "Done". The filter
/// beside the search picks which statuses are shown: proposed and active
/// to start with. Only active actions take up a calendar label; a group
/// never does. A proposed action -- one Claude made -- can be approved
/// from its menu. Tapping one opens its details; a group's menu adds an
/// action or a group to it.
class PlanScreen extends StatefulWidget {
  const PlanScreen({
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
  State<PlanScreen> createState() => _PlanScreenState();
}

class _PlanScreenState extends State<PlanScreen> {
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

  /// What the Actions pane's search has in it.
  String _query = '';

  /// Whether the time summary is folded away.
  bool _timeSummaryCollapsed = false;

  /// Whether time is shown as durations, rather than as percentages:
  /// in the time summary, and under each action.
  bool _durations = true;

  /// Everyone, and each location's name, for the panes that name them:
  /// loaded once here, and again whenever the People or Locations pane
  /// loads them.
  PeopleList? _people;
  Map<String?, String> _locationNames = const {};
  bool _namesAsked = false;

  @override
  void initState() {
    super.initState();
    widget.outbox.addListener(_outboxChanged);
    _saveEvents = widget.outbox.events.listen(_onSaveEvent);
    _showCached();
    _load();
    _loadDurations();
    _loadTimeSummaryCollapsed();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_namesAsked) {
      _namesAsked = true;
      _loadNames();
    }
  }

  /// Everyone and every location, for their names. Best effort: without
  /// them, they're named by id.
  Future<void> _loadNames() async {
    final repository = PeopleScope.of(context);
    if (repository == null) return;
    try {
      final people = await repository.people();
      final locations = await repository.locations();
      if (!mounted) return;
      setState(() {
        _people = people;
        _locationNames = {for (final l in locations) l.id: l.name};
      });
    } catch (_) {
      // The panes say why, when they're shown.
    }
  }

  /// Whether time was in durations last time. Best effort, like the
  /// response cache: without it, it's in durations.
  Future<void> _loadDurations() async {
    try {
      final durations = await SharedPreferencesAsync().getBool(_durationsKey);
      if (!mounted || durations == null) return;
      setState(() => _durations = durations);
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
  /// as [_loadDurations].
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
              "Couldn't save ${name ?? 'an action'}. ${save.lastError}"
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

  Map<String?, String> get _goalNames => {
    for (final goal in _goals?.goals ?? const <Goal>[]) goal.id: goalName(goal),
  };

  /// The actions and groups a trait's part can count, by id, each by its
  /// path.
  Map<String, String> get _actionChoices => {
    for (final goal in _goals?.goals ?? const <Goal>[])
      if (goal.id != null && goal.status != 'deleted')
        goal.id!: goal.path ?? goalName(goal),
  };

  /// Approves [goal], one Claude proposed: it becomes active.
  void _approve(Goal goal) =>
      widget.outbox.update(goal.id!, {'status': 'active'});

  Future<void> _add({String? parentId, bool group = false}) async {
    // So the new one can be seen.
    if (parentId != null) setState(() => _expanded.add(parentId));
    await showNewGoalDialog(
      context,
      create: _create,
      parentId: parentId,
      group: group,
      goals: _allGoals,
    );
  }

  /// Whether to move [goal] to [status]: freeing its label, or deleting it,
  /// is worth a second look.
  Future<bool> _confirmStatus(Goal goal, String status) async {
    final name = goalName(goal);
    // Freeing a label, or deleting, is worth a second look.
    final (String, String, String)? check = switch (status) {
      'deleted' => (
        'Delete $name?',
        "Its history is kept, and events that have it keep it, but no event "
            "can be given it again. It's hidden unless you show deleted "
            'actions.',
        'Delete',
      ),
      _ when goal.active && !goal.isGroup => (
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
    final goals = _goals;
    final ready = goals != null && !_needsSignIn;
    final reordering = _reordering && ready;
    final traits = TraitsScope.of(context);
    final people = PeopleScope.of(context);
    final personNames = {
      for (final person in _people?.withSelf ?? const [defaultSelf])
        person.id: personName(person),
    };
    // Actions leftmost, so swiping a group right, to open or close it,
    // has nothing else to do.
    final panes = <(String, String, Widget)>[
      ('Actions', 'do', _actionsPane(context)),
      if (traits != null)
        (
          'Traits',
          'how to be',
          TraitsPane(
            repository: traits,
            personNames: personNames,
            actions: _actionChoices,
          ),
        ),
      if (people != null) ...[
        (
          'People',
          'who',
          PeoplePane(
            repository: people,
            traits: traits,
            onPeople: (people) => setState(() => _people = people),
            actionNames: _goalNames,
            actions: _actionChoices,
            locationNames: _locationNames,
          ),
        ),
        (
          'Locations',
          'where',
          LocationsPane(
            repository: people,
            onLocations: (locations) => setState(
              () => _locationNames = {for (final l in locations) l.id: l.name},
            ),
          ),
        ),
      ],
    ];
    final theme = Theme.of(context);
    return PopScope(
      canPop: !reordering,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) setState(() => _reordering = false);
      },
      child: DefaultTabController(
        length: panes.length,
        child: Scaffold(
          appBar: AppBar(
            title: Text(reordering ? 'Reorder actions' : 'Plan'),
            actions: reordering
                ? [
                    TextButton(
                      onPressed: () => setState(() => _reordering = false),
                      child: const Text('Done'),
                    ),
                  ]
                : [
                    AppMenu(
                      serverLabel: widget.serverLabel,
                      version: widget.version,
                      onSignOut: widget.onSignOut == null || _needsSignIn
                          ? null
                          : _signOut,
                    ),
                  ],
            bottom: reordering || _needsSignIn || panes.length < 2
                ? null
                : TabBar(
                    tabs: [
                      for (final (title, annotation, _) in panes)
                        Tab(
                          height: 52,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(title),
                              Text(
                                annotation,
                                style: theme.textTheme.labelSmall?.copyWith(
                                  fontStyle: FontStyle.italic,
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
          ),
          body: RefreshingBar(
            refreshing:
                (_stale && _error == null && !_needsSignIn) ||
                widget.outbox.busy,
            child: switch ((_needsSignIn, reordering)) {
              (true, _) => _signInPrompt(),
              (_, true) => _reorderable(goals!),
              _ when panes.length == 1 => panes.single.$3,
              _ => TabBarView(children: [for (final pane in panes) pane.$3]),
            },
          ),
        ),
      ),
    );
  }

  Widget _signInPrompt() => FillViewport(
    child: StatusMessage(
      icon: Icons.lock_outline,
      text: 'Sign in to see your plan.',
      action: widget.onSignIn == null
          ? null
          : FilledButton(
              onPressed: _signingIn ? null : _signIn,
              child: Text(_signingIn ? 'Waiting for browser…' : 'Sign in'),
            ),
    ),
  );

  /// The Actions pane: its search, status filter and "+", over the time
  /// spent on them, then the tree, or why it can't be shown.
  Widget _actionsPane(BuildContext context) => PlanPane(
    searchHint: 'Search actions',
    onSearch: (query) => setState(() => _query = query),
    actions: [
      _StatusFilter(
        shown: _shown,
        onChanged: (status, on) =>
            setState(() => on ? _shown.add(status) : _shown.remove(status)),
      ),
      PopupMenuButton<bool>(
        tooltip: 'Add an action or group',
        icon: const Icon(Icons.add),
        enabled: _goals != null,
        onSelected: (group) => _add(group: group),
        itemBuilder: (_) => const [
          PopupMenuItem(value: false, child: Text('New action')),
          PopupMenuItem(value: true, child: Text('New group')),
        ],
      ),
    ],
    child: RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(bottom: 24),
        children: _actions(context),
      ),
    ),
  );

  /// The Actions pane's list: the time spent on them, then the tree, or
  /// why it can't be shown.
  List<Widget> _actions(BuildContext context) {
    final goals = _goals;
    if (_error != null && (goals == null || goals.goals.isEmpty)) {
      return [
        StatusMessage(
          icon: Icons.cloud_off,
          text: 'Could not load actions.\n$_error',
        ),
      ];
    }
    if (goals == null) return const [LinearProgressIndicator()];
    final tree = _Tree(goals, _shown, _expanded, query: _query);
    if (tree.all.isEmpty) {
      return const [
        StatusMessage(
          icon: Icons.bolt_outlined,
          text: 'No actions yet.\nTap + to add one.',
        ),
      ];
    }
    final shown = tree.shown;
    final onGoals = goals.timeFor(_shown);
    final searching = _query.trim().isNotEmpty;
    return [
      // The last actions loaded, or kept from last time, are still shown.
      if (_error != null)
        StatusMessage(
          icon: Icons.cloud_off,
          text: 'Could not load actions. These may be out of date.\n$_error',
        ),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
        child: Wrap(
          spacing: 16,
          runSpacing: 4,
          children: [
            // Time spent is only counted where it's known.
            if (goals.asOf case final asOf?)
              Tooltip(
                message:
                    'Time spent is counted up to when notes were last '
                    'compacted into the calendar.',
                child: Text(
                  'Last compacted ${formatTimestamp(context, asOf)}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            Tooltip(
              message:
                  "Each active action takes one of the calendar's event "
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
      if (onGoals != null && !searching)
        GoalsTimeSummary(
          visible: shown,
          byId: tree.byId,
          statuses: _shown,
          onGoals: onGoals,
          byPriority: goals.minutesByPriority,
          collapsed: _timeSummaryCollapsed,
          onCollapsed: _setTimeSummaryCollapsed,
          durations: _durations,
          onDurations: _setDurations,
        ),
      if (shown.isEmpty)
        searching
            ? NoMatches(query: _query)
            : const StatusMessage(
                icon: Icons.bolt_outlined,
                text: 'No actions with these statuses.',
              ),
      for (final (i, goal) in shown.indexed) ...[
        if (i > 0) tree.divider(i),
        _GoalTile(
          goal: goal,
          ancestors: tree.ancestors[i],
          joined: tree.sharedAbove(i),
          shownStatuses: _shown,
          durations: _durations,
          subGoals: tree.subGoals[goal.id] ?? 0,
          // A search shows what's in the groups it finds.
          expanded: searching || _expanded.contains(goal.id),
          onToggle: searching
              ? null
              : () => setState(() {
                  if (!_expanded.remove(goal.id)) _expanded.add(goal.id!);
                }),
          // One the server hasn't made yet has nothing to open, and
          // nothing is reordered under changes still being saved, or
          // around one that couldn't be made.
          saving: _unmade(goal.id) && _failed(goal.id) == null,
          failed: switch (_failed(goal.id)) {
            null => null,
            final save when save.refused => save.lastError,
            final save => '${save.lastError}. Trying again soon',
          },
          onTap: () => _open(goal),
          onRetry: () => widget.outbox.retry(goal.id!),
          onDiscard: () => _discard(goal.id!),
          onLongPress:
              !widget.repository.reorderable ||
                  searching ||
                  widget.outbox.busy ||
                  widget.outbox.saves.any((s) => s.isNew)
              ? null
              : () => setState(() => _reordering = true),
          onAddAction: () => _add(parentId: goal.id),
          onAddGroup: () => _add(parentId: goal.id, group: true),
          onApprove: goal.proposed ? () => _approve(goal) : null,
        ),
      ],
    ];
  }

  /// The actions shown, to drag into a new order among their siblings.
  Widget _reorderable(GoalList goals) {
    final tree = _Tree(goals, _shown, _expanded);
    final shown = tree.shown;
    return ReorderableListView.builder(
      buildDefaultDragHandles: false,
      padding: const EdgeInsets.only(bottom: 24),
      header: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
        child: Text(
          'Drag an action or group by its handle to move it among those it '
          "sits with; what's in a group goes with it.",
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ),
      itemCount: shown.length,
      onReorderItem: (from, to) => _reorder(shown, from, to),
      itemBuilder: (context, i) => Column(
        key: ValueKey(shown[i].id),
        mainAxisSize: MainAxisSize.min,
        children: [
          if (i > 0) tree.divider(i),
          _GoalTile(
            goal: shown[i],
            ancestors: tree.ancestors[i],
            joined: tree.sharedAbove(i),
            subGoals: tree.subGoals[shown[i].id] ?? 0,
            expanded: _expanded.contains(shown[i].id),
            dragIndex: i,
            onToggle: () => setState(() {
              if (!_expanded.remove(shown[i].id)) _expanded.add(shown[i].id!);
            }),
            onTap: null,
          ),
        ],
      ),
    );
  }
}

/// The actions and groups as the Actions pane shows them: those with the
/// statuses shown, less those under a collapsed group -- or, searching
/// for [query], those whose name, path or note match it, and the groups
/// they're in -- each with the groups it's in, from the top, whose bands
/// it carries.
class _Tree {
  _Tree(
    GoalList goals,
    Set<String> statuses,
    Set<String> expanded, {
    String query = '',
  }) {
    all = goals.goals;
    byId = {for (final goal in all) goal.id: goal};
    final withStatus = [
      for (final goal in all)
        if (statuses.contains(goal.status)) goal,
    ];
    for (final goal in withStatus) {
      subGoals.update(goal.parentId, (n) => n + 1, ifAbsent: () => 1);
    }
    // One is hidden under any collapsed ancestor that's shown. One whose
    // parent's status is filtered out still shows, where it always has.
    bool underCollapsed(Goal goal) {
      for (
        var parent = byId[goal.parentId];
        parent != null;
        parent = byId[parent.parentId]
      ) {
        if (statuses.contains(parent.status) && !expanded.contains(parent.id)) {
          return true;
        }
      }
      return false;
    }

    if (query.trim().isEmpty) {
      shown = [
        for (final goal in withStatus)
          if (!underCollapsed(goal)) goal,
      ];
    } else {
      // What matches, and every group above it.
      final found = <String?>{};
      for (final goal in withStatus) {
        final texts = [
          goal.name,
          goal.path,
          goal.properties['note'] as String?,
        ];
        if (!matchesSearch(query, texts)) continue;
        found.add(goal.id);
        for (
          var parent = byId[goal.parentId];
          parent != null && found.add(parent.id);
          parent = byId[parent.parentId]
        ) {}
      }
      shown = [
        for (final goal in withStatus)
          if (found.contains(goal.id)) goal,
      ];
      subGoals.clear();
      for (final goal in shown) {
        subGoals.update(goal.parentId, (n) => n + 1, ifAbsent: () => 1);
      }
    }
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

    ancestors = [for (final goal in shown) ancestorsOf(goal)];
  }

  late final List<Goal> all;
  late final Map<String?, Goal> byId;

  /// How many of each one's children are shown, or could be.
  final subGoals = <String?, int>{};
  late final List<Goal> shown;
  late final List<List<Goal>> ancestors;

  /// How many of the [i]th one's bands it shares with the one above it,
  /// which run unbroken over the divider between them.
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
}

/// The Actions pane's filter: a drop-down of every status, each with a check
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
        tooltip: 'Show actions that are…',
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

/// Where whether time is shown as durations is kept.
const _durationsKey = 'goal_time_durations';

/// Where whether the time summary is folded away is kept.
const _timeSummaryCollapsedKey = 'goal_time_summary_collapsed';

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
    this.shownStatuses,
    this.durations = true,
    required this.subGoals,
    required this.expanded,
    required this.onToggle,
    required this.onTap,
    this.onLongPress,
    this.dragIndex,
    this.onAddAction,
    this.onAddGroup,
    this.onApprove,
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
  /// its menu, which offers [onRetry], [onTap] (to edit what wasn't saved)
  /// and [onDiscard].
  final String? failed;
  final VoidCallback? onRetry;
  final VoidCallback? onDiscard;

  /// Its ancestors, from the top: their bands run down beside its own.
  final List<Goal> ancestors;

  /// How many of [ancestors]' bands it shares with the row above, which
  /// run on up over the divider between them.
  final int joined;

  /// The statuses the Plan page shows: its time is through actions with
  /// these. Null for all its time.
  final Set<String>? shownStatuses;

  /// Whether its time is in durations, rather than percentages.
  final bool durations;

  /// How many sub-goals it has (of those shown); none, and it has no arrow.
  final int subGoals;

  /// Whether its sub-goals are shown.
  final bool expanded;

  /// Shows or hides what's in it: swiping it right does this. Null while
  /// a search shows everything found in it.
  final VoidCallback? onToggle;

  /// Opens its details, to see and edit: tapping it, or "Edit" in its
  /// menu.
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  /// While reordering, its index in the list, for its drag handle; null
  /// otherwise, when it has its menu instead.
  final int? dragIndex;

  /// Adds an action, or a group, to it: "Add action" and "Add group" in a
  /// group's menu. An action has neither: actions are always leaves.
  final VoidCallback? onAddAction;
  final VoidCallback? onAddGroup;

  /// Makes a proposed action active: "Approve" in its menu.
  final VoidCallback? onApprove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final faded = goal.active ? null : TextStyle(color: theme.hintColor);
    final details = [
      if (goal.proposed)
        'Proposed by Claude: review it'
      else if (!goal.active)
        goalStatuses[goal.status] ?? goal.status,
      if (goal.isGroup && subGoals == 0) 'Empty group',
    ].nonNulls.join(' · ');
    // Through what's in it with the statuses shown, if that's known; else
    // all of it.
    final filtered = switch (shownStatuses) {
      final shown? => goal.timeFor(shown),
      null => null,
    };
    final shown = switch (filtered ?? (goal.minutes24h, goal.minutes7d)) {
      (final int day, final int week) => describeTime(
        day,
        week,
        skipZero: true,
        asPercent: !durations,
      ),
      _ => null,
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
          if (failed case final why?)
            PopupMenuButton<String>(
              tooltip: 'Not saved: $why',
              icon: Icon(Icons.error_outline, color: theme.colorScheme.error),
              onSelected: (choice) => switch (choice) {
                'retry' => onRetry?.call(),
                'discard' => onDiscard?.call(),
                _ => onTap?.call(),
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
                'approve' => onApprove?.call(),
                'action' => onAddAction?.call(),
                'group' => onAddGroup?.call(),
                _ => onTap?.call(),
              },
              itemBuilder: (context) => [
                if (onApprove != null)
                  const PopupMenuItem(value: 'approve', child: Text('Approve')),
                if (goal.isGroup) ...[
                  if (onAddAction != null)
                    const PopupMenuItem(
                      value: 'action',
                      child: Text('Add action'),
                    ),
                  if (onAddGroup != null)
                    const PopupMenuItem(
                      value: 'group',
                      child: Text('Add group'),
                    ),
                ],
                const PopupMenuItem(value: 'edit', child: Text('Edit')),
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
    // Swiping it right shows or hides what's in it, if anything is.
    return switch (onToggle) {
      final onToggle? when parent && !saving && dragIndex == null =>
        _SwipeRight(onSwipe: onToggle, child: tile),
      _ => tile,
    };
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
/// back; dragged far enough, or flicked, it calls [onSwipe]. Only a drag
/// right is its: one left is left to what it's in -- the Plan page's
/// panes, which it swipes between.
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
  Widget build(BuildContext context) => RawGestureDetector(
    gestures: {
      _RightDragRecognizer:
          GestureRecognizerFactoryWithHandlers<_RightDragRecognizer>(
            _RightDragRecognizer.new,
            (recognizer) {
              recognizer
                ..onUpdate = (details) {
                  setState(() => _dx = (_dx + details.delta.dx).clamp(0, _far));
                }
                ..onEnd = (details) {
                  if (_dx >= _far || (details.primaryVelocity ?? 0) > 600) {
                    widget.onSwipe();
                  }
                  setState(() => _dx = 0);
                }
                ..onCancel = () => setState(() => _dx = 0);
            },
          ),
    },
    child: AnimatedContainer(
      duration: _dx == 0 ? const Duration(milliseconds: 150) : Duration.zero,
      transform: Matrix4.translationValues(_dx, 0, 0),
      child: widget.child,
    ),
  );
}

/// A horizontal drag that's only claimed once it's gone right: one that
/// goes left first loses to whatever else wants it.
class _RightDragRecognizer extends HorizontalDragGestureRecognizer {
  _RightDragRecognizer({super.debugOwner});

  @override
  bool hasSufficientGlobalDistanceToAccept(
    PointerDeviceKind pointerDeviceKind,
    double? deviceTouchSlop,
  ) => globalDistanceMoved > computeHitSlop(pointerDeviceKind, gestureSettings);
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
