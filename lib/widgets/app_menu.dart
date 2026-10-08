import 'package:flutter/material.dart';

import '../screens/background_updates_screen.dart';
import '../screens/settings_screen.dart';
import '../services/app_settings.dart';
import '../services/background_refresh.dart';

/// The app bar's menu: Settings, Background updates, when the app has
/// them (a [BackgroundRefreshScope] above), About, and Sign out when
/// [onSignOut] is set.
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

enum _MenuItem { settings, updates, about, signOut }
