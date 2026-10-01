import 'package:flutter/material.dart';

/// The app bar's menu: About, and Sign out when [onSignOut] is set.
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
    return PopupMenuButton<_MenuItem>(
      onSelected: (item) => switch (item) {
        _MenuItem.about => showAboutDialog(
          context: context,
          applicationName: 'Time Tracker',
          applicationVersion: version,
          children: [Text('Server: $serverLabel')],
        ),
        _MenuItem.signOut => onSignOut!(),
      },
      itemBuilder: (_) => [
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

enum _MenuItem { about, signOut }
