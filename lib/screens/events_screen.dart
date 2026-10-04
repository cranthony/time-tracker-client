import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/event.dart';
import '../models/goal.dart';
import '../models/recurrence.dart';
import '../services/goals_repository.dart';
import '../services/events_repository.dart';
import '../services/mcp_client.dart';
import '../widgets/app_menu.dart';
import '../widgets/day_header.dart';
import '../widgets/day_timeline.dart';
import '../widgets/event_dialog.dart';
import '../widgets/event_summary_dialog.dart';
import '../widgets/recurrence_dialog.dart';
import '../widgets/refreshing_bar.dart';
import '../widgets/status_message.dart';

/// One day's events on a timeline ([DayTimeline]), from midnight to
/// midnight, with buttons to step to the day before or after and to zoom
/// in or out. Swiping left or right slides to the day after or before,
/// which are loaded in the background to be ready, and pinching zooms
/// around the fingers. The days slide over a [TimelineAxis] that stays
/// still, scrolled up and down with them, so every day is at the same
/// time of day. Tapping the date picks another; tapping an event
/// shows all its properties, and lets one change them; tapping between
/// events creates one there. It opens scrolled
/// to now, on today, or else to the day's first event. The last
/// compaction, from the goals, is marked on it.
///
/// The day it opens on, today, is kept for next time, so it shows at once
/// while it refreshes. Other days load afresh, and are loaded again when
/// shown after an event was changed.
class EventsScreen extends StatefulWidget {
  const EventsScreen({
    super.key,
    required this.repository,
    required this.serverLabel,
    this.goalsRepository,
    this.onSignIn,
    this.onSignOut,
    this.version,
    DateTime Function()? clock,
  }) : clock = clock ?? DateTime.now;

  final EventsRepository repository;

  /// Where to list goals from, to pick an event's; null to type their ids.
  final GoalsRepository? goalsRepository;

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

  /// The day shown first; its events are kept for next time.
  late final DateTime _firstDay;

  final _pages = PageController(initialPage: _firstPage);

  /// The page the arrows last sent it sliding to, until it gets there, so
  /// a second tap goes on from there.
  int? _slidingTo;

  /// The events of the day shown and the days around it, as far as
  /// they're loaded. The days either side are loaded in the background,
  /// to be ready to slide in.
  final _events = <DateTime, List<Event>>{};

  /// The days in [_events] the server has answered for since anything
  /// was last changed. The rest are kept from last time, or may be out of
  /// date, and are loaded again when shown.
  final _fresh = <DateTime>{};

  /// Why the day shown couldn't be loaded, if it couldn't.
  Object? _error;
  bool _needsSignIn = false;
  bool _signingIn = false;

  /// The goals by id, for the colors and names of events' goals; empty
  /// until they're loaded, or without goals.
  Map<String, Goal> _goalsById = const {};

  /// When notes were last compacted, as the goals say; null until
  /// they're loaded.
  DateTime? _lastCompaction;

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

  /// How tall the timeline is, with the days on it: clear of the zoom
  /// buttons at the foot, with room for an event drawn past midnight.
  double get _height => timelineHeight(_day, _scale) + 120;

  /// The day shown's events, if they're loaded.
  List<Event>? get _shown => _events[_day];

  /// Whether the day shown is kept from last time, or may be out of date,
  /// and is being loaded again.
  bool get _stale => _events.containsKey(_day) && !_fresh.contains(_day);

  @override
  void initState() {
    super.initState();
    _day = _firstDay = _midnight(widget.clock());
    _showCached();
    _refresh();
    _loadGoals();
  }

