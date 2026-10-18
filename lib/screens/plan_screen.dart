import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/plan_action.dart';
import '../models/person.dart';
import '../models/event.dart';
import '../models/time_split.dart';
import '../outbox/action_writes.dart';
import '../outbox/actions_shown.dart';
import '../services/event_store.dart';
import '../services/events_repository.dart';
import '../services/goals_repository.dart';
import '../services/habits_repository.dart';
import '../services/actions_repository.dart';
import '../services/mcp_client.dart';
import '../services/notes_repository.dart';
import '../services/people_repository.dart';
import '../services/plan_memory.dart';
import '../services/traits_repository.dart';
import 'goals_pane.dart';
import 'locations_pane.dart';
import 'people_pane.dart';
import 'habits_pane.dart';
import '../widgets/action_icon.dart';
import '../widgets/error_sheet.dart';
import '../widgets/load_status.dart';
import '../widgets/action_dialog.dart';
import '../widgets/app_menu.dart';
import '../widgets/color_picker.dart';
import '../widgets/durations.dart';
import '../widgets/priority_chip.dart';
import '../widgets/priority_colors_dialog.dart';
import '../widgets/hotkeys.dart';
import '../widgets/plan_pane.dart';
import '../widgets/plan_summaries.dart';
import '../widgets/time_summary.dart';
import '../widgets/refreshing_bar.dart';
import '../widgets/status_message.dart';
import '../widgets/tree_tile.dart';
import '../services/client_health.dart';
import '../services/work_timing.dart';

/// The Plan page: panes to swipe between, or pick from the tabs at the
/// top, each with a search of its own --
///
/// * **Goals**, what to aim for, leftmost ([GoalsPane]), from the
///   [GoalsScope];
/// * **Actions**, what to do: the actions, kept as actions, and the
///   groups they're in, as a tree;
/// * **Habits**, what to practice ([HabitsPane]), from the [HabitsScope];
/// * **People**, who to be with, Self always among them, with the traits
///   -- how to be -- under them ([PeoplePane]), from the [PeopleScope]
///   and the [TraitsScope];
/// * **Locations**, where ([LocationsPane]), from the [PeopleScope].
///
/// Landing on it loads everything at once, every pane's and the
/// summaries', starting from what [memory] kept from the last visit, or
/// else the repositories kept from the app's last run, so nothing shows
/// empty while it loads.
///
/// The Actions, Habits, People and Locations panes each have a summary, above
/// their search, of the time in its window -- the 24 hours and 7 days
/// before, or after, the last compaction, or a day at a time from it --
/// worked out from the events in it ([eventsRepository]); one window for
/// all four. The Actions pane's splits the time by the actions shown, or
/// by priority. Under it, each action and group: its color, name,
/// status, priority (as a chip, like the Events page's) and the time on
/// it in the window, with what's in a group indented under it. Tapping a
/// group or an action, or "Edit" in its menu, opens it ready to edit
/// ([showActionDialog]): its name, group, status, priority, color and
/// note. Searching shows the actions and groups
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
    this.loads,
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
  final ActionWrites outbox;

  /// Which server this build talks to, for the About dialog.
  final String serverLabel;

  /// Runs the interactive sign-in; null when the backend needs none.
  final Future<void> Function()? onSignIn;
  final Future<void> Function()? onSignOut;

  /// The app's version, for the About dialog; null until it's known.
  final String? version;

  /// How loading the actions is going, for the status bar: the app's,
  /// or else one of the page's own.
  final LoadStatus? loads;

  @override
  State<PlanScreen> createState() => _PlanScreenState();
}

class _PlanScreenState extends State<PlanScreen> {
  /// The actions as the server last listed them.
  ActionList? get _fromServer => _server;
  set _fromServer(ActionList? actions) {
    _server = actions;
    _shownActions = null;
  }

  ActionList? _server;

  /// The actions shown: [_fromServer], with the saves made since it was
  /// fetched, here or by the background task, then those waiting in the
  /// outbox, or that failed, made to them. Worked out again only when
  /// they or the outbox change.
  ActionList? get _actions => switch (_fromServer) {
    final actions? => _shownActions ??= actionsShown(actions, widget.outbox),
    null => null,
  };
  ActionList? _shownActions;

