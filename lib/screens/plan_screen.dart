import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/plan_action.dart';
import '../models/person.dart';
import '../outbox/action_outbox.dart';
import '../outbox/pending_action_save.dart';
import '../outbox/save_error.dart';
import '../services/event_store.dart';
import '../services/events_repository.dart';
import '../services/actions_repository.dart';
import '../services/mcp_client.dart';
import '../services/notes_repository.dart';
import '../services/people_repository.dart';
import '../services/plan_memory.dart';
import '../services/traits_repository.dart';
import 'locations_pane.dart';
import 'people_pane.dart';
import 'traits_pane.dart';
import '../widgets/action_dialog.dart';
import '../widgets/app_menu.dart';
import '../widgets/color_picker.dart';
import '../widgets/durations.dart';
import '../widgets/priority_chip.dart';
import '../widgets/action_details_dialog.dart';
import '../widgets/plan_pane.dart';
import '../widgets/plan_summaries.dart';
import '../widgets/time_summary.dart';
import '../widgets/refreshing_bar.dart';
import '../widgets/status_message.dart';

/// The Plan page: panes to swipe between, or pick from the tabs at the
/// top, each with a search of its own --
///
/// * **Actions**, what to do, leftmost: the actions, kept as actions, and
///   the groups they're in, as a tree;
/// * **Traits**, how to be ([TraitsPane]), from the [TraitsScope];
/// * **People**, who to be with, Self always among them ([PeoplePane]),
///   from the [PeopleScope];
/// * **Locations**, where ([LocationsPane]), from the [PeopleScope].
///
/// Landing on it loads everything at once, every pane's and the
/// summaries', starting from what [memory] kept from the last visit, or
/// else the repositories kept from the app's last run, so nothing shows
/// empty while it loads.
///
/// The Actions, People and Locations panes each have a summary, above
/// their search, of the time in its window -- the 24 hours and 7 days
/// before, or after, the last compaction, or a day at a time from it --
/// worked out from the events in it ([eventsRepository]); one window for
/// all three. The Actions pane's splits the time by the actions shown, or
/// by priority. Under it, each action and group: its color, name,
/// status, priority (as a chip, like the Events page's) and the time on
/// it in the window, with what's in a group indented under it. Tapping a
/// group opens or closes it; tapping an action, or "Edit" in a group's
/// menu, edits its priority and color ([showActionDialog]), from which
/// "Details" opens the rest. Searching shows the actions and groups
/// whose name, path or note match, in their groups. Where the repository
/// is [ActionsRepository.reorderable], pressing and holding one starts
/// reordering: each can be dragged among its siblings, what's in it
/// going with it, until "Done". The filter beside the search picks which
/// statuses are shown: proposed and active to start with. Only active
/// actions take up a calendar label; a group never does. A proposed
/// action -- one Claude made -- can be approved from its menu.
class PlanScreen extends StatefulWidget {
  const PlanScreen({
    super.key,
    required this.repository,
    required this.outbox,
    required this.serverLabel,
    this.eventsRepository,
    this.notesRepository,
    this.memory,
    this.onSignIn,
    this.onSignOut,
    this.version,
  });

  final ActionsRepository repository;

  /// The events the summaries measure; without it, there are none.
  final EventsRepository? eventsRepository;

  /// When notes were last compacted, which the summaries measure from by
  /// default; without it, they measure from now.
  final NotesRepository? notesRepository;

  /// What the page showed last time it was open, to show again while it
  /// loads; without it, it starts empty.
  final PlanMemory? memory;

  /// Where saves go, to be sent in the background: the dialogs close at
  /// once, as notes' do.
  final ActionOutbox outbox;

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
  /// The actions as the server last listed them.
  ActionList? _fromServer;

  /// The actions shown: [_fromServer], with the saves made since it was
  /// fetched, here or by the background task, then those waiting in the
  /// outbox, or that failed, made to them.
  ActionList? get _actions => switch (_fromServer) {
    final actions? => _withSaves(
      _withSaved(actions, widget.outbox.justSaved),
      widget.outbox.saves,
    ),
    null => null,
  };

  StreamSubscription<ActionSaveEvent>? _saveEvents;

  /// [_fromServer] are the ones kept from last time; the server hasn't
  /// answered since.
  bool _stale = false;
  Object? _error;
  bool _needsSignIn = false;
  bool _signingIn = false;

  /// The statuses shown.
  final _shown = {...defaultActionStatuses};

  /// The actions whose sub-actions are shown; every other action is collapsed.
  final _expanded = <String>{};

  /// Whether actions are being dragged into a new order.
  bool _reordering = false;

  /// What the Actions pane's search has in it.
  String _query = '';

  /// Whether the time summary is folded away.
  bool _timeSummaryCollapsed = false;

  /// Whether time is shown as durations, rather than as percentages:
  /// in the time summary, and under each action.
  bool _durations = true;