  @override
  void dispose() {
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

  /// Loads the goals, for their colors, and when notes were last
  /// compacted: those kept from last time, then the server's. Best
  /// effort: without them, goals are named as the events have them, with
  /// outlined diamonds, and the last compaction isn't marked.
  Future<void> _loadGoals() async {
    final repository = widget.goalsRepository;
    if (repository == null) return;
    void show(GoalList goals) {
      if (!mounted) return;
      setState(() {
        _goalsById = {for (final goal in goals.goals) ?goal.id: goal};
        _lastCompaction = goals.asOf;
      });
    }

    try {
      if (await repository.cachedGoals() case final cached?) show(cached);
      show(await repository.goals());
    } catch (_) {
      // Shown as they were.
    }
  }

  DateTime get _dayEnd => _dayAfter(_day);

  /// Scrolls the timeline to now, on today, or else to the first event,
  /// once it's laid out.
  void _scrollToStart() {
    final events = _shown;
    if (!_scrollPending || events == null) return;
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
      final y =
          timelineOffset(at, day: _day, dayEnd: _dayEnd, scale: _scale) -
          (today ? 120 : 24);
      _scroll.jumpTo(y.clamp(0, _scroll.position.maxScrollExtent));
    });
  }

  /// The zoom level the zoom-in button goes to, or zoom-out with
  /// [direction] -1: the next of [timelineScales] past this one; null at
  /// the end.
  double? _nextScale(int direction) => direction > 0
      ? timelineScales.where((s) => s > _scale + 1e-6).firstOrNull
      : timelineScales.where((s) => s < _scale - 1e-6).lastOrNull;

  /// Zooms to [next], keeping the time [focus] down the screen (the
  /// middle, by default) where it is.
  void _zoomTo(double next, {double? focus}) {
    next = next.clamp(timelineScales.first, timelineScales.last);
    if (next == _scale) return;
    if (_scroll.hasClients) {
      final position = _scroll.position;
      final at = focus ?? position.viewportDimension / 2;
      final pad = timelineOffset(
        _day,
        day: _day,
        dayEnd: _dayEnd,
        scale: _scale,
      );
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

  /// Shows the first day's events kept from last time, unless the server
  /// answered first. Only [_firstDay]'s are kept.
  Future<void> _showCached() async {
    final day = _firstDay;
    final events = await widget.repository.cachedEvents(day, _dayAfter(day));
    if (!mounted || events == null || _events.containsKey(day)) return;
    if (_needsSignIn || (_error != null && day == _day)) return;
    setState(() => _events[day] = events);
  }

  /// Loads [day]'s events, the day shown's by default. Only the day
  /// shown's errors are shown; another day's is loaded again when it is.
  Future<void> _load([DateTime? day]) async {
    final which = day ?? _day;
    try {
      final events = await widget.repository.events(
        which,
        _dayAfter(which),
        keep: which == _firstDay,
      );
      if (!mounted) return;
      setState(() {
        _events[which] = events;
        _fresh.add(which);
        if (which == _day) {
          _error = null;
          _needsSignIn = false;
        }
      });
    } on SignInRequiredException {
      if (!mounted || which != _day) return;
      setState(() {
        _events.remove(which);
        _fresh.remove(which);
        _needsSignIn = true;
      });
    } catch (e) {
      if (!mounted || which != _day) return;
      setState(() => _error = e);
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
      _day = day;
      _error = null;
      _events.removeWhere((d, _) => (_pageOf(d) - _pageOf(day)).abs() > 3);
      _fresh.retainWhere(_events.containsKey);
    });
    _refresh(reloadShown: !_fresh.contains(day));
  }

  /// Opens [event]'s summary, and from it, its details.
  Future<void> _openEvent(Event event) async {
    final outcome = await showEventSummaryDialog(
      context,
      event,
      save: (changes) => widget.repository.updateEvent(event, changes),
      goals: _goalsById,
      loadGoals: _goals,
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

  /// The new event's length, unless the next event starts sooner.
  static const _newEventLength = Duration(hours: 1);

  /// Opens a new, blank event at [time], tapped on [day]'s timeline: from
  /// the quarter hour it's in, for [_newEventLength] or up to the next
  /// event, whichever is sooner.
  Future<void> _createAt(DateTime day, DateTime time) async {
    final start = DateTime(
      time.year,
      time.month,
      time.day,
      time.hour,
      time.minute - time.minute % 15,
    );
    var end = start.add(_newEventLength);
    for (final event in _events[day] ?? const <Event>[]) {
      if (event.start.isAfter(start) && event.start.isBefore(end)) {
        end = event.start;
      }
    }
    final created = await showNewEventDialog(
      context,
      start: start,
      end: end,
      create: widget.repository.createEvent,
      goals: _goalsById,
      loadGoals: _goals,
    );
    if (created == null || !mounted) return;
    final moved = created.length - 1;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          moved <= 0
              ? 'Event created.'
              : 'Event created. $moved other event${moved == 1 ? '' : 's'} '
                    'moved to make room.',
        ),
      ),
    );
    _fresh.clear();
    await _refresh();
    await _loadGoals();
  }

  /// Opens every one of [event]'s properties.
  Future<void> _openEventDetails(Event event) async {
    final updated = await showEventDialog(
      context,
      event,
      save: widget.repository.updateEvent,
      goals: _goals,
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
    // It may have moved others, on other days too.
    _fresh.clear();
    await _refresh();
    // Its goals may have changed, and with them its diamonds.
    await _loadGoals();
  }

  /// Every goal, for picking an event's goals; null without goals.
  Future<List<Goal>> Function()? get _goals => switch (widget.goalsRepository) {
    final goals? => () async => (await goals.goals()).goals,
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
      goals: _goalsById,
      loadGoals: _goals,
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
      goals: _goals,
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
      await _refresh();
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Sign-in failed: $e')));
    } finally {
      if (mounted) setState(() => _signingIn = false);
    }
  }

  Future<void> _signOut() async {
    await widget.onSignOut!();
    setState(() {
      _events.clear();
      _fresh.clear();
    });
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
          : Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                FloatingActionButton.small(
                  heroTag: 'zoom-in',
                  tooltip: 'Zoom in',
                  onPressed: switch (_nextScale(1)) {
                    final next? => () => _zoomTo(next),
                    null => null,
                  },
                  child: const Icon(Icons.zoom_in),
                ),
                const SizedBox(height: 8),
                FloatingActionButton.small(
                  heroTag: 'zoom-out',
                  tooltip: 'Zoom out',
                  onPressed: switch (_nextScale(-1)) {
                    final next? => () => _zoomTo(next),
                    null => null,
                  },
                  child: const Icon(Icons.zoom_out),
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
    if (events != null) _scrollToStart();
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
        Expanded(
          child: LayoutBuilder(
            builder: (context, view) => RefreshIndicator(
              onRefresh: _refresh,
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
                              child: TimelineAxis(day: _day, scale: _scale),
                            ),
                            Positioned.fill(
                              child: PageView.builder(
                                controller: _pages,
                                physics: noDrag,
                                onPageChanged: (page) => _show(_dayAt(page)),
                                itemBuilder: (context, page) => _buildDay(
                                  context,
                                  _dayAt(page),
                                  view.maxHeight,
                                ),
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

  /// [day]'s page: its events, over the [TimelineAxis], or why they
  /// can't be shown, in the middle of the [view] tall part of it on
  /// screen.
  Widget _buildDay(BuildContext context, DateTime day, double view) {
    final events = _events[day];
    if (day == _day && _error != null && (events == null || events.isEmpty)) {
      return _inView(
        view,
        StatusMessage(
          icon: Icons.cloud_off,
          text: 'Could not load events.\n$_error',
        ),
      );
    } else if (events == null) {
      return _inView(
        view,
        const Padding(
          padding: EdgeInsets.all(16),
          child: CircularProgressIndicator(),
        ),
      );
    }
    // Drawn past the page's foot, if an event's drawn past midnight.
    final timeline = OverflowBox(
      alignment: Alignment.topCenter,
      minHeight: 0,
      maxHeight: double.infinity,
      child: DayTimeline(
        events: events,
        day: day,
        goals: _goalsById,
        scale: _scale,
        now: widget.clock(),
        lastCompaction: _lastCompaction,
        onTap: _openEvent,
        onTapTime: (time) => _createAt(day, time),
        axis: false,
      ),
    );
    if (events.isNotEmpty) return timeline;
    // Still tapped through, to add one anywhere.
    return Stack(
      children: [
        Positioned.fill(child: timeline),
        IgnorePointer(
          child: _inView(
            view,
            const StatusMessage(
              icon: Icons.event_busy,
              text: 'No events.\nTap a time to add one.',
            ),
          ),
        ),
      ],
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
