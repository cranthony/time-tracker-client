import 'package:flutter/material.dart';

import '../models/event_label.dart';
import '../services/event_labels_repository.dart';
import '../services/mcp_client.dart';
import '../widgets/app_menu.dart';
import '../widgets/color_picker.dart';
import '../widgets/event_label_dialog.dart';
import '../widgets/refreshing_bar.dart';
import '../widgets/status_message.dart';

/// Every named event label: its color, name, priority and whether it's
/// fixed time. Tapping a label shows all its properties, and lets one change
/// its name, color and priority.
///
/// Labels with no name are hidden: they represent Google Calendar's
/// default event colors, and aren't meant to be edited.
class EventLabelsScreen extends StatefulWidget {
  const EventLabelsScreen({
    super.key,
    required this.repository,
    required this.serverLabel,
    this.onSignIn,
    this.onSignOut,
    this.version,
  });

  final EventLabelsRepository repository;

  /// Which server this build talks to, for the About dialog.
  final String serverLabel;

  /// Runs the interactive sign-in; null when the backend needs none.
  final Future<void> Function()? onSignIn;
  final Future<void> Function()? onSignOut;

  /// The app's version, for the About dialog; null until it's known.
  final String? version;

  @override
  State<EventLabelsScreen> createState() => _EventLabelsScreenState();
}

class _EventLabelsScreenState extends State<EventLabelsScreen> {
  List<EventLabel>? _labels;

  /// [_labels] are the ones kept from last time; the server hasn't
  /// answered since.
  bool _stale = false;
  Object? _error;
  bool _needsSignIn = false;
  bool _signingIn = false;

  @override
  void initState() {
    super.initState();
    _showCached();
    _load();
  }

  /// Shows the labels kept from last time, unless the server answered
  /// first.
  Future<void> _showCached() async {
    final labels = await widget.repository.cachedLabels();
    if (!mounted || labels == null) return;
    if (_labels != null || _needsSignIn || _error != null) return;
    setState(() {
      _labels = _named(labels);
      _stale = true;
    });
  }

  Future<void> _load() async {
    try {
      final labels = await widget.repository.labels();
      if (!mounted) return;
      setState(() {
        _labels = _named(labels);
        _stale = false;
        _error = null;
        _needsSignIn = false;
      });
    } on SignInRequiredException {
      if (!mounted) return;
      setState(() {
        _labels = null;
        _stale = false;
        _needsSignIn = true;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e);
    }
  }

  /// [labels] without the unnamed ones. An unnamed label represents one of
  /// Google Calendar's default event colors, not a label anyone made, so
  /// it isn't listed or edited here.
  static List<EventLabel> _named(List<EventLabel> labels) => [
    for (final label in labels)
      if (label.name?.isNotEmpty ?? false) label,
  ];

  Future<void> _open(EventLabel label) async {
    final messenger = ScaffoldMessenger.of(context);
    final labels = await showEventLabelDialog(
      context,
      label,
      save: widget.repository.updateLabel,
    );
    if (labels == null || !mounted) return;
    setState(() {
      _labels = _named(labels);
      _stale = false;
      _error = null;
    });
    messenger.showSnackBar(const SnackBar(content: Text('Saved.')));
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
    return Scaffold(
      appBar: AppBar(
        title: const Text('Event labels'),
        actions: [
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
    final labels = _labels;
    if (_needsSignIn) {
      return FillViewport(
        child: StatusMessage(
          icon: Icons.lock_outline,
          text: 'Sign in to see your event labels.',
          action: widget.onSignIn == null
              ? null
              : FilledButton(
                  onPressed: _signingIn ? null : _signIn,
                  child: Text(_signingIn ? 'Waiting for browser…' : 'Sign in'),
                ),
        ),
      );
    }
    if (_error != null && (labels == null || labels.isEmpty)) {
      return FillViewport(
        child: StatusMessage(
          icon: Icons.cloud_off,
          text: 'Could not load event labels.\n$_error',
        ),
      );
    }
    if (labels == null) return const Center(child: CircularProgressIndicator());
    if (labels.isEmpty) {
      return const FillViewport(
        child: StatusMessage(icon: Icons.label_off, text: 'No event labels.'),
      );
    }
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        // The last labels loaded, or kept from last time, are still shown.
        if (_error != null)
          StatusMessage(
            icon: Icons.cloud_off,
            text:
                'Could not load event labels. These may be out of date.\n'
                '$_error',
          ),
        for (final (i, label) in labels.indexed) ...[
          if (i > 0) const Divider(height: 1),
          _LabelTile(label: label, onTap: () => _open(label)),
        ],
      ],
    );
  }
}

class _LabelTile extends StatelessWidget {
  const _LabelTile({required this.label, required this.onTap});

  final EventLabel label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final name = label.name;
    final color = parseColor(label.backgroundColor);
    final priority = label.priority;
    return ListTile(
      leading: Icon(
        color == null ? Icons.label_outline : Icons.label,
        color: color ?? theme.hintColor,
      ),
      title: Text(
        labelName(label),
        style: name == null || name.isEmpty
            ? TextStyle(color: theme.hintColor)
            : null,
      ),
      subtitle: Text(
        [
          priority == null ? 'No priority' : 'Priority $priority',
          switch (label.fixedTime) {
            true => 'Fixed time',
            false => 'Flexible time',
            null => null,
          },
        ].nonNulls.join(' · '),
      ),
      onTap: onTap,
    );
  }
}