  /// [_fromServer] are the ones kept from last time; the server hasn't
  /// answered since.
  bool _stale = false;
  bool _needsSignIn = false;

  /// How loading the actions is going: a failure is tried again by itself.
  late final LoadStatus _loads = widget.loads ?? LoadStatus('actions');
  Object? get _error => _loads.error;
  bool _signingIn = false;

  /// The panes besides Actions, for the refresh button to refresh.
  final _habitsPane = GlobalKey<HabitsPaneState>();
  final _peoplePane = GlobalKey<PeoplePaneState>();
  final _locationsPane = GlobalKey<LocationsPaneState>();
  final _goalsPane = GlobalKey<GoalsPaneState>();

  /// The statuses shown.
  final _shown = {...defaultActionStatuses};

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

  /// This visit, timed till everything's loaded.
  final _visit = PlanVisitTimer.start();

  /// The loads this visit waits on, before it's done.
  final _visitLoads = <Future<void>>[];

  @override
  void initState() {
    super.initState();
    PlanVisitTimer.open++;
    _memory.newVisit();
    // On its own, without the app's: the summaries' events go in one of
    // its own.
    if (widget.eventsRepository case final events?) {
      _memory.useEvents(EventStore(repository: events));
    }
    _fromServer = _memory.actions;
    widget.outbox.addListener(_outboxChanged);
    _loads.bind(_load);
    _showCached();
    _visitLoads
      ..add(_load())
      ..add(_loadCompaction());
    _loadDurations();
    _loadTimeSummaryCollapsed();
  }

