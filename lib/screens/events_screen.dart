import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/event.dart';
import '../models/plan_action.dart';
import '../models/note.dart';
import '../models/recurrence.dart';
import '../outbox/note_outbox.dart';
import '../outbox/save_error.dart';
import '../services/actions_repository.dart';
import '../services/event_store.dart';
import '../services/events_repository.dart';
import '../services/mcp_client.dart';
import '../services/events_place.dart';
import '../services/notes_repository.dart';
import '../services/people_repository.dart';
import '../services/plan_memory.dart';
import '../services/traits_repository.dart';
import '../widgets/app_menu.dart';
import '../widgets/day_header.dart';
import '../widgets/day_summary.dart';
import '../widgets/pending_event_box.dart';
import '../widgets/day_timeline.dart';
import '../widgets/event_dialog.dart';
import '../widgets/other_events.dart';
import '../widgets/event_summary_dialog.dart';
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
class EventsScreen extends StatefulWidget {
  const EventsScreen({
    super.key,
    required this.repository,
    required this.serverLabel,
    this.actionsRepository,
    this.notesRepository,
    this.outbox,
    this.onSignIn,
    this.onSignOut,
    this.version,
    this.placeStore,
    this.memory,
    DateTime Function()? clock,
  }) : clock = clock ?? DateTime.now;

  final EventsRepository repository;

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

  /// How many times the box's cursors have been switched: each time,
  /// the cursor pings where it's gone.
  int _swaps = 0;

  /// What [_createMode] was before a move, to go back to after it: a move
  /// starts out pushing.
  CreateMode? _modeBeforeMove;

  /// Where keeping events last moved the box, from where it was put, to
  /// show with a [KeptMoveArrow]; [id] tells each move from the last.
  ({DateTime from, DateTime to, int id})? _keptMove;

  /// Whether a new event keeps clear of the events already there, or
  /// overwrites them.
  CreateMode _createMode = CreateMode.keep;

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

  /// The day shown's events, if they're loaded.
  List<Event>? get _shown => _store.day(_day);

  /// Whether the day shown is kept from last time, or may be out of date,
  /// and is being loaded again.
  bool get _stale => _store.has(_day) && !_fresh.contains(_day);

  /// Shows what the app loads -- a day, as it opens, say -- as soon as
  /// it has it.
  void _memoryChanged() {
    if (mounted) setState(() {});
  }

  /// Loads everyone, every location and every trait, for an event's
  /// dialogs to name at once. Best effort.
  Future<void> _prefetchNames() async {
    if (!mounted) return;
    final memory = _memory;
    // Asked afresh each time the page opens.
    memory.newVisit();
    await memory.prefetchNames(
      traits: TraitsScope.of(context),
      people: PeopleScope.of(context),
    );
  }

