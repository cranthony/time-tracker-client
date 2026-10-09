import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/event.dart';
import '../models/person.dart';
import '../models/plan_action.dart';
import '../models/note.dart';
import '../models/proposal.dart';
import '../models/recurrence.dart';
import '../outbox/event_outbox.dart';
import '../outbox/note_outbox.dart';
import '../services/app_settings.dart';
import '../services/actions_repository.dart';
import '../services/event_store.dart';
import '../services/events_repository.dart';
import '../services/habits_repository.dart';
import '../services/mcp_client.dart';
import '../services/events_place.dart';
import '../services/notes_repository.dart';
import '../services/people_repository.dart';
import '../services/plan_memory.dart';
import '../services/proposal_repository.dart';
import '../services/traits_repository.dart';
import '../widgets/window_cursor.dart';
import '../widgets/cursor_modes.dart';
import '../widgets/cursor_sheet.dart';
import '../widgets/cursor_snap.dart';
import '../widgets/app_menu.dart';
import '../widgets/day_header.dart';
import '../widgets/day_summary.dart';
import '../widgets/pending_event_box.dart';
import '../widgets/day_timeline.dart';
import '../widgets/error_sheet.dart';
import '../widgets/event_dialog.dart';
import '../widgets/follow_through_dialog.dart';
import '../widgets/other_events.dart';
import '../widgets/event_summary_dialog.dart';
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
    this.eventOutbox,
    this.showEventRequests,
    this.onSignIn,
    this.onSignOut,
    this.version,
    this.placeStore,
    this.memory,
    this.proposals,
    this.proposalSeen,
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

  /// Where to list actions from, to pick an event's; null to type their ids.
  final ActionsRepository? actionsRepository;

  /// Where to load the notes not yet compacted from, to mark them; null
  /// not to.
  final NotesRepository? notesRepository;

  /// The notes not saved yet, to mark them too.
  final NoteOutbox? outbox;

  /// Where changes to events and the proposal wait to be saved; without
  /// it, each is saved before its dialog closes.
  final EventOutbox? eventOutbox;

  /// Events to show: each, its day gone to, scrolled to it, and
  /// highlighted a moment.
  final Stream<Event>? showEventRequests;

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

  late final PageController _pages;

  /// Whether it's still finding out where it was left, so not to scroll
  /// to the start yet.
  bool _placePending = false;

  /// The time to scroll to the top, where it was left, in place of now
  /// or the first event.
  DateTime? _restoreTop;

  /// The event highlighted, having been asked to show it, a moment.
  String? _highlighted;
  Timer? _unhighlight;
  StreamSubscription<Event>? _showEvents;

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

  /// The cursor last touched: its buttons win where they'd overlap
  /// another's.
  CursorRole _selected = CursorRole.anchor;

  /// Where keeping events last moved the box, from where it was put, to
  /// show with a [KeptMoveArrow]; [id] tells each move from the last.
  ({DateTime from, DateTime to, int id})? _keptMove;

  /// What the box does with the events in its way: as last picked, for
  /// a new event; a move starts out pushing.
  EndMode _endMode = EndMode.trim;

  /// What it does with the event its first cursor is inside of, to match:
  /// trims or cancels it, if it trims or cancels the rest; keeping, or
  /// pushing, keeps clear of it.
  AnchorMode get _anchorMode => switch (_endMode) {
    EndMode.trim => AnchorMode.trim,
    EndMode.cancel => AnchorMode.cancel,
    EndMode.keep || EndMode.push => AnchorMode.keep,
  };

  /// Whether the box changes the events in its way.
  bool get _overwritesAny => _anchorMode.changes || _endMode != EndMode.keep;

  /// Why the day shown couldn't be loaded, if it couldn't.
  Object? _error;
  bool _needsSignIn = false;
  bool _signingIn = false;

  /// The actions by id, for the colors and names of events' actions; empty
  /// until they're loaded, or without actions.
  Map<String, PlanAction> get _actionsById => {
    for (final action in _memory.actions?.actions ?? const <PlanAction>[])
      ?action.id: action,
  };

  /// When notes were last compacted; null until it's known.
  DateTime? get _lastCompaction => _memory.lastCompaction;

  /// When each saved note not yet compacted was taken; empty until
  /// they're loaded.
  List<DateTime> get _savedNotes => [
    for (final n in _memory.notes ?? const <Note>[]) n.timestamp,
  ];

  /// Whether the day's summary is folded away.
  bool _summaryCollapsed = false;

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

  /// How tall the timeline is, with the days on it: clear of the
  /// buttons at the foot, with room for an event drawn past midnight.
  double get _height => timelineSpanHeight(_from, _to, _scale) + _pastFoot;

  /// What's below the last day on the timeline.
  static const _pastFoot = 170.0;

  /// The open compaction proposal as the server last gave it, once it's
  /// loaded; null without one.
  Proposal? _loadedProposal;

  /// The open compaction proposal, as shown: with the edits of it waiting
  /// to be saved.
  Proposal? get _proposal =>
      widget.eventOutbox?.projectProposal(_loadedProposal) ?? _loadedProposal;
  set _proposal(Proposal? proposal) => _loadedProposal = proposal;

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

  /// Which of the proposal's notes is shown under its bar, and
  /// highlighted on the timeline.
  /// Null for the first note to review.
  int? _noteIndex;

  /// Which page of the proposal's details is shown under its bar: its
  /// notes, its cancels, or what it adds.
  ProposalDetailPage _detailPage = ProposalDetailPage.notes;

  /// The page of the proposal's details shown: [_detailPage], if it has
  /// anything on it, or else the first that has.
  ProposalDetailPage? get _shownPage {
    final pages = [
      if (_note != null) ProposalDetailPage.notes,
      if (_cancel != null) ProposalDetailPage.followThrough,
      if (_addition != null) ProposalDetailPage.added,
    ];
    return pages.contains(_detailPage) ? _detailPage : pages.firstOrNull;
  }

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
    };
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
    ProposalDetailPage.followThrough => {?_cancel?.id},
    ProposalDetailPage.added => switch (_addition) {
      final a? => {for (final e in _usesOf(a)) e.id},
      null => const {},
    },
    ProposalDetailPage.notes || null => const {},
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

  /// The proposal's notes, as the timeline draws them.
  List<ReviewNote> get _reviewNotes {
    final selected = _shownPage == ProposalDetailPage.notes ? _note : null;
    return [
      for (final note in _proposalNotes)
        ReviewNote(
          time: note.time,
          kind: reviewNoteKind(note, of: _proposal),
          selected: note.id == selected?.id,
        ),
    ];
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
      _placePending = false;
      _scrollPending = false;
      _restoreTop = null;
      _highlighted = event.id;
    });
    _scrollToTime(event.start);
    _unhighlight = Timer(const Duration(seconds: 4), () {
      if (mounted) setState(() => _highlighted = null);
    });
  }

  /// Shows [time]'s day, scrolled so [time] is in the middle of the view.
  void _scrollToTime(DateTime time) {
    final at = time.toLocal();
    final day = _midnight(at);
    if (_pages.hasClients && day != _day) _pages.jumpToPage(_pageOf(day));
    // Once it's laid out on that day.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      final position = _scroll.position;
      final y =
          timelineOffset(at, day: day, dayEnd: _dayAfter(day), scale: _scale) -
          position.viewportDimension / 2;
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
  /// open proposal says happened, as it says.
  List<Event>? _eventsOn(DateTime day) => switch (_store.day(day)) {
    final events? => _withProposal(
      _waiting(events, day, _dayAfter(day)),
      day,
      _dayAfter(day),
    ),
    null => null,
  };

  /// [events], the calendar's from [from] to [to], with the changes
  /// waiting to be saved made to them.
  List<Event> _waiting(List<Event> events, DateTime from, DateTime to) =>
      widget.eventOutbox?.project(events, from, to) ?? events;

  /// [calendar], the calendar's events from [from] to [to], with those
  /// that the open proposal says happened as it says: a new one added,
  /// and a cancelled one shown cancelled -- unless another is in its place.
  List<Event> _withProposal(List<Event> calendar, DateTime from, DateTime to) {
    final reviewed = _proposal?.reviewed ?? const <ProposalEvent>[];
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
          e.toEvent(byId[e.id], _proposal?.addedNames ?? const {}),
    ]..sort((a, b) => a.start.compareTo(b.start));
  }

  /// Whether [event] is in what the open proposal says happened: changed
  /// in it, not on the calendar.
  bool _inReview(Event event) => _proposal?.event(event.id)?.reviewed ?? false;

  /// Whether an event from [start] to [end] would be in what the open
  /// proposal says happened.
  bool _reviews(DateTime start, DateTime end) =>
      _proposal?.covers(start, end) ?? false;

  /// The events changed since the user last looked at the proposal.
  Set<String> get _changedSince =>
      (_proposal?.changedSince ?? const {}).difference(_editedHere);

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
    final proposal = _proposal;
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
    if (mounted) setState(() {});
  }

  /// Loads everyone, every location, every trait and Self's habits, for
  /// an event's dialogs to name at once. Best effort.
  Future<void> _prefetchNames() async {
    if (!mounted) return;
    final memory = _memory;
    // Asked afresh each time the page opens.
    memory.newVisit();
    await memory.prefetchNames(
      traits: TraitsScope.of(context),
      people: PeopleScope.of(context),
      habits: HabitsScope.of(context),
    );
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
    _lifecycle = AppLifecycleListener(onHide: _savePlace);
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
    _savedWrites = widget.eventOutbox?.saved.listen(_writeSaved);
    _showEvents = widget.showEventRequests?.listen(_showEvent);
    _loadNotes(cached: true);
    _showKeptProposal();
    _loadProposal();
    _loadSummaryCollapsed();
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
        _store.putEvents(events);
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
  /// saved ones again once more are saved.
  void _outboxChanged() {
    if (!mounted) return;
    setState(() {});
    if (widget.outbox!.wantsFetch) _loadNotes();
  }

  /// Loads the saved notes not yet compacted, after those kept from last
  /// time if [cached], and when notes were last compacted. Best effort:
  /// without them, they aren't marked.
  Future<void> _loadNotes({bool cached = false}) async {
    final repository = widget.notesRepository;
    if (repository == null) return;
    if (cached) await _memory.loadKept(notes: repository);
    unawaited(
      _memory.loadCompaction(repository, again: true).catchError((Object _) {}),
    );
    final fetched = widget.outbox?.fetching();
    try {
      await _memory.loadNotes(repository, again: true);
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
    // Asked to show an event meanwhile: there, not where it was left.
    if (!mounted || _highlighted != null) return;
    final kept = place != null && place.keptAt(widget.clock());
    setState(() {
      _placePending = false;
      if (!kept) return;
      _scale = place.scale;
      _restoreTop = place.top;
    });
    if (kept && _pages.hasClients) _pages.jumpToPage(_pageOf(place.day));
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
    widget.outbox?.removeListener(_outboxChanged);
    widget.eventOutbox?.removeListener(_memoryChanged);
    _savedWrites?.cancel();
    _showEvents?.cancel();
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
    final stacked = box != null;
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

  /// Shows today, scrolled so now is about a third of the way down.
  void _goToNow() {
    final now = widget.clock();
    final today = _midnight(now);
    if (_pages.hasClients && today != _day) {
      _pages.jumpToPage(_pageOf(today));
    }
    // Once it's laid out on today.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      final position = _scroll.position;
      final (from, to) = _stacked(today);
      final y =
          timelineOffset(now, day: from, dayEnd: to, scale: _scale) -
          position.viewportDimension / 3;
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
    try {
      final events = await widget.repository.events(which, _dayAfter(which));
      if (!mounted) return;
      _store.putDay(which, events);
      setState(() {
        _fresh.add(which);
        if (which == _day) {
          _error = null;
          _needsSignIn = false;
        }
      });
    } on SignInRequiredException {
      if (!mounted || which != _day) return;
      setState(() {
        _fresh.remove(which);
        _needsSignIn = true;
      });
    } catch (e) {
      if (!mounted || which != _day) return;
      setState(() {
        _error = e;
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
      _day = day;
      _error = null;
      _fresh.removeWhere((d) => (_pageOf(d) - _pageOf(day)).abs() > 3);
      if (_box case final box?) _keep(box, moved: true);
    });
    _refresh(reloadShown: !_fresh.contains(day));
  }

  /// Opens [event]'s summary, and from it, its details.
  Future<void> _openEvent(Event event) async {
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
    if (_writes.queued) {
      // Shown as made (see _proposal), till it's saved.
      final amended = await _writes.amend(
        _loadedProposal!,
        edits,
        label: label,
      );
      if (mounted) setState(() {});
      return amended;
    }
    try {
      final amended = await _writes.amend(proposal, edits, label: label);
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
  void _startCreating() {
    final now = widget.clock();
    DateTime at;
    if (!now.isBefore(_day) && now.isBefore(_dayEnd)) {
      at = now;
    } else if (_scroll.hasClients) {
      final middle = _scroll.offset + _scroll.position.viewportDimension / 2;
      at = timelineTime(middle, day: _from, dayEnd: _to, scale: _scale);
    } else {
      at = _day.add(const Duration(hours: 9));
    }
    final settings = AppSettings.of(context);
    setState(() {
      _endMode = settings.endMode;
      _selected = CursorRole.anchor;
      _setBox(PendingEventBox(_onGrid(at)));
      _keptMove = null;
    });
  }

  /// Starts moving [event]: the box around it, pushing the events in its
  /// way to start with.
  void _startMoving(Event event) {
    if (event.isCancelled) return;
    setState(() {
      _moving = event;
      _setBox(PendingEventBox(event.start, other: event.end));
      _keptMove = null;
      _selected = CursorRole.anchor;
      _endMode = EndMode.push;
    });
  }

  /// Puts the box away -- the new event or the move done, or dropped.
  void _endBox() => setState(() {
    _setBox(null);
    _moving = null;
  });

  /// Saves the move of [_moving] to the box, and what it does to the
  /// events in its way, in one batch.
  Future<void> _finishMoving() async {
    final event = _moving;
    final span = _box?.span;
    if (event == null || span == null) return;
    final (start, end) = span;
    if (start == event.start && end == event.end) return _endBox();
    final makingRoom = _overwritesAny
        ? _overwrite(_otherEvents(event), start, end)
        : const Overwrite();
    final asked = await askFollowThrough(context, makingRoom.cancels);
    // Called off: the box stays up, as it was.
    if (asked == null || !mounted) return;
    final inTheWay = makingRoom.counting(asked);
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
          ProposalEdits.over(inTheWay, updates: [proposalUpdate(event, times)]),
          label: 'Move ${_named(event)}, in what happened',
        );
      } else {
        changed = await _approvingHistory(
          at: start.isBefore(event.start) ? start : event.start,
          (allow) => _writes.makeRoom(
            Overwrite(
              updates: [(event, times), ...inTheWay.updates],
              cancels: inTheWay.cancels,
              creates: inTheWay.creates,
              countsAgainst: inTheWay.countsAgainst,
            ),
            allowHistory: allow,
            label: inTheWay.isEmpty
                ? 'Move ${_named(event)}'
                : 'Move ${_named(event)}, changing ${_events(inTheWay.count)}',
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
    _store.putEvents(changed);
    _fresh.clear();
    // The proposal is planned from the calendar as it is now.
    unawaited(_loadProposal());
    await _refresh();
  }

  /// [box] as its cursors' modes let it be. Its anchor, kept, out of
  /// any event it's inside of, once there's a box: to its edge on the
  /// box's side. Kept by its end too: fitted into free time
  /// (see [OtherEvents]) -- [moved] whole, as near as it fits; or from its
  /// anchor -- or, [fromOther], its end -- to no further than the next
  /// event; otherwise, up to the next event but the anchor's. Pushing, no
  /// further than leaves the day room for what it pushes.
  PendingEventBox _kept(
    PendingEventBox box, {
    bool moved = false,
    bool fromOther = false,
  }) {
    final others = _otherEvents(_moving);
    var (cursor, other) = (box.cursor, box.other);
    final keepAnchor = _anchorMode == AnchorMode.keep;
    if (keepAnchor && _endMode == EndMode.keep && other != null) {
      if (moved) {
        final start = box.span?.$1 ?? box.cursor;
        final (from, to) = others.fitMoved(
          start,
          box.length,
          from: _from,
          to: _to,
        );
        return box.at(from, to);
      }
      if (fromOther) {
        final (fitted, anchor) = others.fitFrom(other, cursor);
        return PendingEventBox(anchor, other: fitted);
      }
      final (anchor, fitted) = others.fitFrom(cursor, other);
      return PendingEventBox(anchor, other: fitted);
    }
    if (other == null || other == cursor) {
      return PendingEventBox(cursor, other: other);
    }
    final later = other.isAfter(cursor);
    // Kept, the anchor out of any event it's in, to its edge on the box's
    // side -- the box with it, its length kept.
    if (keepAnchor) {
      var snapped = cursor;
      for (var i = 0; i < 100; i++) {
        final at = others.inside(snapped);
        if (at == null) break;
        snapped = later ? at.end : at.start;
      }
      other = other.add(snapped.difference(cursor));
      cursor = snapped;
    }
    switch (_endMode) {
      case EndMode.keep:
        final at = others.inside(cursor);
        final rest = OtherEvents(others.events.where((e) => e != at));
        if (later) {
          if (rest.latestEnd(cursor) case final next?
              when next.isBefore(other)) {
            other = next;
          }
        } else if (rest.earliestStart(cursor) case final last?
            when last.isAfter(other)) {
          other = last;
        }
      case EndMode.push:
        other = others.pushFit(
          cursor,
          other,
          from: _from,
          to: _to,
          inside: _anchorMode == AnchorMode.splitPush
              ? Inside.split
              : Inside.trim,
        );
      case EndMode.trim || EndMode.cancel:
        break;
    }
    return PendingEventBox(cursor, other: other);
  }

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

  /// Makes the box [box], kept in free time (see [_kept]); if that moves
  /// it, an arrow shows from where it was put to where it went.
  void _keep(
    PendingEventBox box, {
    bool moved = false,
    bool fromOther = false,
  }) {
    final kept = _kept(box, moved: moved, fromOther: fromOther);
    _box = kept;
    if (kept == box) return;
    // The box's middle, moved whole; or the end that moved.
    DateTime middle(PendingEventBox box) =>
        (box.span?.$1 ?? box.cursor).add(box.length ~/ 2);
    final (from, to) = moved
        ? (middle(box), middle(kept))
        : box.cursor != kept.cursor
        ? (box.cursor, kept.cursor)
        : (box.other ?? box.cursor, kept.other ?? kept.cursor);
    // Still going to the same place, as a drag goes on: the same arrow,
    // from where it's put now.
    final last = _keptMove;
    final id = last == null
        ? 1
        : last.to == to
        ? last.id
        : last.id + 1;
    _keptMove = (from: from, to: to, id: id);
  }

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

  /// What the box does to the events in its way, as it is.
  Overwrite? get _inTheWay => switch (_box?.span) {
    (final start, final end) => _overwrite(_otherEvents(_moving), start, end),
    null => null,
  };

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
    final o = _inTheWay;
    if (o == null) return false;
    // Split, the anchor's event isn't lost: the rest goes after the box.
    final split = _anchorMode == AnchorMode.splitPush
        ? _otherEvents(_moving).inside(_box!.cursor)
        : null;
    return o.cancels.isNotEmpty ||
        o.updates.any((u) => u.$1 != split && !_moves(u.$1, u.$2));
  }

  /// Where the events the new one pushes go, and the rest of one it
  /// splits.
  List<PushedEvent> get _pushed => switch (_inTheWay) {
    final o? => [
      for (final (event, changes) in o.updates)
        if (_moves(event, changes))
          (
            start: DateTime.parse(changes['start']! as String).toLocal(),
            end: DateTime.parse(changes['end']! as String).toLocal(),
            label: event.summary ?? 'Event',
          ),
      for (final rest in o.creates)
        (
          start: DateTime.parse(rest['start'] as String).toLocal(),
          end: DateTime.parse(rest['end'] as String).toLocal(),
          label: '${rest['summary'] ?? 'Event'} (the rest)',
        ),
    ],
    null => const [],
  };

  /// What the shadow covers, cancelling: the box, and every event it
  /// cancels, whole. Null otherwise: just the box.
  (DateTime, DateTime)? get _covers => switch ((_box?.span, _inTheWay)) {
    ((final start, final end), final o?) when o.cancels.isNotEmpty => (
      [
        start,
        for (final e in o.cancels) e.start,
      ].reduce((a, b) => a.isBefore(b) ? a : b),
      [
        end,
        for (final e in o.cancels) e.end,
      ].reduce((a, b) => a.isAfter(b) ? a : b),
    ),
    _ => null,
  };

  /// What an event from [start] to [end] does to the [others] in its
  /// way, as its cursors' modes say: its anchor the [start], for one
  /// [later] (the way the box goes, unless said), or else its [end].
  Overwrite _overwrite(
    OtherEvents others,
    DateTime start,
    DateTime end, {
    bool? later,
  }) {
    final l = later ?? _later;
    return others.around(
      anchor: l ? start : end,
      end: l ? end : start,
      anchorMode: _anchorMode,
      endMode: _endMode,
    );
  }

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
            settings.snapFor(CursorRole.windowEnd).contains(snap));
  }

  /// Whether the proposal's window can be extended: it's being reviewed,
  /// nothing else is up, and there's time since it ends.
  bool get _canExtend => switch (_proposal) {
    final p? =>
      p.state == ProposalState.awaitingReview &&
          !_proposalBusy &&
          _box == null &&
          _extendTo == null &&
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
  /// -- keeping -- not out of free time it's at the edge of.
  bool _canStep(CursorRole role, {required bool later}) {
    final box = _box;
    if (box == null || _stepTo(role, later: later) == null) return false;
    final anchor = role == CursorRole.anchor;
    final keeps = anchor
        ? _anchorMode == AnchorMode.keep
        : _endMode == EndMode.keep;
    if (!keeps) return true;
    final at = anchor ? box.cursor : box.other ?? box.cursor;
    // Into the box, it's free; out of it, not into an event it touches.
    final other = anchor ? box.other : box.cursor;
    if (other != null &&
        !other.isAtSameMomentAs(at) &&
        other.isAfter(at) == later) {
      return true;
    }
    final others = _otherEvents(_moving).events;
    return !others.any((e) => (later ? e.start : e.end).isAtSameMomentAs(at));
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

    final created = await showNewEventDialog(
      context,
      start: start,
      end: end,
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
    _store.putEvents(created);
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

  /// What the box does with the events in its way, in a sheet: kept for
  /// the next new event, but a move's isn't.
  Future<void> _openBox() async {
    final settings = AppSettings.of(context);
    await showCursorSheet(
      context,
      title: 'Events in the way',
      endMode: _endMode,
      onEndMode: (mode) {
        setState(() => _endMode = mode);
        if (_moving == null) settings.setEndMode(mode);
        _changeBox((box) => box);
      },
    );
  }

  /// What a cursor at [time] is on: the starts and ends of the events
  /// there, and the notes.
  List<SnapMark> _marksAt(DateTime time) {
    final events = _otherEvents(_moving).events;
    String name(Event e) => switch (e.summary) {
      final s? when s.trim().isNotEmpty => s.trim(),
      _ => 'an event',
    };
    return [
      for (final e in events)
        if (e.start.isAtSameMomentAs(time)) (what: 'start', name: name(e)),
      for (final e in events)
        if (e.end.isAtSameMomentAs(time)) (what: 'end', name: name(e)),
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
    _store.putEvents(updated);
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
          return _memory.actions?.actions ?? const [];
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
    return _onProposal(
      "Couldn't confirm it",
      (proposal, repository) async =>
          _confirmed(proposal, await repository.confirm(proposal)),
    );
  }

  /// Resumes the apply of the open proposal, where it stopped.
  Future<void> _finishProposal() => _onProposal(
    "Couldn't finish it",
    (proposal, repository) async =>
        _confirmed(proposal, await repository.finish(proposal)),
  );

  /// Shows what confirming [proposal], or finishing it, came to: applied,
  /// it's history; rechecked, or rebuilt, a new revision to confirm; or
  /// handed to Claude.
  Future<void> _confirmed(Proposal proposal, ProposalOutcome outcome) async {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final next = outcome.proposal;
    switch (outcome.status) {
      case ProposalOutcomeStatus.applied:
        _sawProposal();
        setState(() {
          _proposal = null;
          _editedHere.clear();
        });
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              'Confirmed: what happened '
              '${windowLabel(context, proposal.windowStart, proposal.through)} '
              'is recorded.',
            ),
          ),
        );
        _fresh.clear();
        // The last compaction is its through now.
        unawaited(_loadNotes());
        await _refresh();
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
        setState(() => _proposal = null);
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
  }) async {
    final subject = switch ((aboutNote, aboutAddition)) {
      (final n?, _) => 'About ${_noteNames[n.id]}',
      (_, final a?) =>
        'About the new ${a.kind.label.toLowerCase()} “${a.name}”',
      _ => null,
    };
    final note = await showProposalNoteDialog(
      context,
      events: _reviewedNames,
      about: about,
      subject: subject,
    );
    if (note == null || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    await _onProposal("Couldn't leave the note", (proposal, repository) async {
      await repository.addNote(
        proposal,
        note.text,
        // What's added is named by its ref.
        eventId: switch ((aboutNote, aboutAddition)) {
          (null, null) => note.eventId,
          (_, final a?) => a.ref,
          _ => null,
        },
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
    await _onProposal("Couldn't abandon it", (proposal, repository) async {
      await repository.abandon(proposal);
      if (!mounted) return;
      setState(() => _proposal = null);
    });
  }

  /// Shows the start of what the open proposal says happened.
  void _goToProposal() {
    final proposal = _proposal;
    if (proposal == null) return;
    final from = proposal.windowStart.toLocal();
    final day = _midnight(from);
    if (_pages.hasClients && day != _day) _pages.jumpToPage(_pageOf(day));
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
    if (picked != null && _pages.hasClients) {
      _pages.jumpToPage(_pageOf(_midnight(picked)));
    }
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
    final today = widget.clock();
    return Scaffold(
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
          ),
        ],
      ),
      body: RefreshingBar(
        refreshing: _stale && _error == null && !_needsSignIn,
        child: _needsSignIn ? _buildSignIn() : _buildTimeline(),
      ),
      floatingActionButton: _needsSignIn
          ? null
          : _box != null
          ? Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                FloatingActionButton.small(
                  heroTag: 'to-new',
                  tooltip: 'Go to the new event',
                  onPressed: _goToBox,
                  child: const Icon(Icons.filter_center_focus),
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    FloatingActionButton(
                      heroTag: 'cancel-new',
                      tooltip: 'Cancel',
                      onPressed: _endBox,
                      child: const Icon(Icons.close),
                    ),
                    const SizedBox(width: 12),
                    // Only with an event to make.
                    Builder(
                      builder: (context) {
                        final colors = Theme.of(context).colorScheme;
                        final ready = _box?.span != null;
                        return FloatingActionButton(
                          heroTag: 'continue-new',
                          tooltip: !ready
                              ? 'Continue: first, make an event between the '
                                    'cursors'
                              : _moving != null
                              ? 'Move it here'
                              : 'Continue',
                          onPressed: !ready
                              ? null
                              : _moving != null
                              ? _finishMoving
                              : _continueCreating,
                          backgroundColor: ready
                              ? null
                              : colors.surfaceContainerHighest,
                          foregroundColor: ready ? null : colors.outline,
                          elevation: ready ? null : 0,
                          child: const Icon(Icons.check),
                        );
                      },
                    ),
                  ],
                ),
              ],
            )
          : Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                FloatingActionButton.small(
                  heroTag: 'now',
                  tooltip: 'Go to now',
                  onPressed: _goToNow,
                  child: const Icon(Icons.my_location),
                ),
                const SizedBox(height: 12),
                FloatingActionButton(
                  heroTag: 'new',
                  tooltip: 'New event',
                  onPressed: _startCreating,
                  child: const Icon(Icons.add),
                ),
              ],
            ),
    );
  }

  /// Under the proposal's bar, its details, a page each: its notes, its
  /// cancels and whether they count against follow-through, and what it
  /// adds -- each one at a time, stepped through.
  Widget _buildDetails(Proposal proposal) {
    final notes = _proposalNotes;
    final note = _note;
    final cancels = proposal.cancels;
    final cancel = _cancel;
    final added = _additions;
    final addition = _addition;
    int indexOf<T>(List<T> list, bool Function(T) test) =>
        list.indexWhere(test);
    final noteAt = note == null ? -1 : indexOf(notes, (n) => n.id == note.id);
    final cancelAt = cancel == null
        ? -1
        : indexOf(cancels, (e) => e.id == cancel.id);
    final additionAt = addition == null
        ? -1
        : indexOf(added, (a) => a.addition.ref == addition.addition.ref);
    // Its pages, as it'll have them: those with something on.
    final pages = [
      if (note != null) ProposalDetailPage.notes,
      if (cancel != null) ProposalDetailPage.followThrough,
      if (addition != null) ProposalDetailPage.added,
    ];
    return ProposalDetails(
      initialPage: switch (pages.indexOf(_detailPage)) {
        -1 => 0,
        final i => i,
      },
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
              onSettle: _proposalBusy ? null : () => _settle(addition),
              onPrevious: additionAt > 0
                  ? () => _goToAddition(additionAt - 1)
                  : null,
              onNext: additionAt < added.length - 1
                  ? () => _goToAddition(additionAt + 1)
                  : null,
            ),
      addCount: added.length,
      collapsed: _detailsCollapsed,
      onCollapsed: _setDetailsCollapsed,
      onPage: (page) => setState(() => _detailPage = page),
    );
  }

  /// Asks what's to become of [added], and amends the proposal so: made
  /// now, one already there, dropped, or put back as Claude proposed it
  /// -- or leaves a note for Claude about it.
  Future<void> _settle(_Added added) async {
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
          for (final action in _memory.actions?.actions ?? const <PlanAction>[])
            if (!action.isGroup &&
                action.id != null &&
                action.status != 'deleted')
              (id: action.id!, name: actionName(action), detail: null),
        ],
      },
    ];
    final choice = await showAdditionSheet(
      context,
      a,
      settled: added.settled,
      settledAs: _settledName(added.settled, a.kind),
      existing: existing,
    );
    if (choice == null || !mounted) return;
    ProposalEdits settling(
      AdditionUse use, {
      String? id,
      String? name,
      String? detail,
    }) => ProposalEdits(
      additions: [
        (
          ref: a.ref,
          use: use,
          id: id,
          name: name,
          detail: detail,
          kind: a.kind,
        ),
      ],
    );
    final kind = a.kind.label.toLowerCase();
    final (edits, said) = switch (choice) {
      CreateAddition(:final name, :final detail) => (
        settling(AdditionUse.create, name: name, detail: detail),
        'Made the $kind “$name”.',
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
      AskAboutAddition() => (null, null),
    };
    if (edits == null) return _noteForClaude(aboutAddition: a);
    await runOrShowError(
      context,
      title: "Couldn't settle it",
      action: () async {
        final amended = await _amend(edits);
        if (!mounted) return;
        _amended(amended, said!);
        // Made now: named from where it's kept.
        if (choice is CreateAddition) {
          _memory.newVisit();
          unawaited(_prefetchNames());
          unawaited(_loadActions());
        }
      },
    );
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
          : FilledButton(
              onPressed: _signingIn ? null : _signIn,
              child: Text(_signingIn ? 'Waiting for browser…' : 'Sign in'),
            ),
    ),
  );

  /// The days side by side over the [TimelineAxis], all scrolled up and
  /// down at once.
  Widget _buildTimeline() {
    final events = _shown;
    _scrollToStart();
    final noDrag = _pinch == null ? null : const NeverScrollableScrollPhysics();
    return Column(
      children: [
        // The last events loaded, or kept from last time, are still
        // shown, under this.
        if (_error != null && events != null && events.isNotEmpty)
          LoadError(
            what: 'events',
            error: _error!,
            stale: true,
            onRetry: _refresh,
          ),
        if (events != null)
          DaySummary(
            events: events,
            day: _day,
            actions: _actionsById,
            collapsed: _summaryCollapsed,
            onCollapsed: _setSummaryCollapsed,
            durations: _summaryDurations,
            onDurations: _setSummaryDurations,
          ),
        if (_proposal case final proposal?)
          ProposalBar(
            proposal: proposal,
            busy: _proposalBusy,
            changes: _changedSince.length,
            onConfirm: _confirmProposal,
            onNote: _noteForClaude,
            onNotes: _showProposalNotes,
            onRetry: _finishProposal,
            onGoTo: _goToProposal,
            onAbandon: _abandonProposal,
          ),
        if (_proposal case final proposal?) _buildDetails(proposal),
        Expanded(
          child: LayoutBuilder(
            builder: (context, view) => RefreshIndicator(
              onRefresh: () {
                unawaited(_loadNotes());
                unawaited(_loadProposal());
                return _refresh();
              },
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
                                physics: _box != null
                                    ? const NeverScrollableScrollPhysics()
                                    : noDrag,
                                onPageChanged: (page) => _show(_dayAt(page)),
                                itemBuilder: (context, page) => _buildDay(
                                  context,
                                  _dayAt(page),
                                  view.maxHeight,
                                ),
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
                                  anchor:
                                      proposal.claudeThrough ??
                                      proposal.through,
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
                                  onDone: to.isAfter(proposal.through)
                                      ? _extend
                                      : null,
                                  onCancel: () =>
                                      setState(() => _extendTo = null),
                                ),
                              ),
                            if (_box case final box?)
                              Positioned.fill(
                                child: PendingEventBoxView(
                                  day: _from,
                                  dayEnd: _to,
                                  scale: _scale,
                                  box: box,
                                  mode: _endMode,
                                  selected: _selected,
                                  onSelect: (role) =>
                                      setState(() => _selected = role),
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
                                    (box) => box.withCursor(
                                      _snap(to, CursorRole.anchor),
                                    ),
                                    fromOther: true,
                                  ),
                                  onMoveOther: (to) => _changeBox(
                                    (box) => box.withOther(
                                      _snap(to, CursorRole.end),
                                    ),
                                  ),
                                  onMoveBox: (to) => _changeBox(
                                    (box) => box.movedTo(
                                      _snap(to, CursorRole.anchor),
                                    ),
                                    moved: true,
                                  ),
                                  onStep: _stepCursor,
                                  canStep: _canStep,
                                  onTapBox: _openBox,
                                  onEditTime: _editTime,
                                  marks: _marksAt,
                                  cuts: _cutsAt,
                                ),
                              ),
                            if ((_box, _keptMove) case (_?, final move?))
                              Positioned.fill(
                                child: KeptMoveArrow(
                                  key: ValueKey(move.id),
                                  from: move.from,
                                  to: move.to,
                                  day: _from,
                                  dayEnd: _to,
                                  scale: _scale,
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
          ),
        ),
      ],
    );
  }

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
        LoadError(what: 'events', error: _error!, onRetry: _refresh),
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
            height: timelineHeight(d, _scale),
            child: _stackedDay(
              d,
              // Drawn from its midnight to the next, but at the top of
              // them all, and past the foot -- an event drawn past
              // midnight.
              clipTop: d == days.first ? 0 : pad,
              clipBottom: d == days.last ? -_pastFoot : pad,
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
    final proposal = _proposal;
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
                onTap: _box == null ? _openEvent : null,
                // Pressed and held, it's moved: the box around it.
                onLongPress: _box == null ? _startMoving : null,
                faded: _moving?.id,
                highlighted: _highlighted,
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
                // box stays put.
                onTapTime: _box?.span != null || _box == null
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
            // shown.
            Positioned.fill(
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

/// Where whether a proposal's details are folded away is kept.
const _detailsCollapsedKey = 'proposal_details_collapsed';

/// Where whether the day's summary is folded away is kept.
const _summaryCollapsedKey = 'day_summary_collapsed';

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