  /// Ends the visit's timing once its loads are in, and the frame they
  /// make is drawn.
  Future<void> _timeVisit() async {
    await Future.wait(_visitLoads.map((l) => l.catchError((Object _) {})));
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) => _visit.finish());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_prefetched) {
      _prefetched = true;
      _visitLoads.add(_prefetch());
      _timeVisit();
    }
  }

  /// Loads every pane's data at once, from what was kept from the app's
  /// last run, then the server, so each is ready when it's swiped to.
  /// Best effort: each pane says why, if its load failed.
  Future<void> _prefetch() async {
    final traits = TraitsScope.of(context);
    final people = PeopleScope.of(context);
    final habits = HabitsScope.of(context);
    final goals = GoalsScope.of(context);
    // On its own, without the home screen to load the events the traits
    // are scored from as the app opens: loads them here.
    if (!_memory.warmed && widget.eventsRepository != null) {
      unawaited(
        _memory.warmScores(
          traits: traits,
          people: people,
          actions: widget.repository,
          habits: habits,
        ),
      );
    }
    await _memory.loadKept(
      traits: traits,
      people: people,
      habits: habits,
      goals: goals,
    );
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
      quietly(habits == null ? null : _memory.loadHabits(habits)),
      quietly(goals == null ? null : _memory.loadGoals(goals)),
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
    for (final node in _paneFocus.values) {
      node.dispose();
    }
    PlanVisitTimer.open--;
    // Left before everything loaded: as far as it got.
    _visit.finish();
    widget.outbox.removeListener(_outboxChanged);
    _loads.unbind();
    if (widget.loads == null) _loads.dispose();
    super.dispose();
  }

  void _outboxChanged() {
    if (!mounted) return;
    _shownActions = null;
    // Once, after the last of a round is answered, rather than after each.
    if (widget.outbox.wantsFetch) _load();
    setState(() {});
  }

  Future<void> _load() async {
    final fetched = widget.outbox.fetching();
    try {
      final actions = await widget.repository.actions();
      if (!mounted) return;
      _loads.loaded();
      setState(() {
        // Saves made while these were fetched are still made to them.
        _fromServer = _memory.actions = actions;
        _stale = false;
        _needsSignIn = false;
      });
      fetched();
    } on SignInRequiredException {
      if (!mounted) return;
      _loads.reset();
      setState(() {
        _fromServer = null;
        _stale = false;
        _needsSignIn = true;
      });
    } catch (e) {
      if (!mounted) return;
      // Tried again by itself; with actions shown, the status bar says so.
      _loads.failed(e, hasData: _fromServer?.actions.isNotEmpty ?? false);
      setState(() {
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
    final saved = await runOrShowError(
      context,
      title: "Couldn't save the new order",
      action: () async {
        final saved = await widget.repository.reorderActions(ids);
        if (mounted) setState(() => _fromServer = saved);
      },
    );
    // Put back as it was.
    if (!saved) await _load();
  }

  /// Shows each priority's color, to change; reloads the actions after a
  /// change, since those that take their priority's color change with it.
  Future<void> _editPriorityColors() async {
    var changed = false;
    await showDialog<void>(
      context: context,
      builder: (_) => PriorityColorsDialog(
        onSave: (priority, color) async {
          await widget.repository.updatePriorityColor(priority, color);
          changed = true;
        },
      ),
    );
    if (changed && mounted) {
      setState(() {}); // The new colors, at once.
      await _load();
    }
  }

  /// Every action, for the dialogs' action pickers: those shown, with
  /// what's still being saved, or else the server's.
  Future<List<PlanAction>> _allActions() async {
    if (_actions case final shown?) return shown.actions;
    await _memory.loadActions(widget.repository);
    return _memory.actions?.actions ?? const [];
  }

  /// Saves [changes] to [action] in the background. Returns the actions as
  /// they're shown now, with them.
  Future<ActionList> _update(
    PlanAction action,
    Map<String, Object?> changes,
  ) async {
    widget.outbox.update(action.id!, changes, group: action.isGroup);
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
  ActionSave? _failed(String? id) =>
      widget.outbox.saves.where((s) => s.actionId == id && s.failed).lastOrNull;

  /// Whether the action shown as [id] is new, and the server hasn't made it
  /// yet: it can't be opened until then.
  bool _unmade(String? id) =>
      widget.outbox.saves.any((s) => s.actionId == id && s.isNew);

  /// Edits [action]; one whose save failed opens with the changes that
  /// weren't saved, to save again.
  Future<void> _open(PlanAction action) async {
    final id = action.id!;
    final actions = await _allActions();
    if (!mounted) return;
    switch (_failed(id)) {
      case ActionSave(isNew: true, :final changes):
        await showNewActionDialog(
          context,
          create: (fields) async {
            widget.outbox.update(id, fields, group: false, replace: true);
            return _actions!;
          },
          parentId: changes['parent_id'] as String?,
          fields: changes,
          actions: actions,
        );
      case final failed:
        // As the server has it, with what wasn't saved as changes.
        final saved = failed == null
            ? action
            : _fromServer?.actions.where((g) => g.id == id).firstOrNull ??
                  action;
        await showActionDialog(
          context,
          saved,
          changes: failed?.changes ?? const {},
          // What wasn't saved is among the changes, as they stand now.
          save: failed == null
              ? _update
              : (action, changes) async {
                  widget.outbox.update(
                    id,
                    changes,
                    group: saved.isGroup,
                    replace: true,
                  );
                  return _actions!;
                },
          confirmSave: (changes) => switch (changes['status']) {
            final String status when status != saved.status => _confirmStatus(
              saved,
              status,
            ),
            _ => Future.value(true),
          },
          actions: actions,
        );
    }
  }

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
  void _approve(PlanAction action) => widget.outbox.update(action.id!, {
    'status': 'active',
  }, group: action.isGroup);

  Future<void> _add({String? parentId, bool group = false}) async {
    final actions = await _allActions();
    if (!mounted) return;
    await showNewActionDialog(
      context,
      create: _create,
      parentId: parentId,
      group: group,
      actions: actions,
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
    setState(() => _signingIn = true);
    Object? error;
    try {
      await widget.onSignIn!();
      unawaited(widget.outbox.retryNow());
      await _load();
    } catch (e) {
      error = e;
    } finally {
      if (mounted) setState(() => _signingIn = false);
    }
    if (error != null && mounted) {
      await showErrorSheet(
        context,
        title: "Couldn't sign in",
        error: error,
        onRetry: _signIn,
      );
    }
  }

  Future<void> _signOut() async {
    await widget.onSignOut!();
    await _load();
  }

  @override
  Widget build(BuildContext context) =>
      timed(WorkKind.planRebuild, () => _build(context));

  /// Each pane's, by its title: what J and K go down and up.
  final _paneFocus = <String, FocusNode>{};

  FocusNode _paneNode(String title) => _paneFocus.putIfAbsent(
    title,
    () => FocusNode(
      debugLabel: '$title pane',
      canRequestFocus: false,
      skipTraversal: true,
    ),
  );

  /// J or K: the next item in the pane shown, [later] down it or up
  /// ([stepItems]); Enter taps it.
  void _stepInPane(FocusNode pane, {required bool later}) =>
      stepItems(pane, later: later);

  /// The Plan page's hotkeys, with the [panes] shown in [tabs]: J and K
  /// down and up the one shown, H and L to the one beside it.
  List<HotkeyBinding> _paneKeys(TabController tabs, List<String> panes) {
    void step(bool later) =>
        _stepInPane(_paneNode(panes[tabs.index]), later: later);
    void go(int by) =>
        tabs.animateTo((tabs.index + by).clamp(0, tabs.length - 1));
    return [
      HotkeyBinding(
        const HotkeyTrigger.key(LogicalKeyboardKey.keyJ),
        () => step(true),
      ),
      HotkeyBinding(
        const HotkeyTrigger.key(LogicalKeyboardKey.keyK),
        () => step(false),
      ),
      HotkeyBinding(
        const HotkeyTrigger.key(LogicalKeyboardKey.keyH),
        () => go(-1),
      ),
      HotkeyBinding(
        const HotkeyTrigger.key(LogicalKeyboardKey.keyL),
        () => go(1),
      ),
    ];
  }

  Widget _build(BuildContext context) {
    final actions = _actions;
    final ready = actions != null && !_needsSignIn;
    final reordering = _reordering && ready;
    final traits = TraitsScope.of(context);
    final people = PeopleScope.of(context);
    final habits = HabitsScope.of(context);
    final goals = GoalsScope.of(context);
    final personNames = {
      for (final person in _people?.withSelf ?? const [defaultSelf])
        person.id: personName(person),
    };
    // Goals first: what the rest is for.
    final panes = <(String, String, Widget)>[
      if (goals != null)
        (
          'Goals',
          'aim',
          GoalsPane(
            key: _goalsPane,
            repository: goals,
            memory: _memory,
            summary: _summaryView,
          ),
        ),
      // Built only while it's shown: what it works out is costly.
      ('Actions', 'do', Builder(builder: _actionsPane)),
      if (habits != null)
        (
          'Habits',
          'build',
          HabitsPane(
            key: _habitsPane,
            repository: habits,
            memory: _memory,
            summary: _summaryView,
            actions: _actions?.actions ?? const [],
            personNames: personNames,
            locationNames: _locationNames,
          ),
        ),
      if (people != null) ...[
        (
          'People',
          'who',
          PeoplePane(
            key: _peoplePane,
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
            key: _locationsPane,
            repository: people,
            actions: widget.repository,
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
                    Builder(
                      builder: (context) => AppMenu(
                        serverLabel: widget.serverLabel,
                        version: widget.version,
                        onSignOut: widget.onSignOut == null || _needsSignIn
                            ? null
                            : _signOut,
                        onRefresh: _needsSignIn
                            ? null
                            : () => _refreshPane(
                                panes[DefaultTabController.of(context).index]
                                    .$1,
                              ),
                      ),
                    ),
                  ],
            bottom: reordering || _needsSignIn || panes.length < 2
                ? null
                : TabBar(
                    // Narrow enough for every pane's tab on a phone.
                    labelPadding: const EdgeInsets.symmetric(horizontal: 4),
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
              _ => Builder(
                builder: (context) => HotkeyBindings(
                  bindings: _paneKeys(DefaultTabController.of(context), [
                    for (final (title, _, _) in panes) title,
                  ]),
                  child: panes.length == 1
                      ? Focus(
                          focusNode: _paneNode(panes.single.$1),
                          child: panes.single.$3,
                        )
                      : TabBarView(
                          children: [
                            for (final (title, _, pane) in panes)
                              Focus(focusNode: _paneNode(title), child: pane),
                          ],
                        ),
                ),
              ),
            },
          ),
        ),
      ),
    );
  }

  /// The refresh button: the pane shown refreshed, as pulling it down does.
  Future<void> _refreshPane(String title) async {
    await switch (title) {
      'Habits' => _habitsPane.currentState?.reload(),
      'People' => _peoplePane.currentState?.reload(),
      'Locations' => _locationsPane.currentState?.reload(),
      'Goals' => _goalsPane.currentState?.reload(),
      _ => Future.wait([_load(), _loadEvents(again: true)]),
    };
  }

  Widget _signInPrompt() => FillViewport(
    child: StatusMessage(
      icon: Icons.lock_outline,
      text: 'Sign in to see your plan.',
      action: widget.onSignIn == null
          ? null
          : SignInButton(signingIn: _signingIn, onPressed: _signIn),
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
      NewHotkey(
        child: PopupMenuButton<bool>(
          tooltip: 'Add an action or group',
          icon: const Icon(Icons.add),
          enabled: _actions != null,
          onSelected: (group) => _add(group: group),
          itemBuilder: (_) => const [
            PopupMenuItem(value: false, child: Text('New action')),
            PopupMenuItem(value: true, child: Text('New group')),
          ],
        ),
      ),
    ],
    child: RefreshIndicator(
      onRefresh: () => _refreshPane('Actions'),
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
    final tree = _Tree(actions, _shown, query: _query);
    final visible = {for (final action in tree.shown) action.id};
    return PlanSummary(
      view: view,
      titles: const ['By action', 'By priority'],
      pages: (events) {
        final (day, week) = _actionTime(events, view.window, tree);
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
    final (day, week) = _actionTime(events, view.window, tree);
    return (rolledUp(day, tree.byId), rolledUp(week, tree.byId));
  }

  /// [events]' time on each action in [window], by [actionTime]: split
  /// again only when the window, the events, the actions or the statuses
  /// shown change -- not for the summary and the tiles each, nor for each
  /// rebuild.
  (Map<String?, Duration>, Map<String?, Duration>) _actionTime(
    List<Event> events,
    SummaryWindow window,
    _Tree tree,
  ) {
    final key = (
      window,
      _memory.eventStore?.version,
      events.length,
      _actions,
      (_shown.toList()..sort()).join(','),
    );
    if (_actionTimeKept case (final kept, final time) when kept == key) {
      return time;
    }
    final time = actionTime(events, window, tree.byId, _shown);
    _actionTimeKept = (key, time);
    return time;
  }

  (
    (SummaryWindow, int?, int, ActionList?, String),
    (Map<String?, Duration>, Map<String?, Duration>),
  )?
  _actionTimeKept;

  /// The Actions pane's list: the time spent on them, then the tree, or
  /// why it can't be shown.
  List<Widget> _actionTiles(BuildContext context) {
    final actions = _actions;
    if (_error != null && (actions == null || actions.actions.isEmpty)) {
      return [
        LoadError(
          what: 'actions',
          error: _error!,
          retryingAt: _loads.nextAttemptAt,
          onRetry: _load,
        ),
      ];
    }
    if (actions == null) return const [LinearProgressIndicator()];
    final tree = _Tree(actions, _shown, query: _query);
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
      // Over the actions, not one: J and K pass it by.
      NotAnItem(
        child: Padding(
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
              InkWell(
                onTap: _editPriorityColors,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final p in priorities)
                      Padding(
                        padding: const EdgeInsets.only(right: 2),
                        child: ColorDot(color: priorityColor(p), size: 10),
                      ),
                    const SizedBox(width: 4),
                    Text(
                      'Priority colors',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      if (shown.isEmpty)
        searching
            ? NoMatches(query: _query)
            : const StatusMessage(
                icon: Icons.bolt_outlined,
                text: 'No actions with these statuses.',
              ),
      for (var i = 0; i < shown.length; i++)
        _tile(tree, i, time: time, searching: searching),
    ];
  }

  /// The [i]th action [tree] shows, as its row: the row built for it
  /// before, if nothing it shows has changed since -- then it isn't built
  /// again.
  Widget _tile(
    _Tree tree,
    int i, {
    required (Map<String?, Duration>, Map<String?, Duration>)? time,
    required bool searching,
  }) {
    final action = tree.shown[i];
    final id = action.id;
    final save = _failed(id);
    final failed = switch (save) {
      null => null,
      final save when save.refused => save.lastError,
      final save => '${save.lastError}. Trying again soon',
    };
    // One the server hasn't made yet has nothing to open, and nothing is
    // reordered under changes still being saved, or around one that
    // couldn't be made.
    final saving = _unmade(id) && save == null;
    final reorderable =
        widget.repository.reorderable &&
        !searching &&
        !widget.outbox.busy &&
        !widget.outbox.saves.any((s) => s.isNew);
    final subActions = tree.subActions[id] ?? 0;
    final ancestors = tree.ancestors[i];
    final itsTime = switch (time) {
      (final day, final week) => (
        day[id] ?? Duration.zero,
        week[id] ?? Duration.zero,
      ),
      null => null,
    };
    final labels = _summaryView?.window.labels;
    final shows = (
      action,
      [for (final a in ancestors) a.id].join('/'),
      itsTime,
      labels,
      _durations,
      subActions,
      (saving, failed),
      (searching, reorderable),
    );
    if (_tiles[id] case (final kept, final tile) when kept == shows) {
      return tile;
    }
    final tile = _ActionTile(
      key: ValueKey(id),
      action: action,
      ancestors: ancestors,
      time: itsTime,
      timeLabels: labels,
      durations: _durations,
      subActions: subActions,
      saving: saving,
      failed: failed,
      onTap: () => _open(action),
      onEdit: () => _open(action),
      onRetry: () => widget.outbox.retry(id!),
      onDiscard: () => _discard(id!),
      onLongPress: reorderable
          ? () => setState(() => _reordering = true)
          : null,
      onAddAction: () => _add(parentId: id),
      onAddGroup: () => _add(parentId: id, group: true),
      onApprove: action.proposed ? () => _approve(action) : null,
    );
    _tiles[id] = (shows, tile);
    return tile;
  }

  /// Each action's row as last built, with what it showed: built again
  /// only when that changes.
  final _tiles = <String?, (Object, Widget)>{};

  /// The actions shown, to drag into a new order among their siblings.
  Widget _reorderable(ActionList actions) {
    final tree = _Tree(actions, _shown);
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
      itemBuilder: (context, i) => _ActionTile(
        key: ValueKey(shown[i].id),
        action: shown[i],
        ancestors: tree.ancestors[i],
        subActions: tree.subActions[shown[i].id] ?? 0,
        dragIndex: i,
        onTap: null,
      ),
    );
  }
}

/// The actions and groups as the Actions pane shows them, every group
/// open: those with the statuses shown -- or, searching for [query], those
/// whose name, path or note match it, and the groups they're in -- each
/// with the groups it's in, from the top, which it's indented under.
class _Tree {
  _Tree(ActionList actions, Set<String> statuses, {String query = ''}) {
    all = actions.actions;
    byId = {for (final action in all) action.id: action};
    final withStatus = [
      for (final action in all)
        if (statuses.contains(action.status)) action,
    ];
    for (final action in withStatus) {
      subActions.update(action.parentId, (n) => n + 1, ifAbsent: () => 1);
    }
    if (query.trim().isEmpty) {
      // One whose parent's status is filtered out still shows, where it
      // always has.
      shown = withStatus;
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

class _ActionTile extends StatelessWidget {
  const _ActionTile({
    super.key,
    required this.action,
    this.ancestors = const [],
    this.time,
    this.timeLabels,
    this.durations = true,
    required this.subActions,
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

  /// Its ancestors, from the top: it's indented under them.
  final List<PlanAction> ancestors;

  /// Its time, with what's in it, in the summaries' 24 hours and 7 days;
  /// null if it isn't known.
  final (Duration, Duration)? time;

  /// The labels of those windows, as the summaries have them: "24h" and
  /// "7d", or looking on, "+24h" and "+7d".
  final (String, String)? timeLabels;

  /// Whether its time is in durations, rather than percentages.
  final bool durations;

  /// How many sub-actions it has (of those shown): a group with none is
  /// empty.
  final int subActions;

  /// Tapping it: edits it.
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
    return TreeTile(
      depth: ancestors.length,
      end: 4,
      leading: ActionIcon(action),
      onTap: saving ? null : onTap,
      onLongPress: saving ? null : onLongPress,
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
  }
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
