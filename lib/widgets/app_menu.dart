import 'package:flutter/material.dart';

import '../auth/sign_in_mode.dart';
import '../platform/calendar_widget.dart';
import '../screens/background_updates_screen.dart';
import '../screens/diagnostics_screen.dart';
import '../screens/settings_screen.dart';
import '../services/app_settings.dart';
import '../services/background_refresh.dart';
import '../services/diagnostics_repository.dart';
import 'status_bar.dart';

/// The app bar's menu: Settings, Background updates, Changes waiting to
/// save and Diagnostics, when the app has them (a [BackgroundRefreshScope],
/// a [StatusScope] or a [DiagnosticsScope] above), About, and Sign
/// out when [onSignOut] is set. Builds for the emulator test offer to add
/// the home screen calendar too ([CalendarWidget.pinOffered]).
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
    final status = StatusScope.of(context);
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
        _MenuItem.outbox => status!.show(context),
        _MenuItem.diagnostics => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => DiagnosticsScreen(
              repository: diagnostics!.repository,
              client: diagnostics.client,
            ),
          ),
        ),
        _MenuItem.about => showAboutDialog(
          context: context,
          applicationName: appName,
          applicationVersion: version,
          children: [
            Text('Server: $serverLabel'),
            if (signInOff)
              const Padding(
                padding: EdgeInsets.only(top: 12),
                child: Text(
                  'Sign-in is off in this build (DISABLE_AUTH): it never '
                  'signs in and sends the server no token, trusting the '
                  'network in front of the server to sign people in.',
                ),
              ),
          ],
        ),
        _MenuItem.signOut => onSignOut!(),
        _MenuItem.pinCalendar => CalendarWidget.pin(),
      },
      itemBuilder: (_) => [
        const PopupMenuItem(value: _MenuItem.settings, child: Text('Settings')),
        if (refresh != null)
          const PopupMenuItem(
            value: _MenuItem.updates,
            child: Text('Background updates'),
          ),
        if (status != null && status.sources.isNotEmpty)
          PopupMenuItem(
            value: _MenuItem.outbox,
            child: Text(switch (status.count) {
              0 => 'Changes waiting to save',
              final n => 'Changes waiting to save ($n)',
            }),
          ),
        if (diagnostics != null)
          const PopupMenuItem(
            value: _MenuItem.diagnostics,
            child: Text('Diagnostics'),
          ),
        if (CalendarWidget.pinOffered)
          const PopupMenuItem(
            value: _MenuItem.pinCalendar,
            child: Text('Add calendar to home screen'),
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

enum _MenuItem {
  settings,
  updates,
  outbox,
  diagnostics,
  pinCalendar,
  about,
  signOut,
}
