import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/event.dart';
import '../models/goal.dart';
import '../outbox/action_writes.dart';
import '../outbox/event_outbox.dart';
import '../outbox/note_writes.dart';
import '../outbox/write_queue.dart';
import '../services/goal_drafts.dart';
import '../services/goals_repository.dart';
import '../services/note_drafts.dart';
import '../platform/calendar_widget.dart';
import '../services/actions_repository.dart';
import '../services/event_store.dart';
import '../services/events_place.dart';
import '../services/events_repository.dart';
import '../services/habits_repository.dart';
import '../services/notes_repository.dart';
import '../services/people_repository.dart';
import '../services/plan_memory.dart';
import '../services/proposal_repository.dart';
import '../services/traits_repository.dart';
import '../widgets/event_outbox_status.dart';
import '../widgets/goal_flows.dart';
import '../widgets/goal_sheet.dart';
import '../widgets/hotkeys.dart';
import '../widgets/load_status.dart';
import '../widgets/note_dialog.dart';
import '../widgets/outbox_status.dart';
import '../widgets/proposal_problem_status.dart';
import '../widgets/status_bar.dart';
import 'events_screen.dart';
import 'notes_screen.dart';
import 'plan_screen.dart';

/// Notes, Events and Plan, with a bar at the bottom to switch between
/// them. Notes comes first. Each loads afresh when it's switched to, so one sees
/// a sign-in or sign-out done on the other.
class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    required this.notesRepository,
    required this.eventsRepository,
    required this.actionsRepository,
    required this.outbox,
    required this.actionWrites,
    this.eventOutbox,
    this.writeQueue,
    this.proposalsRepository,
    this.onSignIn,
    this.onSignOut,
    this.addNoteRequests,
    this.addGoalRequests,
    this.noteDrafts,
    this.goalDrafts,
    this.onAddNoteFieldFocused,
    this.calendarTaps,
    this.version,
  });

  final NotesRepository notesRepository;
  final EventsRepository eventsRepository;

  /// Where the open compaction proposal comes from; null for none.
  final ProposalRepository? proposalsRepository;
  final ActionsRepository actionsRepository;
  final NoteWrites outbox;

  /// Notes being written, kept as they're typed: the app's, on the
  /// device, or else the screen's own, while it lasts.
  final NoteDrafts? noteDrafts;

  /// The goal being set in the New goal sheet, kept as it's typed: the
  /// app's, on the device, or else the screen's own, while it lasts.
  final GoalDrafts? goalDrafts;
  final ActionWrites actionWrites;

  /// Changes to events, and the proposal, waiting to be saved: a line at
  /// the foot of every page says so while there are any. Without it,
  /// each is saved as it's made.
  final EventOutbox? eventOutbox;

  /// The other writes waiting to be saved -- people, locations -- said at
  /// the foot of every page too.
  final WriteQueue? writeQueue;
  final Future<void> Function()? onSignIn;
  final Future<void> Function()? onSignOut;

  /// Taps on the home screen "+": each switches to Notes and opens the New
  /// note dialog there.
  final Stream<DateTime>? addNoteRequests;

  /// Taps on the home screen goal button: each opens the New goal sheet
  /// over whatever's open.
  final Stream<DateTime>? addGoalRequests;

  /// Called when the New note dialog opened for one of [addNoteRequests],
  /// or the New goal sheet for one of [addGoalRequests], has its field
  /// focused.
  final VoidCallback? onAddNoteFieldFocused;

  /// Taps on the home screen calendar: each switches to Events and shows
  /// what it was on there.
  final Stream<CalendarTap>? calendarTaps;
  final String? version;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  var _tab = _Tab.notes;

  /// Kept across pages, so a draft outlasts the Notes page.
  late final NoteDrafts _noteDrafts =
      widget.noteDrafts ?? NoteDrafts.inMemory();
  late final GoalDrafts _goalDrafts =
      widget.goalDrafts ?? GoalDrafts.inMemory();
  StreamSubscription<DateTime>? _addNoteRequests;
  StreamSubscription<DateTime>? _addGoalRequests;
  StreamSubscription<CalendarTap>? _calendarTaps;

  /// Passes [HomeScreen.addNoteRequests] on to whichever NotesScreen is
  /// showing; broadcast, since each one listens anew.
  final _toNotes = StreamController<DateTime>.broadcast();

  /// Events to show on the Events page, from a refusal naming them.
  final _toEvents = StreamController<Event>.broadcast();

  /// Times to show on the Events page, from the home screen calendar;
  /// null for now.
  final _toEventsTime = StreamController<DateTime?>.broadcast();

  /// Where Events was left, to go back there.
  final _eventsPlace = EventsPlaceStore();

  /// What Plan showed, to show again while it loads when it's back: the
  /// app's, if it shares one.
  late final _planMemory = PlanMemoryScope.of(context) ?? PlanMemory();

  @override
  void initState() {
    super.initState();
    unawaited(_noteDrafts.load());
    unawaited(_goalDrafts.load());
    // Once the scopes can be read: the events around today, and what the
    // traits are scored by, for every page.
    WidgetsBinding.instance.addPostFrameCallback((_) => _warmScores());
    _addNoteRequests = widget.addNoteRequests?.listen((at) {
      setState(() => _tab = _Tab.notes);
      // Once the notes screen is built and listening.
      WidgetsBinding.instance.addPostFrameCallback((_) => _toNotes.add(at));
    });
    _addGoalRequests = widget.addGoalRequests?.listen(
      (_) => _setGoal(onFieldFocused: widget.onAddNoteFieldFocused),
    );
    _calendarTaps = widget.calendarTaps?.listen(_showCalendarTap);
  }

  /// Loads the week either side of today's events, and the traits,
  /// people and actions they're scored by. Best effort.
  Future<void> _warmScores() async {
    if (!mounted) return;
    _planMemory.useEvents(EventStore(repository: widget.eventsRepository));
    await _planMemory.warmScores(
      traits: TraitsScope.of(context),
      people: PeopleScope.of(context),
      actions: widget.actionsRepository,
      habits: HabitsScope.of(context),
    );
  }

  /// Switches to Events, and shows [event] there.
  void _showEvent(Event event) {
    setState(() => _tab = _Tab.events);
    // Once the events screen is built and listening.
    WidgetsBinding.instance.addPostFrameCallback((_) => _toEvents.add(event));
  }

  /// Switches to Events, and shows what [tap] on the home screen calendar
  /// was on: its event, as it is now, if it's here; or else its time, or
  /// now.
  void _showCalendarTap(CalendarTap tap) {
    if (tap.eventId case final id? when _lookup(id) != null) {
      return _showEvent(_lookup(id)!);
    }
    setState(() => _tab = _Tab.events);
    // Once the events screen is built and listening.
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _toEventsTime.add(tap.at),
    );
  }

  @override
  void dispose() {
    _addNoteRequests?.cancel();
    _addGoalRequests?.cancel();
    _calendarTaps?.cancel();
    _toNotes.close();
    if (widget.noteDrafts == null) _noteDrafts.dispose();
    if (widget.goalDrafts == null) _goalDrafts.dispose();
    _toEvents.close();
    _toEventsTime.close();
    _notesLoads.dispose();
    _eventsLoads.dispose();
    _actionsLoads.dispose();
    _proposalProblem.dispose();
    super.dispose();
  }

  /// How loading each page is going: only the page shown's says
  /// anything.
  final _notesLoads = LoadStatus('notes');
  final _eventsLoads = LoadStatus('events');
  final _actionsLoads = LoadStatus('actions');

  /// Why the open proposal can't be confirmed, while Events is shown.
  final _proposalProblem = ProposalProblemStatus();

  /// What the bar at the foot of every page keeps the user posted on: the
  /// page shown's load failing, or the open proposal's problem, then
  /// what's waiting to save.
  late final _status = <StatusSource>[
    _notesLoads,
    _eventsLoads,
    _actionsLoads,
    _proposalProblem,
    if (widget.eventOutbox case final outbox?)
      EventOutboxStatus(outbox, lookup: _lookup, onShow: _showEvent),
    if (widget.writeQueue case final writes?) WriteQueueStatus(writes),
  ];

  @override
  Widget build(BuildContext context) => StatusScope(
    sources: _status,
    child: HotkeyBindings(
      bindings: [
        HotkeyBinding(
          const HotkeyTrigger.ctrl(LogicalKeyboardKey.keyM),
          _writeNote,
          whenCovered: WhenCovered.run,
        ),
        HotkeyBinding(
          const HotkeyTrigger.ctrl(LogicalKeyboardKey.semicolon),
          _setGoal,
          whenCovered: WhenCovered.run,
        ),
        for (final (key, tab) in [
          (LogicalKeyboardKey.keyN, _Tab.notes),
          (LogicalKeyboardKey.keyE, _Tab.events),
          (LogicalKeyboardKey.keyP, _Tab.plan),
        ])
          HotkeyBinding(
            HotkeyTrigger.afterCtrlB(key),
            () => _goTo(tab),
            whenCovered: WhenCovered.run,
          ),
      ],
      child: _scaffold(),
    ),
  );

  /// Opens the New note sheet over whatever's open -- this page, another,
  /// a dialog -- to go back to once it's closed.
  void _writeNote() {
    if (newNoteSheetOpen) return;
    unawaited(
      showAddNoteDialog(context, keep: widget.outbox.add, drafts: _noteDrafts),
    );
  }

  /// Opens the New goal sheet over whatever's open, as [_writeNote] does
  /// the New note sheet -- or, from its More, the full New goal page.
  /// Nothing without goals to set. Calls [onFieldFocused] once its field
  /// has focus.
  Future<void> _setGoal({VoidCallback? onFieldFocused}) async {
    final repository = GoalsScope.of(context);
    if (repository == null || newGoalSheetOpen) return;
    // What's there to check it against, if they've loaded.
    unawaited(_planMemory.loadGoals(repository));
    final saved = await _addGoal(
      repository,
      drafts: _goalDrafts,
      onFieldFocused: onFieldFocused,
    );
    if (saved != null) await _goalDrafts.remove();
  }

  /// Adds a goal in a New goal sheet, starting with [title] and due on
  /// [day], if given -- or, from its More, the full New goal page. Its
  /// Under picker adds a goal for it to go under the same way, in a sheet
  /// over it, kept as no draft. Returns it as saved; null if it was
  /// called off.
  Future<Goal?> _addGoal(
    GoalsRepository repository, {
    GoalDrafts? drafts,
    String? title,
    DateTime? day,
    VoidCallback? onFieldFocused,
  }) async {
    GoalActions actions() => GoalActions(
      context: context,
      repository: repository,
      memory: _planMemory,
    );
    Goal? added;
    final result = await showAddGoalSheet(
      context,
      keep: (fields) async => added = await actions().create(fields),
      goals: _planMemory.goals ?? const [],
      drafts: drafts,
      title: title,
      day: day,
      addParent: (title, day) async {
        final added = await _addGoal(
          repository,
          title: title.isEmpty ? null : title,
          day: day,
        );
        if (added == null) return null;
        return (added: added, goals: _planMemory.goals ?? const []);
      },
      onFieldFocused: onFieldFocused,
    );
    if (result is! MoreGoal || !mounted) return added;
    final goalActions = actions();
    return goalActions.add(
      parent: goalActions.tree[result.parentId],
      title: result.title,
      deadline: result.deadline,
      description: result.description,
      priority: result.priority,
      withIds: result.withIds,
      forIds: result.forIds,
    );
  }

  /// Goes to [tab], from a hotkey: Events at now. Not while a dialog is
  /// open, waiting to be saved or discarded: the screen shakes, saying
  /// so. Pages open over this one are left.
  void _goTo(_Tab tab) {
    final hotkeys = HotkeyScope.maybeOf(context);
    if (hotkeys != null) {
      if (hotkeys.dialogOpen) return hotkeys.shake();
      hotkeys.closePages();
    }
    setState(() => _tab = tab);
    if (tab != _Tab.events) return;
    // Once the events screen is built and listening.
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _toEventsTime.add(null),
    );
  }

  Event? _lookup(String id) => _planMemory.eventStore?.event(id);

  Widget _scaffold() {
    return Scaffold(
      body: switch (_tab) {
        _Tab.notes => NotesScreen(
          repository: widget.notesRepository,
          outbox: widget.outbox,
          onSignIn: widget.onSignIn,
          onSignOut: widget.onSignOut,
          addNoteRequests: _toNotes.stream,
          onAddNoteFieldFocused: widget.onAddNoteFieldFocused,
          version: widget.version,
          memory: _planMemory,
          loads: _notesLoads,
          drafts: _noteDrafts,
        ),
        _Tab.events => EventsScreen(
          repository: widget.eventsRepository,
          serverLabel: widget.notesRepository.label,
          actionsRepository: widget.actionsRepository,
          notesRepository: widget.notesRepository,
          outbox: widget.outbox,
          noteDrafts: _noteDrafts,
          onSignIn: widget.onSignIn,
          onSignOut: widget.onSignOut,
          version: widget.version,
          placeStore: _eventsPlace,
          memory: _planMemory,
          proposals: widget.proposalsRepository,
          eventOutbox: widget.eventOutbox,
          showEventRequests: _toEvents.stream,
          showTimeRequests: _toEventsTime.stream,
          loads: _eventsLoads,
          proposalProblem: _proposalProblem,
        ),
        _Tab.plan => PlanScreen(
          repository: widget.actionsRepository,
          eventsRepository: widget.eventsRepository,
          notesRepository: widget.notesRepository,
          memory: _planMemory,
          outbox: widget.actionWrites,
          serverLabel: widget.notesRepository.label,
          onSignIn: widget.onSignIn,
          onSignOut: widget.onSignOut,
          version: widget.version,
          loads: _actionsLoads,
          onQuickAddGoal: _setGoal,
        ),
      },
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          StatusBar(sources: _status),
          _navigation(),
        ],
      ),
    );
  }

  Widget _navigation() => NavigationBar(
    selectedIndex: _tab.index,
    onDestinationSelected: (i) => setState(() => _tab = _Tab.values[i]),
    destinations: const [
      NavigationDestination(
        icon: HotkeyHint(Hotkey.notes, child: Icon(Icons.edit_note_outlined)),
        selectedIcon: HotkeyHint(Hotkey.notes, child: Icon(Icons.edit_note)),
        label: 'Notes',
      ),
      NavigationDestination(
        icon: HotkeyHint(Hotkey.events, child: Icon(Icons.event_outlined)),
        selectedIcon: HotkeyHint(Hotkey.events, child: Icon(Icons.event)),
        label: 'Events',
      ),
      NavigationDestination(
        icon: HotkeyHint(Hotkey.plan, child: Icon(Icons.explore_outlined)),
        selectedIcon: HotkeyHint(Hotkey.plan, child: Icon(Icons.explore)),
        label: 'Plan',
      ),
    ],
  );
}

enum _Tab { notes, events, plan }
