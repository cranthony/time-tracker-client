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
import '../widgets/recurrence_dialog.dart';
import '../widgets/refreshing_bar.dart';
import '../widgets/status_message.dart';

/// One day's events on a timeline ([DayTimeline]), from midnight to
/// midnight, with buttons to step to the day before or after and to zoom
/// in or out. Tapping the date picks another; tapping an event shows all
/// its properties, and lets one change them. It opens scrolled to now,
/// on today, or else to the day's first event.
///
/// The day it opens on, today, is kept for next time, so it shows at once
/// while it refreshes. Other days load afresh.
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
  /// Midnight, local time, at the start of the day shown.
  late DateTime _day;

  /// The day shown first; its events are kept for next time.
  late final DateTime _firstDay;
  List<Event>? _events;

  /// [_events] are the ones kept from last time; the server hasn't
  /// answered since.
  bool _stale = false;
  Object? _error;
  bool _needsSignIn = false;
  bool _signingIn = false;

  /// The goals by id, for the colors and names of events' goals; empty
  /// until they're loaded, or without goals.
  Map<String, Goal> _goalsById = const {};

  /// The timeline's zoom: logical pixels per minute.
  double _scale = defaultTimelineScale;

  final _scroll = ScrollController();

  /// Whether the timeline is still to be scrolled to the day's first
  /// event, or now: once its events are shown.
  bool _scrollPending = true;

  @override
  void initState() {
    super.initState();
    _day = _firstDay = _midnight(widget.clock());
    _showCached();
    _load();
    _loadGoals();
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  /// Loads the goals, for their colors. Best effort: without them, goals
  /// are named as the events have them, with outlined diamonds.
  Future<void> _loadGoals() async {
    final repository = widget.goalsRepository;
    if (repository == null) return;
    try {
      final goals =
          (await repository.cachedGoals()) ?? await repository.goals();
      if (!mounted) return;
      setState(
        () => _goalsById = {for (final goal in goals.goals) ?goal.id: goal},
      );
    } catch (_) {
      // Shown without their colors.
    }
  }

  DateTime get _dayEnd => _dayAfter(_day);

  /// Scrolls the timeline to now, on today, or else to the first event,
  /// once it's laid out.
  void _scrollToStart() {
    final events = _events;
    if (!_scrollPending || events == null || events.isEmpty) return;
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

  /// Zooms to the next of [timelineScales] in [direction], keeping the
  /// time at the middle of the screen there.
  void _zoom(int direction) {
    final i = timelineScales.indexOf(_scale) + direction;
    if (i < 0 || i >= timelineScales.length) return;
    final next = timelineScales[i];
    if (_scroll.hasClients) {
      final position = _scroll.position;
      final half = position.viewportDimension / 2;
      final target = (position.pixels + half) * next / _scale - half;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_scroll.hasClients) return;
        _scroll.jumpTo(target.clamp(0, _scroll.position.maxScrollExtent));
      });
    }
    setState(() => _scale = next);
  }

  static DateTime _midnight(DateTime t) {
    final local = t.toLocal();
    return DateTime(local.year, local.month, local.day);
  }

  static DateTime _dayAfter(DateTime day) =>
      DateTime(day.year, day.month, day.day + 1);

  /// Shows the day's events kept from last time, unless the server
  /// answered first. Only [_firstDay]'s are kept.
  Future<void> _showCached() async {
    final day = _day;
    if (day != _firstDay) return;
    final events = await widget.repository.cachedEvents(day, _dayAfter(day));
    if (!mounted || day != _day || events == null) return;
    if (_events != null || _needsSignIn || _error != null) return;
    setState(() {
      _events = events;
      _stale = true;
    });
  }

  Future<void> _load() async {
    final day = _day;
    try {
      final events = await widget.repository.events(
        day,
        _dayAfter(day),
        keep: day == _firstDay,
      );
      // Another day was picked while this one loaded.
      if (!mounted || day != _day) return;
      setState(() {
        _events = events;
        _stale = false;
        _error = null;
        _needsSignIn = false;
      });
    } on SignInRequiredException {
      if (!mounted || day != _day) return;
      setState(() {
        _events = null;
        _stale = false;
        _needsSignIn = true;
      });
    } catch (e) {
      if (!mounted || day != _day) return;
      setState(() => _error = e);
    }
  }

  void _show(DateTime day) {
    if (day == _day) return;
    setState(() {
      _day = day;
      _events = null;
      _stale = false;
      _error = null;
      _scrollPending = true;
    });
    _showCached();
    _load();
  }

  Future<void> _openEvent(Event event) async {
    final messenger = ScaffoldMessenger.of(context);
    final updated = await showEventDialog(
      context,
      event,
      save: widget.repository.updateEvent,
      goals: _goals,
      openSeries: (seriesId) => _openSeries(seriesId, event),
    );
    if (updated == null) return;
    final moved = updated.where((e) => e.id != event.id).length;
    final cancelled = updated.any((e) => e.id == event.id && e.isCancelled);
    messenger.showSnackBar(
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
    await _load();
    // Its goals may have changed, and with them its diamonds.
    await _loadGoals();
  }

  /// Every goal, for picking an event's goals; null without goals.
  Future<List<Goal>> Function()? get _goals => switch (widget.goalsRepository) {
    final goals? => () async => (await goals.goals()).goals,
    null => null,
  };

  /// Opens the recurring series [seriesId], from its [event]. True if a
  /// change to it was saved, after which the day is loaded again.
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
    if (!mounted) return false;
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
    await _load();
    return true;
  }

  void _step(int days) =>
      _show(DateTime(_day.year, _day.month, _day.day + days));

  Future<void> _pickDay() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _day,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked != null) _show(_midnight(picked));
  }

  Future<void> _signIn() async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _signingIn = true);
    try {
      await widget.onSignIn!();
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
        child: RefreshIndicator(onRefresh: _load, child: _buildBody(context)),
      ),
      floatingActionButton: (_events?.isEmpty ?? true) || _needsSignIn
          ? null
          : Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                FloatingActionButton.small(
                  heroTag: 'zoom-in',
                  tooltip: 'Zoom in',
                  onPressed: _scale == timelineScales.last
                      ? null
                      : () => _zoom(1),
                  child: const Icon(Icons.zoom_in),
                ),
                const SizedBox(height: 8),
                FloatingActionButton.small(
                  heroTag: 'zoom-out',
                  tooltip: 'Zoom out',
                  onPressed: _scale == timelineScales.first
                      ? null
                      : () => _zoom(-1),
                  child: const Icon(Icons.zoom_out),
                ),
              ],
            ),
    );
  }

  Widget _buildBody(BuildContext context) {
    final events = _events;
    if (_needsSignIn) {
      return FillViewport(
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
    }
    if (_error != null && (events == null || events.isEmpty)) {
      return FillViewport(
        child: StatusMessage(
          icon: Icons.cloud_off,
          text: 'Could not load events.\n$_error',
        ),
      );
    }
    if (events == null) return const Center(child: CircularProgressIndicator());
    if (events.isEmpty) {
      return const FillViewport(
        child: StatusMessage(icon: Icons.event_busy, text: 'No events.'),
      );
    }
    _scrollToStart();
    return Column(
      children: [
        // The last events loaded, or kept from last time, are still shown,
        // under this.
        if (_error != null)
          StatusMessage(
            icon: Icons.cloud_off,
            text: 'Could not load events. These may be out of date.\n$_error',
          ),
        Expanded(
          child: ListView(
            controller: _scroll,
            physics: const AlwaysScrollableScrollPhysics(),
            // Clear of the zoom buttons.
            padding: const EdgeInsets.only(bottom: 120),
            children: [
              DayTimeline(
                events: events,
                day: _day,
                goals: _goalsById,
                scale: _scale,
                now: widget.clock(),
                onTap: _openEvent,
              ),
            ],
          ),
        ),
      ],
    );
  }
}
