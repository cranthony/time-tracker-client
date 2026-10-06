import 'dart:async';

import 'package:flutter/material.dart';

import '../outbox/goal_outbox.dart';
import '../outbox/note_outbox.dart';
import '../services/goals_repository.dart';
import '../services/events_place.dart';
import '../services/events_repository.dart';
import '../services/notes_repository.dart';
import '../services/plan_memory.dart';
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
    required this.goalsRepository,
    required this.outbox,
    required this.goalOutbox,
    this.onSignIn,
    this.onSignOut,
    this.addNoteRequests,
    this.onAddNoteFieldFocused,
    this.version,
  });

  final NotesRepository notesRepository;
  final EventsRepository eventsRepository;
  final GoalsRepository goalsRepository;
  final NoteOutbox outbox;
  final GoalOutbox goalOutbox;
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
    _addNoteRequests = widget.addNoteRequests?.listen((at) {
      setState(() => _tab = _Tab.notes);
      // Once the notes screen is built and listening.
      WidgetsBinding.instance.addPostFrameCallback((_) => _toNotes.add(at));
    });
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
        ),
        _Tab.events => EventsScreen(
          repository: widget.eventsRepository,
          serverLabel: widget.notesRepository.label,
          goalsRepository: widget.goalsRepository,
          notesRepository: widget.notesRepository,
          outbox: widget.outbox,
          onSignIn: widget.onSignIn,
          onSignOut: widget.onSignOut,
          version: widget.version,
          placeStore: _eventsPlace,
          memory: _planMemory,
        ),
        _Tab.plan => PlanScreen(
          repository: widget.goalsRepository,
          eventsRepository: widget.eventsRepository,
          notesRepository: widget.notesRepository,
          memory: _planMemory,
          outbox: widget.goalOutbox,
          serverLabel: widget.notesRepository.label,
          onSignIn: widget.onSignIn,
          onSignOut: widget.onSignOut,
          version: widget.version,
        ),
      },
      bottomNavigationBar: NavigationBar(
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
      ),
    );
  }
}

enum _Tab { notes, events, plan }
