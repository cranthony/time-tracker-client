import 'package:flutter/material.dart';

import '../models/event.dart';
import '../services/events_repository.dart';
import '../services/mcp_client.dart';
import '../widgets/app_menu.dart';
import '../widgets/day_header.dart';
import '../widgets/event_dialog.dart';
import '../widgets/status_message.dart';

/// One day's events, with buttons to step to the day before or after.
/// Tapping the date picks another; tapping an event shows all its
/// properties.
class EventsScreen extends StatefulWidget {
  const EventsScreen({
    super.key,
    required this.repository,
    required this.serverLabel,
    this.onSignIn,
    this.onSignOut,
    this.version,
    DateTime Function()? clock,
  }) : clock = clock ?? DateTime.now;

  final EventsRepository repository;

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
  List<Event>? _events;
  Object? _error;
  bool _needsSignIn = false;
  bool _signingIn = false;

  @override
  void initState() {
    super.initState();
    _day = _midnight(widget.clock());
    _load();
  }

  static DateTime _midnight(DateTime t) {
    final local = t.toLocal();
    return DateTime(local.year, local.month, local.day);
  }

  Future<void> _load() async {
    final day = _day;
    try {
      final events = await widget.repository.events(
        day,
        DateTime(day.year, day.month, day.day + 1),
      );
      // Another day was picked while this one loaded.
      if (!mounted || day != _day) return;
      setState(() {
        _events = events;
        _error = null;
        _needsSignIn = false;
      });
    } on SignInRequiredException {
      if (!mounted || day != _day) return;
      setState(() {
        _events = null;
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
      _error = null;
    });
    _load();
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
      body: RefreshIndicator(onRefresh: _load, child: _buildBody(context)),
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
    if (_error != null) {
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
    return ListView.separated(
      physics: const AlwaysScrollableScrollPhysics(),
      itemCount: events.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, i) => _EventTile(event: events[i], day: _day),
    );
  }
}

class _EventTile extends StatelessWidget {
  const _EventTile({required this.event, required this.day});

  final Event event;

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
      onTap: () => showEventDialog(context, event),
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
