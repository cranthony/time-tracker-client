import 'package:flutter/material.dart';

import '../screens/background_updates_screen.dart';
import '../screens/diagnostics_screen.dart';
import '../screens/settings_screen.dart';
import '../services/app_settings.dart';
import '../services/background_refresh.dart';
import '../services/diagnostics_repository.dart';
import 'event_outbox_bar.dart';

/// The app bar's menu: Settings, Background updates, Changes waiting to
/// save and Diagnostics, when the app has them (a [BackgroundRefreshScope],
/// an [EventOutboxScope] or a [DiagnosticsScope] above), About, and Sign
/// out when [onSignOut] is set.
class AppMenu extends StatelessWidget {
  const AppMenu({
    super.key,
    required this.serverLabel,
    this.version,
    this.onSignOut,
  });

  /// Which server this build talks to, or that it's the offline demo.
  final String serverLabel;

  /// The app's version; null until it's known.
  final String? version;
  final VoidCallback? onSignOut;

  @override
  Widget build(BuildContext context) {
    final refresh = BackgroundRefresh.of(context);
    final outbox = EventOutboxScope.of(context);
    final diagnostics = DiagnosticsScope.of(context);
    final settings = AppSettings.of(context);
    return PopupMenuButton<_MenuItem>(
      onSelected: (item) => switch (item) {
        _MenuItem.settings => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => SettingsScreen(settings: settings),
          ),
        ),
        _MenuItem.updates => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => BackgroundUpdatesScreen(refresh: refresh!),
          ),
        ),
        _MenuItem.outbox => outbox!.show(context),
        _MenuItem.diagnostics => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => DiagnosticsScreen(repository: diagnostics!),
          ),
        ),
        _MenuItem.about => showAboutDialog(
          context: context,
          applicationName: 'Time Tracker',
          applicationVersion: version,
          children: [Text('Server: $serverLabel')],
        ),
        _MenuItem.signOut => onSignOut!(),
      },
      itemBuilder: (_) => [
        const PopupMenuItem(value: _MenuItem.settings, child: Text('Settings')),
        if (refresh != null)
          const PopupMenuItem(
            value: _MenuItem.updates,
            child: Text('Background updates'),
          ),
        if (outbox != null)
          PopupMenuItem(
            value: _MenuItem.outbox,
            child: Text(switch (outbox.outbox.pending.length) {
              0 => 'Changes waiting to save',
              final n => 'Changes waiting to save ($n)',
            }),
          ),
        if (diagnostics != null)
          const PopupMenuItem(
            value: _MenuItem.diagnostics,
            child: Text('Diagnostics'),
          ),
        const PopupMenuItem(value: _MenuItem.about, child: Text('About')),
        if (onSignOut != null)
          const PopupMenuItem(
            value: _MenuItem.signOut,
            child: Text('Sign out'),
          ),
      ],
    );
  }
}

enum _MenuItem { settings, updates, outbox, diagnostics, about, signOut }
