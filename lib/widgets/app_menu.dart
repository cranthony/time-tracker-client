import 'package:flutter/material.dart';

import '../screens/background_updates_screen.dart';
import '../services/background_refresh.dart';

/// The app bar's menu: Background updates, when the app has them (a
/// [BackgroundRefreshScope] above), About, and Sign out when [onSignOut]
/// is set.
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
    return PopupMenuButton<_MenuItem>(
      onSelected: (item) => switch (item) {
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

enum _MenuItem { updates, about, signOut }
