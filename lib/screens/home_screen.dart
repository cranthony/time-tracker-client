import 'dart:async';

import 'package:flutter/material.dart';

import '../outbox/goal_outbox.dart';
import '../outbox/note_outbox.dart';
import '../services/goals_repository.dart';
import '../services/events_repository.dart';
import '../services/notes_repository.dart';
import 'goals_screen.dart';
import 'events_screen.dart';
import 'notes_screen.dart';

/// Notes, Events and Goals, with a bar at the bottom to switch between
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
          version: widget.version,
        ),
        _Tab.events => EventsScreen(
          repository: widget.eventsRepository,
          serverLabel: widget.notesRepository.label,
          goalsRepository: widget.goalsRepository,
          onSignIn: widget.onSignIn,
          onSignOut: widget.onSignOut,
          version: widget.version,
        ),
        _Tab.goals => GoalsScreen(
          repository: widget.goalsRepository,
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
            icon: Icon(Icons.flag_outlined),
            selectedIcon: Icon(Icons.flag),
            label: 'Goals',
          ),
        ],
      ),
    );
  }
}

enum _Tab { notes, events, goals }