  @override
  void initState() {
    super.initState();
    _memory = widget.memory ?? PlanMemoryScope.of(context) ?? PlanMemory();
    _memory
      ..useEvents(EventStore(repository: widget.repository))
      ..addListener(_memoryChanged);
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
    _loadNotes(cached: true);
    _loadSummaryCollapsed();
    // Once the scopes can be read: everyone, every location and every
    // trait, for an event's dialogs.
    WidgetsBinding.instance.addPostFrameCallback((_) => _prefetchNames());
    _loadSummaryDurations();
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

  /// Goes back to where it was left, when the app was last open, if
  /// that's to be kept.
  Future<void> _loadPlace(EventsPlaceStore store) async {
    final place = await store.load();
    if (!mounted) return;
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
    final outcome = await showEventSummaryDialog(
      context,
      event,
      save: (changes) => _approvingHistory(
        (allow) => widget.repository.updateEvent(
          event,
          changes,
          allowCompactedChanges: allow,
        ),
      ),
      cancel: (counts) => _approvingHistory(
        (allow) => widget.repository.deleteEvent(
          event,
          countsAgainstFollowThrough: counts,
          allowCompactedChanges: allow,
        ),
      ),
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

  /// Every event loaded, but [event], for keeping its times clear of.
  OtherEvents _otherEvents(Event? event) => OtherEvents(
    {
      for (final e in _store.between(
        DateTime(_day.year, _day.month, _day.day - 3),
        DateTime(_day.year, _day.month, _day.day + 4),
      ))
        e.id ?? e: e,
    }.values,
    except: event?.id,
  );

  /// [time] at the nearest quarter hour.
  static DateTime _nearestQuarter(DateTime time) {
    final minutes = time.hour * 60 + time.minute + (time.second >= 30 ? 1 : 0);
    final quarters = (minutes / 15).round();
    return DateTime(time.year, time.month, time.day, 0, quarters * 15);
  }

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
    setState(() {
      _setBox(PendingEventBox(_nearestQuarter(at)));
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
      _modeBeforeMove = _createMode;
      _createMode = CreateMode.push;
    });
  }

  /// Switches the box's cursors: the box going the other way from the
  /// other one -- kept in free time, or pushing, as before -- and an
  /// arrow to where the cursor's gone. Not if there's no room that way:
  /// the box would be gone.
  void _swapCursors() {
    final box = _box;
    final other = box?.other;
    if (box == null || other == null) return;
    final switched = PendingEventBox(other, other: box.cursor);
    if (_kept(switched).span == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            "No room to switch: there's no free time "
            '${switched.other!.isAfter(switched.cursor) ? 'later' : 'earlier'} '
            'in the day to push into.',
          ),
        ),
      );
      return;
    }
    setState(() {
      _keep(switched);
      _keptMove = (
        from: box.cursor,
        to: _box!.cursor,
        id: (_keptMove?.id ?? 0) + 1,
      );
      _swaps++;
    });
  }

  /// Puts the box away -- the new event or the move done, or dropped.
  void _endBox() => setState(() {
    _setBox(null);
    _moving = null;
    if (_modeBeforeMove case final mode?) _createMode = mode;
    _modeBeforeMove = null;
  });

  /// Saves the move of [_moving] to the box, and what it does to the
  /// events in its way, in one batch.
  Future<void> _finishMoving() async {
    final event = _moving;
    final span = _box?.span;
    if (event == null || span == null) return;
    final (start, end) = span;
    if (start == event.start && end == event.end) return _endBox();
    final inTheWay = _createMode.overwrites
        ? _overwrite(_otherEvents(event), start, end)
        : const Overwrite();
    final messenger = ScaffoldMessenger.of(context);
    final List<Event> changed;
    try {
      changed = await _approvingHistory(
        (allow) => widget.repository.makeRoom(
          Overwrite(
            updates: [
              (
                event,
                {
                  'start': localIsoTimestamp(start),
                  'end': localIsoTimestamp(end),
                },
              ),
              ...inTheWay.updates,
            ],
            cancels: inTheWay.cancels,
            creates: inTheWay.creates,
          ),
          allowCompactedChanges: allow,
        ),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text("Couldn't move it: ${describeSaveError(e)}")),
      );
      return;
    }
    if (!mounted) return;
    _endBox();
    final others = inTheWay.count;
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
    await _refresh();
  }

  /// [box], keeping events, fitted into free time (see [OtherEvents]):
  /// [moved] whole, as near as it fits; or from its [PendingEventBox.cursor] --
  /// or, [fromOther], its other cursor -- out of any event it's in, and to
  /// no further than the next event. Pushing, see [_pushKept].
  /// Overwriting, as it is.
  PendingEventBox _kept(
    PendingEventBox box, {
    bool moved = false,
    bool fromOther = false,
  }) {
    if (_createMode.pushes) return _pushKept(box, moved: moved);
    final other = box.other;
    if (_createMode.overwrites || other == null) return box;
    final others = _otherEvents(_moving);
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
      final (fitted, cursor) = others.fitFrom(other, box.cursor);
      return PendingEventBox(cursor, other: fitted);
    }
    final (cursor, fitted) = others.fitFrom(box.cursor, other);
    return PendingEventBox(cursor, other: fitted);
  }

  /// [box], pushing events: its cursor -- for [CreateMode.push] -- out
  /// of any event it's inside of, to its nearer edge ([moved] whole, the
  /// other cursor with it); and its other cursor no further from it than
  /// leaves the day room for the events it pushes.
  PendingEventBox _pushKept(PendingEventBox box, {bool moved = false}) {
    final others = _otherEvents(_moving);
    var (cursor, other) = (box.cursor, box.other);
    if (_createMode == CreateMode.push) {
      final snapped = others.between(cursor);
      if (moved) other = other?.add(snapped.difference(cursor));
      cursor = snapped;
    }
    if (other != null && other != cursor) {
      other = others.pushFit(
        cursor,
        other,
        from: _from,
        to: _to,
        inside: _createMode.inside,
      );
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

  /// Whether the new event takes time from events already there:
  /// pushing, only if it cuts one short.
  bool get _overwrites => switch (_box?.span) {
    (final start, final end) when _createMode.pushes =>
      _createMode == CreateMode.trimPush &&
          _otherEvents(_moving).events.any((e) {
            final anchor = _later ? start : end;
            return e.start.isBefore(anchor) && e.end.isAfter(anchor);
          }),
    (final start, final end) =>
      _createMode.overwrites &&
          _otherEvents(_moving).overlapping(start, end) != null,
    null => false,
  };

  /// Where the events the new one pushes go, pushing.
  List<PushedEvent> get _pushed => switch (_box?.span) {
    (final start, final end) when _createMode.pushes => [
      for (final (event, changes) in _overwrite(
        _otherEvents(_moving),
        start,
        end,
      ).updates)
        if (changes case {'start': final String from, 'end': final String to})
          (
            start: DateTime.parse(from).toLocal(),
            end: DateTime.parse(to).toLocal(),
            label: event.summary ?? 'Event',
          ),
      for (final rest in _overwrite(_otherEvents(_moving), start, end).creates)
        (
          start: DateTime.parse(rest['start'] as String).toLocal(),
          end: DateTime.parse(rest['end'] as String).toLocal(),
          label: '${rest['summary'] ?? 'Event'} (the rest)',
        ),
    ],
    _ => const [],
  };

  /// What the shadow covers, cancelling: the box, and every event it
  /// touches, whole. Null otherwise: just the box.
  (DateTime, DateTime)? get _covers => switch (_box?.span) {
    (final start, final end) when _createMode == CreateMode.cancel =>
      _otherEvents(_moving).touching(start, end),
    _ => null,
  };

  /// What an event from [start] to [end] does to the [others] in its way,
  /// overwriting them: trims, or cancels, them; or pushes them, [later]
  /// (the way the box goes, unless said).
  Overwrite _overwrite(
    OtherEvents others,
    DateTime start,
    DateTime end, {
    bool? later,
  }) => switch (_createMode) {
    CreateMode.cancel => others.cancelling(start, end),
    final mode when mode.pushes => others.pushing(
      start,
      end,
      later: later ?? _later,
      inside: mode.inside,
    ),
    _ => others.overwrite(start, end),
  };

  /// A button on the cursor, its [step] later or earlier, dragged to
  /// [to]: the other cursor there, at least a quarter hour from the
  /// cursor on [step]'s side.
  void _dragStep(Duration step, DateTime to) => _changeBox((box) {
    final cursor = box.cursor;
    final quarter = _nearestQuarter(to);
    if (step.isNegative) {
      final latest = cursor.subtract(OtherEvents.shortest);
      return box.withOther(quarter.isAfter(latest) ? latest : quarter);
    }
    final earliest = cursor.add(OtherEvents.shortest);
    return box.withOther(quarter.isBefore(earliest) ? earliest : quarter);
  });

  /// Opens the new event, as shaded between the cursors.
  Future<void> _continueCreating() async {
    final span = _box?.span;
    if (span == null) return;
    final (start, end) = span;
    final others = _otherEvents(_moving);
    final overwrite = _createMode.overwrites;
    final later = _later;
    final inTheWay = _overwrite(others, start, end);
    var cleared = false;
    final created = await showNewEventDialog(
      context,
      start: start,
      end: end,
      // Overwriting, its times needn't keep clear of anything.
      otherEvents: overwrite ? const OtherEvents.none() : others,
      create: overwrite
          ? (fields) => _approvingHistory(
              (allow) => widget.repository.createOver(
                fields,
                _overwrite(
                  others,
                  DateTime.parse(fields['start'] as String),
                  DateTime.parse(fields['end'] as String),
                  later: later,
                ),
                allowCompactedChanges: allow,
              ),
            )
          : widget.repository.createEvent,
      // Overwriting events, the trash makes no new event, but just
      // clears the time of them.
      clear: !overwrite || inTheWay.isEmpty
          ? null
          : (
              question: switch (_createMode) {
                CreateMode.cancel => 'Cancel ${_events(inTheWay.count)}?',
                final mode when mode.pushes =>
                  'Make room, changing ${_events(inTheWay.count)}?',
                _ => 'Clear this time of ${_events(inTheWay.count)}?',
              },
              explanation: switch (_createMode) {
                CreateMode.cancel =>
                  'Every event the new one touches is cancelled, as a '
                      'change of plan, and no new event is made.',
                final mode when mode.pushes =>
                  'The events in the way are pushed along, as the new one '
                      'would push them, and no new event is made.',
                _ =>
                  'The events under the new one are trimmed out of this '
                      'time, and no new event is made.',
              },
              label: switch (_createMode) {
                CreateMode.cancel => 'Cancel them',
                final mode when mode.pushes => 'Make room',
                _ => 'Clear the time',
              },
              run: () {
                cleared = true;
                return _approvingHistory(
                  (allow) => widget.repository.makeRoom(
                    inTheWay,
                    allowCompactedChanges: allow,
                  ),
                );
              },
            ),
      actions: _actionsById,
      loadActions: _actions,
    );
    if (created == null || !mounted) return;
    _endBox();
    final changed = created.length - 1;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          cleared
              ? 'Time cleared: ${_events(created.length)} changed.'
              : changed <= 0
              ? 'Event created.'
              : 'Event created. $changed other '
                    'event${changed == 1 ? '' : 's'} changed to make room.',
        ),
      ),
    );
    _store.putEvents(created);
    _fresh.clear();
    await _refresh();
    await _loadActions();
  }

  /// "3 events", or "1 event".
  static String _events(int count) => '$count event${count == 1 ? '' : 's'}';

  Future<void> _pickCreateMode() async {
    final mode = await showCreateModeDialog(context, _createMode);
    if (mode == null || !mounted) return;
    setState(() => _createMode = mode);
    // Keeping events now: out of their way.
    _changeBox((box) => box);
  }

  /// Runs [change] -- and if the server refuses it because it changes
  /// history (an event compaction settled), asks the user, and runs it
  /// again allowing that if they agree. Otherwise rethrows the refusal.
  Future<List<Event>> _approvingHistory(
    Future<List<Event>> Function(bool allowCompactedChanges) change,
  ) async {
    try {
      return await change(false);
    } catch (e) {
      if (!isHistoryRefusal(e) || !mounted) rethrow;
      final approved = await showDialog<bool>(
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
      if (approved != true) rethrow;
      return change(true);
    }
  }

  /// Opens every one of [event]'s properties.
  Future<void> _openEventDetails(Event event) async {
    final updated = await showEventDialog(
      context,
      event,
      save: (event, changes) => _approvingHistory(
        (allow) => widget.repository.updateEvent(
          event,
          changes,
          allowCompactedChanges: allow,
        ),
      ),
      cancel: (event, counts) => _approvingHistory(
        (allow) => widget.repository.deleteEvent(
          event,
          countsAgainstFollowThrough: counts,
          allowCompactedChanges: allow,
        ),
      ),
      otherEvents: _otherEvents(event),
      actions: _actions,
      openSeries: (seriesId) => _openSeries(seriesId, event),
    );
    if (updated != null) await _saved(event, updated);
  }

  /// Says what saving [event] did, [updated] being what the server
  /// changed, and loads the days again.
  Future<void> _saved(Event event, List<Event> updated) async {
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
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            "Couldn't load the series. ${switch (e) {
              SignInRequiredException() => 'Sign in again, then try again.',
              McpException(:final message) => message,
              _ => '$e',
            }}",
          ),
        ),
      );
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
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _signingIn = true);
    try {
      await widget.onSignIn!();
      unawaited(_loadNotes());
      await _refresh();
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Sign-in failed: $e')));
    } finally {
      if (mounted) setState(() => _signingIn = false);
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
          StatusMessage(
            icon: Icons.cloud_off,
            text: 'Could not load events. These may be out of date.\n$_error',
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
        Expanded(
          child: LayoutBuilder(
            builder: (context, view) => RefreshIndicator(
              onRefresh: () {
                unawaited(_loadNotes());
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
                            if (_box case final box?)
                              Positioned.fill(
                                child: PendingEventBoxView(
                                  day: _from,
                                  dayEnd: _to,
                                  scale: _scale,
                                  box: box,
                                  mode: _createMode,
                                  overwrites: _overwrites,
                                  covers: _covers,
                                  pushed: _pushed,
                                  onSwap: box.other == null
                                      ? null
                                      : _swapCursors,
                                  swaps: _swaps,
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
                                        box.withCursor(_nearestQuarter(to)),
                                    fromOther: true,
                                  ),
                                  onMoveOther: (to) => _changeBox(
                                    (box) => box.withOther(_nearestQuarter(to)),
                                  ),
                                  onMoveBox: (to) => _changeBox(
                                    (box) => box.movedTo(_nearestQuarter(to)),
                                    moved: true,
                                  ),
                                  // A step further each tap, from the
                                  // cursor to start with.
                                  onTap: (step) => _changeBox(
                                    (box) => box.withOther(
                                      (box.other ?? box.cursor).add(step),
                                    ),
                                  ),
                                  onDrag: _dragStep,
                                  onPickMode: _pickCreateMode,
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
    final events = _store.day(day);
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
        StatusMessage(
          icon: Icons.cloud_off,
          text: 'Could not load events.\n$_error',
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
    final events = _store.day(day);
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
                pendingNotes: _pendingNotes,
                // While the cursor's up, events don't open: a tap on one
                // goes to the timeline under it, and moves the cursor
                // there.
                onTap: _box == null ? _openEvent : null,
                // Pressed and held, it's moved: the box around it.
                onLongPress: _box == null ? _startMoving : null,
                faded: _moving?.id,
                // The box moved there, its size intact.
                onTapTime: _box == null
                    ? null
                    : (time) => _changeBox(
                        (box) => box.movedTo(_nearestQuarter(time)),
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
