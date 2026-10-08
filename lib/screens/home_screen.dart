import 'dart:async';

import 'package:flutter/material.dart';

import '../outbox/action_outbox.dart';
import '../outbox/event_outbox.dart';
import '../outbox/note_outbox.dart';
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
import '../widgets/event_outbox_bar.dart';
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
    required this.actionOutbox,
    this.eventOutbox,
    this.proposalsRepository,
    this.onSignIn,
    this.onSignOut,
    this.addNoteRequests,
    this.onAddNoteFieldFocused,
    this.version,
  });

  final NotesRepository notesRepository;
  final EventsRepository eventsRepository;

  /// Where the open compaction proposal comes from; null for none.
  final ProposalRepository? proposalsRepository;
  final ActionsRepository actionsRepository;
  final NoteOutbox outbox;
  final ActionOutbox actionOutbox;

  /// Changes to events, and the proposal, waiting to be saved: a line at
  /// the foot of every page says so while there are any. Without it,
  /// each is saved as it's made.
  final EventOutbox? eventOutbox;
  final Future<void> Function()? onSignIn;
  final Future<void> Function()? onSignOut;

  /// Taps on the home screen "+": each switches to Notes and opens the New
  /// note dialog there.
  final Stream<DateTime>? addNoteRequests;

  /// Called when the New note dialog opened for one of [addNoteRequests]
  /// has its field focused.
  final VoidCallback? onAddNoteFieldFocused;
  final String? version;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  var _tab = _Tab.notes;
  StreamSubscription<DateTime>? _addNoteRequests;

  /// Passes [HomeScreen.addNoteRequests] on to whichever NotesScreen is
  /// showing; broadcast, since each one listens anew.
  final _toNotes = StreamController<DateTime>.broadcast();

  /// Where Events was left, to go back there.
  final _eventsPlace = EventsPlaceStore();

  /// What Plan showed, to show again while it loads when it's back: the
  /// app's, if it shares one.
  late final _planMemory = PlanMemoryScope.of(context) ?? PlanMemory();

  @override
  void initState() {
    super.initState();
    // Once the scopes can be read: the events around today, and what the
    // traits are scored by, for every page.
    WidgetsBinding.instance.addPostFrameCallback((_) => _warmScores());
    _addNoteRequests = widget.addNoteRequests?.listen((at) {
      setState(() => _tab = _Tab.notes);
      // Once the notes screen is built and listening.
      WidgetsBinding.instance.addPostFrameCallback((_) => _toNotes.add(at));
    });
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

  @override
  void dispose() {
    _addNoteRequests?.cancel();
    _toNotes.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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
        ),
        _Tab.events => EventsScreen(
          repository: widget.eventsRepository,
          serverLabel: widget.notesRepository.label,
          actionsRepository: widget.actionsRepository,
          notesRepository: widget.notesRepository,
          outbox: widget.outbox,
          onSignIn: widget.onSignIn,
          onSignOut: widget.onSignOut,
          version: widget.version,
          placeStore: _eventsPlace,
          memory: _planMemory,
          proposals: widget.proposalsRepository,
          eventOutbox: widget.eventOutbox,
        ),
        _Tab.plan => PlanScreen(
          repository: widget.actionsRepository,
          eventsRepository: widget.eventsRepository,
          notesRepository: widget.notesRepository,
          memory: _planMemory,
          outbox: widget.actionOutbox,
          serverLabel: widget.notesRepository.label,
          onSignIn: widget.onSignIn,
          onSignOut: widget.onSignOut,
          version: widget.version,
        ),
      },
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (widget.eventOutbox case final outbox?)
            EventOutboxBar(outbox: outbox),
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
        icon: Icon(Icons.edit_note_outlined),
        selectedIcon: Icon(Icons.edit_note),
        label: 'Notes',
      ),
      NavigationDestination(
        icon: Icon(Icons.event_outlined),
        selectedIcon: Icon(Icons.event),
        label: 'Events',
      ),
      NavigationDestination(
        icon: Icon(Icons.explore_outlined),
        selectedIcon: Icon(Icons.explore),
        label: 'Plan',
      ),
    ],
  );
}

enum _Tab { notes, events, plan }
