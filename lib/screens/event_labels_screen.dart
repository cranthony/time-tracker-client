import 'package:flutter/material.dart';

import '../models/event_label.dart';
import '../services/event_labels_repository.dart';
import '../services/mcp_client.dart';
import '../widgets/app_menu.dart';
import '../widgets/event_label_dialog.dart';
import '../widgets/status_message.dart';

/// Every event label: its color, name, priority and whether it's fixed
/// time. Tapping a label shows all its properties.
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
  Object? _error;
  bool _needsSignIn = false;
  bool _signingIn = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final labels = await widget.repository.labels();
      if (!mounted) return;
      setState(() {
        _labels = labels;
        _error = null;
        _needsSignIn = false;
      });
    } on SignInRequiredException {
      if (!mounted) return;
      setState(() {
        _labels = null;
        _needsSignIn = true;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e);
    }
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
      body: RefreshIndicator(onRefresh: _load, child: _buildBody(context)),
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
    if (_error != null) {
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
    return ListView.separated(
      physics: const AlwaysScrollableScrollPhysics(),
      itemCount: labels.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, i) => _LabelTile(label: labels[i]),
    );
  }
}

class _LabelTile extends StatelessWidget {
  const _LabelTile({required this.label});

  final EventLabel label;

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
      onTap: () => showEventLabelDialog(context, label),
    );
  }
}

/// A color from "#rrggbb", or null if [hex] isn't one.
Color? parseColor(String? hex) {
  if (hex == null) return null;
  final match = RegExp(r'^#([0-9a-fA-F]{6})$').firstMatch(hex.trim());
  if (match == null) return null;
  return Color(0xFF000000 | int.parse(match[1]!, radix: 16));
}