  /// What's kept from visit to visit: the panes' data, and the
  /// summaries' window.
  late final PlanMemory _memory = widget.memory ?? PlanMemory();

  /// Why the summaries' events couldn't be loaded, if they couldn't.
  Object? _eventsError;
  bool _prefetched = false;

  PeopleList? get _people => _memory.people;

  Map<String?, String> get _locationNames => {
    for (final l in _memory.locations ?? const <Location>[]) l.id: l.name,
  };

  @override
  void initState() {
    super.initState();
    _memory.newVisit();
    // On its own, without the app's: the summaries' events go in one of
    // its own.
    if (widget.eventsRepository case final events?) {
      _memory.useEvents(EventStore(repository: events));
    }
    _fromServer = _memory.actions;
    widget.outbox.addListener(_outboxChanged);
    _saveEvents = widget.outbox.events.listen(_onSaveEvent);
    _showCached();
    _load();
    _loadDurations();
    _loadTimeSummaryCollapsed();
    _loadCompaction();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_prefetched) {
      _prefetched = true;
      _prefetch();
    }
  }

  /// Loads every pane's data at once, from what was kept from the app's
  /// last run, then the server, so each is ready when it's swiped to.
  /// Best effort: each pane says why, if its load failed.
  Future<void> _prefetch() async {
    final traits = TraitsScope.of(context);
    final people = PeopleScope.of(context);
    // On its own, without the home screen to load the events the traits
    // are scored from as the app opens: loads them here.
    if (!_memory.warmed && widget.eventsRepository != null) {
      unawaited(
        _memory.warmScores(
          traits: traits,
          people: people,
          actions: widget.repository,
        ),
      );
    }
    await _memory.loadKept(traits: traits, people: people);
    if (mounted) setState(() {});
    Future<void> quietly(Future<void>? loading) async {
      try {
        await loading;
        if (mounted) setState(() {});
      } catch (_) {
        // Said by the pane.
      }
    }

    await Future.wait([
      quietly(traits == null ? null : _memory.loadTraits(traits)),
      quietly(people == null ? null : _memory.loadPeople(people)),
      quietly(people == null ? null : _memory.loadLocations(people)),
    ]);
  }

  /// When notes were last compacted, kept from last time, then the
  /// server's, then the summaries' events. Best effort: without it, they
  /// measure from now.
  Future<void> _loadCompaction() async {
    final notes = widget.notesRepository;
    try {
      if (notes != null) {
        await _memory.loadKept(notes: notes);
        if (mounted) setState(() {});
        await _memory.loadCompaction(notes);
      }
    } catch (_) {
      // Measured from what's known.
    }
    if (mounted) setState(() {});
    await _loadEvents();
  }

  /// Loads the events in the summaries' window, unless they're loaded
  /// already this visit; with [again], afresh.
  Future<void> _loadEvents({bool again = false}) async {
    if (widget.eventsRepository == null) return;
    try {
      await _memory.loadEvents(_memory.window(DateTime.now()), again: again);
      if (mounted) setState(() => _eventsError = null);
    } catch (e) {
      if (mounted) setState(() => _eventsError = e);
    }
  }

  /// Moves the summaries' window to [days] from the last compaction, or
  /// on from it rather than back with [forward].
  void _moveWindow({int? days, bool? forward}) {
    setState(() {
      _memory.dayOffset = days ?? _memory.dayOffset;
      _memory.forward = forward ?? _memory.forward;
      _eventsError = null;
    });
    _loadEvents();
  }

  /// What every summary measures, and how they're shown; null without
  /// events to measure.
  SummaryView? get _summaryView {
    if (widget.eventsRepository == null) return null;
    final window = _memory.window(DateTime.now());
    return SummaryView(
      window: window,
      lastCompaction: _memory.lastCompaction,
      dayOffset: _memory.dayOffset,
      collapsed: _timeSummaryCollapsed,
      durations: _durations,
      onDays: (days) => _moveWindow(days: days),
      onForward: (forward) => _moveWindow(forward: forward),
      onCollapsed: _setTimeSummaryCollapsed,
      onDurations: _setDurations,
      events: _memory.windowEvents(window),
      error: _eventsError,
    );
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

  /// Shows the actions kept from last time, unless the server answered
  /// first.
  Future<void> _showCached() async {
    await _memory.loadKept(actions: widget.repository);
    final actions = _memory.actions;
    if (!mounted || actions == null) return;
    if (_fromServer != null || _needsSignIn || _error != null) return;
    setState(() {
      _fromServer = _memory.actions = actions;
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

  void _onSaveEvent(ActionSaveEvent event) {
    if (!mounted) return;
    switch (event) {
      // Said once, not again each time it's tried again by itself.
      case ActionSaveFailed(:final save)
          when save.refused || save.attempts <= 1:
        final name = save.isNew
            ? save.action.name
            : _actions?.actions
                  .where((g) => g.id == save.actionId)
                  .firstOrNull
                  ?.name;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              "Couldn't save ${name ?? 'an action'}. ${save.lastError}"
              "${save.refused ? '' : ' Trying again soon.'}",
            ),
            action: SnackBarAction(
              label: 'Retry',
              onPressed: () => widget.outbox.retry(save.actionId),
            ),
          ),
        );
      case ActionSaveFailed():
        break;
    }
  }

  Future<void> _load() async {
    final fetched = widget.outbox.fetching();
    try {
      final actions = await widget.repository.actions();
      if (!mounted) return;
      widget.outbox.reconcile(actions);
      setState(() {
        // Saves made while these were fetched are still made to them.
        _fromServer = _memory.actions = actions;
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

  /// Moves the action at [oldIndex] of [shown] to [newIndex] (as
  /// ReorderableListView.onReorderItem gives it) among its siblings, shows the new
  /// order at once, and saves it.
  Future<void> _reorder(
    List<PlanAction> shown,
    int oldIndex,
    int newIndex,
  ) async {
    final actions = _fromServer;
    if (actions == null) return;
    final moved = shown[oldIndex];
    final order = [...shown]
      ..removeAt(oldIndex)
      ..insert(newIndex, moved);
    final ids = [
      for (final action in order)
        if (action.parentId == moved.parentId) action.id!,
    ];
    final before = [
      for (final action in shown)
        if (action.parentId == moved.parentId) action.id!,
    ];
    if (ids.join(',') == before.join(',')) return;
    setState(() => _fromServer = _withSiblingOrder(actions, ids));
    final messenger = ScaffoldMessenger.of(context);
    try {
      final saved = await widget.repository.reorderActions(ids);
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

  /// Every action, for the dialogs' action pickers.
  Future<List<PlanAction>> _allActions() async =>
      (await widget.repository.actions()).actions;

  /// Saves [changes] to [action] in the background. Returns the actions as
  /// they're shown now, with them.
  Future<ActionList> _update(
    PlanAction action,
    Map<String, Object?> changes,
  ) async {
    widget.outbox.update(action.id!, changes);
    return _actions!;
  }

  /// Creates an action from [fields] in the background. Returns the actions as
  /// they're shown now, with it.
  Future<ActionList> _create(Map<String, Object?> fields) async {
    widget.outbox.create(fields);
    return _actions!;
  }

  /// Drops the saves that failed for the action shown as [id].
  void _discard(String id) => widget.outbox.discard(id);

  /// The save that failed for the action shown as [id], if one did.
  PendingActionSave? _failed(String? id) =>
      widget.outbox.saves.where((s) => s.actionId == id && s.failed).lastOrNull;

  /// Whether the action shown as [id] is new, and the server hasn't made it
  /// yet: it can't be opened until then.
  bool _unmade(String? id) =>
      widget.outbox.saves.any((s) => s.actionId == id && s.isNew) ||
      // Made by the background task, which didn't say its id.
      widget.outbox.justSaved.any(
        (s) => s.item.actionId == id && s.item.isNew && s.result == null,
      );

  /// Shows [action]'s details to edit; one whose save failed opens with the
  /// changes that weren't saved, to save again.
  Future<void> _open(PlanAction action) async {
    final id = action.id!;
    switch (_failed(id)) {
      case PendingActionSave(isNew: true, :final changes):
        await showNewActionDialog(
          context,
          create: (fields) async {
            widget.outbox.update(id, fields, replace: true);
            return _actions!;
          },
          parentId: changes['parent_id'] as String?,
          fields: changes,
          actions: _allActions,
        );
      case final failed:
        // As the server has it, with what wasn't saved as changes.
        final saved = failed == null
            ? action
            : _fromServer?.actions.where((g) => g.id == id).firstOrNull ??
                  action;
        await showActionDetailsDialog(
          context,
          saved,
          changes: failed?.changes ?? const {},
          // What wasn't saved is among the changes, as they stand now.
          save: failed == null
              ? _update
              : (action, changes) async {
                  widget.outbox.update(id, changes, replace: true);
                  return _actions!;
                },
          confirmSave: (changes) => switch (changes['status']) {
            final String status when status != saved.status => _confirmStatus(
              saved,
              status,
            ),
            _ => Future.value(true),
          },
          actions: _allActions,
        );
    }
  }

  /// Edits [action]'s priority and color, from which "Details" opens the
  /// rest.
  Future<void> _edit(PlanAction action) => showActionDialog(
    context,
    action,
    actions: _actions?.actions ?? const [],
    save: _update,
    onDetails: _open,
  );

  Map<String?, String> get _actionNames => {
    for (final action in _actions?.actions ?? const <PlanAction>[])
      action.id: actionName(action),
  };

  /// The actions and groups a trait's part can count, by id, each by its
  /// path.
  Map<String, String> get _actionChoices => {
    for (final action in _actions?.actions ?? const <PlanAction>[])
      if (action.id != null && action.status != 'deleted')
        action.id!: action.path ?? actionName(action),
  };

  /// Approves [action], one Claude proposed: it becomes active.
  void _approve(PlanAction action) =>
      widget.outbox.update(action.id!, {'status': 'active'});

  Future<void> _add({String? parentId, bool group = false}) async {
    // So the new one can be seen.
    if (parentId != null) setState(() => _expanded.add(parentId));
    await showNewActionDialog(
      context,
      create: _create,
      parentId: parentId,
      group: group,
      actions: _allActions,
    );
  }

  /// Whether to move [action] to [status]: freeing its label, or deleting it,
  /// is worth a second look.
  Future<bool> _confirmStatus(PlanAction action, String status) async {
    final name = actionName(action);
    // Freeing a label, or deleting, is worth a second look.
    final (String, String, String)? check = switch (status) {
      'deleted' => (
        'Delete $name?',
        "Its history is kept, and events that have it keep it, but no event "
            "can be given it again. It's hidden unless you show deleted "
            'actions.',
        'Delete',
      ),
      _ when action.active && !action.isGroup => (
        'Move $name to ${actionStatuses[status]?.toLowerCase()}?',
        "It stops taking up one of the calendar's event labels, and its "
            "events lose its color until it's active again. Its history is "
            'kept.',
        actionStatuses[status] ?? status,
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
    final actions = _actions;
    final ready = actions != null && !_needsSignIn;
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
            memory: _memory,
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
            memory: _memory,
            summary: _summaryView,
            traits: traits,
            onPeople: (_) => setState(() {}),
            actionNames: _actionNames,
            actions: _actionChoices,
            locationNames: _locationNames,
          ),
        ),
        (
          'Locations',
          'where',
          LocationsPane(
            repository: people,
            memory: _memory,
            summary: _summaryView,
            onLocations: (_) => setState(() {}),
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
              (_, true) => _reorderable(actions!),
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
    summary: _actionsSummary(),
    actions: [
      _StatusFilter(
        shown: _shown,
        onChanged: (status, on) =>
            setState(() => on ? _shown.add(status) : _shown.remove(status)),
      ),
      PopupMenuButton<bool>(
        tooltip: 'Add an action or group',
        icon: const Icon(Icons.add),
        enabled: _actions != null,
        onSelected: (group) => _add(group: group),
        itemBuilder: (_) => const [
          PopupMenuItem(value: false, child: Text('New action')),
          PopupMenuItem(value: true, child: Text('New group')),
        ],
      ),
    ],
    child: RefreshIndicator(
      onRefresh: () => Future.wait([_load(), _loadEvents(again: true)]),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(bottom: 24),
        children: _actionTiles(context),
      ),
    ),
  );

  /// The Actions pane's summary: the window's time by the actions shown
  /// (each action's going to the nearest of it and its groups that's
  /// shown), or by priority; null without events, or actions, to show.
  Widget? _actionsSummary() {
    final view = _summaryView;
    final actions = _actions;
    if (view == null || actions == null) return null;
    final tree = _Tree(actions, _shown, _expanded, query: _query);
    final visible = {for (final action in tree.shown) action.id};
    return PlanSummary(
      view: view,
      titles: const ['Visible actions', 'By priority'],
      pages: (events) {
        final (day, week) = actionTime(events, view.window, tree.byId, _shown);
        List<SummarySlice> shares(Map<String?, Duration> time) => planShares(
          byVisible(time, tree.byId, visible),
          none: '',
          noneLabel: 'No action',
          others: 'actions',
          slice: (id, time) => actionSlice(tree.byId[id], id, time),
        );
        return [(shares(day), shares(week)), priorityTime(events, view.window)];
      },
    );
  }

  /// Each action's and group's time in the summaries' window, with what's
  /// in it, through the actions shown, for the 24 hours and 7 days; null
  /// until the window's events are in.
  (Map<String?, Duration>, Map<String?, Duration>)? _timeOnActions(_Tree tree) {
    final view = _summaryView;
    final events = view?.events;
    if (view == null || events == null) return null;
    final (day, week) = actionTime(events, view.window, tree.byId, _shown);
    return (rolledUp(day, tree.byId), rolledUp(week, tree.byId));
  }

  /// The Actions pane's list: the time spent on them, then the tree, or
  /// why it can't be shown.
  List<Widget> _actionTiles(BuildContext context) {
    final actions = _actions;
    if (_error != null && (actions == null || actions.actions.isEmpty)) {
      return [
        StatusMessage(
          icon: Icons.cloud_off,
          text: 'Could not load actions.\n$_error',
        ),
      ];
    }
    if (actions == null) return const [LinearProgressIndicator()];
    final tree = _Tree(actions, _shown, _expanded, query: _query);
    if (tree.all.isEmpty) {
      return const [
        StatusMessage(
          icon: Icons.bolt_outlined,
          text: 'No actions yet.\nTap + to add one.',
        ),
      ];
    }
    final shown = tree.shown;
    final time = _timeOnActions(tree);
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
            Tooltip(
              message:
                  "Each active action takes one of the calendar's event "
                  'labels, as do its own default colors.',
              child: Text(
                '${actions.labelSlotsUsed} of ${actions.labelSlotsTotal} labels '
                'in use',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ],
        ),
      ),
      if (shown.isEmpty)
        searching
            ? NoMatches(query: _query)
            : const StatusMessage(
                icon: Icons.bolt_outlined,
                text: 'No actions with these statuses.',
              ),
      for (final (i, action) in shown.indexed) ...[
        if (i > 0) tree.divider(i),
        _ActionTile(
          action: action,
          ancestors: tree.ancestors[i],
          joined: tree.sharedAbove(i),
          time: switch (time) {
            (final day, final week) => (
              day[action.id] ?? Duration.zero,
              week[action.id] ?? Duration.zero,
            ),
            null => null,
          },
          timeLabels: _summaryView?.window.labels,
          durations: _durations,
          subActions: tree.subActions[action.id] ?? 0,
          // A search shows what's in the groups it finds.
          expanded: searching || _expanded.contains(action.id),
          onToggle: searching
              ? null
              : () => setState(() {
                  if (!_expanded.remove(action.id)) _expanded.add(action.id!);
                }),
          // One the server hasn't made yet has nothing to open, and
          // nothing is reordered under changes still being saved, or
          // around one that couldn't be made.
          saving: _unmade(action.id) && _failed(action.id) == null,
          failed: switch (_failed(action.id)) {
            null => null,
            final save when save.refused => save.lastError,
            final save => '${save.lastError}. Trying again soon',
          },
          onTap: _failed(action.id) != null
              ? () => _open(action)
              : (action.isGroup || (tree.subActions[action.id] ?? 0) > 0) &&
                    !searching
              ? () => setState(() {
                  if (!_expanded.remove(action.id)) _expanded.add(action.id!);
                })
              : () => _edit(action),
          onEdit: () => _edit(action),
          onRetry: () => widget.outbox.retry(action.id!),
          onDiscard: () => _discard(action.id!),
          onLongPress:
              !widget.repository.reorderable ||
                  searching ||
                  widget.outbox.busy ||
                  widget.outbox.saves.any((s) => s.isNew)
              ? null
              : () => setState(() => _reordering = true),
          onAddAction: () => _add(parentId: action.id),
          onAddGroup: () => _add(parentId: action.id, group: true),
          onApprove: action.proposed ? () => _approve(action) : null,
        ),
      ],
    ];
  }

  /// The actions shown, to drag into a new order among their siblings.
  Widget _reorderable(ActionList actions) {
    final tree = _Tree(actions, _shown, _expanded);
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
          _ActionTile(
            action: shown[i],
            ancestors: tree.ancestors[i],
            joined: tree.sharedAbove(i),
            subActions: tree.subActions[shown[i].id] ?? 0,
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
    ActionList actions,
    Set<String> statuses,
    Set<String> expanded, {
    String query = '',
  }) {
    all = actions.actions;
    byId = {for (final action in all) action.id: action};
    final withStatus = [
      for (final action in all)
        if (statuses.contains(action.status)) action,
    ];
    for (final action in withStatus) {
      subActions.update(action.parentId, (n) => n + 1, ifAbsent: () => 1);
    }
    // One is hidden under any collapsed ancestor that's shown. One whose
    // parent's status is filtered out still shows, where it always has.
    bool underCollapsed(PlanAction action) {
      for (
        var parent = byId[action.parentId];
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
        for (final action in withStatus)
          if (!underCollapsed(action)) action,
      ];
    } else {
      // What matches, and every group above it.
      final found = <String?>{};
      for (final action in withStatus) {
        final texts = [
          action.name,
          action.path,
          action.properties['note'] as String?,
        ];
        if (!matchesSearch(query, texts)) continue;
        found.add(action.id);
        for (
          var parent = byId[action.parentId];
          parent != null && found.add(parent.id);
          parent = byId[parent.parentId]
        ) {}
      }
      shown = [
        for (final action in withStatus)
          if (found.contains(action.id)) action,
      ];
      subActions.clear();
      for (final action in shown) {
        subActions.update(action.parentId, (n) => n + 1, ifAbsent: () => 1);
      }
    }
    List<PlanAction> ancestorsOf(PlanAction action) {
      final chain = <PlanAction>[];
      for (
        var parent = byId[action.parentId];
        parent != null && !chain.contains(parent);
        parent = byId[parent.parentId]
      ) {
        chain.insert(0, parent);
      }
      return chain;
    }

    ancestors = [for (final action in shown) ancestorsOf(action)];
  }

  late final List<PlanAction> all;
  late final Map<String?, PlanAction> byId;

  /// How many of each one's children are shown, or could be.
  final subActions = <String?, int>{};
  late final List<PlanAction> shown;
  late final List<List<PlanAction>> ancestors;

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
      Divider(height: 1, indent: sharedAbove(i) * actionBandWidth);
}

/// The Actions pane's filter: a drop-down of every status, each with a check
/// box, which stays open while they're ticked. A dot on its icon says
/// it's showing something other than [defaultActionStatuses].
class _StatusFilter extends StatelessWidget {
  const _StatusFilter({required this.shown, required this.onChanged});

  final Set<String> shown;
  final void Function(String status, bool on) onChanged;

  @override
  Widget build(BuildContext context) {
    final changed =
        shown.length != defaultActionStatuses.length ||
        !shown.containsAll(defaultActionStatuses);
    return MenuAnchor(
      menuChildren: [
        for (final MapEntry(key: status, value: label)
            in actionStatuses.entries)
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
// Named from when actions were goals: kept, so the choices stay.
const _durationsKey = 'goal_time_durations';

/// Where whether the time summary is folded away is kept.
const _timeSummaryCollapsedKey = 'goal_time_summary_collapsed';

/// How wide each action's band is, down the left of the Actions page: also
/// how far each level of sub-actions is indented, its band beside its
/// parent's.
const actionBandWidth = 6.0;

/// How long each dash of a dashed band is, and each gap between.
const _dash = 5.0;

/// How far an action's band juts out to say it has sub-actions: as an arrow,
/// collapsed. (Expanded, it widens down over its sub-actions' bands.)
const _bandTip = 8.0;

class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.action,
    this.ancestors = const [],
    this.joined = 0,
    this.time,
    this.timeLabels,
    this.durations = true,
    required this.subActions,
    required this.expanded,
    required this.onToggle,
    required this.onTap,
    this.onLongPress,
    this.dragIndex,
    this.onAddAction,
    this.onAddGroup,
    this.onApprove,
    this.onEdit,
    this.saving = false,
    this.failed,
    this.onRetry,
    this.onDiscard,
  });

  final PlanAction action;

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
  final List<PlanAction> ancestors;

  /// How many of [ancestors]' bands it shares with the row above, which
  /// run on up over the divider between them.
  final int joined;

  /// Its time, with what's in it, in the summaries' 24 hours and 7 days;
  /// null if it isn't known.
  final (Duration, Duration)? time;

  /// The labels of those windows, as the summaries have them: "24h" and
  /// "7d", or looking on, "+24h" and "+7d".
  final (String, String)? timeLabels;

  /// Whether its time is in durations, rather than percentages.
  final bool durations;

  /// How many sub-actions it has (of those shown); none, and it has no arrow.
  final int subActions;

  /// Whether its sub-actions are shown.
  final bool expanded;

  /// Shows or hides what's in it, for a group. Null while a search shows
  /// everything found in it.
  final VoidCallback? onToggle;

  /// Tapping it: a group's opens or closes it; an action's edits it.
  final VoidCallback? onTap;

  /// Edits its priority and color: "Edit" in its menu.
  final VoidCallback? onEdit;
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
    final faded = action.active ? null : TextStyle(color: theme.hintColor);
    final details = [
      if (action.proposed)
        'Proposed by Claude: review it'
      else if (!action.active)
        actionStatuses[action.status] ?? action.status,
      if (action.isGroup && subActions == 0) 'Empty group',
    ].nonNulls.join(' · ');
    final shown = switch (time) {
      (final day, final week) => describeTime(
        day.inMinutes,
        week.inMinutes,
        skipZero: true,
        asPercent: !durations,
        windows: timeLabels ?? ('24h', '7d'),
      ),
      null => null,
    };
    // Its own priority, filled; else the one it inherits, outlined. Only
    // an active action's events take one.
    final priority = action.active ? action.effectivePriority : null;
    final bands = [
      for (final action in [...ancestors, action]) _bandOf(context, action),
    ];
    final listTile = ListTile(
      contentPadding: const EdgeInsetsDirectional.only(start: 8, end: 4),
      // Its priority after its name, as the Events page puts it after an
      // event's summary.
      title: Text.rich(
        TextSpan(
          text: actionName(action),
          children: [
            if (priority != null) ...[
              const TextSpan(text: ' '),
              WidgetSpan(
                alignment: PlaceholderAlignment.middle,
                child: PriorityChip(
                  priority: priority,
                  own: action.priority != null,
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
                message: 'Drag to move ${actionName(action)}',
                child: const Padding(
                  padding: EdgeInsets.all(12),
                  child: Icon(Icons.drag_handle),
                ),
              ),
            )
          else
            PopupMenuButton<String>(
              tooltip: 'More for ${actionName(action)}',
              onSelected: (choice) => switch (choice) {
                'approve' => onApprove?.call(),
                'action' => onAddAction?.call(),
                'group' => onAddGroup?.call(),
                _ => onEdit?.call(),
              },
              itemBuilder: (context) => [
                if (onApprove != null)
                  const PopupMenuItem(value: 'approve', child: Text('Approve')),
                if (action.isGroup) ...[
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
    final parent = subActions > 0;
    final bandsWidth = actionBandWidth * bands.length + _bandTip;
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
              child: ActionBands(
                bands: bands,
                joined: joined,
                shape: !parent
                    ? ActionBandShape.plain
                    : expanded
                    ? ActionBandShape.expanded
                    : ActionBandShape.collapsed,
              ),
            ),
          ),
        ],
      ),
    );
    return tile;
  }

  /// [action]'s band: its own color, solid, or the one it inherits, dashed.
  /// Only an active action's is in color.
  static ActionBand _bandOf(BuildContext context, PlanAction action) {
    final own = parseColor(action.backgroundColor);
    final color = action.active
        ? own ?? parseColor(action.effectiveColor)
        : null;
    return ActionBand(
      color: color ?? Theme.of(context).colorScheme.outlineVariant,
      dashed: own == null || !action.active,
    );
  }
}

/// One action's band: its color, and whether it's dashed, for one inherited.
class ActionBand {
  const ActionBand({required this.color, required this.dashed});

  final Color color;
  final bool dashed;

  @override
  bool operator ==(Object other) =>
      other is ActionBand && other.color == color && other.dashed == dashed;

  @override
  int get hashCode => Object.hash(color, dashed);
}

/// How an action's own band ends: plainly, with no sub-actions; as an arrow
/// pointing right, its sub-actions hidden; or slanting down to them, shown.
enum ActionBandShape { plain, collapsed, expanded }

/// An action's [bands] side by side down the left of its row: its
/// ancestors', then its own, shaped as [shape] says. The first [joined]
/// run on up over the divider above, which they share with the row there.
///
/// Dashes are laid out from the top of the list, not of the row, so a
/// dashed band runs evenly down every row it's in.
class ActionBands extends LeafRenderObjectWidget {
  const ActionBands({
    super.key,
    required this.bands,
    required this.shape,
    required this.joined,
  });

  final List<ActionBand> bands;
  final ActionBandShape shape;
  final int joined;

  @override
  RenderActionBands createRenderObject(BuildContext context) =>
      RenderActionBands(
        bands: bands,
        shape: shape,
        joined: joined,
        scroll: Scrollable.maybeOf(context)?.position,
      );

  @override
  void updateRenderObject(
    BuildContext context,
    RenderActionBands renderObject,
  ) => renderObject
    ..bands = bands
    ..shape = shape
    ..joined = joined
    ..scroll = Scrollable.maybeOf(context)?.position
    // Rows above may have grown or shrunk, moving this one without
    // repainting it, which would leave its dashes out of step.
    ..markNeedsPaint();
}

/// Lays out and paints [ActionBands].
class RenderActionBands extends RenderBox {
  RenderActionBands({
    required this._bands,
    required this._shape,
    required this._joined,
    required this.scroll,
  });

  /// The list's scrolling, to find where in the list the row is.
  ScrollPosition? scroll;

  List<ActionBand> _bands;
  set bands(List<ActionBand> value) {
    if (listEquals(value, _bands)) return;
    _bands = value;
    markNeedsPaint();
  }

  ActionBandShape _shape;
  set shape(ActionBandShape value) {
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
      final x0 = actionBandWidth * i;
      final x1 = x0 + actionBandWidth;
      // Over the divider above, if it's shared with the row there.
      final y0 = i < _joined ? -1.0 : 0.0;
      final paint = Paint()..color = band.color;
      final shape = i == _bands.length - 1 ? _shape : ActionBandShape.plain;
      if (band.dashed) {
        dashes(paint, i, x0, x1, y0);
      } else {
        canvas.drawRect(Rect.fromLTRB(x0, y0, x1, h), paint);
      }
      switch (shape) {
        case ActionBandShape.plain:
          break;
        case ActionBandShape.collapsed:
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
        case ActionBandShape.expanded:
          // Widening down over where its sub-actions' bands start, dashed as
          // the next band's would be.
          final slant = Path()
            ..moveTo(x1, 0)
            ..lineTo(x1 + actionBandWidth, h)
            ..lineTo(x1, h)
            ..close();
          if (!band.dashed) {
            canvas.drawPath(slant, paint);
          } else {
            canvas.save();
            canvas.clipPath(slant);
            dashes(paint, i + 1, x1, x1 + actionBandWidth, 0);
            canvas.restore();
          }
      }
    }
    canvas.restore();
  }
}

/// [actions] with [saved], saves the server has answered, made to them, as
/// far as they don't have them yet: each new action added, with the id the
/// server gave it if that's known, and each action's changes made.
ActionList _withSaved(
  ActionList actions,
  List<({PendingActionSave item, String? result})> saved,
) {
  var shown = actions;
  for (final (:item, :result) in saved) {
    if (!item.isNew) {
      shown = _withChanged(shown, item.actionId, item.changes);
    } else if (item.madeIn(shown) == null &&
        !shown.actions.any((g) => result != null && g.id == result)) {
      shown = _inTree(shown, [
        ...shown.actions,
        PlanAction.fromJson({
          ...item.action.toJson(),
          'id': result ?? item.actionId,
        }),
      ]);
    }
  }
  return shown;
}

/// [actions] with [saves] made to them, oldest first: each new action added,
/// and each action's changes made.
ActionList _withSaves(ActionList actions, List<PendingActionSave> saves) {
  if (saves.isEmpty) return actions;
  var shown = actions;
  for (final save in saves) {
    shown = save.isNew
        ? _inTree(shown, [...shown.actions, save.action])
        : _withChanged(shown, save.actionId, save.changes);
  }
  return shown;
}

/// [actions] with [changes], keyed as `update_action` takes them, made to the
/// action with [id]: moved, if it's given another parent, and renamed in
/// its sub-actions' paths.
ActionList _withChanged(
  ActionList actions,
  String? id,
  Map<String, Object?> changes,
) => _inTree(actions, [
  for (final action in actions.actions)
    action.id == id
        ? PlanAction.fromJson({...action.toJson(), ...changes})
        : action,
]);

/// [actions] in place of [list]'s, parents first, each action's sub-actions
/// after it in the order given, and each path made again from its
/// ancestors' names, and the priority each inherits from them.
ActionList _inTree(ActionList list, List<PlanAction> actions) {
  final ids = {for (final action in actions) action.id};
  final children = <String?, List<PlanAction>>{};
  for (final action in actions) {
    final parent = ids.contains(action.parentId) ? action.parentId : null;
    children.putIfAbsent(parent, () => []).add(action);
  }
  final ordered = <PlanAction>[];
  void visit(PlanAction action, PlanAction? parent, String? parentPath) {
    final path = switch ((parentPath, action.parentId)) {
      (final parent?, _) => '$parent › ${actionName(action)}',
      (null, null) => actionName(action),
      // Under an action that isn't listed: only its own name can be redone.
      _ => switch (action.path?.lastIndexOf(' › ')) {
        final end? when end >= 0 =>
          '${action.path!.substring(0, end)} › ${actionName(action)}',
        _ => actionName(action),
      },
    };
    // Under an action that isn't listed, what it inherits is as it was.
    final priority =
        action.priority ??
        (parent != null
            ? parent.effectivePriority
            : action.parentId == null
            ? null
            : action.effectivePriority);
    final shown = path == action.path && priority == action.effectivePriority
        ? action
        : PlanAction.fromJson({
            ...action.toJson(),
            'path': path,
            'effective_priority': priority,
          });
    ordered.add(shown);
    for (final child in children[action.id] ?? const <PlanAction>[]) {
      visit(child, shown, path);
    }
  }

  children[null]?.forEach((action) => visit(action, null, null));
  return ActionList(
    actions: ordered,
    labelSlotsUsed: list.labelSlotsUsed,
    labelSlotsTotal: list.labelSlotsTotal,
  );
}

/// [actions] with the siblings [ids] (sharing a parent) put in that order
/// among the places they hold, and the list rebuilt parents first, each
/// action's sub-actions after it, as the server lists them.
ActionList _withSiblingOrder(ActionList actions, List<String> ids) {
  final byId = {for (final action in actions.actions) action.id: action};
  final children = <String?, List<PlanAction>>{};
  for (final action in actions.actions) {
    final parent = byId.containsKey(action.parentId) ? action.parentId : null;
    children.putIfAbsent(parent, () => []).add(action);
  }
  final siblings = children[byId[ids.first]?.parentId] ?? [];
  final places = [
    for (final (i, action) in siblings.indexed)
      if (ids.contains(action.id)) i,
  ];
  for (var i = 0; i < places.length && i < ids.length; i++) {
    siblings[places[i]] = byId[ids[i]]!;
  }
  final ordered = <PlanAction>[];
  void visit(PlanAction action) {
    ordered.add(action);
    children[action.id]?.forEach(visit);
  }

  children[null]?.forEach(visit);
  return ActionList(
    actions: ordered,
    labelSlotsUsed: actions.labelSlotsUsed,
    labelSlotsTotal: actions.labelSlotsTotal,
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
  (String, String) windows = ('24h', '7d'),
}) {
  String? part(int minutes, String window, int windowMinutes) {
    if (skipZero && minutes == 0) return null;
    return asPercent
        ? '${_percent(minutes, windowMinutes)} of $window'
        : '${formatMinutes(minutes)} in $window';
  }

  final parts = [
    part(day, windows.$1, 24 * 60),
    part(week, windows.$2, 7 * 24 * 60),
  ].nonNulls;
  return parts.isEmpty ? null : parts.join(' · ');
}

/// [minutes] as a share of [of] to a tenth: "37.5%", "6%", "<0.1%".
String _percent(int minutes, int of) {
  final percent = (minutes * 100 / of).toStringAsFixed(1);
  if (minutes > 0 && percent == '0.0') return '<0.1%';
  return '${percent.endsWith('.0') ? percent.substring(0, percent.length - 2) : percent}%';
}
