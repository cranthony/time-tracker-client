import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/commute.dart';
import '../models/event.dart';
import '../models/facts.dart';
import '../models/goal.dart';
import '../models/person.dart';
import '../models/plan_action.dart';
import '../models/note.dart';
import '../models/proposal.dart';
import '../models/recurrence.dart';
import '../models/trait.dart';
import '../outbox/event_outbox.dart';
import '../outbox/legacy_writes.dart' show actionWriteFields;
import '../outbox/note_writes.dart';
import '../outbox/write_queue.dart';
import '../services/keep_rules.dart';
import '../services/app_settings.dart';
import '../services/actions_repository.dart';
import '../services/event_store.dart';
import '../services/events_repository.dart';
import '../services/goals_repository.dart';
import '../services/habits_repository.dart';
import '../services/mcp_client.dart';
import '../services/events_place.dart';
import '../services/note_drafts.dart';
import '../services/notes_repository.dart';
import '../services/people_repository.dart';
import '../services/plan_memory.dart';
import '../services/proposal_repository.dart';
import '../services/traits_repository.dart';
import '../models/google_calendar.dart';
import '../services/google_calendars.dart';
import '../widgets/event_description.dart';
import '../widgets/google_all_day_strip.dart';
import '../widgets/goal_editor.dart'
    show deadlineLabel, goalPeopleLabel, goalPeopleNames;
import '../widgets/goal_flows.dart';
import '../widgets/goal_tile.dart';
import '../widgets/goals_due_strip.dart';
import 'goal_screen.dart';
import '../models/weather.dart';
import '../services/weather.dart';
import '../widgets/weather_strip.dart';
import '../widgets/google_event_sheet.dart';
import '../widgets/event_lists.dart';
import '../widgets/mode_stack.dart';
import '../widgets/window_cursor.dart';
import '../widgets/note_cursor.dart';
import '../widgets/note_dialog.dart';
import '../widgets/picker_edits.dart';
import '../widgets/hotkeys.dart';
import '../widgets/cursor_sheet.dart';
import '../widgets/cursor_snap.dart';
import '../widgets/app_menu.dart';
import '../widgets/day_header.dart';
import '../widgets/day_summary.dart';
import '../widgets/pending_event_box.dart';
import '../widgets/day_timeline.dart';
import '../widgets/commute_dialog.dart';
import '../widgets/durations.dart' show formatMinutes;
import '../widgets/error_sheet.dart';
import '../widgets/load_status.dart';
import '../widgets/event_dialog.dart';
import '../widgets/follow_through_dialog.dart';
import '../widgets/other_events.dart';
import '../widgets/event_summary_dialog.dart';
import '../widgets/proposal_problem_status.dart';
import '../widgets/proposal_review.dart';
import '../widgets/recurrence_dialog.dart';
import '../widgets/refreshing_bar.dart';
import '../widgets/status_message.dart';

/// One day's events on a timeline ([DayTimeline]), from midnight to
/// midnight, with buttons to step to the day before or after and to zoom
/// in or out, and one to go to now. Swiping left or right slides to the
/// day after or before, which are loaded in the background to be ready, and pinching zooms
/// around the fingers. The days slide over a [TimelineAxis] that stays
/// still, scrolled up and down with them, so every day is at the same
/// time of day. Tapping the date picks another; tapping an event
/// shows all its properties, and lets one change them; tapping between
/// events creates one there. It opens scrolled
/// to now, on today, or else to the day's first event. The last
/// compaction, from the actions, is marked on it, and so is each note not
/// yet compacted, saved or not.
///
/// Today's events are kept for next time, so they show at once while
/// they refresh. Other days load afresh, and are loaded again when shown
/// after an event was changed.
///
/// Where it was left, the day, time and zoom, is kept in its
/// [placeStore], and it opens there again if it's back within
/// [EventsPlace.keptFor]; otherwise on today.
///
/// While a compaction proposal is open (from [proposals]), what it says
/// happened, from the last compaction to its `through`, is shown in a
/// band over the days, to confirm, each event marked with what it does
/// to it; and a [ProposalBar] above confirms it, or leaves notes for
/// Claude. Changes to the events in the band -- moving, resizing,
/// cancelling or adding one, or setting its actions or facts -- edit the
/// proposal, not the calendar. The events after it are the plan, changed
/// as ever.
///
/// With [eventOutbox], changes to events and to the proposal aren't sent
/// before the dialog closes: they wait in it, in order, shown as made --
/// each marked as waiting to save -- and what a change waiting changes
/// can't be changed again till it's saved: an event it cancels or
/// creates not at all, nor the fields it sets.
class EventsScreen extends StatefulWidget {
  const EventsScreen({
    super.key,
    required this.repository,
    required this.serverLabel,
    this.actionsRepository,
    this.notesRepository,
    this.outbox,
    this.noteDrafts,
    this.eventOutbox,
    this.showEventRequests,
    this.showTimeRequests,
    this.onSignIn,
    this.onSignOut,
    this.version,
    this.placeStore,
    this.proposalProblem,
    this.memory,
    this.proposals,
    this.proposalSeen,
    this.loads,
    DateTime Function()? clock,
  }) : clock = clock ?? DateTime.now;

  final EventsRepository repository;

  /// Where the open compaction proposal comes from, to review; null for
  /// none.
  final ProposalRepository? proposals;

  /// Where the revision of the proposal last seen is kept, to show what's
  /// changed since; by default, on the device.
  final ProposalSeenStore? proposalSeen;

  /// Where to keep where it was left; null always to open on today.
  final EventsPlaceStore? placeStore;

  /// Where to load everyone, every location and every trait into as the
  /// page opens, so an event's dialogs name them at once: by default, the
  /// [PlanMemoryScope]'s.
  final PlanMemory? memory;

  /// How loading the day shown is going, for the status bar: the app's,
  /// or else one of the page's own.
  final LoadStatus? loads;

  /// Where to say why the open proposal can't be confirmed, for the
  /// status bar; null to say nothing of it.
  final ProposalProblemStatus? proposalProblem;

  /// Where to list actions from, to pick an event's; null to type their ids.
  final ActionsRepository? actionsRepository;

  /// Where to load the notes not yet compacted from, to mark them; null
  /// not to.
  final NotesRepository? notesRepository;

  /// The notes not saved yet, to mark them too.
  final NoteWrites? outbox;

  /// Where what's typed in the New note sheet is kept as a draft until
  /// it's added.
  final NoteDrafts? noteDrafts;

  /// Where changes to events and the proposal wait to be saved; without
  /// it, each is saved before its dialog closes.
  final EventOutbox? eventOutbox;

  /// Events to show: each, its day gone to, scrolled to it, and
  /// highlighted a moment.
  final Stream<Event>? showEventRequests;

  /// Times to show: each, its day gone to, scrolled to it; null for now.
  final Stream<DateTime?>? showTimeRequests;

  /// Which server this build talks to, for the About dialog.
  final String serverLabel;

  /// Runs the interactive sign-in; null when the backend needs none.
  final Future<void> Function()? onSignIn;
  final Future<void> Function()? onSignOut;

  /// The app's version, for the About dialog; null until it's known.
  final String? version;

  /// Now, for the day shown first and the "Today" label.
  final DateTime Function() clock;

  @override
  State<EventsScreen> createState() => _EventsScreenState();
}

class _EventsScreenState extends State<EventsScreen> {
  /// The page [_firstDay] is on; the days before and after it are on the
  /// pages before and after.
  static const _firstPage = 100000;

  /// How long sliding to the next or previous day takes.
  static const _slide = Duration(milliseconds: 300);

  /// Midnight, local time, at the start of the day shown.
  late DateTime _day;

  /// Today, when it opened: the day [_firstPage] is, and the one whose
  /// events are kept for next time.
  late final DateTime _firstDay;

  late PageController _pages;

  /// Whether it's still finding out where it was left, so not to scroll
  /// to the start yet.
  bool _placePending = false;

  /// The time to scroll to the top, where it was left, in place of now
  /// or the first event.
  DateTime? _restoreTop;

  /// The event highlighted, having been asked to show it, a moment.
  String? _highlighted;

  /// The event J and K have stepped to: highlighted, for Enter to open.
  String? _keyed;

  /// Stepping to another day's events, whether to its first (later) or
  /// its last, once they're loaded.
  bool? _keyedOnto;
  Timer? _unhighlight;
  StreamSubscription<Event>? _showEvents;
  StreamSubscription<DateTime?>? _showTimes;

  /// Whether it's been asked to show an event or a time, so not to go
  /// back where it was left.
  var _askedToShow = false;

  late final AppLifecycleListener _lifecycle;

  /// The page the arrows last sent it sliding to, until it gets there, so
  /// a second tap goes on from there.
  int? _slidingTo;

  /// What the app has loaded, for every page: here, the events (in its
  /// [PlanMemory.eventStore]), the actions, the notes not yet compacted
  /// and when notes were last compacted. The app's, or else one of its
  /// own.
  late final PlanMemory _memory;

  /// The app's events, day by day: each day loaded here goes in, and one
  /// already there shows at once, while it's loaded again.
  EventStore get _store => _memory.eventStore!;

  /// The days the server has answered for here since anything was last
  /// changed. The rest are kept from before, or may be out of date, and
  /// are loaded again when shown. The day shown and those either side
  /// are loaded, to be ready to slide in.
  final _fresh = <DateTime>{};

  /// The event being made or moved, while one is: the "+" starts a new
  /// one, and pressing and holding an event, moving it ([_moving]); its
  /// "✓" opens the new one, or saves the move.
  PendingEventBox? _box;

  /// The event the box is moving, if it's moving one.
  Event? _moving;

  /// The commutes queued with the move: at the box's top (true), from
  /// the event before, and at its foot (false), to the event after. A new
  /// one rides with the box's edge, trimming what it runs into as the box
  /// does; one there already is pushed with it.
  final Map<bool, _CommuteEdit> _commutes = {};

  /// The cursor last touched: its buttons win where they'd overlap
  /// another's.
  CursorRole _selected = CursorRole.anchor;

  /// The events the box treats as a list says, by list -- kept, pushed
  /// up or down, or cancelled -- in place of trimming them.
  final _lists = {for (final l in EventList.values) l: EventSelection()};

  /// The list being picked for, while it is: a tap on an event picks it,
  /// or unpicks it.
  EventList? _selecting;

  /// Whether the lists' buttons are out, above ✕ and ✓; the checklist button
  /// beside go-to-new shows or hides them.
  bool _listsShown = false;

  /// The lists' ids, as [BoxEffect] takes them.
  Map<EventList, Set<String>> get _listIds => {
    for (final MapEntry(:key, :value) in _lists.entries) key: value.ids,
  };

  /// The box always trims what's in its way, unless a list says otherwise.
  bool get _overwritesAny => true;

  /// How loading the day shown is going: a failure is tried again by
  /// itself.
  late final LoadStatus _loads = widget.loads ?? LoadStatus('events');

  /// Why the day shown couldn't be loaded, if it couldn't.
  Object? get _error => _loads.error;
  bool _needsSignIn = false;
  bool _signingIn = false;

  /// The actions by id, for the colors and names of events' actions; empty
  /// until they're loaded, or without actions.
  Map<String, PlanAction> get _actionsById => {
    for (final action in _memory.shownActions?.actions ?? const <PlanAction>[])
      ?action.id: action,
  };

  /// Everyone's names by id, and those the shown proposal adds by ref,
  /// for the people events' facts name.
  Map<String, String> get _personNames => {
    ...?_shownProposal?.addedNames,
    for (final p in _memory.people?.withSelf ?? const <Person>[])
      p.id: personName(p),
  };

  /// Every location's name by id, and those the shown proposal adds by
  /// ref, for the locations events' facts name.
  Map<String, String> get _locationNames => {
    ...?_shownProposal?.addedNames,
    for (final l in _memory.locations ?? const <Location>[]) l.id: l.name,
  };

  /// Every goal's title by id, for the goals events are for.
  Map<String, String> get _goalNames => {
    for (final g in _memory.goals ?? const <Goal>[]) g.id: goalTitle(g),
  };

  /// When notes were last compacted; null until it's known.
  DateTime? get _lastCompaction => _memory.lastCompaction;

  /// The time spent toward each goal in the events kept here that have
  /// been compacted -- ended by [_lastCompaction] -- for the goals due
  /// strip; null until when notes were last compacted is known, or if no
  /// open goal due on the day shown has an expected time. Worked out
  /// again only when the events, the goals or that change.
  Map<String, Duration>? _compactedGoalTime(List<Goal> goals) {
    final through = _lastCompaction;
    if (through == null ||
        ![
          ...goalsDueOn(goals, _day),
          ...overdueGoalsOn(goals, _day, today: widget.clock()),
        ].any((g) => g.open && g.expectedMinutes != null)) {
      return null;
    }
    final key = (_memory.eventStore?.version, goals, through);
    if (_goalTimeKept case (final kept, final time)
        when kept.$1 == key.$1 &&
            identical(kept.$2, key.$2) &&
            kept.$3 == key.$3) {
      return time;
    }
    final time = keptGoalTime(_memory, GoalTree(goals), through: through);
    _goalTimeKept = (key, time);
    return time;
  }

  ((int?, List<Goal>, DateTime), Map<String, Duration>)? _goalTimeKept;

  /// When each saved note not yet compacted was taken; empty until
  /// they're loaded.
  List<DateTime> get _savedNotes => [
    for (final n in _memory.notes ?? const <Note>[]) n.timestamp,
  ];

  /// Whether the day's summary is folded away.
  bool _summaryCollapsed = false;

  /// Whether the strip of Google Calendar's all-day events is folded to
  /// a line.
  bool _allDayCollapsed = false;

  /// Whether the weather strip is folded to its first line.
  bool _weatherCollapsed = false;

  /// Whether the strip of goals due on the day is folded to a line.
  bool _goalsDueCollapsed = false;

  /// Whether Google Calendar's events are drawn over the user's own,
  /// rather than behind them.
  bool _googleOnTop = false;

  /// The Google Calendar event being logged, while the box is up for it:
  /// the new event starts with its title, description and location.
  GoogleEvent? _logging;

  /// Whether the day's summary shows durations, rather than percentages.
  bool _summaryDurations = false;

  /// The timeline's zoom: logical pixels per minute, from the first of
  /// [timelineScales] to the last; the buttons step between them, and
  /// pinching goes anywhere between.
  double _scale = defaultTimelineScale;

  /// Where a zoom this frame is to scroll the timeline to, once it's laid
  /// out.
  double? _scrollTo;

  /// The pointers down on the timeline, where they are, for pinching.
  final _pointers = <int, Offset>{};

  /// While pinching: the distance between the fingers and the zoom when
  /// it started. Nothing scrolls or slides by dragging meanwhile.
  ({double distance, double scale})? _pinch;

  /// The timeline's scrolling up and down: every day's at once, as they
  /// slide side by side within it.
  final _scroll = ScrollController();

  /// Whether the timeline is still to be scrolled to the first day's
  /// first event, or now: once its events are shown.
  bool _scrollPending = true;

  /// How tall the timeline is, with the days on it: past the last, clear
  /// of the buttons at the foot.
  double get _height =>
      timelineSpanHeight(_from, _to, _scale) + _pastLast + _pastFoot;

  /// How far below its midnight the last day on the timeline is drawn:
  /// to the foot of an event drawn on past it, pushed down by those
  /// above.
  double get _pastLast {
    final last = DateTime(_to.year, _to.month, _to.day - 1);
    return _drawnPast(last);
  }

  /// How far below its midnight [day] is drawn.
  double _drawnPast(DateTime day) => switch (_eventsOn(day)) {
    null => 0,
    final events =>
      timelineDrawnHeight(
            context,
            events: events,
            day: day,
            scale: _scale,
            marks: _marks,
          ) -
          timelineHeight(day, _scale),
  };

  /// What's below the last day on the timeline, clear of the buttons at
  /// the foot.
  static const _pastFoot = 170.0;

  /// The open compaction proposal as the server last gave it, once it's
  /// loaded; null without one.
  Proposal? _loadedProposal;

  /// The open compaction proposal, as shown: with the edits of it waiting
  /// to be saved. Never one that's closed -- confirmed and applied, or
  /// abandoned -- however it was loaded: a load asked for before it closed
  /// answers with it still open.
  Proposal? get _proposal => switch (_loadedProposal) {
    final loaded? when !_closed.contains(loaded.id) =>
      widget.eventOutbox?.projectProposal(loaded) ?? loaded,
    _ => null,
  };

