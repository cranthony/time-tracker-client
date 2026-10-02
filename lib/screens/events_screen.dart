import 'package:flutter/material.dart';

import '../models/event.dart';
import '../services/goals_repository.dart';
import '../services/events_repository.dart';
import '../services/mcp_client.dart';
import '../widgets/app_menu.dart';
import '../widgets/day_header.dart';
import '../widgets/event_dialog.dart';
import '../widgets/refreshing_bar.dart';
import '../widgets/status_message.dart';

/// One day's events, with buttons to step to the day before or after.
/// Tapping the date picks another; tapping an event shows all its
/// properties, and lets one change them.
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

  @override
  void initState() {
    super.initState();
    _day = _firstDay = _midnight(widget.clock());
    _showCached();
    _load();
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
      goals: switch (widget.goalsRepository) {
        final goals? => () async => (await goals.goals()).goals,
        null => null,
      },
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
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        // The last events loaded, or kept from last time, are still shown.
        if (_error != null)
          StatusMessage(
            icon: Icons.cloud_off,
            text: 'Could not load events. These may be out of date.\n$_error',
          ),
        for (final (i, event) in events.indexed) ...[
          if (i > 0) const Divider(height: 1),
          _EventTile(event: event, day: _day, onTap: () => _openEvent(event)),
        ],
      ],
    );
  }
}

class _EventTile extends StatelessWidget {
  const _EventTile({
    required this.event,
    required this.day,
    required this.onTap,
  });

  final Event event;
  final VoidCallback onTap;

  /// The day being shown: a start or end on another day shows its date.
  final DateTime day;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cancelled = event.isCancelled;
    final muted = TextStyle(
      color: theme.hintColor,
      decoration: cancelled ? TextDecoration.lineThrough : null,
    );
    final summary = event.summary;
    return ListTile(
      title: Text(
        summary == null || summary.isEmpty ? '(no summary)' : summary,
        style: summary == null || summary.isEmpty || cancelled ? muted : null,
      ),
      subtitle: Text(
        '${_when(context, event.start)} – ${_when(context, event.end)}'
        '${cancelled ? ' · cancelled' : ''}',
      ),
      onTap: onTap,
    );
  }

  String _when(BuildContext context, DateTime t) {
    final local = t.toLocal();
    final strings = MaterialLocalizations.of(context);
    final time = strings.formatTimeOfDay(TimeOfDay.fromDateTime(local));
    return sameDay(local, day)
        ? time
        : '${strings.formatShortMonthDay(local)}, $time';
  }
}