  /// One that no longer plans keeps the events it last planned, as they
  /// were, to show. Hidden while it didn't, it's shown again once it
  /// does: the calendar fixed under it.
  set _proposal(Proposal? proposal) {
    final earlier = _loadedProposal;
    final next = _loadedProposal = proposal?.keepingPlanOf(earlier);
    _learnNames(earlier, next);
    if (_hidden &&
        next != null &&
        next.plans &&
        earlier?.id == next.id &&
        !earlier!.plans) {
      _hiddenId = null;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('The proposal plans again, so it\'s shown again.'),
          ),
        );
      });
    }
  }

  /// The ids the proposal's settled additions are named by that names
  /// were loaded again for: each loaded for once.
  final _namesLoadedFor = <String>{};

  /// Whether names are to be loaded again once this frame's done.
  bool _namesDue = false;

  /// Loads everyone, every location and every action again -- once this
  /// frame's done -- when what the proposal adds is made where it isn't
  /// loaded: [earlier] closed, applied (its additions made) or not, or
  /// [next] naming, by an addition settled, one not loaded yet.
  void _learnNames(Proposal? earlier, Proposal? next) {
    final known = {
      for (final p in _memory.people?.withSelf ?? const <Person>[]) p.id,
      for (final l in _memory.locations ?? const <Location>[]) l.id,
      ..._actionsById.keys,
    };
    final unknown = {
      for (final s in next?.settledAdditions ?? const <AdditionSettled>[])
        if (s.id case final id? when !known.contains(id)) id,
    }.difference(_namesLoadedFor);
    final closed =
        earlier != null &&
        earlier.additions.isNotEmpty &&
        next?.id != earlier.id;
    if (unknown.isEmpty && !closed) return;
    _namesLoadedFor.addAll(unknown);
    if (_namesDue) return;
    _namesDue = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _namesDue = false;
      if (!mounted) return;
      unawaited(_prefetchNames());
      unawaited(_loadActions());
    });
  }

  /// The proposal hidden, by id, to show the calendar under it.
  String? _hiddenId;

  /// Whether the open proposal is hidden: the calendar's shown under it.
  bool get _hidden => _hiddenId != null && _hiddenId == _loadedProposal?.id;

  /// The open proposal, as the timeline shows it: none, while it's hidden.
  Proposal? get _shownProposal => _hidden ? null : _proposal;

  /// Whether the calendar's being fixed under the open proposal: it's
  /// hidden while it no longer plans -- not while its apply stopped
  /// partway, which finishing writes over.
  bool get _fixing => switch (_proposal) {
    final p? => _hidden && !p.plans && p.state != ProposalState.applying,
    null => false,
  };

  /// The proposal edits in its window go to: the open one -- unless the
  /// calendar's being fixed under it, so they're the calendar's.
  Proposal? get _editedProposal => _fixing ? null : _proposal;

  /// Whether the calendar's shown under a proposal it isn't being fixed
  /// under -- one that plans, or whose apply stopped partway: there to
  /// see, not edit, so nothing changes under it.
  bool get _readOnly => _hidden && !_fixing;

  /// Hides the open proposal, to show the calendar under it, or shows it
  /// again.
  void _toggleHidden() {
    final proposal = _proposal;
    if (proposal == null) return;
    setState(() {
      _hiddenId = _hidden ? null : proposal.id;
      _extendTo = null;
    });
  }

  /// Says, while [_readOnly], that the calendar can't be changed under a
  /// proposal that plans; returns whether it is.
  bool _saidReadOnly() {
    if (!_readOnly) return false;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text(
          'The proposal is hidden: show it again to make changes.',
        ),
        action: SnackBarAction(label: 'Show it', onPressed: _toggleHidden),
      ),
    );
    return true;
  }

  /// Takes in [changed], as saved: and, while the calendar's being fixed
  /// under a proposal that no longer plans, asks whether it does now.
  void _putEvents(Iterable<Event> changed) {
    _store.putEvents(changed);
    if (_fixing) unawaited(_loadProposal());
  }

  /// The proposals closed while the page has been open: here, or as the
  /// notices say -- by the background task, say.
  Set<String> get _closed => {
    ..._closedHere,
    for (final n in _notices)
      if (n.kind == ProposalNoticeKind.applied ||
          n.kind == ProposalNoticeKind.abandoned)
        n.proposalId,
  };
  final _closedHere = <String>{};

  /// The proposal last applied while the page has been open, and when:
  /// what it says happened is shown on each of its days kept from before
  /// then, till that day's asked for again -- not the calendar as it was
  /// before it was applied.
  ({Proposal proposal, DateTime at})? _applied;

  /// The proposal applied, if [day]'s events were asked for before it
  /// was: what's on the calendar now.
  Proposal? _appliedOn(DateTime day) => switch (_applied) {
    (:final proposal, :final at)
        when _store.askedAt(day)?.isBefore(at) ?? true =>
      proposal,
    _ => null,
  };

  /// Takes the proposal [id] away, once, as closed: [applied], the events
  /// and notes it compacted are loaded again.
  void _closeProposal(String id, {required bool applied}) {
    if (!mounted || !_closedHere.add(id)) return;
    if (applied && _loadedProposal?.id == id) {
      // Kept as seen: nothing in it is new any more.
      final loaded = _loadedProposal!;
      if (_proposalLoaded) _seen.saw(loaded.id, loaded.revision);
      _applied = (proposal: loaded, at: _store.clock());
    }
    setState(() {
      if (_loadedProposal?.id == id) _proposal = null;
      _editedHere.clear();
    });
    if (!applied) return;
    _fresh.clear();
    // The last compaction is its through now.
    unawaited(_loadNotes());
    unawaited(_refresh());
    // The actions it made, or approved, as the server has them now.
    unawaited(_loadActions());
  }

  /// How changes are made: by way of [EventsScreen.eventOutbox], or at
  /// once.
  late final EventWrites _writes =
      widget.eventOutbox ??
      DirectEventWrites(widget.repository, widget.proposals);

  StreamSubscription<(PendingEventWrite, Object?)>? _savedWrites;

  /// Where the revision of the proposal last seen is kept.
  late final ProposalSeenStore _seen;

  /// The revision of [_proposal] seen before this visit -- what's changed
  /// since is highlighted -- and the proposal it's of.
  int? _since;
  String? _sinceOf;

  /// Whether the proposal's been loaded from the server this visit: until
  /// then, it's as it was kept, if it was.
  bool _proposalLoaded = false;

  /// The events the user's own edits changed this visit: not highlighted
  /// as changed since they looked.
  final _editedHere = <String>{};

  /// Whether the proposal's being confirmed, or a note left: its bar
  /// can't be used meanwhile.
  bool _proposalBusy = false;

  /// Where the proposal's window is being extended to, while it is: its
  /// end's cursor.
  DateTime? _extendTo;

  /// Where a new note goes, while it's being placed: its cursor, which ✓
  /// opens the New note sheet at.
  DateTime? _noteAt;

  /// Which of the proposal's notes is shown under its bar, and
  /// highlighted on the timeline.
  /// Null for the first note to review.
  int? _noteIndex;

  /// Which page of the proposal's details is shown under its bar:
  /// Claude's recap of it -- first, while it has one -- its notes, its
  /// cancels, or what it adds.
  ProposalDetailPage _detailPage = ProposalDetailPage.claude;

  /// The page of the proposal's details shown: [_detailPage], if it has
  /// anything on it, or else the first that has.
  ProposalDetailPage? get _shownPage {
    final pages = [
      if (_recapPoint != null) ProposalDetailPage.claude,
      if (_note != null) ProposalDetailPage.notes,
      if (_cancel != null) ProposalDetailPage.followThrough,
      if (_addition != null) ProposalDetailPage.added,
      if (_goalChange != null) ProposalDetailPage.goals,
    ];
    return pages.contains(_detailPage) ? _detailPage : pages.firstOrNull;
  }

  /// Which point of Claude's recap is shown.
  int _recapIndex = 0;

  /// The point of Claude's recap shown under the proposal's bar, if it has
  /// a recap.
  RecapPoint? get _recapPoint => switch (_proposal?.recap?.points) {
    final points? when points.isNotEmpty =>
      points[_recapIndex.clamp(0, points.length - 1)],
    _ => null,
  };

  /// Which of the proposal's cancels, and of what it adds, is shown.
  int _cancelIndex = 0;
  int _additionIndex = 0;

  /// Whether the proposal's details are folded away.
  bool _detailsCollapsed = false;

  /// The cancel shown under the proposal's bar, if it has any.
  ProposalEvent? get _cancel => switch (_proposal?.cancels) {
    final cancels? when cancels.isNotEmpty =>
      cancels[_cancelIndex.clamp(0, cancels.length - 1)],
    _ => null,
  };

  /// What the proposal adds that's shown under its bar, if it adds any.
  _Added? get _addition => switch (_additions) {
    final added when added.isNotEmpty =>
      added[_additionIndex.clamp(0, added.length - 1)],
    _ => null,
  };

  /// Every addition the app's seen the open proposal make, by ref: those
  /// it's settled leave its additions, but are still shown.
  final _seenAdditions = <String, ProposalAddition>{};

  /// What the proposal adds -- still to settle, then settled -- in the
  /// order it first made them.
  List<_Added> get _additions {
    final proposal = _proposal;
    if (proposal == null) return const [];
    for (final a in proposal.additions) {
      _seenAdditions.putIfAbsent(a.ref, () => a);
    }
    final settled = {for (final s in proposal.settledAdditions) s.ref: s};
    final pending = {for (final a in proposal.additions) a.ref};
    return [
      for (final ref in {..._seenAdditions.keys, ...settled.keys})
        if (pending.contains(ref) || settled.containsKey(ref))
          (
            addition:
                _seenAdditions[ref] ??
                ProposalAddition(
                  ref: ref,
                  kind: AdditionKind.person,
                  name: ref.replaceFirst('new:', ''),
                ),
            settled: settled[ref],
          ),
    ];
  }

  /// Which of the proposal's goal changes is shown.
  int _goalChangeIndex = 0;

  /// Every goal change the app's seen the open proposal make, by goal id,
  /// as Claude first made it: one the user settled leaves the proposal's
  /// changes, or is changed in them, but is still shown -- and can be put
  /// back.
  final _seenGoalChanges = <String, ProposalGoalChange>{};

  /// The proposal's goal changes -- still to settle, then settled -- in
  /// the order it first made them.
  List<_GoalChanged> get _goalChanges {
    final proposal = _proposal;
    if (proposal == null) return const [];
    for (final c in proposal.goalChanges) {
      // Claude's, as first seen; one the user changed isn't Claude's.
      if (c.decidedBy != DecidedBy.user) {
        _seenGoalChanges.putIfAbsent(c.goalId, () => c);
      }
    }
    final settled = {for (final s in proposal.settledGoalChanges) s.goalId: s};
    final pending = {for (final c in proposal.goalChanges) c.goalId: c};
    return [
      for (final id in {
        ..._seenGoalChanges.keys,
        ...pending.keys,
        ...settled.keys,
      })
        if (pending.containsKey(id) || settled.containsKey(id))
          (
            change:
                pending[id] ??
                switch ((_seenGoalChanges[id], settled[id])) {
                  (final claudes?, _) => claudes,
                  (null, final s?) => ProposalGoalChange(
                    goalId: id,
                    status: s.status ?? 'done',
                    title: _memory.goals
                        ?.where((g) => g.id == id)
                        .firstOrNull
                        ?.title,
                    at: s.at,
                    retryDeadline: s.retryDeadline,
                    decidedBy: DecidedBy.user,
                  ),
                  _ => ProposalGoalChange(goalId: id, status: 'done'),
                },
            settled: settled[id],
            claudes: _seenGoalChanges[id],
          ),
    ];
  }

  /// The goal change shown under the proposal's bar, if it makes any.
  _GoalChanged? get _goalChange => switch (_goalChanges) {
    final changes when changes.isNotEmpty =>
      changes[_goalChangeIndex.clamp(0, changes.length - 1)],
    _ => null,
  };

  /// Shows the [index]th of the proposal's goal changes under its bar.
  void _goToGoalChange(int index) {
    final changes = _goalChanges;
    if (changes.isEmpty) return;
    setState(() {
      _goalChangeIndex = index.clamp(0, changes.length - 1);
      _detailPage = ProposalDetailPage.goals;
    });
  }

  /// The events of what happened that [added] is used at, given as an
  /// action, or in their facts: by its ref, or, settled, by its id.
  List<ProposalEvent> _usesOf(_Added added) {
    final name = switch (added.settled) {
      null => added.addition.ref,
      AdditionSettled(:final id?) => id,
      _ => null,
    };
    if (name == null) return const [];
    return [
      for (final e in _proposal?.reviewed ?? const <ProposalEvent>[])
        if (e.live && (e.actionIds.contains(name) || _mentions(e.facts, name)))
          e,
    ];
  }

  /// What [settled] is named, now it's one already there, or made.
  String? _settledName(AdditionSettled? settled, AdditionKind kind) {
    final id = settled?.id;
    if (id == null) return null;
    return switch (kind) {
      AdditionKind.person => switch (_memory.people?.withSelf
          .where((p) => p.id == id)
          .firstOrNull) {
        final p? => personName(p),
        null => null,
      },
      AdditionKind.location =>
        _memory.locations?.where((l) => l.id == id).firstOrNull?.name,
      AdditionKind.action => switch (_actionsById[id]) {
        final a? => actionName(a),
        null => null,
      },
      AdditionKind.goal => switch (_memory.goals
          ?.where((g) => g.id == id)
          .firstOrNull) {
        final g? => goalTitle(g),
        null => null,
      },
    };
  }

  /// A new goal's [a]: when it's due, and who it's with and for -- the
  /// people the proposal adds named as it has them, marked new.
  String? _aboutGoal(ProposalAddition a) {
    if (a.kind != AdditionKind.goal) return null;
    final added = {
      for (final p in _proposal?.additions ?? const <ProposalAddition>[])
        if (p.kind == AdditionKind.person) p.ref: '${p.name} (new)',
    };
    final known = goalPeopleNames(_memory);
    String name(String id) => added[id] ?? known(id);
    return [
      if (a.deadline case final d?) 'Due ${deadlineLabel(context, d)}',
      ?goalPeopleLabel(a.withIds, a.forIds, name),
    ].join(' · ');
  }

  /// Whether [json] -- facts, say -- names [ref] anywhere.
  static bool _mentions(Object? json, String ref) => switch (json) {
    final String s => s == ref,
    final List list => list.any((v) => _mentions(v, ref)),
    final Map map =>
      map.keys.contains(ref) || map.values.any((v) => _mentions(v, ref)),
    _ => false,
  };

  /// The events outlined on the timeline: the cancel shown, or where
  /// what's added that's shown is used.
  Set<String> get _selectedEvents => switch (_shownPage) {
    ProposalDetailPage.claude => {...?_recapPoint?.eventIds},
    ProposalDetailPage.followThrough => {?_cancel?.id},
    ProposalDetailPage.added => switch (_addition) {
      final a? => {for (final e in _usesOf(a)) e.id},
      null => const {},
    },
    ProposalDetailPage.notes || ProposalDetailPage.goals || null => const {},
  };

  /// The proposal's notes, after the latest one an earlier compaction
  /// used, as context: the proposal's own, or else the one the app was
  /// told of.
  List<ProposalNote> get _proposalNotes {
    final proposal = _proposal;
    if (proposal == null) return const [];
    final notes = proposal.notes;
    final latest = _memory.compaction?.latestCompacted;
    if (latest == null ||
        notes.any((n) => n.compacted) ||
        !latest.timestamp.isBefore(proposal.windowStart)) {
      return notes;
    }
    return [
      ProposalNote(
        id: latest.id ?? 'compacted',
        time: latest.timestamp,
        text: latest.description,
        compacted: true,
      ),
      ...notes,
    ];
  }

  /// The note shown under the proposal's bar: [_noteIndex], or else the
  /// first to review.
  ProposalNote? get _note {
    final notes = _proposalNotes;
    if (notes.isEmpty) return null;
    final i =
        _noteIndex ??
        switch (notes.indexWhere((n) => !n.compacted)) {
          -1 => 0,
          final first => first,
        };
    return notes[i.clamp(0, notes.length - 1)];
  }

  /// The proposal's notes, as the timeline draws them: the note shown
  /// selected, or those the point of Claude's recap shown names.
  List<ReviewNote> get _reviewNotes {
    if (_hidden) return const [];
    final selected = switch (_shownPage) {
      ProposalDetailPage.notes => {?_note?.id},
      ProposalDetailPage.claude => {...?_recapPoint?.noteIds},
      _ => const <String>{},
    };
    return [
      for (final note in _proposalNotes)
        ReviewNote(
          time: note.time,
          kind: reviewNoteKind(note, of: _proposal),
          selected: selected.contains(note.id),
        ),
    ];
  }

  /// Shows the [index]th point of Claude's recap under the proposal's
  /// bar, and scrolls the timeline to [eventId] or [noteId] -- or, with
  /// neither, to the first event, or else note, it names. With [goalId],
  /// shows that goal change instead.
  void _goToRecap(
    int index, {
    String? eventId,
    String? noteId,
    String? goalId,
  }) {
    final points = _proposal?.recap?.points ?? const <RecapPoint>[];
    if (points.isEmpty) return;
    final i = index.clamp(0, points.length - 1);
    setState(() {
      _recapIndex = i;
      _detailPage = ProposalDetailPage.claude;
    });
    if (goalId != null) {
      final at = _goalChanges.indexWhere((c) => c.change.goalId == goalId);
      if (at >= 0) _goToGoalChange(at);
      return;
    }
    final point = points[i];
    final proposal = _proposal;
    final event = proposal?.event(
      eventId ?? (noteId == null ? point.eventIds.firstOrNull : null),
    );
    if (event != null) return _scrollToTime(event.start);
    final noteTo = noteId ?? point.noteIds.firstOrNull;
    final note = _proposalNotes.where((n) => n.id == noteTo).firstOrNull;
    if (note != null) _scrollToTime(note.time);
  }

  /// The open proposal's events, by id or key, named for Claude's recap:
  /// those still to come too, which it may name.
  Map<String, String> get _recapEventNames {
    final strings = MaterialLocalizations.of(context);
    return {
      for (final e in _proposal?.events ?? const <ProposalEvent>[])
        e.id:
            '${switch (e.summary) {
              final s? when s.isNotEmpty => s,
              _ => '(no summary)',
            }}, ${strings.formatTimeOfDay(TimeOfDay.fromDateTime(e.start.toLocal()))}',
    };
  }

  /// The open proposal's time notes, by id, named for Claude's recap:
  /// "11:05 AM note".
  Map<String, String> get _recapNoteNames {
    final strings = MaterialLocalizations.of(context);
    return {
      for (final n in _proposalNotes)
        n.id:
            '${strings.formatTimeOfDay(TimeOfDay.fromDateTime(n.time.toLocal()))} note',
    };
  }

  /// The open proposal's goal changes, by goal id, named for Claude's
  /// recap: the goal's title, and what the change marks it.
  Map<String, String> get _recapGoalNames => {
    for (final (:change, settled: _, claudes: _) in _goalChanges)
      change.goalId:
          '${change.name} · ${goalChangeLabel(context, change.status, change.retryDeadline)}',
  };

  /// Shows all of Claude's recap, and goes where the user asks of it: to
  /// a point, an event, a note or a goal change -- or leaves a note for
  /// Claude answering a point it's unsure of.
  Future<void> _openRecap() async {
    final proposal = _proposal;
    final recap = proposal?.recap;
    if (proposal == null || recap == null) return;
    final action = await showRecapSheet(
      context,
      recap,
      revision: proposal.revision,
      events: _recapEventNames,
      notes: _recapNoteNames,
      goals: _recapGoalNames,
      changed: proposal.editedSinceRecap,
      canAsk: !_proposalBusy,
      answersTo: proposal.answersTo,
      others: proposal.notesForClaude,
      about: {..._reviewedNames, ..._noteNames},
    );
    if (action == null || !mounted) return;
    switch (action) {
      case GoToRecapPoint(
        :final index,
        :final eventId,
        :final noteId,
        :final goalId,
      ):
        _goToRecap(index, eventId: eventId, noteId: noteId, goalId: goalId);
      case AskAboutRecapPoint(:final point):
        final note = point.eventIds.isEmpty
            ? _proposalNotes
                  .where((n) => point.noteIds.contains(n.id))
                  .firstOrNull
            : null;
        await _noteForClaude(
          about: point.eventIds.where(_reviewedNames.containsKey).firstOrNull,
          aboutNote: note,
          answering: point,
        );
    }
  }

  /// Shows the [index]th of the proposal's notes under its bar, and
  /// scrolls the timeline to it, in the middle of the view.
  void _goToNote(int index) {
    final notes = _proposalNotes;
    if (notes.isEmpty) return;
    final i = index.clamp(0, notes.length - 1);
    setState(() => _noteIndex = i);
    _scrollToTime(notes[i].time);
  }

  /// Turns the proposal's details to [page]; turned to its notes, cancels
  /// or what it adds, the timeline scrolls to the one shown.
  void _turnDetailsTo(ProposalDetailPage page) {
    setState(() => _detailPage = page);
    final time = switch (page) {
      ProposalDetailPage.notes => _note?.time,
      ProposalDetailPage.followThrough => _cancel?.start,
      ProposalDetailPage.added => switch (_addition) {
        final a? => _usesOf(a).firstOrNull?.start,
        null => null,
      },
      ProposalDetailPage.claude || ProposalDetailPage.goals => null,
    };
    if (time != null) _scrollToTime(time);
  }

  /// Shows the [index]th of the proposal's cancels under its bar, and
  /// scrolls the timeline to it.
  void _goToCancel(int index) {
    final cancels = _proposal?.cancels ?? const <ProposalEvent>[];
    if (cancels.isEmpty) return;
    final i = index.clamp(0, cancels.length - 1);
    setState(() => _cancelIndex = i);
    _scrollToTime(cancels[i].start);
  }

  /// Shows the [index]th of what the proposal adds under its bar, and
  /// scrolls the timeline to where it's first used.
  void _goToAddition(int index) {
    final added = _additions;
    if (added.isEmpty) return;
    final i = index.clamp(0, added.length - 1);
    setState(() => _additionIndex = i);
    if (_usesOf(added[i]).firstOrNull case final e?) _scrollToTime(e.start);
  }

  /// Shows [event]: its day, scrolled to it, and it highlighted a moment.
  void _showEvent(Event event) {
    _unhighlight?.cancel();
    setState(() {
      _askedToShow = true;
      _placePending = false;
      _scrollPending = false;
      _restoreTop = null;
      _highlighted = event.id;
    });
    _scrollToTime(event.start, nearTop: true);
    _unhighlight = Timer(const Duration(seconds: 4), () {
      if (mounted) setState(() => _highlighted = null);
    });
  }

  /// Shows [time]'s day, scrolled to it; or, with none, now.
  void _showTime(DateTime? time) {
    setState(() {
      _askedToShow = true;
      _placePending = false;
      _scrollPending = false;
      _restoreTop = null;
    });
    if (time == null) {
      _goToNow();
    } else {
      _scrollToTime(time, nearTop: true);
    }
  }

  /// Shows [time]'s day, scrolled so [time] is in the middle of the view;
  /// or, [nearTop], a little below its top -- where it stays in view as
  /// what's above the timeline loads and pushes its foot off the screen,
  /// as it does when the app's just started.
  void _scrollToTime(DateTime time, {bool nearTop = false}) {
    final at = time.toLocal();
    final day = _midnight(at);
    if (day != _day) _goToDay(day);
    // Once it's laid out on that day.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      final position = _scroll.position;
      final y =
          timelineOffset(at, day: day, dayEnd: _dayAfter(day), scale: _scale) -
          (nearTop ? 48 : position.viewportDimension / 2);
      _scroll.animateTo(
        y.clamp(0, position.maxScrollExtent),
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    });
  }

  /// The day shown's events, if they're loaded.
  List<Event>? get _shown => _eventsOn(_day);

  /// [day]'s events, if they're loaded, as they're shown: in what an
  /// open proposal says happened, as it says -- or one just applied, till
  /// the day's loaded again.
  List<Event>? _eventsOn(DateTime day) => switch (_store.day(day)) {
    final events? => _withProposal(
      _waiting(events, day, _dayAfter(day)),
      day,
      _dayAfter(day),
      proposal: _shownProposal ?? _appliedOn(day),
    ),
    null => null,
  };

  /// [events], the calendar's from [from] to [to], with the changes
  /// waiting to be saved made to them.
  List<Event> _waiting(List<Event> events, DateTime from, DateTime to) =>
      widget.eventOutbox?.project(events, from, to) ?? events;

  /// [calendar], the calendar's events from [from] to [to], with those
  /// that [proposal] -- the open one by default -- says happened as it
  /// says: a new one added, and a cancelled one shown cancelled -- unless
  /// another is in its place.
  List<Event> _withProposal(
    List<Event> calendar,
    DateTime from,
    DateTime to, {
    Proposal? proposal,
  }) {
    proposal ??= _shownProposal;
    final reviewed = proposal?.reviewed ?? const <ProposalEvent>[];
    if (reviewed.isEmpty) return calendar;
    final ids = {for (final e in reviewed) e.id};
    final byId = {for (final e in calendar) ?e.id: e};
    final here = [
      for (final e in reviewed)
        if (e.start.isBefore(to) && e.end.isAfter(from)) e,
    ];
    bool covered(ProposalEvent e) => here.any(
      (other) =>
          other.live &&
          other.start.isBefore(e.end) &&
          other.end.isAfter(e.start),
    );
    return [
      for (final e in calendar)
        if (!ids.contains(e.id)) e,
      for (final e in here)
        if (e.live || !covered(e))
          e.toEvent(byId[e.id], proposal?.addedNames ?? const {}),
    ]..sort((a, b) => a.start.compareTo(b.start));
  }

  /// Whether [event] is in what the open proposal says happened: changed
  /// in it, not on the calendar.
  bool _inReview(Event event) =>
      _editedProposal?.event(event.id)?.reviewed ?? false;

  /// Whether an event from [start] to [end] would be in what the open
  /// proposal says happened.
  bool _reviews(DateTime start, DateTime end) =>
      _editedProposal?.covers(start, end) ?? false;

  /// The events changed since the user last looked at the proposal.
  Set<String> get _changedSince => {
    ...(_proposal?.changedSince ?? const {}).difference(_editedHere),
    // Those an edit sent from the queue replaced Claude's newer changes to.
    for (final n in _notices)
      if (n.kind == ProposalNoticeKind.replaced &&
          n.proposalId == _proposal?.id)
        ...n.eventIds,
  };

  /// What came of changes to the proposal sent from the queue, not yet
  /// dismissed.
  List<ProposalNotice> get _notices =>
      widget.eventOutbox?.notices?.notices ?? const [];

  /// What the open proposal does to each of its events, and which wait
  /// for a change to be saved, to mark them.
  Map<String, EventMark> get _marks {
    final marks = _proposalMarks;
    final outbox = widget.eventOutbox;
    if (outbox == null || outbox.pending.isEmpty) return marks;
    final waiting = {
      for (final w in outbox.pending)
        for (final id in w.locks.keys) id: w,
    };
    return {
      ...marks,
      for (final MapEntry(key: id, value: write) in waiting.entries)
        id: EventMark(
          label: [
            ?marks[id]?.label,
            write.refused ? "Couldn't save" : 'Waiting to save',
          ].join(' · '),
          icon: write.refused
              ? Icons.cloud_off_outlined
              : Icons.cloud_upload_outlined,
          changed: marks[id]?.changed ?? false,
          selected: marks[id]?.selected ?? false,
        ),
    };
  }

  /// What the open proposal does to each of its events, to mark them.
  Map<String, EventMark> get _proposalMarks {
    final proposal = _shownProposal;
    if (proposal == null) return const {};
    final calendar = {
      for (final e in _store.between(
        proposal.windowStart.subtract(const Duration(days: 1)),
        proposal.through.add(const Duration(days: 1)),
      ))
        ?e.id: e,
    };
    final changed = _changedSince;
    final selected = _selectedEvents;
    final strings = MaterialLocalizations.of(context);
    return {
      for (final e in proposal.reviewed)
        e.id: proposalMark(
          e,
          calendar: calendar[e.id],
          changed: changed.contains(e.id),
          selected: selected.contains(e.id),
          time: (t) =>
              strings.formatTimeOfDay(TimeOfDay.fromDateTime(t.toLocal())),
        ),
    };
  }

  /// Whether the day shown is kept from last time, or may be out of date,
  /// and is being loaded again.
  bool get _stale => _store.has(_day) && !_fresh.contains(_day);

  /// Shows what the app loads -- a day, as it opens, say -- as soon as
  /// it has it.
  void _memoryChanged() {
    if (!mounted) return;
    // Closed, as a notice says -- sent from here or by the background
    // task: gone as the banner says so, not when it's next loaded.
    if (_loadedProposal case final loaded?
        when !_closedHere.contains(loaded.id)) {
      for (final n in _notices) {
        if (n.proposalId != loaded.id) continue;
        if (n.kind == ProposalNoticeKind.applied) {
          return _closeProposal(loaded.id, applied: true);
        }
        if (n.kind == ProposalNoticeKind.abandoned) {
          return _closeProposal(loaded.id, applied: false);
        }
      }
    }
    setState(() {});
  }

  /// Loads everyone, every location, every trait and Self's habits, for
  /// an event's dialogs to name at once. Best effort.
  Future<void> _prefetchNames() async {
    if (!mounted) return;
    final memory = _memory;
    // Asked afresh each time the page opens.
    memory.newVisit();
    final people = PeopleScope.of(context);
    await Future.wait([
      memory.prefetchNames(
        traits: TraitsScope.of(context),
        people: people,
        habits: HabitsScope.of(context),
        goals: GoalsScope.of(context),
      ),
      // For the commutes a moved event can have: best effort.
      if (people != null)
        memory.loadTravelTimes(people).catchError((Object _) {}),
    ]);
    if (mounted) setState(() {});
  }

  @override
  void initState() {
    super.initState();
    _memory = widget.memory ?? PlanMemoryScope.of(context) ?? PlanMemory();
    _memory
      ..useEvents(EventStore(repository: widget.repository))
      ..addListener(_memoryChanged);
    _seen = widget.proposalSeen ?? ProposalSeenStore();
    _day = _firstDay = _midnight(widget.clock());
    _loads.bind(_refresh);
    _lifecycle = AppLifecycleListener(
      onHide: _savePlace,
      onResume: () {
        _resumeProposal();
        // Changed in the calendar app, maybe, while away.
        GoogleCalendars.of(context)?.refresh();
        // Old by now, maybe, or somewhere else.
        Weather.read(context)?.refresh();
      },
    );
    final store = widget.placeStore;
    // Back from another tab: there at once.
    if (store?.remembered case final place? when place.keptAt(widget.clock())) {
      _day = place.day;
      _scale = place.scale;
      _restoreTop = place.top;
    } else if (store != null) {
      _placePending = true;
      unawaited(_loadPlace(store));
    }
    _pages = PageController(initialPage: _pageOf(_day));
    _showCached();
    _refresh();
    _loadActions();
    widget.outbox?.addListener(_outboxChanged);
    widget.eventOutbox?.addListener(_memoryChanged);
    widget.eventOutbox?.notices
      ?..addListener(_memoryChanged)
      ..load();
    _savedWrites = widget.eventOutbox?.saved.listen(_writeSaved);
    _showEvents = widget.showEventRequests?.listen(_showEvent);
    _showTimes = widget.showTimeRequests?.listen(_showTime);
    _loadNotes(cached: true);
    _showKeptProposal();
    _loadProposal();
    _loadSummaryCollapsed();
    _loadAllDayCollapsed();
    _loadGoalsDueCollapsed();
    _loadWeatherCollapsed();
    // Once the scopes above can be read: if it's old by now.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Weather.read(context)?.refresh();
    });
    _loadGoogleOnTop();
    _loadDetailsCollapsed();
    // Once the scopes can be read: everyone, every location and every
    // trait, for an event's dialogs.
    WidgetsBinding.instance.addPostFrameCallback((_) => _prefetchNames());
    _loadSummaryDurations();
  }

  /// What [write] saved: the events it changed, shown at once, or the
  /// proposal's new revision.
  void _writeSaved((PendingEventWrite, Object?) saved) {
    if (!mounted) return;
    final (write, result) = saved;
    switch (result) {
      case final List<Event> events:
        _putEvents(events);
        // A series' later events, which the server worked out: the days
        // here are loaded again, each as it's shown.
        if (write.setsRepeat) {
          _fresh.clear();
          unawaited(_refresh());
        }
      case final Proposal amended:
        final loaded = _loadedProposal;
        if (loaded == null || loaded.id != amended.id) return;
        setState(() {
          _editedHere
            ..addAll(write.edits.eventIds)
            ..addAll({
              for (final e in amended.events ?? const <ProposalEvent>[])
                if (loaded.event(e.id) == null) e.id,
            });
          _proposal = amended.copyWith(changedSince: loaded.changedSince);
        });
      // What came of it is said in the notices: here, it's only shown.
      case ProposalOutcome(status: ProposalOutcomeStatus.applied):
        if (write.proposalId case final id?) {
          _closeProposal(id, applied: true);
        }
      case ProposalOutcome(status: ProposalOutcomeStatus.abandoned):
        if (write.proposalId case final id?) {
          _closeProposal(id, applied: false);
        }
      case _ when write.kind == EventWriteKind.abandon:
        if (write.proposalId case final id?) {
          _closeProposal(id, applied: false);
        }
      case _ when write.kind.ofProposal:
        // A new revision, or a note left or withdrawn.
        unawaited(_loadProposal());
    }
  }

  /// When each note not yet compacted was taken: those saved, and those
  /// still to be.
  List<DateTime> get _pendingNotes => {
    ..._savedNotes,
    ...?widget.outbox?.items.map((p) => p.note.timestamp),
    ...?widget.outbox?.justSaved.map((s) => s.item.note.timestamp),
  }.toList();

  /// Shows the notes still to be saved as they change, and loads the
  /// saved ones again once more are saved -- and the actions, people or
  /// locations saved, which go through the same queue: one added from an
  /// event's picker gets what the server fills in, an action's color, say,
  /// or a location's group path.
  void _outboxChanged() {
    if (!mounted) return;
    setState(() {});
    final outbox = widget.outbox!;
    if (!outbox.wantsFetch) return;
    final saved = {for (final s in outbox.queue.justSaved) s.item.kind};
    bool any(List<WriteKind> kinds) => kinds.any((k) => saved.contains(k.name));
    final actions = any(const [WriteKind.action, WriteKind.actionGroup]);
    final people = any(const [WriteKind.person, WriteKind.circle]);
    final locations = any(const [WriteKind.location, WriteKind.locationGroup]);
    _loadNotes(
      notes: any(const [WriteKind.note]) || !(actions || people || locations),
      actions: actions,
      people: people,
      locations: locations,
    );
  }

  /// Loads the saved notes not yet compacted, after those kept from last
  /// time if [cached], and when notes were last compacted -- unless not
  /// [notes] -- and with [actions], [people] and [locations], those.
  /// Best effort: without them, they aren't marked.
  Future<void> _loadNotes({
    bool cached = false,
    bool notes = true,
    bool actions = false,
    bool people = false,
    bool locations = false,
  }) async {
    final repository = notes ? widget.notesRepository : null;
    final actionsRepository = actions ? widget.actionsRepository : null;
    final peopleRepository = people || locations
        ? PeopleScope.of(context)
        : null;
    if (repository == null &&
        actionsRepository == null &&
        peopleRepository == null) {
      return;
    }
    if (cached && repository != null) {
      await _memory.loadKept(notes: repository);
    }
    if (repository != null) {
      unawaited(
        _memory
            .loadCompaction(repository, again: true)
            .catchError((Object _) {}),
      );
    }
    // What was saved is let go of once all are in, so none shows without
    // it in the meantime.
    final fetched = widget.outbox?.fetching();
    try {
      await Future.wait([
        if (repository != null) _memory.loadNotes(repository, again: true),
        if (actionsRepository != null)
          _memory.loadActions(actionsRepository, again: true),
        if (peopleRepository != null && people)
          _memory.loadPeople(peopleRepository, again: true),
        if (peopleRepository != null && locations)
          _memory.loadLocations(peopleRepository, again: true),
      ]);
      fetched?.call();
    } catch (_) {
      // Shown as they were.
    }
  }

  /// Shows the open proposal as it was kept -- by the background fetch,
  /// say -- while [_loadProposal] asks again, unless that answers first.
  Future<void> _showKeptProposal() async {
    try {
      final kept = await widget.proposals?.cachedCurrent();
      if (!mounted || kept == null || _proposalLoaded) return;
      setState(() => _proposal = kept);
    } catch (_) {
      // Nothing kept, then.
    }
  }

  /// Back in the app: the proposal the background task kept meanwhile,
  /// shown at once if it's newer than the one shown, while it's asked for
  /// again -- not just once something else asks.
  Future<void> _resumeProposal() async {
    try {
      final kept = await widget.proposals?.cachedCurrent();
      final loaded = _loadedProposal;
      if (mounted &&
          kept != null &&
          !_closed.contains(kept.id) &&
          (loaded == null ||
              loaded.id != kept.id ||
              kept.revision > loaded.revision)) {
        setState(() => _proposal = kept);
      }
    } catch (_) {
      // Nothing kept, then.
    }
    if (mounted) unawaited(_loadProposal());
  }

  /// Loads the open compaction proposal, if there is one: the first time,
  /// what's changed since the revision the user last saw, to highlight.
  /// Best effort: without it, it's shown as it was.
  Future<void> _loadProposal() async {
    final repository = widget.proposals;
    if (repository == null) return;
    try {
      var proposal = await repository.current(sinceRevision: _since);
      if (proposal != null && proposal.id != _sinceOf) {
        _sinceOf = proposal.id;
        _since = await _seen.seen(proposal.id);
        if (_since case final since? when since < proposal.revision) {
          proposal = await repository.current(sinceRevision: since);
        }
        // Never seen: nothing's changed since. From now on, what changes
        // while it's open is.
        _since ??= proposal?.revision;
      }
      if (!mounted) return;
      _proposalLoaded = true;
      setState(() => _proposal = proposal);
    } catch (_) {
      // Shown as it was.
    }
  }

  /// Keeps the proposal's revision as seen, for next time: not one only
  /// kept, its changes not yet shown.
  void _sawProposal() {
    if (!_proposalLoaded) return;
    if (_proposal case final proposal?) {
      _seen.saw(proposal.id, proposal.revision);
    }
  }

  /// Goes back to where it was left, when the app was last open, if
  /// that's to be kept.
  Future<void> _loadPlace(EventsPlaceStore store) async {
    final place = await store.load();
    // Asked to show an event or a time meanwhile: there, not where it
    // was left.
    if (!mounted || _askedToShow) return;
    final kept = place != null && place.keptAt(widget.clock());
    setState(() {
      _placePending = false;
      if (!kept) return;
      _scale = place.scale;
      _restoreTop = place.top;
    });
    if (kept) _goToDay(place.day);
  }

  /// Keeps where it is, for [EventsPlaceStore], while the timeline's
  /// still laid out to say.
  void _savePlace() {
    _sawProposal();
    final store = widget.placeStore;
    if (store == null || _placePending || !_scroll.hasClients) return;
    store.save(
      EventsPlace(
        day: _day,
        top: timelineTime(
          _scroll.position.pixels,
          day: _from,
          dayEnd: _to,
          scale: _scale,
        ),
        scale: _scale,
        leftAt: widget.clock(),
      ),
    );
  }

  @override
  void deactivate() {
    // Before the timeline under it goes.
    _savePlace();
    super.deactivate();
  }

  /// Whether the day's summary was folded away last time. Best effort:
  /// without it, it's open.
  Future<void> _loadSummaryCollapsed() async {
    try {
      final collapsed = await SharedPreferencesAsync().getBool(
        _summaryCollapsedKey,
      );
      if (!mounted || collapsed == null) return;
      setState(() => _summaryCollapsed = collapsed);
    } catch (_) {
      // Nowhere to keep it: it's open.
    }
  }

  void _setSummaryCollapsed(bool collapsed) {
    setState(() => _summaryCollapsed = collapsed);
    try {
      SharedPreferencesAsync()
          .setBool(_summaryCollapsedKey, collapsed)
          .catchError((_) {});
    } catch (_) {
      // Nowhere to keep it: it lasts until the app closes.
    }
  }

  /// Whether the all-day strip was folded last time. Best effort:
  /// without it, it's open.
  Future<void> _loadAllDayCollapsed() async {
    try {
      final collapsed = await SharedPreferencesAsync().getBool(
        _allDayCollapsedKey,
      );
      if (!mounted || collapsed == null) return;
      setState(() => _allDayCollapsed = collapsed);
    } catch (_) {
      // Nowhere to keep it: it's open.
    }
  }

  /// Whether the weather strip was folded last time. Best effort:
  /// without it, it's open.
  Future<void> _loadWeatherCollapsed() async {
    try {
      final collapsed = await SharedPreferencesAsync().getBool(
        _weatherCollapsedKey,
      );
      if (!mounted || collapsed == null) return;
      setState(() => _weatherCollapsed = collapsed);
    } catch (_) {
      // Nowhere to keep it: it's open.
    }
  }

  void _setWeatherCollapsed(bool collapsed) {
    setState(() => _weatherCollapsed = collapsed);
    try {
      SharedPreferencesAsync()
          .setBool(_weatherCollapsedKey, collapsed)
          .catchError((_) {});
    } catch (_) {
      // Nowhere to keep it: it lasts until the app closes.
    }
  }

  /// [day]'s sunrise and sunset, to mark on its band, if the weather's
  /// shown and the forecast has the day.
  List<SunTime> _sunOn(DateTime day) {
    final weather = Weather.of(context);
    if (weather == null || !weather.enabled) return const [];
    return weather.forecast?.sunOn(day) ?? const [];
  }

  /// The weather to draw down [day]'s band, from now, if it's shown:
  /// none yet, till there's a forecast.
  List<WeatherSpan>? _weatherBand() {
    final weather = Weather.of(context);
    if (weather == null || !weather.enabled) return null;
    return switch (weather.forecast) {
      final forecast? => weatherTimeline(forecast, from: widget.clock()),
      null => const [],
    };
  }

  /// The forecast to label the band's temperatures from: from when it
  /// was fetched, so those before now stay.
  List<WeatherSpan>? _temperatures() {
    final weather = Weather.of(context);
    if (weather == null || !weather.enabled) return null;
    return switch (weather.forecast) {
      final forecast? => weatherTimeline(forecast, from: forecast.fetchedAt),
      null => null,
    };
  }

  /// Whether Google Calendar's events were over the user's last time.
  /// Best effort: without it, they're behind.
  Future<void> _loadGoogleOnTop() async {
    try {
      final onTop = await SharedPreferencesAsync().getBool(_googleOnTopKey);
      if (!mounted || onTop == null) return;
      setState(() => _googleOnTop = onTop);
    } catch (_) {
      // Nowhere to keep it: they're behind.
    }
  }

  void _setGoogleOnTop(bool onTop) {
    setState(() => _googleOnTop = onTop);
    try {
      SharedPreferencesAsync()
          .setBool(_googleOnTopKey, onTop)
          .catchError((_) {});
    } catch (_) {
      // Nowhere to keep it: it lasts until the app closes.
    }
  }

  /// Whether any day on the page -- with the box up, those stacked with
  /// it too -- has Google Calendar events, timed or all day.
  bool get _hasGoogleEvents {
    final calendars = GoogleCalendars.of(context);
    if (calendars == null || !calendars.enabled) return false;
    final (from, to) = _stacked(_day);
    for (
      var d = from;
      d.isBefore(to);
      d = DateTime(d.year, d.month, d.day + 1)
    ) {
      if (calendars.on(d).isNotEmpty) return true;
    }
    return false;
  }

  /// The button that brings Google Calendar's events over the user's
  /// own, or sends them back behind: marked while they're over.
  Widget _googleToggle() {
    final colors = Theme.of(context).colorScheme;
    return FloatingActionButton.small(
      heroTag: 'google-on-top',
      tooltip: _googleOnTop
          ? 'Put calendar events behind yours'
          : 'Bring calendar events over yours',
      onPressed: () => _setGoogleOnTop(!_googleOnTop),
      backgroundColor: _googleOnTop ? colors.primary : null,
      foregroundColor: _googleOnTop ? colors.onPrimary : null,
      // What's on top, as it is: the user's, solid, over the calendar's,
      // dotted -- or the other way round.
      child: Icon(_googleOnTop ? Icons.flip_to_back : Icons.flip_to_front),
    );
  }

  /// Whether the goals-due strip was folded last time. Best effort:
  /// without it, it's open.
  Future<void> _loadGoalsDueCollapsed() async {
    try {
      final collapsed = await SharedPreferencesAsync().getBool(
        _goalsDueCollapsedKey,
      );
      if (!mounted || collapsed == null) return;
      setState(() => _goalsDueCollapsed = collapsed);
    } catch (_) {
      // Nowhere to keep it: it's open.
    }
  }

  void _setGoalsDueCollapsed(bool collapsed) {
    setState(() => _goalsDueCollapsed = collapsed);
    try {
      SharedPreferencesAsync()
          .setBool(_goalsDueCollapsedKey, collapsed)
          .catchError((_) {});
    } catch (_) {
      // Nowhere to keep it: it lasts until the app closes.
    }
  }

  /// [goal]'s page, if there are goals to show it from.
  void _openGoal(Goal goal) {
    final repository = GoalsScope.of(context);
    if (repository == null) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => GoalScreen(
          goalId: goal.id,
          repository: repository,
          memory: _memory,
        ),
      ),
    );
  }

  /// [action], picked by holding [goal]'s overdue pill on the goals-due
  /// strip: marks it done or missed, or missed and tried again by a day
  /// picked, as its page does -- if there are goals to change.
  Future<void> _actOnOverdue(Goal goal, OverdueGoalAction action) async {
    final repository = GoalsScope.of(context);
    if (repository == null) return;
    final actions = GoalActions(
      context: context,
      repository: repository,
      memory: _memory,
      now: widget.clock,
    );
    switch (action) {
      case OverdueGoalAction.done:
        await actions.setStatus(goal, 'done');
      case OverdueGoalAction.missed:
        await actions.setStatus(goal, 'missed');
      case OverdueGoalAction.retry:
        await actions.retry(goal);
    }
  }

  void _setAllDayCollapsed(bool collapsed) {
    setState(() => _allDayCollapsed = collapsed);
    try {
      SharedPreferencesAsync()
          .setBool(_allDayCollapsedKey, collapsed)
          .catchError((_) {});
    } catch (_) {
      // Nowhere to keep it: it lasts until the app closes.
    }
  }

  /// Whether the day's summary showed durations last time. Best effort:
  /// without it, it shows percentages.
  Future<void> _loadSummaryDurations() async {
    try {
      final durations = await SharedPreferencesAsync().getBool(
        _summaryDurationsKey,
      );
      if (!mounted || durations == null) return;
      setState(() => _summaryDurations = durations);
    } catch (_) {
      // Nowhere to keep it: percentages.
    }
  }

  void _setSummaryDurations(bool durations) {
    setState(() => _summaryDurations = durations);
    try {
      SharedPreferencesAsync()
          .setBool(_summaryDurationsKey, durations)
          .catchError((_) {});
    } catch (_) {
      // Nowhere to keep it: it lasts until the app closes.
    }
  }

  @override
  void dispose() {
    _memory.removeListener(_memoryChanged);
    _lifecycle.dispose();
    _loads.unbind();
    widget.proposalProblem?.clear();
    if (widget.loads == null) _loads.dispose();
    widget.outbox?.removeListener(_outboxChanged);
    widget.eventOutbox?.removeListener(_memoryChanged);
    widget.eventOutbox?.notices?.removeListener(_memoryChanged);
    _savedWrites?.cancel();
    _showEvents?.cancel();
    _showTimes?.cancel();
    _unhighlight?.cancel();
    _pages.dispose();
    _scroll.dispose();
    super.dispose();
  }

  /// The day on [page].
  DateTime _dayAt(int page) => DateTime(
    _firstDay.year,
    _firstDay.month,
    _firstDay.day + page - _firstPage,
  );

  /// The page [day] is on.
  int _pageOf(DateTime day) =>
      _firstPage +
      DateTime.utc(day.year, day.month, day.day)
          .difference(
            DateTime.utc(_firstDay.year, _firstDay.month, _firstDay.day),
          )
          .inDays;

  /// Loads the actions, for their colors: those kept from last time,
  /// then the server's. Best effort: without them, actions are named as
  /// the events have them, with outlined diamonds.
  Future<void> _loadActions() async {
    final repository = widget.actionsRepository;
    if (repository == null) return;
    try {
      await _memory.loadKept(actions: repository);
      await _memory.loadActions(repository, again: true);
    } catch (_) {
      // Shown as they were.
    }
  }

  DateTime get _dayEnd => _dayAfter(_day);

  /// The days on the timeline, while the box is up: the day shown, with
  /// the day before it stacked above, and the day after below -- to make
  /// or move events across midnight. Otherwise, just the day shown.
  (DateTime, DateTime) _stacked(DateTime day) => _box == null
      ? (day, _dayAfter(day))
      : (
          DateTime(day.year, day.month, day.day - 1),
          DateTime(day.year, day.month, day.day + 2),
        );

  /// Puts the box up, or away ([box] null): the day before stacked
  /// above the day shown, or taken away, the timeline scrolled to keep
  /// what's on screen where it is.
  void _setBox(PendingEventBox? box) {
    final was = _box != null;
    _box = box;
    if (box == null) _logging = null;
    final stacked = box != null;
    // A box comes up with its lists' buttons tucked away.
    if (stacked != was) _listsShown = false;
    if (stacked == was || !_scroll.hasClients) return;
    final before = DateTime(_day.year, _day.month, _day.day - 1);
    final by = _day.difference(before).inMinutes * _scale;
    final pixels = _scroll.position.pixels;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.jumpTo(
        (pixels + (stacked ? by : -by)).clamp(
          0,
          _scroll.position.maxScrollExtent,
        ),
      );
    });
  }

  /// Where the days stacked on the timeline start, and end.
  DateTime get _from => _stacked(_day).$1;
  DateTime get _to => _stacked(_day).$2;

  /// How far down the timeline [time] is, on the days stacked on it.
  double _offset(DateTime time) =>
      timelineOffset(time, day: _from, dayEnd: _to, scale: _scale);

  /// Scrolls the timeline to where it was left, if it's going back
  /// there, or else to now, on today, or else to the first event, once
  /// it's laid out.
  void _scrollToStart() {
    final events = _shown;
    if (!_scrollPending || _placePending) return;
    if (_restoreTop case final top?) {
      _scrollPending = false;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_scroll.hasClients) return;
        final y = _offset(top);
        _scroll.jumpTo(y.clamp(0, _scroll.position.maxScrollExtent));
      });
      return;
    }
    if (events == null) return;
    _scrollPending = false;
    final now = widget.clock();
    final starts = [
      for (final e in events)
        if (e.end.isAfter(_day)) e.start.isBefore(_day) ? _day : e.start,
    ]..sort();
    final today = sameDay(now, _day);
    final at = today ? now : starts.firstOrNull ?? _day;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      final y = _offset(at) - (today ? 120 : 24);
      _scroll.jumpTo(y.clamp(0, _scroll.position.maxScrollExtent));
    });
  }

  /// Shows today, scrolled so now is a fifth of the way down.
  void _goToNow() {
    final now = widget.clock();
    final today = _midnight(now);
    if (today != _day) _goToDay(today);
    // Once it's laid out on today.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      final position = _scroll.position;
      final (from, to) = _stacked(today);
      final y =
          timelineOffset(now, day: from, dayEnd: to, scale: _scale) -
          position.viewportDimension / 5;
      _scroll.jumpTo(y.clamp(0, position.maxScrollExtent));
    });
    setState(() {});
  }

  /// Zooms to [next], keeping the time [focus] down the screen (the
  /// middle, by default) where it is.
  void _zoomTo(double next, {double? focus}) {
    next = next.clamp(timelineScales.first, timelineScales.last);
    if (next == _scale) return;
    if (_scroll.hasClients) {
      final position = _scroll.position;
      final at = focus ?? position.viewportDimension / 2;
      final pad = _offset(_from);
      // From where an earlier zoom this frame will put it, if one will.
      final from = _scrollTo ?? position.pixels;
      final first = _scrollTo == null;
      _scrollTo = (from + at - pad) * next / _scale + pad - at;
      // Once it's laid out at the new zoom, so it can scroll that far.
      if (first) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          final target = _scrollTo;
          _scrollTo = null;
          if (!_scroll.hasClients || target == null) return;
          _scroll.jumpTo(target.clamp(0, _scroll.position.maxScrollExtent));
        });
      }
    }
    setState(() => _scale = next);
  }

  void _pointerDown(PointerDownEvent event) {
    _pointers[event.pointer] = event.localPosition;
    if (_pointers.length == 2) {
      final [a, b] = _pointers.values.toList();
      setState(() => _pinch = (distance: (a - b).distance, scale: _scale));
    }
  }

  void _pointerMove(PointerMoveEvent event) {
    if (!_pointers.containsKey(event.pointer)) return;
    _pointers[event.pointer] = event.localPosition;
    final pinch = _pinch;
    if (pinch == null || _pointers.length < 2 || pinch.distance < 1) return;
    final [a, b, ...] = _pointers.values.toList();
    _zoomTo(
      pinch.scale * (a - b).distance / pinch.distance,
      focus: (a.dy + b.dy) / 2,
    );
  }

  void _pointerUp(PointerEvent event) {
    _pointers.remove(event.pointer);
    if (_pointers.length >= 2 || _pinch == null) return;
    setState(() => _pinch = null);
    // A drag just before the pinch may have left the days part-way across.
    if (_pages.hasClients) {
      final page = _pages.page ?? _pageOf(_day).toDouble();
      if ((page - page.round()).abs() > 0.001) {
        _pages.animateToPage(
          _pageOf(_day),
          duration: _slide,
          curve: Curves.easeOut,
        );
      }
    }
  }

  static DateTime _midnight(DateTime t) {
    final local = t.toLocal();
    return DateTime(local.year, local.month, local.day);
  }

  static DateTime _dayAfter(DateTime day) =>
      DateTime(day.year, day.month, day.day + 1);

  /// Shows the days the app kept from its last run, unless the server
  /// answered first.
  Future<void> _showCached() async {
    await _store.restored();
    if (mounted) setState(() {});
  }

  /// Loads [day]'s events, the day shown's by default. Only the day
  /// shown's errors are shown; another day's is loaded again when it is.
  Future<void> _load([DateTime? day]) async {
    final which = day ?? _day;
    final asked = _store.clock();
    try {
      final events = await widget.repository.events(which, _dayAfter(which));
      if (!mounted) return;
      _store.putDay(which, events, asked: asked);
      setState(() {
        _fresh.add(which);
        if (which == _day) {
          _loads.loaded();
          _needsSignIn = false;
        }
      });
    } on SignInRequiredException {
      if (!mounted || which != _day) return;
      _loads.reset();
      setState(() {
        _fresh.remove(which);
        _needsSignIn = true;
      });
    } catch (e) {
      if (!mounted || which != _day) return;
      // Tried again by itself; with events shown, the status bar says so.
      _loads.failed(e, hasData: _shown?.isNotEmpty ?? false);
      setState(() {
        // Signed in: without that it's SignInRequiredException.
        _needsSignIn = false;
      });
    }
  }

  /// Loads the day shown, unless not to [reloadShown], then in the
  /// background the days either side that the server hasn't answered for.
  Future<void> _refresh({bool reloadShown = true}) async {
    final day = _day;
    if (reloadShown) await _load(day);
    if (!mounted || _needsSignIn || day != _day) return;
    for (final other in [
      _dayAfter(day),
      DateTime(day.year, day.month, day.day - 1),
    ]) {
      if (!_fresh.contains(other)) unawaited(_load(other));
    }
  }

  /// Shows [day], on its page and as the day shown. Sliding to a page
  /// says which it's on ([_show]), but a jump before the days are laid
  /// out -- as when a tap on the home screen calendar starts the app --
  /// only takes effect as they are, saying nothing, so the day shown is
  /// set here too. Before they're built at all (signing in), they start
  /// there.
  void _goToDay(DateTime day) {
    if (_pages.hasClients) {
      _pages.jumpToPage(_pageOf(day));
    } else if (_pages.initialPage != _pageOf(day)) {
      _pages.dispose();
      _pages = PageController(initialPage: _pageOf(day));
    }
    _show(day);
  }

  /// Shows [day], the page slid to: at once if it's loaded, loading it
  /// again if it may be out of date, and the days either side if they
  /// aren't loaded. Days well away from it are let go.
  void _show(DateTime day) {
    if (day == _day) return;
    setState(() {
      if (_box case final box?) {
        final cursor = box.cursor;
        _box = box.movedTo(
          DateTime(day.year, day.month, day.day, cursor.hour, cursor.minute),
        );
      }
      // A note being placed goes along too, at the same time of day.
      if (_noteAt case final at?) {
        _noteAt = DateTime(day.year, day.month, day.day, at.hour, at.minute);
      }
      _day = day;
      _loads.reset();
      _fresh.removeWhere((d) => (_pageOf(d) - _pageOf(day)).abs() > 3);
      if (_box case final box?) _keep(box, moved: true);
    });
    _refresh(reloadShown: !_fresh.contains(day));
    // If it's old by now.
    Weather.read(context)?.refresh();
  }

  /// Opens [event]'s summary, and from it, its details.
  Future<void> _openEvent(Event event) async {
    if (_saidReadOnly()) return;
    if (_inReview(event)) return _openReviewed(event);
    final outcome = await showEventSummaryDialog(
      context,
      event,
      // What a proposal adds, named by its ref until it's made.
      additions: _proposal?.additions ?? const [],
      save: (changes) => _approvingHistory(
        at: event.start,
        (allow) => _writes.update(event, changes, allowHistory: allow),
      ),
      cancel: _waitingOn(event).isNotEmpty
          ? null
          : (counts) => _approvingHistory(
              at: event.start,
              (allow) => _writes.cancel(
                event,
                countsAgainstFollowThrough: counts,
                allowHistory: allow,
              ),
            ),
      waiting: _waitingOn(event),
      otherEvents: _otherEvents(event),
      actions: _actionsById,
      loadActions: _actions,
      openSeries: (seriesId) => _openSeries(seriesId, event),
      repeatable: true,
    );
    if (!mounted) return;
    switch (outcome) {
      case SummarySaved(:final value):
        await _saved(event, value);
      case SummaryDetails():
        await _openEventDetails(event);
      case null:
    }
  }

  /// Opens [event], one in what the open proposal says happened, as
  /// [_openEvent] does, its changes and its cancelling edits of the
  /// proposal. One the proposal cancels can be put back as planned.
  Future<void> _openReviewed(Event event) async {
    if (event.isCancelled) return _openCancelled(event);
    Proposal? amended;
    final outcome = await showEventSummaryDialog(
      context,
      event,
      // What a proposal adds, named by its ref until it's made.
      additions: _proposal?.additions ?? const [],
      save: (changes) async {
        amended = await _amend(
          ProposalEdits(updates: [proposalUpdate(event, changes)]),
          label: 'Change ${_named(event)}, in what happened',
        );
        return const [];
      },
      cancel: _waitingOn(event).isNotEmpty
          ? null
          : (counts) async {
              amended = await _amend(
                ProposalEdits(
                  cancels: [
                    (eventId: event.id!, countsAgainstFollowThrough: counts),
                  ],
                ),
                label: 'Cancel ${_named(event)}, in what happened',
              );
              return const [];
            },
      waiting: _waitingOn(event),
      otherEvents: _otherEvents(event),
      actions: _actionsById,
      loadActions: _actions,
    );
    if (!mounted) return;
    switch (outcome) {
      case SummarySaved():
        _amended(amended!, 'Changed in what happened, to confirm.');
      case SummaryDetails():
        await _openReviewedDetails(event);
      case null:
    }
  }

  /// Opens every one of [event]'s properties, as [_openEventDetails]
  /// does, for one in what the open proposal says happened: its changes
  /// edit the proposal.
  Future<void> _openReviewedDetails(Event event) async {
    Proposal? amended;
    final updated = await showEventDialog(
      context,
      event,
      save: (event, changes) async {
        amended = await _amend(
          ProposalEdits(updates: [proposalUpdate(event, changes)]),
          label: 'Change ${_named(event)}, in what happened',
        );
        return const [];
      },
      cancel: _waitingOn(event).isNotEmpty
          ? null
          : (event, counts) async {
              amended = await _amend(
                ProposalEdits(
                  cancels: [
                    (eventId: event.id!, countsAgainstFollowThrough: counts),
                  ],
                ),
                label: 'Cancel ${_named(event)}, in what happened',
              );
              return const [];
            },
      waiting: _waitingOn(event),
      otherEvents: _otherEvents(event),
      actions: _actions,
    );
    if (updated != null && mounted) {
      _amended(amended!, 'Changed in what happened, to confirm.');
    }
  }

  /// Shows [event], which the open proposal says didn't happen: when, who
  /// said so, and whether it counts against follow-through, and against
  /// whom -- to say otherwise, put it back as planned, or ask Claude about.
  Future<void> _openCancelled(Event event) async {
    final proposed = _proposal?.event(event.id);
    if (proposed == null) return;
    final choice = await showCancelledDialog(
      context,
      proposed,
      // Saved as the switch is turned, the dialog staying open.
      setCounts: (counts) async {
        final amended = await _amend(
          ProposalEdits(
            cancels: [
              (eventId: proposed.id, countsAgainstFollowThrough: counts),
            ],
          ),
        );
        return amended.event(proposed.id);
      },
    );
    if (!mounted) return;
    switch (choice) {
      case AskAboutCancel():
        await _noteForClaude(about: proposed.id);
      case PutBack():
        await runOrShowError(
          context,
          title: "Couldn't put it back",
          action: () async {
            final amended = await _amend(
              ProposalEdits(asPlanned: [proposed.id]),
            );
            if (mounted) _amended(amended, 'Put back as planned.');
          },
        );
      case null:
    }
  }

  /// Records [edits] to the open proposal, as the user's, and shows its
  /// new revision. If they're refused -- they'd overlap, say -- loads it
  /// again and rethrows, the edits left where they were made, as a draft.
  Future<Proposal> _amend(ProposalEdits edits, {String? label}) async {
    final proposal = _proposal;
    final repository = widget.proposals;
    if (proposal == null || repository == null) {
      throw StateError('No proposal is open.');
    }
    if (movesRevisited(edits, proposal) case final e?) {
      throw McpException(
        '“${e.summary ?? '(no summary)'}” is an earlier event a historical note '
        'revisits: what happened at it can change here, but not when. '
        'Change its times on the calendar once this is confirmed.',
      );
    }
    // Asked now, if it changes what a compaction settled; one the app
    // can't tell is refused, and asked then (below, or from the changes
    // waiting).
    var allowHistory = false;
    if (changesHistory(edits, proposal)) {
      if (await _approveHistory() != true) throw const HistoryKept();
      allowHistory = true;
    }
    if (_writes.queued) {
      // Shown as made (see _proposal), till it's saved.
      final amended = await _writes.amend(
        _loadedProposal!,
        edits,
        label: label,
        allowHistory: allowHistory,
      );
      if (mounted) setState(() {});
      return amended;
    }
    try {
      Proposal amended;
      try {
        amended = await _writes.amend(
          proposal,
          edits,
          label: label,
          allowHistory: allowHistory,
        );
      } catch (e) {
        if (allowHistory || !isHistoryRefusal(e) || !mounted) rethrow;
        if (await _approveHistory() != true) rethrow;
        amended = await _writes.amend(
          proposal,
          edits,
          label: label,
          allowHistory: true,
        );
      }
      if (mounted) {
        setState(() {
          _editedHere
            ..addAll(edits.eventIds)
            // The keys of the events they made.
            ..addAll({
              for (final e in amended.events ?? const <ProposalEvent>[])
                if (proposal.event(e.id) == null) e.id,
            });
          _proposal = amended.copyWith(changedSince: proposal.changedSince);
        });
      }
      return amended;
    } catch (_) {
      unawaited(_loadProposal());
      rethrow;
    }
  }

  /// Says [said] of an edit to the proposal that made [amended], and
  /// which of Claude's newer changes it replaced.
  void _amended(Proposal amended, String said) {
    final replaced = [
      for (final id in amended.replaced)
        switch (amended.event(id)?.summary) {
          final s? when s.isNotEmpty => '“$s”',
          _ => 'an event',
        },
    ];
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          replaced.isEmpty
              ? said
              : "$said It replaced Claude's newer change to "
                    '${replaced.join(', ')}.',
        ),
      ),
    );
  }

  /// Every event loaded, but [event], for keeping its times clear of: in
  /// what an open proposal says happened, as it says.
  OtherEvents _otherEvents(Event? event) {
    final from = DateTime(_day.year, _day.month, _day.day - 3);
    final to = DateTime(_day.year, _day.month, _day.day + 4);
    return OtherEvents(
      {
        for (final e in _withProposal(
          _waiting(_store.between(from, to), from, to),
          from,
          to,
        ))
          e.id ?? e: e,
      }.values,
      except: event?.id,
    );
  }

  /// [time] on the nearest line of the grid set in [AppSettings].
  DateTime _onGrid(DateTime time) =>
      snapToGrid(time, AppSettings.of(context).grid);

  /// Starts making a new event: a cursor across the day shown, at now if
  /// that's today, or else the middle of what's in view.
  void _startCreating([DateTime? from]) {
    if (_saidReadOnly()) return;
    final now = widget.clock();
    DateTime at;
    if (from != null) {
      at = from;
    } else if (!now.isBefore(_day) && now.isBefore(_dayEnd)) {
      at = now;
    } else if (_scroll.hasClients) {
      final middle = _scroll.offset + _scroll.position.viewportDimension / 2;
      at = timelineTime(middle, day: _from, dayEnd: _to, scale: _scale);
    } else {
      at = _day.add(const Duration(hours: 9));
    }
    final cursor = _onGrid(at);
    setState(() {
      _clearLists();
      _keepByRules(from: cursor, to: cursor);
      _selected = CursorRole.anchor;
      _setBox(PendingEventBox(cursor));
    });
  }

  /// Starts placing a new note: its cursor in the middle of what's in
  /// view -- on today too, not at now.
  void _startNoting() {
    final at = _scroll.hasClients
        ? timelineTime(
            _scroll.offset + _scroll.position.viewportDimension / 2,
            day: _from,
            dayEnd: _to,
            scale: _scale,
          )
        : _day.add(const Duration(hours: 9));
    setState(() => _noteAt = _onGrid(at));
  }

  /// The event the note's cursor is in -- from its start up to its end --
  /// to ring while it's placed; the latest started, where they overlap.
  Event? get _noteInside {
    final at = _noteAt;
    if (at == null) return null;
    return _otherEvents(null).events
        .where((e) => !e.start.isAfter(at) && e.end.isAfter(at))
        .lastOrNull;
  }

  /// The note's cursor, dragged to [to]: where it stops.
  void _moveNoteCursor(DateTime to) =>
      setState(() => _noteAt = _snap(to, CursorRole.note));

  /// Where the note's cursor steps to, [later] or earlier: its next stop,
  /// if it has one.
  DateTime? _noteStep({required bool later}) {
    final at = _noteAt;
    if (at == null) return null;
    return _stops(CursorRole.note).next(at, later: later);
  }

  /// Opens the New note sheet at the note's cursor; the cursor's put
  /// away once the note's kept, or stays if the sheet's dismissed.
  Future<void> _addNoteAtCursor() async {
    final at = _noteAt;
    final outbox = widget.outbox;
    if (at == null || outbox == null || newNoteSheetOpen) return;
    final note = await showAddNoteDialog(
      context,
      keep: outbox.add,
      drafts: widget.noteDrafts,
      time: at,
      clock: widget.clock,
    );
    if (note != null && mounted) setState(() => _noteAt = null);
  }

  /// The day shown's events, in order, for J and K to step through.
  List<Event> _steppable() => [
    for (final e in _eventsOn(_day) ?? const <Event>[])
      if (e.end.isAfter(_day) && e.start.isBefore(_dayEnd)) e,
  ]..sort((a, b) => a.start.compareTo(b.start));

  /// The event J and K have stepped to, if it's on the day shown.
  Event? get _keyedEvent =>
      _steppable().where((e) => e.id == _keyed).firstOrNull;

  /// Steps the highlight to the next event, [later], or the one before:
  /// from the one happening now, on today, at first. Past the day's
  /// first or last, onto the day before or after.
  void _stepEvent({required bool later}) {
    final events = _steppable();
    final at = events.indexWhere((e) => e.id == _keyed);
    Event? next;
    if (at >= 0) {
      final i = at + (later ? 1 : -1);
      if (i >= 0 && i < events.length) next = events[i];
    } else if (events.isNotEmpty) {
      final now = widget.clock();
      next = !now.isBefore(_day) && now.isBefore(_dayEnd)
          ? events.lastWhere(
              (e) => !e.start.isAfter(now) && e.end.isAfter(now),
              orElse: () => events.firstWhere(
                (e) => e.start.isAfter(now),
                orElse: () => events.last,
              ),
            )
          : later
          ? events.first
          : events.last;
    }
    if (next != null) return _keyTo(next);
    _keyedOnto = later;
    _goToDay(later ? _dayEnd : DateTime(_day.year, _day.month, _day.day - 1));
    _keyOnto();
  }

  /// Once the day stepped onto has its events, highlights its first or
  /// last -- not the one stepped from, running across midnight.
  void _keyOnto() {
    final later = _keyedOnto;
    if (later == null || _eventsOn(_day) == null) return;
    _keyedOnto = null;
    final events = [
      for (final e in _steppable())
        if (e.id != _keyed) e,
    ];
    if (events.isEmpty) {
      setState(() => _keyed = null);
      return;
    }
    _keyTo(later ? events.first : events.last);
  }

  /// Highlights [event], scrolled into view if it isn't.
  void _keyTo(Event event) {
    setState(() => _keyed = event.id);
    if (!_scroll.hasClients) return;
    final position = _scroll.position;
    final start = event.start.isBefore(_day) ? _day : event.start;
    final y = _offset(start);
    final view = position.viewportDimension;
    if (y >= position.pixels + 24 && y <= position.pixels + view - 96) return;
    _scroll.animateTo(
      (y - view / 3).clamp(0, position.maxScrollExtent),
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeInOut,
    );
  }

  /// Scrolls the timeline by the arrow keys' step
  /// ([AppSettings.keyScroll]), [later] or earlier.
  void _scrollByKey({required bool later}) {
    if (!_scroll.hasClients) return;
    final position = _scroll.position;
    final by = AppSettings.of(context).keyScroll.inMinutes * _scale;
    _scroll.animateTo(
      (position.pixels + (later ? by : -by)).clamp(0, position.maxScrollExtent),
      duration: const Duration(milliseconds: 150),
      curve: Curves.easeOut,
    );
  }

  /// J or K: with the box up, its cursor -- the one picked, once there
  /// are two -- to its next stop; or else the highlight, to the next
  /// event.
  void _keyStep({required bool later}) {
    if (_noteAt != null) {
      final to = _noteStep(later: later);
      if (to != null) setState(() => _noteAt = to);
      return;
    }
    final box = _box;
    if (box == null) return _stepEvent(later: later);
    final role = box.other == null ? CursorRole.anchor : _selected;
    if (_canStep(role, later: later)) _stepCursor(role, later: later);
  }

  /// Home or End ([last]): highlights the day's first event, or its
  /// last -- not while a cursor is out, which J and K move.
  void _keyEnd({required bool last}) {
    if (_box != null) return;
    final events = _steppable();
    if (events.isEmpty) return;
    _keyTo(last ? events.last : events.first);
  }

  /// Enter: with just the one cursor, sets the start, making the box to
  /// the next stop after it, for J and K to move its end; with the box,
  /// goes on, as ✓ does. Picking events, picks the one highlighted; or
  /// else opens it.
  void _keyEnter() {
    if (_noteAt != null) {
      unawaited(_addNoteAtCursor());
      return;
    }
    final box = _box;
    if (box != null) {
      if (box.other == null) {
        if (_canStep(CursorRole.end, later: true)) {
          _stepCursor(CursorRole.end, later: true);
        }
        return;
      }
      _continueAction?.call();
      return;
    }
    final event = _keyedEvent;
    if (event == null) return;
    if (_selecting != null) return _pick(event);
    _openEvent(event);
  }

  /// Esc: leaves the top mode, as ✕ does, or else lets go of the
  /// highlight.
  void _keyEscape() {
    if (_modes.isNotEmpty) return _leaveMode();
    setState(() => _keyed = null);
  }

  /// What ✓ does: with just the one cursor and events on the cancel
  /// list, cancels them; or else makes -- or moves -- the event between
  /// the cursors; null while there's none, or it runs into an event to
  /// keep.
  VoidCallback? get _continueAction {
    if (_cursorCancels.isNotEmpty) return _cancelAtCursor;
    final blocked = _effectOf(_box)?.blocked ?? false;
    if (_box?.span == null || blocked) return null;
    return _moving != null ? _finishMoving : _continueCreating;
  }

  /// The Events page's hotkeys.
  List<HotkeyBinding> get _hotkeys => [
    HotkeyBinding(
      const HotkeyTrigger.key(LogicalKeyboardKey.keyJ),
      () => _keyStep(later: true),
    ),
    HotkeyBinding(
      const HotkeyTrigger.key(LogicalKeyboardKey.keyK),
      () => _keyStep(later: false),
    ),
    HotkeyBinding(
      const HotkeyTrigger.key(LogicalKeyboardKey.home),
      () => _keyEnd(last: false),
    ),
    HotkeyBinding(
      const HotkeyTrigger.key(LogicalKeyboardKey.end),
      () => _keyEnd(last: true),
    ),
    HotkeyBinding(const HotkeyTrigger.key(LogicalKeyboardKey.enter), _keyEnter),
    HotkeyBinding(
      const HotkeyTrigger.key(LogicalKeyboardKey.escape),
      _keyEscape,
    ),
    HotkeyBinding(
      const HotkeyTrigger.key(LogicalKeyboardKey.keyH),
      () => _goToDay(DateTime(_day.year, _day.month, _day.day - 1)),
    ),
    HotkeyBinding(
      const HotkeyTrigger.key(LogicalKeyboardKey.keyL),
      () => _goToDay(_dayEnd),
    ),
    HotkeyBinding(
      const HotkeyTrigger.key(LogicalKeyboardKey.arrowUp),
      () => _scrollByKey(later: false),
    ),
    HotkeyBinding(
      const HotkeyTrigger.key(LogicalKeyboardKey.arrowDown),
      () => _scrollByKey(later: true),
    ),
    HotkeyBinding(const HotkeyTrigger.key(LogicalKeyboardKey.keyT), _goToNow),
    for (final key in const [LogicalKeyboardKey.keyC, LogicalKeyboardKey.add])
      HotkeyBinding(HotkeyTrigger.key(key), () {
        if (_box != null || _selecting != null || _noteAt != null) return;
        _startCreating(_keyedEvent?.end);
      }),
  ];

  /// What a new event logged from [event] starts with: its title,
  /// description, and where, as its map location.
  Map<String, Object?> _loggedFields(GoogleEvent event) => {
    'summary': event.title,
    if (event.description case final about? when about.trim().isNotEmpty)
      'description': descriptionText(about),
    if (event.location case final where? when where.trim().isNotEmpty)
      'location': where.trim(),
  };

  /// Shows [event], from Google Calendar; logged, the box goes up
  /// across its times, to make an event of the user's own there.
  Future<void> _openGoogleEvent(GoogleEvent event) async {
    final choice = await showGoogleEventSheet(context, event);
    if (!mounted) return;
    if (choice == GoogleEventChoice.open) {
      final calendars = GoogleCalendars.of(context);
      if (!(await calendars?.source.open(event) ?? false) && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Couldn't open it in a calendar app")),
        );
      }
      return;
    }
    if (choice != GoogleEventChoice.log || _saidReadOnly()) return;
    setState(() {
      _clearLists();
      _keepByRules(from: event.start, to: event.end);
      _selected = CursorRole.anchor;
      _setBox(PendingEventBox(event.start, other: event.end));
      _logging = event;
    });
  }

  /// Starts moving [event]: the box around it, pushing the events in its
  /// way to start with.
  void _startMoving(Event event) {
    if (event.isCancelled || _saidReadOnly()) return;
    setState(() {
      _moving = event;
      _commutes.clear();
      _setBox(PendingEventBox(event.start, other: event.end));
      _clearLists();
      _keepByRules(from: event.start, to: event.end, except: event.id);
      _pushCommutes(event);
      _selected = CursorRole.anchor;
    });
  }

  /// Puts the commutes right before [event] in the Push up list, and right
  /// after it in Push down, so they go where it goes.
  void _pushCommutes(Event event) {
    final ways = _commuteActionIds;
    for (final e in _otherEvents(event).events) {
      if (!_isCommute(e, ways)) continue;
      final list = e.end == event.start
          ? EventList.pushUp
          : e.start == event.end
          ? EventList.pushDown
          : null;
      if (list == null || e.id == null) continue;
      _lists[EventList.keep]!.remove(e.id!);
      _lists[list]!.set({..._lists[list]!.ids, e.id!});
    }
  }

  /// [span], stretched over the new commutes queued at its ends.
  (DateTime, DateTime) _withCommutes((DateTime, DateTime) span) => (
    switch (_commutes[true]) {
      (event: null, fields: final f?) => span.$1.subtract(f.length),
      _ => span.$1,
    },
    switch (_commutes[false]) {
      (event: null, fields: final f?) => span.$2.add(f.length),
      _ => span.$2,
    },
  );

  /// The ids of the actions that are ways to commute.
  Set<String> get _commuteActionIds => {
    for (final a in _memory.shownActions?.actions ?? const <PlanAction>[])
      if (a.commute && a.id != null) a.id!,
  };

  /// Whether [event] is a commute: said to be one, or done by one of the
  /// [ways] to commute.
  static bool _isCommute(Event event, Set<String> ways) =>
      event.isCommute || event.actionIds.any(ways.contains);

  /// The events other than [moving] wholly before [span] -- for its
  /// [top] -- or after it, nearest first.
  List<Event> _beyond(bool top, Event moving, (DateTime, DateTime) span) {
    final (start, end) = span;
    final events = [
      for (final e in _otherEvents(moving).events)
        if (top ? !e.end.isAfter(start) : !e.start.isBefore(end)) e,
    ];
    if (top) events.sort((a, b) => b.end.compareTo(a.end));
    return events;
  }

  /// The place at the edge of [event] -- one beyond the box's [top] or
  /// foot, or the moved event itself ([own]) -- that faces the other: an
  /// event before the box's last place, say. Null if it has none, so
  /// it's unknown.
  static String? _edgePlace(
    Event event, {
    required bool top,
    bool own = false,
  }) {
    final ids = event.facts?.locationIds ?? const <String>[];
    if (ids.isEmpty) return null;
    return top != own ? ids.last : ids.first;
  }

  /// Where a commute at the box's [top] or foot is from and to -- the
  /// place at the moved event's edge, and at the nearest event's that
  /// way, past one commute -- each null if unknown; and the commute to
  /// edit there, if there's one: the nearest that way, past only events
  /// at the moved event's place. Null while no event's being moved.
  _CommutePlace? _commuteAt(bool top) {
    final event = _moving;
    final span = _box?.span;
    if (event == null || span == null) return null;
    final ways = _commuteActionIds;
    final hereId = _edgePlace(event, top: top, own: true);
    final beyond = _beyond(top, event, span);
    var next = beyond.firstOrNull;
    if (next != null && _isCommute(next, ways)) {
      next = beyond.elementAtOrNull(1);
      if (next != null && _isCommute(next, ways)) next = null;
    }
    final thereId = next == null ? null : _edgePlace(next, top: top);
    Event? commute;
    for (final e in beyond) {
      if (_isCommute(e, ways)) {
        if (e.id != null) commute = e;
        break;
      }
      final ids = e.facts?.locationIds ?? const <String>[];
      if (hereId == null || ids.isEmpty || ids.any((id) => id != hereId)) {
        break;
      }
    }
    return (
      fromId: top ? thereId : hereId,
      toId: top ? hereId : thereId,
      commute: commute,
    );
  }

  /// The ends with a commute button: each, unless the event next to it
  /// isn't a commute and is at the moved event's place -- known, and the
  /// same.
  Set<bool> get _commuteEnds {
    final event = _moving;
    final span = _box?.span;
    if (event == null || span == null) return const {};
    final ways = _commuteActionIds;
    bool samePlace(bool top) {
      final next = _beyond(top, event, span).firstOrNull;
      if (next == null || _isCommute(next, ways)) return false;
      final here = _edgePlace(event, top: top, own: true);
      return here != null && here == _edgePlace(next, top: top);
    }

    return {
      for (final top in const [true, false])
        if (!samePlace(top)) top,
    };
  }

  /// The commute button at the box's [top] or foot: asks which way to go
  /// -- or for no commute -- then, for a way, its summary and how long
  /// it takes, and queues that for the commute there, or a new one.
  Future<void> _commute(bool top) async {
    final at = _commuteAt(top);
    if (at == null) return;
    final memory = _memory;
    final choices = commuteChoices(
      fromId: at.fromId,
      toId: at.toId,
      actions: memory.shownActions?.actions ?? const [],
      travelTimes: memory.travelTimes ?? const [],
      locations: memory.locations ?? const [],
      groups: memory.locationGroups ?? const [],
    );
    final picked = await _pickCommute(
      at,
      choices,
      removable: at.commute != null || _commutes.containsKey(top),
    );
    if (picked == null || !mounted) return;
    if (picked is! CommuteChoice) {
      return setState(() {
        if (at.commute case final commute?) {
          _commutes[top] = (event: commute, fields: null);
          _listCommute(commute, null);
        } else {
          _commutes.remove(top);
        }
      });
    }
    final action = picked.action;
    final name = action.name ?? action.id!;
    final suggested = switch (picked.option) {
      final o? => Duration(minutes: o.minutes),
      null => null,
    };
    // Started from what's queued for the same commute, or the one there
    // as it is.
    final queued = switch (_commutes[top]) {
      (:final event, fields: final f?) when event?.id == at.commute?.id => f,
      _ => null,
    };
    final base =
        queued ??
        switch (at.commute) {
          final c? => (
            summary: c.summary ?? '',
            actionIds: c.actionIds,
            length: c.end.difference(c.start),
          ),
          null => null,
        };
    final _CommuteFields start;
    if (base == null) {
      start = (
        summary: name,
        actionIds: [action.id!],
        length: suggested ?? Duration.zero,
      );
    } else {
      final way = base.actionIds.where(_commuteActionIds.contains).firstOrNull;
      start = (
        summary: way != null && base.summary == _actionName(way)
            ? name
            : base.summary,
        actionIds: way == null
            ? [action.id!, ...base.actionIds.where((id) => id != action.id)]
            : [
                for (final id in base.actionIds)
                  if (id == way) action.id! else if (id != action.id) id,
              ],
        length: suggested ?? base.length,
      );
    }
    final route = _route(at);
    final fields = await showCommuteDialog(
      context,
      title: name,
      summary: start.summary,
      length: start.length,
      help: switch ((route, picked.option)) {
        (final r?, final o?) => '$r: ${_commuteTime(o)}',
        _ => route,
      },
    );
    if (fields == null || !mounted) return;
    setState(() {
      _commutes[top] = (
        event: at.commute,
        fields: (
          summary: fields.summary,
          actionIds: start.actionIds,
          length: fields.length,
        ),
      );
      if (at.commute case final commute?) {
        _listCommute(commute, top ? EventList.pushUp : EventList.pushDown);
      }
    });
  }

  /// Puts [commute] in [list] alone of the lists, or in none.
  void _listCommute(Event commute, EventList? list) {
    final id = commute.id!;
    for (final MapEntry(:key, :value) in _lists.entries) {
      if (key == list) {
        value.set({...value.ids, id});
      } else {
        value.remove(id);
      }
    }
  }

  /// An action's name, by id.
  String? _actionName(String id) =>
      (_memory.shownActions?.actions ?? const <PlanAction>[])
          .where((a) => a.id == id)
          .firstOrNull
          ?.name;

  /// A location's or a location group's name, by id.
  String _placeName(String id) =>
      _memory.locations?.where((l) => l.id == id).firstOrNull?.name ??
      _memory.locationGroups?.where((g) => g.id == id).firstOrNull?.name ??
      id;

  /// "The cafe to The office", "To The office" or "From The cafe", as
  /// far as [at]'s places are known; null if neither is.
  String? _route(_CommutePlace at) => switch ((at.fromId, at.toId)) {
    (final from?, final to?) => '${_placeName(from)} to ${_placeName(to)}',
    (null, final to?) => 'To ${_placeName(to)}',
    (final from?, null) => 'From ${_placeName(from)}',
    _ => null,
  };

  /// How long [option] takes: "25m", or "25m (20m–30m)" when it varies.
  static String _commuteTime(CommuteOption option) =>
      option.time.maxMinutes == null
      ? formatMinutes(option.minutes)
      : '${formatMinutes(option.minutes)} (${option.time.describe})';

  /// Which way to go, for [at], of [choices]: the one picked,
  /// [_noCommute] for none -- offered if there's one to take away,
  /// [removable] -- or null.
  Future<Object?> _pickCommute(
    _CommutePlace at,
    List<CommuteChoice> choices, {
    required bool removable,
  }) {
    final from = at.fromId == null ? '' : ' from ${_placeName(at.fromId!)}';
    final to = at.toId == null ? '' : ' to ${_placeName(at.toId!)}';
    return showModalBottomSheet<Object>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            ListTile(
              title: Text('Edit commute$from$to'),
              subtitle: Text(switch (at.commute) {
                final c? =>
                  'Changes ${c.summary ?? 'the commute there'}, pushed '
                      'with the move.',
                null =>
                  'Made with the move, against its edge, and pushed with '
                      'it.',
              }),
            ),
            for (final choice in choices)
              ListTile(
                leading: const Icon(Icons.directions_walk),
                title: Text(choice.action.name ?? choice.action.id!),
                subtitle: Text(switch (choice.option) {
                  final o? => _travelUsed(o),
                  null => 'No travel time',
                }),
                trailing: switch (choice.option) {
                  final o? => Text(formatMinutes(o.minutes)),
                  null => null,
                },
                onTap: () => Navigator.of(context).pop(choice),
              ),
            if (removable)
              ListTile(
                leading: const Icon(Icons.block),
                title: const Text('No commute'),
                subtitle: Text(switch (at.commute) {
                  final c? =>
                    '${c.summary ?? 'The commute'} is taken away with the '
                        'move.',
                  null => 'None made with the move.',
                }),
                onTap: () => Navigator.of(context).pop(_noCommute),
              ),
          ],
        ),
      ),
    );
  }

  /// What [_pickCommute] gives back for no commute.
  static const _noCommute = #noCommute;

  /// The travel time [option] goes by: "The cafe ↔ Downtown · 20m–30m",
  /// "→" for one that goes one way, and the way it's by, if that's a
  /// group of the way picked.
  String _travelUsed(CommuteOption option) {
    final travel = option.travel;
    final by = option.time.modeId == option.action.id
        ? ''
        : ' by ${_actionName(option.time.modeId) ?? option.time.modeId}';
    return '${_placeName(travel.fromId)} ${travel.oneWay ? '→' : '↔'} '
        '${_placeName(travel.toId)} · ${option.time.describe}$by';
  }

  /// The new commutes queued, as `create_event` takes them, against
  /// [span]'s ends.
  List<Map<String, Object?>> _commuteCreates((DateTime, DateTime) span) => [
    for (final MapEntry(key: top, value: c) in _commutes.entries)
      if (c case (event: null, fields: final f?))
        {
          'summary': f.summary,
          'start': localIsoTimestamp(
            top ? span.$1.subtract(f.length) : span.$2,
          ),
          'end': localIsoTimestamp(top ? span.$1 : span.$2.add(f.length)),
          'action_ids': f.actionIds,
          'facts': const Facts(commute: true).toJson(),
        },
  ];

  /// What the commute [edit] at the box's [top] or foot makes of the one
  /// there, before it's pushed: its summary as edited, and its length,
  /// the edge facing the box kept. Null if it's taken away.
  static Event? _edited(bool top, _CommuteEdit edit) {
    final event = edit.event!;
    final fields = edit.fields;
    if (fields == null) return null;
    return Event(
      id: event.id,
      summary: fields.summary,
      start: top ? event.end.subtract(fields.length) : event.start,
      end: top ? event.end : event.start.add(fields.length),
      isCancelled: event.isCancelled,
      properties: event.properties,
    );
  }

  /// The events other than [moving], with the commutes edited at the
  /// box's ends as they're edited, and those taken away gone.
  OtherEvents _movingOthers(Event? moving) {
    final others = _otherEvents(moving);
    final edited = <String, Event?>{
      for (final MapEntry(key: top, value: c) in _commutes.entries)
        ?c.event?.id: _edited(top, c),
    };
    if (edited.isEmpty) return others;
    return OtherEvents([
      for (final e in others.events)
        if (!edited.containsKey(e.id)) e else ?edited[e.id],
    ]);
  }

  /// [over], with each commute edited at the box's ends changed as it's
  /// edited -- and to where it's pushed, if it is -- and each taken away
  /// cancelled.
  Overwrite _withCommuteEdits(Overwrite over) {
    final edits = {
      for (final MapEntry(key: top, value: c) in _commutes.entries)
        ?c.event?.id: (top, c),
    };
    if (edits.isEmpty) return over;
    final done = {for (final e in over.cancels) e.id};
    Map<String, Object?> changes(Event was, _CommuteFields f, Event now) => {
      if (now.start != was.start) 'start': localIsoTimestamp(now.start),
      if (now.end != was.end) 'end': localIsoTimestamp(now.end),
      if (f.summary != was.summary) 'summary': f.summary,
      if (!_sameIds(f.actionIds, was.actionIds)) 'action_ids': f.actionIds,
    };
    final updates = <(Event, Map<String, Object?>)>[];
    for (final (e, fields) in over.updates) {
      final edit = edits[e.id]?.$2;
      if (edit == null) {
        updates.add((e, fields));
        continue;
      }
      done.add(e.id);
      final now = Event(
        start: switch (fields['start']) {
          final String s => DateTime.parse(s),
          _ => e.start,
        },
        end: switch (fields['end']) {
          final String s => DateTime.parse(s),
          _ => e.end,
        },
      );
      final change = changes(edit.event!, edit.fields!, now);
      if (change.isNotEmpty) updates.add((edit.event!, change));
    }
    final cancels = [...over.cancels];
    for (final MapEntry(key: id, value: (top, edit)) in edits.entries) {
      if (done.contains(id)) continue;
      final now = _edited(top, edit);
      if (now == null) {
        cancels.add(edit.event!);
        continue;
      }
      final change = changes(edit.event!, edit.fields!, now);
      if (change.isNotEmpty) updates.add((edit.event!, change));
    }
    return Overwrite(
      cancels: cancels,
      updates: updates,
      creates: over.creates,
      countsAgainst: over.countsAgainst,
    );
  }

  /// Whether each of [updates] -- an event and its changes -- leaves room
  /// for the minutes its goals and actions take; if one doesn't, says
  /// which, and that their shares need changing first: the app never
  /// shortens an event below what its shares take.
  Future<bool> _goalsFit(
    Iterable<(Event, Map<String, Object?>)> updates,
  ) async {
    final problems = <String>[];
    for (final (event, changes) in updates) {
      final (goals, actions) = (event.goals, event.actionShares);
      if (goals.isEmpty && actions.every((a) => a.whole)) continue;
      DateTime at(String key, DateTime was) => switch (changes[key]) {
        final String s => DateTime.parse(s),
        _ => was,
      };
      final minutes = at(
        'end',
        event.end,
      ).difference(at('start', event.start)).inMinutes;
      if (shareProblems(goals, minutes).isNotEmpty) {
        problems.add(
          '${_named(event)} would be ${formatMinutes(minutes)}, but its '
          'goals take more of it than that.',
        );
      }
      if (shareProblems(actions, minutes, kind: 'action').isNotEmpty) {
        problems.add(
          '${_named(event)} would be ${formatMinutes(minutes)}, but its '
          'actions take more of it than that.',
        );
      }
    }
    if (problems.isEmpty) return true;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Its shares don't fit"),
        content: Text(
          '${problems.join('\n')}\n\nChange how much of it its goals or '
          'actions take first, then shorten it.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
    return false;
  }

  /// Whether [a] and [b] are the same ids, in the same order.
  static bool _sameIds(List<String> a, List<String> b) =>
      a.length == b.length &&
      [for (var i = 0; i < a.length; i++) a[i] == b[i]].every((same) => same);

  /// Puts in the Keep list what the rules in [AppSettings] pick, for a box
  /// from [from] to [to], [except] the event being edited.
  void _keepByRules({
    required DateTime from,
    required DateTime to,
    String? except,
  }) => _lists[EventList.keep]!.set(
    keepByRules(
      AppSettings.of(context).keepRules,
      _otherEvents(null).events,
      from: from,
      to: to,
      lastCompaction: _lastCompaction,
      actions: _actionsById,
      except: except,
    ),
  );

  /// Empties the lists, and stops picking for one.
  void _clearLists() {
    for (final list in _lists.values) {
      list.set(const []);
    }
    _selecting = null;
  }

  /// Puts the box away -- the new event or the move done, or dropped.
  void _endBox() => setState(() {
    _clearLists();
    _setBox(null);
    _moving = null;
    _commutes.clear();
  });

  /// Saves the move of [_moving] to the box, and what it does to the
  /// events in its way, in one batch.
  Future<void> _finishMoving() async {
    final event = _moving;
    final span = _box?.span;
    if (event == null || span == null) return;
    final (start, end) = span;
    if (start == event.start && end == event.end && _commutes.isEmpty) {
      return _endBox();
    }
    // Room made for the commutes too, as they ride with the box.
    final (top, foot) = _withCommutes(span);
    final makingRoom = _overwritesAny
        ? _overwrite(_movingOthers(event), top, foot)
        : const Overwrite();
    final commutes = _commuteCreates(span);
    final editing = _commutes.values.any((c) => c.event != null);
    final adding = switch ((commutes.length, editing)) {
      (0, false) => '',
      (0, true) => ', changing its commute',
      (1, false) => ', adding a commute',
      (_, false) => ', adding commutes',
      _ => ', adding and changing commutes',
    };
    // Shortening an event below what its goals take is refused here,
    // before anything's asked: the box stays up, as it was.
    if (!await _goalsFit([
      (
        event,
        {'start': localIsoTimestamp(start), 'end': localIsoTimestamp(end)},
      ),
      ..._withCommuteEdits(makingRoom).updates,
    ])) {
      return;
    }
    if (!mounted) return;
    final asked = await askFollowThrough(context, makingRoom.cancels);
    // Called off: the box stays up, as it was.
    if (asked == null || !mounted) return;
    final inTheWay = makingRoom.counting(asked);
    // The commutes edited, as they're edited: not asked about, as
    // they're the move's own.
    final writing = _withCommuteEdits(inTheWay);
    final messenger = ScaffoldMessenger.of(context);
    final times = {
      'start': localIsoTimestamp(start),
      'end': localIsoTimestamp(end),
    };
    // In what happened, to confirm: the proposal's changed.
    final review = _inReview(event) || _reviews(start, end);
    var changed = const <Event>[];
    Proposal? amended;
    try {
      if (review) {
        amended = await _amend(
          ProposalEdits.over(
            writing,
            updates: [proposalUpdate(event, times)],
            creates: [for (final c in commutes) proposalCreate(c)],
          ),
          label: 'Move ${_named(event)}$adding, in what happened',
        );
      } else {
        changed = await _approvingHistory(
          at: start.isBefore(event.start) ? start : event.start,
          (allow) => _writes.makeRoom(
            Overwrite(
              updates: [(event, times), ...writing.updates],
              cancels: writing.cancels,
              creates: [...writing.creates, ...commutes],
              countsAgainst: writing.countsAgainst,
            ),
            allowHistory: allow,
            label: inTheWay.isEmpty
                ? 'Move ${_named(event)}$adding'
                : 'Move ${_named(event)}$adding, changing '
                      '${_events(inTheWay.count)}',
          ),
        );
      }
    } catch (e) {
      // The box is still up, as it was: try again from it.
      if (mounted) {
        await showErrorSheet(
          context,
          title: "Couldn't move it",
          error: e,
          onRetry: _finishMoving,
        );
      }
      return;
    }
    if (!mounted) return;
    _endBox();
    final others = inTheWay.count;
    if (amended != null) {
      return _amended(
        amended,
        others == 0
            ? 'Moved in what happened, to confirm.'
            : 'Moved in what happened, to confirm. ${_events(others)} '
                  'changed to make room.',
      );
    }
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          others == 0
              ? 'Event moved.'
              : 'Event moved. ${_events(others)} changed to make room.',
        ),
      ),
    );
    _putEvents(changed);
    _fresh.clear();
    // The proposal is planned from the calendar as it is now.
    unawaited(_loadProposal());
    await _refresh();
  }

  /// [box], unless it -- or what it pushes -- would run into an event to
  /// keep: then the box as it was.
  PendingEventBox _kept(
    PendingEventBox box, {
    bool moved = false,
    bool fromOther = false,
  }) {
    if (_effectOf(box)?.blocked ?? false) return _box ?? box;
    return box;
  }

  /// What [box] does to the events in its way, as the lists say; null if
  /// it's no box yet.
  BoxEffect? _effectOf(PendingEventBox? box) => switch (box?.span) {
    final span? => BoxEffect(
      _movingOthers(_moving),
      start: _withCommutes(span).$1,
      end: _withCommutes(span).$2,
      lists: _listIds,
    ),
    null => null,
  };

  /// Whether the box goes later from its cursor: the way it pushes.
  bool get _later => switch (_box) {
    PendingEventBox(:final cursor, other: final other?) => other.isAfter(
      cursor,
    ),
    _ => true,
  };

  /// Changes the box to what [change] makes of it, kept in free time
  /// (see [_kept]).
  void _changeBox(
    PendingEventBox Function(PendingEventBox box) change, {
    bool moved = false,
    bool fromOther = false,
  }) {
    final box = _box;
    if (box == null) return;
    setState(() => _keep(change(box), moved: moved, fromOther: fromOther));
  }

  /// Makes the box [box], unless an event to keep's in the way (see
  /// [_kept]).
  void _keep(
    PendingEventBox box, {
    bool moved = false,
    bool fromOther = false,
  }) => _box = _kept(box, moved: moved, fromOther: fromOther);

  /// Scrolls the new event into the middle of the view.
  void _goToBox() {
    final box = _box;
    if (box == null || !_scroll.hasClients) return;
    final position = _scroll.position;
    final at = box.span == null
        ? box.cursor
        : box.span!.$1.add(box.length ~/ 2);
    final y = _offset(at) - position.viewportDimension / 2;
    _scroll.animateTo(
      y.clamp(0, position.maxScrollExtent),
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeInOut,
    );
  }

  /// Whether [fields] move [event] whole, its length kept: pushing it.
  static bool _moves(Event event, Map<String, Object?> fields) =>
      switch ((fields['start'], fields['end'])) {
        (final String s, final String e) =>
          DateTime.parse(e).difference(DateTime.parse(s)) ==
              event.end.difference(event.start),
        _ => false,
      };

  /// Whether the new event takes time from events already there: cuts
  /// one short, or cancels one.
  bool get _overwrites {
    final effect = _effectOf(_box);
    if (effect == null) return false;
    final pushed = {for (final p in effect.pushed) p.$1};
    final o = effect.overwrite;
    return o.cancels.isNotEmpty || o.updates.any((u) => !pushed.contains(u.$1));
  }

  /// Where the events the new one pushes go, up or down, and the rest of
  /// the one it was started in, pushed.
  List<PushedEvent> get _pushed => [
    if (_box?.span case final span?)
      for (final MapEntry(key: top, value: c) in _commutes.entries)
        if (c case (event: null, fields: final f?))
          (
            start: top ? span.$1.subtract(f.length) : span.$2,
            end: top ? span.$1 : span.$2.add(f.length),
            label: '${f.summary} (commute)',
          ),
    for (final (event, from, to, rest)
        in _effectOf(_box)?.pushed ??
            const <(Event, DateTime, DateTime, bool)>[])
      (
        start: from,
        end: to,
        label: rest
            ? '${event.summary ?? 'Event'} (the rest)'
            : event.summary ?? 'Event',
      ),
  ];

  /// What the shadow covers: the box, and every event in its way it
  /// cancels, whole. Null otherwise: just the box.
  (DateTime, DateTime)? get _covers {
    final span = _box?.span;
    final effect = _effectOf(_box);
    if (span == null || effect == null) return null;
    final (top, foot) = effect.span;
    final cancels = [
      for (final e in effect.overwrite.cancels)
        if (e.start.isBefore(foot) && e.end.isAfter(top)) e,
    ];
    if (cancels.isEmpty) return null;
    return (
      [
        span.$1,
        for (final e in cancels) e.start,
      ].reduce((a, b) => a.isBefore(b) ? a : b),
      [
        span.$2,
        for (final e in cancels) e.end,
      ].reduce((a, b) => a.isAfter(b) ? a : b),
    );
  }

  /// What an event from [start] to [end] does to the [others] in its
  /// way, as the lists say ([BoxEffect]).
  Overwrite _overwrite(
    OtherEvents others,
    DateTime start,
    DateTime end, {
    bool? later,
  }) => BoxEffect(others, start: start, end: end, lists: _listIds).overwrite;

  /// How near, on screen, a dragged cursor has to come to an edge or a
  /// note to stop there.
  static const _snapReach = 12.0;

  /// What [role]'s cursor stops at: the grid set in [AppSettings], and --
  /// as it snaps to them -- the edges of the events shown and the notes.
  CursorStops _stops(CursorRole role) {
    final settings = AppSettings.of(context);
    final snap = settings.snapFor(role);
    return CursorStops(
      from: _from,
      to: _to,
      grid: settings.grid,
      edges: snap.contains(SnapTo.events)
          ? [
              for (final e in _otherEvents(_moving).events) ...[e.start, e.end],
            ]
          : const [],
      notes: snap.contains(SnapTo.notes)
          ? [..._pendingNotes, for (final n in _proposalNotes) n.time]
          : const [],
    );
  }

  /// Whether a cursor that's up -- the box's, or the end of the window
  /// being extended -- stops at [snap].
  bool _snapsTo(SnapTo snap) {
    final settings = AppSettings.of(context);
    return (_box != null &&
            (settings.snapFor(CursorRole.anchor).contains(snap) ||
                settings.snapFor(CursorRole.end).contains(snap))) ||
        (_extendTo != null &&
            settings.snapFor(CursorRole.windowEnd).contains(snap)) ||
        (_noteAt != null && settings.snapFor(CursorRole.note).contains(snap));
  }

  /// Whether the proposal's window can be extended: it's being reviewed,
  /// nothing else is up, and there's time since it ends.
  bool get _canExtend => switch (_shownProposal) {
    final p? =>
      p.state == ProposalState.awaitingReview &&
          !_proposalBusy &&
          _box == null &&
          _extendTo == null &&
          _noteAt == null &&
          p.through.isBefore(widget.clock()),
    null => false,
  };

  /// Starts extending the proposal's window: its end's cursor, where it
  /// ends now.
  void _startExtending() =>
      setState(() => _extendTo = _proposal!.through.toLocal());

  /// [time], kept where the window can be extended to: from where it ends
  /// now to now.
  DateTime _inExtensible(DateTime time) {
    final from = _proposal!.through;
    final now = widget.clock();
    if (time.isBefore(from)) return from;
    return time.isAfter(now) ? now : time;
  }

  /// Where the window's end steps to, [later] or earlier: its next stop,
  /// if that's where it can be extended to.
  DateTime? _extensionStep({required bool later}) {
    final at = _extendTo;
    if (at == null) return null;
    final to = _stops(CursorRole.windowEnd).next(at, later: later);
    if (to == null || _inExtensible(to) != to) return null;
    return to;
  }

  /// The window's end, dragged to [to]: where it stops, and can be.
  void _moveExtension(DateTime to) => setState(
    () => _extendTo = _inExtensible(_snap(to, CursorRole.windowEnd)),
  );

  /// The window's end's settings: its time. What it stops at is set in
  /// Settings, for every cursor.
  Future<void> _openExtension() async {
    await showCursorSheet(
      context,
      title: 'The end of what happened',
      onEditTime: () async {
        final proposal = _proposal;
        final at = _extendTo;
        if (proposal == null || at == null) return;
        final picked = await showEditTimeDialog(
          context,
          title: 'The end of what happened',
          initial: at,
          day: _day,
          first: proposal.through,
          last: widget.clock(),
        );
        if (picked != null && mounted) {
          setState(() => _extendTo = _inExtensible(picked));
        }
      },
    );
  }

  /// Extends the proposal's window to its end's cursor: the notes it
  /// takes in added where they fall.
  Future<void> _extend() async {
    final to = _extendTo;
    if (to == null) return;
    setState(() => _extendTo = null);
    final time = MaterialLocalizations.of(context)
        .formatTimeOfDay(TimeOfDay.fromDateTime(to.toLocal()));
    await runOrShowError(
      context,
      title: "Couldn't extend it",
      action: () async {
        final amended = await _amend(
          ProposalEdits(through: to),
          label: 'Extend what happened to $time',
        );
        if (mounted) {
          _amended(
            amended,
            'What happened now runs to $time, to confirm: its notes there '
            'are added where they fall.',
          );
        }
      },
    );
  }

  /// Where [role]'s cursor, dragged to [to], stops: at an edge or a note
  /// it snaps to, if it's near one, or else on the grid.
  DateTime _snap(DateTime to, CursorRole role) => _stops(
    role,
  ).nearest(to, reach: Duration(seconds: (_snapReach / _scale * 60).round()));

  /// Where [role]'s cursor steps to, [later] or earlier: its next stop,
  /// if there is one and it doesn't reach, or pass, the other cursor.
  /// Before there's an end, the end's step makes it, from the anchor.
  DateTime? _stepTo(CursorRole role, {required bool later}) {
    final box = _box;
    if (box == null) return null;
    final anchor = role == CursorRole.anchor;
    final from = anchor ? box.cursor : box.other ?? box.cursor;
    final to = _stops(role).next(from, later: later);
    if (to == null) return null;
    final other = anchor ? box.other : box.cursor;
    // The same moment, whether in UTC, as the server's, or local.
    if (other != null && !other.isAtSameMomentAs(from)) {
      final towards = other.isAfter(from) == later;
      if (towards && (later ? !to.isBefore(other) : !to.isAfter(other))) {
        return null;
      }
    }
    return to;
  }

  /// Whether [role]'s cursor can step [later], or earlier: to a stop, and
  /// not so the box -- or what it pushes -- runs into an event to keep.
  bool _canStep(CursorRole role, {required bool later}) {
    final box = _box;
    final to = _stepTo(role, later: later);
    if (box == null || to == null) return false;
    final stepped = role == CursorRole.anchor
        ? box.withCursor(to)
        : box.withOther(to);
    return !(_effectOf(stepped)?.blocked ?? false);
  }

  /// [role]'s cursor stepped to its next stop, [later] or earlier.
  void _stepCursor(CursorRole role, {required bool later}) {
    final to = _stepTo(role, later: later);
    if (to == null) return;
    setState(() => _selected = role);
    if (role == CursorRole.anchor) {
      _changeBox((box) => box.withCursor(to), fromOther: true);
    } else {
      _changeBox((box) => box.withOther(to));
    }
  }

  /// Opens the new event, as shaded between the cursors.
  Future<void> _continueCreating() async {
    final span = _box?.span;
    if (span == null) return;
    final (start, end) = span;
    final others = _otherEvents(_moving);
    final overwrite = _overwritesAny;
    final later = _later;
    final inTheWay = _overwrite(others, start, end);
    var cleared = false;
    // In what happened, to confirm: made in the proposal.
    final review = _reviews(start, end);
    Proposal? amended;
    Overwrite inTheWayOf(Map<String, Object?> fields) => _overwrite(
      others,
      DateTime.parse(fields['start'] as String),
      DateTime.parse(fields['end'] as String),
      later: later,
    );

    // Asked of what it cancels; called off, the dialog stays open.
    Future<Overwrite> askedInTheWayOf(Map<String, Object?> fields) async {
      final over = inTheWayOf(fields);
      final asked = await askFollowThrough(context, over.cancels);
      if (asked == null) throw const CalledOff();
      return over.counting(asked);
    }

    final logging = _logging;
    final logged = logging == null ? const {} : _loggedFields(logging);
    // Where it most likely is: where the user was before it, or is going
    // -- unless it's logged from somewhere that says.
    final where = logged.containsKey('location')
        ? const <String>[]
        : others.likelyLocationIds(start);
    final created = await showNewEventDialog(
      context,
      start: start,
      end: end,
      initial: {
        ...logged,
        if (where.isNotEmpty) 'facts': Facts(locationIds: where).toJson(),
      },
      // Overwriting, its times needn't keep clear of anything.
      otherEvents: overwrite ? const OtherEvents.none() : others,
      create: review
          ? (fields) async {
              amended = await _amend(
                ProposalEdits.over(
                  overwrite ? await askedInTheWayOf(fields) : const Overwrite(),
                  creates: [proposalCreate(fields)],
                ),
                label: 'Add ${_nameOf(fields)}, to what happened',
              );
              return const [];
            }
          : overwrite
          ? (fields) async {
              final over = await askedInTheWayOf(fields);
              return _approvingHistory(
                at: start,
                (allow) =>
                    _writes.createOver(fields, over, allowHistory: allow),
              );
            }
          : _writes.create,
      // Overwriting events, the trash makes no new event, but just
      // clears the time of them.
      clear: !overwrite || inTheWay.isEmpty
          ? null
          : (
              question: switch (_clearing(inTheWay)) {
                _Clearing.cancels => 'Cancel ${_events(inTheWay.count)}?',
                _Clearing.pushes =>
                  'Make room, changing ${_events(inTheWay.count)}?',
                _Clearing.trims =>
                  'Clear this time of ${_events(inTheWay.count)}?',
              },
              explanation: switch (_clearing(inTheWay)) {
                _Clearing.cancels =>
                  'Every event the new one touches is cancelled, and no '
                      'new event is made.',
                _Clearing.pushes =>
                  'The events in the way are pushed along, as the new one '
                      'would push them, and no new event is made.',
                _Clearing.trims =>
                  'The events under the new one are trimmed out of this '
                      'time, and no new event is made.',
              },
              label: switch (_clearing(inTheWay)) {
                _Clearing.cancels => 'Cancel them',
                _Clearing.pushes => 'Make room',
                _Clearing.trims => 'Clear the time',
              },
              run: () async {
                if (!await _goalsFit(inTheWay.updates)) {
                  throw const CalledOff();
                }
                if (!mounted) throw const CalledOff();
                final asked = await askFollowThrough(context, inTheWay.cancels);
                if (asked == null) throw const CalledOff();
                final over = inTheWay.counting(asked);
                cleared = true;
                if (review) {
                  amended = await _amend(
                    ProposalEdits.over(over),
                    label: 'Clear time in what happened',
                  );
                  return const [];
                }
                return _approvingHistory(
                  at: start,
                  (allow) => _writes.makeRoom(
                    over,
                    allowHistory: allow,
                    label: 'Clear time of ${_events(inTheWay.count)}',
                  ),
                );
              },
            ),
      actions: _actionsById,
      loadActions: _actions,
      // What a proposal adds, named by its ref until it's made.
      additions: review ? _proposal?.additions ?? const [] : const [],
      // A proposal's events don't repeat.
      repeatable: !review,
    );
    if (created == null || !mounted) return;
    _endBox();
    if (amended case final amended?) {
      return _amended(
        amended,
        cleared
            ? 'Time cleared in what happened, to confirm: '
                  '${_events(inTheWay.count)} changed.'
            : 'Added to what happened, to confirm.',
      );
    }
    final changed = _writes.queued ? inTheWay.count : created.length - 1;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          cleared
              ? 'Time cleared: ${_events(inTheWay.count)} changed.'
              : changed <= 0
              ? 'Event created.'
              : 'Event created. $changed other '
                    'event${changed == 1 ? '' : 's'} changed to make room.',
        ),
      ),
    );
    _putEvents(created);
    _fresh.clear();
    unawaited(_loadProposal());
    await _refresh();
    await _loadActions();
  }

  /// "3 events", or "1 event".
  static String _events(int count) => '$count event${count == 1 ? '' : 's'}';

  /// What clearing the time does, mostly: only cancels, pushes some
  /// along, or else trims.
  _Clearing _clearing(Overwrite o) => o.updates.isEmpty && o.creates.isEmpty
      ? _Clearing.cancels
      : o.creates.isNotEmpty || o.updates.any((u) => _moves(u.$1, u.$2))
      ? _Clearing.pushes
      : _Clearing.trims;

  /// [list]'s button: its icon, round, with a dot while it has events in
  /// it; tapped, picking events for it.
  Widget _listButton(EventList list) => _dotted(
    FloatingActionButton.small(
      heroTag: 'list-${list.name}',
      tooltip: '${list.label}: pick events to ${list.verb}',
      onPressed: () => _startSelecting(list),
      child: Icon(list.icon),
    ),
    dot: !_lists[list]!.isEmpty,
  );

  /// The button that shows the lists' buttons, or hides them: marked
  /// while they're out, with a dot while any list has events in it.
  Widget _listsToggle() {
    final colors = Theme.of(context).colorScheme;
    return _dotted(
      FloatingActionButton.small(
        heroTag: 'lists',
        tooltip: _listsShown ? 'Hide the lists' : 'Show the lists',
        onPressed: () => setState(() => _listsShown = !_listsShown),
        backgroundColor: _listsShown ? colors.primary : null,
        foregroundColor: _listsShown ? colors.onPrimary : null,
        child: const Icon(Icons.checklist),
      ),
      dot: _lists.values.any((l) => !l.isEmpty),
    );
  }

  /// [button], with a dot at its top right if [dot].
  Widget _dotted(Widget button, {required bool dot}) => Stack(
    clipBehavior: Clip.none,
    children: [
      button,
      if (dot)
        Positioned(
          right: 2,
          top: 2,
          child: Semantics(
            label: 'Has events',
            child: Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.error,
                shape: BoxShape.circle,
              ),
            ),
          ),
        ),
    ],
  );

  /// Starts picking events for [list]: a tap on one picks it, or unpicks
  /// it; ✓ keeps what's picked, and ✕ or back puts the lists back.
  void _startSelecting(EventList list) {
    for (final l in _lists.values) {
      l.begin();
    }
    setState(() => _selecting = list);
  }

  /// Stops picking: what was picked [kept], or put back as it was; the
  /// lists' buttons tucked away again.
  void _endSelecting({required bool kept}) {
    for (final l in _lists.values) {
      kept ? l.commit() : l.revert();
    }
    setState(() {
      _selecting = null;
      _listsShown = false;
    });
  }

  /// [event], tapped while picking: picked for the list being picked for
  /// -- out of any other -- or unpicked. Not the event being moved: that's
  /// the box.
  void _pick(Event event) {
    final list = _selecting;
    final id = event.id;
    if (list == null || id == null || id == _moving?.id) return;
    for (final MapEntry(:key, :value) in _lists.entries) {
      if (key != list) value.remove(id);
    }
    setState(() => _lists[list]!.toggle(id));
  }

  /// Each event in a list, by id, with its list's icon.
  Map<String, IconData> get _listed => {
    for (final MapEntry(:key, :value) in _lists.entries)
      for (final id in value.ids) id: key.icon,
  };

  /// What a cursor at [time] is on: the starts and ends of the events
  /// there, and the notes.
  List<SnapMark> _marksAt(DateTime time) {
    final events = _otherEvents(_moving).events;
    String name(Event e) => switch (e.summary) {
      final s? when s.trim().isNotEmpty => s.trim(),
      _ => 'an event',
    };
    // The end of what's before above the start of what's after, as they
    // are on the timeline.
    return [
      for (final e in events)
        if (e.end.isAtSameMomentAs(time)) (what: 'end', name: name(e)),
      for (final e in events)
        if (e.start.isAtSameMomentAs(time)) (what: 'start', name: name(e)),
      for (final (at, text) in _noteTexts)
        if (at.isAtSameMomentAs(time)) (what: 'note', name: text),
    ];
  }

  /// The notes not yet compacted, and the proposal's, each with its time
  /// and text.
  List<(DateTime, String)> get _noteTexts => [
    for (final n in _memory.notes ?? const <Note>[])
      (n.timestamp, n.description ?? ''),
    ...?widget.outbox?.items.map(
      (p) => (p.note.timestamp, p.note.description ?? ''),
    ),
    for (final n in _proposalNotes) (n.time, n.text ?? ''),
  ];

  /// The modes the page is in, first entered first: placing a cursor --
  /// left as soon as there's a box -- or creating or editing an event;
  /// extending the compaction window.
  List<EventsMode> get _modes => [
    if (_box case final box?)
      _moving != null
          ? EventsMode.edit
          : box.span == null
          ? EventsMode.placeCursor
          : EventsMode.create,
    if (_extendTo != null) EventsMode.extend,
    if (_noteAt != null) EventsMode.placeNote,
    if (_selecting case final list?)
      EventsMode(list.icon, 'Select events to ${list.verb}'),
  ];

  /// Leaves the top mode -- as ✕ does -- undoing what was done in it.
  void _leaveMode() {
    if (_selecting != null) {
      _endSelecting(kept: false);
    } else if (_noteAt != null) {
      setState(() => _noteAt = null);
    } else if (_extendTo != null) {
      setState(() => _extendTo = null);
    } else if (_box != null) {
      _endBox();
    }
  }

  /// The events to cancel with ✓ while there's just the one cursor: the
  /// cancel list's, there being no box to do it with.
  List<Event> get _cursorCancels => switch (_box) {
    PendingEventBox(other: null) when _moving == null => [
      for (final e in _otherEvents(null).events)
        if (_lists[EventList.cancel]!.contains(e.id)) e,
    ],
    _ => const [],
  };

  /// With just the one cursor, cancels the cancel list's events, asked
  /// which count against follow-through -- in what happened, if the
  /// cursor's in the proposal's window.
  Future<void> _cancelAtCursor() async {
    final cancels = _cursorCancels;
    final at = _box?.cursor;
    if (at == null || cancels.isEmpty) return;
    final asked = await askFollowThrough(context, cancels, makingRoom: false);
    // Called off: the cursor stays, as it was.
    if (asked == null || !mounted) return;
    final over = Overwrite(cancels: cancels).counting(asked);
    final label = 'Cancel ${_events(cancels.length)}';
    final said = 'Cancelled ${_events(cancels.length)}';
    try {
      if (_reviews(at, at.add(const Duration(minutes: 1)))) {
        final amended = await _amend(
          ProposalEdits.over(over),
          label: '$label, in what happened',
        );
        if (!mounted) return;
        _endBox();
        return _amended(amended, '$said, in what happened.');
      }
      final changed = await _approvingHistory(
        at: cancels.map((e) => e.start).reduce((a, b) => a.isBefore(b) ? a : b),
        (allow) => _writes.makeRoom(over, allowHistory: allow, label: label),
      );
      if (!mounted) return;
      _endBox();
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('$said.')));
      _putEvents(changed);
      _fresh.clear();
      await _refresh();
    } catch (e) {
      if (mounted) {
        await showErrorSheet(context, title: "Couldn't cancel them", error: e);
      }
    }
  }

  /// Whether a cursor at [time] is inside an event, cutting it.
  bool _cutsAt(DateTime time) => _otherEvents(_moving).inside(time) != null;

  /// Asks for [role]'s cursor's time, its date and time of day, and puts
  /// it there.
  Future<void> _editTime(CursorRole role) async {
    final box = _box;
    if (box == null) return;
    final anchor = role == CursorRole.anchor;
    final picked = await showEditTimeDialog(
      context,
      title: switch ((anchor, box.cursorOnTop)) {
        _ when box.span == null => "The cursor's time",
        (true, true) || (false, false) => 'The top of the event',
        _ => 'The bottom of the event',
      },
      initial: anchor ? box.cursor : box.other ?? box.cursor,
      day: _day,
      first: _from,
      last: _to,
    );
    if (picked == null || !mounted) return;
    setState(() => _selected = role);
    if (anchor) {
      _changeBox((box) => box.withCursor(picked), fromOther: true);
    } else {
      _changeBox((box) => box.withOther(picked));
    }
  }

  /// Runs [change] -- and if the server refuses it because it changes
  /// history (an event compaction settled), asks the user, and runs it
  /// again allowing that if they agree. Otherwise rethrows the refusal.
  Future<List<Event>> _approvingHistory(
    Future<List<Event>> Function(bool allowCompactedChanges) change, {
    DateTime? at,
  }) async {
    if (_writes.queued) {
      // Asked now, of a change from [at], as the server will only say so
      // once it's sent: refused then, it's asked from the changes waiting.
      final compacted = _memory.lastCompaction;
      final history = at != null && compacted != null && at.isBefore(compacted);
      if (!history) return change(false);
      if (await _approveHistory() != true) throw const HistoryKept();
      return change(true);
    }
    try {
      return await change(false);
    } catch (e) {
      if (!isHistoryRefusal(e) || !mounted) rethrow;
      final approved = await _approveHistory();
      if (approved != true) rethrow;
      return change(true);
    }
  }

  /// Asks whether to change history: an event compaction recorded.
  Future<bool?> _approveHistory() => showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Change history?'),
      content: const Text(
        'Compaction has already recorded this event as what happened. '
        'Changing it rewrites that record.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Keep history'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Change it'),
        ),
      ],
    ),
  );

  /// What of [event] waits for a change to be saved: the fields it sets,
  /// or, for all of it, [allWaiting].
  Set<String> _waitingOn(Event event) {
    final id = event.id;
    final outbox = widget.eventOutbox;
    if (id == null || outbox == null) return const {};
    return outbox.locked(id) ?? allWaiting;
  }

  /// [event]'s title, quoted, to name it in what's waiting.
  static String _named(Event event) => switch (event.summary) {
    final s? when s.isNotEmpty => '“$s”',
    _ => 'an event',
  };

  static String _nameOf(Map<String, Object?> fields) =>
      switch (fields['summary']) {
        final String s when s.isNotEmpty => '“$s”',
        _ => 'an event',
      };

  /// Opens every one of [event]'s properties.
  Future<void> _openEventDetails(Event event) async {
    final updated = await showEventDialog(
      context,
      event,
      save: (event, changes) => _approvingHistory(
        at: event.start,
        (allow) => _writes.update(event, changes, allowHistory: allow),
      ),
      cancel: _waitingOn(event).isNotEmpty
          ? null
          : (event, counts) => _approvingHistory(
              at: event.start,
              (allow) => _writes.cancel(
                event,
                countsAgainstFollowThrough: counts,
                allowHistory: allow,
              ),
            ),
      waiting: _waitingOn(event),
      otherEvents: _otherEvents(event),
      actions: _actions,
      openSeries: (seriesId) => _openSeries(seriesId, event),
    );
    if (updated != null) await _saved(event, updated);
  }

  /// Says what saving [event] did, [updated] being what the server
  /// changed, and loads the days again.
  Future<void> _saved(Event event, List<Event> updated) async {
    if (_writes.queued) return setState(() {});
    final moved = updated.where((e) => e.id != event.id).length;
    final cancelled = updated.any((e) => e.id == event.id && e.isCancelled);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          cancelled
              ? 'Event cancelled.'
              : moved == 0
              ? 'Saved.'
              : 'Saved. $moved other event${moved == 1 ? '' : 's'} '
                    'moved to make room.',
        ),
      ),
    );
    // The traits are scored from it at once; it may have moved others, on
    // other days too.
    _putEvents(updated);
    _fresh.clear();
    unawaited(_loadProposal());
    await _refresh();
    // Its actions may have changed, and with them its diamonds.
    await _loadActions();
  }

  /// Every action, for picking an event's actions: the app's, loaded
  /// as it opened and again as this page did, or else the server's; null
  /// without actions.
  Future<List<PlanAction>> Function()? get _actions =>
      switch (widget.actionsRepository) {
        final repository? => () async {
          if (_memory.actions == null) {
            await _memory.loadActions(repository);
          }
          return _memory.shownActions?.actions ?? const [];
        },
        null => null,
      };

  /// Opens the recurring series [seriesId]'s summary, from its [event],
  /// and from it, its details. True if a change to it was saved, after
  /// which the day is loaded again.
  Future<bool> _openSeries(String seriesId, Event event) async {
    final messenger = ScaffoldMessenger.of(context);
    final Recurrence recurrence;
    try {
      recurrence = await widget.repository.recurrence(seriesId);
    } catch (e) {
      if (mounted) {
        await showErrorSheet(
          context,
          title: "Couldn't load the series",
          error: e,
          onRetry: () => _openSeries(seriesId, event),
        );
      }
      return false;
    }
    if (!mounted || event.id == null) return false;
    // What was saved, for saying so.
    String? said;
    final outcome = await showSeriesSummaryDialog(
      context,
      recurrence,
      fromEventId: event.id!,
      fromEventStart: event.start,
      actions: _actionsById,
      loadActions: _actions,
      save: (changes, scope) {
        said = scope == SeriesScope.following
            ? 'Saved this and following events.'
            : 'Saved every event in the series.';
        return widget.repository.updateRecurrence(
          recurrence,
          changes,
          startingAt: scope == SeriesScope.following ? event.id : null,
        );
      },
      // Always from this event on: see EventsRepository.deleteRecurrence.
      delete: () {
        said = 'Deleted this and following events.';
        return widget.repository.deleteRecurrence(
          recurrence,
          startingAt: event.id!,
        );
      },
    );
    if (!mounted) return false;
    switch (outcome) {
      case SummaryDetails():
        return _openSeriesDetails(recurrence, event);
      case SummarySaved():
        messenger.showSnackBar(SnackBar(content: Text(said!)));
        _fresh.clear();
        await _refresh();
        return true;
      case null:
        return false;
    }
  }

  /// Opens every one of [recurrence]'s properties, from its [event]. True
  /// if a change to it was saved.
  Future<bool> _openSeriesDetails(Recurrence recurrence, Event event) async {
    final messenger = ScaffoldMessenger.of(context);
    SeriesScope? savedFor;
    final saved = await showRecurrenceDialog(
      context,
      recurrence,
      fromEventId: event.id,
      actions: _actions,
      save: (changes, scope) {
        savedFor = scope;
        return widget.repository.updateRecurrence(
          recurrence,
          changes,
          startingAt: scope == SeriesScope.following ? event.id : null,
        );
      },
    );
    if (saved == null) return false;
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          savedFor == SeriesScope.following
              ? 'Saved this and following events.'
              : 'Saved every event in the series.',
        ),
      ),
    );
    _fresh.clear();
    await _refresh();
    return true;
  }

  /// Runs [action] on the open proposal, its bar busy meanwhile; if it
  /// fails, loads the proposal again and says why, after [failed].
  Future<void> _onProposal(
    String failed,
    Future<void> Function(Proposal proposal, ProposalRepository repository)
    action,
  ) async {
    final proposal = _proposal;
    final repository = widget.proposals;
    if (proposal == null || repository == null || _proposalBusy) return;
    setState(() => _proposalBusy = true);
    Object? error;
    try {
      await action(proposal, repository);
    } catch (e) {
      error = e;
      await _loadProposal();
    } finally {
      if (mounted) setState(() => _proposalBusy = false);
    }
    if (error == null || !mounted) return;
    final now = _proposal?.revision;
    final changed = now != null && now != proposal.revision;
    await showErrorSheet(
      context,
      title: failed,
      error: error,
      message: changed
          ? 'It changed since you looked: this is revision $now. Review it, '
                'then try again.'
          : null,
      // Not one that changed: that's to review first.
      onRetry: changed ? null : () => _onProposal(failed, action),
    );
  }

  /// Queues [action] on the open proposal, as the server gave it, with the
  /// [EventOutbox]; says [queued] once it is, or why it can't be.
  Future<void> _queueOnProposal(
    String queued,
    Future<void> Function(Proposal proposal, EventOutbox outbox) action,
  ) async {
    final proposal = _loadedProposal;
    final outbox = widget.eventOutbox;
    if (proposal == null || outbox == null) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await action(proposal, outbox);
      messenger.showSnackBar(SnackBar(content: Text(queued)));
    } on ProposalEditException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  /// Confirms the open proposal, as shown.
  Future<void> _confirmProposal() async {
    final waiting = [
      for (final w
          in widget.eventOutbox?.pending ?? const <PendingEventWrite>[])
        if (w.kind == EventWriteKind.amend && w.proposalId == _proposal?.id) w,
    ];
    if (waiting.isNotEmpty) {
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Not yet'),
          content: Text(
            '${waiting.length == 1 ? 'A change' : '${waiting.length} changes'}'
            ' to it ${waiting.length == 1 ? 'is' : 'are'} still waiting to '
            'save. Confirm it once '
            '${waiting.length == 1 ? "it's" : "they're"} saved, so what '
            "you confirm is what's shown.",
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      return;
    }
    if (widget.eventOutbox != null) {
      return _queueOnProposal(
        "Confirm waiting to save: it goes as soon as it can, and what came "
        'of it shows here.',
        (proposal, outbox) => outbox.confirm(proposal),
      );
    }
    return _onProposal(
      "Couldn't confirm it",
      (proposal, repository) async =>
          _confirmed(proposal, await repository.confirm(proposal)),
    );
  }

  /// Resumes the apply of the open proposal, where it stopped.
  Future<void> _finishProposal() async {
    if (widget.eventOutbox != null) {
      return _queueOnProposal(
        'Finishing it waits to save: it goes as soon as it can.',
        (proposal, outbox) => outbox.finish(proposal),
      );
    }
    return _onProposal(
      "Couldn't finish it",
      (proposal, repository) async =>
          _confirmed(proposal, await repository.finish(proposal)),
    );
  }

  /// Shows what confirming [proposal], or finishing it, came to: applied,
  /// it's history; rechecked, or rebuilt, a new revision to confirm; or
  /// handed to Claude.
  Future<void> _confirmed(Proposal proposal, ProposalOutcome outcome) async {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final next = outcome.proposal;
    switch (outcome.status) {
      case ProposalOutcomeStatus.applied:
        _closeProposal(proposal.id, applied: true);
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              'Confirmed: what happened '
              '${windowLabel(context, proposal.windowStart, proposal.through)} '
              'is recorded.',
            ),
          ),
        );
        // A goal change the goals refused: left for the user.
        final warnings = outcome.warningsSince(proposal);
        if (warnings.isNotEmpty) {
          await showDialog<void>(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('Confirmed, with warnings'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final w in warnings)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text('• $w'),
                      ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('OK'),
                ),
              ],
            ),
          );
        }
      case ProposalOutcomeStatus.rechecked:
        // What the recheck changed, from the revision confirmed.
        final again =
            await widget.proposals!.current(sinceRevision: proposal.revision) ??
            next;
        if (again == null || !mounted) return;
        setState(() {
          _proposal = again.copyWith(
            changedSince: {...proposal.changedSince, ...again.changedSince},
          );
          // Not while it's asked.
          _proposalBusy = false;
        });
        final confirm = await showRecheckedDialog(
          context,
          again,
          message: outcome.message,
          names: [
            for (final id in again.changedSince) again.event(id)?.summary ?? id,
          ],
        );
        if (confirm && mounted) await _confirmProposal();
      case ProposalOutcomeStatus.rebuilt:
        setState(() => _proposal = next ?? _proposal);
        unawaited(_loadProposal());
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              outcome.message ??
                  "Some of it couldn't be applied, so it's been planned "
                      'again from the calendar as it is: review it, then '
                      'confirm again.',
            ),
          ),
        );
      case ProposalOutcomeStatus.abandoned:
        _closeProposal(proposal.id, applied: false);
        messenger.showSnackBar(
          SnackBar(content: Text(outcome.message ?? 'It was abandoned.')),
        );
      case ProposalOutcomeStatus.needsClaude:
        setState(() {
          _proposal = next ?? _proposal;
          _proposalBusy = false;
        });
        unawaited(_loadProposal());
        await showDialog<void>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Claude needs to look at it'),
            content: Text(
              outcome.message ??
                  "It can't be planned as it is any more, so it's gone to "
                      "Claude with a note saying why. It'll come back "
                      'revised, to confirm.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('OK'),
              ),
            ],
          ),
        );
    }
  }

  /// The open proposal's events, by id, named for notes about them.
  Map<String, String> get _reviewedNames {
    final strings = MaterialLocalizations.of(context);
    String time(DateTime t) =>
        strings.formatTimeOfDay(TimeOfDay.fromDateTime(t.toLocal()));
    return {
      for (final e in _proposal?.reviewed ?? const <ProposalEvent>[])
        e.id:
            '${switch (e.summary) {
              final s? when s.isNotEmpty => s,
              _ => '(no summary)',
            }}, ${time(e.start)}',
    };
  }

  /// The open proposal's events, by id, by summary.
  Map<String, String> get _reviewedSummaries => {
    for (final e in _proposal?.reviewed ?? const <ProposalEvent>[])
      e.id: switch (e.summary) {
        final s? when s.isNotEmpty => s,
        _ => '(no summary)',
      },
  };

  /// The open proposal's time notes, by id, named for notes about them:
  /// "the 11:05 AM note, “Coffee's cold”".
  Map<String, String> get _noteNames {
    final strings = MaterialLocalizations.of(context);
    return {
      for (final n in _proposalNotes)
        n.id:
            'the ${strings.formatTimeOfDay(TimeOfDay.fromDateTime(n.time.toLocal()))} '
            'note${n.text == null ? '' : ', “${n.text}”'}',
    };
  }

  /// Asks what [note] is for, and edits the proposal so: added to the
  /// event it falls within or another of its day's, left out, or put back
  /// as Claude had it -- or leaves a note for Claude about it.
  Future<void> _editNote(ProposalNote note) async {
    final proposal = _proposal;
    if (proposal == null) return;
    final day = _midnight(note.time.toLocal());
    final live = [
      for (final e in proposal.reviewed)
        if (e.live && e.start.isBefore(_dayAfter(day)) && e.end.isAfter(day)) e,
    ];
    final summaries = _reviewedSummaries;
    final strings = MaterialLocalizations.of(context);
    String time(DateTime t) =>
        strings.formatTimeOfDay(TimeOfDay.fromDateTime(t.toLocal()));
    final choice = await showNoteUseSheet(
      context,
      note,
      events: {
        for (final e in live) e.id: '${summaries[e.id]}, ${time(e.start)}',
      },
      // Annotated with no event named, a note goes to the event whose edge
      // it sets, or else the one it falls within.
      fallsIn:
          note.edgeOf ??
          live
              .where(
                (e) => !e.start.isAfter(note.time) && e.end.isAfter(note.time),
              )
              .firstOrNull
              ?.id,
    );
    if (choice == null || !mounted) return;
    final (edits, said) = switch (choice) {
      AnnotateNote(:final eventId) => (
        ProposalEdits(
          notes: [(noteId: note.id, ignore: false, eventId: eventId)],
        ),
        'Note added to ${switch (summaries[eventId]) {
          final name? => '“$name”',
          null => 'the event it falls within',
        }}, in what happened, to confirm.',
      ),
      IgnoreNote() => (
        ProposalEdits(notes: [(noteId: note.id, ignore: true, eventId: null)]),
        'Note left out of what happened, to confirm.',
      ),
      NoteAsClaudeHadIt() => (
        ProposalEdits(asPlanned: [note.id]),
        'Note put back as Claude had it.',
      ),
      AskClaudeAboutNote() => (null, null),
    };
    if (edits == null) return _noteForClaude(aboutNote: note);
    await runOrShowError(
      context,
      title: "Couldn't change it",
      action: () async {
        final amended = await _amend(edits);
        if (mounted) _amended(amended, said!);
      },
    );
  }

  /// Asks for a note for Claude on the open proposal, about [about] to
  /// start with -- or about the time note [aboutNote] -- and leaves it.
  Future<void> _noteForClaude({
    String? about,
    ProposalNote? aboutNote,
    ProposalAddition? aboutAddition,
    ProposalGoalChange? aboutGoalChange,
    RecapPoint? answering,
  }) async {
    final subject = switch ((aboutNote, aboutAddition)) {
      _ when answering != null => 'Answering Claude: “${answering.quote}”',
      (final n?, _) => 'About ${_noteNames[n.id]}',
      (_, final a?) =>
        'About the new ${a.kind.label.toLowerCase()} “${a.name}”',
      _ when aboutGoalChange != null =>
        'About the change to the goal “${aboutGoalChange.name}”',
      _ => null,
    };
    final note = await showProposalNoteDialog(
      context,
      events: _reviewedNames,
      about: about,
      subject: subject,
    );
    if (note == null || !mounted) return;
    // Quoting the point it answers, for Claude, and to show it under; a
    // note about a goal change names the goal, as a note has nowhere else
    // to say it.
    final text = switch ((answering, aboutGoalChange)) {
      (final point?, _) => ProposalFeedback.answering(point, note.text),
      (null, final c?) =>
        'About the change to the goal “${c.name}” (${c.goalId}):\n\n'
            '${note.text}',
      _ => note.text,
    };
    // What's added is named by its ref.
    final eventId = switch ((aboutNote, aboutAddition)) {
      (null, null) => note.eventId,
      (_, final a?) => a.ref,
      _ => null,
    };
    if (widget.eventOutbox != null) {
      return _queueOnProposal(
        "Note left. It's waiting for Claude to answer.",
        (proposal, outbox) => outbox.addNote(
          proposal,
          text,
          eventId: eventId,
          noteId: aboutNote?.id,
        ),
      );
    }
    final messenger = ScaffoldMessenger.of(context);
    await _onProposal("Couldn't leave the note", (proposal, repository) async {
      await repository.addNote(
        proposal,
        text,
        eventId: eventId,
        noteId: aboutNote?.id,
      );
      await _loadProposal();
      messenger.showSnackBar(
        const SnackBar(
          content: Text("Note left. It's waiting for Claude to answer."),
        ),
      );
    });
  }

  /// Shows the open proposal's notes for Claude, and Claude's replies.
  Future<void> _showProposalNotes() async {
    final proposal = _proposal;
    if (proposal == null) return;
    final action = await showProposalNotesSheet(
      context,
      proposal,
      names: {
        ..._reviewedNames,
        // A note about what's added names it by its ref.
        for (final (:addition, settled: _) in _additions)
          addition.ref:
              'the new ${addition.kind.label.toLowerCase()} '
              '“${addition.name}”',
      },
      noteNames: _noteNames,
    );
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    switch (action) {
      case WithdrawNote(:final feedback) when widget.eventOutbox != null:
        await _queueOnProposal(
          'Note withdrawn.',
          (proposal, outbox) => outbox.withdrawNote(proposal, feedback.id),
        );
      case WithdrawNote(:final feedback):
        await _onProposal("Couldn't withdraw it", (_, repository) async {
          await repository.withdrawNote(feedback.id);
          await _loadProposal();
          messenger.showSnackBar(
            const SnackBar(content: Text('Note withdrawn.')),
          );
        });
      case AddNote():
        await _noteForClaude();
      case null:
    }
  }

  /// Gives up the open proposal, after asking.
  Future<void> _abandonProposal() async {
    final proposal = _proposal;
    if (proposal == null) return;
    final sure = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Abandon it?'),
        content: Text(
          'What happened '
          '${windowLabel(context, proposal.windowStart, proposal.through)} '
          "isn't confirmed from it, and your edits and notes to it are "
          'dropped. Claude proposes it again on its next run.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Keep it'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Abandon it'),
          ),
        ],
      ),
    );
    if (sure != true || !mounted) return;
    if (widget.eventOutbox != null) {
      return _queueOnProposal(
        'Abandoning it waits to save: it goes as soon as it can.',
        (proposal, outbox) => outbox.abandon(proposal),
      );
    }
    await _onProposal("Couldn't abandon it", (proposal, repository) async {
      await repository.abandon(proposal);
      _closeProposal(proposal.id, applied: false);
    });
  }

  /// Shows the start of what the open proposal says happened.
  void _goToProposal() {
    final proposal = _proposal;
    if (proposal == null) return;
    final from = proposal.windowStart.toLocal();
    final day = _midnight(from);
    if (day != _day) _goToDay(day);
    // Once it's laid out on that day.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      final y =
          timelineOffset(
            from,
            day: day,
            dayEnd: _dayAfter(day),
            scale: _scale,
          ) -
          48;
      _scroll.jumpTo(y.clamp(0, _scroll.position.maxScrollExtent));
    });
  }

  /// Slides [days] on, from the day shown or the one it's sliding to.
  void _step(int days) {
    if (!_pages.hasClients) return;
    final page = (_slidingTo ?? _pageOf(_day)) + days;
    _slidingTo = page;
    _pages.animateToPage(page, duration: _slide, curve: Curves.easeInOut);
  }

  Future<void> _pickDay() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _day,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked != null && mounted) _goToDay(_midnight(picked));
  }

  Future<void> _signIn() async {
    setState(() => _signingIn = true);
    Object? error;
    try {
      await widget.onSignIn!();
      unawaited(_loadNotes());
      await _refresh();
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
    setState(_fresh.clear);
    await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    _sayProblem();
    final today = widget.clock();
    // Back leaves the top mode, as ✕ does, before it leaves the page.
    final modes = _modes;
    // Stepped onto another day, once it's loaded.
    if (_keyedOnto != null && _eventsOn(_day) != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _keyOnto();
      });
    }
    return HotkeyBindings(
      bindings: _hotkeys,
      child: _page(context, today, modes),
    );
  }

  Widget _page(BuildContext context, DateTime today, List<EventsMode> modes) {
    return PopScope(
      canPop: modes.isEmpty,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _leaveMode();
      },
      child: Scaffold(
        appBar: AppBar(
          title: TextButton.icon(
            onPressed: _pickDay,
            icon: const Icon(Icons.calendar_today, size: 18),
            label: Text(dayLabel(context, _day, today)),
            style: TextButton.styleFrom(
              textStyle: Theme.of(context).textTheme.titleLarge,
            ),
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.chevron_left),
              tooltip: 'Previous day',
              onPressed: () => _step(-1),
            ),
            IconButton(
              icon: const Icon(Icons.chevron_right),
              tooltip: 'Next day',
              onPressed: () => _step(1),
            ),
            AppMenu(
              serverLabel: widget.serverLabel,
              version: widget.version,
              onSignOut: widget.onSignOut == null || _needsSignIn
                  ? null
                  : _signOut,
              onRefresh: _needsSignIn ? null : _refreshAll,
            ),
          ],
        ),
        body: Stack(
          children: [
            RefreshingBar(
              refreshing: _stale && _error == null && !_needsSignIn,
              child: _needsSignIn ? _buildSignIn() : _buildTimeline(),
            ),
            // The modes it's in, lower left.
            Positioned(left: 16, bottom: 16, child: ModeStack(modes: _modes)),
          ],
        ),
        floatingActionButton: _needsSignIn
            ? null
            : _selecting != null
            // Picking: ✓ keeps what's picked, ✕ puts the lists back.
            ? Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  FloatingActionButton(
                    heroTag: 'cancel-pick',
                    tooltip: 'Put the list back as it was',
                    onPressed: () => _endSelecting(kept: false),
                    child: const Icon(Icons.close),
                  ),
                  const SizedBox(width: 12),
                  FloatingActionButton(
                    heroTag: 'done-pick',
                    tooltip: 'Done picking',
                    onPressed: () => _endSelecting(kept: true),
                    child: const Icon(Icons.check),
                  ),
                ],
              )
            : _noteAt != null
            // Placing a note: ✓ opens the New note sheet at the cursor.
            ? Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  HotkeyHint(
                    Hotkey.leaveMode,
                    child: FloatingActionButton(
                      heroTag: 'cancel-note',
                      tooltip: 'Cancel',
                      onPressed: _leaveMode,
                      child: const Icon(Icons.close),
                    ),
                  ),
                  const SizedBox(width: 12),
                  HotkeyHint(
                    Hotkey.setEnd,
                    child: FloatingActionButton(
                      heroTag: 'done-note',
                      tooltip: 'Write a note here',
                      onPressed: _addNoteAtCursor,
                      child: const Icon(Icons.check),
                    ),
                  ),
                ],
              )
            : _box != null
            ? Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  // The lists, while they're out: keep; push up over
                  // push down; cancel.
                  if (_listsShown) ...[
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _listButton(EventList.keep),
                        const SizedBox(width: 12),
                        Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _listButton(EventList.pushUp),
                            const SizedBox(height: 8),
                            _listButton(EventList.pushDown),
                          ],
                        ),
                        const SizedBox(width: 12),
                        _listButton(EventList.cancel),
                      ],
                    ),
                    const SizedBox(height: 28),
                  ],
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _listsToggle(),
                      const SizedBox(width: 12),
                      if (_hasGoogleEvents) ...[
                        _googleToggle(),
                        const SizedBox(width: 12),
                      ],
                      FloatingActionButton.small(
                        heroTag: 'to-new',
                        tooltip: 'Go to the new event',
                        onPressed: _goToBox,
                        child: const Icon(Icons.filter_center_focus),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      HotkeyHint(
                        Hotkey.leaveMode,
                        child: FloatingActionButton(
                          heroTag: 'cancel-new',
                          tooltip: 'Cancel',
                          onPressed: _leaveMode,
                          child: const Icon(Icons.close),
                        ),
                      ),
                      const SizedBox(width: 12),
                      // Only with an event to make, or -- with just the
                      // one cursor -- events to cancel.
                      Builder(
                        builder: (context) {
                          final colors = Theme.of(context).colorScheme;
                          final cancels = _cursorCancels.length;
                          final atCursor = cancels == 0
                              ? null
                              : 'Cancel ${_events(cancels)}';
                          // Not into an event to keep.
                          final blocked = _effectOf(_box)?.blocked ?? false;
                          final ready =
                              (_box?.span != null && !blocked) ||
                              atCursor != null;
                          return HotkeyHint(
                            Hotkey.setEnd,
                            child: FloatingActionButton(
                              heroTag: 'continue-new',
                              tooltip:
                                  atCursor ??
                                  (!ready
                                      ? 'Continue: first, make an event '
                                            'between the cursors'
                                      : _moving != null
                                      ? 'Move it here'
                                      : 'Continue'),
                              onPressed: _continueAction,
                              backgroundColor: ready
                                  ? null
                                  : colors.surfaceContainerHighest,
                              foregroundColor: ready ? null : colors.outline,
                              elevation: ready ? null : 0,
                              child: const Icon(Icons.check),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ],
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                // Flush right, where go-to-new is with a box up.
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_hasGoogleEvents) ...[
                        _googleToggle(),
                        const SizedBox(width: 12),
                      ],
                      HotkeyHint(
                        Hotkey.now,
                        child: FloatingActionButton.small(
                          heroTag: 'now',
                          tooltip: 'Go to now',
                          onPressed: _goToNow,
                          child: const Icon(Icons.my_location),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (widget.outbox != null) ...[
                        FloatingActionButton.small(
                          heroTag: 'new-note',
                          tooltip: 'New note at a time',
                          onPressed: _startNoting,
                          child: const Icon(Icons.edit_note),
                        ),
                        const SizedBox(width: 12),
                      ],
                      HotkeyHint(
                        Hotkey.create,
                        child: FloatingActionButton(
                          heroTag: 'new',
                          tooltip: 'New event',
                          onPressed: _startCreating,
                          child: const Icon(Icons.add),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
      ),
    );
  }

  /// Under the proposal's bar, its details, a page each: its notes, its
  /// cancels and whether they count against follow-through, and what it
  /// adds -- each one at a time, stepped through.
  /// Whether the proposal has details to show under its bar.
  bool _hasDetails(Proposal proposal) =>
      _recapPoint != null ||
      _note != null ||
      _cancel != null ||
      _addition != null ||
      _goalChange != null;

  /// Says why the open proposal can't be confirmed, if it can't, at the
  /// foot of the page ([ProposalProblemStatus]): once the frame's built,
  /// as that's built with it.
  void _sayProblem() {
    final status = widget.proposalProblem;
    if (status == null) return;
    final problem = switch (_proposal) {
      // One whose apply stopped partway says so in its bar.
      final proposal?
          when !proposal.plans && proposal.state != ProposalState.applying =>
        proposal.problem ?? ProposalProblemStatus.fallback,
      _ => null,
    };
    if (problem == status.problem) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) status.show(problem);
    });
  }

  Widget _buildDetails(Proposal proposal) {
    final notes = _proposalNotes;
    final note = _note;
    final cancels = proposal.cancels;
    final cancel = _cancel;
    final added = _additions;
    final addition = _addition;
    int indexOf<T>(List<T> list, bool Function(T) test) =>
        list.indexWhere(test);
    final points = proposal.recap?.points ?? const <RecapPoint>[];
    final point = _recapPoint;
    final recapAt = point == null ? -1 : points.indexOf(point);
    final edited = proposal.editedSinceRecap;
    final eventNames = _recapEventNames;
    final noteNames = _recapNoteNames;
    final noteAt = note == null ? -1 : indexOf(notes, (n) => n.id == note.id);
    final cancelAt = cancel == null
        ? -1
        : indexOf(cancels, (e) => e.id == cancel.id);
    final additionAt = addition == null
        ? -1
        : indexOf(added, (a) => a.addition.ref == addition.addition.ref);
    final goalChanges = _goalChanges;
    final goalChange = _goalChange;
    final goalChangeAt = goalChange == null
        ? -1
        : indexOf(
            goalChanges,
            (c) => c.change.goalId == goalChange.change.goalId,
          );
    final goalNames = _recapGoalNames;
    // Its pages, as it'll have them: those with something on.
    final pages = [
      if (point != null) ProposalDetailPage.claude,
      if (note != null) ProposalDetailPage.notes,
      if (cancel != null) ProposalDetailPage.followThrough,
      if (addition != null) ProposalDetailPage.added,
      if (goalChange != null) ProposalDetailPage.goals,
    ];
    return ProposalDetails(
      initialPage: switch (pages.indexOf(_detailPage)) {
        -1 => 0,
        final i => i,
      },
      recap: point == null
          ? null
          : ProposalRecapStrip(
              point: point,
              index: recapAt,
              count: points.length,
              about: [
                for (final id in point.eventIds)
                  ?_reviewedSummaries[id] ?? eventNames[id],
                for (final id in point.noteIds) ?noteNames[id],
                for (final id in point.goalIds) ?goalNames[id],
              ],
              changed: point.eventIds.any(edited.contains),
              answers: proposal.answersTo(point),
              onOpen: _openRecap,
              onPrevious: recapAt > 0 ? () => _goToRecap(recapAt - 1) : null,
              onNext: recapAt < points.length - 1
                  ? () => _goToRecap(recapAt + 1)
                  : null,
            ),
      recapCount: points.length,
      unsureCount: proposal.recap?.unsure.length ?? 0,
      waitingCount: proposal.openFeedback.length,
      notes: note == null
          ? null
          : ProposalNoteStrip(
              note: note,
              index: noteAt,
              count: notes.length,
              onPrevious: noteAt > 0 ? () => _goToNote(noteAt - 1) : null,
              onNext: noteAt < notes.length - 1
                  ? () => _goToNote(noteAt + 1)
                  : null,
              events: _reviewedSummaries,
              extended: _proposal?.inExtension(note.time) ?? false,
              // Compacted already: there to see, not to change.
              onEdit: note.compacted ? null : () => _editNote(note),
            ),
      noteCount: notes.length,
      cancels: cancel == null
          ? null
          : ProposalCancelStrip(
              event: cancel,
              index: cancelAt,
              count: cancels.length,
              onCounts: _proposalBusy
                  ? null
                  : (counts) => _setCounts(cancel, counts),
              onPrevious: cancelAt > 0 ? () => _goToCancel(cancelAt - 1) : null,
              onNext: cancelAt < cancels.length - 1
                  ? () => _goToCancel(cancelAt + 1)
                  : null,
              // Shown, and opened: who it counts against, in full.
              onTap: () {
                _goToCancel(cancelAt);
                _openCancelled(cancel.toEvent());
              },
            ),
      cancelCount: cancels.length,
      counting: cancels
          .where((e) => e.countsAgainstFollowThrough ?? true)
          .length,
      adds: addition == null
          ? null
          : ProposalAdditionStrip(
              addition: addition.addition,
              settled: addition.settled,
              settledAs: _settledName(addition.settled, addition.addition.kind),
              index: additionAt,
              count: added.length,
              uses: [
                for (final e in _usesOf(addition)) _reviewedNames[e.id] ?? e.id,
              ],
              about: _aboutGoal(addition.addition),
              onSettle: _proposalBusy ? null : () => _settle(addition),
              onActivate:
                  _proposalBusy ||
                      addition.settled != null ||
                      addition.addition.kind != AdditionKind.goal
                  ? null
                  : () => _settle(addition, activate: true),
              onPrevious: additionAt > 0
                  ? () => _goToAddition(additionAt - 1)
                  : null,
              onNext: additionAt < added.length - 1
                  ? () => _goToAddition(additionAt + 1)
                  : null,
            ),
      addCount: added.length,
      goals: goalChange == null
          ? null
          : ProposalGoalChangeStrip(
              change: goalChange.change,
              settled: goalChange.settled,
              index: goalChangeAt,
              count: goalChanges.length,
              from: [
                for (final id in goalChange.change.noteIds) ?noteNames[id],
              ],
              onSettle: _proposalBusy
                  ? null
                  : () => _settleGoalChange(goalChange),
              onApply:
                  _proposalBusy ||
                      goalChange.settled != null &&
                          goalChange.settled!.use != GoalChangeUse.change
                  ? null
                  : () => _settleGoalChange(goalChange, apply: true),
              onPrevious: goalChangeAt > 0
                  ? () => _goToGoalChange(goalChangeAt - 1)
                  : null,
              onNext: goalChangeAt < goalChanges.length - 1
                  ? () => _goToGoalChange(goalChangeAt + 1)
                  : null,
            ),
      goalCount: goalChanges.length,
      collapsed: _detailsCollapsed,
      onCollapsed: _setDetailsCollapsed,
      onPage: _turnDetailsTo,
    );
  }

  /// Asks what's to become of the goal change [changed], and amends the
  /// proposal so: applied now, dropped, changed -- to mark the goal done,
  /// missed (tried again by a day picked) or obsolete -- or put back as
  /// Claude proposed it; or leaves a note for Claude about it. With
  /// [apply], it's applied at once.
  Future<void> _settleGoalChange(
    _GoalChanged changed, {
    bool apply = false,
  }) async {
    final c = changed.change;
    final from = [for (final id in c.noteIds) ?_recapNoteNames[id]];
    final choice = apply
        ? const ApplyGoalChange()
        : await showGoalChangeSheet(
            context,
            c,
            settled: changed.settled,
            claudes: changed.claudes,
            from: from,
            now: widget.clock,
          );
    if (choice == null || !mounted) return;
    ProposalEdits settling(
      GoalChangeUse use, {
      String? status,
      String? retryDeadline,
    }) => ProposalEdits(
      goalChanges: [
        (
          goalId: c.goalId,
          use: use,
          status: status,
          at: null,
          retryDeadline: retryDeadline,
        ),
      ],
    );
    final (edits, said) = switch (choice) {
      ApplyGoalChange() => (
        settling(GoalChangeUse.apply),
        'Applied: “${c.name}” is ${goalStatuses[c.status]?.toLowerCase() ?? c.status}'
            '${c.retries ? ', and tried again' : ''}.',
      ),
      DropGoalChange() => (
        settling(GoalChangeUse.drop),
        'Dropped: “${c.name}” is left alone.',
      ),
      ChangeGoalChange(:final status, :final retryDeadline) => (
        settling(
          GoalChangeUse.change,
          status: status,
          retryDeadline: retryDeadline,
        ),
        'Changed: “${c.name}” · '
            '${goalChangeLabel(context, status, retryDeadline)}.',
      ),
      // As Claude had it: a change back to its status -- or, for one of
      // the user's own, dropped.
      PutBackGoalChange() => (
        switch (changed.claudes) {
          final claudes? => settling(
            GoalChangeUse.change,
            status: claudes.status,
            retryDeadline: claudes.retryDeadline,
          ),
          null => settling(GoalChangeUse.drop),
        },
        'Put back as Claude proposed it.',
      ),
      AskAboutGoalChange() => (null, null),
    };
    if (edits == null) return _noteForClaude(aboutGoalChange: c);
    await runOrShowError(
      context,
      title: "Couldn't settle it",
      action: () async {
        final amended = await _amend(edits);
        if (!mounted) return;
        _amended(amended, said!);
        // Applied: the goal's changed where it's kept.
        if (choice is ApplyGoalChange) unawaited(_reloadGoals());
      },
    );
  }

  /// Loads the goals again, after one's changed outside the app's own
  /// goal flows. Best effort.
  Future<void> _reloadGoals() async {
    final repository = GoalsScope.of(context);
    if (repository == null) return;
    try {
      _memory.goals = await repository.goals();
    } catch (_) {
      // Shown as they were, till they're next loaded.
    }
  }

  /// Asks what's to become of [added], and amends the proposal so: made
  /// now, one already there, dropped, or put back as Claude proposed it
  /// -- or leaves a note for Claude about it.
  ///
  /// With [activate], a new goal is made at once, active, due when the
  /// user picks. A person, location or action made now is made in its
  /// quick sheet ([_make]).
  Future<void> _settle(_Added added, {bool activate = false}) async {
    final a = added.addition;
    final existing = <({String id, String name, String? detail})>[
      ...switch (a.kind) {
        AdditionKind.person => [
          for (final p in _memory.people?.people ?? const <Person>[])
            if (p.active) (id: p.id, name: p.name, detail: p.context),
        ],
        AdditionKind.location => [
          for (final l in _memory.locations ?? const <Location>[])
            (id: l.id, name: l.name, detail: l.hint),
        ],
        AdditionKind.action => [
          for (final action
              in _memory.shownActions?.actions ?? const <PlanAction>[])
            if (!action.isGroup &&
                action.id != null &&
                action.status != 'deleted')
              (id: action.id!, name: actionName(action), detail: null),
        ],
        AdditionKind.goal => [
          for (final g in _memory.goals ?? const <Goal>[])
            if (g.open)
              (
                id: g.id,
                name: goalTitle(g),
                detail: g.path.isEmpty ? null : g.path.join(' › '),
              ),
        ],
      },
    ];
    final choice = activate
        ? await activateGoal(context, a)
        : await showAdditionSheet(
            context,
            a,
            settled: added.settled,
            settledAs: _settledName(added.settled, a.kind),
            existing: existing,
          );
    if (choice == null || !mounted) return;
    if (choice is MakeAddition) return _make(a);
    ProposalEdits settling(
      AdditionUse use, {
      String? id,
      String? name,
      String? detail,
      String? deadline,
    }) => ProposalEdits(
      additions: [
        (
          ref: a.ref,
          use: use,
          id: id,
          name: name,
          detail: detail,
          kind: a.kind,
          deadline: deadline,
          fields: null,
        ),
      ],
    );
    final kind = a.kind.label.toLowerCase();
    final (edits, said) = switch (choice) {
      CreateAddition(:final name, :final detail, :final deadline) => (
        settling(
          AdditionUse.create,
          name: name,
          detail: detail,
          deadline: deadline,
        ),
        deadline == null
            ? 'Made the $kind “$name”.'
            : 'Made the $kind “$name”, active.',
      ),
      UseExisting(:final id) => (
        settling(AdditionUse.existing, id: id),
        'It’s ${existing.where((e) => e.id == id).firstOrNull?.name ?? 'one already here'}.',
      ),
      DropAddition() => (
        settling(AdditionUse.drop),
        'Dropped “${a.name}”: taken out of every event.',
      ),
      UnsettleAddition() => (
        ProposalEdits(asPlanned: [a.ref]),
        'Put back as Claude proposed it.',
      ),
      AskAboutAddition() || MakeAddition() => (null, null),
    };
    if (edits == null) return _noteForClaude(aboutAddition: a);
    await runOrShowError(
      context,
      title: "Couldn't settle it",
      action: () async {
        final amended = await _amend(edits);
        if (!mounted) return;
        // Made now: named from where it's kept, once it's saved (see
        // _learnNames).
        _amended(amended, said!);
      },
    );
  }

  /// Makes the person, location or action [a] now, in its quick sheet --
  /// or its More, the full page or dialog -- starting as Claude has it,
  /// and amends the proposal so: made with every field set there. If the
  /// amend fails, the sheet stays open, saying so, to try again.
  Future<void> _make(ProposalAddition a) async {
    final kind = a.kind.label.toLowerCase();
    Future<void> make(Map<String, Object?> fields) async {
      final name = (fields['name'] as String?)?.trim();
      final amended = await _amend(
        ProposalEdits(
          additions: [
            (
              ref: a.ref,
              use: AdditionUse.create,
              id: null,
              name: name == null || name.isEmpty ? null : name,
              detail: null,
              kind: a.kind,
              deadline: null,
              // Everything else, its context or hint too -- cleared, if
              // it was.
              fields: {...fields}..remove('name'),
            ),
          ],
        ),
      );
      if (!mounted) return;
      // Made now: named from where it's kept, once it's saved (see
      // _learnNames).
      _amended(amended, 'Made the $kind “${name ?? a.name}”.');
    }

    switch (a.kind) {
      case AdditionKind.person:
        await editPerson(
          context,
          name: a.name,
          about: a.detail,
          create: (fields) async {
            await make(fields);
            return Person.fromJson({'id': '', ...fields});
          },
        );
      case AdditionKind.location:
        await editLocation(
          context,
          name: a.name,
          hint: a.detail,
          mapLocation: a.fields['map_location'] as String?,
          create: (fields) async {
            await make(fields);
            return Location.fromJson({'id': '', ...fields});
          },
        );
      case AdditionKind.action:
        await addAction(
          context,
          a.name,
          parentId: a.fields['group_id'] as String?,
          create: (fields) async {
            await make({
              for (final MapEntry(:key, :value) in actionWriteFields(
                fields,
                group: false,
              ).entries)
                // Made active, as any made now is.
                if (value != null && key != 'status') key: value,
            });
            return null;
          },
        );
      case AdditionKind.goal:
        break;
    }
  }

  /// Says whether [cancel] counts against follow-through -- [counts] --
  /// or is a change of plan: sent again, the other way.
  Future<void> _setCounts(ProposalEvent cancel, bool counts) async {
    await runOrShowError(
      context,
      title: "Couldn't change it",
      action: () async {
        final amended = await _amend(
          ProposalEdits(
            cancels: [(eventId: cancel.id, countsAgainstFollowThrough: counts)],
          ),
        );
        if (mounted) {
          _amended(
            amended,
            counts
                ? 'It counts against follow-through.'
                : "A change of plan: it doesn't count against follow-through.",
          );
        }
      },
    );
  }

  /// Whether the proposal's details were folded away last time. Best
  /// effort: without it, they're open.
  Future<void> _loadDetailsCollapsed() async {
    try {
      final collapsed = await SharedPreferencesAsync().getBool(
        _detailsCollapsedKey,
      );
      if (!mounted || collapsed == null) return;
      setState(() => _detailsCollapsed = collapsed);
    } catch (_) {
      // Nowhere to keep it: they're open.
    }
  }

  void _setDetailsCollapsed(bool collapsed) {
    setState(() => _detailsCollapsed = collapsed);
    try {
      SharedPreferencesAsync()
          .setBool(_detailsCollapsedKey, collapsed)
          .catchError((_) {});
    } catch (_) {
      // Nowhere to keep it: it lasts until the app closes.
    }
  }

  Widget _buildSignIn() => FillViewport(
    child: StatusMessage(
      icon: Icons.lock_outline,
      text: 'Sign in to see your events.',
      action: widget.onSignIn == null
          ? null
          : SignInButton(signingIn: _signingIn, onPressed: _signIn),
    ),
  );

  /// The days side by side over the [TimelineAxis], all scrolled up and
  /// down at once; above them, the day's panels -- its summary, weather,
  /// all-day events, goals due and proposal -- in at most half the page, scrolled
  /// within it past that, so on a small phone the timeline, and an event
  /// shown on it, isn't squeezed out of view.
  Widget _buildTimeline() {
    final events = _shown;
    _scrollToStart();
    final noDrag = _pinch == null ? null : const NeverScrollableScrollPhysics();
    return LayoutBuilder(
      builder: (context, page) => Column(
        children: [
          ConstrainedBox(
            constraints: BoxConstraints(maxHeight: page.maxHeight / 2),
            child: SingleChildScrollView(
              key: const Key('day-panels'),
              primary: false,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: _buildPanels(events),
              ),
            ),
          ),
          Expanded(child: _buildDays(noDrag)),
        ],
      ),
    );
  }

  /// The panels above the timeline: the day's summary, its weather,
  /// all-day events and goals due, and the open proposal's bar and
  /// details.
  List<Widget> _buildPanels(List<Event>? events) => [
    if (events != null)
      DaySummary(
        events: events,
        day: _day,
        actions: _actionsById,
        goals: _memory.goals ?? const [],
        collapsed: _summaryCollapsed,
        onCollapsed: _setSummaryCollapsed,
        durations: _summaryDurations,
        onDurations: _setSummaryDurations,
      ),
    if (Weather.of(context) case final weather? when weather.enabled)
      WeatherStrip(
        weather: weather,
        day: _day,
        now: widget.clock(),
        collapsed: _weatherCollapsed,
        onCollapsed: _setWeatherCollapsed,
        onDay: _goToDay,
      ),
    if (GoogleCalendars.of(context) case final calendars?)
      GoogleAllDayStrip(
        events: [
          for (final e in calendars.on(_day))
            if (e.allDay) e,
        ],
        collapsed: _allDayCollapsed,
        onCollapsed: _setAllDayCollapsed,
        onTap: _openGoogleEvent,
      ),
    if (_memory.goals case final goals?)
      GoalsDueStrip(
        goals: goalsDueOn(goals, _day),
        missed: missedOn(goals, _day),
        overdue: overdueGoalsOn(goals, _day, today: widget.clock()),
        day: _day,
        today: widget.clock(),
        tree: GoalTree(goals),
        spent: _compactedGoalTime(goals),
        collapsed: _goalsDueCollapsed,
        onCollapsed: _setGoalsDueCollapsed,
        onTap: GoalsScope.of(context) == null ? null : _openGoal,
        onOverdueAction: GoalsScope.of(context) == null ? null : _actOnOverdue,
      ),
    if (_notices.isNotEmpty)
      ProposalNoticesBanner(
        notices: _notices,
        onDismiss: (notice) => widget.eventOutbox?.notices?.dismiss(notice),
      ),
    if (_proposal case final proposal?)
      ProposalBar(
        proposal: proposal,
        busy: _proposalBusy,
        closing: widget.eventOutbox?.closing(proposal.id)?.label,
        changes: _changedSince.length,
        joined: _hasDetails(proposal),
        onConfirm: _confirmProposal,
        onNote: _noteForClaude,
        onNotes: _showProposalNotes,
        onRetry: _finishProposal,
        onGoTo: _goToProposal,
        onAbandon: _abandonProposal,
        hidden: _hidden,
        onHide: _toggleHidden,
        onRevisited: switch (proposal.revisited) {
          [final first, ...] => () => _scrollToTime(first.start, nearTop: true),
          _ => null,
        },
        onFacts: () => showFactSummariesSheet(
          context,
          proposal,
          personNames: _personNames,
          factNames: {
            for (final t in _memory.traits ?? const <Trait>[])
              for (final f in t.facts) '${t.id}/${f.id}': f.name,
          },
        ),
      ),
    if (_shownProposal case final proposal?) _buildDetails(proposal),
  ];

  /// Pulling the days down, or the refresh button: everything shown again.
  Future<void> _refreshAll() {
    unawaited(_loadNotes());
    unawaited(_loadProposal());
    GoogleCalendars.of(context)?.refresh();
    return _refresh();
  }

  /// The days themselves, scrolled up and down by [_scroll].
  Widget _buildDays(ScrollPhysics? noDrag) => LayoutBuilder(
    builder: (context, view) => RefreshIndicator(
      onRefresh: _refreshAll,
      child: NotificationListener<ScrollEndNotification>(
        // The days' sliding, not the timeline's scrolling.
        onNotification: (notification) {
          if (notification.metrics.axis == Axis.horizontal) {
            _slidingTo = null;
          }
          return false;
        },
        // Raw pointers, so pinching doesn't contend with scrolling.
        child: Listener(
          onPointerDown: _pointerDown,
          onPointerMove: _pointerMove,
          onPointerUp: _pointerUp,
          onPointerCancel: _pointerUp,
          child: ListView(
            controller: _scroll,
            physics: noDrag ?? const AlwaysScrollableScrollPhysics(),
            children: [
              SizedBox(
                height: _height,
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: TimelineAxis(
                        day: _from,
                        dayEnd: _to,
                        scale: _scale,
                      ),
                    ),
                    Positioned.fill(
                      child: PageView.builder(
                        controller: _pages,
                        physics: _box != null || _noteAt != null
                            ? const NeverScrollableScrollPhysics()
                            : noDrag,
                        onPageChanged: (page) => _show(_dayAt(page)),
                        itemBuilder: (context, page) =>
                            _buildDay(context, _dayAt(page), view.maxHeight),
                      ),
                    ),
                    if ((_extendTo, _proposal) case (
                      final to?,
                      final proposal?,
                    ))
                      Positioned.fill(
                        child: WindowCursorView(
                          day: _from,
                          dayEnd: _to,
                          scale: _scale,
                          anchor: proposal.claudeThrough ?? proposal.through,
                          end: to,
                          onMove: _moveExtension,
                          onStep: ({required later}) {
                            final to = _extensionStep(later: later);
                            if (to != null) {
                              setState(() => _extendTo = to);
                            }
                          },
                          canStep: ({required later}) =>
                              _extensionStep(later: later) != null,
                          onOpen: _openExtension,
                          onDone: to.isAfter(proposal.through) ? _extend : null,
                          onCancel: () => setState(() => _extendTo = null),
                        ),
                      ),
                    if (_noteAt case final at?)
                      Positioned.fill(
                        child: NoteCursorView(
                          day: _from,
                          dayEnd: _to,
                          scale: _scale,
                          at: at,
                          onMove: _moveNoteCursor,
                          onStep: ({required later}) {
                            final to = _noteStep(later: later);
                            if (to != null) setState(() => _noteAt = to);
                          },
                          canStep: ({required later}) =>
                              _noteStep(later: later) != null,
                        ),
                      ),
                    if (_box case final box?)
                      Positioned.fill(
                        child: PendingEventBoxView(
                          day: _from,
                          dayEnd: _to,
                          scale: _scale,
                          box: box,
                          selected: _selected,
                          onSelect: (role) => setState(() => _selected = role),
                          overwrites: _overwrites,
                          covers: _covers,
                          pushed: _pushed,
                          label: switch (_moving) {
                            final event? =>
                              'Moving ${switch (event.summary) {
                                final s? when s.isNotEmpty => '“$s”',
                                _ => 'this event',
                              }}',
                            null => null,
                          },
                          onMoveCursor: (to) => _changeBox(
                            (box) =>
                                box.withCursor(_snap(to, CursorRole.anchor)),
                            fromOther: true,
                          ),
                          onMoveOther: (to) => _changeBox(
                            (box) => box.withOther(_snap(to, CursorRole.end)),
                          ),
                          onMoveBox: (to) => _changeBox(
                            (box) => box.movedTo(_snap(to, CursorRole.anchor)),
                            moved: true,
                          ),
                          onStep: _stepCursor,
                          canStep: _canStep,
                          commuteEnds: _commuteEnds,
                          onCommute: _commute,
                          onEditTime: _editTime,
                          // Picking, taps go to the events.
                          interactive: _selecting == null,
                          marks: _marksAt,
                          cuts: _cutsAt,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );

  /// [day]'s page: its events, over the [TimelineAxis], with the day
  /// before's stacked above, and the day after's below, shaded; or why
  /// its events can't be shown, in the middle of the [view] tall part of
  /// it on screen.
  Widget _buildDay(BuildContext context, DateTime day, double view) {
    // The app's, so a day sliding in is drawn as it slides, not after.
    final events = _eventsOn(day);
    final (from, to) = _stacked(day);
    double offset(DateTime time) =>
        timelineOffset(time, day: from, dayEnd: to, scale: _scale);
    // Above each day's midnight on the timeline, what's drawn for its
    // labels: where the days meet, the one above is cut off there.
    final pad = offset(from);
    final next = _dayAfter(day);
    final stacked = from != day;
    final days = stacked ? [from, day, next] : [day];
    final message = switch (events) {
      _ when day == _day && _error != null && (events?.isEmpty ?? true) =>
        LoadError(
          what: 'events',
          error: _error!,
          retryingAt: _loads.nextAttemptAt,
          onRetry: _refresh,
        ),
      null => const Padding(
        padding: EdgeInsets.all(16),
        child: CircularProgressIndicator(),
      ),
      [] => const StatusMessage(
        icon: Icons.event_busy,
        text: 'No events.\nTap + to add one.',
      ),
      _ => null,
    };
    return Stack(
      children: [
        for (final d in days)
          Positioned(
            left: 0,
            right: 0,
            top: offset(d) - pad,
            // At the foot of them all, past it -- so an event drawn past
            // midnight is there to tap, as far as it's drawn.
            height:
                timelineHeight(d, _scale) +
                (d == days.last ? _drawnPast(d) + _pastFoot : 0),
            child: _stackedDay(
              d,
              // Drawn from its midnight to the next, but at the top of
              // them all, and past the foot.
              clipTop: d == days.first ? 0 : pad,
              clipBottom: d == days.last ? 0 : pad,
              shaded: d != day,
            ),
          ),
        // Where the days meet: which is which.
        if (stacked) ...[
          _daysMeet(context, offset(day), above: from),
          _daysMeet(context, offset(next), below: next),
        ],
        if (message != null)
          // Still tapped through, to add one anywhere.
          IgnorePointer(
            ignoring: events != null,
            child: _inView(view, message),
          ),
      ],
    );
  }

  /// [day]'s events, on a timeline stacked with others: cut off
  /// [clipTop] from its top and [clipBottom] from its foot, where it
  /// meets the days either side of it, and [shaded] if it's not the day
  /// shown.
  Widget _stackedDay(
    DateTime day, {
    required double clipTop,
    required double clipBottom,
    required bool shaded,
  }) {
    final events = _eventsOn(day);
    final proposal = _shownProposal;
    return ClipRect(
      clipper: _InsetClipper(top: clipTop, bottom: clipBottom),
      child: Stack(
        children: [
          if (events != null)
            // Drawn past its foot, if an event's drawn past midnight -- and
            // cut off there, where the next day's drawn.
            OverflowBox(
              alignment: Alignment.topCenter,
              minHeight: 0,
              maxHeight: double.infinity,
              child: DayTimeline(
                // The day the page is for, to tell from those stacked with
                // it.
                key: shaded ? null : ValueKey(('shown', day)),
                events: events,
                day: day,
                actions: _actionsById,
                personNames: _personNames,
                locationNames: _locationNames,
                goalNames: _goalNames,
                scale: _scale,
                now: widget.clock(),
                lastCompaction: _lastCompaction,
                // In a proposal's window, its notes, drawn as it says.
                pendingNotes: [
                  for (final t in _pendingNotes)
                    // Unless the proposal draws it: one it's just been
                    // extended over is drawn here till it's back.
                    if (!(proposal?.covers(
                              t,
                              t.add(const Duration(seconds: 1)),
                            ) ??
                            false) ||
                        !(proposal?.notes.any((n) => n.time == t) ?? false))
                      t,
                ],
                reviewNotes: _reviewNotes,
                // While the cursor's up, events don't open: a tap on one
                // goes to the timeline under it, and moves the cursor
                // there.
                // Picking for a list, a tap picks the event; while the box
                // is up otherwise, events don't open.
                onTap: _selecting != null
                    ? _pick
                    : _box == null
                    ? _openEvent
                    : null,
                listed: _listed,
                // Pressed and held, it's moved: the box around it.
                onLongPress: _box == null && _noteAt == null
                    ? _startMoving
                    : null,
                googleEvents: GoogleCalendars.of(context)?.on(day) ?? const [],
                googleOnTop: _googleOnTop,
                weather: _weatherBand(),
                sun: _sunOn(day),
                temperatureLabel: AppSettings.of(context)
                    .temperatureUnit
                    .format,
                // A quarter hour after it's fetched, held till it's
                // fetched again.
                temperaturesFrom: Weather.of(context)?.forecast?.fetchedAt
                    .add(const Duration(minutes: 15)),
                temperatures: _temperatures(),
                onTapGoogle: _box == null && _selecting == null
                    ? _openGoogleEvent
                    : null,
                faded: _moving?.id,
                highlighted: _highlighted,
                // Placing a note, the event it's in; or else J and K's.
                keyed: _noteAt != null ? _noteInside?.id : _keyed,
                // While the box is up, what its cursors stop at.
                pulseNotes: _snapsTo(SnapTo.notes),
                pulseEdges: _snapsTo(SnapTo.events),
                review: proposal == null
                    ? null
                    : (
                        from: proposal.windowStart,
                        // Being extended, as far as it's going.
                        through: _extendTo ?? proposal.through,
                        claudeThrough:
                            proposal.claudeThrough ?? proposal.through,
                      ),
                onTapThrough: _canExtend ? _startExtending : null,
                marks: _marks,
                // Before there's a box, the cursor moved there; after, the
                // box stays put. Picking, a tap only picks.
                onTapTime:
                    _box?.span != null || _box == null || _selecting != null
                    ? null
                    : (time) => _changeBox(
                        (box) => box.movedTo(_snap(time, CursorRole.anchor)),
                        moved: true,
                      ),
                axis: false,
              ),
            ),
          if (shaded)
            // The days either side, under a shadow: there to see, and to
            // make or move events across midnight into, but not the day
            // shown. Not past its foot.
            Positioned(
              left: 0,
              right: 0,
              top: 0,
              height: timelineHeight(day, _scale),
              child: IgnorePointer(
                child: ColoredBox(
                  color: Theme.of(context).colorScheme.surface
                      .withValues(alpha: 0.55),
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// The line at midnight, [y] down the timeline, where the days meet:
  /// the day [above] it named above it, or the day [below] it, below.
  Widget _daysMeet(
    BuildContext context,
    double y, {
    DateTime? above,
    DateTime? below,
  }) {
    final colors = Theme.of(context).colorScheme;
    final day = above ?? below!;
    return Positioned(
      left: 0,
      right: 0,
      top: y - 24,
      height: 48,
      child: IgnorePointer(
        child: Stack(
          children: [
            Positioned(
              left: 0,
              right: 0,
              top: 23.5,
              height: 1,
              child: ColoredBox(color: colors.outline),
            ),
            Positioned(
              left: 4,
              top: above != null ? 2 : 27,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: colors.surfaceContainerHighest,
                  border: Border.all(color: colors.outline),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      above != null ? Icons.arrow_upward : Icons.arrow_downward,
                      size: 12,
                      color: colors.onSurfaceVariant,
                    ),
                    const SizedBox(width: 2),
                    Text(
                      MaterialLocalizations.of(context).formatMediumDate(day),
                      style: TextStyle(
                        color: colors.onSurfaceVariant,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// [child] on a card in the middle of the [view] tall part of the
  /// timeline on screen, over the axis, kept there as it scrolls.
  Widget _inView(double view, Widget child) => ListenableBuilder(
    listenable: _scroll,
    builder: (context, child) {
      final scrolled = _scroll.hasClients && _scroll.position.hasPixels
          ? _scroll.position.pixels
          : 0.0;
      final end = _height - view;
      return Padding(
        padding: EdgeInsets.only(top: scrolled.clamp(0.0, math.max(0.0, end))),
        child: SizedBox(
          height: view,
          child: Center(child: child),
        ),
      );
    },
    child: Card(child: child),
  );
}

/// One of the things a proposal adds, and how the user settled it, if
/// they have.
typedef _Added = ({ProposalAddition addition, AdditionSettled? settled});

/// A goal change the proposal makes, or made: [change] as it stands, how
/// the user [settled] it, if they have, and [claudes], as Claude first
/// proposed it -- null for one of the user's own.
typedef _GoalChanged = ({
  ProposalGoalChange change,
  GoalChangeSettled? settled,
  ProposalGoalChange? claudes,
});

/// Where whether a proposal's details are folded away is kept.
const _detailsCollapsedKey = 'proposal_details_collapsed';

/// Where whether the day's summary is folded away is kept.
const _summaryCollapsedKey = 'day_summary_collapsed';
const _allDayCollapsedKey = 'google_all_day_collapsed';
const _goalsDueCollapsedKey = 'goals_due_collapsed';
const _weatherCollapsedKey = 'weather_strip_collapsed';
const _googleOnTopKey = 'google_on_top';

/// Where whether the day's summary shows durations is kept.
const _summaryDurationsKey = 'day_summary_durations';

/// Clips [top] off the top of what it's given, and [bottom] off its foot.
class _InsetClipper extends CustomClipper<Rect> {
  const _InsetClipper({required this.top, required this.bottom});

  final double top;
  final double bottom;

  @override
  Rect getClip(Size size) =>
      Rect.fromLTRB(0, top, size.width, math.max(top, size.height - bottom));

  @override
  bool shouldReclip(_InsetClipper old) =>
      old.top != top || old.bottom != bottom;
}

/// What clearing the time does, mostly (see [_EventsScreenState._clearing]).
enum _Clearing { cancels, pushes, trims }

/// A commute queued with a move, at one of the box's ends: a change to
/// [event], the commute there already, or -- if it's null -- a new one,
/// made against the box's edge; as [fields] say, or, if they're null,
/// [event] taken away.
typedef _CommuteEdit = ({Event? event, _CommuteFields? fields});

/// A commute's [summary], its actions -- one of them a way to commute --
/// and how long it takes.
typedef _CommuteFields = ({
  String summary,
  List<String> actionIds,
  Duration length,
});

/// Where a commute at one of a moved event's ends is from and to, each
/// null if unknown, and the [commute] there to edit, if there's one.
typedef _CommutePlace = ({String? fromId, String? toId, Event? commute});
